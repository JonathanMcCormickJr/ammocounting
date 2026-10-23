require "test_helper"

# Real concurrency: separate threads, each with its own SQLite connection and no
# wrapping test transaction. Proves the per-user lock (BEGIN IMMEDIATE on SQLite;
# FOR UPDATE is ignored there) serialises read-quote-post-record so a user can
# neither overspend nor hit a database-busy 500.
class ConcurrentTradesTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = users(:one)
    @caliber = calibers(:nine_mm)
  end

  teardown do
    without_ledger_triggers do
      Trade.delete_all
      LedgerPosting.delete_all
      LedgerTransaction.delete_all
    end
  end

  def in_threads(count)
    gate = Queue.new
    threads = Array.new(count) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          yield i
        rescue StandardError => e
          e
        end
      end
    end
    count.times { gate << :go }
    threads.map(&:value)
  end

  test "Rails 8.1 opens write transactions with BEGIN IMMEDIATE so with_lock really serialises on SQLite" do
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] if payload[:name] == "TRANSACTION" }
    User.find(@user.id).with_lock { }
    assert_includes statements.map(&:upcase), "BEGIN IMMEDIATE TRANSACTION"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "two simultaneous buys that together exceed cash: exactly one succeeds, the other is refused, no overspend" do
    fund(@user, 30_000)
    quantity = 800 # about $207 with costs: one fits in $300, two do not
    results = in_threads(2) { Ledger::Buy.call(User.find(@user.id), Caliber.find(@caliber.id), quantity) }

    trades, errors = results.partition { _1.is_a?(Trade) }
    assert_equal 1, trades.size, results.inspect
    assert_equal [ Ledger::Refused ], errors.map(&:class), results.inspect
    assert_equal "Not enough cash for this purchase.", errors.first.message
    assert_equal 1, @user.trades.count
    assert_operator Ledger::Balances.sheet(@user).cash, :>=, 0
    assert LedgerEngine.audit_chain(@user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
  end

  test "two simultaneous submissions of the same form (same nonce) execute once and the other is a replay" do
    fund(@user, 1_000_000)
    nonce = Ledger.new_nonce
    results = in_threads(2) { Ledger::Buy.call(User.find(@user.id), Caliber.find(@caliber.id), 10, nonce: nonce) }
    assert_equal [ Ledger::Replay, Trade ], results.map(&:class).sort_by(&:name), results.inspect
    assert_equal 1, @user.trades.count
    assert_equal 10, Ledger::Balances.quantities(@user).fetch(@caliber.id)
  end

  test "two simultaneous tick runs for the same instant store each caliber's tick once, without errors" do
    now = Time.utc(2031, 1, 1, 0, 7)
    results = in_threads(2) { TickRunner.call(now: now) }
    assert_equal [ Array ], results.map(&:class).uniq, results.inspect
    assert_equal [ 0, 2 ], results.map(&:size).sort
    assert_equal 2, PriceTick.where(as_of: PriceTick.floor_time(now)).count
  ensure
    PriceTick.where(as_of: Time.utc(2031, 1, 1)..).delete_all
  end

  test "many concurrent small buys all succeed without errors and keep the chain intact" do
    fund(@user, 1_000_000)
    results = in_threads(4) { Ledger::Buy.call(User.find(@user.id), Caliber.find(@caliber.id), 10) }
    assert_equal [ Trade ], results.map(&:class).uniq, results.inspect
    assert_equal 4, @user.trades.count
    assert_equal 40, Ledger::Balances.quantities(@user).fetch(@caliber.id)
    assert LedgerEngine.audit_chain(@user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
  end
end
