require "test_helper"

class UserFlowTest < ActionDispatch::IntegrationTest
  test "signup, browse the market, switch cost basis, sign out" do
    post signup_path, params: { user: { email_address: "flow@example.com", password: "longenough", password_confirmation: "longenough" } }
    follow_redirect!
    assert_select "h1", "Portfolio"
    get calibers_path
    assert_select "h1", "Market"
    patch settings_path, params: { user: { cost_basis_method: "fifo" } }
    assert_predicate User.find_by!(email_address: "flow@example.com"), :fifo?
    delete session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "login page is the landing for logged-out visitors" do
    get root_path
    follow_redirect!
    assert_select "h1", "Sign in"
    assert_select "header.site nav", 0
  end
end
