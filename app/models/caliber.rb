class Caliber < ApplicationRecord
  # name, slug, starting price in centicents (1/100 cent) per round.
  CATALOG = [
    [ ".22 LR", "22-lr", 1000 ],
    [ ".17 HMR", "17-hmr", 2200 ],
    [ ".223/5.56x45", "223-556x45", 3800 ],
    [ ".300 BLK", "300-blk", 5500 ],
    [ "7.62x39", "762x39", 3200 ],
    [ ".308/7.62x51", "308-762x51", 6500 ],
    [ ".30-06", "30-06", 9000 ],
    [ "6.5 Creedmoor", "65-creedmoor", 9500 ],
    [ ".243 Win", "243-win", 8000 ],
    [ "9mm", "9mm", 2500 ],
    [ ".40 S&W", "40-sw", 3500 ],
    [ ".45 ACP", "45-acp", 4200 ],
    [ ".380 ACP", "380-acp", 3600 ],
    [ "12 gauge", "12-gauge", 3500 ],
    [ "20 gauge", "20-gauge", 3800 ]
  ].freeze

  # Price history and trades are facts that are never deleted, so a caliber with
  # history cannot be destroyed (a bare destroy would also fail on the append-only triggers).
  has_many :price_ticks, dependent: :restrict_with_exception
  has_many :price_buckets, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :starting_price_centicents, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(:position) }

  # Idempotent: safe to run any number of times.
  def self.seed_catalog!(now: Time.current)
    transaction do
      CATALOG.each_with_index do |(name, slug, price), index|
        caliber = find_or_initialize_by(slug: slug)
        caliber.update!(name: name, position: index, starting_price_centicents: price)
        next if caliber.price_ticks.exists?

        caliber.price_ticks.create!(price_centicents: price, as_of: PriceTick.floor_time(now))
      end
    end
  end

  def to_param
    slug
  end

  def latest_tick
    price_ticks.order(:as_of).last
  end
end
