module Ledger
  # Marks a user's holdings to market. The engine sums the market values of
  # every held caliber at the given prices, compares them with the Holdings
  # carrying balance (running totals) and builds the Dr/Cr Trading Gain/Loss
  # postings, or none when equal (so calling it twice is harmless).
  class Revalue
    # prices: { caliber_id => centicents }, default the prices at `at` (default: the
    # user's game time). Returns the LedgerTransaction, or nil when nothing needed posting.
    def self.call(user, prices: nil, at: nil)
      user.with_lock do
        at ||= Ledger.now_for(user)
        prices ||= Ledger.latest_prices(at: at) # read inside the lock: an older tick can never overwrite a newer revaluation
        values = Balances.quantities(user).map { |caliber_id, qty| LedgerEngine.market_value(qty, prices.fetch(caliber_id)) }
        revaluation = LedgerEngine.revalue(values, Balances.sheet(user).holdings)
        next if revaluation.postings.empty?

        Poster.call(user, kind: :revalue, at: at, description: "Revalue holdings", postings: revaluation.postings)
      end
    end

    # Revalues every user who holds rounds, at the latest prices. One user's failure
    # is logged (Rails.logger.error) and does not stop the others; once all have been
    # tried, any failure raises Ledger::RevalueFailed (carrying the failures and the
    # transactions posted for the rest), so a failed revaluation is never silent.
    # Returns the transactions posted when every user succeeded.
    def self.all_holders(logger: Rails.logger, at: nil)
      failures = {}
      posted = User.where(id: Trade.holder_user_ids).filter_map do |user|
        call(user, at: at)
      rescue StandardError => e
        logger.error("Ledger::Revalue failed for user #{user.id}: #{e.class}: #{e.message}")
        failures[user.id] = e
        nil
      end
      raise RevalueFailed.new(failures, posted) if failures.any?

      posted
    end
  end
end
