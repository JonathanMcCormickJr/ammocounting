# Double-entry ledger tables. Rows are append-only (enforced in the models);
# CHECK constraints mirror the engine's documented bounds (ledger_core/ABI.md).
class CreateLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :ledger_transactions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.integer :kind, null: false
      t.datetime :occurred_at, null: false
      t.string :description
      t.timestamps
      t.check_constraint "kind BETWEEN 0 AND 3", name: "ledger_transactions_kind_check"
    end
    add_index :ledger_transactions, %i[user_id occurred_at]

    create_table :ledger_postings do |t|
      t.references :ledger_transaction, null: false, foreign_key: true, index: false
      t.integer :account, null: false
      t.integer :side, null: false
      t.bigint :amount_cents, null: false
      t.timestamps
      t.check_constraint "account BETWEEN 1 AND 5", name: "ledger_postings_account_check"
      t.check_constraint "side IN (0, 1)", name: "ledger_postings_side_check"
      t.check_constraint "amount_cents BETWEEN 1 AND 1000000000000", name: "ledger_postings_amount_check"
    end
    add_index :ledger_postings, %i[ledger_transaction_id account side]

    create_table :trades do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :caliber, null: false, foreign_key: true
      t.integer :side, null: false
      t.bigint :quantity, null: false
      t.bigint :price_centicents, null: false
      t.bigint :value_cents, null: false
      t.bigint :spread_cents, null: false
      t.bigint :fee_cents, null: false
      t.references :ledger_transaction, null: false, foreign_key: true, index: { unique: true }
      t.datetime :occurred_at, null: false
      t.timestamps
      t.check_constraint "side IN (0, 1)", name: "trades_side_check"
      t.check_constraint "quantity BETWEEN 1 AND 1000000000", name: "trades_quantity_check"
      t.check_constraint "price_centicents BETWEEN 0 AND 10000000", name: "trades_price_check"
      t.check_constraint "value_cents BETWEEN 0 AND 1000000000000", name: "trades_value_check"
      t.check_constraint "spread_cents >= 0 AND fee_cents >= 0", name: "trades_costs_check"
    end
    add_index :trades, %i[user_id occurred_at id]
    add_index :trades, %i[user_id caliber_id]
  end
end
