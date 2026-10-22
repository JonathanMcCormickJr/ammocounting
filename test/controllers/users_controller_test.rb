require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_signup_path
    assert_response :success
  end

  test "create signs the user in" do
    assert_difference "User.count", 1 do
      post signup_path, params: { user: { email_address: "New@Example.com", password: "longenough", password_confirmation: "longenough" } }
    end
    assert_redirected_to root_url
    assert cookies[:session_id]
    assert_equal "new@example.com", User.order(:id).last.email_address
  end

  test "create ignores attempts to set cost basis directly" do
    post signup_path, params: { user: { email_address: "x@example.com", password: "longenough", cost_basis_method: "fifo" } }
    assert_predicate User.find_by!(email_address: "x@example.com"), :weighted_average?
  end

  test "create with invalid data re-renders" do
    assert_no_difference "User.count" do
      post signup_path, params: { user: { email_address: "bad", password: "x", password_confirmation: "y" } }
    end
    assert_response :unprocessable_content
    assert_select ".errors li"
  end

  test "signup is rate limited" do
    11.times { post signup_path, params: { user: { email_address: "bad", password: "x" } } }
    assert_redirected_to new_signup_path
  end
end
