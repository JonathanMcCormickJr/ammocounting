# Audit L6: hourly buckets remember the highest price_ticks.id they were built
# from, so PriceRollup can tell which old ticks arrived late (higher id than any
# rolled tick, but an older time) and re-derive from the earliest affected hour.
# Existing hourly buckets are backfilled from the ticks inside their span.
class AddLastTickIdToPriceBuckets < ActiveRecord::Migration[8.1]
  def change
    add_column :price_buckets, :last_tick_id, :bigint
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE price_buckets SET last_tick_id = (
            SELECT MAX(t.id) FROM price_ticks t
            WHERE t.caliber_id = price_buckets.caliber_id
              AND t.as_of >= price_buckets.bucket_start AND t.as_of <= price_buckets.last_as_of)
          WHERE resolution = 'hourly'
        SQL
      end
    end
  end
end
