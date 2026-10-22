require "test_helper"

class ChartRangeTest < ActiveSupport::TestCase
  test "all lists every range in order" do
    assert_equal %w[1D 1W 1M YTD 1Y MAX], ChartRange.all.map(&:key)
  end

  test "parse handles case, instances and unknown values" do
    assert_equal "1W", ChartRange.parse("1w").key
    range = ChartRange.new("YTD")
    assert_same range, ChartRange.parse(range)
    assert_equal "1D", ChartRange.parse("bogus").key
    assert_equal "1D", ChartRange.parse(nil).key
  end

  test "new rejects unknown keys" do
    assert_raises(ArgumentError) { ChartRange.new("5Y") }
  end

  test "resolution per range" do
    assert_equal %i[raw raw hourly daily daily weekly], ChartRange.all.map(&:resolution)
  end

  test "to_s is the key" do
    assert_equal "1M", ChartRange.new("1M").to_s
  end

  test "relative ranges" do
    now = Time.utc(2026, 6, 15, 10, 30)
    assert_equal Time.utc(2026, 6, 14, 10, 30), ChartRange.new("1D").start_at(now: now)
    assert_equal Time.utc(2026, 6, 8, 10, 30), ChartRange.new("1W").start_at(now: now)
    assert_equal Time.utc(2026, 5, 15, 10, 30), ChartRange.new("1M").start_at(now: now)
    assert_equal Time.utc(2025, 6, 15, 10, 30), ChartRange.new("1Y").start_at(now: now)
  end

  test "defaults to Time.current" do
    travel_to Time.utc(2026, 6, 15, 10, 30) do
      assert_equal Time.utc(2026, 6, 14, 10, 30), ChartRange.new("1D").start_at
    end
  end

  test "YTD is the start of the UTC calendar year" do
    travel_to Time.utc(2026, 12, 31, 23, 59, 59) do
      assert_equal Time.utc(2026, 1, 1), ChartRange.new("YTD").start_at
    end
    travel_to Time.utc(2027, 1, 1, 0, 0, 0) do
      assert_equal Time.utc(2027, 1, 1), ChartRange.new("YTD").start_at
    end
    travel_to Time.utc(2026, 1, 1, 0, 0, 1) do
      assert_equal Time.utc(2026, 1, 1), ChartRange.new("YTD").start_at
    end
  end

  test "YTD uses UTC even for non-UTC input times" do
    now = Time.new(2027, 1, 1, 1, 0, 0, "+02:00") # 2026-12-31 23:00 UTC
    assert_equal Time.utc(2026, 1, 1), ChartRange.new("YTD").start_at(now: now)
  end

  test "leap day edges" do
    leap = Time.utc(2028, 2, 29, 12)
    assert_equal Time.utc(2027, 2, 28, 12), ChartRange.new("1Y").start_at(now: leap)
    assert_equal Time.utc(2028, 1, 29, 12), ChartRange.new("1M").start_at(now: leap)
    assert_equal Time.utc(2028, 1, 1), ChartRange.new("YTD").start_at(now: leap)
    assert_equal Time.utc(2028, 2, 22, 12), ChartRange.new("1W").start_at(now: leap)
    assert_equal Time.utc(2028, 2, 28, 12), ChartRange.new("1D").start_at(now: leap)
    after = Time.utc(2028, 3, 1, 0)
    assert_equal Time.utc(2028, 2, 29, 0), ChartRange.new("1D").start_at(now: after)
    assert_equal Time.utc(2028, 2, 1, 0), ChartRange.new("1M").start_at(now: after)
    assert_equal Time.utc(2027, 3, 1, 0), ChartRange.new("1Y").start_at(now: after)
    assert_equal Time.utc(2028, 1, 1), ChartRange.new("YTD").start_at(now: after)
  end

  test "year boundary for relative ranges" do
    now = Time.utc(2027, 1, 1, 0, 0)
    assert_equal Time.utc(2026, 12, 25), ChartRange.new("1W").start_at(now: now)
    assert_equal Time.utc(2026, 12, 1), ChartRange.new("1M").start_at(now: now)
    assert_equal Time.utc(2026, 1, 1), ChartRange.new("1Y").start_at(now: now)
  end

  test "MAX starts at the earliest data or now when empty" do
    now = Time.utc(2026, 6, 15)
    earliest = Time.utc(2020, 2, 29)
    assert_equal earliest, ChartRange.new("MAX").start_at(now: now, earliest: earliest)
    assert_equal now, ChartRange.new("MAX").start_at(now: now)
  end
end
