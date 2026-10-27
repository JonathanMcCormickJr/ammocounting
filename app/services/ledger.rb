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

  class << self
    def spread_bps
      Rails.configuration.x.spread_bps
    end

    def fee_bps
      Rails.configuration.x.fee_bps
    end

    # The time for an entry made "now" by this user: their game clock, which only
    # moves forward, so the per-user chain stays chronological (see Poster). Call
    # inside the user lock, which reloads the clock.
    def now_for(user)
      user.game_time.utc.floor
    end

    # A fresh random form nonce (see Replay).
    def new_nonce
      SecureRandom.hex(16)
    end

    # { caliber_id => price_centicents } as of game time `at` (the newest ticks when nil).
    def latest_prices(at: nil)
      PriceTick.latest_by_caliber(at: at).transform_values(&:price_centicents)
    end
  end
end
