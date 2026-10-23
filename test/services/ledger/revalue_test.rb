require "test_helper"

module Ledger
  class RevalueTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      fund(@user)
      Buy.call(@user, calibers(:nine_mm), 1000, at: Time.utc(2026, 1, 1, 12)) # holdings carried at 25_500
    end

    def tick(caliber, price, minute)
      PriceTick.create!(caliber: caliber, price_centicents: price, as_of: Time.utc(2026, 1, 1, 1, minute))
    end

    test "reads the latest prices inside the user's lock, never before it" do
      events = []
      real_prices = Ledger.method(:latest_prices)
      with_singleton(@user, :with_lock, ->(&block) { events << :lock; block.call }) do
        with_singleton(Ledger, :latest_prices, -> { events << :prices; real_prices.call }) do
          Revalue.call(@user)
        end
      end
      assert_equal [ :lock, :prices ], events
    end

    test "all_holders takes prices per user, inside each user's lock" do
      fund(users(:two))
      Buy.call(users(:two), calibers(:nine_mm), 10)
      reads = 0
      real_prices = Ledger.method(:latest_prices)
      with_singleton(Ledger, :latest_prices, -> { reads += 1; real_prices.call }) do
        Revalue.all_holders
      end
      assert_equal 2, reads
    end

    test "posts nothing when carrying value equals market value" do
      assert_no_difference "LedgerTransaction.count" do
        assert_nil Revalue.call(@user)
      end
    end

    test "posts nothing for a user without holdings" do
      assert_nil Revalue.call(users(:two))
    end

    test "a price rise debits holdings and credits trading gain" do
      tick(calibers(:nine_mm), 2600, 0) # market 26_000, carrying 25_500
      tx = Revalue.call(@user)
      assert_equal "revalue", tx.kind
      assert_equal [ [ 2, 0, 500 ], [ 4, 1, 500 ] ], tx.postings.order(:id).pluck(:account, :side, :amount_cents)
      assert_equal 26_000, Balances.sheet(@user).holdings
    end

    test "a price fall credits holdings and debits trading gain" do
      tick(calibers(:nine_mm), 2500, 0) # market 25_000
      tx = Revalue.call(@user)
      assert_equal [ [ 4, 0, 500 ], [ 2, 1, 500 ] ], tx.postings.order(:id).pluck(:account, :side, :amount_cents)
      assert_equal 25_000, Balances.sheet(@user).holdings
    end

    test "is idempotent" do
      tick(calibers(:nine_mm), 2600, 0)
      assert Revalue.call(@user)
      assert_no_difference "LedgerTransaction.count" do
        assert_nil Revalue.call(@user)
      end
    end

    test "explicit prices override the latest ticks" do
      tx = Revalue.call(@user, prices: { calibers(:nine_mm).id => 3000 }, at: Time.utc(2026, 3, 3))
      assert_equal Time.utc(2026, 3, 3), tx.occurred_at
      assert_equal 30_000, Balances.sheet(@user).holdings
    end

    test "values every held caliber with the engine and sums them" do
      Buy.call(@user, calibers(:twenty_two), 700) # 7_000 at 1000
      tick(calibers(:nine_mm), 2600, 0)
      tick(calibers(:twenty_two), 1100, 0)
      Revalue.call(@user)
      assert_equal 26_000 + 7_700, Balances.sheet(@user).holdings
    end

    test "all_holders revalues only users with rounds, returning the transactions" do
      fund(users(:two))
      tick(calibers(:nine_mm), 2600, 0)
      txs = Revalue.all_holders
      assert_equal [ @user.id ], txs.map(&:user_id)
      assert_empty Revalue.all_holders
    end

    test "all_holders posts at the given time" do
      tick(calibers(:nine_mm), 2600, 0)
      at = Time.utc(2026, 5, 5)
      assert_equal [ at ], Revalue.all_holders(at: at).map(&:occurred_at)
    end

    test "all_holders logs a failing user, carries on, then raises RevalueFailed so the failure is observable" do
      other = users(:two)
      fund(other)
      Buy.call(other, calibers(:nine_mm), 10)
      tick(calibers(:nine_mm), 2600, 0)
      messages = []
      logger = Object.new
      logger.define_singleton_method(:error) { |message| messages << message }
      original = Revalue.method(:call)
      failing_id = @user.id
      failing = ->(user, **opts) { user.id == failing_id ? raise("boom") : original.call(user, **opts) }
      error = with_singleton(Revalue, :call, failing) do
        assert_raises(RevalueFailed) { Revalue.all_holders(logger: logger) }
      end
      assert_equal [ other.id ], error.transactions.map(&:user_id), "the other user was still revalued"
      assert_equal [ failing_id ], error.failures.keys
      assert_equal "boom", error.failures[failing_id].message
      assert_includes error.message, "user(s) #{failing_id}"
      assert_includes error.message, "boom"
      assert_equal 1, messages.size
      assert_includes messages.first, "user #{@user.id}"
      assert_includes messages.first, "boom"
    end

    test "all_holders logs engine errors to Rails.logger by default" do
      tick(calibers(:nine_mm), 2600, 0)
      lines = []
      sink = Object.new
      sink.define_singleton_method(:error) { |message| lines << message }
      failing = ->(*) { raise LedgerEngine::Error.new(:out_of_range, :revalue) }
      with_singleton(Rails, :logger, -> { sink }) do
        with_singleton(LedgerEngine, :revalue, failing) do
          error = assert_raises(RevalueFailed) { Revalue.all_holders }
          assert_equal :out_of_range, error.failures.fetch(@user.id).status
        end
      end
      assert_equal 1, lines.size
      assert_includes lines.first, "out_of_range"
    end

    test "failure inside a user's revaluation rolls back that user's writes" do
      tick(calibers(:nine_mm), 2600, 0)
      with_singleton(Poster, :call, ->(*, **) { raise "no" }) do
        assert_raises(RuntimeError) { Revalue.call(@user) }
      end
      assert_equal 25_500, Balances.sheet(@user).holdings
    end

    test "locks the user" do
      locked = false
      with_singleton(@user, :with_lock, ->(&block) { locked = true; block.call }) { Revalue.call(@user) }
      assert locked
    end
  end
end
