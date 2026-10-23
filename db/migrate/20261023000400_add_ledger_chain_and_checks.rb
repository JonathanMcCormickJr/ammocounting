# Database backstops for guarantees the Ruby services already give (audit L2, L8).
# Must run after the running-totals backfill (20261023000300): the backfill writes
# totals through update_columns and relies on the columns existing, and this
# migration then makes them mandatory, chained and constrained.
#
#  * the running-total columns and trades.quantity_after lose `default: 0`: a
#    writer that forgets them now fails instead of silently restarting the chain;
#  * ledger_transactions.previous_id links each row to the user's previous row.
#    A unique index on it (plus a partial unique index for the first row) makes
#    a forked chain impossible even for writers that bypass Ledger::Poster; the
#    composite foreign key keeps the link inside one user's ledger. (This is the
#    chain guard of audit L2, as a linked list instead of a counter: a counter
#    would need Ruby arithmetic in app/ for no extra protection.)
#  * trades get a composite foreign key so a trade's user is its ledger
#    transaction's user;
#  * CHECKs: Cash and Holdings never go negative (debits >= credits), and total
#    debits = total credits (sums over the stored cumulative columns, evaluated
#    by SQLite as a constraint, never by application code);
#  * prices are positive and OHLC buckets are ordered (low <= open/close <= high).
class AddLedgerChainAndChecks < ActiveRecord::Migration[8.1]
  KINDS = %w[deposit buy sell revalue].freeze
  ACCOUNTS = %w[cash holdings capital gain costs].freeze

  def change
    drop_totals_defaults
    add_chain
    add_totals_checks
    add_price_checks
  end

  private

  def total_of(side, accounts = ACCOUNTS)
    KINDS.product(accounts).map { |kind, account| "#{kind}_#{account}_#{side}" }.join(" + ")
  end

  def drop_totals_defaults
    KINDS.product(ACCOUNTS, %w[debits credits]).each do |kind, account, side|
      change_column_default :ledger_transactions, "#{kind}_#{account}_#{side}", from: 0, to: nil
    end
    change_column_default :trades, :quantity_after, from: 0, to: nil
  end

  def add_chain
    add_column :ledger_transactions, :previous_id, :bigint
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE ledger_transactions SET previous_id = (
            SELECT p.id FROM ledger_transactions p
            WHERE p.user_id = ledger_transactions.user_id
              AND (p.occurred_at < ledger_transactions.occurred_at
                OR (p.occurred_at = ledger_transactions.occurred_at AND p.id < ledger_transactions.id))
            ORDER BY p.occurred_at DESC, p.id DESC LIMIT 1)
        SQL
      end
    end
    add_index :ledger_transactions, :previous_id, unique: true, name: "index_ledger_transactions_on_previous_id"
    add_index :ledger_transactions, :user_id, unique: true, where: "previous_id IS NULL",
      name: "index_ledger_transactions_one_first_row_per_user"
    add_index :ledger_transactions, %i[id user_id], unique: true, name: "index_ledger_transactions_on_id_and_user_id"
    add_foreign_key :ledger_transactions, :ledger_transactions, column: %i[previous_id user_id], primary_key: %i[id user_id],
      name: "fk_ledger_transactions_previous_same_user"
    add_foreign_key :trades, :ledger_transactions, column: %i[ledger_transaction_id user_id], primary_key: %i[id user_id],
      name: "fk_trades_ledger_transaction_same_user"
  end

  def add_totals_checks
    add_check_constraint :ledger_transactions, "(#{total_of('debits', %w[cash])}) >= (#{total_of('credits', %w[cash])})",
      name: "ledger_transactions_cash_not_negative"
    add_check_constraint :ledger_transactions, "(#{total_of('debits', %w[holdings])}) >= (#{total_of('credits', %w[holdings])})",
      name: "ledger_transactions_holdings_not_negative"
    add_check_constraint :ledger_transactions, "(#{total_of('debits')}) = (#{total_of('credits')})",
      name: "ledger_transactions_debits_equal_credits"
  end

  def add_price_checks
    remove_check_constraint :trades, "price_centicents BETWEEN 0 AND 10000000", name: "trades_price_check"
    add_check_constraint :trades, "price_centicents BETWEEN 1 AND 10000000", name: "trades_price_check"
    add_check_constraint :price_ticks, "price_centicents > 0", name: "price_ticks_price_check"
    add_check_constraint :price_buckets,
      "low_centicents > 0 AND low_centicents <= open_centicents AND open_centicents <= high_centicents " \
      "AND low_centicents <= close_centicents AND close_centicents <= high_centicents",
      name: "price_buckets_ohlc_check"
  end
end
