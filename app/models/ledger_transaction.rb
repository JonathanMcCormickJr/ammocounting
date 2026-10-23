# One balanced set of postings plus the running totals after it (the 40
# cumulative debit/credit numbers of the user's whole ledger, as the engine
# returned them). Written only through Ledger::Poster.
class LedgerTransaction < ApplicationRecord
  include AppendOnly

  # Columns of the running totals in the engine's Totals index order
  # (kind * 5 + account - 1, debits then credits); see ledger_core/ABI.md.
  TOTALS_COLUMNS = %w[deposit buy sell revalue].product(%w[cash holdings capital gain costs], %w[debits credits])
    .map { |kind, account, side| "#{kind}_#{account}_#{side}" }.freeze

  belongs_to :user
  # The user's previous ledger row (nil for the first); see the chain guard in
  # db/migrate/20261023000400_add_ledger_chain_and_checks.rb.
  belongs_to :previous, class_name: "LedgerTransaction", optional: true
  has_many :postings, class_name: "LedgerPosting", dependent: nil
  has_one :trade, dependent: nil

  enum :kind, { deposit: 0, buy: 1, sell: 2, revalue: 3 }, validate: true

  validates :occurred_at, presence: true

  # { "deposit_cash_debits" => n, ... } for create!.
  def self.totals_attributes(totals)
    TOTALS_COLUMNS.zip(totals).to_h
  end

  # The 40 running totals as an Array of Integers (LedgerEngine totals).
  def totals
    attributes.values_at(*TOTALS_COLUMNS)
  end
end
