module Ledger
  # Reads the engine's running totals persisted on ledger transactions (see
  # LedgerTransaction::TOTALS_COLUMNS). Never adds anything up: the totals as of
  # time T are those of the latest row at or before T (ties by id), or all
  # zeros when there is none.
  module Totals
    class << self
      # The user's latest ledger row at or before `time` (nil = any time), or nil.
      def row_at(user, time = nil)
        scope = LedgerTransaction.where(user_id: user.id)
        scope = scope.where(occurred_at: ..time) if time
        scope.order(occurred_at: :desc, id: :desc).first
      end

      # Array of 40 Integers (LedgerEngine totals) as of `time` (nil = latest).
      def as_of(user, time = nil)
        row_at(user, time)&.totals || LedgerEngine::ZERO_TOTALS
      end
    end
  end
end
