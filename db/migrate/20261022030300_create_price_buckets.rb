class CreatePriceBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :price_buckets do |t|
      t.references :caliber, null: false, foreign_key: true, index: false
      t.string :resolution, null: false
      t.datetime :bucket_start, null: false
      t.integer :open_centicents, null: false
      t.integer :high_centicents, null: false
      t.integer :low_centicents, null: false
      t.integer :close_centicents, null: false
      t.integer :tick_count, null: false
      t.datetime :last_as_of, null: false
    end
    add_index :price_buckets, %i[caliber_id resolution bucket_start], unique: true,
      name: "index_price_buckets_on_bucket"
  end
end
