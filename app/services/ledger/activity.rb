module Ledger
  # Period activity for the engine's cash_flow / income_statement inputs.
  module Activity
    class << self
      # Running-totals difference for transactions in the period (from, to]
      # (from exclusive, to inclusive; nil = unbounded): 40 Integers in
      # LedgerEngine totals layout, from LedgerEngine.diff_totals. Pass straight
      # to LedgerEngine.cash_flow.
      def between(user, from, to)
        opening = from ? Totals.as_of(user, from) : LedgerEngine::ZERO_TOTALS
        LedgerEngine.diff_totals(Totals.as_of(user, to), opening)
      end

      # Collapses activity (kind x account) to five [debits, credits] account
      # totals for LedgerEngine.income_statement.
      def account_totals(activity)
        LedgerEngine.collapse_kinds(activity)
      end
    end
  end
end
