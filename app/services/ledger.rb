# Namespace and shared vocabulary for the double-entry ledger. Money is never
# computed here: quotes, values, basis and statements all come from
# LedgerEngine (the proven SPARK engine). See ledger_core/DESIGN.md.
module Ledger
  ACCOUNTS = { cash: 1, holdings: 2, owners_capital: 3, trading_gain: 4, trading_costs: 5 }.freeze
  SIDES = { debit: 0, credit: 1 }.freeze

  MAX_QUANTITY = 1_000_000_000

  # A user-facing refusal (bad order, not enough cash, ...); the message is safe to display.
  class Refused < StandardError; end

  # The books failed an engine consistency check. Never expected; investigate.
  class IntegrityError < StandardError; end

  # Called after every price tick: revalue everyone holding rounds.
  TICK_HOOK = ->(_ticks) { Revalue.all_holders }

  class << self
    def spread_bps
      Rails.configuration.x.spread_bps
    end

    def fee_bps
      Rails.configuration.x.fee_bps
    end

    # The current time in whole seconds: the resolution of ledger timestamps.
    def now
      Time.current.floor
    end

    # { caliber_id => latest price_centicents }
    def latest_prices
      PriceTick.latest_by_caliber.transform_values(&:price_centicents)
    end

    # Idempotent; wired from config/initializers/ledger.rb.
    def register_tick_hook
      TickRunner.after_tick << TICK_HOOK unless TickRunner.after_tick.include?(TICK_HOOK)
    end
  end
end
