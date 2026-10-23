require "test_helper"

class LedgerModelsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @transaction = Ledger::Deposit.call(@user, 5_000)
    @posting = @transaction.postings.first
    @trade = fund_and_buy
  end

  test "persisted ledger transactions, postings and trades are read-only" do
    [ @transaction, @posting, @trade ].each do |record|
      assert_predicate record, :readonly?
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(updated_at: Time.current) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.destroy }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.delete }
    end
    assert_equal 5_000, @posting.reload.amount_cents
  end

  test "new records are writable until saved" do
    assert_not_predicate LedgerTransaction.new, :readonly?
  end

  test "a user with ledger history cannot be deleted" do
    assert_raises(ActiveRecord::InvalidForeignKey) { @user.destroy }
  end

  test "associations" do
    assert_equal @user, @transaction.user
    assert_equal 2, @transaction.postings.count
    assert_equal @trade, @trade.ledger_transaction.trade
    assert_includes @user.ledger_transactions, @transaction
    assert_includes @user.trades, @trade
    assert_equal calibers(:nine_mm), @trade.caliber
  end

  test "LedgerTransaction validates kind and occurred_at" do
    transaction = LedgerTransaction.new(user: @user, kind: :deposit)
    assert_not_predicate transaction, :valid?
    assert_includes transaction.errors.attribute_names, :occurred_at
    assert_predicate LedgerTransaction.new(user: @user, kind: :buy, occurred_at: Time.current), :valid?
    assert_equal({ "deposit" => 0, "buy" => 1, "sell" => 2, "revalue" => 3 }, LedgerTransaction.kinds)
  end

  test "LedgerPosting validations and debit?" do
    base = { ledger_transaction: @transaction }
    assert_predicate LedgerPosting.new(base.merge(account: 1, side: 0, amount_cents: 1)), :valid?
    assert_not_predicate LedgerPosting.new(base.merge(account: 0, side: 0, amount_cents: 1)), :valid?
    assert_not_predicate LedgerPosting.new(base.merge(account: 6, side: 0, amount_cents: 1)), :valid?
    assert_not_predicate LedgerPosting.new(base.merge(account: 1, side: 2, amount_cents: 1)), :valid?
    assert_not_predicate LedgerPosting.new(base.merge(account: 1, side: 0, amount_cents: 0)), :valid?
    assert_not_predicate LedgerPosting.new(base.merge(account: 1, side: 0, amount_cents: 10**12 + 1)), :valid?
    assert_predicate LedgerPosting.new(account: 1, side: 0), :debit?
    assert_not_predicate LedgerPosting.new(account: 1, side: 1), :debit?
  end

  test "Trade validations" do
    attrs = { user: @user, caliber: calibers(:nine_mm), ledger_transaction: @transaction, side: :buy, quantity: 1,
              price_centicents: 1, value_cents: 0, spread_cents: 0, fee_cents: 0, quantity_after: 1, occurred_at: Time.current }
    assert_predicate Trade.new(attrs), :valid?
    assert_predicate Trade.new(attrs.merge(nonce: Ledger.new_nonce)), :valid?
    assert_not_predicate Trade.new(attrs.merge(nonce: "short")), :valid?
    assert_not_predicate Trade.new(attrs.merge(nonce: "G" * 32)), :valid?
    assert_not_predicate Trade.new(attrs.merge(quantity: 0)), :valid?
    assert_not_predicate Trade.new(attrs.merge(quantity: 10**9 + 1)), :valid?
    assert_not_predicate Trade.new(attrs.merge(price_centicents: 0)), :valid?
    assert_not_predicate Trade.new(attrs.merge(value_cents: -1)), :valid?
    assert_not_predicate Trade.new(attrs.merge(occurred_at: nil)), :valid?
  end

  test "database CHECK constraints reject out-of-bounds rows" do
    now = Time.current
    assert_raises(ActiveRecord::CheckViolation) do
      LedgerPosting.insert_all([ { ledger_transaction_id: @transaction.id, account: 6, side: 0, amount_cents: 1, created_at: now, updated_at: now } ])
    end
    assert_raises(ActiveRecord::CheckViolation) do
      LedgerPosting.insert_all([ { ledger_transaction_id: @transaction.id, account: 1, side: 2, amount_cents: 1, created_at: now, updated_at: now } ])
    end
    assert_raises(ActiveRecord::CheckViolation) do
      LedgerPosting.insert_all([ { ledger_transaction_id: @transaction.id, account: 1, side: 0, amount_cents: 0, created_at: now, updated_at: now } ])
    end
    assert_raises(ActiveRecord::CheckViolation) do
      LedgerTransaction.insert_all([ { user_id: @user.id, kind: 4, occurred_at: now, created_at: now, updated_at: now }
        .merge(LedgerTransaction.totals_attributes(LedgerEngine::ZERO_TOTALS)) ])
    end
    row = { user_id: @user.id, caliber_id: calibers(:nine_mm).id, side: 0, quantity: 1, price_centicents: 1, value_cents: 0,
            spread_cents: 0, fee_cents: 0, quantity_after: 1, ledger_transaction_id: @transaction.id, occurred_at: now, created_at: now, updated_at: now }
    [ { side: 2 }, { nonce: "short" }, { price_centicents: 0 }, { quantity: 0 }, { quantity_after: -1 }, { quantity_after: 10**9 + 1 }, { price_centicents: 10**7 + 1 }, { value_cents: -1 }, { fee_cents: -1 } ].each do |bad|
      assert_raises(ActiveRecord::CheckViolation, bad.to_s) { Trade.insert_all([ row.merge(bad) ]) }
    end
  end

  test "database foreign keys are enforced" do
    now = Time.current
    assert_raises(ActiveRecord::InvalidForeignKey) do
      LedgerPosting.insert_all([ { ledger_transaction_id: 0, account: 1, side: 0, amount_cents: 1, created_at: now, updated_at: now } ])
    end
  end

  test "holder_user_ids lists only users holding rounds" do
    assert_equal [ @user.id ], Trade.holder_user_ids
    Ledger::Sell.call(@user, calibers(:nine_mm), 100)
    assert_equal [ @user.id ], Trade.holder_user_ids
    Ledger::Sell.call(@user, calibers(:nine_mm), 900)
    assert_empty Trade.holder_user_ids
  end

  test "engine_rows are time ordered engine-ready rows for the scope" do
    Ledger::Sell.call(@user, calibers(:nine_mm), 100, at: Time.current.floor + 10)
    Ledger::Deposit.call(users(:two), 1000)
    rows = @user.trades.engine_rows
    assert_equal [ [ calibers(:nine_mm).id, 0, 1000, 25_500, @trade.occurred_at.to_i ],
                   [ calibers(:nine_mm).id, 1, 100, 2_550, (@trade.occurred_at + 10).to_i ] ], rows
    assert_empty users(:two).trades.engine_rows
  end

  test "TOTALS_COLUMNS are the 40 running totals in engine order" do
    columns = LedgerTransaction::TOTALS_COLUMNS
    assert_equal 40, columns.size
    assert_equal %w[deposit_cash_debits deposit_cash_credits deposit_holdings_debits deposit_holdings_credits
                    deposit_capital_debits deposit_capital_credits deposit_gain_debits deposit_gain_credits
                    deposit_costs_debits deposit_costs_credits buy_cash_debits], columns.first(11)
    assert_equal %w[revalue_costs_debits revalue_costs_credits], columns.last(2)
    assert_equal columns, LedgerTransaction.column_names & columns, "every column exists"
    LedgerTransaction.columns_hash.values_at(*columns).each do |column|
      assert_equal [ "bigint", false, nil ], [ column.sql_type, column.null, column.default ], column.name
    end
  end

  test "totals reads the running totals and totals_attributes maps them back to columns" do
    assert_equal [ 5_000, 0, 0, 0, 0, 5_000 ] + ([ 0 ] * 34), @transaction.totals
    attributes = LedgerTransaction.totals_attributes(@transaction.totals)
    assert_equal 5_000, attributes["deposit_cash_debits"]
    assert_equal 5_000, attributes["deposit_capital_credits"]
    assert_equal 40, attributes.size
    assert_equal @trade.ledger_transaction.totals, @user.ledger_transactions.order(:id).last.totals
  end

  test "trade quantity_after is validated and constrained" do
    attrs = { user: @user, caliber: calibers(:nine_mm), ledger_transaction: @transaction, side: :buy, quantity: 1,
              price_centicents: 1, value_cents: 0, spread_cents: 0, fee_cents: 0, occurred_at: Time.current }
    assert_predicate Trade.new(attrs.merge(quantity_after: 10**9)), :valid?
    assert_not_predicate Trade.new(attrs.merge(quantity_after: -1)), :valid?
    assert_not_predicate Trade.new(attrs.merge(quantity_after: 10**9 + 1)), :valid?
    assert_equal 1000, @trade.quantity_after
  end

  test "held and holdings follow the latest trade per caliber (ties broken by id)" do
    nine = calibers(:nine_mm)
    twenty_two = calibers(:twenty_two)
    assert_equal 1000, Trade.held(@user, nine)
    assert_equal 0, Trade.held(@user, twenty_two)
    assert_equal 0, Trade.held(users(:two), nine)
    at = Time.current.floor + 100
    Ledger::Buy.call(@user, twenty_two, 50, at: at)
    Ledger::Sell.call(@user, nine, 300, at: at) # same instant as the 22 buy: later id
    assert_equal({ nine.id => 700, twenty_two.id => 50 }, Trade.holdings(@user))
    Ledger::Sell.call(@user, twenty_two, 50, at: at)
    assert_equal({ nine.id => 700 }, Trade.holdings(@user))
    assert_equal 0, Trade.held(@user, twenty_two)
    assert_empty Trade.holdings(users(:two))
  end

  test "engine_rows are grouped by caliber id, then time, then id (the order cost_basis requires)" do
    nine = calibers(:nine_mm)
    twenty_two = calibers(:twenty_two)
    at = Time.current.floor
    Ledger::Buy.call(@user, twenty_two, 10, at: at + 5)
    Ledger::Buy.call(@user, nine, 10, at: at + 6)
    Ledger::Buy.call(@user, twenty_two, 20, at: at + 7)
    rows = @user.trades.engine_rows
    assert_equal rows.map(&:first), rows.map(&:first).sort, "calibers ascending"
    assert_equal [ nine.id, nine.id, twenty_two.id, twenty_two.id ].sort, rows.map(&:first)
    assert_equal [ 1000, 10 ], rows.select { _1.first == nine.id }.map { _1[2] }
    assert_equal [ 10, 20 ], rows.select { _1.first == twenty_two.id }.map { _1[2] }
    assert_nothing_raised { LedgerEngine.cost_basis(method: :fifo, trades: rows, t_start: 0, t_end: (at + 100).to_i) }
  end

  private

  def fund_and_buy
    fund(@user, at: @transaction.occurred_at)
    Ledger::Buy.call(@user, calibers(:nine_mm), 1000)
  end
end
