class CreatePriceTicks < ActiveRecord::Migration[8.1]
  def change
    create_table :price_ticks do |t|
      t.references :caliber, null: false, foreign_key: true, index: false
      t.integer :price_centicents, null: false
      t.datetime :as_of, null: false
    end
    add_index :price_ticks, %i[caliber_id as_of], unique: true
  end
end
