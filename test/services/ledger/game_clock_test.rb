require "test_helper"

module Ledger
  # Ledger entries are dated by the player's own game clock, never the wall clock.
  class GameClockTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm)
      @game_time = @user.game_time.utc
      fund(@user)
    end

    test "now_for is the player's game time, whole seconds, independent of the wall clock" do
      assert_equal @game_time, Ledger.now_for(@user)
      travel_to Time.utc(2030, 6, 1) do
        assert_equal @game_time, Ledger.now_for(@user)
      end
    end

    test "buys, sells, deposits and revaluations post at the game time" do
      buy = Buy.call(@user, @nine, 100)
      assert_equal @game_time, buy.occurred_at
      assert_equal @game_time, buy.ledger_transaction.occurred_at
      assert_equal @game_time, Sell.call(@user, @nine, 40).occurred_at
      assert_equal @game_time, Deposit.call(@user, 500).occurred_at
      assert_equal 60, Trade.held(@user, @nine)
      assert LedgerEngine.audit_chain(@user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
    end

    test "trades are priced as of the game time: later ticks are the future" do
      PriceTick.create!(caliber: @nine, price_centicents: 9999, as_of: @game_time + 1.day)
      assert_equal 2550, Buy.call(@user, @nine, 10).price_centicents
    end

    test "a trade dated before the player's latest ledger row is still refused" do
      Buy.call(@user, @nine, 1)
      assert_raises(Poster::OutOfOrder) { Buy.call(@user, @nine, 1, at: @game_time - 1) }
    end

    test "latest_prices at a game time ignores later ticks" do
      later = PriceTick.create!(caliber: @nine, price_centicents: 3000, as_of: Time.utc(2026, 2, 1))
      assert_equal 2550, Ledger.latest_prices(at: Time.utc(2026, 1, 15))[@nine.id]
      assert_equal 2500, Ledger.latest_prices(at: Time.utc(2026, 1, 1, 0, 4))[@nine.id]
      assert_equal 3000, Ledger.latest_prices(at: later.as_of)[@nine.id]
      assert_equal 3000, Ledger.latest_prices[@nine.id]
      assert_empty Ledger.latest_prices(at: Time.utc(2025, 12, 31))
    end
  end
end
