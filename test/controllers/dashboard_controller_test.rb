require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects logged-out visitors to login" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows cash, holdings, net worth and trade forms for the signed-in user" do
    fund(users(:one))
    Ledger::Buy.call(users(:one), calibers(:nine_mm), 1000)
    sign_in_as(users(:one))
    get root_path
    assert_response :success
    assert_select "#cash", "$1,517.17"
    assert_select "#holdings-value", "$255.00"
    assert_select "#net-worth", "$1,772.17"
    assert_select "#holdings tbody tr", 1
    assert_select "#holdings tbody tr td", text: "9mm"
    assert_select "#market tbody tr", 2
    assert_select "#market form[action='#{trades_path}']", 2
    assert_select "#market input[name='trade[quantity]']", 2
    assert_select "#market button[name='trade[side]'][value='buy']", 2
    assert_select "#market button[name='trade[side]'][value='sell']", 2
  end

  test "an empty portfolio says so" do
    sign_in_as(users(:one))
    get root_path
    assert_select "#cash", "$0.00"
    assert_select "#holdings", false
    assert_select "p.placeholder"
  end

  test "never shows another user's money or holdings" do
    fund(users(:two))
    Ledger::Buy.call(users(:two), calibers(:nine_mm), 1000)
    sign_in_as(users(:one))
    get root_path
    assert_select "#cash", "$0.00"
    assert_select "#net-worth", "$0.00"
    assert_select "#holdings", false
  end

  test "shows the portfolio and settings to a signed-in user" do
    sign_in_as(users(:one))
    get root_path
    assert_response :success
    assert_select "h1", "Portfolio"
    assert_select "select[name='user[cost_basis_method]'] option[selected]", "Weighted average"
    assert_select "button", "Sign out"
  end

  test "reflects the user's own cost basis method only" do
    users(:two).fifo!
    sign_in_as(users(:one))
    get root_path
    assert_select "option[selected]", "Weighted average"
  end

  test "shows the cost basis method with the switch and a settings link" do
    users(:one).fifo!
    sign_in_as(users(:one))
    get root_path
    assert_select "#cost-basis-method strong", "FIFO"
    assert_select "#cost-basis-method a[href='#{settings_path}']"
    assert_select "form[action='#{settings_path}'] select option[selected]", "FIFO"
  end

  test "positions use the user's cost basis method for basis and unrealized gain" do
    user = users(:one)
    ScriptedHistory.build(user, calibers(:nine_mm))
    sign_in_as(user)
    get root_path
    # 1500 held at $0.30 = $450.00; weighted basis 55_000 * 1500 / 2000 = 41_250; FIFO basis 42_500
    assert_select "#holdings tbody td", "$412.50"
    assert_select "#holdings tbody td", "$37.50"
    user.fifo!
    get root_path
    assert_select "#holdings tbody td", "$425.00"
    assert_select "#holdings tbody td", "$25.00"
  end

  test "net worth chart: range buttons, svg, and last point equals net worth" do
    user = users(:one)
    ScriptedHistory.build(user, calibers(:nine_mm))
    sign_in_as(user)
    get root_path(range: "MAX")
    assert_response :success
    assert_select "nav[aria-label='Net worth range'] a", ChartRange::KEYS.size
    assert_select "nav[aria-label='Net worth range'] a.active", "MAX"
    assert_select "figure.chart svg polyline"
    assert_select "figcaption", /Latest \$1,825\.35/
    assert_select "#net-worth", "$1,825.35"
  end

  test "chart ranges never leak another user's history" do
    fund(users(:two), 1_000_000)
    sign_in_as(users(:one))
    get root_path(range: "MAX")
    assert_select "figcaption", /Latest \$0\.00/
  end

  test "unknown range falls back to the default" do
    sign_in_as(users(:one))
    get root_path(range: "bogus")
    assert_select "nav[aria-label='Net worth range'] a.active", "1D"
  end
end
