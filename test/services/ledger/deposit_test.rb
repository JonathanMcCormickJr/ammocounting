require "test_helper"

module Ledger
  class DepositTest < ActiveSupport::TestCase
    test "debits cash and credits owner's capital" do
      tx = Deposit.call(users(:one), 177_600, at: Time.utc(2026, 1, 1))
      assert_equal [ [ 1, 0, 177_600 ], [ 3, 1, 177_600 ] ], tx.postings.order(:id).pluck(:account, :side, :amount_cents)
      assert_equal "Deposit", tx.description
      sheet = Balances.sheet(users(:one))
      assert_equal [ 177_600, 177_600 ], [ sheet.cash, sheet.owners_capital ]
    end

    test "uses a custom description" do
      assert_equal "Top up", Deposit.call(users(:one), 1, description: "Top up").description
    end

    test "refuses zero, negative and oversized amounts" do
      [ 0, -5, 10**12 + 1 ].each do |amount|
        assert_no_difference "LedgerTransaction.count" do
          assert_raises(LedgerEngine::Error) { Deposit.call(users(:one), amount) }
        end
      end
    end

    test "locks the user" do
      locked = false
      user = users(:one)
      with_singleton(user, :with_lock, ->(&block) { locked = true; block.call }) { Deposit.call(user, 100) }
      assert locked
    end
  end
end
