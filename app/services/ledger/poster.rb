module Ledger
  # The only writer of ledger transactions and postings. Takes the user lock,
  # loads the user's latest running totals, has the engine apply (and validate:
  # 1..16 postings, valid codes, debits = credits, no negative cash/holdings)
  # the postings, and persists transaction, postings and new totals together.
  class Poster
    # The new row would sort before the user's latest row, breaking the totals chain.
    class OutOfOrder < StandardError; end

    # postings: [[account, side, amount], ...] as built by LedgerEngine.build_*
    # / .revalue. kind: :deposit, :buy, :sell or :revalue. Returns the
    # LedgerTransaction. Raises LedgerEngine::Error if the engine refuses.
    def self.call(user, kind:, postings:, at:, description: nil)
      user.with_lock do
        previous = Totals.row_at(user)
        raise OutOfOrder, "Ledger entry at #{at.iso8601} is older than the latest entry (#{previous.occurred_at.iso8601})" if previous && at < previous.occurred_at

        totals = LedgerEngine.apply_transaction(kind, postings, previous ? previous.totals : LedgerEngine::ZERO_TOTALS)
        LedgerTransaction.transaction do
          transaction = LedgerTransaction.create!(user: user, kind: kind, occurred_at: at, description: description,
            **LedgerTransaction.totals_attributes(totals))
          postings.each { |account, side, amount| transaction.postings.create!(account: account, side: side, amount_cents: amount) }
          transaction
        end
      end
    end
  end
end
