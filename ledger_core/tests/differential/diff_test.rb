#!/usr/bin/env ruby
# frozen_string_literal: true

# Differential test: every exported ledger_core function against an
# independent pure-Ruby reference (Ruby Integers are exact), on seeded random
# inputs plus boundary values. Needs only `ruby` and the `ffi` gem; exits
# non-zero on any mismatch.
#
#   ruby ledger_core/tests/differential/diff_test.rb [path/to/libLedger_Core.so]
#
# Environment: SEED (default 20260101), ITERATIONS (default 4000 per seed),
# SEED_COUNT (default 3: SEED, SEED + 1, SEED + 2).
#
# Three kinds of checks:
#  * per-function: the engine against the pure-Ruby reference (module Ref) on
#    seeded random and boundary inputs;
#  * economic/flow properties (module Sim): the engine is driven like the Rails
#    app drives it and its books are compared with an independent Ruby model of
#    the same user (cash, holdings, market value tracked directly): the ledger's
#    trading gain equals realized + unrealized computed from that model, equity
#    never rises on round trips, every trade costs at least a cent;
#  * audit E3 reproduction (price 149 centicents, spread 0).
#
# Behaviour changes vs the first engine (audit): a quote with value 0 is status 1
# (was Ok), and a trade of positive value costs at least 1 cent (spread is raised
# to 1 cent when spread and fee both round to 0). The default 50/100 bps
# configuration is numerically unchanged (its ceiling spread is already >= 1).

require "ffi"
require_relative "../check_contract_boundary"

LIB = ARGV[0] || ENV["LEDGER_CORE_LIB"] ||
      File.expand_path("../../lib/libLedger_Core.so", __dir__)
SEED = Integer(ENV.fetch("SEED", "20260101"))
N = Integer(ENV.fetch("ITERATIONS", "4000"))
# Every random suite runs once per seed (SEED, SEED + 1, ...).
SEED_COUNT = Integer(ENV.fetch("SEED_COUNT", "3"))
SEEDS = Array.new(SEED_COUNT) { SEED + _1 }.freeze

# ---------------------------------------------------------------- engine ---
module Engine
  extend FFI::Library
  ffi_lib LIB

  I = %i[int32 int64].freeze
  {
    engine_version: [[], :int32],
    validate_transaction: [%i[int32 pointer], :int32],
    apply_transaction: [%i[int32 pointer pointer pointer], :int32],
    apply_deposit: %i[pointer pointer pointer],
    apply_buy: %i[pointer pointer pointer],
    apply_sell: %i[pointer pointer pointer],
    apply_revalue: %i[pointer pointer pointer],
    diff_totals: %i[pointer pointer pointer],
    collapse_kinds: %i[pointer pointer],
    audit_chain: %i[int32 pointer],
    build_deposit: %i[int64 pointer],
    build_buy: %i[pointer pointer],
    build_sell: %i[pointer pointer],
    revalue: %i[int32 pointer int64 pointer pointer],
    market_value: %i[int64 int64 pointer],
    quote_buy: %i[int64 int64 int64 int64 int64 pointer],
    quote_sell: %i[int64 int64 int64 int64 int64 pointer],
    apply_trade_quantity: %i[int64 int32 int64 pointer],
    portfolio_position: %i[int64 int64 pointer],
    sum: %i[int32 pointer pointer],
    cost_basis: %i[int32 int32 pointer int64 int64 pointer],
    balance_sheet: %i[pointer pointer],
    income_statement: %i[pointer int64 pointer],
    cash_flow: %i[pointer int64 int64 pointer],
    period_report: %i[pointer pointer int64 pointer],
    period_report_checked: %i[pointer pointer pointer pointer],
    split_money: %i[int64 pointer],
    split_price: %i[int64 pointer],
    negate: %i[int64 pointer],
    scale: %i[int64 int64 int64 int64 int32 pointer],
    min_max: %i[int32 pointer pointer],
    sample_times: %i[int64 int64 int32 pointer pointer pointer],
    next_price: %i[int64 int64 int64 int64 int64 pointer],
    bps_from_random: %i[uint64 int64 pointer],
    ohlc: %i[int32 pointer pointer],
    ohlc_merge: %i[int32 pointer pointer]
  }.each do |name, sig|
    args, ret = sig.first.is_a?(Array) ? sig : [sig, :int32]
    attach_function name, :"ledger_core_#{name}", args, ret
  end
end

MAX_AMOUNT = 10**12
MAX_QTY = 10**9
MAX_PRICE = 10**7
MAX_BPS = 10_000
MAX_AGG = 10**17
MAX_GAIN = 10**18
MAX_HELD = 10**9
MAX_TIME = 10**12
MAX_SIZE = 10**9
MAX_POINTS = 10**6
MAX_CELL = MAX_AGG / 4
I64_MIN = -(2**63)
I64_MAX = (2**63) - 1
def i64(value) = value.clamp(I64_MIN, I64_MAX)
OK = 0
BAD = 1
RANGE = 2
UNBAL = 3
CASH = 4
HOLD = 5
PROCEEDS = 6
ORDER = 7
NEG = 8
NOREC = 9

# ------------------------------------------------------------- reference ---
module Ref
  module_function

  def rhu(a, b, d) = ((2 * a * b) + d) / (2 * d)
  def ceil_div(a, b, d) = ((a * b) + d - 1) / d
  def zeros(n) = Array.new(n, 0)
  def fail_with(status, n) = [status, zeros(n)]

  def market_value(qty, price)
    return fail_with(RANGE, 1) unless (0..MAX_QTY).cover?(qty) && (0..MAX_PRICE).cover?(price)

    value = rhu(qty, price, 100)
    value > MAX_AMOUNT ? fail_with(RANGE, 1) : [OK, [value]]
  end

  # Spread and fee on a value, with the audit-E3 minimum: a positive value never
  # trades for free (the spread is raised to 1 cent when spread and fee both
  # round to 0). Whenever spread_bps > 0 the ceiling already gives >= 1 cent for
  # a positive value, so the default 50/100 bps configuration is unchanged.
  def costs_of(value, spread_bps, fee_bps)
    spread = ceil_div(value, spread_bps, 10_000)
    fee = rhu(value, fee_bps, 10_000)
    spread = 1 if value.positive? && (spread + fee).zero?
    [spread, fee]
  end

  def quote_buy(qty, price, spread_bps, fee_bps, cash)
    status, out = market_value(qty, price)
    value = out.first
    return fail_with(status, 5) unless status == OK
    return fail_with(RANGE, 5) unless (0..MAX_BPS).cover?(spread_bps) && (0..MAX_BPS).cover?(fee_bps)
    return fail_with(BAD, 5) if value.zero? # audit E5: a zero value is not a quote

    spread, fee = costs_of(value, spread_bps, fee_bps)
    total = value + spread + fee
    return fail_with(RANGE, 5) if total > MAX_AMOUNT
    return fail_with(CASH, 5) if total > cash

    [OK, [value, spread, fee, spread + fee, total]]
  end

  def quote_sell(qty, held, price, spread_bps, fee_bps)
    status, out = market_value(qty, price)
    value = out.first
    return fail_with(status, 5) unless status == OK
    return fail_with(RANGE, 5) unless (0..MAX_BPS).cover?(spread_bps) && (0..MAX_BPS).cover?(fee_bps)
    return fail_with(RANGE, 5) if held.negative?
    return fail_with(BAD, 5) if value.zero?
    return fail_with(HOLD, 5) if qty > held

    spread, fee = costs_of(value, spread_bps, fee_bps)
    costs = spread + fee
    return fail_with(PROCEEDS, 5) if costs > value

    [OK, [value, spread, fee, costs, value - costs]]
  end

  # postings: [[account, side, amount], ...]
  def validate_postings(postings)
    return BAD unless (1..16).cover?(postings.size)

    postings.each do |account, side, amount|
      return BAD unless (1..5).cover?(account) && (0..1).cover?(side) && amount >= 1
      return RANGE if amount > MAX_AMOUNT
    end
    debits = postings.sum { |_a, s, m| s.zero? ? m : 0 }
    credits = postings.sum { |_a, s, m| s == 1 ? m : 0 }
    debits == credits ? OK : UNBAL
  end

  # A Posting_Set as the flat [count, reserved, postings...] the engine returns.
  def set_out(postings)
    [postings.size, 0] + postings.flatten + zeros(3 * (16 - postings.size))
  end

  def empty_set = zeros(2 + 48)

  def build_deposit(cents)
    return [BAD, empty_set] if cents < 1
    return [RANGE, empty_set] if cents > MAX_AMOUNT

    [OK, set_out([[1, 0, cents], [3, 1, cents]])]
  end

  def build_buy(value, spread, fee, costs, total)
    return [RANGE, empty_set] unless [value, spread, fee, costs, total].all? { (0..MAX_AMOUNT).cover?(_1) }
    return [UNBAL, empty_set] unless costs == spread + fee && total == value + costs
    return [BAD, empty_set] if total.zero?

    lines = []
    lines << [2, 0, value] if value.positive?
    lines << [5, 0, costs] if costs.positive?
    lines << [1, 1, total]
    [OK, set_out(lines)]
  end

  def build_sell(value, spread, fee, costs, net)
    return [RANGE, empty_set] unless [value, spread, fee, costs, net].all? { (0..MAX_AMOUNT).cover?(_1) }
    return [UNBAL, empty_set] unless costs == spread + fee && net + costs == value
    return [BAD, empty_set] if value.zero?

    lines = []
    lines << [1, 0, net] if net.positive?
    lines << [5, 0, costs] if costs.positive?
    lines << [2, 1, value]
    [OK, set_out(lines)]
  end

  # => [status, [market_total, amount, direction, reserved] + set]
  def revalue(values, carrying)
    bad = ->(status) { [status, zeros(2) + [0] + empty_set] }
    return bad.call(RANGE) unless (0..MAX_AGG).cover?(carrying)

    market = 0
    values.each do |v|
      return bad.call(RANGE) unless (0..MAX_AMOUNT).cover?(v)
      return bad.call(RANGE) if market + v > MAX_AGG

      market += v
    end
    diff = market - carrying
    return [OK, [market, 0, 0] + empty_set] if diff.zero?
    return bad.call(RANGE) if diff.abs > MAX_AMOUNT

    if diff.positive?
      [OK, [market, diff, 1] + set_out([[2, 0, diff], [4, 1, diff]])]
    else
      [OK, [market, -diff, 2] + set_out([[4, 0, -diff], [2, 1, -diff]])]
    end
  end

  # ---- totals: 20 cells, each [debits, credits], index kind * 5 + account - 1
  def valid_totals?(cells) = cells.all? { |d, c| (0..MAX_CELL).cover?(d) && (0..MAX_CELL).cover?(c) }
  def balanced?(cells) = cells.sum(&:first) == cells.sum(&:last)
  def not_less?(a, b) = a.zip(b).all? { |(ad, ac), (bd, bc)| ad >= bd && ac >= bc }

  def account_side(cells, account, side)
    (0..3).sum { |k| cells[(k * 5) + account - 1][side] }
  end

  def books_sound?(cells)
    account_side(cells, 1, 0) >= account_side(cells, 1, 1) && account_side(cells, 2, 0) >= account_side(cells, 2, 1)
  end

  def zero_totals = Array.new(20) { [0, 0] }
  def flat(cells) = cells.flatten

  def apply_transaction(kind, postings, prev)
    zero = [0] * 40
    return [BAD, zero] unless (0..3).cover?(kind)

    status = validate_postings(postings)
    return [status, zero] unless status == OK
    return [RANGE, zero] unless valid_totals?(prev)
    return [UNBAL, zero] unless balanced?(prev)

    cells = prev.map(&:dup)
    postings.each do |account, side, amount|
      cell = cells[(kind * 5) + account - 1]
      cell[side] += amount
      return [RANGE, zero] if cell[side] > MAX_CELL
    end
    return [NEG, zero] unless books_sound?(cells)

    [OK, flat(cells)]
  end

  def diff_totals(to, from)
    zero = [0] * 40
    return [RANGE, zero] unless valid_totals?(to) && valid_totals?(from)
    return [UNBAL, zero] unless balanced?(to) && balanced?(from)
    return [ORDER, zero] unless not_less?(to, from)

    [OK, flat(to.zip(from).map { |(td, tc), (fd, fc)| [td - fd, tc - fc] })]
  end

  def collapse(cells)
    return [RANGE, [0] * 10] unless valid_totals?(cells)

    [OK, (1..5).flat_map { |a| [account_side(cells, a, 0), account_side(cells, a, 1)] }]
  end

  def audit_chain(rows)
    rows.each_with_index do |row, i|
      return RANGE unless valid_totals?(row)
      return UNBAL unless balanced?(row)
      return NEG unless books_sound?(row)
      return ORDER if i.positive? && !not_less?(row, rows[i - 1])
    end
    OK
  end

  # sums5: [[d, c] x 5]
  def balance_sheet(sums)
    zero = [0] * 7
    return [RANGE, zero] unless sums.all? { |d, c| (0..MAX_AGG).cover?(d) && (0..MAX_AGG).cover?(c) }
    return [UNBAL, zero] unless sums.sum(&:first) == sums.sum(&:last)

    cash = sums[0][0] - sums[0][1]
    holdings = sums[1][0] - sums[1][1]
    return [NEG, zero] if cash.negative? || holdings.negative?

    capital = sums[2][1] - sums[2][0]
    income = (sums[3][1] - sums[3][0]) - (sums[4][0] - sums[4][1])
    [OK, [cash, holdings, cash + holdings, capital, income, capital + income, 0]]
  end

  def income_statement(sums, realized)
    zero = [0] * 5
    return [RANGE, zero] unless sums.all? { |d, c| (0..MAX_AGG).cover?(d) && (0..MAX_AGG).cover?(c) } &&
                                (-MAX_GAIN..MAX_GAIN).cover?(realized)

    gain = sums[3][1] - sums[3][0]
    costs = sums[4][0] - sums[4][1]
    [OK, [realized, gain - realized, gain, costs, gain - costs]]
  end

  def cash_flow(act, opening, closing)
    zero = [0] * 4
    valid = act.all? { |d, c| (0..MAX_AGG).cover?(d) && (0..MAX_AGG).cover?(c) } &&
            (-MAX_AGG..MAX_AGG).cover?(opening) && (-MAX_AGG..MAX_AGG).cover?(closing)
    return [RANGE, zero] unless valid

    net = ->(k, a) { act[(k * 5) + a - 1][0] - act[(k * 5) + a - 1][1] }
    financing = net.call(0, 1)
    investing = -net.call(1, 2) - net.call(2, 2)
    operating = -net.call(1, 5) - net.call(2, 5)
    change = financing + investing + operating
    actual = net.call(0, 1) + net.call(1, 1) + net.call(2, 1) + net.call(3, 1)
    return [NOREC, zero] if change != actual || opening + change != closing

    [OK, [financing, investing, operating, change]]
  end

  def period_report(opening, closing, realized)
    zero = [0] * 23
    status, diff = diff_totals(closing, opening)
    return [status, zero] unless status == OK

    activity = diff.each_slice(2).to_a
    sums = [opening, closing, activity].map { |cells| collapse(cells).last.each_slice(2).to_a }
    s_open, open_sheet = balance_sheet(sums[0]).then { |s, out| [s, out] }
    return [s_open, zero] unless s_open == OK

    s_close, close_sheet = balance_sheet(sums[1])
    return [s_close, zero] unless s_close == OK

    s_inc, income = income_statement(sums[2], realized)
    return [s_inc, zero] unless s_inc == OK

    s_flow, flow = cash_flow(activity, open_sheet[0], close_sheet[0])
    return [s_flow, zero] unless s_flow == OK

    [OK, open_sheet + close_sheet + income + flow]
  end

  # ---- typed transaction kinds (audit E4). Written from the ABI description,
  # not from the engine: the (account, side) cells each kind may post to, and
  # the cell that must be positive. Revalue posts one of two cell pairs.
  KIND_CELLS = {
    0 => [[[1, 0], [3, 1]], [1, 0]], # deposit: Dr Cash / Cr Capital
    1 => [[[2, 0], [5, 0], [1, 1]], [1, 1]], # buy: Dr Holdings, Dr Costs / Cr Cash
    2 => [[[1, 0], [5, 0], [2, 1]], [2, 1]] # sell: Dr Cash, Dr Costs / Cr Holdings
  }.freeze
  REVALUE_GAIN = [[2, 0], [4, 1]].freeze # Dr Holdings / Cr Gain
  REVALUE_LOSS = [[4, 0], [2, 1]].freeze # Dr Gain / Cr Holdings

  def shape_ok?(kind, postings)
    cells = postings.map { |account, side, _amount| [account, side] }
    if kind == 3
      [REVALUE_GAIN, REVALUE_LOSS].any? { |pair| cells.all? { pair.include?(_1) } && pair.all? { cells.include?(_1) } }
    else
      allowed, required = KIND_CELLS.fetch(kind)
      cells.all? { allowed.include?(_1) } && cells.include?(required)
    end
  end

  def apply_typed(kind, postings, prev)
    zero = [0] * 40
    status = validate_postings(postings)
    return [status, zero] unless status == OK
    return [BAD, zero] unless shape_ok?(kind, postings)

    apply_transaction(kind, postings, prev)
  end

  # ---- period report reconciled with the cost basis (audit E2). basis =
  # [realized, basis_at_start, basis_at_end, purchased, consumed]. The report is
  # [opening sheet (7), closing sheet (7), income (5), flow (4)]: holdings is
  # index 1 / 8, the income statement's unrealized gain index 15.
  def period_report_checked(opening, closing, basis)
    zero = [0] * 23
    realized, start_basis, end_basis, purchased, consumed = basis
    return [RANGE, zero] unless [start_basis, end_basis, purchased, consumed].all? { (0..MAX_AGG).cover?(_1) }

    status, report = period_report(opening, closing, realized)
    return [status, zero] unless status == OK

    unrealized = (report[8] - end_basis) - (report[1] - start_basis) # market - basis, at both ends
    return [NOREC, zero] if purchased != consumed + end_basis || report[15] != unrealized

    [OK, report]
  end

  def apply_trade_quantity(held, side, qty)
    return fail_with(BAD, 1) unless (0..1).cover?(side)
    return fail_with(RANGE, 1) unless (0..MAX_HELD).cover?(held) && (1..MAX_QTY).cover?(qty)

    if side.zero?
      held + qty > MAX_HELD ? fail_with(RANGE, 1) : [OK, [held + qty]]
    else
      qty > held ? fail_with(HOLD, 1) : [OK, [held - qty]]
    end
  end

  def portfolio_position(market, basis)
    return fail_with(RANGE, 1) unless (0..MAX_AGG).cover?(market) && (0..MAX_AGG).cover?(basis)

    [OK, [market - basis]]
  end

  def sum(values)
    running = 0
    values.each do |v|
      return fail_with(RANGE, 1) unless (-MAX_AGG..MAX_AGG).cover?(v) && (-MAX_AGG..MAX_AGG).cover?(running + v)

      running += v
    end
    [OK, [running]]
  end

  def split(amount, unit)
    whole, fraction = amount.abs.divmod(unit)
    [OK, [whole, fraction, amount.negative? ? 1 : 0, 0]]
  end

  def negate(x) = x == I64_MIN ? fail_with(RANGE, 1) : [OK, [-x]]

  def scale(value, low, high, size, invert)
    return fail_with(BAD, 1) unless (0..1).cover?(invert) && low <= high
    return fail_with(RANGE, 1) unless (0..MAX_SIZE).cover?(size) && value.between?(low, high)

    raw = high == low ? size / 2 : ((value - low) * size) / (high - low)
    [OK, [invert.zero? ? raw : size - raw]]
  end

  def min_max(values)
    values.empty? ? fail_with(BAD, 2) : [OK, [values.min, values.max]]
  end

  def sample_times(start, finish, capacity)
    n = capacity
    return [BAD, [0, 0] + zeros(n)] if n.zero? || start > finish
    return [RANGE, [0, 0] + zeros(n)] if n > MAX_POINTS || start.negative? || finish > MAX_TIME

    if start == finish || n == 1
      return [OK, [1, 1, finish] + zeros(n - 1)]
    end

    span = finish - start
    intervals = [span, n - 1].min
    step = (span + intervals - 1) / intervals
    last = (span + step - 1) / step
    times = (0..last).map { |i| [start + (i * step), finish].min }
    [OK, [last + 1, step] + times + zeros(n - times.size)]
  end

  def next_price(price, change, max_step, floor, ceiling)
    return fail_with(BAD, 1) if floor > ceiling
    return fail_with(RANGE, 1) unless [price, floor, ceiling].all? { (0..MAX_PRICE).cover?(_1) } &&
                                      (0..MAX_BPS).cover?(max_step) && change.abs <= max_step

    delta = (price * change.abs) / 10_000
    delta = -delta if change.negative?
    [OK, [[[price + delta, ceiling].min, floor].max]]
  end

  def bps_from_random(random, max_step)
    return fail_with(RANGE, 1) unless (0..MAX_BPS).cover?(max_step)

    [OK, [(random % ((2 * max_step) + 1)) - max_step]]
  end

  def ohlc(prices)
    return fail_with(BAD, 6) if prices.empty?
    return fail_with(RANGE, 6) unless prices.all? { (0..MAX_PRICE).cover?(_1) }

    [OK, [prices.first, prices.max, prices.min, prices.last, prices.size, 0]]
  end

  # candles: [[open, high, low, close, ticks, last_as_of], ...]
  def ohlc_merge(candles)
    return fail_with(BAD, 6) if candles.empty?

    ticks = 0
    candles.each do |open, high, low, close, tk, _last|
      return fail_with(RANGE, 6) unless [open, high, low, close].all? { (0..MAX_PRICE).cover?(_1) } && (0..MAX_AGG).cover?(tk)
      return fail_with(BAD, 6) unless low <= open && open <= high && low <= close && close <= high
      return fail_with(RANGE, 6) if ticks + tk > MAX_AGG

      ticks += tk
    end
    [OK, [candles.first[0], candles.map { _1[1] }.max, candles.map { _1[2] }.min, candles.last[3], ticks,
          candles.map(&:last).max]]
  end

  # trades: [[caliber, side, qty, value, time], ...]
  def cost_basis(method, trades, t_start, t_end)
    zero = [0] * 5
    return [BAD, zero] unless (0..1).cover?(method) && t_start <= t_end

    trades.each_with_index do |(caliber, side, qty, value, time), i|
      return [BAD, zero] unless (0..1).cover?(side)
      return [RANGE, zero] unless (1..MAX_QTY).cover?(qty) && (0..MAX_AMOUNT).cover?(value)
      next if i.zero?

      pc, _ps, _pq, _pv, pt = trades[i - 1]
      return [ORDER, zero] if caliber < pc || (caliber == pc && time < pt)
    end

    totals = { start_p: 0, start_c: 0, end_p: 0, end_c: 0, sales: 0 }
    trades.group_by(&:first).sort.each do |_caliber, group|
      seg = method == 1 ? segment_fifo(group, t_start, t_end) : segment_average(group, t_start, t_end)
      return [seg, zero] if seg.is_a?(Integer)

      seg.each { |k, v| totals[k] += v }
    end
    return [RANGE, zero] if totals[:end_p] > MAX_AGG || totals[:sales] > MAX_AGG

    [OK, [totals[:sales] - (totals[:end_c] - totals[:start_c]), totals[:start_p] - totals[:start_c],
          totals[:end_p] - totals[:end_c], totals[:end_p], totals[:end_c]]]
  end

  def segment_average(group, t_start, t_end)
    held = purchased = consumed = basis = sales = 0
    snap = nil
    group.each do |_c, side, qty, value, time|
      snap ||= [purchased, consumed] if time > t_start
      break if time > t_end

      if side.zero?
        return RANGE if held + qty > MAX_HELD || basis + value > MAX_AGG

        held += qty
        purchased += value
        basis += value
      else
        return HOLD if qty > held

        piece = rhu(basis, qty, held)
        held -= qty
        basis -= piece
        consumed += piece
        sales += value if time > t_start
      end
    end
    snap ||= [purchased, consumed]
    { start_p: snap[0], start_c: snap[1], end_p: purchased, end_c: consumed, sales: sales }
  end

  # FIFO by its exact definition: consumed after S units sold is the sum over
  # lots of round_half_up (value * units taken from the lot / lot units).
  def fifo_consumed(lots, sold)
    before = 0
    lots.sum do |qty, value|
      taken = (sold - before).clamp(0, qty)
      before += qty
      rhu(value, taken, qty)
    end
  end

  def segment_fifo(group, t_start, t_end)
    lots = []
    held = sold = sales = 0
    snap = nil
    state = -> { [lots.sum(&:last), fifo_consumed(lots, sold)] }
    group.each do |_c, side, qty, value, time|
      snap ||= state.call if time > t_start
      break if time > t_end

      if side.zero?
        return RANGE if held + qty > MAX_HELD

        held += qty
        lots << [qty, value]
      else
        return HOLD if qty > held

        held -= qty
        sold += qty
        sales += value if time > t_start
      end
    end
    snap ||= state.call
    purchased, consumed = state.call
    { start_p: snap[0], start_c: snap[1], end_p: purchased, end_c: consumed, sales: sales }
  end
end

# ------------------------------------------------------------- marshalling --
module Wire
  module_function

  def i64s(values)
    mem = FFI::MemoryPointer.new(:int64, [values.size, 1].max)
    mem.write_array_of_int64(values) unless values.empty?
    mem
  end

  def read_i64s(mem, count) = mem.read_array_of_int64(count)

  def totals(cells) = i64s(cells.flatten)
  def read_totals(mem) = mem.read_array_of_int64(40)

  # postings => PostingSet bytes; count may be forced for bad-count tests.
  def posting_set(postings, count: postings.size)
    mem = FFI::MemoryPointer.new(:int8, 264)
    mem.put_int32(0, count)
    postings.first(16).each_with_index do |(account, side, amount), i|
      mem.put_int32(8 + (i * 16), account)
      mem.put_int32(12 + (i * 16), side)
      mem.put_int64(16 + (i * 16), amount)
    end
    mem
  end

  def read_set(mem)
    out = [mem.get_int32(0), mem.get_int32(4)]
    16.times do |i|
      out << mem.get_int32(8 + (i * 16)) << mem.get_int32(12 + (i * 16)) << mem.get_int64(16 + (i * 16))
    end
    out
  end

  def postings_array(postings)
    mem = FFI::MemoryPointer.new(:int8, [postings.size, 1].max * 16)
    postings.each_with_index do |(account, side, amount), i|
      mem.put_int32(i * 16, account)
      mem.put_int32((i * 16) + 4, side)
      mem.put_int64((i * 16) + 8, amount)
    end
    mem
  end

  def trades(list)
    mem = FFI::MemoryPointer.new(:int8, [list.size, 1].max * 32)
    list.each_with_index do |(caliber, side, qty, value, time), i|
      mem.put_int32(i * 32, caliber)
      mem.put_int32((i * 32) + 4, side)
      mem.put_int64((i * 32) + 8, qty)
      mem.put_int64((i * 32) + 16, value)
      mem.put_int64((i * 32) + 24, time)
    end
    mem
  end

  def out(count) = FFI::MemoryPointer.new(:int64, count)
end

# -------------------------------------------------------------- generators --
class Gen
  def initialize(seed) = reseed(seed)
  def reseed(seed) = (@r = Random.new(seed))

  def int(range) = @r.rand(range)
  def pick(list) = list[@r.rand(list.size)]
  def chance(percent) = @r.rand(100) < percent

  # An integer near a bound (or in the middle) of lo..hi, sometimes outside.
  def near(lo, hi, outside: 25)
    case @r.rand(100)
    when 0...30 then pick([lo, lo + 1, hi, hi - 1, (lo + hi) / 2, 0, 1].select { |v| v.between?(lo, hi) }.then { |l| l.empty? ? [lo] : l })
    when 30...(30 + outside)
      pick([lo - 1, hi + 1, lo - 1 - int(0..1000), hi + 1 + int(0..1000), I64_MIN, I64_MAX])
        .clamp(I64_MIN, I64_MAX)
    else int(lo..hi)
    end
  end

  def mostly(lo, hi) = near(lo, hi, outside: 8)

  def small(lo, hi) = int(lo..hi)

  def log_int(max) = int(0..max) >> int(0..Math.log2(max + 1).floor)

  def totals_cell(max) = pick([0, 1, max, max - 1, max + 1, int(0..max), log_int(max), int(0..max)])
end

GEN = Gen.new(SEED)

# ----------------------------------------------------------------- harness --
$failures = 0
$checks = 0
$per_function = Hash.new(0)

def check(name, inputs, got, want)
  $checks += 1
  $per_function[name] += 1
  return if got == want

  $failures += 1
  warn "MISMATCH #{name}\n  inputs: #{inputs.inspect}\n  engine: #{got.inspect}\n  ref:    #{want.inspect}" if $failures <= 25
end

# Random balanced posting lists (valid or deliberately broken).
def random_postings(allow_bad: true)
  n = GEN.pick([2, 2, 2, 3, 3, 4, 6])
  lines = []
  total = GEN.pick([1, 5, 100, 177_600, GEN.small(1, 10**6), GEN.log_int(MAX_AMOUNT).clamp(1, MAX_AMOUNT)])
  parts = Array.new(n - 1) { GEN.small(1, total) }.sort
  amounts = [0] + parts + [total]
  deltas = amounts.each_cons(2).map { |a, b| b - a }.reject(&:zero?)
  deltas = [total] if deltas.empty?
  debit = deltas.map { |d| [GEN.small(1, 5), 0, d] }
  credit = deltas.map { |d| [GEN.small(1, 5), 1, d] }
  lines = debit + credit
  lines = lines.shuffle(random: Random.new(GEN.int(0..10**6)))
  return lines unless allow_bad && GEN.chance(25)

  case GEN.int(0..6)
  when 0 then lines[0] = [GEN.pick([0, 6, -1]), lines[0][1], lines[0][2]]
  when 1 then lines[0] = [lines[0][0], GEN.pick([2, -1]), lines[0][2]]
  when 2 then lines[0] = [lines[0][0], lines[0][1], GEN.pick([0, -5])]
  when 3 then lines[0] = [lines[0][0], lines[0][1], MAX_AMOUNT + 1]
  when 4 then lines[0][2] += 1
  when 5 then lines = lines * 5 if lines.size > 3
  else lines = []
  end
  lines
end

def kind_postings_set
  case GEN.int(0..3)
  when 0 then Ref.build_deposit(GEN.small(1, 10**7)).last
  when 1 then Ref.build_buy(*buy_quote(true)).last
  when 2 then Ref.build_sell(*sell_quote(true)).last
  else Ref.revalue([GEN.small(0, 10**6)], GEN.small(0, 10**6)).last.drop(3)
  end
end

TYPED_EXPORTS = { 0 => :apply_deposit, 1 => :apply_buy, 2 => :apply_sell, 3 => :apply_revalue }.freeze

# A posting list built by the reference builders for a random kind: [kind, postings].
def kinded_postings
  kind = GEN.int(0..3)
  set = case kind
        when 0 then Ref.build_deposit(GEN.small(1, 10**7)).last
        when 1 then Ref.build_buy(*buy_quote(true)).last
        when 2 then Ref.build_sell(*sell_quote(true)).last
        else Ref.revalue([GEN.small(0, 10**6)], GEN.small(0, 10**6)).last.drop(3)
        end
  [kind, set.drop(2).each_slice(3).first(set[0])]
end

def buy_quote(consistent)
  value = GEN.near(0, MAX_AMOUNT, outside: consistent ? 0 : 10)
  spread = GEN.near(0, 10**9, outside: 0).clamp(0, MAX_AMOUNT)
  fee = GEN.near(0, 10**9, outside: 0).clamp(0, MAX_AMOUNT)
  costs = spread + fee
  total = value + costs
  return [value, spread, fee, costs, total] if consistent

  case GEN.int(0..3)
  when 0 then [value, spread, fee, costs + 1, total + 1]
  when 1 then [value, spread, fee, costs, total + 1]
  when 2 then [value, spread, fee, costs, total - 1]
  else [value, spread, fee, costs, total]
  end
end

def sell_quote(consistent)
  value = GEN.near(0, MAX_AMOUNT, outside: consistent ? 0 : 10)
  spread = GEN.small(0, 1000)
  fee = GEN.small(0, 1000)
  spread = [spread, value].min
  fee = [fee, value - spread].min
  costs = spread + fee
  net = value - costs
  return [value, spread, fee, costs, net] if consistent

  case GEN.int(0..3)
  when 0 then [value, spread, fee, costs + 1, net]
  when 1 then [value, spread, fee, costs, net + 1]
  when 2 then [value, spread, fee, costs, -1]
  else [value, spread, fee, costs, net]
  end
end

# Valid balanced running totals, built through the reference engine.
def random_totals
  cells = Ref.zero_totals
  GEN.int(0..6).times do
    status, flat = Ref.apply_transaction(GEN.int(0..3), random_postings(allow_bad: false), cells)
    cells = flat.each_slice(2).to_a if status == OK
  end
  cells
end

def corrupt(cells)
  cells = cells.map(&:dup)
  case GEN.int(0..4)
  when 0 then cells[GEN.int(0..19)][GEN.int(0..1)] = MAX_CELL + 1
  when 1 then cells[GEN.int(0..19)][GEN.int(0..1)] = -1
  when 2 then cells[GEN.int(0..19)][GEN.int(0..1)] += GEN.small(1, 50)
  when 3 then cells[GEN.int(0..19)][GEN.int(0..1)] = MAX_CELL
  else cells[GEN.int(0..19)][GEN.int(0..1)] = GEN.totals_cell(MAX_CELL)
  end
  cells
end

def any_totals
  cells = random_totals
  GEN.chance(25) ? corrupt(cells) : cells
end

def chain_rows
  rows = []
  cells = Ref.zero_totals
  GEN.int(0..4).times do
    status, flat = Ref.apply_transaction(GEN.int(0..3), random_postings(allow_bad: false), cells)
    next unless status == OK

    cells = flat.each_slice(2).to_a
    rows << cells
  end
  rows = rows.shuffle(random: Random.new(GEN.int(0..1000))) if GEN.chance(15) && rows.size > 1
  rows[GEN.int(0..rows.size)] = corrupt(random_totals) if GEN.chance(15) && !rows.empty?
  rows.map { |r| r.map(&:dup) }
end

def random_trades
  calibers = Array.new(GEN.int(1..3)) { GEN.pick([1, 2, 7, 9, 30, -4]) }.uniq.sort
  trades = []
  calibers.each do |caliber|
    held = 0
    time = GEN.int(0..20)
    GEN.int(0..9).times do
      time += GEN.pick([0, 1, 5, 10])
      if held.zero? || GEN.chance(55)
        qty = GEN.pick([1, 3, 100, GEN.small(1, 1000), GEN.log_int(MAX_QTY).clamp(1, MAX_QTY)])
        value = GEN.pick([0, 1, 33, GEN.small(0, 100_000), GEN.log_int(MAX_AMOUNT)])
        held += qty
        trades << [caliber, 0, qty, value, time]
      else
        qty = GEN.chance(20) ? held : GEN.small(1, held)
        qty += 1 if GEN.chance(4)
        held = [held - qty, 0].max
        trades << [caliber, 1, qty, GEN.pick([0, 1, 40, GEN.small(0, 100_000), GEN.log_int(MAX_AMOUNT)]), time]
      end
    end
  end
  trades = trades.shuffle(random: Random.new(GEN.int(0..1000))) if GEN.chance(6)
  trades[GEN.int(0...trades.size)] = [1, GEN.pick([2, -1]), 5, 5, 5] if GEN.chance(3) && !trades.empty?
  trades[GEN.int(0...trades.size)][2] = GEN.pick([0, MAX_QTY + 1]) if GEN.chance(3) && !trades.empty?
  trades
end

# Many calibers (including negative codes), 4..45 trades each, sells never exceed the
# holding, values near qty * price. Valid input: both methods must agree with the reference.
def random_trades_large
  calibers = Array.new(GEN.int(3..9)) { GEN.pick([-7, -1, 0, 1, 2, 3, 5, 7, 9, 12, 30, 99]) }.uniq.sort
  calibers.flat_map do |caliber|
    held = 0
    time = GEN.int(0..30)
    price = GEN.int(50..5000)
    Array.new(GEN.int(4..45)) do
      time += GEN.pick([0, 0, 1, 2, 7])
      price = [price + GEN.int(-300..300), 50].max
      if held < 2 || GEN.chance(52)
        qty = GEN.pick([1, 2, 10, 50, GEN.small(1, 2000)])
        held += qty
        [caliber, 0, qty, Ref.rhu(qty, price, 100) + GEN.pick([0, 0, 0, 1, 40]), time]
      else
        qty = GEN.chance(15) ? held : GEN.small(1, held)
        held -= qty
        [caliber, 1, qty, Ref.rhu(qty, price, 100), time]
      end
    end
  end
end

# ------------------------------------------------------------------- tests --
def status_and(mem_out, status, count)
  [status, mem_out ? Wire.read_i64s(mem_out, count) : []]
end

check("engine_version", [], Engine.engine_version, 300)

# Audit E9: no subprogram called by the C shim has a Pre (contracts are compiled out), and no
# pragma Assume/Annotate/Suppress. See check_contract_boundary.rb.
check("contract boundary", [], ContractBoundary.violations(File.expand_path("../../src", __dir__)), [])

current_seed = nil
SEEDS.flat_map { |seed| Array.new(N, seed) }.each do |seed|
  GEN.reseed(current_seed = seed) unless seed == current_seed

  # ---- quotes
  qty = GEN.near(0, MAX_QTY)
  price = GEN.near(0, MAX_PRICE)
  out = Wire.out(1)
  check("market_value", [qty, price], status_and(out, Engine.market_value(qty, price, out), 1),
        Ref.market_value(qty, price))

  qty = GEN.mostly(0, MAX_QTY)
  price = GEN.mostly(0, MAX_PRICE)
  sb = GEN.near(0, MAX_BPS, outside: 10)
  fb = GEN.near(0, MAX_BPS, outside: 10)
  cash = GEN.pick([I64_MAX, 0, GEN.int(0..MAX_AMOUNT * 2), GEN.near(0, MAX_AMOUNT), -1])
  out = Wire.out(5)
  got = status_and(out, Engine.quote_buy(qty, price, sb, fb, cash, out), 5)
  want = Ref.quote_buy(qty, price, sb, fb, cash)
  if want.first == OK && GEN.chance(60)
    cash = i64(want.last[4] + GEN.pick([-1, 0, 1]))
    out = Wire.out(5)
    got = status_and(out, Engine.quote_buy(qty, price, sb, fb, cash, out), 5)
    want = Ref.quote_buy(qty, price, sb, fb, cash)
  end
  check("quote_buy", [qty, price, sb, fb, cash], got, want)

  held = i64(GEN.pick([qty, qty - 1, qty + 1, GEN.near(0, MAX_QTY), -1, GEN.int(0..MAX_QTY)]))
  out = Wire.out(5)
  check("quote_sell", [qty, held, price, sb, fb], status_and(out, Engine.quote_sell(qty, held, price, sb, fb, out), 5),
        Ref.quote_sell(qty, held, price, sb, fb))
  if GEN.chance(50) # rates that make costs exceed value
    sb2 = GEN.pick([10_000, 9_999, 5_000])
    fb2 = GEN.pick([10_000, 1, 5_000])
    out = Wire.out(5)
    check("quote_sell", [qty, held, price, sb2, fb2],
          status_and(out, Engine.quote_sell(qty, held, price, sb2, fb2, out), 5),
          Ref.quote_sell(qty, held, price, sb2, fb2))
  end

  # ---- validate_transaction
  postings = random_postings
  postings = [[1, 0, 5]] * GEN.int(17..18) if GEN.chance(3)
  buf = Wire.postings_array(postings)
  check("validate_transaction", postings, [Engine.validate_transaction(postings.size, buf)],
        [Ref.validate_postings(postings)])

  # ---- builders
  cents = GEN.near(1, MAX_AMOUNT)
  out = Wire.posting_set([])
  got = [Engine.build_deposit(cents, out), Wire.read_set(out)]
  check("build_deposit", [cents], got, Ref.build_deposit(cents))

  quote = buy_quote(GEN.chance(70))
  quote[GEN.int(0..4)] = GEN.pick([-1, MAX_AMOUNT + 1, 0]) if GEN.chance(8)
  quote.map! { i64(_1) }
  qmem = Wire.i64s(quote)
  out = Wire.posting_set([])
  check("build_buy", quote, [Engine.build_buy(qmem, out), Wire.read_set(out)], Ref.build_buy(*quote))

  quote = sell_quote(GEN.chance(70))
  quote[GEN.int(0..4)] = GEN.pick([-1, MAX_AMOUNT + 1, 0]) if GEN.chance(8)
  quote.map! { i64(_1) }
  qmem = Wire.i64s(quote)
  out = Wire.posting_set([])
  check("build_sell", quote, [Engine.build_sell(qmem, out), Wire.read_set(out)], Ref.build_sell(*quote))

  values = Array.new(GEN.int(0..5)) { GEN.pick([GEN.mostly(0, MAX_AMOUNT), GEN.int(0..10**6), MAX_AMOUNT]) }
  carrying = GEN.pick([values.sum, values.sum + GEN.int(1..1000), [values.sum - GEN.int(1..1000), 0].max,
                       GEN.near(0, MAX_AGG), GEN.near(0, MAX_AMOUNT)])
  carrying = i64(carrying)
  info = Wire.out(3)
  out = Wire.posting_set([])
  eng = Engine.revalue(values.size, Wire.i64s(values), carrying, info, out)
  got = [eng, Wire.read_i64s(info, 3) + Wire.read_set(out)]
  check("revalue", [values, carrying], got, Ref.revalue(values, carrying))

  # ---- running totals
  prev = any_totals
  kind = GEN.pick([0, 1, 2, 3, 3, 4, -1])
  postings = GEN.chance(60) ? random_postings : kind_postings_set.then { |s| s.drop(2).each_slice(3).first(s[0]) }
  set_count = GEN.chance(3) ? GEN.pick([0, 17, -1]) : postings.size
  nxt = Wire.out(40)
  eng = Engine.apply_transaction(kind, Wire.posting_set(postings, count: set_count), Wire.totals(prev), nxt)
  want = set_count == postings.size ? Ref.apply_transaction(kind, postings, prev) : [BAD, [0] * 40]
  check("apply_transaction", [kind, postings, prev, set_count], [eng, Wire.read_totals(nxt)], want)

  # typed entry points: the kind is implied by the export and the postings must have its shape
  typed = GEN.int(0..3)
  prev = any_totals
  real_kind, postings = kinded_postings
  typed = real_kind if GEN.chance(60) # mostly the right kind, sometimes a mislabelled one
  postings = random_postings if GEN.chance(10)
  nxt = Wire.out(40)
  eng = Engine.public_send(TYPED_EXPORTS.fetch(typed), Wire.posting_set(postings), Wire.totals(prev), nxt)
  check("apply_#{TYPED_EXPORTS.fetch(typed).to_s.delete_prefix('apply_')}", [postings, prev],
        [eng, Wire.read_totals(nxt)], Ref.apply_typed(typed, postings, prev))

  to = any_totals
  from = GEN.chance(50) ? random_totals : to.map(&:dup)
  from = to.map { |d, c| [[d - GEN.int(0..3), 0].max, [c - GEN.int(0..3), 0].max] } if GEN.chance(30)
  out = Wire.out(40)
  eng = Engine.diff_totals(Wire.totals(to), Wire.totals(from), out)
  check("diff_totals", [to, from], [eng, Wire.read_totals(out)], Ref.diff_totals(to, from))

  cells = any_totals
  out = Wire.out(10)
  check("collapse_kinds", cells, [Engine.collapse_kinds(Wire.totals(cells), out), Wire.read_i64s(out, 10)],
        Ref.collapse(cells))

  rows = chain_rows
  check("audit_chain", rows, [Engine.audit_chain(rows.size, Wire.i64s(rows.flatten.flatten))], [Ref.audit_chain(rows)])

  opening = random_totals
  closing = GEN.chance(70) ? opening.dup : random_totals
  if GEN.chance(60)
    status, flat = Ref.apply_transaction(GEN.int(0..3), random_postings(allow_bad: false), closing)
    closing = flat.each_slice(2).to_a if status == OK
  end
  opening = corrupt(opening) if GEN.chance(8)
  realized = GEN.near(-MAX_GAIN, MAX_GAIN, outside: 6)
  out = Wire.out(23)
  eng = Engine.period_report(Wire.totals(opening), Wire.totals(closing), realized, out)
  check("period_report", [opening, closing, realized], [eng, Wire.read_i64s(out, 23)],
        Ref.period_report(opening, closing, realized))

  # reconciled with a cost basis report: random reports mostly disagree with the ledger, so
  # also feed the exact split the ledger implies (the realized/unrealized pair that does reconcile)
  basis = [realized, GEN.near(0, MAX_AGG, outside: 8), GEN.near(0, MAX_AGG, outside: 8), 0, 0]
  basis[4] = GEN.near(0, MAX_AGG, outside: 8)
  basis[3] = GEN.chance(60) ? i64(basis[4] + basis[2]) : GEN.near(0, MAX_AGG, outside: 8)
  want_status, want_report = Ref.period_report(opening, closing, 0)
  if want_status == OK && GEN.chance(70)
    gain = want_report[16] # trading gain total of the period
    basis[1] = GEN.small(0, 10**6)
    basis[2] = GEN.small(0, 10**6)
    basis[0] = gain - ((want_report[8] - basis[2]) - (want_report[1] - basis[1])) # makes the split reconcile
    basis[4] = GEN.small(0, 10**6)
    basis[3] = basis[4] + basis[2]
  end
  basis = basis.map { i64(_1) }
  out = Wire.out(23)
  eng = Engine.period_report_checked(Wire.totals(opening), Wire.totals(closing), Wire.i64s(basis), out)
  check("period_report_checked", [opening, closing, basis], [eng, Wire.read_i64s(out, 23)],
        Ref.period_report_checked(opening, closing, basis))

  # ---- reports (from the five account totals / activity)
  sums = Array.new(5) { [GEN.totals_cell(MAX_AGG), GEN.totals_cell(MAX_AGG)] }
  if GEN.chance(70) # make it balanced and plausible
    status, collapsed = Ref.collapse(random_totals)
    sums = collapsed.each_slice(2).to_a if status == OK
    sums[GEN.int(0..4)][GEN.int(0..1)] += GEN.pick([0, 0, 0, 1, -1]) if GEN.chance(20)
  end
  out = Wire.out(7)
  check("balance_sheet", sums, [Engine.balance_sheet(Wire.i64s(sums.flatten), out), Wire.read_i64s(out, 7)],
        Ref.balance_sheet(sums))
  realized = GEN.near(-MAX_GAIN, MAX_GAIN, outside: 6)
  out = Wire.out(5)
  check("income_statement", [sums, realized],
        [Engine.income_statement(Wire.i64s(sums.flatten), realized, out), Wire.read_i64s(out, 5)],
        Ref.income_statement(sums, realized))

  act = any_totals
  act = Array.new(20) { [GEN.totals_cell(MAX_AGG), GEN.totals_cell(MAX_AGG)] } if GEN.chance(8)
  opening_cash = GEN.pick([0, GEN.near(-MAX_AGG, MAX_AGG)])
  net_cash = (0..3).sum { |k| act[(k * 5)][0] - act[(k * 5)][1] }
  closing_cash = i64(GEN.pick([opening_cash + net_cash, opening_cash + net_cash + 1, GEN.near(-MAX_AGG, MAX_AGG)]))
  out = Wire.out(4)
  check("cash_flow", [act, opening_cash, closing_cash],
        [Engine.cash_flow(Wire.totals(act), opening_cash, closing_cash, out), Wire.read_i64s(out, 4)],
        Ref.cash_flow(act, opening_cash, closing_cash))

  # ---- holdings
  held = GEN.near(0, MAX_HELD)
  side = GEN.pick([0, 1, 0, 1, 2, -1])
  qty = i64(GEN.pick([GEN.near(1, MAX_QTY), held, held + 1, 1]))
  out = Wire.out(1)
  check("apply_trade_quantity", [held, side, qty], status_and(out, Engine.apply_trade_quantity(held, side, qty, out), 1),
        Ref.apply_trade_quantity(held, side, qty))

  market = GEN.near(0, MAX_AGG)
  basis = GEN.near(0, MAX_AGG)
  out = Wire.out(1)
  check("portfolio_position", [market, basis], status_and(out, Engine.portfolio_position(market, basis, out), 1),
        Ref.portfolio_position(market, basis))

  values = Array.new(GEN.int(0..6)) { GEN.pick([GEN.near(-MAX_AGG, MAX_AGG), GEN.int(-10**6..10**6), MAX_AGG, -MAX_AGG]) }
  out = Wire.out(1)
  check("sum", values, status_and(out, Engine.sum(values.size, Wire.i64s(values), out), 1), Ref.sum(values))

  # ---- cost basis
  trades = random_trades
  method = GEN.pick([0, 1, 0, 1, 2, -1])
  t_end = GEN.pick([GEN.int(0..200), 1_000_000, 10, 25])
  t_start = GEN.pick([0, GEN.int(0..t_end), t_end, t_end + 1])
  out = Wire.out(5)
  eng = Engine.cost_basis(method, trades.size, Wire.trades(trades), t_start, t_end, out)
  check("cost_basis", [method, trades, t_start, t_end], [eng, Wire.read_i64s(out, 5)],
        Ref.cost_basis(method, trades, t_start, t_end))

  # larger, mixed-caliber histories (valid sells, realistic values), both methods, several windows
  trades = random_trades_large
  last_time = trades.empty? ? 0 : trades.map(&:last).max
  [0, 1].each do |m|
    t_end = GEN.pick([last_time, GEN.int(0..last_time + 1), last_time + 5])
    t_start = GEN.pick([0, GEN.int(0..t_end), t_end])
    out = Wire.out(5)
    eng = Engine.cost_basis(m, trades.size, Wire.trades(trades), t_start, t_end, out)
    check("cost_basis large", [m, trades.size, t_start, t_end], [eng, Wire.read_i64s(out, 5)],
          Ref.cost_basis(m, trades, t_start, t_end))
  end

  # ---- display
  cents = GEN.pick([GEN.near(I64_MIN, I64_MAX, outside: 0), GEN.int(-10**6..10**6), I64_MIN, I64_MAX, 0, -1])
  [[:split_money, 100], [:split_price, 10_000]].each do |name, unit|
    out = FFI::MemoryPointer.new(:int8, 24)
    eng = Engine.public_send(name, cents, out)
    got = [eng, out.read_array_of_int64(2) + [out.get_int32(16), out.get_int32(20)]]
    check(name.to_s, [cents], got, Ref.split(cents, unit))
  end
  out = Wire.out(1)
  check("negate", [cents], status_and(out, Engine.negate(cents, out), 1), Ref.negate(cents))

  low = GEN.pick([GEN.near(I64_MIN, I64_MAX, outside: 0), GEN.int(-1000..1000), 0])
  high = GEN.pick([low, low + 1, GEN.int(low..[low + 10**6, I64_MAX].min), [low + GEN.int(0..2**40), I64_MAX].min,
                   GEN.chance(5) ? I64_MAX : low])
  high = i64(high)
  high = i64(low - 1) if GEN.chance(3)
  value = GEN.pick([low, high, (low + high) / 2, GEN.int([low, high].min..[low, high].max), low - 1, high + 1].map { _1.clamp(I64_MIN, I64_MAX) })
  size = GEN.near(0, MAX_SIZE, outside: 8)
  invert = GEN.pick([0, 1, 0, 1, 2, -1])
  out = Wire.out(1)
  check("scale", [value, low, high, size, invert], status_and(out, Engine.scale(value, low, high, size, invert, out), 1),
        Ref.scale(value, low, high, size, invert))

  values = Array.new(GEN.int(0..7)) { GEN.near(I64_MIN, I64_MAX, outside: 0) }
  out = Wire.out(2)
  check("min_max", values, status_and(out, Engine.min_max(values.size, Wire.i64s(values), out), 2), Ref.min_max(values))

  start = GEN.pick([GEN.int(0..2_000_000_000), 0, GEN.near(0, MAX_TIME), -1])
  finish = GEN.pick([start, start + 1, start + GEN.int(0..200), start + GEN.int(0..100_000), start + 86_400,
                     GEN.near(0, MAX_TIME), MAX_TIME, MAX_TIME + 1, start - 1])
  start = i64(start)
  finish = i64(finish)
  capacity = GEN.pick([0, 1, 2, 3, 5, 11, 200, GEN.int(1..300), 1000])
  times = Wire.out([capacity, 1].max)
  count = FFI::MemoryPointer.new(:int32)
  step = Wire.out(1)
  eng = Engine.sample_times(start, finish, capacity, times, count, step)
  got = [eng, [count.read_int32, step.read_int64] + (capacity.zero? ? [] : Wire.read_i64s(times, capacity))]
  check("sample_times", [start, finish, capacity], got, Ref.sample_times(start, finish, capacity))

  # ---- prices
  price = GEN.near(0, MAX_PRICE)
  max_step = GEN.pick([200, GEN.near(0, MAX_BPS, outside: 8), 0, MAX_BPS])
  change = i64(GEN.pick([GEN.int(-max_step.clamp(0, MAX_BPS)..max_step.clamp(0, MAX_BPS)), max_step, -max_step,
                         max_step + 1, -max_step - 1, 0]))
  floor = GEN.pick([0, 100, GEN.near(0, MAX_PRICE), GEN.int(0..MAX_PRICE)])
  ceiling = GEN.pick([100_000, MAX_PRICE, GEN.near(0, MAX_PRICE), GEN.int(floor.clamp(0, MAX_PRICE)..MAX_PRICE)])
  out = Wire.out(1)
  check("next_price", [price, change, max_step, floor, ceiling],
        status_and(out, Engine.next_price(price, change, max_step, floor, ceiling, out), 1),
        Ref.next_price(price, change, max_step, floor, ceiling))

  random = GEN.pick([0, 1, 2**64 - 1, GEN.int(0..(2**64) - 1), GEN.int(0..1000), 2**63])
  ms = GEN.pick([200, 0, 1, MAX_BPS, MAX_BPS + 1, -1, GEN.int(0..MAX_BPS)])
  out = Wire.out(1)
  check("bps_from_random", [random, ms], status_and(out, Engine.bps_from_random(random, ms, out), 1),
        Ref.bps_from_random(random, ms))

  prices = Array.new(GEN.int(0..6)) { GEN.near(0, MAX_PRICE, outside: 6) }
  out = Wire.out(6)
  check("ohlc", prices, status_and(out, Engine.ohlc(prices.size, Wire.i64s(prices), out), 6), Ref.ohlc(prices))

  candles = Array.new(GEN.int(0..4)) do
    low = GEN.near(0, MAX_PRICE, outside: 3)
    high = [low + GEN.int(0..50), MAX_PRICE].min
    high = low if high < low
    open = GEN.int(low..high)
    close = GEN.int(low..high)
    [open, high, low, close, GEN.pick([1, 3, GEN.int(0..1000), MAX_AGG, MAX_AGG - 1, -1]), GEN.near(0, 2_000_000_000)]
  end
  candles[GEN.int(0...candles.size)][GEN.int(0..3)] += GEN.pick([-100, 100]) if GEN.chance(6) && !candles.empty?
  candles = candles.map { |c| c.map { i64(_1) } }
  out = Wire.out(6)
  check("ohlc_merge", candles,
        status_and(out, Engine.ohlc_merge(candles.size, Wire.i64s(candles.flatten), out), 6), Ref.ohlc_merge(candles))
end

# ------------------------------------------------ economic / flow properties --
# Drives the engine exactly as the Rails app does (quote -> build -> typed apply, revalue on
# a tick, cost basis, reconciled period report) and checks the books against an independent
# Ruby model of the same user (cash, holdings and market value tracked directly from the
# trades), not against the engine's own reports.
module Sim
  module_function

  CALIBERS = [1, 2, 7].freeze
  RATES = [[50, 100], [50, 100], [0, 0], [0, 100], [0, 1], [50, 0], [10, 10], [100, 0]].freeze

  def apply(kind, set_mem, totals)
    out = Wire.out(40)
    status = Engine.public_send(TYPED_EXPORTS.fetch(kind), set_mem, Wire.totals(totals), out)
    [status, Wire.read_totals(out).each_slice(2).to_a]
  end

  # [status, 7 balance sheet numbers] of running totals, through collapse_kinds like Rails does
  def sheet(totals)
    sums = Wire.out(10)
    status = Engine.collapse_kinds(Wire.totals(totals), sums)
    return [status, []] unless status == OK

    out = Wire.out(7)
    [Engine.balance_sheet(sums, out), Wire.read_i64s(out, 7)]
  end

  def market_values(held, price)
    CALIBERS.map do |c|
      out = Wire.out(1)
      raise "market_value failed" unless Engine.market_value(held[c], price[c], out) == OK

      Wire.read_i64s(out, 1).first
    end
  end

  def deposit(state, cents)
    set = Wire.posting_set([])
    raise "build_deposit" unless Engine.build_deposit(cents, set) == OK

    status, state[:totals] = apply(0, set, state[:totals])
    raise "apply_deposit #{status}" unless status == OK

    state[:cash] += cents
    state[:deposited] += cents
  end

  def trade(state, caliber, side, qty, rates)
    price = state[:price][caliber]
    out = Wire.out(5)
    if side.zero?
      status = Engine.quote_buy(qty, price, *rates, state[:cash], out)
      want = Ref.quote_buy(qty, price, *rates, state[:cash])
    else
      status = Engine.quote_sell(qty, state[:held][caliber], price, *rates, out)
      want = Ref.quote_sell(qty, state[:held][caliber], price, *rates)
    end
    quote = Wire.read_i64s(out, 5)
    check("sim quote", [side, qty, price, rates], [status, quote], want)
    return unless status == OK

    set = Wire.posting_set([])
    builder = side.zero? ? :build_buy : :build_sell
    raise "#{builder} failed" unless Engine.public_send(builder, Wire.i64s(quote), set) == OK

    applied, state[:totals] = apply(side.zero? ? 1 : 2, set, state[:totals])
    raise "apply failed #{applied}" unless applied == OK

    state[:held][caliber] += side.zero? ? qty : -qty
    state[:cash] += side.zero? ? -quote[4] : quote[4]
    state[:costs] += quote[3]
    state[:trades] << [caliber, side, qty, quote[0], state[:t]]
  end

  # Marks the holdings to market through the engine and records a snapshot of the books.
  def tick(state)
    values = market_values(state[:held], state[:price])
    carrying = sheet(state[:totals]).last[1]
    info = Wire.out(3)
    set = Wire.posting_set([])
    status = Engine.revalue(values.size, Wire.i64s(values), carrying, info, set)
    raise "revalue failed #{status}" unless status == OK

    if Wire.read_i64s(info, 3)[2].positive?
      applied, state[:totals] = apply(3, set, state[:totals])
      raise "apply_revalue failed #{applied}" unless applied == OK
    end
    market = CALIBERS.sum { Ref.rhu(state[:held][_1], state[:price][_1], 100) } # the model's own market value
    status, books = sheet(state[:totals])
    check("sim marked to market", [state[:t]], [status, books[0], books[1]], [OK, state[:cash], market])
    state[:snaps] << { t: state[:t], totals: state[:totals], market: market, cash: state[:cash],
                       deposited: state[:deposited], costs: state[:costs] }
  end

  def run(walk:)
    rates = GEN.pick(RATES)
    state = { totals: Ref.zero_totals, held: CALIBERS.to_h { [_1, 0] }, price: CALIBERS.to_h { [_1, GEN.int(50..3000)] },
              cash: 0, deposited: 0, costs: 0, trades: [], t: 0, snaps: [] }
    state[:snaps] << { t: 0, totals: state[:totals], market: 0, cash: 0, deposited: 0, costs: 0 }
    state[:t] += 1
    deposit(state, GEN.int(10_000..400_000))
    GEN.int(10..70).times do
      state[:t] += GEN.int(1..4)
      case GEN.int(0..99)
      when 0...34 then trade(state, GEN.pick(CALIBERS), 0, GEN.pick([1, 1, 2, 5, 40, 300]), rates)
      when 34...64 then trade(state, GEN.pick(CALIBERS), 1, GEN.pick([1, 1, 2, 5, 40, 300]), rates)
      when 64...72 then deposit(state, GEN.int(100..50_000))
      else
        state[:price].transform_values! { |p| walk ? (p + GEN.int(-250..250)).clamp(50, 20_000) : p }
        tick(state)
      end
    end
    state[:t] += 1
    tick(state)
    [state, rates]
  end

  def cost_basis(method, trades, t_start, t_end)
    ordered = trades.each_with_index.sort_by { |(caliber, _s, _q, _v, time), i| [caliber, time, i] }.map(&:first)
    out = Wire.out(5)
    [Engine.cost_basis(method, ordered.size, Wire.trades(ordered), t_start, t_end, out), Wire.read_i64s(out, 5), ordered]
  end

  def verify(state, rates)
    snaps = state[:snaps]
    3.times do
      i = GEN.int(0...snaps.size)
      j = GEN.int(i...snaps.size)
      open_snap = snaps[i]
      close_snap = snaps[j]
      method = GEN.int(0..1)
      status, basis, ordered = cost_basis(method, state[:trades], open_snap[:t], close_snap[:t])
      check("sim cost_basis", [method, open_snap[:t], close_snap[:t], rates],
            [status, basis], Ref.cost_basis(method, ordered, open_snap[:t], close_snap[:t]))
      report_out = Wire.out(23)
      status = Engine.period_report_checked(Wire.totals(open_snap[:totals]), Wire.totals(close_snap[:totals]),
                                            Wire.i64s(basis), report_out)
      # the engine's own split must reconcile with the ledger
      check("sim period reconciles", [method, i, j, rates], [status], [OK])
      next unless status == OK

      report = Wire.read_i64s(report_out, 23)
      realized, start_basis, end_basis = basis
      # the market value comes from the simulation, not from the ledger or the engine
      unrealized = (close_snap[:market] - end_basis) - (open_snap[:market] - start_basis)
      check("sim ledger gain = realized + unrealized (independent market)", [method, i, j, rates],
            [report[16], report[14], report[15]], [realized + unrealized, realized, unrealized])
      check("sim closing books = model", [i, j], [report[7], report[8], report[9]],
            [close_snap[:cash], close_snap[:market], close_snap[:cash] + close_snap[:market]])
      check("sim opening books = model", [i, j], [report[0], report[1]], [open_snap[:cash], open_snap[:market]])
      deposits = close_snap[:deposited] - open_snap[:deposited]
      costs = close_snap[:costs] - open_snap[:costs]
      check("sim equity change = deposits + gain - costs", [i, j, rates],
            [report[12] - report[5], report[17], report[18]],
            [deposits + report[16] - costs, costs, report[16] - costs])
    end
  end
end

SEEDS.each do |seed|
  GEN.reseed(seed + 1_000_003)
  (N / 40).times do
    state, rates = Sim.run(walk: true)
    Sim.verify(state, rates)
  end

  # Round trips (audit E3): constant prices, any mix of buys and sells, then mark to market. With
  # every trade costing at least a cent, equity never ends above what was deposited.
  (N / 40).times do
    state, rates = Sim.run(walk: false)
    final = state[:snaps].last
    check("sim round trip: equity never rises", [rates, state[:trades].size],
          [final[:cash] + final[:market] <= final[:deposited]], [true])
    check("sim every trade costs at least a cent", [rates], [state[:costs] >= state[:trades].size], [true])
  end
end

# Audit E3, reproduced: price 149 centicents, spread 0, 1 % fee. 100 one-round buys are booked at
# 1 cent each, the 100 rounds are worth 149 cents; the buys must cost at least the 49 cent gap.
e3_costs = 0
100.times do
  out = Wire.out(5)
  status = Engine.quote_buy(1, 149, 0, 100, 10**6, out)
  e3_costs += Wire.read_i64s(out, 5)[3]
  check("E3 minimum cost", [], [status, e3_costs.positive?], [OK, true])
end
check("E3 free gain closed", [], [Ref.rhu(100, 149, 100) - 100 <= e3_costs], [true])

# A few big, fixed cases that random generation will not reach.
big_buy = Array.new(100_000) { [1, 0, 1, MAX_AMOUNT, 1] }
[0, 1].each do |method|
  out = Wire.out(5)
  eng = Engine.cost_basis(method, big_buy.size, Wire.trades(big_buy), 0, 10, out)
  check("cost_basis big", [method, big_buy.size], [eng, Wire.read_i64s(out, 5)], [OK, [0, 0, 0, MAX_AGG, 0].tap { _1[2] = MAX_AGG }])
end
times = Wire.out(MAX_POINTS)
count = FFI::MemoryPointer.new(:int32)
step = Wire.out(1)
status = Engine.sample_times(0, MAX_TIME, MAX_POINTS, times, count, step)
check("sample_times max points", [], [status, count.read_int32], [OK, MAX_POINTS])
last_times = Wire.read_i64s(times, MAX_POINTS)
check("sample_times max points ends at finish", [], [last_times.last, last_times.each_cons(2).all? { _1 < _2 }],
      [MAX_TIME, true])

$per_function.sort.each { |name, count| puts format("  %-24s %6d checks", name, count) }
puts "#{$checks} checks against the Ruby reference, #{$failures} mismatches (seed #{SEED})"
exit($failures.zero? ? 0 : 1)
