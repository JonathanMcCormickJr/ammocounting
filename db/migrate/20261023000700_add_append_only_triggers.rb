# Append-only enforcement in the database (audit L3), so update_all, delete_all,
# raw SQL and similar bypasses of the Rails models fail too. Ledger transactions,
# postings and trades can be neither updated nor deleted; raw price ticks cannot
# be updated (they are facts; the rollup only reads them). Price buckets are
# derived data that the rollup upserts, so they are not protected. Ticks stay
# deletable only because test fixtures reload them with DELETE.
#
# Must be the LAST migration touching these tables: SQLite rebuilds a table for
# most ALTERs and a rebuild drops the table's triggers. Because schema.rb cannot
# carry triggers, the schema is dumped as db/structure.sql (config/database.yml).
class AddAppendOnlyTriggers < ActiveRecord::Migration[8.1]
  PROTECTED = %w[ledger_transactions ledger_postings trades].freeze

  def up
    PROTECTED.each do |table|
      create_guard(table, "UPDATE")
      create_guard(table, "DELETE")
    end
    create_guard("price_ticks", "UPDATE")
  end

  def down
    [ *PROTECTED.product(%w[update delete]), %w[price_ticks update] ].each do |table, event|
      execute "DROP TRIGGER IF EXISTS #{table}_no_#{event}"
    end
  end

  private

  def create_guard(table, event)
    execute <<~SQL
      CREATE TRIGGER #{table}_no_#{event.downcase} BEFORE #{event} ON #{table}
      BEGIN SELECT RAISE(ABORT, '#{table} is append-only (#{event.downcase} refused)'); END
    SQL
  end
end
