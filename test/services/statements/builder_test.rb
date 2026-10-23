require "test_helper"

module Statements
  class BuilderTest < ActiveSupport::TestCase
    H = ScriptedHistory

    setup do
      @user = users(:one)
      ScriptedHistory.build(@user, calibers(:nine_mm))
    end

    def period(from, to, key = "custom")
      Period.new(key, from, to, [])
    end

    def full_period
      Period.parse({ period: "max" }, origin: @user.history_start, now: Time.utc(2026, 2, 6))
    end

    test "balance sheet at the end of the script (hand computed)" do
      # cash 177_600 - 25_375 - 30_450 + 15_760; holdings 1500 * $0.30; net income 6_000 - 1_065
      sheet = Builder.balance_sheet(@user, Time.utc(2026, 2, 6))
      assert_equal [ 137_535, 45_000, 182_535, 0, 177_600, 4_935, 182_535 ],
        [ sheet.cash, sheet.holdings, sheet.total_assets, sheet.total_liabilities, sheet.owners_capital,
          sheet.net_income_to_date, sheet.total_equity ]
    end

    test "balance sheet mid-history is as of that moment" do
      sheet = Builder.balance_sheet(@user, Time.utc(2026, 2, 2, 12)) # right after the first buy (inclusive)
      assert_equal [ 152_225, 25_000, 177_225, -375 ], [ sheet.cash, sheet.holdings, sheet.total_equity, sheet.net_income_to_date ]
    end

    test "full period, weighted average: realized 2_250, unrealized 3_750" do
      # basis 25_000 + 30_000 over 2000 rounds; selling 500 consumes 55_000 * 500 / 2000 = 13_750; 16_000 - 13_750 = 2_250
      report = Builder.period(@user, full_period)
      income = report.income
      assert_equal "weighted_average", report.cost_basis_method
      assert_equal [ 2_250, 3_750, 6_000, 1_065, 4_935 ],
        [ income.realized_gain, income.unrealized_gain, income.trading_gain_total, income.trading_costs, income.net_income ]
    end

    test "full period, FIFO: realized 3_500, unrealized 2_500; net income identical" do
      # first lot (1000 for 25_000) supplies the 500 sold: basis 12_500; 16_000 - 12_500 = 3_500
      @user.fifo!
      report = Builder.period(@user, full_period)
      income = report.income
      assert_equal "fifo", report.cost_basis_method
      assert_equal [ 3_500, 2_500, 6_000, 1_065, 4_935 ],
        [ income.realized_gain, income.unrealized_gain, income.trading_gain_total, income.trading_costs, income.net_income ]
      assert_equal 182_535, report.closing.total_equity
    end

    test "switching the method at runtime changes the split but not net worth or net income" do
      weighted = Builder.period(@user, full_period)
      @user.fifo!
      fifo = Builder.period(@user, full_period)
      refute_equal weighted.income.realized_gain, fifo.income.realized_gain
      assert_equal weighted.income.net_income, fifo.income.net_income
      assert_equal weighted.closing.total_equity, fifo.closing.total_equity
    end

    test "full period cash flows (hand computed)" do
      # operating -(375 + 450 + 240); investing -(25_000 + 30_000) + 16_000; financing 177_600
      flow = Builder.period(@user, full_period).cash_flow
      assert_equal [ -1_065, -39_000, 177_600, 137_535 ], [ flow.operating, flow.investing, flow.financing, flow.net_change ]
      report = Builder.period(@user, full_period)
      assert_equal [ 0, 137_535 ], [ report.opening.cash, report.closing.cash ]
    end

    test "sub-period (02-03 00:00, 02-05 00:00]: opening from the earlier balance sheet" do
      # activity: buy 30_000 (costs 450), sell 16_000 (costs 240), revalues +5_000 +4_000 -3_000
      # opening: cash 152_225, equity 177_225 (income -375); closing: cash 137_535, income 4_935
      report = Builder.period(@user, period(Time.utc(2026, 2, 3), H::T4))
      income = report.income
      assert_equal [ 6_000, 690, 5_310, 2_250, 3_750 ],
        [ income.trading_gain_total, income.trading_costs, income.net_income, income.realized_gain, income.unrealized_gain ]
      flow = report.cash_flow
      assert_equal [ -690, -14_000, 0, -14_690 ], [ flow.operating, flow.investing, flow.financing, flow.net_change ]
      assert_equal [ 152_225, 137_535 ], [ report.opening.cash, report.closing.cash ]
      assert_equal 5_310, report.closing.net_income_to_date - report.opening.net_income_to_date
    end

    test "trades after the period end are ignored by realized gain" do
      # (T0 - 1, 02-03 18:00]: both buys, +5_000 revalue; the later sell does not exist yet
      report = Builder.period(@user, period(H::T0 - 1, Time.utc(2026, 2, 3, 18)))
      assert_equal [ 0, 5_000, 5_000, 825, 4_175 ],
        [ report.income.realized_gain, report.income.unrealized_gain, report.income.trading_gain_total,
          report.income.trading_costs, report.income.net_income ]
    end

    test "a period with no activity is all zero" do
      report = Builder.period(@user, period(Time.utc(2026, 3, 1), Time.utc(2026, 3, 2)))
      assert_equal [ 0, 0, 0, 0, 0 ], report.income.to_h.values
      assert_equal [ 0, 0, 0, 0 ], report.cash_flow.to_h.values
      assert_equal report.opening.cash, report.closing.cash
    end

    test "a user with no trades or ledger rows gets zero statements" do
      empty = users(:two)
      report = Builder.period(empty, Period.parse({ period: "max" }, origin: empty.history_start, now: Time.current))
      assert_equal [ 0, 0, 0, 0, 0 ], report.income.to_h.values
      assert_equal 0, report.closing.total_equity
    end

    test "never includes another user's postings" do
      fund(users(:two), 5_000)
      assert_equal 182_535, Builder.balance_sheet(@user, Time.utc(2026, 2, 6)).total_equity
      assert_equal 5_000, Builder.balance_sheet(users(:two), Time.current).total_equity
    end

    test "trading costs are also given negated for display" do
      assert_equal(-1_065, Builder.period(@user, full_period).costs_shown)
    end

    test "engine failures surface as IntegrityError and nothing is built" do
      failing = ->(*) { raise LedgerEngine::Error.new(:unbalanced, :balance_sheet) }
      with_singleton(LedgerEngine, :balance_sheet, failing) do
        error = assert_raises(Ledger::IntegrityError) { Builder.balance_sheet(@user, Time.current) }
        assert_includes error.message, "unbalanced"
      end
      failing_report = ->(*) { raise LedgerEngine::Error.new(:not_reconciled, :period_report_checked) }
      with_singleton(LedgerEngine, :period_report_checked, failing_report) do
        error = assert_raises(Ledger::IntegrityError) { Builder.period(@user, full_period) }
        assert_includes error.message, "not_reconciled"
      end
    end

    test "the statements are built by period_report_checked from the same period's cost basis report" do
      period = full_period
      basis = LedgerEngine.cost_basis(method: @user.cost_basis_method, trades: @user.trades.engine_rows,
        t_start: period.from.to_i, t_end: period.to.to_i)
      seen = []
      real = LedgerEngine.method(:period_report_checked)
      spy = ->(opening, closing, given) { seen << given; real.call(opening, closing, given) }
      generic = ->(*) { raise "unchecked period_report used" }
      with_singleton(LedgerEngine, :period_report_checked, spy) do
        with_singleton(LedgerEngine, :period_report, generic) { Builder.period(@user, period) }
      end
      assert_equal [ basis ], seen
    end

    test "a ledger the trades disagree with is never rendered (Not_Reconciled is an IntegrityError)" do
      period = full_period
      real = LedgerEngine.method(:cost_basis)
      forged = ->(**args) { real.call(**args).with(basis_at_end: 1) }
      with_singleton(LedgerEngine, :cost_basis, forged) do
        error = assert_raises(Ledger::IntegrityError) { Builder.period(@user, period) }
        assert_includes error.message, "not_reconciled in period_report_checked"
        assert_includes error.message, "not shown"
      end
    end

    test "a missing trade (ledger and trades tell different stories) is not rendered" do
      without_ledger_triggers { Trade.where(id: Trade.where(user: @user).order(:id).first.id).delete_all }
      error = assert_raises(Ledger::IntegrityError) { Builder.period(@user, full_period) }
      assert_includes error.message, "not_reconciled"
    end

    test "tampered running totals are caught by the engine, not rendered" do
      # The database refuses to store unbalanced totals (see LedgerDatabaseGuardsTest), so simulate
      # corrupt storage by handing the engine unbalanced totals.
      unbalanced = Array.new(40, 0).tap { _1[0] = 1 }
      with_singleton(Ledger::Totals, :as_of, ->(*) { unbalanced }) do
        error = assert_raises(Ledger::IntegrityError) { Builder.balance_sheet(@user, Time.current) }
        assert_includes error.message, "unbalanced in balance_sheet"
        assert_raises(Ledger::IntegrityError) { Builder.period(@user, full_period) }
      end
    end

    test "a closing total below the opening one (reordered rows) is refused as bad_order" do
      without_ledger_triggers do
        LedgerTransaction.where(id: Ledger::Totals.row_at(@user, H::T1).id).update_all(deposit_cash_debits: 177_700, deposit_capital_credits: 177_700)
      end
      error = assert_raises(Ledger::IntegrityError) { Builder.period(@user, period(H::T1, H::T4)) }
      assert_includes error.message, "bad_order in period_report_checked"
    end
  end
end
