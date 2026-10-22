require "test_helper"

class PriceHistoryTest < ActiveSupport::TestCase
  setup do
    PriceTick.delete_all
    @caliber = calibers(:nine_mm)
    @now = Time.utc(2026, 3, 20, 12, 0)
  end

  def tick(time, price)
    @caliber.price_ticks.create!(as_of: time, price_centicents: price)
  end

  def series(range, now: @now)
    PriceHistory.series(@caliber, range: range, now: now)
  end

  test "1D returns raw ticks inside the window in order" do
    tick(@now - 2.days, 1)
    tick(@now - 1.hour, 300)
    tick(@now - 2.hours, 200)
    points = series("1D")
    assert_equal [ 200, 300 ], points.map(&:close)
    assert_equal [ @now - 2.hours, @now - 1.hour ], points.map(&:at)
  end

  test "raw points have equal OHLC" do
    tick(@now - 1.hour, 300)
    point = series("1W").first
    assert_equal [ 300, 300, 300, 300 ], [ point.open, point.high, point.low, point.close ]
  end

  test "ticks after now are excluded" do
    tick(@now + 1.hour, 5)
    assert_empty series("1D")
  end

  test "accepts ChartRange instances and defaults now" do
    tick(@now - 1.hour, 300)
    travel_to @now do
      assert_equal 1, PriceHistory.series(@caliber, range: ChartRange.new("1D")).size
    end
  end

  test "empty series" do
    assert_empty series("MAX")
  end

  test "1M uses hourly buckets plus raw tail after the last bucketed tick" do
    tick(Time.utc(2026, 3, 1, 10, 0), 100)
    tick(Time.utc(2026, 3, 1, 10, 5), 140)
    tick(Time.utc(2026, 3, 19, 9, 0), 500)
    tick(Time.utc(2026, 3, 20, 11, 0), 600)
    PriceRollup.call(now: @now)
    points = series("1M")
    assert_equal [ Time.utc(2026, 3, 1, 10), Time.utc(2026, 3, 19, 9), Time.utc(2026, 3, 20, 11) ].sort,
      points.map(&:at).sort
    first = points.first
    assert_equal [ 100, 140, 100, 140 ], [ first.open, first.high, first.low, first.close ]
    assert_equal [ 140, 500, 600 ], points.map(&:close)
  end

  test "bucketed window excludes buckets that ended before the start" do
    tick(Time.utc(2026, 1, 1, 10), 100)
    tick(Time.utc(2026, 3, 1, 10), 200)
    PriceRollup.call(now: @now)
    assert_equal [ 200 ], series("1M").map(&:close)
  end

  test "YTD and 1Y use daily buckets" do
    tick(Time.utc(2025, 12, 31, 10), 100)
    tick(Time.utc(2026, 2, 3, 10), 200)
    tick(Time.utc(2026, 2, 3, 11), 250)
    PriceRollup.call(now: @now)
    ytd = series("YTD")
    assert_equal [ Time.utc(2026, 2, 3) ], ytd.map(&:at)
    assert_equal [ 200, 250, 200, 250 ], [ ytd.first.open, ytd.first.high, ytd.first.low, ytd.first.close ]
    assert_equal [ Time.utc(2025, 12, 31), Time.utc(2026, 2, 3) ], series("1Y").map(&:at)
  end

  test "MAX uses weekly buckets from the earliest data" do
    tick(Time.utc(2020, 2, 29, 10), 100)
    tick(Time.utc(2026, 3, 1, 10), 200)
    PriceRollup.call(now: @now)
    points = series("MAX")
    assert_equal [ Time.utc(2020, 2, 24), Time.utc(2026, 2, 23) ], points.map(&:at)
  end

  test "weekly bucket partially covering the raw window does not hide raw ticks" do
    tick(Time.utc(2026, 3, 9, 10), 100)  # Monday, rolled
    tick(Time.utc(2026, 3, 17, 10), 300) # raw, same-week-or-later but after cutoff
    PriceRollup.call(now: @now)
    assert_equal [ 100, 300 ], series("MAX").map(&:close)
  end

  test "year boundary YTD excludes last year's raw ticks" do
    tick(Time.utc(2026, 12, 31, 23, 55), 100)
    tick(Time.utc(2027, 1, 1, 0, 0), 200)
    now = Time.utc(2027, 1, 1, 0, 5)
    assert_equal [ 200 ], series("YTD", now: now).map(&:close)
  end
end
