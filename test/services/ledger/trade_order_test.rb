require "test_helper"

module Ledger
  # Shared TradeOrder behaviour: strict quantity parsing (audit L11) and the form
  # nonce that makes a replayed or double-submitted order a no-op (audit L5).
  class TradeOrderTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @nine = calibers(:nine_mm)
      fund(@user)
    end

    # --- L11 --------------------------------------------------------------

    test "quantity must be plain ASCII digits: underscores, signs, leading zeros and stray text are refused" do
      [ "1_000", "+5", "-5", "05", "00", "0", " 5 6", "5\n6", "１２", "1e3", "0x1F", "٣", "5.0", "" ].each do |quantity|
        error = assert_raises(Refused, quantity.inspect) { Buy.call(@user, @nine, quantity) }
        assert_includes error.message, "whole number of rounds", quantity.inspect
      end
      assert_equal 0, Trade.count
    end

    test "surrounding whitespace and integers are accepted" do
      assert_equal 5, Buy.call(@user, @nine, " 5\n").quantity
      assert_equal 7, Buy.call(@user, @nine, 7).quantity
    end

    # --- L5 ---------------------------------------------------------------

    test "new_nonce is a fresh 32 hex character string" do
      assert_match Ledger::NONCE_FORMAT, Ledger.new_nonce
      assert_not_equal Ledger.new_nonce, Ledger.new_nonce
    end

    test "the nonce is stored on the trade it produced" do
      nonce = Ledger.new_nonce
      assert_equal nonce, Buy.call(@user, @nine, 3, nonce: nonce).nonce
    end

    test "replaying a nonce raises Replay with the original trade and writes nothing" do
      nonce = Ledger.new_nonce
      original = Buy.call(@user, @nine, 3, nonce: nonce)
      assert_no_difference [ "Trade.count", "LedgerTransaction.count", "LedgerPosting.count" ] do
        error = assert_raises(Replay) { Buy.call(@user, @nine, 3, nonce: nonce) }
        assert_equal original, error.trade
        assert_equal "This order was already placed.", error.message
      end
      assert_equal 3, Trade.held(@user, @nine)
    end

    test "a replay is detected whatever the replayed order says" do
      nonce = Ledger.new_nonce
      Buy.call(@user, @nine, 3, nonce: nonce)
      assert_raises(Replay) { Sell.call(@user, @nine, 1, nonce: nonce) }
      assert_raises(Replay) { Buy.call(@user, calibers(:twenty_two), 99, nonce: nonce) }
      assert_equal 1, Trade.count
    end

    test "nonces are per user" do
      nonce = Ledger.new_nonce
      fund(users(:two))
      Buy.call(@user, @nine, 1, nonce: nonce)
      assert Buy.call(users(:two), @nine, 1, nonce: nonce)
    end

    test "a refused order does not consume its nonce" do
      nonce = Ledger.new_nonce
      assert_raises(Refused) { Sell.call(@user, @nine, 1, nonce: nonce) }
      Buy.call(@user, @nine, 5, nonce: Ledger.new_nonce)
      assert Sell.call(@user, @nine, 1, nonce: nonce)
    end

    test "orders without a nonce are never treated as replays" do
      2.times { Buy.call(@user, @nine, 1) }
      assert_equal 2, Trade.count
    end

    test "a malformed nonce is refused before anything is written" do
      [ "short", "G" * 32, "a" * 31, "a" * 33, "" ].each do |nonce|
        error = assert_raises(Refused, nonce.inspect) { Buy.call(@user, @nine, 1, nonce: nonce) }
        assert_includes error.message, "out of date"
      end
      assert_equal 0, Trade.count
    end

    test "the database itself refuses a second trade with the same nonce" do
      nonce = Ledger.new_nonce
      first = Buy.call(@user, @nine, 1, nonce: nonce)
      assert_raises(ActiveRecord::RecordNotUnique) do
        Trade.insert!(first.attributes.except("id").merge("ledger_transaction_id" => first.ledger_transaction_id))
      end
    end
  end
end
