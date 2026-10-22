require "test_helper"

# Direct tests of the running-totals, builder, holdings, display and price
# wrappers. Expected values are hand-computed from ledger_core/ABI.md.
class LedgerEngineMathTest < ActiveSupport::TestCase
  E = LedgerEngine

  DEPOSIT = [ [ 1, 0, 177_600 ], [ 3, 1, 177_600 ] ].freeze
  BUY = [ [ 2, 0, 25_000 ], [ 5, 0, 375 ], [ 1, 1, 25_375 ] ].freeze
  # signup deposit, then a buy of 1000 at 2500 (cells: kind * 5 + account - 1, debits then credits)
  AFTER_DEPOSIT = ([ 177_600, 0, 0, 0, 0, 177_600 ] + [ 0 ] * 34).freeze
  AFTER_BUY = ([ 177_600, 0, 0, 0, 0, 177_600, 0, 0, 0, 0 ] + [ 0, 25_375, 25_000, 0, 0, 0, 0, 0, 375, 0 ] + [ 0 ] * 20).freeze

  def status_of(error_class = E::Error, &block)
    assert_raises(error_class, &block).status
  end

  # --- builders ---

  test "build_deposit builds Dr Cash / Cr Owner's Capital" do
    assert_equal DEPOSIT, E.build_deposit(177_600)
  end

  test "build_deposit refuses zero, negative and oversize deposits" do
    assert_equal :bad_argument, status_of { E.build_deposit(0) }
    assert_equal :bad_argument, status_of { E.build_deposit(-1) }
    assert_equal :out_of_range, status_of { E.build_deposit(10**12 + 1) }
    assert_equal [ [ 1, 0, 10**12 ], [ 3, 1, 10**12 ] ], E.build_deposit(10**12)
  end

  test "build_buy builds holdings, costs and cash lines from a quote" do
    quote = E.quote_buy(qty: 1000, price: 2500, spread_bps: 50, fee_bps: 100, cash_available: 200_000)
    assert_equal BUY, E.build_buy(quote)
  end

  test "build_buy leaves out a zero costs line" do
    quote = E::BuyQuote.new(value: 100, spread: 0, fee: 0, costs: 0, total_cash_out: 100)
    assert_equal [ [ 2, 0, 100 ], [ 1, 1, 100 ] ], E.build_buy(quote)
  end

  test "build_buy error statuses" do
    inconsistent = E::BuyQuote.new(value: 100, spread: 1, fee: 1, costs: 3, total_cash_out: 103)
    assert_equal :unbalanced, status_of { E.build_buy(inconsistent) }
    assert_equal :bad_argument, status_of { E.build_buy(E::BuyQuote.new(value: 0, spread: 0, fee: 0, costs: 0, total_cash_out: 0)) }
    assert_equal :out_of_range, status_of { E.build_buy(E::BuyQuote.new(value: 10**12 + 1, spread: 0, fee: 0, costs: 0, total_cash_out: 10**12 + 1)) }
  end

  test "build_sell builds cash, costs and holdings lines from a quote" do
    quote = E.quote_sell(qty: 1000, qty_held: 1000, price: 2500, spread_bps: 50, fee_bps: 100)
    assert_equal [ [ 1, 0, 24_625 ], [ 5, 0, 375 ], [ 2, 1, 25_000 ] ], E.build_sell(quote)
  end

  test "build_sell leaves out zero cash and zero costs lines" do
    free = E::SellQuote.new(value: 100, spread: 0, fee: 0, costs: 0, net_cash_in: 100)
    assert_equal [ [ 1, 0, 100 ], [ 2, 1, 100 ] ], E.build_sell(free)
    all_costs = E::SellQuote.new(value: 100, spread: 100, fee: 0, costs: 100, net_cash_in: 0)
    assert_equal [ [ 5, 0, 100 ], [ 2, 1, 100 ] ], E.build_sell(all_costs)
  end

  test "build_sell error statuses" do
    assert_equal :unbalanced, status_of { E.build_sell(E::SellQuote.new(value: 100, spread: 1, fee: 1, costs: 2, net_cash_in: 99)) }
    assert_equal :bad_argument, status_of { E.build_sell(E::SellQuote.new(value: 0, spread: 0, fee: 0, costs: 0, net_cash_in: 0)) }
    assert_equal :out_of_range, status_of { E.build_sell(E::SellQuote.new(value: 10**12 + 1, spread: 0, fee: 0, costs: 0, net_cash_in: 10**12 + 1)) }
  end

  test "revalue posts a gain (market 65_000 over carrying 63_000)" do
    revaluation = E.revalue([ 25_000, 40_000 ], 63_000)
    assert_equal E::Revaluation.new(market_total: 65_000, amount: 2000, direction: :gain, postings: [ [ 2, 0, 2000 ], [ 4, 1, 2000 ] ]), revaluation
  end

  test "revalue posts a loss" do
    revaluation = E.revalue([ 20_000 ], 25_000)
    assert_equal E::Revaluation.new(market_total: 20_000, amount: 5000, direction: :loss, postings: [ [ 4, 0, 5000 ], [ 2, 1, 5000 ] ]), revaluation
  end

  test "revalue posts nothing when market equals carrying, or when nothing is held" do
    assert_equal E::Revaluation.new(market_total: 30_000, amount: 0, direction: :none, postings: []), E.revalue([ 10_000, 20_000 ], 30_000)
    assert_equal E::Revaluation.new(market_total: 0, amount: 0, direction: :none, postings: []), E.revalue([], 0)
  end

  test "revalue error statuses" do
    assert_equal :out_of_range, status_of { E.revalue([ 10**12 + 1 ], 0) }
    assert_equal :out_of_range, status_of { E.revalue([ 1 ], 10**17 + 1) }
    assert_equal :out_of_range, status_of { E.revalue([ 10**12, 1 ], 0) } # difference above 10^12
  end

  # --- running totals ---

  test "apply_transaction adds the postings of one kind to the running totals" do
    assert_equal AFTER_DEPOSIT, E.apply_transaction(:deposit, DEPOSIT, E::ZERO_TOTALS)
    assert_equal AFTER_BUY, E.apply_transaction(:buy, BUY, AFTER_DEPOSIT)
  end

  test "apply_transaction takes a kind symbol or code" do
    assert_equal AFTER_DEPOSIT, E.apply_transaction(0, DEPOSIT, E::ZERO_TOTALS)
    assert_equal :bad_argument, status_of { E.apply_transaction(4, DEPOSIT, E::ZERO_TOTALS) }
  end

  test "apply_transaction error statuses" do
    assert_equal :unbalanced, status_of { E.apply_transaction(:deposit, [ [ 1, 0, 5 ], [ 3, 1, 4 ] ], E::ZERO_TOTALS) }
    assert_equal :bad_argument, status_of { E.apply_transaction(:deposit, [], E::ZERO_TOTALS) }
    assert_equal :bad_argument, status_of { E.apply_transaction(:deposit, [ [ 9, 0, 5 ], [ 3, 1, 5 ] ], E::ZERO_TOTALS) }
    assert_equal :out_of_range, status_of { E.apply_transaction(:deposit, [ [ 1, 0, 10**12 + 1 ], [ 3, 1, 10**12 + 1 ] ], E::ZERO_TOTALS) }
    assert_equal :negative_balance, status_of { E.apply_transaction(:buy, BUY, E::ZERO_TOTALS) }
    unbalanced_previous = E::ZERO_TOTALS.dup.tap { _1[0] = 5 }
    assert_equal :unbalanced, status_of { E.apply_transaction(:deposit, DEPOSIT, unbalanced_previous) }
    cell_too_big = E::ZERO_TOTALS.dup.tap { _1[0] = 10**17 }
    assert_equal :out_of_range, status_of { E.apply_transaction(:deposit, DEPOSIT, cell_too_big) }
  end

  test "apply_transaction refuses more than 16 postings and totals of the wrong size" do
    many = Array.new(17) { [ 1, 0, 1 ] }
    error = assert_raises(E::Error) { E.apply_transaction(:deposit, many, E::ZERO_TOTALS) }
    assert_equal :bad_argument, error.status
    assert_raises(ArgumentError) { E.apply_transaction(:deposit, DEPOSIT, [ 0 ] * 39) }
  end

  test "apply_transaction takes exactly 16 postings" do
    sixteen = Array.new(8) { [ [ 1, 0, 1 ], [ 3, 1, 1 ] ] }.flatten(1)
    assert_equal 16, sixteen.size
    assert_equal [ 8, 0, 0, 0, 0, 8 ], E.apply_transaction(:deposit, sixteen, E::ZERO_TOTALS).first(6)
  end

  test "ints beyond int64 never reach the engine" do
    assert_raises(RangeError) { E.sum([ 2**70 ]) }
    assert_raises(RangeError) { E.apply_transaction(:deposit, DEPOSIT, [ 2**70 ] + [ 0 ] * 39) }
  end

  test "diff_totals is closing minus opening, cell by cell" do
    assert_equal AFTER_BUY.zip(AFTER_DEPOSIT).map { |a, b| a - b }, E.diff_totals(AFTER_BUY, AFTER_DEPOSIT)
    assert_equal ([ 0 ] * 11) + [ 25_375, 25_000, 0, 0, 0, 0, 0, 375 ] + ([ 0 ] * 21), E.diff_totals(AFTER_BUY, AFTER_DEPOSIT)
  end

  test "diff_totals error statuses" do
    assert_equal :bad_order, status_of { E.diff_totals(AFTER_DEPOSIT, AFTER_BUY) }
    assert_equal :unbalanced, status_of { E.diff_totals(E::ZERO_TOTALS.dup.tap { _1[0] = 1 }, E::ZERO_TOTALS) }
    assert_equal :out_of_range, status_of { E.diff_totals(E::ZERO_TOTALS.dup.tap { _1[0] = 10**17 }, E::ZERO_TOTALS) }
  end

  test "collapse_kinds sums the four kinds into five account pairs" do
    assert_equal [ [ 177_600, 25_375 ], [ 25_000, 0 ], [ 0, 177_600 ], [ 0, 0 ], [ 375, 0 ] ], E.collapse_kinds(AFTER_BUY)
    assert_equal [ [ 0, 0 ] ] * 5, E.collapse_kinds(E::ZERO_TOTALS)
    assert_equal :out_of_range, status_of { E.collapse_kinds(E::ZERO_TOTALS.dup.tap { _1[39] = 10**17 }) }
  end

  test "audit_chain accepts a consistent chain, an empty chain and equal neighbours" do
    assert E.audit_chain([ AFTER_DEPOSIT, AFTER_BUY ])
    assert E.audit_chain([])
    assert E.audit_chain([ AFTER_DEPOSIT, AFTER_DEPOSIT ])
  end

  test "audit_chain error statuses" do
    assert_equal :bad_order, status_of { E.audit_chain([ AFTER_BUY, AFTER_DEPOSIT ]) }
    assert_equal :unbalanced, status_of { E.audit_chain([ AFTER_DEPOSIT, AFTER_DEPOSIT.dup.tap { _1[0] = 177_601 } ]) }
    assert_equal :negative_balance, status_of { E.audit_chain([ E::ZERO_TOTALS.dup.tap { |t| t[1] = 5; t[4] = 5 } ]) }
    assert_equal :out_of_range, status_of { E.audit_chain([ E::ZERO_TOTALS.dup.tap { _1[0] = 10**17 } ]) }
    assert_raises(ArgumentError) { E.audit_chain([ [ 0 ] * 39 ]) }
  end

  test "period_report returns both balance sheets, the income statement and the cash flow" do
    report = E.period_report(AFTER_DEPOSIT, AFTER_BUY, 0)
    assert_equal E::BalanceSheet.new(cash: 177_600, holdings: 0, total_assets: 177_600, owners_capital: 177_600,
      net_income_to_date: 0, total_equity: 177_600, total_liabilities: 0), report.opening
    assert_equal E::BalanceSheet.new(cash: 152_225, holdings: 25_000, total_assets: 177_225, owners_capital: 177_600,
      net_income_to_date: -375, total_equity: 177_225, total_liabilities: 0), report.closing
    assert_equal E::IncomeStatement.new(realized_gain: 0, unrealized_gain: 0, trading_gain_total: 0, trading_costs: 375, net_income: -375), report.income
    assert_equal E::CashFlow.new(financing: 0, investing: -25_000, operating: -375, net_change: -25_375), report.cash_flow
  end

  test "period_report error statuses" do
    assert_equal :bad_order, status_of { E.period_report(AFTER_BUY, AFTER_DEPOSIT, 0) }
    assert_equal :out_of_range, status_of { E.period_report(AFTER_DEPOSIT, AFTER_BUY, 10**18 + 1) }
  end

  # --- holdings ---

  test "apply_trade_quantity adds buys and subtracts sells" do
    assert_equal 100, E.apply_trade_quantity(0, :buy, 100)
    assert_equal 60, E.apply_trade_quantity(100, :sell, 40)
    assert_equal 0, E.apply_trade_quantity(100, 1, 100)
    assert_equal 10**9, E.apply_trade_quantity(10**9 - 1, 0, 1)
  end

  test "apply_trade_quantity error statuses" do
    assert_equal :bad_argument, status_of { E.apply_trade_quantity(0, 2, 1) }
    assert_equal :insufficient_holdings, status_of(E::Refusal) { E.apply_trade_quantity(5, :sell, 6) }
    assert_equal :out_of_range, status_of { E.apply_trade_quantity(10**9, :buy, 1) }
    assert_equal :out_of_range, status_of { E.apply_trade_quantity(0, :buy, 0) }
    assert_equal :out_of_range, status_of { E.apply_trade_quantity(-1, :buy, 1) }
  end

  test "portfolio_position is market value minus cost basis" do
    assert_equal 5000, E.portfolio_position(25_000, 20_000)
    assert_equal(-10, E.portfolio_position(10, 20))
    assert_equal 0, E.portfolio_position(0, 0)
    assert_equal :out_of_range, status_of { E.portfolio_position(10**17 + 1, 0) }
    assert_equal :out_of_range, status_of { E.portfolio_position(0, -1) }
  end

  test "sum adds exactly" do
    assert_equal 6, E.sum([ 1, 2, 3 ])
    assert_equal 0, E.sum([])
    assert_equal(-5, E.sum([ 10, -15 ]))
    assert_equal 10**17, E.sum([ 10**17 ])
    assert_equal :out_of_range, status_of { E.sum([ 10**17 + 1 ]) }
    assert_equal :out_of_range, status_of { E.sum([ 10**17, 1 ]) }
  end

  # --- display and chart math ---

  test "split_money splits cents into whole and fraction" do
    assert_equal E::MoneyParts.new(whole: 1776, fraction: 0, negative: false), E.split_money(177_600)
    assert_equal E::MoneyParts.new(whole: 0, fraction: 5, negative: true), E.split_money(-5)
    assert_equal E::MoneyParts.new(whole: 0, fraction: 0, negative: false), E.split_money(0)
    assert_equal E::MoneyParts.new(whole: 92_233_720_368_547_758, fraction: 8, negative: true), E.split_money(-(2**63))
  end

  test "split_price splits centicents into whole dollars and a four digit fraction" do
    assert_equal E::MoneyParts.new(whole: 0, fraction: 2500, negative: false), E.split_price(2500)
    assert_equal E::MoneyParts.new(whole: 1, fraction: 1, negative: true), E.split_price(-10_001)
    assert_equal E::MoneyParts.new(whole: 12, fraction: 345, negative: false), E.split_price(120_345)
  end

  test "negate flips the sign" do
    assert_equal(-5, E.negate(5))
    assert_equal 5, E.negate(-5)
    assert_equal 0, E.negate(0)
    assert_equal :out_of_range, status_of { E.negate(-(2**63)) }
  end

  test "scale places values on the chart, flipped for the y axis" do
    assert_equal 120, E.scale(5, 0, 10, 240)
    assert_equal 0, E.scale(0, 0, 10, 240)
    assert_equal 240, E.scale(10, 0, 10, 240)
    assert_equal 240, E.scale(0, 0, 10, 240, invert: true)
    assert_equal 0, E.scale(10, 0, 10, 240, invert: true)
    assert_equal 3, E.scale(1, 0, 10, 30)
    assert_equal 2, E.scale(2, 0, 3, 3)
    assert_equal 360, E.scale(7, 7, 7, 720)
    assert_equal 120, E.scale(7, 7, 7, 240, invert: true)
  end

  test "scale error statuses" do
    assert_equal :bad_argument, status_of { E.scale(5, 10, 0, 240) }
    assert_equal :out_of_range, status_of { E.scale(11, 0, 10, 240) }
    assert_equal :out_of_range, status_of { E.scale(5, 0, 10, 10**9 + 1) }
  end

  test "min_max finds the extent" do
    assert_equal E::Extent.new(low: 1, high: 3), E.min_max([ 3, 1, 2 ])
    assert_equal E::Extent.new(low: -4, high: -4), E.min_max([ -4 ])
    assert_equal :bad_argument, status_of { E.min_max([]) }
  end

  test "sample_times spreads times evenly and always ends at finish" do
    assert_equal E::Sampling.new(times: [ 0, 250, 500, 750, 1000 ], step: 250), E.sample_times(0, 1000, 5)
    assert_equal E::Sampling.new(times: [ 0, 4, 8, 10 ], step: 4), E.sample_times(0, 10, 4)
    assert_equal E::Sampling.new(times: [ 7 ], step: 1), E.sample_times(7, 7, 200)
    assert_equal E::Sampling.new(times: [ 100 ], step: 1), E.sample_times(0, 100, 1)
    assert_equal E::Sampling.new(times: [ 0, 1, 2 ], step: 1), E.sample_times(0, 2, 200)
  end

  test "sample_times error statuses" do
    assert_equal :bad_argument, status_of { E.sample_times(5, 4, 10) }
    assert_equal :bad_argument, status_of { E.sample_times(0, 10, 0) }
    assert_equal :out_of_range, status_of { E.sample_times(0, 10**12 + 1, 10) }
    assert_equal :out_of_range, status_of { E.sample_times(-1, 10, 10) }
    assert_equal :out_of_range, status_of { E.sample_times(0, 10, 10**6 + 1) }
  end

  # --- price math ---

  test "next_price moves by basis points truncating toward zero, then clamps" do
    options = { max_step_bps: 200, floor: 100, ceiling: 100_000 }
    assert_equal 2550, E.next_price(2500, 200, **options)
    assert_equal 2450, E.next_price(2500, -200, **options)
    assert_equal 101, E.next_price(101, -1, **options)
    assert_equal 100, E.next_price(100, -200, **options)
    assert_equal 100_000, E.next_price(99_999, 200, **options)
    assert_equal 2500, E.next_price(2500, 0, **options)
  end

  test "next_price error statuses" do
    assert_equal :bad_argument, status_of { E.next_price(5, 0, max_step_bps: 1, floor: 10, ceiling: 1) }
    assert_equal :out_of_range, status_of { E.next_price(5, 201, max_step_bps: 200, floor: 0, ceiling: 100) }
    assert_equal :out_of_range, status_of { E.next_price(10**7 + 1, 0, max_step_bps: 200, floor: 0, ceiling: 10**7) }
  end

  test "bps_from_random maps an unsigned 64 bit number into +-max_step_bps" do
    assert_equal(-200, E.bps_from_random(0, 200))
    assert_equal 200, E.bps_from_random(400, 200)
    assert_equal(-200, E.bps_from_random(401, 200))
    assert_equal(-138, E.bps_from_random((2**64) - 1, 200))
    assert_equal 32, E.bps_from_random(2**63, 200)
    assert_equal 0, E.bps_from_random(12_345, 0)
    assert_equal :out_of_range, status_of { E.bps_from_random(1, 10_001) }
  end

  test "ohlc builds a candle from prices" do
    candle = E.ohlc([ 2500, 2600, 2400, 2550 ])
    assert_equal E::Candle.new(open: 2500, high: 2600, low: 2400, close: 2550, ticks: 4, last_as_of: 0), candle
    assert_equal E::Candle.new(open: 7, high: 7, low: 7, close: 7, ticks: 1, last_as_of: 0), E.ohlc([ 7 ])
  end

  test "ohlc error statuses" do
    assert_equal :bad_argument, status_of { E.ohlc([]) }
    assert_equal :out_of_range, status_of { E.ohlc([ -1 ]) }
    assert_equal :out_of_range, status_of { E.ohlc([ 10**7 + 1 ]) }
  end

  test "ohlc_merge merges time ordered candles" do
    first = E::Candle.new(open: 100, high: 120, low: 90, close: 110, ticks: 3, last_as_of: 50)
    second = E::Candle.new(open: 110, high: 150, low: 105, close: 140, ticks: 2, last_as_of: 80)
    assert_equal E::Candle.new(open: 100, high: 150, low: 90, close: 140, ticks: 5, last_as_of: 80), E.ohlc_merge([ first, second ])
    assert_equal first, E.ohlc_merge([ first ])
  end

  test "ohlc_merge error statuses" do
    assert_equal :bad_argument, status_of { E.ohlc_merge([]) }
    broken = E::Candle.new(open: 100, high: 99, low: 90, close: 95, ticks: 1, last_as_of: 1)
    assert_equal :bad_argument, status_of { E.ohlc_merge([ broken ]) }
    off = E::Candle.new(open: 100, high: 10**7 + 1, low: 90, close: 95, ticks: 1, last_as_of: 1)
    assert_equal :out_of_range, status_of { E.ohlc_merge([ off ]) }
  end

  # --- status codes ---

  test "status 10 is an internal error and a plain Error" do
    error = assert_raises(E::Error) { E.send(:check!, 10, :anything) }
    assert_equal :internal_error, error.status
    assert_not_kind_of E::Refusal, error
  end
end
