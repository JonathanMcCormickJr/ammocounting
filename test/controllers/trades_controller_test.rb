require "test_helper"

class TradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
    fund(@user)
    fund(@other)
  end

  def order(side, quantity, slug: "9mm", nonce: Ledger.new_nonce, **extra)
    post trades_path, params: { trade: { caliber_slug: slug, side: side, quantity: quantity, nonce: nonce }.merge(extra) }
  end

  test "requires sign in" do
    order("buy", 1)
    assert_redirected_to new_session_path
    assert_equal 0, Trade.count
  end

  test "buy executes for the signed-in user" do
    sign_in_as(@user)
    assert_difference "@user.trades.count", 1 do
      order("buy", 1000)
    end
    assert_redirected_to root_path
    assert_equal "Buy: 1000 x 9mm at $0.255.", flash[:notice]
    assert_equal 177_600 - 25_883, Ledger::Balances.sheet(@user).cash
  end

  test "sell executes and refusals show a flash alert" do
    sign_in_as(@user)
    order("buy", 10)
    order("sell", 4)
    assert_equal "Sell: 4 x 9mm at $0.255.", flash[:notice]
    order("sell", 100)
    assert_redirected_to root_path
    assert_equal "You do not hold that many rounds.", flash[:alert]
    order("buy", 10_000_000)
    assert_equal "Not enough cash for this purchase.", flash[:alert]
    order("buy", "lots")
    assert_includes flash[:alert], "whole number of rounds"
  end

  test "submitting the same form twice executes once and shows a friendly notice" do
    sign_in_as(@user)
    nonce = Ledger.new_nonce
    order("buy", 1000, nonce: nonce)
    assert_equal "Buy: 1000 x 9mm at $0.255.", flash[:notice]
    cash = Ledger::Balances.sheet(@user).cash
    assert_no_difference [ "Trade.count", "LedgerTransaction.count" ] do
      order("buy", 1000, nonce: nonce)
    end
    assert_redirected_to root_path
    assert_equal "This order was already placed. Buy: 1000 x 9mm at $0.255.", flash[:notice]
    assert_nil flash[:alert]
    assert_equal cash, Ledger::Balances.sheet(@user).cash
  end

  test "a stale or forged nonce is refused politely" do
    sign_in_as(@user)
    order("buy", 1, nonce: "not-a-real-nonce")
    assert_redirected_to root_path
    assert_includes flash[:alert], "out of date"
    assert_equal 0, Trade.count
  end

  test "a missing nonce is a bad request" do
    sign_in_as(@user)
    post trades_path, params: { trade: { caliber_slug: "9mm", side: "buy", quantity: 1 } }
    assert_response :bad_request
    assert_equal 0, Trade.count
  end

  test "another user's nonce does not block or reveal anything" do
    sign_in_as(@other)
    nonce = Ledger.new_nonce
    Ledger::Buy.call(@user, calibers(:nine_mm), 1, nonce: nonce)
    assert_difference "@other.trades.count", 1 do
      order("buy", 1, nonce: nonce)
    end
    assert_equal "Buy: 1 x 9mm at $0.255.", flash[:notice]
  end

  test "an unknown side is refused" do
    sign_in_as(@user)
    order("hold", 1)
    assert_equal "Choose buy or sell.", flash[:alert]
    assert_equal 0, Trade.count
  end

  test "an unknown caliber is a 404" do
    sign_in_as(@user)
    order("buy", 1, slug: "nope")
    assert_response :not_found
  end

  test "missing parameters are a bad request" do
    sign_in_as(@user)
    post trades_path, params: {}
    assert_response :bad_request
  end

  test "trading never touches another user's ledger, even when asked to" do
    sign_in_as(@user)
    before = Ledger::Balances.as_of(@other)
    order("buy", 500, user_id: @other.id)
    assert_equal before, Ledger::Balances.as_of(@other)
    assert_equal 0, @other.trades.count
    assert_equal 1, @user.trades.count
  end

  test "another user cannot sell rounds they do not hold" do
    sign_in_as(@user)
    order("buy", 100)
    sign_out
    sign_in_as(@other)
    order("sell", 100)
    assert_equal "You do not hold that many rounds.", flash[:alert]
    assert_equal({ calibers(:nine_mm).id => 100 }, Ledger::Balances.quantities(@user))
  end
end
