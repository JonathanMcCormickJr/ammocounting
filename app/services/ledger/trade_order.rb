module Ledger
  # Shared flow for Buy and Sell: validate quantity, lock the user, revalue
  # holdings at current prices, then quote (engine), post (engine-built
  # postings) and record the trade with the engine's quantity_after. Subclasses
  # supply #side, #quote and #postings. Raises Ledger::Refused (user-facing)
  # for refusals, and Ledger::Replay (nothing written) when the order's nonce
  # was already used by an earlier trade of the same user.
  class TradeOrder
    REFUSALS = {
      insufficient_cash: "Not enough cash for this purchase.",
      insufficient_holdings: "You do not hold that many rounds.",
      negative_proceeds: "Trading costs would exceed the sale value.",
      # Engine quote status 1: the position is worth nothing (qty * price rounds to 0 cents).
      trade_too_small: "This trade is too small to price. Try a larger quantity."
    }.freeze
    QUOTE_OPERATIONS = %i[quote_buy quote_sell].freeze

    # quantity: Integer or numeric string (whole rounds). nonce: the form nonce
    # (Ledger.new_nonce) or nil for orders not placed from a form. Returns the Trade.
    def self.call(user, caliber, quantity, at: nil, nonce: nil)
      new(user, caliber, at, nonce).call(quantity)
    end

    def initialize(user, caliber, at, nonce = nil)
      @user = user
      @caliber = caliber
      @at = at
      @nonce = nonce
    end

    def call(quantity)
      qty = parse_quantity(quantity)
      check_nonce_format
      @user.with_lock do
        replay = @nonce && @user.trades.find_by(nonce: @nonce)
        raise Replay, replay if replay

        @at ||= Ledger.now_for(@user)
        prices = Ledger.latest_prices(at: @at)
        price = prices[@caliber.id] || raise(Refused, "No price is available for #{@caliber.name}.")
        Revalue.call(@user, prices: prices, at: @at)
        execute(qty, price)
      end
    rescue LedgerEngine::Refusal => e
      raise Refused, REFUSALS.fetch(e.status)
    end

    private

    # Whole rounds written as plain ASCII digits with no sign, underscores or
    # leading zeros (Integer() alone would accept "1_000", "+5" and "05").
    def parse_quantity(quantity)
      text = quantity.to_s.strip
      qty = Integer(text, 10) if text.match?(/\A[1-9][0-9]*\z/)
      return qty if qty && (1..MAX_QUANTITY).cover?(qty)

      raise Refused, "Quantity must be a whole number of rounds between 1 and #{MAX_QUANTITY}."
    end

    def check_nonce_format
      return if @nonce.nil? || @nonce.to_s.match?(NONCE_FORMAT)

      raise Refused, "This order form is out of date. Reload the page and try again."
    end

    def execute(qty, price)
      held = Trade.held(@user, @caliber)
      quote = priced(qty, price, held)
      held_after = quantity_after(held, qty)
      transaction = Poster.call(@user, kind: side, at: @at, description: "#{side.to_s.capitalize} #{qty} #{@caliber.name}",
        postings: postings(quote))
      Trade.create!(user: @user, caliber: @caliber, side: side, quantity: qty, quantity_after: held_after,
        price_centicents: price, value_cents: quote.value, spread_cents: quote.spread, fee_cents: quote.fee,
        ledger_transaction: transaction, occurred_at: @at, nonce: @nonce)
    end

    # The engine quote; status 1 (bad_argument) from the quote itself means the
    # trade is worth nothing, a user matter. Any other bad_argument is a bug.
    def priced(qty, price, held)
      quote(qty, price, held)
    rescue LedgerEngine::Error => e
      raise unless e.status == :bad_argument && QUOTE_OPERATIONS.include?(e.operation)

      raise Refused, REFUSALS.fetch(:trade_too_small)
    end

    # The engine's units held after the trade; a buy beyond the per-caliber limit is refused.
    def quantity_after(held, qty)
      LedgerEngine.apply_trade_quantity(held, side, qty)
    rescue LedgerEngine::Error => e
      raise unless e.status == :out_of_range

      raise Refused, "You cannot hold more than #{MAX_QUANTITY} rounds of one caliber."
    end
  end
end
