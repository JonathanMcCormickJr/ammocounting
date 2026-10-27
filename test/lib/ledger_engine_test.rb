require "test_helper"

# Hand-computed values from ledger_core/ABI.md and ledger_core/tests.
class LedgerEngineTest < ActiveSupport::TestCase
  HISTORY = [ [ 7, 0, 100, 1000, 10 ], [ 7, 0, 100, 2000, 20 ], [ 7, 1, 100, 1500, 30 ] ].freeze
  # accounts 1..5 after: signup deposit 177_600, then buy of 1000 rounds at 2500 (25_375 out).
  TOTALS = [ [ 177_600, 25_375 ], [ 25_000, 0 ], [ 0, 177_600 ], [ 0, 0 ], [ 375, 0 ] ].freeze

  test "library_path defaults to the built library and honours LEDGER_CORE_LIB" do
    assert_equal Rails.root.join("ledger_core/lib/libLedger_Core.so").to_s, LedgerEngine.library_path(env: {})
    assert_equal "/opt/x.so", LedgerEngine.library_path(env: { "LEDGER_CORE_LIB" => "/opt/x.so" })
  end

  test "resolve_library returns an existing path" do
    path = Rails.root.join("ledger_core/ledger_core.gpr").to_s
    assert_equal path, LedgerEngine.resolve_library(path)
  end

  test "resolve_library explains how to build a missing library" do
    error = assert_raises(LedgerEngine::LibraryMissing) { LedgerEngine.resolve_library("/nonexistent/libLedger_Core.so") }
    assert_includes error.message, "/nonexistent/libLedger_Core.so"
    assert_includes error.message, "scripts/build.sh"
    assert_includes error.message, "LEDGER_CORE_LIB"
  end

  test "the built library is the one loaded" do
    assert_equal LedgerEngine.library_path, ENV.fetch("LEDGER_CORE_LIB") { LedgerEngine.library_path }
    assert File.exist?(LedgerEngine.library_path)
  end

  test "struct layouts match ABI.md sizes" do
    native = LedgerEngine::Native
    sizes = { Posting: 16, PostingSet: 264, Trade: 32, BuyQuote: 40, SellQuote: 40, BasisReport: 40, AccountTotal: 16,
              BalanceSheet: 56, IncomeStatement: 40, CashFlow: 32, PeriodReport: 184, Revaluation: 24,
              MoneyParts: 24, Extent: 16, Candle: 48 }
    sizes.each { |name, size| assert_equal size, native.const_get(name).size, name }
  end

  test "version" do
    assert_equal 300, LedgerEngine.version
  end

  test "validate_transaction accepts a balanced transaction" do
    assert LedgerEngine.validate_transaction([ [ 1, 0, 177_600 ], [ 3, 1, 177_600 ] ])
  end

  test "validate_transaction reports unbalanced postings" do
    error = assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([ [ 1, 0, 100 ], [ 3, 1, 99 ] ]) }
    assert_equal :unbalanced, error.status
    assert_equal :validate_transaction, error.operation
    assert_not_kind_of LedgerEngine::Refusal, error
    assert_includes error.message, "unbalanced"
  end

  test "validate_transaction rejects an empty transaction, bad codes and bad amounts" do
    assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([]) }.status
    assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([ [ 6, 0, 1 ], [ 3, 1, 1 ] ]) }.status
    assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([ [ 1, 2, 1 ], [ 3, 1, 1 ] ]) }.status
    assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([ [ 1, 0, 0 ], [ 3, 1, 0 ] ]) }.status
    big = 10**12 + 1
    assert_equal :out_of_range, assert_raises(LedgerEngine::Error) { LedgerEngine.validate_transaction([ [ 1, 0, big ], [ 3, 1, big ] ]) }.status
  end

  test "int64 overflow never reaches the engine" do
    assert_equal :out_of_range, assert_raises(LedgerEngine::Error) { LedgerEngine.market_value(2**70, 1) }.status
  end

  test "market_value rounds half cents up" do
    assert_equal 25_000, LedgerEngine.market_value(1000, 2500)
    assert_equal 1275, LedgerEngine.market_value(50, 2550)
  end

  test "market_value half-up boundary and zero" do
    assert_equal 1, LedgerEngine.market_value(1, 50) # 0.5 cents -> 1
    assert_equal 0, LedgerEngine.market_value(1, 49)
    assert_equal 0, LedgerEngine.market_value(0, 2500)
  end

  test "market_value rejects out-of-range input" do
    assert_equal :out_of_range, assert_raises(LedgerEngine::Error) { LedgerEngine.market_value(10**9 + 1, 1) }.status
    assert_equal :out_of_range, assert_raises(LedgerEngine::Error) { LedgerEngine.market_value(1, 10**7 + 1) }.status
  end

  test "quote_buy matches ABI.md" do
    quote = LedgerEngine.quote_buy(qty: 1000, price: 2500, spread_bps: 50, fee_bps: 100, cash_available: 200_000)
    assert_equal LedgerEngine::BuyQuote.new(value: 25_000, spread: 125, fee: 250, costs: 375, total_cash_out: 25_375), quote
  end

  test "quote_buy allows spending exactly the available cash" do
    quote = LedgerEngine.quote_buy(qty: 1000, price: 2500, spread_bps: 50, fee_bps: 100, cash_available: 25_375)
    assert_equal 25_375, quote.total_cash_out
  end

  test "quote_buy refuses insufficient cash with a Refusal" do
    error = assert_raises(LedgerEngine::Refusal) do
      LedgerEngine.quote_buy(qty: 1000, price: 2500, spread_bps: 50, fee_bps: 100, cash_available: 25_374)
    end
    assert_equal :insufficient_cash, error.status
  end

  test "quote_buy range errors are plain Errors" do
    error = assert_raises(LedgerEngine::Error) do
      LedgerEngine.quote_buy(qty: 1, price: 1, spread_bps: 10_001, fee_bps: 0, cash_available: 100)
    end
    assert_equal :out_of_range, error.status
    assert_not_kind_of LedgerEngine::Refusal, error
  end

  test "quote_sell matches ABI.md" do
    quote = LedgerEngine.quote_sell(qty: 1000, qty_held: 1000, price: 2500, spread_bps: 50, fee_bps: 100)
    assert_equal LedgerEngine::SellQuote.new(value: 25_000, spread: 125, fee: 250, costs: 375, net_cash_in: 24_625), quote
  end

  test "quote_sell refuses overselling" do
    error = assert_raises(LedgerEngine::Refusal) do
      LedgerEngine.quote_sell(qty: 1001, qty_held: 1000, price: 2500, spread_bps: 50, fee_bps: 100)
    end
    assert_equal :insufficient_holdings, error.status
  end

  test "quote_sell refuses costs above value and allows costs equal to value" do
    error = assert_raises(LedgerEngine::Refusal) do
      LedgerEngine.quote_sell(qty: 100, qty_held: 100, price: 100, spread_bps: 10_000, fee_bps: 100)
    end
    assert_equal :negative_proceeds, error.status
    quote = LedgerEngine.quote_sell(qty: 100, qty_held: 100, price: 100, spread_bps: 10_000, fee_bps: 0)
    assert_equal 0, quote.net_cash_in
  end

  test "cost_basis weighted average and FIFO match ABI.md" do
    wa = LedgerEngine.cost_basis(method: :weighted_average, trades: HISTORY, t_start: 0, t_end: 100)
    assert_equal LedgerEngine::BasisReport.new(realized_gain: 0, basis_at_start: 0, basis_at_end: 1500, purchased: 3000, consumed: 1500), wa
    fifo = LedgerEngine.cost_basis(method: "fifo", trades: HISTORY, t_start: 0, t_end: 100)
    assert_equal LedgerEngine::BasisReport.new(realized_gain: 500, basis_at_start: 0, basis_at_end: 2000, purchased: 3000, consumed: 1000), fifo
  end

  test "cost_basis accepts an empty history" do
    report = LedgerEngine.cost_basis(method: :fifo, trades: [], t_start: 0, t_end: 100)
    assert_equal 0, report.purchased
  end

  test "cost_basis reports period boundaries" do
    report = LedgerEngine.cost_basis(method: :fifo, trades: HISTORY, t_start: 20, t_end: 100)
    assert_equal 3000, report.basis_at_start
    assert_equal 500, report.realized_gain
  end

  test "cost_basis error statuses" do
    assert_equal :bad_order, assert_raises(LedgerEngine::Error) { LedgerEngine.cost_basis(method: :fifo, trades: HISTORY.reverse, t_start: 0, t_end: 100) }.status
    oversell = [ [ 7, 1, 1, 1, 1 ] ]
    assert_equal :insufficient_holdings, assert_raises(LedgerEngine::Refusal) { LedgerEngine.cost_basis(method: :fifo, trades: oversell, t_start: 0, t_end: 5) }.status
    assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { LedgerEngine.cost_basis(method: :fifo, trades: [], t_start: 5, t_end: 1) }.status
    assert_raises(KeyError) { LedgerEngine.cost_basis(method: :lifo, trades: [], t_start: 0, t_end: 1) }
  end

  test "balance_sheet matches ABI.md" do
    sheet = LedgerEngine.balance_sheet(TOTALS)
    expected = { cash: 152_225, holdings: 25_000, total_assets: 177_225, owners_capital: 177_600,
                 net_income_to_date: -375, total_equity: 177_225, total_liabilities: 0 }
    assert_equal expected, sheet.to_h
  end

  test "balance_sheet refuses unbalanced and negative-cash books" do
    assert_equal :unbalanced, assert_raises(LedgerEngine::Error) { LedgerEngine.balance_sheet(TOTALS.dup.tap { _1[0] = [ 177_601, 25_375 ] }) }.status
    negative = [ [ 0, 5 ], [ 5, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 0 ] ]
    assert_equal :negative_balance, assert_raises(LedgerEngine::Error) { LedgerEngine.balance_sheet(negative) }.status
  end

  test "totals must have exactly the rows the engine reads" do
    assert_raises(ArgumentError) { LedgerEngine.balance_sheet(TOTALS.first(4)) }
    assert_raises(ArgumentError) { LedgerEngine.income_statement(TOTALS + [ [ 0, 0 ] ], 0) }
    assert_raises(ArgumentError) { LedgerEngine.cash_flow(Array.new(39, 0), 0, 0) }
  end

  test "income_statement" do
    period = [ [ 0, 0 ], [ 0, 0 ], [ 0, 0 ], [ 0, 1500 ], [ 375, 0 ] ]
    statement = LedgerEngine.income_statement(period, 1000)
    assert_equal LedgerEngine::IncomeStatement.new(realized_gain: 1000, unrealized_gain: 500, trading_gain_total: 1500,
      trading_costs: 375, net_income: 1125), statement
  end

  test "income_statement range error" do
    assert_equal :out_of_range, assert_raises(LedgerEngine::Error) { LedgerEngine.income_statement(Array.new(5) { [ 0, 0 ] }, 10**18 + 1) }.status
  end

  test "cash_flow for the signup deposit" do
    activity = activity_with({ [ 0, 1 ] => [ 177_600, 0 ], [ 0, 3 ] => [ 0, 177_600 ] })
    flow = LedgerEngine.cash_flow(activity, 0, 177_600)
    assert_equal LedgerEngine::CashFlow.new(financing: 177_600, investing: 0, operating: 0, net_change: 177_600), flow
  end

  test "cash_flow for a buy" do
    activity = activity_with({ [ 1, 1 ] => [ 0, 25_375 ], [ 1, 2 ] => [ 25_000, 0 ], [ 1, 5 ] => [ 375, 0 ] })
    flow = LedgerEngine.cash_flow(activity, 177_600, 152_225)
    assert_equal LedgerEngine::CashFlow.new(financing: 0, investing: -25_000, operating: -375, net_change: -25_375), flow
  end

  test "cash_flow refuses a closing balance that does not reconcile" do
    activity = activity_with({ [ 0, 1 ] => [ 100, 0 ], [ 0, 3 ] => [ 0, 100 ] })
    assert_equal :not_reconciled, assert_raises(LedgerEngine::Error) { LedgerEngine.cash_flow(activity, 0, 5) }.status
  end

  test "cost_basis wants trades grouped by caliber ascending, then time" do
    two_calibers = [ [ 7, 0, 10, 100, 10 ], [ 9, 0, 10, 200, 5 ], [ 9, 1, 10, 300, 6 ] ]
    report = LedgerEngine.cost_basis(method: :fifo, trades: two_calibers, t_start: 0, t_end: 100)
    assert_equal LedgerEngine::BasisReport.new(realized_gain: 100, basis_at_start: 0, basis_at_end: 100, purchased: 300, consumed: 200), report
    assert_equal :bad_order, assert_raises(LedgerEngine::Error) { LedgerEngine.cost_basis(method: :fifo, trades: two_calibers.reverse, t_start: 0, t_end: 100) }.status
    reappears = [ [ 7, 0, 1, 1, 1 ], [ 9, 0, 1, 1, 2 ], [ 7, 0, 1, 1, 3 ] ]
    assert_equal :bad_order, assert_raises(LedgerEngine::Error) { LedgerEngine.cost_basis(method: :fifo, trades: reappears, t_start: 0, t_end: 100) }.status
  end

  private

  # The flat 40 running totals with { [kind, account] => [debits, credits] } filled in.
  def activity_with(cells)
    LedgerEngine::ZERO_TOTALS.dup.tap do |totals|
      cells.each { |(kind, account), (debits, credits)| totals[(((kind * 5) + account - 1) * 2), 2] = [ debits, credits ] }
    end
  end
end
