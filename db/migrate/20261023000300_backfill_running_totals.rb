# Data migration: replays each user's existing ledger through the engine to fill
# the running totals (and each caliber's trades to fill quantity_after). A no-op
# on an empty database. Fails loudly if the engine refuses any historic row.
# Uses local (writable) models: the app's ledger models are append-only.
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
  end

  def down
    # Nothing to undo: the columns are dropped by the previous migration's rollback.
  end

  private

  def replay_ledger(user_id)
    totals = LedgerEngine::ZERO_TOTALS
    Tx.where(user_id: user_id).order(:occurred_at, :id).each do |row|
      postings = Entry.where(ledger_transaction_id: row.id).order(:id).pluck(:account, :side, :amount_cents)
      totals = LedgerEngine.apply_transaction(row.kind, postings, totals)
      row.update_columns(COLUMNS.zip(totals).to_h)
    end
  end

  def replay_quantities(user_id, caliber_id)
    held = 0
    TradeRow.where(user_id: user_id, caliber_id: caliber_id).order(:occurred_at, :id).each do |row|
      held = LedgerEngine.apply_trade_quantity(held, row.side, row.quantity)
      row.update_columns(quantity_after: held)
    end
  end
end
