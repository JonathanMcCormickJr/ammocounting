require "test_helper"

# Audit L2, L3, L8: the guarantees must hold in the database, not only in Ruby.
# These tests go around the models on purpose (raw SQL, update_all, insert_all).
class LedgerDatabaseGuardsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    fund(@user)
    Ledger::Buy.call(@user, calibers(:nine_mm), 100)
    @transaction = LedgerTransaction.where(user: @user).order(:id).last
    @trade = Trade.last
    @posting = @transaction.postings.first
    @connection = ActiveRecord::Base.connection
  end

  def refused(&block)
    assert_raises(ActiveRecord::StatementInvalid, ActiveRecord::InvalidForeignKey, ActiveRecord::NotNullViolation, &block)
  end

  def row(table, id)
    @connection.select_one("SELECT * FROM #{table} WHERE id = #{id}")
  end

  # A copy of an existing ledger row, with overrides, inserted with raw SQL.
  def insert_copy(table, source, **overrides)
    attributes = source.attributes.except("id").merge(overrides.transform_keys(&:to_s))
    @connection.execute("INSERT INTO #{table} (#{attributes.keys.join(', ')}) VALUES (#{attributes.values.map { @connection.quote(_1) }.join(', ')})")
  end

  # --- L3: append-only triggers --------------------------------------------

  test "ledger transactions, postings and trades cannot be updated by update_all or SQL" do
    error = refused { LedgerTransaction.where(id: @transaction.id).update_all(description: "tampered") }
    assert_match(/append-only/, error.message)
    refused { LedgerPosting.where(id: @posting.id).update_all(amount_cents: 1) }
    refused { Trade.where(id: @trade.id).update_all(quantity: 1) }
    refused { @connection.execute("UPDATE ledger_transactions SET buy_cash_credits = 0") }
  end

  test "ledger transactions, postings and trades cannot be deleted by delete_all or SQL" do
    error = refused { Trade.delete_all }
    assert_match(/append-only/, error.message)
    refused { LedgerPosting.delete_all }
    refused { LedgerTransaction.delete_all }
    refused { @connection.execute("DELETE FROM ledger_postings") }
    assert_equal 1, Trade.count
  end

  test "raw price ticks cannot be updated" do
    error = refused { PriceTick.update_all(price_centicents: 1) }
    assert_match(/append-only/, error.message)
  end

  test "the triggers are the only thing stopping a bypass (helper removes and restores them)" do
    without_ledger_triggers { LedgerPosting.where(id: @posting.id).update_all(amount_cents: 2) }
    assert_equal 2, @posting.reload.amount_cents
    refused { LedgerPosting.where(id: @posting.id).update_all(amount_cents: 3) }
  end

  # --- L2: defaults, chain, CHECKs, consistency ------------------------------

  test "running-total columns and quantity_after have no default" do
    defaults = LedgerTransaction::TOTALS_COLUMNS.map { LedgerTransaction.columns_hash.fetch(_1).default }
    assert_equal [ nil ], defaults.uniq
    assert_nil Trade.columns_hash.fetch("quantity_after").default
  end

  test "a ledger insert that omits the running totals is refused" do
    refused do
      @connection.execute("INSERT INTO ledger_transactions (user_id, kind, occurred_at, created_at, updated_at) " \
                          "VALUES (#{@user.id}, 0, '2030-01-01', '2030-01-01', '2030-01-01')")
    end
  end

  test "each ledger row records the user's previous row, forming one chain" do
    Ledger::Deposit.call(@user, 100)
    rows = LedgerTransaction.where(user: @user).order(:occurred_at, :id).to_a
    assert_operator rows.size, :>=, 3
    assert_nil rows.first.previous_id
    assert_equal rows.first(rows.size - 1).map(&:id), rows.drop(1).map(&:previous_id)
  end

  test "the chain cannot fork: a second successor or a second first row is refused" do
    refused { insert_copy("ledger_transactions", @transaction) } # same previous_id as the existing row
    first = LedgerTransaction.where(user: @user).order(:id).first
    refused { insert_copy("ledger_transactions", first) } # a second row with no previous
  end

  test "a row cannot point at another user's row as its previous" do
    other = users(:two)
    fund(other)
    other_row = LedgerTransaction.where(user: other).first
    refused { insert_copy("ledger_transactions", @transaction, previous_id: other_row.id, occurred_at: Time.utc(2031, 1, 1)) }
  end

  test "totals that would make cash negative, holdings negative or the books unbalanced are refused" do
    next_row = ->(**changes) { insert_copy("ledger_transactions", @transaction, previous_id: @transaction.id, occurred_at: Time.utc(2031, 1, 1), **changes) }
    refused { next_row.call(buy_cash_credits: @transaction.buy_cash_credits + 10**9) } # cash overdrawn, unbalanced
    refused { next_row.call(buy_holdings_credits: @transaction.buy_holdings_debits + 1, buy_cash_debits: @transaction.buy_cash_debits + 1) } # holdings negative
    refused { next_row.call(deposit_capital_credits: @transaction.deposit_capital_credits + 1) } # debits != credits
  end

  test "a trade must belong to the user of its ledger transaction" do
    other = users(:two)
    refused { insert_copy("trades", @trade, user_id: other.id, ledger_transaction_id: @trade.ledger_transaction_id) }
  end

  # --- L8: price CHECKs ------------------------------------------------------

  test "zero prices are refused on ticks and trades" do
    refused { insert_copy("price_ticks", PriceTick.first, as_of: Time.utc(2031, 1, 1), price_centicents: 0) }
    refused { insert_copy("trades", @trade, price_centicents: 0) }
  end

  test "OHLC buckets must be positive and ordered" do
    good = { caliber_id: calibers(:nine_mm).id, resolution: "hourly", bucket_start: Time.utc(2031, 1, 1), open_centicents: 5, high_centicents: 9,
             low_centicents: 2, close_centicents: 6, tick_count: 3, last_as_of: Time.utc(2031, 1, 1, 0, 50) }
    assert_nothing_raised { PriceBucket.insert!(good) }
    refused { PriceBucket.insert!(good.merge(bucket_start: Time.utc(2031, 1, 2), low_centicents: 0)) }
    refused { PriceBucket.insert!(good.merge(bucket_start: Time.utc(2031, 1, 3), open_centicents: 10)) } # open > high
    refused { PriceBucket.insert!(good.merge(bucket_start: Time.utc(2031, 1, 4), close_centicents: 1)) } # close < low
  end
end
