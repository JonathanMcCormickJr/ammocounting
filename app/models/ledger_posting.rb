# One debit or credit line. account/side are the engine's integer codes
# (see Ledger::ACCOUNTS and Ledger::SIDES).
class LedgerPosting < ApplicationRecord
  include AppendOnly

  belongs_to :ledger_transaction

  validates :account, inclusion: { in: 1..5 }
  validates :side, inclusion: { in: [ 0, 1 ] }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10**12 }

  def debit?
    side == Ledger::SIDES.fetch(:debit)
  end
end
