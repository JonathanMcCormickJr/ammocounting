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

  test "an expired session is no longer accepted" do
    sign_in_as(@user)
    get root_path
    assert_response :success
    Session.update_all(created_at: Session::TTL.ago - 1.minute)
    get root_path
    assert_redirected_to new_session_path
  end

  test "session cookie is httponly, lax, expiring, and secure over https" do
    https!
    post session_path, params: { email_address: @user.email_address, password: "password" }
    cookie = Array(response.headers["set-cookie"]).join("\n")
    assert_match(/session_id=/, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
    assert_match(/; secure/i, cookie)
    expires = Time.httpdate(cookie[/expires=([^;]+)/i, 1])
    assert_in_delta Session::TTL.from_now.to_i, expires.to_i, 60
  end

  test "session cookie is not marked secure over plain http" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_no_match(/; secure/i, Array(response.headers["set-cookie"]).join("\n"))
  end

  test "login is also rate limited per account across addresses" do
    11.times do |i|
      post session_path, params: { email_address: @user.email_address, password: "wrong" },
        env: { "REMOTE_ADDR" => "10.0.0.#{i}" }
    end
    assert_redirected_to new_session_path
    assert_equal "Try again later.", flash[:alert]
  end

  test "account rate limit key ignores case and padding of the email" do
    11.times do |i|
      post session_path, params: { email_address: " #{@user.email_address.upcase} ", password: "wrong" },
        env: { "REMOTE_ADDR" => "10.1.0.#{i}" }
    end
    assert_equal "Try again later.", flash[:alert]
  end

  test "rate limit keys on the client ip behind a proxy, not the proxy" do
    trusted = { "REMOTE_ADDR" => "127.0.0.1" }
    11.times { |i| post session_path, params: { email_address: "u#{i}@example.com", password: "x" }, env: trusted.merge("HTTP_X_FORWARDED_FOR" => "203.0.113.9") }
    assert_equal "Try again later.", flash[:alert]
    post session_path, params: { email_address: "other@example.com", password: "x" }, env: trusted.merge("HTTP_X_FORWARDED_FOR" => "203.0.113.10")
    assert_equal "Try another email address or password.", flash[:alert]
  end
end
