require "test_helper"

class ChartHelperTest < ActionView::TestCase
  include MoneyHelper

  P = PriceHistory::Point

  def point(minute, price)
    P.new(Time.utc(2026, 1, 1, 0, minute), price, price, price, price)
  end

  test "empty series renders a message" do
    assert_includes price_chart([]), "No price data"
  end

  test "renders an svg polyline with integer coordinates" do
    html = price_chart([ point(0, 100), point(10, 300), point(20, 200) ])
    assert_includes html, "<svg"
    assert_includes html, 'points="0,240 360,0 720,120"'
    assert_includes html, "Low $0.01 / High $0.03"
  end

  test "flat series draws mid-height" do
    assert_equal "0,120 720,120", chart_coordinates([ point(0, 5), point(5, 5) ], 5, 5)
  end

  test "single point draws at center" do
    assert_equal "360,120", chart_coordinates([ point(0, 5) ], 5, 5)
  end

  test "chart_coordinates scales within the viewBox" do
    coords = chart_coordinates([ point(0, 1), point(1, 2), point(7, 10) ], 1, 10)
    xs_ys = coords.split.map { _1.split(",").map(&:to_i) }
    assert(xs_ys.all? { |x, y| x.between?(0, 720) && y.between?(0, 240) })
    assert_equal [ 0, 240 ], xs_ys.first
    assert_equal [ 720, 0 ], xs_ys.last
  end

  test "net worth chart plots values and captions low, high and latest in dollars" do
    points = [ 100, 300, 200 ].each_with_index.map { |cents, i| NetWorthHistory::Point.new(at: Time.utc(2026, 1, 1, 0, i), value: cents) }
    html = net_worth_chart(points)
    assert_includes html, 'points="0,240 360,0 720,120"'
    assert_includes html, "Low $1.00 / High $3.00 / Latest $2.00"
    assert_includes html, "Net worth $1.00 to $3.00"
  end

  test "net worth chart with a single point or flat values draws mid-height" do
    html = net_worth_chart([ NetWorthHistory::Point.new(at: Time.utc(2026, 1, 1), value: 500) ])
    assert_includes html, 'points="360,120"'
  end
end
