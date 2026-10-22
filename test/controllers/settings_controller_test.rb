require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    patch settings_path, params: { user: { cost_basis_method: "fifo" } }
    assert_redirected_to new_session_path
    assert_predicate users(:one), :weighted_average?
  end

  test "show requires authentication and shows only the signed-in user's method" do
    get settings_path
    assert_redirected_to new_session_path
    users(:two).fifo!
    sign_in_as(users(:one))
    get settings_path
    assert_response :success
    assert_select "select[name='user[cost_basis_method]'] option[selected]", "Weighted average"
  end

  test "switches cost basis method at runtime" do
    sign_in_as(users(:one))
    patch settings_path, params: { user: { cost_basis_method: "fifo" } }
    assert_redirected_to root_path
    assert_predicate users(:one).reload, :fifo?
    patch settings_path, params: { user: { cost_basis_method: "weighted_average" } }
    assert_predicate users(:one).reload, :weighted_average?
  end

  test "rejects invalid methods" do
    sign_in_as(users(:one))
    patch settings_path, params: { user: { cost_basis_method: "lifo" } }
    assert_redirected_to root_path
    assert_equal "Invalid cost basis method.", flash[:alert]
    assert_predicate users(:one).reload, :weighted_average?
  end

  test "a user cannot change another user's settings" do
    sign_in_as(users(:one))
    patch settings_path, params: { id: users(:two).id, user_id: users(:two).id, user: { id: users(:two).id, cost_basis_method: "fifo" } }
    assert_predicate users(:two).reload, :weighted_average?
    assert_predicate users(:one).reload, :fifo?
  end
end
