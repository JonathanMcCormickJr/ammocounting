# The shared price world. Every player trades in the same price history, but each
# on their own game clock, so prices are only generated as far as the furthest
# game time any player has reached. Extending is deterministic (the seeded walk,
# one tick per game day) and idempotent, so concurrent or repeated calls agree.
module Timeline
  class << self
    # Stores a tick for every missing game day up to `time` (floored to the tick
    # interval), then rolls the new history up into buckets. Returns the ticks stored.
    def extend_to(time, index: PriceIndex.build)
      target = PriceTick.floor_time(time)
      stored = []
      latest = PriceTick.maximum(:as_of)
      at = latest && PriceTick.floor_time(latest) # the tick grid, even if a stray tick sits off it
      while at &&(at = at.advance(minutes: Rails.configuration.x.tick_interval_minutes)) <= target
        stored.concat(TickRunner.call(now: at, index: index))
      end
      PriceRollup.call(now: target) if stored.any?
      stored
    end
  end
end
