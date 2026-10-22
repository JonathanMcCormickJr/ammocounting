require "test_helper"

class SignupTest < ActiveSupport::TestCase
  test "creates a user" do
    result = Signup.call(email_address: "new@example.com", password: "longenough", password_confirmation: "longenough")
    assert_predicate result, :success?
    assert_predicate result.user, :persisted?
    assert_predicate result.user, :weighted_average?
  end

  test "reports failure without persisting" do
    assert_no_difference "User.count" do
      result = Signup.call(email_address: "bad", password: "x")
      assert_not result.success?
      assert_not_empty result.user.errors
    end
  end

  test "grants $1,776.00 as Dr Cash / Cr Owner's Capital" do
    assert_equal 177_600, Signup::INITIAL_FUNDS_CENTS
    result = Signup.call(email_address: "rich@example.com", password: "longenough")
    tx = result.user.ledger_transactions.sole
    assert_equal "deposit", tx.kind
    assert_equal "Initial funds", tx.description
    assert_equal [ [ 1, 0, 177_600 ], [ 3, 1, 177_600 ] ], tx.postings.order(:id).pluck(:account, :side, :amount_cents)
    assert_equal 177_600, Ledger::Balances.sheet(result.user).cash
  end

  test "failed signups post nothing" do
    assert_no_difference "LedgerTransaction.count" do
      Signup.call(email_address: "bad", password: "x")
    end
  end

  test "signup fails atomically if the ledger refuses the deposit" do
    refuse = ->(_user, _amount, **) { raise LedgerEngine::Error.new(:unbalanced, :validate_transaction) }
    with_singleton(Ledger::Deposit, :call, refuse) do
      assert_no_difference [ "User.count", "LedgerTransaction.count" ] do
        assert_raises(LedgerEngine::Error) { Signup.call(email_address: "atomic@example.com", password: "longenough") }
      end
    end
    assert_nil User.find_by(email_address: "atomic@example.com")
  end

  test "grant_initial_funds deposits for the given user" do
    tx = Signup.new.grant_initial_funds(users(:one))
    assert_equal users(:one), tx.user
  end

  test "grant_initial_funds is invoked after a successful save only" do
    granted = []
    signup = Signup.new
    signup.define_singleton_method(:grant_initial_funds) { |user| granted << user }
    signup.call(email_address: "a@example.com", password: "longenough")
    signup.call(email_address: "bad", password: "x")
    assert_equal [ "a@example.com" ], granted.map(&:email_address)
  end
end
