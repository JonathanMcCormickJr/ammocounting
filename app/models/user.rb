class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  # Append-only; a user with ledger history cannot be deleted (foreign keys).
  has_many :ledger_transactions, dependent: nil
  has_many :trades, dependent: nil

  # Per-user setting, switchable at runtime via SettingsController.
  enum :cost_basis_method, { weighted_average: "weighted_average", fifo: "fifo" },
    default: :weighted_average, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # Earliest moment this user has existed in the books: the sooner of account
  # creation and the first ledger transaction, to whole seconds (UTC).
  def history_start
    [ created_at, ledger_transactions.minimum(:occurred_at) ].compact.min.utc.floor
  end
end
