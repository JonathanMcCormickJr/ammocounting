require "digest"

# Crises that spike ammo prices, with a reason the player can read. The schedule
# is a pure function of the price seed (like the walk itself, so every player
# lives through the same history): one event 6 to 10 years after the previous
# one (the first, after the game start). Each ramps prices up for `ramp_days`
# game days (the spike), then unwinds for as long (the crisis ends), after which
# the normal random walk simply continues. PriceIndex::Mock applies the drift.
class MarketEvent
  # slugs: the calibers affected, nil for all of them.
  Kind = Data.define(:headline, :resolution, :ramp_days, :slugs)

  RIFLE_SLUGS = %w[223-556x45 300-blk 762x39 308-762x51 30-06 65-creedmoor 243-win 9mm].freeze

  KINDS = [
    Kind.new(headline: "The Bubonic Plague is back! Panicked shoppers are stockpiling everything.",
      resolution: "The plague has passed and the shelves are filling again.", ramp_days: 60, slugs: nil),
    Kind.new(headline: "Democrats have been elected to a federal trifecta, and buyers fear new restrictions.",
      resolution: "The feared restrictions never materialised and buyers have calmed down.", ramp_days: 45, slugs: nil),
    Kind.new(headline: "Republicans have been elected to a federal trifecta, and a wave of celebratory range days has begun.",
      resolution: "The range-day craze has faded.", ramp_days: 45, slugs: nil),
    Kind.new(headline: "Global conflicts have driven a spike in military demand for ammo.",
      resolution: "The conflicts have de-escalated and military orders have dried up.", ramp_days: 90, slugs: RIFLE_SLUGS),
    Kind.new(headline: "A primer factory fire has choked the supply of ammunition.",
      resolution: "The primer factory is rebuilt and supply has recovered.", ramp_days: 75, slugs: nil),
    Kind.new(headline: "Rumors of a coming ammunition ban have set off a buying frenzy.",
      resolution: "The ban rumors were false and the frenzy is over.", ramp_days: 30, slugs: nil)
  ].freeze

  MIN_GAP_YEARS = 6
  GAP_SPREAD_DAYS = 1460 # 4 more years at most: 6..10 years between events
  DRIFT_BPS = (100..180).freeze # per game day, while rising (and the reverse while unwinding)
  # The engine caps one price step; normal walk steps are within Mock::MAX_STEP_BPS.
  MAX_DRIFT_BPS = DRIFT_BPS.end

  # phase(time): :rising from starts_at up to peak_at, :unwinding from peak_at up
  # to ends_at (the crisis is over), nil otherwise.
  class Event < Data.define(:index, :kind, :starts_at, :peak_at, :ends_at, :drift_bps)
    def phase(time)
      if (starts_at...peak_at).cover?(time) then :rising
      elsif (peak_at...ends_at).cover?(time) then :unwinding
      end
    end

    def affects?(slug)
      kind.slugs.nil? || kind.slugs.include?(slug)
    end

    # What the news says at `time`: the crisis while it builds, its end while it unwinds.
    def news(time)
      phase(time) == :unwinding ? kind.resolution : kind.headline
    end
  end

  class << self
    # All events of the game (the 128 years of FastForward::MAX_YEARS), oldest first.
    def all(seed: Rails.configuration.x.price_index_seed)
      @schedules ||= {}
      @schedules[seed] ||= build(seed)
    end

    # The event under way at `time`, or nil.
    def current(time, seed: Rails.configuration.x.price_index_seed)
      all(seed: seed).find { _1.phase(time) }
    end

    # Events that began at or before `time`, oldest first (nothing from the future).
    def started_by(time, seed: Rails.configuration.x.price_index_seed)
      all(seed: seed).select { _1.starts_at <= time }
    end

    # Events that begin in (from, to]: what a player skipped over while fast-forwarding.
    def between(from, to, seed: Rails.configuration.x.price_index_seed)
      all(seed: seed).select { _1.starts_at > from && _1.starts_at <= to }
    end

    # Signed basis points an event adds to a caliber's price on the tick at `time`:
    # up while the crisis builds, down while it unwinds, 0 otherwise.
    def drift_bps(slug, time, seed: Rails.configuration.x.price_index_seed)
      event = current(time, seed: seed)
      return 0 unless event&.affects?(slug)

      event.phase(time) == :rising ? event.drift_bps : LedgerEngine.negate(event.drift_bps)
    end

    private

    # Deterministic from the seed and the event number alone.
    def build(seed)
      limit = Rails.configuration.x.game_start.advance(years: FastForward::MAX_YEARS)
      events = []
      starts = Rails.configuration.x.game_start
      index = 0
      loop do
        random = Random.new(Digest::SHA256.digest("#{seed}:event:#{index}").unpack1("Q>"))
        starts = starts.advance(years: MIN_GAP_YEARS).advance(days: random.rand(0..GAP_SPREAD_DAYS))
        break if starts > limit

        kind = KINDS[random.rand(KINDS.size)]
        peak = starts.advance(days: kind.ramp_days)
        events << Event.new(index: index, kind: kind, starts_at: starts, peak_at: peak,
          ends_at: peak.advance(days: kind.ramp_days), drift_bps: random.rand(DRIFT_BPS))
        index = index.succ
      end
      events.freeze
    end
  end
end
