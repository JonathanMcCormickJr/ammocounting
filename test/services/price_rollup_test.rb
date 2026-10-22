require "test_helper"

class PriceRollupTest < ActiveSupport::TestCase
  setup do
    PriceTick.delete_all
    @caliber = calibers(:nine_mm)
    @now = Time.utc(2026, 3, 20, 12, 30) # cutoff 2026-03-13 12:00
  end

  def tick(time, price)
    @caliber.price_ticks.create!(as_of: time, price_centicents: price)
  end

  def buckets(resolution)
    @caliber.price_buckets.where(resolution: resolution).order(:bucket_start)
  end

  test "bucket_start per resolution, weeks start Monday" do
    t = Time.utc(2026, 3, 18, 15, 45, 10) # Wednesday
    assert_equal Time.utc(2026, 3, 18, 15), PriceRollup.bucket_start(t, "hourly")
    assert_equal Time.utc(2026, 3, 18), PriceRollup.bucket_start(t, "daily")
    assert_equal Time.utc(2026, 3, 16), PriceRollup.bucket_start(t, "weekly")
  end

  test "combine builds OHLC from ordered entries" do
    e = PriceRollup::Entry
    t = Time.utc(2026, 3, 18, 10)
    combined = PriceRollup.combine([
      e.new(t, 5, 5, 5, 5, 1, t), e.new(t + 60, 9, 9, 9, 9, 1, t + 60),
      e.new(t + 120, 2, 2, 2, 2, 1, t + 120), e.new(t + 3600, 7, 7, 7, 7, 1, t + 3600)
    ], "hourly")
    assert_equal [ [ t, 5, 9, 2, 2, 3 ], [ t + 3600, 7, 7, 7, 7, 1 ] ],
      combined.map { [ _1.at, _1.open, _1.high, _1.low, _1.close, _1.count ] }
  end

  test "combine merges candles: summed ticks, latest last_as_of" do
    e = PriceRollup::Entry
    t = Time.utc(2026, 3, 18, 10)
    combined = PriceRollup.combine([
      e.new(t, 5, 9, 2, 6, 3, t + 120), e.new(t + 600, 6, 12, 4, 8, 2, t + 700)
    ], "hourly")
    assert_equal [ [ t, 5, 12, 2, 8, 5, t + 700 ] ],
      combined.map { [ _1.at, _1.open, _1.high, _1.low, _1.close, _1.count, _1.last_as_of ] }
  end

  test "combine_ticks builds OHLC per bucket from raw [as_of, price] ticks" do
    t = Time.utc(2026, 3, 18, 10)
    combined = PriceRollup.combine_ticks([ [ t, 5 ], [ t + 60, 9 ], [ t + 120, 2 ], [ t + 3600, 7 ] ], "hourly")
    assert_equal [ [ t, 5, 9, 2, 2, 3, t + 120 ], [ t + 3600, 7, 7, 7, 7, 1, t + 3600 ] ],
      combined.map { [ _1.at, _1.open, _1.high, _1.low, _1.close, _1.count, _1.last_as_of ] }
  end

  test "rolls ticks older than 7 days into hourly daily and weekly buckets" do
    tick(Time.utc(2026, 3, 10, 10, 0), 100)
    tick(Time.utc(2026, 3, 10, 10, 5), 150)
    tick(Time.utc(2026, 3, 10, 10, 10), 120)
    tick(Time.utc(2026, 3, 10, 11, 0), 130)
    tick(Time.utc(2026, 3, 11, 0, 0), 90)
    PriceRollup.call(now: @now)

    hourly = buckets("hourly")
    assert_equal 3, hourly.size
    first = hourly.first
    assert_equal [ Time.utc(2026, 3, 10, 10), 100, 150, 100, 120, 3, Time.utc(2026, 3, 10, 10, 10) ],
      [ first.bucket_start, first.open_centicents, first.high_centicents, first.low_centicents,
        first.close_centicents, first.tick_count, first.last_as_of ]

    day = buckets("daily").first
    assert_equal Time.utc(2026, 3, 10), day.bucket_start
    assert_equal [ 100, 150, 100, 130, 4 ], [ day.open_centicents, day.high_centicents, day.low_centicents, day.close_centicents, day.tick_count ]
    assert_equal 2, buckets("daily").size

    week = buckets("weekly").first
    assert_equal Time.utc(2026, 3, 9), week.bucket_start
    assert_equal [ 100, 150, 90, 90, 5 ], [ week.open_centicents, week.high_centicents, week.low_centicents, week.close_centicents, week.tick_count ]
  end

  test "does not roll recent ticks and deletes nothing" do
    tick(Time.utc(2026, 3, 10, 10), 100)
    tick(Time.utc(2026, 3, 19, 10), 200)
    tick(Time.utc(2026, 3, 13, 12), 300) # exactly at the cutoff stays raw
    PriceRollup.call(now: @now)
    assert_equal 3, PriceTick.count
    assert_equal [ Time.utc(2026, 3, 10, 10) ], buckets("hourly").map(&:bucket_start)
  end

  test "does nothing when there are no old ticks" do
    tick(Time.utc(2026, 3, 19, 10), 200)
    assert_no_difference "PriceBucket.count" do
      PriceRollup.call(now: @now)
    end
  end

  test "is idempotent and refreshes partial buckets incrementally" do
    tick(Time.utc(2026, 3, 10, 10), 100)
    PriceRollup.call(now: @now)
    snapshot = PriceBucket.order(:id).pluck(:resolution, :bucket_start, :close_centicents, :tick_count)
    PriceRollup.call(now: @now)
    assert_equal snapshot, PriceBucket.order(:id).pluck(:resolution, :bucket_start, :close_centicents, :tick_count)

    tick(Time.utc(2026, 3, 10, 10, 30), 50)
    tick(Time.utc(2026, 3, 12, 8), 70)
    PriceRollup.call(now: @now)
    assert_equal [ 100, 50, 2 ], buckets("hourly").first.then { [ _1.open_centicents, _1.close_centicents, _1.tick_count ] }
    day = buckets("daily").first
    assert_equal [ 2, 50 ], [ day.tick_count, day.close_centicents ]
    assert_equal 3, buckets("weekly").sum(:tick_count)
  end

  test "rolls each caliber separately" do
    tick(Time.utc(2026, 3, 10, 10), 100)
    calibers(:twenty_two).price_ticks.create!(as_of: Time.utc(2026, 3, 10, 10), price_centicents: 900)
    PriceRollup.call(now: @now)
    assert_equal 1, buckets("hourly").size
    assert_equal 900, calibers(:twenty_two).price_buckets.find_by(resolution: "hourly").close_centicents
  end

  test "defaults now to current time" do
    travel_to @now do
      tick(Time.utc(2026, 3, 10, 10), 100)
      PriceRollup.call
      assert_equal 1, buckets("hourly").size
    end
  end
end
