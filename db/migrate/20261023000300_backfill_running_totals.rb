# Data migration: replays each user's existing ledger through the engine to fill
# the running totals (and each caliber's trades to fill quantity_after). A no-op
# on an empty database. Fails loudly if the engine refuses any historic row.
# Uses local (writable) models: the app's ledger models are append-only.
#
# DEPENDS ON LIVE CODE: it calls the current LedgerEngine (the shipped SPARK
# library), not a frozen copy. A future engine change in apply_transaction or
# apply_trade_quantity changes what a replay produces; run this migration only
# against a library whose semantics for historic rows are unchanged (audit L12).
# After replaying, it asserts that each user's final totals equal what SQL sums
# of that user's postings give (and each caliber's quantity_after equals bought
# minus sold), and raises if not. The newer migrations (chain, CHECKs, triggers)
# run after this one, so on an upgrade the rows are rewritten before they are guarded.
class BackfillRunningTotals < ActiveRecord::Migration[8.1]
  class Tx < ActiveRecord::Base
    self.table_name = "ledger_transactions"
  end

  class Entry < ActiveRecord::Base
    self.table_name = "ledger_postings"
  end

  class TradeRow < ActiveRecord::Base
    self.table_name = "trades"
  end

  COLUMNS = %w[deposit buy sell revalue].product(%w[cash holdings capital gain costs], %w[debits credits])
    .map { |kind, account, side| "#{kind}_#{account}_#{side}" }.freeze

  def up
    Tx.distinct.pluck(:user_id).each { |user_id| replay_ledger(user_id) }
    TradeRow.distinct.pluck(:user_id, :caliber_id).each { |user_id, caliber_id| replay_quantities(user_id, caliber_id) }
    Tx.distinct.pluck(:user_id).each { |user_id| verify_ledger(user_id) }
    TradeRow.distinct.pluck(:user_id, :caliber_id).each { |user_id, caliber_id| verify_quantities(user_id, caliber_id) }
  end

  def down
    # Nothing to undo: the columns are dropped by the previous migration's rollback.
  end

  private

  def replay_ledger(user_id)
    totals = LedgerEngine::ZERO_TOTALS
    Tx.where(user_id: user_id).order(:occurred_at, :id).each do |row|
      postings = Entry.where(ledger_transaction_id: row.id).order(:id).pluck(:account, :side, :amount_cents)
      kind = LedgerEngine::KINDS.key(row.kind) || raise(ArgumentError, "ledger transaction #{row.id} has unknown kind #{row.kind.inspect}")
      totals = LedgerEngine.apply_transaction(kind, postings, totals)
      row.update_columns(COLUMNS.zip(totals).to_h)
    end
  end

  # Independent check of the replay: the last row's totals, collapsed over kinds by
  # the engine, must equal the per-account sums of the user's postings.
  def verify_ledger(user_id)
    last = Tx.where(user_id: user_id).order(:occurred_at, :id).last
    postings = Entry.joins("INNER JOIN ledger_transactions t ON t.id = ledger_postings.ledger_transaction_id")
      .where("t.user_id = ?", user_id)
    expected = (1..5).map do |account|
      [ 0, 1 ].map { |side| LedgerEngine.sum(postings.where(account: account, side: side).pluck(:amount_cents)) }
    end
    actual = LedgerEngine.collapse_kinds(COLUMNS.map { last[_1] })
    raise "Backfill verification failed for user #{user_id}: totals #{actual.inspect} != posting sums #{expected.inspect}" unless actual == expected
  end

  def verify_quantities(user_id, caliber_id)
    trades = TradeRow.where(user_id: user_id, caliber_id: caliber_id)
    last = trades.order(:occurred_at, :id).last
    bought = LedgerEngine.sum(trades.where(side: 0).pluck(:quantity))
    sold_and_held = LedgerEngine.sum([ *trades.where(side: 1).pluck(:quantity), last.quantity_after ])
    raise "Backfill verification failed for user #{user_id} caliber #{caliber_id}: quantity_after #{last.quantity_after} but bought #{bought} != sold + held #{sold_and_held}" unless bought == sold_and_held
  end

  def replay_quantities(user_id, caliber_id)
    held = 0
    TradeRow.where(user_id: user_id, caliber_id: caliber_id).order(:occurred_at, :id).each do |row|
      held = LedgerEngine.apply_trade_quantity(held, row.side, row.quantity)
      row.update_columns(quantity_after: held)
    end
  end
end
