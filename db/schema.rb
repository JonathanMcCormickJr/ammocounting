# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_000300) do
  create_table "calibers", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.integer "starting_price_centicents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_calibers_on_slug", unique: true
  end

  create_table "ledger_postings", force: :cascade do |t|
    t.integer "ledger_transaction_id", null: false
    t.integer "account", null: false
    t.integer "side", null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ledger_transaction_id", "account", "side"], name: "idx_on_ledger_transaction_id_account_side_875f0cd53f"
    t.check_constraint "account BETWEEN 1 AND 5", name: "ledger_postings_account_check"
    t.check_constraint "amount_cents BETWEEN 1 AND 1000000000000", name: "ledger_postings_amount_check"
    t.check_constraint "side IN (0, 1)", name: "ledger_postings_side_check"
  end

  create_table "ledger_transactions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "kind", null: false
    t.datetime "occurred_at", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "deposit_cash_debits", default: 0, null: false
    t.bigint "deposit_cash_credits", default: 0, null: false
    t.bigint "deposit_holdings_debits", default: 0, null: false
    t.bigint "deposit_holdings_credits", default: 0, null: false
    t.bigint "deposit_capital_debits", default: 0, null: false
    t.bigint "deposit_capital_credits", default: 0, null: false
    t.bigint "deposit_gain_debits", default: 0, null: false
    t.bigint "deposit_gain_credits", default: 0, null: false
    t.bigint "deposit_costs_debits", default: 0, null: false
    t.bigint "deposit_costs_credits", default: 0, null: false
    t.bigint "buy_cash_debits", default: 0, null: false
    t.bigint "buy_cash_credits", default: 0, null: false
    t.bigint "buy_holdings_debits", default: 0, null: false
    t.bigint "buy_holdings_credits", default: 0, null: false
    t.bigint "buy_capital_debits", default: 0, null: false
    t.bigint "buy_capital_credits", default: 0, null: false
    t.bigint "buy_gain_debits", default: 0, null: false
    t.bigint "buy_gain_credits", default: 0, null: false
    t.bigint "buy_costs_debits", default: 0, null: false
    t.bigint "buy_costs_credits", default: 0, null: false
    t.bigint "sell_cash_debits", default: 0, null: false
    t.bigint "sell_cash_credits", default: 0, null: false
    t.bigint "sell_holdings_debits", default: 0, null: false
    t.bigint "sell_holdings_credits", default: 0, null: false
    t.bigint "sell_capital_debits", default: 0, null: false
    t.bigint "sell_capital_credits", default: 0, null: false
    t.bigint "sell_gain_debits", default: 0, null: false
    t.bigint "sell_gain_credits", default: 0, null: false
    t.bigint "sell_costs_debits", default: 0, null: false
    t.bigint "sell_costs_credits", default: 0, null: false
    t.bigint "revalue_cash_debits", default: 0, null: false
    t.bigint "revalue_cash_credits", default: 0, null: false
    t.bigint "revalue_holdings_debits", default: 0, null: false
    t.bigint "revalue_holdings_credits", default: 0, null: false
    t.bigint "revalue_capital_debits", default: 0, null: false
    t.bigint "revalue_capital_credits", default: 0, null: false
    t.bigint "revalue_gain_debits", default: 0, null: false
    t.bigint "revalue_gain_credits", default: 0, null: false
    t.bigint "revalue_costs_debits", default: 0, null: false
    t.bigint "revalue_costs_credits", default: 0, null: false
    t.index ["user_id", "occurred_at", "id"], name: "index_ledger_transactions_on_user_id_and_occurred_at_and_id"
    t.check_constraint "kind BETWEEN 0 AND 3", name: "ledger_transactions_kind_check"
  end

  create_table "price_buckets", force: :cascade do |t|
    t.integer "caliber_id", null: false
    t.string "resolution", null: false
    t.datetime "bucket_start", null: false
    t.integer "open_centicents", null: false
    t.integer "high_centicents", null: false
    t.integer "low_centicents", null: false
    t.integer "close_centicents", null: false
    t.integer "tick_count", null: false
    t.datetime "last_as_of", null: false
    t.index ["caliber_id", "resolution", "bucket_start"], name: "index_price_buckets_on_bucket", unique: true
  end

  create_table "price_ticks", force: :cascade do |t|
    t.integer "caliber_id", null: false
    t.integer "price_centicents", null: false
    t.datetime "as_of", null: false
    t.index ["caliber_id", "as_of"], name: "index_price_ticks_on_caliber_id_and_as_of", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "trades", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "caliber_id", null: false
    t.integer "side", null: false
    t.bigint "quantity", null: false
    t.bigint "price_centicents", null: false
    t.bigint "value_cents", null: false
    t.bigint "spread_cents", null: false
    t.bigint "fee_cents", null: false
    t.integer "ledger_transaction_id", null: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "quantity_after", default: 0, null: false
    t.index ["caliber_id"], name: "index_trades_on_caliber_id"
    t.index ["ledger_transaction_id"], name: "index_trades_on_ledger_transaction_id", unique: true
    t.index ["user_id", "caliber_id", "occurred_at", "id"], name: "index_trades_on_user_id_and_caliber_id_and_occurred_at_and_id"
    t.index ["user_id", "occurred_at", "id"], name: "index_trades_on_user_id_and_occurred_at_and_id"
    t.check_constraint "price_centicents BETWEEN 0 AND 10000000", name: "trades_price_check"
    t.check_constraint "quantity BETWEEN 1 AND 1000000000", name: "trades_quantity_check"
    t.check_constraint "quantity_after BETWEEN 0 AND 1000000000", name: "trades_quantity_after_check"
    t.check_constraint "side IN (0, 1)", name: "trades_side_check"
    t.check_constraint "spread_cents >= 0 AND fee_cents >= 0", name: "trades_costs_check"
    t.check_constraint "value_cents BETWEEN 0 AND 1000000000000", name: "trades_value_check"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cost_basis_method", default: "weighted_average", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "ledger_postings", "ledger_transactions"
  add_foreign_key "ledger_transactions", "users"
  add_foreign_key "price_buckets", "calibers"
  add_foreign_key "price_ticks", "calibers"
  add_foreign_key "sessions", "users"
  add_foreign_key "trades", "calibers"
  add_foreign_key "trades", "ledger_transactions"
  add_foreign_key "trades", "users"
end
