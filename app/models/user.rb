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
  # has_secure_password already caps passwords at bcrypt's 72 bytes (anything longer
  # would be silently truncated), so only a minimum and a weak-password check here.
  COMMON_PASSWORDS = %w[
    password password1 password12 passw0rd p@ssw0rd 12345678 123456789 1234567890 11111111
    00000000 87654321 qwerty123 qwertyui qwertyuiop 1q2w3e4r 1qaz2wsx abc12345 abcd1234
    iloveyou letmein1 welcome1 admin123 football baseball superman trustno1 monkey123
  ].freeze

  validates :password, length: { minimum: 8 }, allow_nil: true
  validate :password_not_weak, if: -> { password.present? }

  # Earliest moment this user has existed in the books: the sooner of account
  # creation and the first ledger transaction, to whole seconds (UTC).
  def history_start
    [ created_at, ledger_transactions.minimum(:occurred_at) ].compact.min.utc.floor
  end

  private

  def password_not_weak
    return unless COMMON_PASSWORDS.include?(password.downcase) || password.casecmp?(email_address.to_s)

    errors.add(:password, "is too common")
  end
end
