module Statements
  # Assembles the three statements from the persisted running totals and the
  # engine. Rails does no arithmetic: the engine's period_report_checked builds
  # both balance sheets, the income statement and the cash flow from the totals
  # at the two ends of the period and the cost basis report of the same period,
  # and proves them consistent (assets = liabilities + equity, net income =
  # change in net income to date, cash reconciles, and the realized/unrealized
  # split agrees with the trades).
  #
  # Any engine failure, including Not_Reconciled (the trades and the ledger
  # disagree), raises Ledger::IntegrityError and nothing is rendered.
  class Builder
    # costs_shown: trading costs negated for display as a deduction.
    Report = Data.define(:period, :cost_basis_method, :opening, :closing, :income, :cash_flow, :costs_shown)

    class << self
      # Balance sheet as of `time` (the engine proves assets = liabilities + equity).
      def balance_sheet(user, time)
        guard("balance sheet") { Ledger::Balances.sheet(user, time) }
      end

      # Balance sheets at both ends, income statement and cash flows for a
      # Statements::Period, using the user's current cost basis method.
      def period(user, period)
        guard("statements") do
          report = LedgerEngine.period_report_checked(Ledger::Totals.as_of(user, period.from), Ledger::Totals.as_of(user, period.to),
            basis_report(user, period))
          Report.new(period: period, cost_basis_method: user.cost_basis_method, opening: report.opening, closing: report.closing,
            income: report.income, cash_flow: report.cash_flow, costs_shown: LedgerEngine.negate(report.income.trading_costs))
        end
      end

      private

      # The cost basis report of the same user, trades and period (from, to] as the totals.
      def basis_report(user, period)
        LedgerEngine.cost_basis(method: user.cost_basis_method, trades: user.trades.engine_rows,
          t_start: period.from.to_i, t_end: period.to.to_i)
      end

      def guard(what)
        yield
      rescue LedgerEngine::Error => e
        raise Ledger::IntegrityError, "The #{what} failed an engine check (#{e.status} in #{e.operation}); not shown."
      end
    end
  end
end
