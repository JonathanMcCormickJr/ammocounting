require "test_helper"

module Ledger
  class BalancesTest < ActiveSupport::TestCase
    T1 = Time.utc(2026, 1, 1, 10)
    T2 = Time.utc(2026, 1, 1, 11)

    setup do
      @user = users(:one)
      Deposit.call(@user, 1000, at: T1)
      Deposit.call(@user, 500, at: T2)
    end

    test "as_of sums debits and credits per account up to the time, inclusive" do
      empty = [ [ 0, 0 ] ] * 5
      assert_equal empty, Balances.as_of(@user, T1 - 1)
      assert_equal [ [ 1000, 0 ], [ 0, 0 ], [ 0, 1000 ], [ 0, 0 ], [ 0, 0 ] ], Balances.as_of(@user, T1)
      assert_equal [ [ 1500, 0 ], [ 0, 0 ], [ 0, 1500 ], [ 0, 0 ], [ 0, 0 ] ], Balances.as_of(@user, T2)
    end

    test "without a time as_of covers everything" do
      assert_equal [ 1500, 0 ], Balances.as_of(@user).first
    end

    test "only the given user's postings are summed" do
      Deposit.call(users(:two), 7, at: T1)
      assert_equal [ 1500, 0 ], Balances.as_of(@user).first
      assert_equal [ 7, 0 ], Balances.as_of(users(:two)).first
    end

    test "output feeds the engine balance sheet" do
      sheet = Balances.sheet(@user, T1)
      assert_equal 1000, sheet.cash
      assert_equal 1000, sheet.total_equity
      assert_equal 1500, Balances.sheet(@user).total_assets
    end

    test "sheet is zero for a user with no history" do
      assert_equal 0, Balances.sheet(users(:two)).total_assets
    end

    test "quantities nets buys and sells, only positive balances" do
      fund(@user, at: T2)
      Buy.call(@user, calibers(:nine_mm), 300)
      Buy.call(@user, calibers(:twenty_two), 50)
      Sell.call(@user, calibers(:twenty_two), 50)
      Sell.call(@user, calibers(:nine_mm), 100)
      assert_equal({ calibers(:nine_mm).id => 200 }, Balances.quantities(@user))
      assert_empty Balances.quantities(users(:two))
    end
  end
end
