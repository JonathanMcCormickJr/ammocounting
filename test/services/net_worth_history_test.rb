require "test_helper"

class NetWorthHistoryTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 2, 6)

  setup do
    @user = users(:one)
    @nine = calibers(:nine_mm)
  end

  def series(range, user: @user, now: NOW)
    NetWorthHistory.series(user, range: range, now: now)
  end

  # Independent check: every point is the engine balance sheet as of its own time.
  def assert_points_match_ledger(points, user = @user)
    points.each do |point|
      assert_equal Ledger::Balances.sheet(user, point.at).total_equity, point.value, "net worth at #{point.at}"
    end
  end

  test "MAX over the scripted history starts at the deposit and ends at current net worth" do
    ScriptedHistory.build(@user, @nine)
    points = series("MAX")
    assert_equal [ ScriptedHistory::T0, NOW ], [ points.first.at, points.last.at ]
    assert_equal 177_600, points.first.value
    assert_equal 182_535, points.last.value
    assert_operator points.size, :<=, NetWorthHistory::MAX_POINTS
    assert_equal points.map(&:at).sort, points.map(&:at)
    assert_points_match_ledger points
    assert_equal Ledger::Portfolio.for(@user, now: NOW).net_worth, points.last.value
  end

  test "net worth follows each event: revalues, costs and sells" do
    ScriptedHistory.build(@user, @nine)
    at = ->(time) { Ledger::Balances.sheet(@user, time).total_equity }
    assert_equal 177_600 - 375, at.(ScriptedHistory::T1)
    assert_equal 177_225 + 5_000 - 450, at.(ScriptedHistory::T2)
    assert_equal 181_775 + 4_000 - 240, at.(ScriptedHistory::T3)
    assert_equal 182_535, at.(ScriptedHistory::T4)
  end

  test "every range stays within the point bound and matches the ledger" do
    ScriptedHistory.build(@user, @nine)
    ChartRange.all.each do |range|
      points = series(range)
      assert_operator points.size, :<=, NetWorthHistory::MAX_POINTS, range.key
      assert_equal NOW, points.last.at
      assert_points_match_ledger points
    end
  end

  test "a long history is capped at 200 points: one indexed lookup per point plus the account start lookup" do
    ScriptedHistory.build(@user, @nine)
    assert_queries_count(1 + NetWorthHistory::MAX_POINTS) { series("MAX") }
    assert_equal NetWorthHistory::MAX_POINTS, series("MAX").size
  end

  test "the sample times come from the engine" do
    ScriptedHistory.build(@user, @nine)
    sampling = LedgerEngine.sample_times(ScriptedHistory::T0.to_i, NOW.to_i, NetWorthHistory::MAX_POINTS)
    assert_equal sampling.times, series("MAX").map { _1.at.to_i }
  end

  test "accepts a ChartRange object or a string" do
    assert_equal series("1W"), series(ChartRange.new("1W"))
  end

  test "1D covers the last day and clamps to the account start" do
    ScriptedHistory.build(@user, @nine)
    day = series("1D", now: Time.utc(2026, 2, 5, 12))
    assert_equal Time.utc(2026, 2, 4, 12), day.first.at
    assert_equal 181_775 + 4_000 - 240, day.first.value
    clamped = series("1Y")
    assert_equal ScriptedHistory::T0, clamped.first.at # account is younger than a year
  end

  test "a transaction exactly at the window start is in the first point; one second later is not" do
    start = Time.utc(2026, 3, 1)
    Ledger::Deposit.call(@user, 1_000, at: start - 86_400)
    Ledger::Deposit.call(@user, 500, at: start)
    Ledger::Deposit.call(@user, 70, at: start + 1)
    points = series("1D", now: start + 86_400)
    assert_equal [ start, 1_500 ], [ points.first.at, points.first.value ]
    assert_equal 1_570, points.last.value
    assert_points_match_ledger points
  end

  test "YTD at the exact start of the year is a single point" do
    @user.update_columns(created_at: Time.utc(2025, 6, 1))
    Ledger::Deposit.call(@user, 1_776, at: Time.utc(2025, 6, 1))
    points = series("YTD", now: Time.utc(2027, 1, 1))
    assert_equal [ Point(Time.utc(2027, 1, 1), 1_776) ], points
  end

  test "YTD starts at January 1 UTC" do
    @user.update_columns(created_at: Time.utc(2025, 6, 1))
    Ledger::Deposit.call(@user, 1_776, at: Time.utc(2025, 6, 1))
    Ledger::Deposit.call(@user, 24, at: Time.utc(2027, 1, 1, 0, 0, 1))
    points = series("YTD", now: Time.utc(2027, 1, 1, 0, 1))
    assert_equal [ Time.utc(2027, 1, 1), Time.utc(2027, 1, 1, 0, 1) ], [ points.first.at, points.last.at ]
    assert_equal [ 1_776, 1_800 ], [ points.first.value, points.last.value ]
    assert_equal 61, points.size # 60 one-second steps + start
    assert_points_match_ledger points
  end

  test "leap day: 1Y and 1M windows around 2028-02-29" do
    @user.update_columns(created_at: Time.utc(2020, 1, 1))
    Ledger::Deposit.call(@user, 100, at: Time.utc(2020, 1, 1))
    assert_equal Time.utc(2027, 2, 28, 12), series("1Y", now: Time.utc(2028, 2, 29, 12)).first.at
    assert_equal Time.utc(2028, 2, 29, 12), series("1M", now: Time.utc(2028, 3, 29, 12)).first.at
    assert_equal Time.utc(2028, 2, 28, 12), series("1D", now: Time.utc(2028, 2, 29, 12)).first.at
    assert_equal Time.utc(2028, 1, 1), series("YTD", now: Time.utc(2028, 2, 29, 12)).first.at
    leap = series("1W", now: Time.utc(2028, 3, 1))
    assert_equal Time.utc(2028, 2, 23), leap.first.at
    assert_equal 100, leap.last.value
  end

  test "a user with a single deposit has a flat line at the deposit" do
    two = users(:two)
    two.update_columns(created_at: Time.utc(2026, 1, 1))
    Ledger::Deposit.call(two, 177_600, at: Time.utc(2026, 1, 1)) # same instant as account creation
    ChartRange.all.each do |range|
      points = series(range, user: two, now: Time.utc(2026, 1, 2))
      assert_equal [ 177_600 ], points.map(&:value).uniq, range.key
      assert_equal Time.utc(2026, 1, 2), points.last.at
    end
  end

  test "a user created seconds ago gets a short, valid series" do
    @user.update_columns(created_at: NOW - 3)
    Ledger::Deposit.call(@user, 177_600, at: NOW - 3)
    points = series("MAX")
    assert_equal [ NOW - 3, NOW - 2, NOW - 1, NOW ], points.map(&:at)
    assert_equal [ 177_600 ] * 4, points.map(&:value)
    assert_equal 4, series("1D").size
  end

  test "a brand new user with no ledger rows is zero and a user with the clock at creation has one point" do
    two = users(:two)
    two.update_columns(created_at: NOW)
    assert_equal [ NetWorthHistory::Point.new(at: NOW, value: 0) ], series("MAX", user: two)
  end

  test "an account that exists but has no history before the window is empty-valued" do
    two = users(:two)
    two.update_columns(created_at: Time.utc(2026, 1, 1))
    points = series("1D", user: two)
    assert_equal [ 0 ], points.map(&:value).uniq
  end

  test "an account start in the future of now collapses to a single point" do
    @user.update_columns(created_at: NOW + 3600)
    assert_equal [ NOW ], series("MAX").map(&:at)
  end

  test "56 years of history works: bounded points, correct ends" do
    ancient = Time.utc(1970, 1, 2)
    @user.update_columns(created_at: ancient)
    Ledger::Deposit.call(@user, 1_776, at: ancient)
    Ledger::Deposit.call(@user, 24, at: Time.utc(1999, 12, 31, 23, 59, 59))
    points = series("MAX")
    assert_equal [ ancient, NOW ], [ points.first.at, points.last.at ]
    assert_equal [ 1_776, 1_800 ], [ points.first.value, points.last.value ]
    assert_operator points.size, :<=, NetWorthHistory::MAX_POINTS
    assert_points_match_ledger points
  end

  test "an account older than the epoch is outside the engine's time range and fails loudly" do
    @user.update_columns(created_at: Time.utc(1969, 12, 31))
    error = assert_raises(Ledger::IntegrityError) { series("MAX") }
    assert_includes error.message, "sample_times"
  end

  test "other users' postings never leak in" do
    fund(users(:two), 999)
    ScriptedHistory.build(@user, @nine)
    assert_equal 182_535, series("MAX").last.value
  end

  test "an engine failure is raised loudly" do
    ScriptedHistory.build(@user, @nine)
    failing = ->(*) { raise LedgerEngine::Error.new(:unbalanced, :balance_sheet) }
    with_singleton(LedgerEngine, :balance_sheet, failing) do
      error = assert_raises(Ledger::IntegrityError) { series("MAX") }
      assert_includes error.message, "unbalanced"
    end
  end

  private

  def Point(at, value) # rubocop:disable Naming/MethodName
    NetWorthHistory::Point.new(at: at, value: value)
  end
end
