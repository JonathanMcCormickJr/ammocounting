require "test_helper"

module Ledger
  # Audit L4: after the clock steps backwards (NTP, a restored VM) the user's
  # latest ledger row is "in the future". Writers reading the clock must keep the
  # chronological chain (post at max(now, latest row)) instead of raising
  # Poster::OutOfOrder and blocking the user.
  class ClockSkewTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm)
      @future = (Time.current + 1.hour).floor
      fund(@user, Signup::INITIAL_FUNDS_CENTS, at: @future)
    end

    test "now_for is the clock normally and the latest row when that is later" do
      assert_equal @future, Ledger.now_for(@user)
      assert_in_delta Time.current.to_f, Ledger.now_for(users(:two)).to_f, 2, "no ledger rows: the clock"
      travel_to @future + 5 do
        assert_equal @future + 5, Ledger.now_for(@user)
      end
    end

    test "a buy, a sell and a deposit made while the clock is behind post at the latest row's time" do
      buy = Buy.call(@user, @nine, 100)
      assert_equal @future, buy.occurred_at
      assert_equal @future, buy.ledger_transaction.occurred_at
      sell = Sell.call(@user, @nine, 40)
      assert_equal @future, sell.occurred_at
      assert_equal @future, Deposit.call(@user, 500).occurred_at
      assert_equal 60, Trade.held(@user, @nine)
      assert LedgerEngine.audit_chain(@user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
    end

    test "the revaluation before a trade is also placed at the latest row's time" do
      Buy.call(@user, @nine, 100)
      PriceTick.create!(caliber: @nine, price_centicents: 2700, as_of: Time.utc(2026, 1, 1, 0, 10))
      revalue = Revalue.call(@user)
      assert_equal @future, revalue.occurred_at
    end

    test "an explicit older time is still refused (only the clock is clamped)" do
      assert_raises(Poster::OutOfOrder) { Buy.call(@user, @nine, 1, at: @future - 1) }
    end
  end
end
