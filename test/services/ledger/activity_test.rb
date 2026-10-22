require "test_helper"

module Ledger
  class ActivityTest < ActiveSupport::TestCase
    T0 = Time.utc(2026, 1, 1, 10)
    T1 = Time.utc(2026, 1, 1, 11)
    T2 = Time.utc(2026, 1, 1, 12)

    setup do
      @user = users(:one)
      Deposit.call(@user, 177_600, at: T0)
      Buy.call(@user, calibers(:nine_mm), 1000, at: T1) # value 25_500, costs 383, cash out 25_883
      Sell.call(@user, calibers(:nine_mm), 400, at: T2) # value 10_200, costs 153, net 10_047
    end

    # cell of the flat 40-number totals: kind * 5 + account - 1 -> [debits, credits]
    def cell(totals, kind, account)
      totals.slice(((kind * 5) + account - 1) * 2, 2)
    end

    test "unbounded activity is the latest running totals, by kind and account" do
      activity = Activity.between(@user, nil, nil)
      assert_equal 40, activity.size
      assert_equal [ 177_600, 0 ], cell(activity, 0, 1)
      assert_equal [ 0, 177_600 ], cell(activity, 0, 3)
      assert_equal [ 0, 25_883 ], cell(activity, 1, 1)
      assert_equal [ 25_500, 0 ], cell(activity, 1, 2)
      assert_equal [ 383, 0 ], cell(activity, 1, 5)
      assert_equal [ 10_047, 0 ], cell(activity, 2, 1)
      assert_equal [ 0, 10_200 ], cell(activity, 2, 2)
      assert_equal [ 153, 0 ], cell(activity, 2, 5)
      assert_equal [ 0 ] * 10, activity.last(10)
    end

    test "period is exclusive of from and inclusive of to" do
      activity = Activity.between(@user, T0, T1)
      assert_equal [ 0, 0 ], cell(activity, 0, 1)
      assert_equal [ 25_500, 0 ], cell(activity, 1, 2)
      assert_equal [ 0, 0 ], cell(activity, 2, 2)
    end

    test "feeds the engine cash flow and income statement" do
      activity = Activity.between(@user, T0, T2)
      flow = LedgerEngine.cash_flow(activity, Balances.sheet(@user, T0).cash, Balances.sheet(@user, T2).cash)
      assert_equal [ 0, -15_300, -536, -15_836 ], flow.to_h.values_at(:financing, :investing, :operating, :net_change)
      statement = LedgerEngine.income_statement(Activity.account_totals(activity), 0)
      assert_equal 536, statement.trading_costs
    end

    test "account_totals collapses kinds" do
      totals = Activity.account_totals(Activity.between(@user, nil, nil))
      assert_equal [ 187_647, 25_883 ], totals[0]
      assert_equal [ 25_500, 10_200 ], totals[1]
      assert_equal [ 536, 0 ], totals[4]
    end

    test "other users' activity is excluded" do
      assert_equal LedgerEngine::ZERO_TOTALS, Activity.between(users(:two), nil, nil)
    end
  end
end
