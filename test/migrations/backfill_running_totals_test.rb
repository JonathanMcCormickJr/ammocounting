require "test_helper"
require Rails.root.join("db/migrate/20261023000300_backfill_running_totals")

# The data migration that fills running totals and quantity_after for rows
# written before those columns existed.
class BackfillRunningTotalsTest < ActiveSupport::TestCase
  def run_migration
    ActiveRecord::Migration.suppress_messages { BackfillRunningTotals.new.up }
  end

  def wipe_totals
    LedgerTransaction.update_all(LedgerTransaction::TOTALS_COLUMNS.index_with { 0 }) # bypasses append-only models on purpose
    Trade.update_all(quantity_after: 0)
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
    LedgerPosting.where(ledger_transaction_id: LedgerTransaction.last.id, side: 1).update_all(amount_cents: 2) # credits != debits
    assert_raises(LedgerEngine::Error) { run_migration }
  end

  test "down is a no-op" do
    assert_nothing_raised { ActiveRecord::Migration.suppress_messages { BackfillRunningTotals.new.down } }
  end
end
