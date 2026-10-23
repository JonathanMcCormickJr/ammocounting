CREATE TABLE IF NOT EXISTS "calibers" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "slug" varchar NOT NULL, "position" integer DEFAULT 0 NOT NULL, "starting_price_centicents" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_calibers_on_slug" ON "calibers" ("slug");
CREATE TABLE IF NOT EXISTS "users" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email_address" varchar NOT NULL, "password_digest" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "cost_basis_method" varchar DEFAULT 'weighted_average' NOT NULL);
CREATE UNIQUE INDEX "index_users_on_email_address" ON "users" ("email_address");
CREATE TABLE IF NOT EXISTS "ledger_postings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "ledger_transaction_id" integer NOT NULL, "account" integer NOT NULL, "side" integer NOT NULL, "amount_cents" bigint NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_575406f954"
FOREIGN KEY ("ledger_transaction_id")
  REFERENCES "ledger_transactions" ("id")
, CONSTRAINT ledger_postings_account_check CHECK (account BETWEEN 1 AND 5), CONSTRAINT ledger_postings_amount_check CHECK (amount_cents BETWEEN 1 AND 1000000000000), CONSTRAINT ledger_postings_side_check CHECK (side IN (0, 1)));
CREATE INDEX "idx_on_ledger_transaction_id_account_side_875f0cd53f" ON "ledger_postings" ("ledger_transaction_id", "account", "side");
CREATE TABLE IF NOT EXISTS "sessions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "user_id" integer NOT NULL, "ip_address" varchar, "user_agent" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_758836b4f0"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
);
CREATE INDEX "index_sessions_on_user_id" ON "sessions" ("user_id");
CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "ledger_transactions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "user_id" integer NOT NULL, "kind" integer NOT NULL, "occurred_at" datetime(6) NOT NULL, "description" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "deposit_cash_debits" bigint NOT NULL, "deposit_cash_credits" bigint NOT NULL, "deposit_holdings_debits" bigint NOT NULL, "deposit_holdings_credits" bigint NOT NULL, "deposit_capital_debits" bigint NOT NULL, "deposit_capital_credits" bigint NOT NULL, "deposit_gain_debits" bigint NOT NULL, "deposit_gain_credits" bigint NOT NULL, "deposit_costs_debits" bigint NOT NULL, "deposit_costs_credits" bigint NOT NULL, "buy_cash_debits" bigint NOT NULL, "buy_cash_credits" bigint NOT NULL, "buy_holdings_debits" bigint NOT NULL, "buy_holdings_credits" bigint NOT NULL, "buy_capital_debits" bigint NOT NULL, "buy_capital_credits" bigint NOT NULL, "buy_gain_debits" bigint NOT NULL, "buy_gain_credits" bigint NOT NULL, "buy_costs_debits" bigint NOT NULL, "buy_costs_credits" bigint NOT NULL, "sell_cash_debits" bigint NOT NULL, "sell_cash_credits" bigint NOT NULL, "sell_holdings_debits" bigint NOT NULL, "sell_holdings_credits" bigint NOT NULL, "sell_capital_debits" bigint NOT NULL, "sell_capital_credits" bigint NOT NULL, "sell_gain_debits" bigint NOT NULL, "sell_gain_credits" bigint NOT NULL, "sell_costs_debits" bigint NOT NULL, "sell_costs_credits" bigint NOT NULL, "revalue_cash_debits" bigint NOT NULL, "revalue_cash_credits" bigint NOT NULL, "revalue_holdings_debits" bigint NOT NULL, "revalue_holdings_credits" bigint NOT NULL, "revalue_capital_debits" bigint NOT NULL, "revalue_capital_credits" bigint NOT NULL, "revalue_gain_debits" bigint NOT NULL, "revalue_gain_credits" bigint NOT NULL, "revalue_costs_debits" bigint NOT NULL, "revalue_costs_credits" bigint NOT NULL, "previous_id" bigint, CONSTRAINT "fk_rails_114c2d69a9"
FOREIGN KEY ("previous_id", "user_id")
  REFERENCES "ledger_transactions" ("id", "user_id")
, CONSTRAINT "fk_rails_9eb516ca65"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
, CONSTRAINT ledger_transactions_kind_check CHECK (kind BETWEEN 0 AND 3), CONSTRAINT ledger_transactions_cash_not_negative CHECK ((deposit_cash_debits + buy_cash_debits + sell_cash_debits + revalue_cash_debits) >= (deposit_cash_credits + buy_cash_credits + sell_cash_credits + revalue_cash_credits)), CONSTRAINT ledger_transactions_holdings_not_negative CHECK ((deposit_holdings_debits + buy_holdings_debits + sell_holdings_debits + revalue_holdings_debits) >= (deposit_holdings_credits + buy_holdings_credits + sell_holdings_credits + revalue_holdings_credits)), CONSTRAINT ledger_transactions_debits_equal_credits CHECK ((deposit_cash_debits + deposit_holdings_debits + deposit_capital_debits + deposit_gain_debits + deposit_costs_debits + buy_cash_debits + buy_holdings_debits + buy_capital_debits + buy_gain_debits + buy_costs_debits + sell_cash_debits + sell_holdings_debits + sell_capital_debits + sell_gain_debits + sell_costs_debits + revalue_cash_debits + revalue_holdings_debits + revalue_capital_debits + revalue_gain_debits + revalue_costs_debits) = (deposit_cash_credits + deposit_holdings_credits + deposit_capital_credits + deposit_gain_credits + deposit_costs_credits + buy_cash_credits + buy_holdings_credits + buy_capital_credits + buy_gain_credits + buy_costs_credits + sell_cash_credits + sell_holdings_credits + sell_capital_credits + sell_gain_credits + sell_costs_credits + revalue_cash_credits + revalue_holdings_credits + revalue_capital_credits + revalue_gain_credits + revalue_costs_credits)));
CREATE INDEX "index_ledger_transactions_on_user_id_and_occurred_at_and_id" ON "ledger_transactions" ("user_id", "occurred_at", "id");
CREATE UNIQUE INDEX "index_ledger_transactions_on_previous_id" ON "ledger_transactions" ("previous_id");
CREATE UNIQUE INDEX "index_ledger_transactions_one_first_row_per_user" ON "ledger_transactions" ("user_id") WHERE previous_id IS NULL;
CREATE UNIQUE INDEX "index_ledger_transactions_on_id_and_user_id" ON "ledger_transactions" ("id", "user_id");
CREATE TABLE IF NOT EXISTS "price_ticks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "caliber_id" integer NOT NULL, "price_centicents" integer NOT NULL, "as_of" datetime(6) NOT NULL, CONSTRAINT "fk_rails_d04f056aaa"
FOREIGN KEY ("caliber_id")
  REFERENCES "calibers" ("id")
, CONSTRAINT price_ticks_price_check CHECK (price_centicents > 0));
CREATE UNIQUE INDEX "index_price_ticks_on_caliber_id_and_as_of" ON "price_ticks" ("caliber_id", "as_of");
CREATE TABLE IF NOT EXISTS "price_buckets" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "caliber_id" integer NOT NULL, "resolution" varchar NOT NULL, "bucket_start" datetime(6) NOT NULL, "open_centicents" integer NOT NULL, "high_centicents" integer NOT NULL, "low_centicents" integer NOT NULL, "close_centicents" integer NOT NULL, "tick_count" integer NOT NULL, "last_as_of" datetime(6) NOT NULL, "last_tick_id" bigint, CONSTRAINT "fk_rails_3a993a1d11"
FOREIGN KEY ("caliber_id")
  REFERENCES "calibers" ("id")
, CONSTRAINT price_buckets_ohlc_check CHECK (low_centicents > 0 AND low_centicents <= open_centicents AND open_centicents <= high_centicents AND low_centicents <= close_centicents AND close_centicents <= high_centicents));
CREATE UNIQUE INDEX "index_price_buckets_on_bucket" ON "price_buckets" ("caliber_id", "resolution", "bucket_start");
CREATE TABLE IF NOT EXISTS "trades" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "user_id" integer NOT NULL, "caliber_id" integer NOT NULL, "side" integer NOT NULL, "quantity" bigint NOT NULL, "price_centicents" bigint NOT NULL, "value_cents" bigint NOT NULL, "spread_cents" bigint NOT NULL, "fee_cents" bigint NOT NULL, "ledger_transaction_id" integer NOT NULL, "occurred_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "quantity_after" bigint NOT NULL, "nonce" varchar, CONSTRAINT "fk_rails_d3f4cdfe49"
FOREIGN KEY ("ledger_transaction_id", "user_id")
  REFERENCES "ledger_transactions" ("id", "user_id")
, CONSTRAINT "fk_rails_12b0ea7696"
FOREIGN KEY ("user_id")
  REFERENCES "users" ("id")
, CONSTRAINT "fk_rails_c647716fb0"
FOREIGN KEY ("caliber_id")
  REFERENCES "calibers" ("id")
, CONSTRAINT "fk_rails_0df75091f8"
FOREIGN KEY ("ledger_transaction_id")
  REFERENCES "ledger_transactions" ("id")
, CONSTRAINT trades_quantity_check CHECK (quantity BETWEEN 1 AND 1000000000), CONSTRAINT trades_quantity_after_check CHECK (quantity_after BETWEEN 0 AND 1000000000), CONSTRAINT trades_side_check CHECK (side IN (0, 1)), CONSTRAINT trades_costs_check CHECK (spread_cents >= 0 AND fee_cents >= 0), CONSTRAINT trades_value_check CHECK (value_cents BETWEEN 0 AND 1000000000000), CONSTRAINT trades_price_check CHECK (price_centicents BETWEEN 1 AND 10000000), CONSTRAINT trades_nonce_check CHECK (nonce IS NULL OR length(nonce) BETWEEN 16 AND 64));
CREATE INDEX "index_trades_on_caliber_id" ON "trades" ("caliber_id");
CREATE UNIQUE INDEX "index_trades_on_ledger_transaction_id" ON "trades" ("ledger_transaction_id");
CREATE INDEX "index_trades_on_user_id_and_caliber_id_and_occurred_at_and_id" ON "trades" ("user_id", "caliber_id", "occurred_at", "id");
CREATE INDEX "index_trades_on_user_id_and_occurred_at_and_id" ON "trades" ("user_id", "occurred_at", "id");
CREATE UNIQUE INDEX "index_trades_on_user_id_and_nonce" ON "trades" ("user_id", "nonce");
CREATE TRIGGER ledger_transactions_no_update BEFORE UPDATE ON ledger_transactions
BEGIN SELECT RAISE(ABORT, 'ledger_transactions is append-only (update refused)'); END;
CREATE TRIGGER ledger_transactions_no_delete BEFORE DELETE ON ledger_transactions
BEGIN SELECT RAISE(ABORT, 'ledger_transactions is append-only (delete refused)'); END;
CREATE TRIGGER ledger_postings_no_update BEFORE UPDATE ON ledger_postings
BEGIN SELECT RAISE(ABORT, 'ledger_postings is append-only (update refused)'); END;
CREATE TRIGGER ledger_postings_no_delete BEFORE DELETE ON ledger_postings
BEGIN SELECT RAISE(ABORT, 'ledger_postings is append-only (delete refused)'); END;
CREATE TRIGGER trades_no_update BEFORE UPDATE ON trades
BEGIN SELECT RAISE(ABORT, 'trades is append-only (update refused)'); END;
CREATE TRIGGER trades_no_delete BEFORE DELETE ON trades
BEGIN SELECT RAISE(ABORT, 'trades is append-only (delete refused)'); END;
CREATE TRIGGER price_ticks_no_update BEFORE UPDATE ON price_ticks
BEGIN SELECT RAISE(ABORT, 'price_ticks is append-only (update refused)'); END;
INSERT INTO "schema_migrations" (version) VALUES
('20261023000700'),
('20261023000600'),
('20261023000500'),
('20261023000400'),
('20261023000300'),
('20261023000200'),
('20261023000100'),
('20261022030300'),
('20261022030200'),
('20261022030100'),
('20261022030000'),
('20261022025241'),
('20261022025240');

