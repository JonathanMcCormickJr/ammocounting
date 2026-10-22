require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "defaults to weighted average cost basis" do
    assert_predicate User.new, :weighted_average?
  end

  test "can switch cost basis method to fifo" do
    user = users(:one)
    user.fifo!
    assert_equal "fifo", user.reload.cost_basis_method
  end

  test "rejects unknown cost basis method" do
    user = users(:one)
    user.cost_basis_method = "lifo"
    assert_not user.valid?
    assert_includes user.errors.attribute_names, :cost_basis_method
  end

  test "requires valid unique email" do
    assert_not User.new(email_address: "", password: "longenough").valid?
    assert_not User.new(email_address: "nope", password: "longenough").valid?
    assert_not User.new(email_address: "one@example.com", password: "longenough").valid?
    assert User.new(email_address: "new@example.com", password: "longenough").valid?
  end

  test "requires password of at least 8 characters" do
    assert_not User.new(email_address: "a@example.com", password: "short").valid?
  end

  test "authenticates with correct password only" do
    assert_equal users(:one), User.authenticate_by(email_address: "one@example.com", password: "password")
    assert_nil User.authenticate_by(email_address: "one@example.com", password: "wrong")
  end

  test "history_start is the sooner of creation and the first ledger transaction, to the second" do
    user = users(:one)
    user.update_columns(created_at: Time.utc(2026, 5, 1, 10, 0, 0, 900_000))
    assert_equal Time.utc(2026, 5, 1, 10), user.history_start
    Ledger::Deposit.call(user, 100, at: Time.utc(2026, 4, 1))
    assert_equal Time.utc(2026, 4, 1), user.history_start
    Ledger::Deposit.call(user, 100, at: Time.utc(2026, 4, 2))
    assert_equal Time.utc(2026, 4, 1), user.history_start
  end
end
