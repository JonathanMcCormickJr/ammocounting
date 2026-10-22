require "test_helper"

class CalibersControllerTest < ActionDispatch::IntegrationTest
  test "index requires authentication" do
    get calibers_path
    assert_redirected_to new_session_path
  end

  test "show requires authentication" do
    get caliber_path(calibers(:nine_mm))
    assert_redirected_to new_session_path
  end

  test "index lists every caliber with its latest price" do
    sign_in_as(users(:one))
    get calibers_path
    assert_response :success
    assert_select "tbody tr", 2
    assert_select "tbody tr:first-child td.num", "$0.255"
    assert_select "tbody tr:last-child td.num", "$0.10"
  end

  test "show renders a chart and range buttons" do
    sign_in_as(users(:one))
    travel_to Time.utc(2026, 1, 1, 0, 10) do
      get caliber_path(calibers(:nine_mm), range: "1W")
    end
    assert_response :success
    assert_select ".ranges a", 6
    assert_select ".ranges a.active", "1W"
    assert_select "svg polyline"
  end

  test "show defaults the range and handles empty data" do
    sign_in_as(users(:one))
    get caliber_path(calibers(:nine_mm), range: "nonsense")
    assert_response :success
    assert_select ".ranges a.active", "1D"
    assert_select "p.empty"
  end

  test "unknown caliber is 404" do
    sign_in_as(users(:one))
    get caliber_path("nope")
    assert_response :not_found
  end
end
