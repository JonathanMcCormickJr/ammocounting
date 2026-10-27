# Moves a player's game clock forward by one of the fixed JUMPS, simulating the
# wait before their next buy/sell decision. One-way: there is no rewind. Inside
# the user lock (so atomic: a failure leaves the clock and ledger untouched):
#   1. the shared price world is extended to the new time (Timeline),
#   2. the player's holdings are revalued at every game day passed, so unrealized
#      gains, statements and the net worth chart cover the skipped period,
#   3. the clock moves. The player cannot trade during the skip.
class FastForward
  JUMPS = {
    "day" => { days: 1 }, "week" => { weeks: 1 }, "month" => { months: 1 },
    "quarter" => { months: 3 }, "year" => { years: 1 }
  }.freeze
  LABELS = { "day" => "1 day", "week" => "1 week", "month" => "1 month", "quarter" => "3 months", "year" => "1 year" }.freeze
  # The game ends this many years after the start (a human lifespan, as the history design ceiling).
  MAX_YEARS = 128

  def self.call(user, jump)
    advance = JUMPS[jump.to_s] or raise Ledger::Refused, "Choose how far to fast-forward."
    user.with_lock do
      from = user.game_time
      target = from.advance(**advance)
      raise Ledger::Refused, "The game ends on #{limit.to_date}; you cannot fast-forward past it." if target > limit

      Timeline.extend_to(target)
      revalue_through(user, from, target)
      user.update!(game_time: target)
      target
    end
  end

  def self.limit
    Rails.configuration.x.game_start.advance(years: MAX_YEARS)
  end

  # One revaluation per game day in (from, to], at that day's prices. Nothing to
  # revalue (and no queries per day) when the player holds no rounds.
  def self.revalue_through(user, from, to)
    return if Ledger::Balances.quantities(user).empty?

    days = PriceTick.where(as_of: from..to).where("as_of > ?", from).order(:as_of).pluck(:as_of, :caliber_id, :price_centicents)
    days.group_by(&:first).each do |at, rows|
      Ledger::Revalue.call(user, prices: rows.to_h { |_, caliber_id, price| [ caliber_id, price ] }, at: at)
    end
  end
  private_class_method :revalue_through
end
