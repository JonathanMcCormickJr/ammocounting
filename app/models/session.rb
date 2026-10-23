class Session < ApplicationRecord
  # Absolute lifetime of a login, counted from sign-in. Checked on every request
  # and enforced on the cookie too; SessionCleanupJob deletes the dead rows.
  TTL = 2.weeks

  belongs_to :user

  scope :expired, -> { where(created_at: ...TTL.ago) }
  scope :unexpired, -> { where(created_at: TTL.ago..) }
end
