class PriceTick < ApplicationRecord
  belongs_to :caliber

  validates :price_centicents, numericality: { only_integer: true, greater_than: 0 }
  validates :as_of, presence: true

  # Latest tick per caliber as { caliber_id => PriceTick } in one query. With `at`,
  # the latest tick at or before that game time (later ticks are the future).
  def self.latest_by_caliber(at: nil)
    visible = at ? where(as_of: ..at) : all
    where("(caliber_id, as_of) IN (?)", visible.group(:caliber_id).select("caliber_id, MAX(as_of)")).index_by(&:caliber_id)
  end

  # Floors a time to the configured tick interval (UTC epoch aligned).
  def self.floor_time(time, interval_minutes: Rails.configuration.x.tick_interval_minutes)
    step = interval_minutes * 60
    Time.at(time.to_i.div(step) * step).utc
  end
end
