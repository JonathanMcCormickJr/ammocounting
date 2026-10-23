require "test_helper"

module Ledger
  class PortfolioTest < ActiveSupport::TestCase
    T = Time.utc(2026, 1, 1, 12)

    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm)
    end

    def tick(price, minute)
      PriceTick.create!(caliber: @nine, price_centicents: price, as_of: Time.utc(2026, 1, 1, 1, minute))
    end

    # buy 1000 @2550 (V 25_500), buy 1000 @2600 (V 26_000), sell 1000 @2700 (V 27_000)
    def trade_history
      fund(@user)
      Buy.call(@user, @nine, 1000, at: T)
      tick(2600, 0)
      Buy.call(@user, @nine, 1000, at: T + 60)
      tick(2700, 5)
      Sell.call(@user, @nine, 1000, at: T + 120)
    end

    test "reads everything inside one non-joinable (snapshot) transaction" do
      trade_history
      seen = []
      connection = ApplicationRecord.connection
      real_sheet = Balances.method(:sheet)
      real_quantities = Balances.method(:quantities)
      spy = ->(real) { ->(*args) { seen << connection.current_transaction.joinable?; real.call(*args) } }
      with_singleton(Balances, :sheet, spy.call(real_sheet)) do
        with_singleton(Balances, :quantities, spy.call(real_quantities)) { Portfolio.for(@user) }
      end
      assert_equal [ false, false ], seen
    end

    test "empty portfolio for a user without history" do
      portfolio = Portfolio.for(@user)
      assert_equal [ 0, 0, 0, [] ], [ portfolio.cash, portfolio.holdings_value, portfolio.net_worth, portfolio.positions ]
      assert_nil portfolio.position_for(@nine)
      assert_equal @user, portfolio.user
    end

    test "cash only after a deposit" do
      fund(@user)
      portfolio = Portfolio.for(@user)
      assert_equal [ 177_600, 177_600 ], [ portfolio.cash, portfolio.net_worth ]
      assert_empty portfolio.positions
    end

    test "weighted average cost basis" do
      trade_history
      position = Portfolio.for(@user).position_for(@nine)
      # basis 51_500 for 2000 rounds; selling 1000 consumes 25_750
      assert_equal [ 1000, 2700, 27_000, 25_750, 1_250 ], [ position.quantity, position.price_centicents, position.market_value, position.cost_basis, position.unrealized_gain ]
      assert_equal @nine, position.caliber
    end

    test "FIFO cost basis follows the user's setting" do
      trade_history
      @user.fifo!
      position = Portfolio.for(@user).position_for(@nine)
      # first lot (25_500) sold; remaining lot costs 26_000
      assert_equal [ 26_000, 1_000 ], [ position.cost_basis, position.unrealized_gain ]
    end

    test "cash, holdings and net worth come from the ledger" do
      trade_history
      portfolio = Portfolio.for(@user)
      sheet = portfolio.sheet
      assert_equal sheet.cash, portfolio.cash
      assert_equal sheet.holdings, portfolio.holdings_value
      assert_equal sheet.total_equity, portfolio.net_worth
      assert_equal portfolio.cash + portfolio.holdings_value, portfolio.net_worth
    end

    test "positions are ordered by caliber and only list calibers held" do
      fund(@user)
      Buy.call(@user, calibers(:twenty_two), 10)
      Buy.call(@user, @nine, 10)
      assert_equal %w[9mm .22\ LR], Portfolio.for(@user).positions.map { _1.caliber.name }
      assert_equal 10, Portfolio.for(@user).position_for(calibers(:twenty_two)).quantity
    end

    test "other users' trades never appear" do
      fund(@user)
      fund(users(:two))
      Buy.call(users(:two), @nine, 500)
      portfolio = Portfolio.for(@user)
      assert_empty portfolio.positions
      assert_equal 177_600, portfolio.cash
    end

    test "a failing engine balance check is a loud IntegrityError" do
      fund(@user)
      broken = ->(_user, _time = nil) { raise LedgerEngine::Error.new(:unbalanced, :balance_sheet) }
      with_singleton(Balances, :sheet, broken) do
        error = assert_raises(IntegrityError) { Portfolio.for(@user) }
        assert_includes error.message, "unbalanced"
      end
    end

    test "balance sheet is as of the given time" do
      fund(@user)
      assert_equal 0, Portfolio.for(@user, now: Time.utc(1999, 12, 31)).cash
    end
  end
end
