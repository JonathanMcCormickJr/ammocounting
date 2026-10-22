module Ledger
  # Read side: balances from the persisted running totals, shaped for the engine.
  module Balances
    class << self
      # Cumulative [debits, credits] for accounts 1..5 (index 0..4), for
      # transactions with occurred_at <= time (all of them when time is nil).
      # Pass straight to LedgerEngine.balance_sheet / income_statement.
      def as_of(user, time = nil)
        LedgerEngine.collapse_kinds(Totals.as_of(user, time))
      end

      # Engine balance sheet (cash, holdings, equity ...) as of time (nil = now).
      # Raises LedgerEngine::Error if the books do not balance.
      def sheet(user, time = nil)
        LedgerEngine.balance_sheet(as_of(user, time))
      end

      # { caliber_id => whole rounds held } for calibers with a positive balance.
      def quantities(user)
        Trade.holdings(user)
      end
    end
  end
end
