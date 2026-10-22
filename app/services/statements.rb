# Namespace for per-user financial statements. All figures come from the ledger
# engine (LedgerEngine); Rails only chooses periods, gathers inputs and renders.
module Statements
  # The user asked for something we cannot show (bad date, end before start...).
  # The message is safe to display.
  class Invalid < StandardError; end
end
