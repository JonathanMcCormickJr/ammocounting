module Ledger
  # Shared flow for Buy and Sell: validate quantity, lock the user, revalue
  # holdings at current prices, then quote (engine), post (engine-built
  # postings) and record the trade with the engine's quantity_after. Subclasses
  # supply #side, #quote and #postings. Raises Ledger::Refused (user-facing)
  # for refusals.
  class TradeOrder
    REFUSALS = {
      insufficient_cash: "Not enough cash for this purchase.",
      insufficient_holdings: "You do not hold that many rounds.",
      negative_proceeds: "Trading costs would exceed the sale value."
    }.freeze

    # quantity: Integer or numeric string (whole rounds). Returns the Trade.
    def self.call(user, caliber, quantity, at: nil)
      new(user, caliber, at).call(quantity)
    end

    def initialize(user, caliber, at)
      @user = user
      @caliber = caliber
      @at = at
    end

    def call(quantity)
      qty = parse_quantity(quantity)
      @user.with_lock do
        @at ||= Ledger.now
        prices = Ledger.latest_prices
        price = prices[@caliber.id] || raise(Refused, "No price is available for #{@caliber.name}.")
        Revalue.call(@user, prices: prices, at: @at)
        execute(qty, price)
      end
    rescue LedgerEngine::Refusal => e
      raise Refused, REFUSALS.fetch(e.status)
    end

    private

    def parse_quantity(quantity)
      qty = Integer(quantity.to_s, 10, exception: false)
      return qty if qty && (1..MAX_QUANTITY).cover?(qty)

      raise Refused, "Quantity must be a whole number of rounds between 1 and #{MAX_QUANTITY}."
    end

    def execute(qty, price)
      held = Trade.held(@user, @caliber)
      quote = quote(qty, price, held)
      held_after = quantity_after(held, qty)
      transaction = Poster.call(@user, kind: side, at: @at, description: "#{side.to_s.capitalize} #{qty} #{@caliber.name}",
        postings: postings(quote))
      Trade.create!(user: @user, caliber: @caliber, side: side, quantity: qty, quantity_after: held_after,
        price_centicents: price, value_cents: quote.value, spread_cents: quote.spread, fee_cents: quote.fee,
        ledger_transaction: transaction, occurred_at: @at)
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
