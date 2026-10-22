require "test_helper"

module Ledger
  class TotalsTest < ActiveSupport::TestCase
    T1 = Time.utc(2026, 1, 1, 10)
    T2 = Time.utc(2026, 1, 1, 11)

    setup do
      @user = users(:one)
      Deposit.call(@user, 1000, at: T1)
      Deposit.call(@user, 500, at: T2)
    end

    def deposits(total_cash)
      [ total_cash, 0, 0, 0, 0, total_cash ] + ([ 0 ] * 34)
    end

    test "row_at is the latest row at or before the time (inclusive)" do
      assert_nil Totals.row_at(@user, T1 - 1)
      assert_equal T1, Totals.row_at(@user, T1).occurred_at
      assert_equal T1, Totals.row_at(@user, T2 - 1).occurred_at
      assert_equal T2, Totals.row_at(@user, T2).occurred_at
      assert_equal T2, Totals.row_at(@user).occurred_at
      assert_equal T2, Totals.row_at(@user, T2 + 3600).occurred_at
    end

    test "rows at the same instant are ordered by id: the later one wins" do
      third = Deposit.call(@user, 7, at: T2)
      assert_equal third, Totals.row_at(@user, T2)
      assert_equal third, Totals.row_at(@user)
      assert_equal deposits(1507), Totals.as_of(@user, T2)
    end

    test "as_of returns the engine totals of that row, zeros before any row" do
      assert_equal LedgerEngine::ZERO_TOTALS, Totals.as_of(@user, T1 - 1)
      assert_equal deposits(1000), Totals.as_of(@user, T1)
      assert_equal deposits(1500), Totals.as_of(@user, T2)
      assert_equal deposits(1500), Totals.as_of(@user)
    end

    test "totals are per user" do
      assert_equal LedgerEngine::ZERO_TOTALS, Totals.as_of(users(:two))
      assert_nil Totals.row_at(users(:two))
    end

    test "reading costs one indexed query and never sums postings" do
      assert_queries_count(1) { Totals.as_of(@user, T2) }
      plan = LedgerTransaction.connection.select_rows(
        "EXPLAIN QUERY PLAN SELECT * FROM ledger_transactions WHERE user_id = #{@user.id} AND occurred_at <= '2026-01-01 11:00:00' " \
        "ORDER BY occurred_at DESC, id DESC LIMIT 1"
      ).flatten.join(" ")
      assert_includes plan, "index_ledger_transactions_on_user_id_and_occurred_at_and_id"
      assert_not_includes plan, "TEMP B-TREE"
    end
  end
end
