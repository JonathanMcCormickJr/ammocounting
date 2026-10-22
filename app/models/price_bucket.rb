# One OHLC bucket (hourly, daily or weekly) of raw PriceTicks. Buckets are
# derived data written by the PriceRollup service; raw ticks are never deleted.
class PriceBucket < ApplicationRecord
  RESOLUTIONS = %w[hourly daily weekly].freeze

  belongs_to :caliber

  validates :resolution, inclusion: { in: RESOLUTIONS }
  validates :bucket_start, :last_as_of, presence: true
end
