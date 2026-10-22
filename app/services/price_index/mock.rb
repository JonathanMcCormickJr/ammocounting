require "digest"

module PriceIndex
  # Deterministic, bounded random walk. Each tick moves every caliber by a
  # pseudo-random whole number of basis points within +-2%, derived from
  # SHA-256(seed, caliber id, tick time) (the only thing computed in Ruby; the
  # engine turns it into a bounded change with bps_from_random and takes the
  # step with next_price). It continues from the
  # last stored PriceTick (or the caliber's starting price) and is idempotent
  # for a given tick time.
  class Mock
    MAX_STEP_BPS = 200
    FLOOR_CENTICENTS = 100
    CEILING_CENTICENTS = 100_000

    def initialize(seed: Rails.configuration.x.price_index_seed,
                   interval_minutes: Rails.configuration.x.tick_interval_minutes)
      @seed = seed
      @interval_minutes = interval_minutes
    end

    def current_prices(now: Time.current)
      as_of = PriceTick.floor_time(now, interval_minutes: @interval_minutes)
      latest = PriceTick.latest_by_caliber
      Caliber.ordered.map do |caliber|
        { caliber_id: caliber.id, slug: caliber.slug, as_of: as_of,
          price_centicents: price_for(caliber, latest[caliber.id], as_of) }
      end
    end

    # Basis-point move for a caliber at a tick time, in -MAX_STEP_BPS..MAX_STEP_BPS.
    def step_bps(caliber_id, as_of)
      digest = Digest::SHA256.digest("#{@seed}:#{caliber_id}:#{as_of.to_i}")
      LedgerEngine.bps_from_random(digest.unpack1("Q>"), MAX_STEP_BPS)
    end

    # Applies a basis-point move (engine next_price: truncating toward zero,
    # then clamped to bounds). |bps| must be within MAX_STEP_BPS.
    def self.apply_step(price, bps)
      LedgerEngine.next_price(price, bps, max_step_bps: MAX_STEP_BPS, floor: FLOOR_CENTICENTS, ceiling: CEILING_CENTICENTS)
    end

    private

    def price_for(caliber, last_tick, as_of)
      return last_tick.price_centicents if last_tick && last_tick.as_of >= as_of

      base = last_tick ? last_tick.price_centicents : caliber.starting_price_centicents
      self.class.apply_step(base, step_bps(caliber.id, as_of))
    end
  end
end
