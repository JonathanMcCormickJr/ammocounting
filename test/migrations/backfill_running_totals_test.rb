require "test_helper"
require Rails.root.join("db/migrate/20261023000300_backfill_running_totals")

# The data migration that fills running totals and quantity_after for rows
# written before those columns existed.
class BackfillRunningTotalsTest < ActiveSupport::TestCase
  def run_migration
    without_ledger_triggers do # the migration predates the append-only triggers and rewrites rows
      ActiveRecord::Migration.suppress_messages { BackfillRunningTotals.new.up }
    end
  end

  def wipe_totals
    without_ledger_triggers do
      LedgerTransaction.update_all(LedgerTransaction::TOTALS_COLUMNS.index_with { 0 }) # bypasses append-only models on purpose
      Trade.update_all(quantity_after: 0)
    end
  end

  test "replaying through the engine restores exactly the totals and holdings the services wrote" do
    ScriptedHistory.build(users(:one), calibers(:nine_mm))
    fund(users(:two), 50_000)
    Ledger::Buy.call(users(:two), calibers(:twenty_two), 30)
    Ledger::Buy.call(users(:two), calibers(:nine_mm), 20)
    Ledger::Sell.call(users(:two), calibers(:twenty_two), 10)

    expected_totals = LedgerTransaction.order(:id).map { [ _1.id, _1.totals ] }
    expected_quantities = Trade.order(:id).map { [ _1.id, _1.quantity_after ] }
    assert_operator expected_totals.size, :>, 8
    wipe_totals
    assert_equal [ LedgerEngine::ZERO_TOTALS ], LedgerTransaction.all.map(&:totals).uniq

    run_migration

    assert_equal expected_totals, LedgerTransaction.order(:id).map { [ _1.id, _1.totals ] }
    assert_equal expected_quantities, Trade.order(:id).map { [ _1.id, _1.quantity_after ] }
    assert LedgerEngine.audit_chain(users(:one).ledger_transactions.order(:occurred_at, :id).map(&:totals))
  end

  test "is safe on an empty database and idempotent on a populated one" do
    assert_nothing_raised { run_migration }
    fund(users(:one))
    before = LedgerTransaction.last.totals
    run_migration
    run_migration
    assert_equal before, LedgerTransaction.last.totals
  end

  test "a historic row the engine refuses fails the migration loudly" do
    fund(users(:one))
    without_ledger_triggers { LedgerPosting.where(ledger_transaction_id: LedgerTransaction.last.id, side: 1).update_all(amount_cents: 2) } # credits != debits
    assert_raises(LedgerEngine::Error) { run_migration }
  end

  test "a replay that disagrees with the postings fails the verification loudly" do
    fund(users(:one))
    real = LedgerEngine.method(:apply_transaction)
    corrupt = ->(kind, postings, previous) { real.call(kind, postings, previous).each_with_index.map { |v, i| [ 0, 5 ].include?(i) ? v + 1 : v } }
    with_singleton(LedgerEngine, :apply_transaction, corrupt) do
      error = assert_raises(RuntimeError) { run_migration }
      assert_includes error.message, "Backfill verification failed for user #{users(:one).id}"
    end
  end

  test "a quantity_after that disagrees with the trades fails the verification loudly" do
    fund(users(:one))
    Ledger::Buy.call(users(:one), calibers(:nine_mm), 10)
    wrong = ->(held, _side, _qty) { held }
    with_singleton(LedgerEngine, :apply_trade_quantity, wrong) do
      error = assert_raises(RuntimeError) { run_migration }
      assert_includes error.message, "quantity_after 0 but bought 10 != sold + held 0"
    end
  end

  test "a historic row with an unknown kind is refused" do
    fund(users(:one))
    connection = ActiveRecord::Base.connection
    without_ledger_triggers do
      connection.execute("PRAGMA ignore_check_constraints = ON") # the CHECK would stop us writing kind 9
      LedgerTransaction.where(id: LedgerTransaction.last.id).update_all(kind: 9)
    ensure
      connection.execute("PRAGMA ignore_check_constraints = OFF")
    end
    error = assert_raises(ArgumentError) { run_migration }
    assert_includes error.message, "unknown kind 9"
  end

  test "down is a no-op" do
    assert_nothing_raised { ActiveRecord::Migration.suppress_messages { BackfillRunningTotals.new.down } }
  end
end
