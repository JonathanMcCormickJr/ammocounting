# Query object: price series for a caliber over a ChartRange, choosing raw
# ticks or rolled-up buckets so charts stay fast. Where buckets exist they cover
# the older part; raw ticks after the last bucketed tick fill the recent tail.
class PriceHistory
  Point = Struct.new(:at, :open, :high, :low, :close)

  def self.series(caliber, range:, now: Time.current)
    new(caliber, ChartRange.parse(range), now).series
  end

  def initialize(caliber, range, now)
    @caliber = caliber
    @range = range
    @now = now
  end

  def series
    start = @range.start_at(now: @now, earliest: earliest_tick_time)
    buckets = bucket_points(start)
    tail_after = buckets.empty? ? nil : @last_bucketed
    [ *buckets, *raw_points(start, tail_after) ]
  end

  private

  def earliest_tick_time
    @caliber.price_ticks.minimum(:as_of) if @range.key == "MAX"
  end

  def bucket_points(start)
    @last_bucketed = nil
    return [] if @range.resolution == :raw

    resolution = @range.resolution.to_s
    rows = @caliber.price_buckets.where(resolution: resolution, bucket_start: (start - PriceRollup::SPANS.fetch(resolution))..@now)
      .where(last_as_of: start..).order(:bucket_start)
    @last_bucketed = rows.last&.last_as_of # buckets are time ordered, so the last holds the latest tick
    rows.map do |b|
      Point.new(b.bucket_start, b.open_centicents, b.high_centicents, b.low_centicents, b.close_centicents)
    end
  end

  def raw_points(start, after)
    scope = @caliber.price_ticks.where(as_of: start..@now)
    scope = scope.where("as_of > ?", after) if after
    scope.order(:as_of).pluck(:as_of, :price_centicents).map do |at, price|
      Point.new(at, price, price, price, price)
    end
  end
end
