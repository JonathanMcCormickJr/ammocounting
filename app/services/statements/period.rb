module Statements
  # A reporting period (from, to] in UTC: `from` exclusive, `to` inclusive, both
  # whole seconds. Built from request parameters by .parse; an unusable request
  # raises Statements::Invalid with a displayable message.
  #
  # Decisions:
  # * Presets: past_day / past_week / past_month / past_year (calendar offsets
  #   back from now), ytd (includes 00:00:00 UTC Jan 1), max (from account start).
  # * Custom: `from` and `to` are YYYY-MM-DD dates, both whole days included: the
  #   period is after 23:59:59 UTC of the day before `from` through 23:59:59 UTC
  #   of `to` (or now if `to` is today). Missing `from` = account start, missing `to` = now.
  # * A start before the account began is CLAMPED to the account start (with a
  #   note), because nothing exists earlier. An end before the account began, an
  #   end after today, or an end not after the start is REJECTED.
  # * The account start is User#history_start; the lower bound is one second
  #   before it so the first transaction (the initial deposit) is inside (from, to].
  class Period
    PRESETS = {
      "past_day" => "Past day", "past_week" => "Past week", "past_month" => "Past month",
      "ytd" => "YTD", "past_year" => "Past year", "max" => "MAX"
    }.freeze
    DEFAULT_PRESET = "past_month".freeze
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    attr_reader :key, :from, :to, :notes

    class << self
      # params: anything responding to [] with :period, :from, :to (String or nil).
      def parse(params, origin:, now: Time.current)
        now = now.utc.floor
        floor = origin.utc.floor - 1
        if blank?(params[:from]) && blank?(params[:to])
          preset(params[:period].presence || DEFAULT_PRESET, floor, now)
        else
          custom(params[:from], params[:to], floor, now)
        end
      end

      # A single instant for the balance sheet: end of the given date (or now
      # when that date is today or the value is blank). Rejects future dates and
      # dates before the account began.
      def as_of(value, origin:, now: Time.current)
        now = now.utc.floor
        return now if blank?(value)

        date = parse_date(value, "As-of date")
        raise Invalid, "As-of date #{value} is in the future." if date > now.to_date

        moment = [ end_of(date), now ].min
        raise Invalid, "As-of date #{value} is before your account began (#{origin.utc.floor.to_date})." if moment < origin.utc.floor

        moment
      end

      private

      def blank?(value)
        value.nil? || value == ""
      end

      def preset(key, floor, now)
        raise Invalid, "Unknown period." unless PRESETS.key?(key)

        from = case key
        when "past_day" then now - 1.day
        when "past_week" then now - 1.week
        when "past_month" then now - 1.month
        when "past_year" then now - 1.year
        when "ytd" then now.beginning_of_year - 1
        else floor
        end
        build(key, from, now, floor)
      end

      def custom(from_value, to_value, floor, now)
        from = blank?(from_value) ? floor : parse_date(from_value, "Start date").then { Time.utc(_1.year, _1.month, _1.day) - 1 }
        to = blank?(to_value) ? now : custom_end(to_value, floor, now)
        build("custom", from, to, floor)
      end

      def custom_end(value, floor, now)
        date = parse_date(value, "End date")
        raise Invalid, "End date #{value} is in the future." if date > now.to_date

        [ end_of(date), now ].min.tap do |to|
          raise Invalid, "End date #{value} is before your account began." if to <= floor
        end
      end

      def build(key, from, to, floor)
        notes = []
        if from < floor
          from = floor
          notes << "Start was before your account began; the period starts when it did."
        end
        raise Invalid, "The end must be after the start." if to <= from

        new(key, from, to, notes)
      end

      def parse_date(value, name)
        raise ArgumentError unless value.is_a?(String) && value.match?(DATE_FORMAT)

        Date.iso8601(value)
      rescue ArgumentError # Date::Error is an ArgumentError
        raise Invalid, "#{name} must be a real date written YYYY-MM-DD."
      end

      def end_of(date)
        Time.utc(date.year, date.month, date.day, 23, 59, 59)
      end
    end

    def initialize(key, from, to, notes)
      @key = key
      @from = from
      @to = to
      @notes = notes.freeze
    end

    def label
      PRESETS.fetch(key, "Custom")
    end

    def preset?
      PRESETS.key?(key)
    end
  end
end
