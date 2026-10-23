module Ledger
  # Dr Cash / Cr Owner's Capital (engine build_deposit).
  class Deposit
    def self.call(user, amount_cents, at: nil, description: "Deposit")
      user.with_lock do
        Poster.call(user, kind: :deposit, at: at || Ledger.now_for(user), description: description,
          postings: LedgerEngine.build_deposit(amount_cents))
      end
    end
  end
end
