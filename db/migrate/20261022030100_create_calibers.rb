class CreateCalibers < ActiveRecord::Migration[8.1]
  def change
    create_table :calibers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.integer :starting_price_centicents, null: false

      t.timestamps
    end
    add_index :calibers, :slug, unique: true
  end
end
