require "test_helper"

module Ledger
  class BuyTest < ActiveSupport::TestCase
    AT = Time.utc(2026, 1, 1, 12)

    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm) # latest tick 2550
      fund(@user)
    end

    test "buys at the engine quote: value 25_500, spread 128, fee 255" do
      trade = Buy.call(@user, @nine, 1000, at: AT)
      assert_equal %w[buy], [ trade.side ]
      assert_equal [ 1000, 2550, 25_500, 128, 255, AT ],
        [ trade.quantity, trade.price_centicents, trade.value_cents, trade.spread_cents, trade.fee_cents, trade.occurred_at ]
      tx = trade.ledger_transaction
      assert_equal "buy", tx.kind
      assert_equal "Buy 1000 9mm", tx.description
      assert_equal [ [ 2, 0, 25_500 ], [ 5, 0, 383 ], [ 1, 1, 25_883 ] ], tx.postings.order(:id).pluck(:account, :side, :amount_cents)
      sheet = Balances.sheet(@user)
      assert_equal [ 177_600 - 25_883, 25_500, 177_600 - 383 ], [ sheet.cash, sheet.holdings, sheet.total_equity ]
    end

    test "accepts a numeric string quantity" do
      assert_equal 12, Buy.call(@user, @nine, " 12 ").quantity
    end

    test "revalues existing holdings first at the current price" do
      Buy.call(@user, @nine, 1000)
      PriceTick.create!(caliber: @nine, price_centicents: 2600, as_of: Time.utc(2026, 1, 1, 0, 10))
      assert_difference "LedgerTransaction.revalue.count", 1 do
        Buy.call(@user, @nine, 100) # V 2600, spread 13, fee 26
      end
      assert_equal 26_000 + 2_600, Balances.sheet(@user).holdings
      assert_equal [ 2600, 2600, 13, 26 ], Trade.order(:id).last.then { [ _1.value_cents, _1.price_centicents, _1.spread_cents, _1.fee_cents ] }
    end

    test "spending exactly all cash is allowed, one cent more is refused" do
      # 1000 rounds at 2550 cost 25_883; fund exactly that for a fresh user
      two = users(:two)
      fund(two, 25_883)
      assert Buy.call(two, @nine, 1000)
      assert_equal 0, Balances.sheet(two).cash
      three = User.create!(email_address: "three@example.com", password: "password123")
      fund(three, 25_882)
      error = assert_raises(Refused) { Buy.call(three, @nine, 1000) }
      assert_equal "Not enough cash for this purchase.", error.message
    end

    test "a refused buy leaves no rows behind, not even a revaluation" do
      Buy.call(@user, @nine, 1000)
      PriceTick.create!(caliber: @nine, price_centicents: 2600, as_of: Time.utc(2026, 1, 1, 0, 10))
      assert_no_difference [ "LedgerTransaction.count", "LedgerPosting.count", "Trade.count" ] do
        assert_raises(Refused) { Buy.call(@user, @nine, 1_000_000) }
      end
    end

    test "refuses invalid quantities" do
      [ nil, "", "abc", "0", 0, -3, "2.5", 2.5, "0x10", "1e3", 10**9 + 1 ].each do |quantity|
        error = assert_raises(Refused, quantity.inspect) { Buy.call(@user, @nine, quantity) }
        assert_includes error.message, "whole number of rounds"
      end
      assert_equal 0, Trade.count
    end

    test "refuses a caliber without a price" do
      unpriced = Caliber.create!(name: "Test", slug: "test", starting_price_centicents: 1)
      error = assert_raises(Refused) { Buy.call(@user, unpriced, 1) }
      assert_equal "No price is available for Test.", error.message
    end

    test "there is no trade limit any more: the engine's cost_basis is linear" do
      assert_not Ledger.respond_to?(:trade_limit)
      3.times { Buy.call(@user, @nine, 1) }
      assert_equal 3, Trade.count
    end

    test "records the engine's quantity_after on each trade" do
      assert_equal 1000, Buy.call(@user, @nine, 1000, at: AT).quantity_after
      assert_equal 1500, Buy.call(@user, @nine, 500, at: AT + 1).quantity_after
      assert_equal 7, Buy.call(@user, calibers(:twenty_two), 7, at: AT + 2).quantity_after
      assert_equal 1500, Trade.held(@user, @nine)
    end

    test "refuses a buy that would take one caliber beyond the engine's holding limit" do
      rich = users(:two)
      fund(rich, 10**12)
      assert_equal 10**9, Buy.call(rich, @nine, 10**9).quantity_after
      assert_no_difference [ "Trade.count", "LedgerTransaction.count" ] do
        error = assert_raises(Refused) { Buy.call(rich, @nine, 1) }
        assert_equal "You cannot hold more than 1000000000 rounds of one caliber.", error.message
      end
    end

    test "other engine failures while counting the holding are not disguised as refusals" do
      failing = ->(*) { raise LedgerEngine::Error.new(:internal_error, :apply_trade_quantity) }
      with_singleton(LedgerEngine, :apply_trade_quantity, failing) do
        assert_equal :internal_error, assert_raises(LedgerEngine::Error) { Buy.call(@user, @nine, 1) }.status
      end
    end

    test "a buy at an earlier explicit time than the user's latest entry is refused loudly, not misordered" do
      Buy.call(@user, @nine, 1, at: AT)
      assert_raises(Poster::OutOfOrder) { Buy.call(@user, @nine, 1, at: AT - 1) }
    end

    test "a trade worth nothing (engine quote status 1) is a friendly refusal and writes nothing" do
      PriceTick.create!(caliber: @nine, price_centicents: 1, as_of: Time.utc(2100, 1, 1))
      assert_no_difference [ "Trade.count", "LedgerTransaction.count" ] do
        error = assert_raises(Refused) { Buy.call(@user, @nine, 1) }
        assert_equal "This trade is too small to price. Try a larger quantity.", error.message
      end
    end

    test "bad_argument from anywhere but the quote is a bug, not a refusal" do
      failing = ->(*) { raise LedgerEngine::Error.new(:bad_argument, :build_buy) }
      with_singleton(LedgerEngine, :build_buy, failing) do
        assert_equal :bad_argument, assert_raises(LedgerEngine::Error) { Buy.call(@user, @nine, 1) }.status
      end
    end

    test "locks the user" do
      locked = false
      with_singleton(@user, :with_lock, ->(&block) { locked = true; block.call }) { Buy.call(@user, @nine, 1) }
      assert locked
    end

    test "uses configured spread and fee" do
      config = Rails.configuration.x
      original = [ config.spread_bps, config.fee_bps ]
      config.spread_bps = 0
      config.fee_bps = 0
      trade = Buy.call(@user, @nine, 1000)
      # Audit E3: with spread and fee both rounding to nothing the engine charges a minimum
      # of 1 cent (booked as spread), so a trade is never free.
      assert_equal [ 1, 0 ], [ trade.spread_cents, trade.fee_cents ]
      assert_equal 177_600 - 25_500 - 1, Balances.sheet(@user).cash
    ensure
      config.spread_bps, config.fee_bps = original
    end

    test "an engine range error is not disguised as a refusal" do
      nine_id = @nine.id
      with_singleton(Ledger, :latest_prices, -> { { nine_id => 10**7 + 1 } }) do
        error = assert_raises(LedgerEngine::Error) { Buy.call(@user, @nine, 1) }
        assert_equal :out_of_range, error.status
      end
    end
  end
end
