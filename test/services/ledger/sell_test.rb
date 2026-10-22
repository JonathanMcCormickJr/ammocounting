require "test_helper"

module Ledger
  class SellTest < ActiveSupport::TestCase
    AT = Time.utc(2026, 1, 1, 12)

    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm) # 2550
      fund(@user)
      Buy.call(@user, @nine, 1000, at: AT - 60) # cash 151_717, holdings 25_500
    end

    test "sells at the engine quote: value 10_200, costs 153, net 10_047" do
      trade = Sell.call(@user, @nine, 400, at: AT)
      assert_equal "sell", trade.side
      assert_equal [ 400, 10_200, 51, 102 ], [ trade.quantity, trade.value_cents, trade.spread_cents, trade.fee_cents ]
      assert_equal [ [ 1, 0, 10_047 ], [ 5, 0, 153 ], [ 2, 1, 10_200 ] ], trade.ledger_transaction.postings.order(:id).pluck(:account, :side, :amount_cents)
      assert_equal "Sell 400 9mm", trade.ledger_transaction.description
      sheet = Balances.sheet(@user)
      assert_equal [ 151_717 + 10_047, 15_300 ], [ sheet.cash, sheet.holdings ]
      assert_equal({ @nine.id => 600 }, Balances.quantities(@user))
    end

    test "selling everything empties the holding" do
      Sell.call(@user, @nine, 1000)
      assert_empty Balances.quantities(@user)
      assert_equal 0, Balances.sheet(@user).holdings
    end

    test "revalues first so the sale credits holdings at market" do
      PriceTick.create!(caliber: @nine, price_centicents: 2600, as_of: Time.utc(2026, 1, 1, 0, 10))
      assert_difference "LedgerTransaction.revalue.count", 1 do
        Sell.call(@user, @nine, 1000)
      end
      assert_equal 0, Balances.sheet(@user).holdings
    end

    test "refuses to sell more than is held" do
      error = assert_raises(Refused) { Sell.call(@user, @nine, 1001) }
      assert_equal "You do not hold that many rounds.", error.message
    end

    test "refuses to sell a caliber never held" do
      assert_raises(Refused) { Sell.call(@user, calibers(:twenty_two), 1) }
    end

    test "cannot sell another user's rounds" do
      assert_raises(Refused) { Sell.call(users(:two), @nine, 1) }
      assert_equal({ @nine.id => 1000 }, Balances.quantities(@user))
    end

    test "refuses sales whose costs exceed value" do
      config = Rails.configuration.x
      original = [ config.spread_bps, config.fee_bps ]
      config.spread_bps = 10_000
      config.fee_bps = 100
      error = assert_raises(Refused) { Sell.call(@user, @nine, 10) }
      assert_equal "Trading costs would exceed the sale value.", error.message
    ensure
      config.spread_bps, config.fee_bps = original
    end

    test "zero net proceeds post no cash line" do
      config = Rails.configuration.x
      original = [ config.spread_bps, config.fee_bps ]
      config.spread_bps = 10_000
      config.fee_bps = 0
      trade = Sell.call(@user, @nine, 10)
      assert_equal [ [ 5, 0, 255 ], [ 2, 1, 255 ] ], trade.ledger_transaction.postings.order(:id).pluck(:account, :side, :amount_cents)
    ensure
      config.spread_bps, config.fee_bps = original
    end

    test "refuses invalid quantities" do
      assert_raises(Refused) { Sell.call(@user, @nine, 0) }
      assert_equal 1, Trade.count
    end

    test "records the engine's quantity_after on each sale" do
      assert_equal 600, Sell.call(@user, @nine, 400, at: AT).quantity_after
      assert_equal 0, Sell.call(@user, @nine, 600, at: AT + 1).quantity_after
      assert_equal 0, Trade.held(@user, @nine)
    end
  end
end
