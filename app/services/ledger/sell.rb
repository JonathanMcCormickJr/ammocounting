module Ledger
  # Sell: Dr Cash net, Dr Trading Costs costs / Cr Holdings value (engine quote and builder).
  class Sell < TradeOrder
    private

    def side
      :sell
    end

    def quote(qty, price, held)
      LedgerEngine.quote_sell(qty: qty, qty_held: held, price: price, spread_bps: Ledger.spread_bps, fee_bps: Ledger.fee_bps)
    end

    def postings(quote)
      LedgerEngine.build_sell(quote)
    end
  end
end
