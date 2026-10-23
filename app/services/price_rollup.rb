# Rolls raw PriceTicks older than RAW_WINDOW into hourly, daily and weekly OHLC
# PriceBuckets. Nothing is ever deleted. Incremental and idempotent: each run
# re-derives the hourly buckets from the earliest hour that can have changed,
# then daily from hourly and weekly from daily. That hour is the earliest of
#  * the last hourly bucket (it may have been partial), and
#  * any old tick newer in insertion order (id) than every tick already rolled
#    (a late tick: older in time than the resume point, so a plain "from the last
#    bucket" scan would never see it). Hourly buckets store the highest tick id
#    they were built from (last_tick_id) for this.
# Each caliber is rolled in its own transaction (a crash leaves either the old
# buckets or the complete new ones, never a mix of hourly, daily and weekly).
class PriceRollup
  RAW_WINDOW = 7.days
  SPANS = { "hourly" => 1.hour, "daily" => 1.day, "weekly" => 1.week }.freeze

  Entry = Struct.new(:at, :open, :high, :low, :close, :count, :last_as_of, :last_tick_id)

  def self.call(now: Time.current)
    new(now).call
  end

  def initialize(now)
    @cutoff = (now - RAW_WINDOW).utc.beginning_of_hour
  end

  def call
    Caliber.find_each { roll(_1) }
  end

  # Start of the bucket of `resolution` containing `time` (UTC, weeks start Monday).
  def self.bucket_start(time, resolution)
    time = time.utc
    case resolution
    when "hourly" then time.beginning_of_hour
    when "daily" then time.beginning_of_day
    else time.beginning_of_week
    end
  end

  # Merges time-ordered entries into one bucket-level Entry per bucket (engine ohlc_merge).
  def self.combine(entries, resolution)
    entries.group_by { bucket_start(_1.at, resolution) }.map do |start, group|
      entry_for(start, LedgerEngine.ohlc_merge(group.map { candle_for(_1) }))
    end
  end

  # Builds one bucket-level Entry per bucket from time-ordered raw ticks
  # [[as_of, price_centicents, id], ...] (id optional; engine ohlc; last_as_of is the
  # last tick's time, last_tick_id the highest id).
  def self.combine_ticks(ticks, resolution)
    ticks.group_by { |at, _price, _id| bucket_start(at, resolution) }.map do |start, group|
      entry_for(start, LedgerEngine.ohlc(group.map { _1[1] }), last_as_of: group.last.first, last_tick_id: group.filter_map { _1[2] }.max)
    end
  end

  def self.candle_for(entry)
    LedgerEngine::Candle.new(open: entry.open, high: entry.high, low: entry.low, close: entry.close,
      ticks: entry.count, last_as_of: entry.last_as_of.to_i)
  end
  private_class_method :candle_for

  def self.entry_for(start, candle, last_as_of: Time.at(candle.last_as_of).utc, last_tick_id: nil)
    Entry.new(start, candle.open, candle.high, candle.low, candle.close, candle.ticks, last_as_of, last_tick_id)
  end
  private_class_method :entry_for

  private

  def roll(caliber)
    PriceBucket.transaction(requires_new: true) { roll_caliber(caliber) }
  end

  def roll_caliber(caliber)
    hourly_buckets = caliber.price_buckets.where(resolution: "hourly")
    resume = hourly_buckets.maximum(:bucket_start)
    rolled_id = hourly_buckets.order(last_tick_id: :desc).pick(:last_tick_id) || 0
    old = caliber.price_ticks.where(as_of: ...@cutoff)
    pending = resume ? old.where("as_of >= ? OR id > ?", resume, rolled_id) : old
    earliest = pending.order(:as_of).pick(:as_of)
    return unless earliest

    raw = old.where(as_of: self.class.bucket_start(earliest, "hourly")..).order(:as_of).pluck(:as_of, :price_centicents, :id)
    hourly = self.class.combine_ticks(raw, "hourly")
    store(caliber, "hourly", hourly)
    daily = derive(caliber, "hourly", "daily", hourly.first.at)
    derive(caliber, "daily", "weekly", daily.first.at)
  end

  def derive(caliber, from, to, since)
    since = self.class.bucket_start(since, to)
    entries = caliber.price_buckets.where(resolution: from, bucket_start: since..).order(:bucket_start).map do |b|
      Entry.new(b.bucket_start, b.open_centicents, b.high_centicents, b.low_centicents,
        b.close_centicents, b.tick_count, b.last_as_of)
    end
    combined = self.class.combine(entries, to)
    store(caliber, to, combined)
    combined
  end

  def store(caliber, resolution, entries)
    rows = entries.map do |e|
      { caliber_id: caliber.id, resolution: resolution, bucket_start: e.at, open_centicents: e.open,
        high_centicents: e.high, low_centicents: e.low, close_centicents: e.close,
        tick_count: e.count, last_as_of: e.last_as_of, last_tick_id: e.last_tick_id }
    end
    PriceBucket.upsert_all(rows, unique_by: :index_price_buckets_on_bucket)
  end
end
