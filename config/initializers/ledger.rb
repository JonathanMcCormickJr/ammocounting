# Revalue holdings after every price tick. to_prepare re-runs on code reload
# (TickRunner.after_tick is reset when TickRunner reloads); registration is idempotent.
Rails.application.config.to_prepare { Ledger.register_tick_hook }
