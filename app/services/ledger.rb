# Namespace and shared vocabulary for the double-entry ledger. Money is never
# computed here: quotes, values, basis and statements all come from
# LedgerEngine (the proven SPARK engine). See ledger_core/DESIGN.md.
module Ledger
  ACCOUNTS = { cash: 1, holdings: 2, owners_capital: 3, trading_gain: 4, trading_costs: 5 }.freeze
  SIDES = { debit: 0, credit: 1 }.freeze

  MAX_QUANTITY = 1_000_000_000

  # A user-facing refusal (bad order, not enough cash, ...); the message is safe to display.
  class Refused < StandardError; end

  # The order carrying this nonce was already executed (a double-submit or replay).
  # `trade` is the trade it produced; nothing new was written.
  class Replay < StandardError
    attr_reader :trade

    def initialize(trade)
      @trade = trade
      super("This order was already placed.")
    end
  end

  # Form nonces: issued by Ledger.new_nonce when a trade form is rendered.
  NONCE_FORMAT = /\A[0-9a-f]{32}\z/

  # The books failed an engine consistency check. Never expected; investigate.
  class IntegrityError < StandardError; end

  # One or more users could not be revalued. Raised by Revalue.all_holders only after
  # every other user was processed: `failures` is { user_id => the error } and
  # `transactions` what was posted for the rest. The failed run is visible (a failed tick job).
  class RevalueFailed < StandardError
    attr_reader :failures, :transactions

    def initialize(failures, transactions)
      @failures = failures
      @transactions = transactions
      super("Revaluation failed for user(s) #{failures.keys.join(', ')}: " \
            "#{failures.map { |id, error| "#{id}: #{error.class}: #{error.message}" }.join('; ')}")
    end
  end

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

    # The time for an entry made "now" for this user: the clock, but never before
    # the user's latest ledger row. If the clock stepped backwards the entry goes at
    # the latest row's time, which keeps the per-user chain chronological (see
    # Poster) instead of raising and blocking the user. Call inside the user lock.
    def now_for(user)
      clock = now
      latest = Totals.row_at(user)&.occurred_at
      latest && latest > clock ? latest : clock
    end

    # A fresh random form nonce (see Replay).
    def new_nonce
      SecureRandom.hex(16)
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
