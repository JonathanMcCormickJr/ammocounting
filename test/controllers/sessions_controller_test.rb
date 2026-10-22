require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal 1, @user.sessions.count
  end

  test "create resets the existing rails session" do
    get calibers_path # unauthenticated: stores return_to in the session
    assert_redirected_to new_session_path
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to calibers_url
    get new_session_path
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to root_url # return_to did not survive the reset
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "login is rate limited" do
    11.times { post session_path, params: { email_address: @user.email_address, password: "wrong" } }
    assert_redirected_to new_session_path
    assert_equal "Try again later.", flash[:alert]
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    assert_equal 0, @user.sessions.count
  end

  test "destroy requires authentication" do
    delete session_path
    assert_redirected_to new_session_path
  end
end
