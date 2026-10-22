module Ledger
  # Buy: Dr Holdings value, Dr Trading Costs costs / Cr Cash total (engine quote and builder).
  class Buy < TradeOrder
    private

    def side
      :buy
    end

    def quote(qty, price, _held)
      LedgerEngine.quote_buy(qty: qty, price: price, spread_bps: Ledger.spread_bps, fee_bps: Ledger.fee_bps,
        cash_available: Balances.sheet(@user).cash)
    end

    def postings(quote)
      LedgerEngine.build_buy(quote)
    end
  end
end
