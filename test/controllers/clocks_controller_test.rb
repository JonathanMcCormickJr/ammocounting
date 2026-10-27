require "test_helper"

class ClocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other = users(:two)
    fund(@user)
  end

  test "requires sign in" do
    post clock_path(jump: "week")
    assert_redirected_to new_session_path
    assert_equal Time.utc(2026, 1, 2), @user.reload.game_time
  end

  test "fast-forwards only the signed-in player's clock" do
    sign_in_as(@user)
    post clock_path(jump: "week")
    assert_redirected_to root_path
    assert_equal "Fast-forwarded to 2026-01-09.", flash[:notice]
    assert_equal Time.utc(2026, 1, 9), @user.reload.game_time
    assert_equal Time.utc(2026, 1, 2), @other.reload.game_time
  end

  test "an unknown jump is a flash alert, not an error" do
    sign_in_as(@user)
    post clock_path(jump: "decade")
    assert_redirected_to root_path
    assert_equal "Choose how far to fast-forward.", flash[:alert]
    assert_equal Time.utc(2026, 1, 2), @user.reload.game_time
  end

  test "the dashboard shows the game date and a button per jump" do
    sign_in_as(@user)
    get root_path
    assert_select "#game-date", "2026-01-02"
    FastForward::JUMPS.each_key { |jump| assert_select "form[action='#{clock_path(jump: jump)}'] button" }
    post clock_path(jump: "month")
    follow_redirect!
    assert_select "#game-date", "2026-02-02"
  end

  EVENT = MarketEvent::Event.new(index: 0, kind: MarketEvent::Kind.new(headline: "The Bubonic Plague is back!", resolution: "The plague has passed.", ramp_days: 5, slugs: nil),
    starts_at: Time.utc(2026, 1, 5), peak_at: Time.utc(2026, 1, 10), ends_at: Time.utc(2026, 1, 15), drift_bps: 150)

  test "fast-forwarding past an event reports why prices moved, and the dashboard carries the news" do
    sign_in_as(@user)
    with_singleton(MarketEvent, :all, ->(**) { [ EVENT ] }) do
      post clock_path(jump: "week")
      assert_equal "Fast-forwarded to 2026-01-09. The Bubonic Plague is back!", flash[:notice]
      get root_path
      assert_select "#market-news", /The Bubonic Plague is back!/
      assert_select "#market-history li", /2026-01-05: The Bubonic Plague is back!/
      post clock_path(jump: "day") # 2026-01-10: the crisis is unwinding
      get root_path
      assert_select "#market-news", /The plague has passed\./
      post clock_path(jump: "week")
      get root_path
      assert_select "#market-news", false
      assert_select "#market-history li", 1
    end
  end

  test "the dashboard has no news or history before any event" do
    sign_in_as(@user)
    get root_path
    assert_select "#market-news", false
    assert_select "#market-history", false
  end
end
