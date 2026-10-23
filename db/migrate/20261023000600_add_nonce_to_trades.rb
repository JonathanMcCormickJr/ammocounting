# Audit L5: every trade form carries a nonce issued when the form is rendered.
# The nonce is stored on the trade it produced, atomically with it, and
# (user_id, nonce) is unique, so a double-submit or replay can never execute
# twice (the database refuses it even if the application check is bypassed).
# Nullable: trades written by services without a form (and historic trades)
# have none; SQLite treats NULLs as distinct in a unique index.
class AddNonceToTrades < ActiveRecord::Migration[8.1]
  def change
    add_column :trades, :nonce, :string
    add_index :trades, %i[user_id nonce], unique: true, name: "index_trades_on_user_id_and_nonce"
    add_check_constraint :trades, "nonce IS NULL OR length(nonce) BETWEEN 16 AND 64", name: "trades_nonce_check"
  end
end
