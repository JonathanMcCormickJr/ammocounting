# Each player has their own game clock (UTC); it only moves when they fast-forward.
# The default is config.x.game_start (2026-01-01), the shared start of every game.
class AddGameTimeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :game_time, :datetime, null: false, default: "2026-01-01 00:00:00"
  end
end
