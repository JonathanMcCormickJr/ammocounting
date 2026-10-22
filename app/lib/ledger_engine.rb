require "ffi"

# Idiomatic Ruby wrapper over the SPARK ledger_core C ABI (ledger_core/ABI.md).
#
# All inputs and outputs are plain Integers (cents, centicents, rounds, basis
# points, epoch seconds). The engine does all money arithmetic; this module only
# marshals. Non-zero engine statuses raise LedgerEngine::Error, or its subclass
# LedgerEngine::Refusal for business refusals a user can cause (not enough cash,
# not enough rounds, costs above sale value); every other status means the
# caller (or data) is broken.
module LedgerEngine
  DEFAULT_LIBRARY = "ledger_core/lib/libLedger_Core.so".freeze

  STATUS = {
    0 => :ok, 1 => :bad_argument, 2 => :out_of_range, 3 => :unbalanced,
    4 => :insufficient_cash, 5 => :insufficient_holdings, 6 => :negative_proceeds,
    7 => :bad_order, 8 => :negative_balance, 9 => :not_reconciled, 10 => :internal_error
  }.freeze
  REFUSALS = %i[insufficient_cash insufficient_holdings negative_proceeds].freeze
  METHODS = { weighted_average: 0, fifo: 1 }.freeze
  # Transaction kinds of the running totals (ledger_transactions.kind).
  KINDS = { deposit: 0, buy: 1, sell: 2, revalue: 3 }.freeze
  # Trade sides.
  SIDES = { buy: 0, sell: 1 }.freeze
  DIRECTIONS = { 0 => :none, 1 => :gain, 2 => :loss }.freeze
  # Running totals: 20 cells (kind * 5 + account - 1) x [debits, credits] = 40 Integers.
  TOTALS_SIZE = 40
  ZERO_TOTALS = Array.new(TOTALS_SIZE, 0).freeze

  class LibraryMissing < StandardError; end

  # Raised for any non-zero engine status. #status is the symbol (e.g. :unbalanced).
  class Error < StandardError
    attr_reader :status, :operation

    def initialize(status, operation)
      @status = status
      @operation = operation
      super("ledger_core #{operation} failed: #{status}")
    end
  end

  # A business-rule refusal (see REFUSALS); safe to show to the user.
  class Refusal < Error; end

  BuyQuote = Data.define(:value, :spread, :fee, :costs, :total_cash_out)
  SellQuote = Data.define(:value, :spread, :fee, :costs, :net_cash_in)
  BasisReport = Data.define(:realized_gain, :basis_at_start, :basis_at_end, :purchased, :consumed)
  BalanceSheet = Data.define(:cash, :holdings, :total_assets, :owners_capital,
                             :net_income_to_date, :total_equity, :total_liabilities)
  IncomeStatement = Data.define(:realized_gain, :unrealized_gain, :trading_gain_total, :trading_costs, :net_income)
  CashFlow = Data.define(:financing, :investing, :operating, :net_change)
  PeriodReport = Data.define(:opening, :closing, :income, :cash_flow)
  # direction: :none, :gain or :loss; postings: [[account, side, amount], ...] (empty for :none).
  Revaluation = Data.define(:market_total, :amount, :direction, :postings)
  # |value| = whole * 100 (money) or * 10_000 (price) + fraction; negative is true/false.
  MoneyParts = Data.define(:whole, :fraction, :negative)
  Extent = Data.define(:low, :high)
  Candle = Data.define(:open, :high, :low, :close, :ticks, :last_as_of)
  # times: Array of epoch seconds; step: seconds between samples.
  Sampling = Data.define(:times, :step)

  class << self
    # ENV["LEDGER_CORE_LIB"] overrides the default build location.
    def library_path(env: ENV)
      env.fetch("LEDGER_CORE_LIB") { Rails.root.join(DEFAULT_LIBRARY).to_s }
    end

    # Returns the path if the shared library exists, else raises with build instructions.
    def resolve_library(path)
      return path if File.exist?(path)

      raise LibraryMissing,
        "ledger_core shared library not found at #{path}. Run script/build " \
        "(or: cd ledger_core && LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --validation), " \
        "or set LEDGER_CORE_LIB to its location."
    end

    # 200 for 0.2.0.
    def version
      Native.engine_version
    end

    # postings: [[account 1..5, side 0|1, amount_cents], ...]. Returns true or raises.
    def validate_transaction(postings)
      check!(Native.validate_transaction(postings.size, pack(Native::Posting, postings, %i[account side amount])),
        :validate_transaction)
      true
    end

    # --- posting builders: return [[account, side, amount], ...] ---

    def build_deposit(cents)
      set = Native::PostingSet.new
      check!(Native.build_deposit(cents, set), :build_deposit)
      read_postings(set)
    end

    # quote: a BuyQuote from quote_buy.
    def build_buy(quote)
      set = Native::PostingSet.new
      check!(Native.build_buy(int64s(quote.to_h.values_at(*BuyQuote.members)), set), :build_buy)
      read_postings(set)
    end

    # quote: a SellQuote from quote_sell.
    def build_sell(quote)
      set = Native::PostingSet.new
      check!(Native.build_sell(int64s(quote.to_h.values_at(*SellQuote.members)), set), :build_sell)
      read_postings(set)
    end

    # market_values: per-caliber values (from market_value); carrying_holdings: Holdings balance.
    # Returns a Revaluation; its postings are empty when nothing needs posting.
    def revalue(market_values, carrying_holdings)
      info = Native::Revaluation.new
      set = Native::PostingSet.new
      check!(Native.revalue(market_values.size, int64s(market_values), carrying_holdings, info, set), :revalue)
      Revaluation.new(market_total: info[:market_total], amount: info[:amount],
        direction: DIRECTIONS.fetch(info[:direction]), postings: read_postings(set))
    end

    # --- running totals (flat Arrays of 40 Integers, see TOTALS_SIZE) ---

    # kind: :deposit/:buy/:sell/:revalue (or 0..3). Validates the postings and
    # returns the new running totals.
    def apply_transaction(kind, postings, previous)
      out = FFI::MemoryPointer.new(:int64, TOTALS_SIZE)
      check!(Native.apply_transaction(KINDS.fetch(kind) { kind }, posting_set(postings), totals_pointer(previous), out),
        :apply_transaction)
      out.read_array_of_int64(TOTALS_SIZE)
    end

    # Period activity: to - from, cell by cell.
    def diff_totals(to, from)
      out = FFI::MemoryPointer.new(:int64, TOTALS_SIZE)
      check!(Native.diff_totals(totals_pointer(to), totals_pointer(from), out), :diff_totals)
      out.read_array_of_int64(TOTALS_SIZE)
    end

    # Sums the four kinds per account: five [debits, credits] pairs (accounts 1..5).
    def collapse_kinds(totals)
      out = FFI::MemoryPointer.new(:int64, 10)
      check!(Native.collapse_kinds(totals_pointer(totals), out), :collapse_kinds)
      out.read_array_of_int64(10).each_slice(2).to_a
    end

    # rows: stored running totals, oldest first. Returns true or raises.
    def audit_chain(rows)
      mem = int64s(rows.each { |row| check_totals!(row) }.flatten)
      check!(Native.audit_chain(rows.size, mem), :audit_chain)
      true
    end

    # The whole statements package for the period between two running totals.
    def period_report(opening, closing, realized_gain)
      out = Native::PeriodReport.new
      check!(Native.period_report(totals_pointer(opening), totals_pointer(closing), realized_gain, out), :period_report)
      PeriodReport.new(opening: read(out[:opening], BalanceSheet), closing: read(out[:closing], BalanceSheet),
        income: read(out[:income], IncomeStatement), cash_flow: read(out[:flow], CashFlow))
    end

    # --- trades, holdings, basis ---

    # Market value in cents of qty rounds at price centicents.
    def market_value(qty, price)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.market_value(qty, price, out), :market_value)
      out.read_int64
    end

    def quote_buy(qty:, price:, spread_bps:, fee_bps:, cash_available:)
      out = Native::BuyQuote.new
      check!(Native.quote_buy(qty, price, spread_bps, fee_bps, cash_available, out), :quote_buy)
      read(out, BuyQuote)
    end

    def quote_sell(qty:, qty_held:, price:, spread_bps:, fee_bps:)
      out = Native::SellQuote.new
      check!(Native.quote_sell(qty, qty_held, price, spread_bps, fee_bps, out), :quote_sell)
      read(out, SellQuote)
    end

    # Rounds held after a trade; side :buy/:sell (or 0/1). Stored as quantity_after.
    def apply_trade_quantity(held, side, qty)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.apply_trade_quantity(held, SIDES.fetch(side) { side }, qty, out), :apply_trade_quantity)
      out.read_int64
    end

    # Unrealized gain = market value - cost basis (may be negative).
    def portfolio_position(market_value, cost_basis)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.portfolio_position(market_value, cost_basis, out), :portfolio_position)
      out.read_int64
    end

    # Exact sum of Integers (0 for an empty list).
    def sum(values)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.sum(values.size, int64s(values), out), :sum)
      out.read_int64
    end

    # method: :weighted_average or :fifo (symbol or string).
    # trades: [[caliber, side 0 buy|1 sell, qty, value_cents, epoch_seconds], ...] grouped by
    # caliber ascending and time ordered within a caliber (order by caliber_id, occurred_at, id).
    # Reports for the period (t_start, t_end].
    def cost_basis(method:, trades:, t_start:, t_end:)
      out = Native::BasisReport.new
      mem = pack_trades(trades)
      check!(Native.cost_basis(METHODS.fetch(method.to_sym), trades.size, mem, t_start, t_end, out), :cost_basis)
      read(out, BasisReport)
    end

    # --- statements ---

    # totals: five [debits, credits] pairs for accounts 1..5.
    def balance_sheet(totals)
      out = Native::BalanceSheet.new
      check!(Native.balance_sheet(pack_totals(totals, 5), out), :balance_sheet)
      read(out, BalanceSheet)
    end

    # period_totals: five [debits, credits] pairs; realized_gain from cost_basis.
    def income_statement(period_totals, realized_gain)
      out = Native::IncomeStatement.new
      check!(Native.income_statement(pack_totals(period_totals, 5), realized_gain, out), :income_statement)
      read(out, IncomeStatement)
    end

    # activity: the period's running totals (flat 40 Integers, e.g. from diff_totals).
    def cash_flow(activity, opening_cash, closing_cash)
      out = Native::CashFlow.new
      check!(Native.cash_flow(totals_pointer(activity), opening_cash, closing_cash, out), :cash_flow)
      read(out, CashFlow)
    end

    # --- display and chart math ---

    # MoneyParts of cents: |cents| = whole * 100 + fraction.
    def split_money(cents)
      split(:split_money, cents)
    end

    # MoneyParts of centicents: |centicents| = whole * 10_000 + fraction.
    def split_price(centicents)
      split(:split_price, centicents)
    end

    def negate(value)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.negate(value, out), :negate)
      out.read_int64
    end

    # Chart position of value within low..high mapped to 0..size (flipped when invert).
    def scale(value, low, high, size, invert: false)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.scale(value, low, high, size, invert ? 1 : 0, out), :scale)
      out.read_int64
    end

    def min_max(values)
      out = Native::Extent.new
      check!(Native.min_max(values.size, int64s(values), out), :min_max)
      Extent.new(low: out[:low], high: out[:high])
    end

    # Evenly spaced, increasing sample times from start to finish (epoch seconds), at most max_points.
    def sample_times(start, finish, max_points)
      times = FFI::MemoryPointer.new(:int64, max_points.nonzero? || 1)
      count = FFI::MemoryPointer.new(:int32)
      step = FFI::MemoryPointer.new(:int64)
      check!(Native.sample_times(start, finish, max_points, times, count, step), :sample_times)
      Sampling.new(times: times.read_array_of_int64(count.read_int32), step: step.read_int64)
    end

    # --- price math ---

    def next_price(price, change_bps, max_step_bps:, floor:, ceiling:)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.next_price(price, change_bps, max_step_bps, floor, ceiling, out), :next_price)
      out.read_int64
    end

    # random: unsigned 64-bit Integer; returns a change within +-max_step_bps.
    def bps_from_random(random, max_step_bps)
      out = FFI::MemoryPointer.new(:int64)
      check!(Native.bps_from_random(random, max_step_bps, out), :bps_from_random)
      out.read_int64
    end

    # Candle of a list of prices (ticks = their count, last_as_of = 0).
    def ohlc(prices)
      out = Native::Candle.new
      check!(Native.ohlc(prices.size, int64s(prices), out), :ohlc)
      read(out, Candle)
    end

    # Merges time-ordered Candles into one.
    def ohlc_merge(candles)
      out = Native::Candle.new
      check!(Native.ohlc_merge(candles.size, int64s(candles.flat_map { |candle| candle.to_h.values_at(*Candle.members) }), out),
        :ohlc_merge)
      read(out, Candle)
    end

    private

    def check!(code, operation)
      return if code.zero?

      status = STATUS.fetch(code)
      raise (REFUSALS.include?(status) ? Refusal : Error).new(status, operation)
    end

    # Struct -> Data object of plain Integers.
    def read(struct, data_class)
      data_class.new(**data_class.members.to_h { |member| [ member, struct[member] ] })
    end

    def split(operation, value)
      out = Native::MoneyParts.new
      check!(Native.public_send(operation, value, out), operation)
      MoneyParts.new(whole: out[:whole], fraction: out[:fraction], negative: out[:negative] == 1)
    end

    # The engine reads exactly `count` fixed-size cells, so shape is checked here.
    def pack_totals(rows, count)
      raise ArgumentError, "expected #{count} [debits, credits] rows, got #{rows.size}" unless rows.size == count

      pack(Native::AccountTotal, rows, %i[debits credits])
    end

    def check_totals!(totals)
      return totals if totals.size == TOTALS_SIZE

      raise ArgumentError, "expected #{TOTALS_SIZE} running totals, got #{totals.size}"
    end

    def totals_pointer(totals)
      int64s(check_totals!(totals))
    end

    # A C array of int64 (one cell if empty, so the pointer is never zero-sized).
    # ffi raises RangeError for anything outside int64.
    def int64s(values)
      FFI::MemoryPointer.new(:int64, values.size.nonzero? || 1).write_array_of_int64(values)
    end

    # postings: [[account, side, amount], ...]; at most 16 (the engine's limit).
    def posting_set(postings)
      raise Error.new(:bad_argument, :posting_set) if postings.size > Native::POSTINGS_MAX

      set = Native::PostingSet.new
      set[:count] = postings.size
      postings.each_with_index do |(account, side, amount), index|
        posting = set[:postings][index]
        posting[:account] = account
        posting[:side] = side
        posting[:amount] = amount
      end
      set
    end

    def read_postings(set)
      Array.new(set[:count]) do |index|
        posting = set[:postings][index]
        [ posting[:account], posting[:side], posting[:amount] ]
      end
    end

    def pack_trades(trades)
      pack(Native::Trade, trades, %i[caliber side qty value time])
    end

    # Copies rows into a C array of struct_class (one extra cell if empty, so the
    # pointer is never zero-sized). mem[index] is the pointer to element `index`.
    def pack(struct_class, rows, fields)
      mem = FFI::MemoryPointer.new(struct_class, rows.size.nonzero? || 1)
      rows.each_with_index do |row, index|
        cell = struct_class.new(mem[index])
        fields.zip(row) { |field, value| cell[field] = value }
      end
      mem
    end
  end
end
