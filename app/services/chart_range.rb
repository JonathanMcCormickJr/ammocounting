# A chart time range (1D, 1W, 1M, YTD, 1Y, MAX) and the data resolution used
# to draw it: :raw ticks, or :hourly / :daily / :weekly PriceBuckets.
class ChartRange
  RESOLUTIONS = {
    "1D" => :raw, "1W" => :raw, "1M" => :hourly,
    "YTD" => :daily, "1Y" => :daily, "MAX" => :weekly
  }.freeze
  KEYS = RESOLUTIONS.keys.freeze
  DEFAULT_KEY = "1D".freeze

  attr_reader :key

  def self.all
    KEYS.map { new(_1) }
  end

  # Unknown or blank keys fall back to the default range.
  def self.parse(value)
    return value if value.is_a?(ChartRange)

    new(KEYS.include?(value.to_s.upcase) ? value.to_s.upcase : DEFAULT_KEY)
  end

  def initialize(key)
    raise ArgumentError, "unknown range: #{key}" unless KEYS.include?(key)

    @key = key
  end

  def resolution
    RESOLUTIONS.fetch(key)
  end

  def to_s
    key
  end

  # Start of the window ending at `now`. YTD is the start of the current UTC
  # calendar year; MAX is the earliest data (or `now` when there is none).
  def start_at(now: Time.current, earliest: nil)
    now = now.utc
    case key
    when "1D" then now - 1.day
    when "1W" then now - 1.week
    when "1M" then now - 1.month
    when "YTD" then now.beginning_of_year
    when "1Y" then now - 1.year
    else earliest || now
    end
  end
end
