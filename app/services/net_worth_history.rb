# Query object: a user's net worth (engine total equity) over a ChartRange.
#
# Holdings are revalued on every tick, so equity as of T is the engine balance
# sheet of the persisted running totals as of T. The engine picks at most
# MAX_POINTS evenly spaced sample times (sample_times); for each, the latest
# ledger row at or before it is read (one indexed LIMIT 1 query on
# user_id + occurred_at + id) and collapsed and checked by the engine.
# Query count: 1 (history_start, one MIN query on the ledger) + at most
# MAX_POINTS (one per sample); no SUM, GROUP BY or strftime over money.
#
# The window starts at the range start, clamped to the account start
# (User#history_start); MAX starts there. It ends at `now` (whole seconds, UTC).
class NetWorthHistory
  MAX_POINTS = 200
  Point = Data.define(:at, :value)

  def self.series(user, range:, now: Time.current)
    new(user, ChartRange.parse(range), now).series
  end

  def initialize(user, range, now)
    @user = user
    @range = range
    @finish = now.utc.floor
  end

  def series
    origin = @user.history_start
    start = [ [ @range.start_at(now: @finish, earliest: origin).utc.floor, origin ].max, @finish ].min
    LedgerEngine.sample_times(start.to_i, @finish.to_i, MAX_POINTS).times.map do |epoch|
      at = Time.at(epoch).utc
      Point.new(at: at, value: Ledger::Balances.sheet(@user, at).total_equity)
    end
  rescue LedgerEngine::Error => e
    raise Ledger::IntegrityError, "Net worth history failed an engine check (#{e.status} in #{e.operation})"
  end
end
