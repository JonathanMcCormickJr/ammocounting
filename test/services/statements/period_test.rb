require "test_helper"

module Statements
  class PeriodTest < ActiveSupport::TestCase
    ORIGIN = Time.utc(2026, 1, 10, 8, 30, 15, 500_000)
    NOW = Time.utc(2026, 3, 15, 12, 0, 0, 250_000)

    def parse(params = {}, origin: ORIGIN, now: NOW)
      Period.parse(params, origin: origin, now: now)
    end

    def error_for(params = {})
      assert_raises(Invalid) { parse(params) }.message
    end

    test "default is the past month, to now floored to the second" do
      period = parse
      assert_equal "past_month", period.key
      assert_equal [ Time.utc(2026, 2, 15, 12), Time.utc(2026, 3, 15, 12) ], [ period.from, period.to ]
      assert_equal "Past month", period.label
      assert_predicate period, :preset?
      assert_empty period.notes
    end

    test "presets" do
      assert_equal Time.utc(2026, 3, 14, 12), parse({ period: "past_day" }).from
      assert_equal Time.utc(2026, 3, 8, 12), parse({ period: "past_week" }).from
      assert_equal Time.utc(2025, 3, 15, 12), parse({ period: "past_year" }, origin: Time.utc(2020, 1, 1)).from
      assert_equal Time.utc(2025, 12, 31, 23, 59, 59), parse({ period: "ytd" }, origin: Time.utc(2020, 1, 1)).from
    end

    test "ytd includes midnight UTC Jan 1" do
      period = parse({ period: "ytd" }, origin: Time.utc(2020, 1, 1))
      assert_equal "YTD", period.label
    end

    test "max starts one second before the account start so the first transaction is inside" do
      period = parse({ period: "max" })
      assert_equal Time.utc(2026, 1, 10, 8, 30, 14), period.from
      assert_empty period.notes
    end

    test "a preset reaching before the account began is clamped with a note" do
      period = parse({ period: "past_year" })
      assert_equal Time.utc(2026, 1, 10, 8, 30, 14), period.from
      assert_equal [ "Start was before your account began; the period starts when it did." ], period.notes
    end

    test "unknown preset is rejected" do
      assert_equal "Unknown period.", error_for({ period: "decade" })
      assert_equal "Unknown period.", error_for({ period: [ "max" ] })
    end

    test "custom dates include both whole days" do
      period = parse({ from: "2026-02-01", to: "2026-02-28" })
      assert_equal [ "custom", "Custom" ], [ period.key, period.label ]
      refute_predicate period, :preset?
      assert_equal [ Time.utc(2026, 1, 31, 23, 59, 59), Time.utc(2026, 2, 28, 23, 59, 59) ], [ period.from, period.to ]
    end

    test "custom end today is now; missing from is the account start; missing to is now" do
      assert_equal NOW.floor, parse({ from: "2026-03-01", to: "2026-03-15" }).to
      only_to = parse({ to: "2026-02-01" })
      assert_equal [ Time.utc(2026, 1, 10, 8, 30, 14), Time.utc(2026, 2, 1, 23, 59, 59) ], [ only_to.from, only_to.to ]
      assert_empty only_to.notes
      only_from = parse({ from: "2026-03-01" })
      assert_equal [ Time.utc(2026, 2, 28, 23, 59, 59), NOW.floor ], [ only_from.from, only_from.to ]
    end

    test "custom start before the account began is clamped with a note" do
      period = parse({ from: "2025-01-01", to: "2026-02-01" })
      assert_equal Time.utc(2026, 1, 10, 8, 30, 14), period.from
      assert_equal 1, period.notes.size
    end

    test "blank strings count as missing" do
      assert_equal "past_month", parse({ from: "", to: "", period: "" }).key
    end

    test "rejects unparsable dates" do
      message = "Start date must be a real date written YYYY-MM-DD."
      assert_equal message, error_for({ from: "yesterday" })
      assert_equal message, error_for({ from: "2026-02-30" })
      assert_equal message, error_for({ from: "2026-2-1" })
      assert_equal message, error_for({ from: [ "2026-02-01" ] })
      assert_equal "End date must be a real date written YYYY-MM-DD.", error_for({ to: "2026-13-01" })
      assert_equal "End date must be a real date written YYYY-MM-DD.", error_for({ from: "2026-02-01", to: "x" })
    end

    test "rejects future end dates" do
      assert_equal "End date 2026-03-16 is in the future.", error_for({ to: "2026-03-16" })
      assert_equal "End date 9999-12-31 is in the future.", error_for({ from: "2026-02-01", to: "9999-12-31" })
    end

    test "rejects an end before the account began" do
      assert_equal "End date 2026-01-09 is before your account began.", error_for({ to: "2026-01-09" })
    end

    test "rejects end not after start" do
      assert_equal "The end must be after the start.", error_for({ from: "2026-03-01", to: "2026-02-01" })
      assert_equal "The end must be after the start.", error_for({ from: "2026-03-20" }) # future start
    end

    test "a user created this very second still gets a valid MAX period" do
      period = parse({ period: "max" }, origin: NOW)
      assert_equal [ NOW.floor - 1, NOW.floor ], [ period.from, period.to ]
    end

    test "as_of defaults to now and otherwise takes the end of the day" do
      assert_equal NOW.floor, Period.as_of(nil, origin: ORIGIN, now: NOW)
      assert_equal NOW.floor, Period.as_of("", origin: ORIGIN, now: NOW)
      assert_equal NOW.floor, Period.as_of("2026-03-15", origin: ORIGIN, now: NOW)
      assert_equal Time.utc(2026, 2, 1, 23, 59, 59), Period.as_of("2026-02-01", origin: ORIGIN, now: NOW)
    end

    test "as_of rejects bad, future and pre-account dates" do
      [ [ "nope", "As-of date must be a real date written YYYY-MM-DD." ],
        [ "2026-03-16", "As-of date 2026-03-16 is in the future." ],
        [ "2026-01-09", "As-of date 2026-01-09 is before your account began (2026-01-10)." ] ].each do |value, message|
        assert_equal message, assert_raises(Invalid) { Period.as_of(value, origin: ORIGIN, now: NOW) }.message
      end
    end

    test "as_of on the account's first day is allowed even before its first second" do
      assert_equal Time.utc(2026, 1, 10, 23, 59, 59), Period.as_of("2026-01-10", origin: ORIGIN, now: NOW)
    end
  end
end
