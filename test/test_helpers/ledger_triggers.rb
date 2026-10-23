# Test-only escape hatch for the database triggers that make ledger tables
# append-only (see db/migrate/*_add_append_only_triggers.rb). Tests that must
# corrupt, wipe or rewrite ledger rows (to prove a guard, or to simulate old
# data) run that part inside without_ledger_triggers. The triggers are read from
# sqlite_master and recreated verbatim afterwards, so this never drifts from the schema.
module LedgerTriggers
  def without_ledger_triggers
    connection = ActiveRecord::Base.connection
    triggers = connection.select_rows("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'")
    triggers.each { |name, _sql| connection.execute("DROP TRIGGER #{name}") }
    yield
  ensure
    triggers.each { |_name, sql| connection.execute(sql) }
  end
end
