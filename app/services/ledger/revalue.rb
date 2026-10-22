module Ledger
  # Marks a user's holdings to market. The engine sums the market values of
  # every held caliber at the given prices, compares them with the Holdings
  # carrying balance (running totals) and builds the Dr/Cr Trading Gain/Loss
  # postings, or none when equal (so calling it twice is harmless).
  class Revalue
    # prices: { caliber_id => centicents }, default the latest ticks.
    # Returns the LedgerTransaction, or nil when nothing needed posting.
    def self.call(user, prices: Ledger.latest_prices, at: nil)
      user.with_lock do
        values = Balances.quantities(user).map { |caliber_id, qty| LedgerEngine.market_value(qty, prices.fetch(caliber_id)) }
        revaluation = LedgerEngine.revalue(values, Balances.sheet(user).holdings)
        next if revaluation.postings.empty?

        Poster.call(user, kind: :revalue, at: at || Ledger.now, description: "Revalue holdings", postings: revaluation.postings)
      end
    end

    # Revalues every user who holds rounds, at the latest prices. One user's
    # failure is logged and does not stop the others. Returns the transactions posted.
    def self.all_holders(logger: Rails.logger, at: nil)
      prices = Ledger.latest_prices
      User.where(id: Trade.holder_user_ids).filter_map do |user|
        call(user, prices: prices, at: at)
      rescue StandardError => e
        logger.error("Ledger::Revalue failed for user #{user.id}: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
