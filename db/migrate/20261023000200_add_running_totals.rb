# Running totals (ledger_core/ABI.md): every ledger transaction stores the
# cumulative debits and credits of its user's whole ledger, per kind x account,
# including itself (40 numbers, Totals index order: cell = kind * 5 + account - 1,
# debits then credits). Every trade stores the units held of its caliber after it.
# Existing rows are backfilled by the next migration. The engine, not SQL, does
# all the arithmetic on these numbers.
class AddRunningTotals < ActiveRecord::Migration[8.1]
  KINDS = %w[deposit buy sell revalue].freeze
  ACCOUNTS = %w[cash holdings capital gain costs].freeze
  SIDES = %w[debits credits].freeze

  def change
    KINDS.product(ACCOUNTS, SIDES).each do |kind, account, side|
      add_column :ledger_transactions, "#{kind}_#{account}_#{side}", :bigint, null: false, default: 0
    end

    add_column :trades, :quantity_after, :bigint, null: false, default: 0
    add_check_constraint :trades, "quantity_after BETWEEN 0 AND 1000000000", name: "trades_quantity_after_check"

    # Latest ledger row at or before T per user (ties by id).
    remove_index :ledger_transactions, %i[user_id occurred_at]
    add_index :ledger_transactions, %i[user_id occurred_at id]
    # Latest trade per user + caliber (ties by id); also the cost_basis replay order.
    remove_index :trades, %i[user_id caliber_id]
    add_index :trades, %i[user_id caliber_id occurred_at id]
  end
end
