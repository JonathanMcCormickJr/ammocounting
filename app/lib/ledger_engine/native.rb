# Raw ffi bindings; struct layouts exactly as in ledger_core/ABI.md. Loaded
# lazily; raises LedgerEngine::LibraryMissing if the library has not been built.
module LedgerEngine
  module Native
    extend FFI::Library
    ffi_lib LedgerEngine.resolve_library(LedgerEngine.library_path)

    POSTINGS_MAX = 16
    TOTALS_CELLS = 20

    class Posting < FFI::Struct
      layout :account, :int32, :side, :int32, :amount, :int64
    end

    class PostingSet < FFI::Struct
      layout :count, :int32, :reserved, :int32, :postings, [ Posting, POSTINGS_MAX ]
    end

    class Trade < FFI::Struct
      layout :caliber, :int32, :side, :int32, :qty, :int64, :value, :int64, :time, :int64
    end

    class BuyQuote < FFI::Struct
      layout :value, :int64, :spread, :int64, :fee, :int64, :costs, :int64, :total_cash_out, :int64
    end

    class SellQuote < FFI::Struct
      layout :value, :int64, :spread, :int64, :fee, :int64, :costs, :int64, :net_cash_in, :int64
    end

    class BasisReport < FFI::Struct
      layout :realized_gain, :int64, :basis_at_start, :int64, :basis_at_end, :int64,
             :purchased, :int64, :consumed, :int64
    end

    class AccountTotal < FFI::Struct
      layout :debits, :int64, :credits, :int64
    end

    class BalanceSheet < FFI::Struct
      layout :cash, :int64, :holdings, :int64, :total_assets, :int64, :owners_capital, :int64,
             :net_income_to_date, :int64, :total_equity, :int64, :total_liabilities, :int64
    end

    class IncomeStatement < FFI::Struct
      layout :realized_gain, :int64, :unrealized_gain, :int64, :trading_gain_total, :int64,
             :trading_costs, :int64, :net_income, :int64
    end

    class CashFlow < FFI::Struct
      layout :financing, :int64, :investing, :int64, :operating, :int64, :net_change, :int64
    end

    class PeriodReport < FFI::Struct
      layout :opening, BalanceSheet, :closing, BalanceSheet, :income, IncomeStatement, :flow, CashFlow
    end

    class Revaluation < FFI::Struct
      layout :market_total, :int64, :amount, :int64, :direction, :int32, :reserved, :int32
    end

    class MoneyParts < FFI::Struct
      layout :whole, :int64, :fraction, :int64, :negative, :int32, :reserved, :int32
    end

    class Extent < FFI::Struct
      layout :low, :int64, :high, :int64
    end

    class Candle < FFI::Struct
      layout :open, :int64, :high, :int64, :low, :int64, :close, :int64, :ticks, :int64, :last_as_of, :int64
    end

    {
      engine_version: [ [], :int32 ],
      validate_transaction: [ %i[int32 pointer], :int32 ],
      apply_transaction: [ %i[int32 pointer pointer pointer], :int32 ],
      diff_totals: [ %i[pointer pointer pointer], :int32 ],
      collapse_kinds: [ %i[pointer pointer], :int32 ],
      audit_chain: [ %i[int32 pointer], :int32 ],
      build_deposit: [ %i[int64 pointer], :int32 ],
      build_buy: [ %i[pointer pointer], :int32 ],
      build_sell: [ %i[pointer pointer], :int32 ],
      revalue: [ %i[int32 pointer int64 pointer pointer], :int32 ],
      market_value: [ %i[int64 int64 pointer], :int32 ],
      quote_buy: [ %i[int64 int64 int64 int64 int64 pointer], :int32 ],
      quote_sell: [ %i[int64 int64 int64 int64 int64 pointer], :int32 ],
      apply_trade_quantity: [ %i[int64 int32 int64 pointer], :int32 ],
      portfolio_position: [ %i[int64 int64 pointer], :int32 ],
      sum: [ %i[int32 pointer pointer], :int32 ],
      cost_basis: [ %i[int32 int32 pointer int64 int64 pointer], :int32 ],
      balance_sheet: [ %i[pointer pointer], :int32 ],
      income_statement: [ %i[pointer int64 pointer], :int32 ],
      cash_flow: [ %i[pointer int64 int64 pointer], :int32 ],
      period_report: [ %i[pointer pointer int64 pointer], :int32 ],
      split_money: [ %i[int64 pointer], :int32 ],
      split_price: [ %i[int64 pointer], :int32 ],
      negate: [ %i[int64 pointer], :int32 ],
      scale: [ %i[int64 int64 int64 int64 int32 pointer], :int32 ],
      min_max: [ %i[int32 pointer pointer], :int32 ],
      sample_times: [ %i[int64 int64 int32 pointer pointer pointer], :int32 ],
      next_price: [ %i[int64 int64 int64 int64 int64 pointer], :int32 ],
      bps_from_random: [ %i[uint64 int64 pointer], :int32 ],
      ohlc: [ %i[int32 pointer pointer], :int32 ],
      ohlc_merge: [ %i[int32 pointer pointer], :int32 ]
    }.each { |name, (args, ret)| attach_function name, :"ledger_core_#{name}", args, ret }
  end
end
