module Ledger
  # The only writer of ledger transactions and postings. Takes the user lock,
  # loads the user's latest running totals, has the engine apply (and validate:
  # 1..16 postings, valid codes, debits = credits, no negative cash/holdings)
  # the postings with the typed apply_* entry point of the kind, and persists
  # transaction, postings and new totals together.
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

        totals = apply(kind, postings, previous ? previous.totals : LedgerEngine::ZERO_TOTALS)
        LedgerTransaction.transaction do
          transaction = LedgerTransaction.create!(user: user, kind: kind, occurred_at: at, description: description,
            previous_id: previous&.id, **LedgerTransaction.totals_attributes(totals))
          postings.each { |account, side, amount| transaction.postings.create!(account: account, side: side, amount_cents: amount) }
          transaction
        end
      end
    end

    # The engine's typed entry point for the kind: it also checks that the postings
    # have that kind's shape (a sell's postings cannot be booked as a deposit). An
    # unknown kind is a programming error (KeyError), not an engine status.
    def self.apply(kind, postings, previous)
      case kind
      when :deposit then LedgerEngine.apply_deposit(postings, previous)
      when :buy then LedgerEngine.apply_buy(postings, previous)
      when :sell then LedgerEngine.apply_sell(postings, previous)
      when :revalue then LedgerEngine.apply_revalue(postings, previous)
      else raise KeyError, "unknown ledger transaction kind #{kind.inspect}"
      end
    end
    private_class_method :apply
  end
end
