# TODO

Legend: `[x]` done, `[ ]` not started.

## Done

- [x] Rails 8.1 app generated (SQLite, Hotwire, importmap)
- [x] `ledger_core` Alire crate created; SPARK types + `Is_Balanced` spec stub builds
- [x] README describes the product and architecture

## Decisions (made)

- **Bridge:** C-ABI shared library exported from Ada (`Convention => C`), loaded
  in Rails via Ruby `ffi`.
- **Persistence:** Rails persists postings in SQLite; the engine validates every
  transaction (balanced, cash and holdings never negative) before Rails commits.
- **Price index:** in-process Ruby class behind an interface (swappable later).
- **Price ticks:** scheduled Solid Queue job; one shared price history for all users.
- **Trading:** users buy and sell whole rounds at the current price, with a
  spread/fee. No shorting, no borrowing. Fees post to a Fee Expense account and
  appear on the income statement and cash flow statement.
- **Calibers:** a large seed set (15+), see below.
- **Time:** real wall-clock time; ticks every N minutes.
- **Valuation:** mark-to-market, revalued every tick (unrealized gain/loss posts
  to the ledger), while also tracking cost basis per holding for realized gains.
- **Cost basis method:** per-user runtime setting, **weighted average or FIFO**,
  changeable at any time. Applies to every view, including the statements.
- **Chart history:** kept indefinitely (design ceiling: 128 years). Range
  options: past day, week, month, YTD, year, and MAX.

## Still to pin down (defaults proposed; change if you disagree)

- [ ] Tick interval N: **5 minutes**
- [ ] Fee model: flat **1% of trade value per buy or sell**, rounded half-up to
      the cent, plus a bid/ask spread of **0.5% each side** of the index price
- [ ] Cost basis implementation: the ledger records every purchase as a **lot**.
      Holdings are marked to market, so balances and net worth don't depend on
      the method; only the realized/unrealized gain split does. Proposal: compute
      that split by replaying lots under the user's chosen method, so both
      methods yield balanced statements. Confirm this (vs. posting under one
      canonical method).
- [ ] Seed calibers (15): .22 LR, .17 HMR, .223/5.56x45, .300 BLK, 7.62x39,
      .308/7.62x51, .30-06, 6.5 Creedmoor, .243 Win, 9mm, .40 S&W, .45 ACP,
      .380 ACP, 12 gauge, 20 gauge
- [ ] Storage scale: 128 years at 5-minute ticks is ~13.5M ticks per caliber
      (~200M rows for 15 calibers). Proposal: keep raw ticks for recent data and
      roll older data up into OHLC buckets (hour/day/week) so charts stay fast
      with nothing deleted. Same idea for per-user net worth history, or compute
      it on demand from the ledger. Confirm.
- [ ] Chart of accounts additions: Fee Expense, Cost Basis tracking per caliber

## Ledger core (`ledger_core/`)

- [ ] Ghost body for `Total`; prove `Is_Balanced`
- [ ] `Post` procedure: precondition `Is_Balanced`, postcondition ledger totals still equal
- [ ] Account balance state and proof that Σdebits = Σcredits across the ledger
- [ ] Buy / Sell operations with fees/spread; reject insufficient cash or holdings
- [ ] Lot tracking per purchase; realized gain on sale under both weighted
      average and FIFO (prove lots sum to holdings and cost basis is conserved)
- [ ] Per-tick revaluation operation posting unrealized gain/loss
- [ ] Install GNATprove; get `gnatprove --level=2` clean in CI
- [ ] AUnit/test-driver cases alongside the proofs
- [ ] Export C-ABI for Ruby `ffi` (add `ffi` gem; build shared lib via `LIBRARY_TYPE=relocatable`)

## Financial statements (per user, on demand)

Requirements; the ledger computes them, Rails only renders.

- [ ] Decide chart of accounts: Cash, Holdings (per caliber), Owner's Capital,
      Retained Earnings, Realized Gain/Loss, Unrealized Gain/Loss
- [ ] Ledger supports as-of queries (balances at time T) and period queries (T1..T2)
- [ ] Balance sheet as of T: Assets = Liabilities + Equity (prove in SPARK)
- [ ] Income statement for T1..T2: realized + unrealized gains/losses, net income
- [ ] Statement of cash flows for T1..T2: operating (trades), financing (initial
      funding), opening/closing cash; reconcile to balance sheet cash
- [ ] Cross-statement checks: net income = Δ retained earnings; cash flow closing
      cash = balance sheet cash
- [ ] Rails: statement pages with date / period picker, scoped to the current user
- [ ] Rails: invalid periods (end before start, future dates) are rejected
- [ ] Tests with hand-computed fixtures for each statement

## Price index

- [ ] Interface: `current_prices` → `[{caliber, price_cents, as_of}]`
- [ ] Mock implementation: seeded random walk, bounded per tick, price ≥ 1 cent
- [ ] Price history table so portfolio history can be recomputed
- [ ] Tests for determinism and bounds

## Rails app

- [ ] Enable `bcrypt`; user model with `has_secure_password`; sessions/login/signup
- [ ] Signup grants $1,776.00 (177_600 cents) via a ledger deposit transaction
- [ ] `Caliber` model + seeds (15+ calibers)
- [ ] Solid Queue recurring job to tick prices (config/recurring.yml)
- [ ] Holdings and trades (buy/sell) through the ledger
- [ ] Portfolio snapshots (timestamp, cash, holdings value, net worth)
- [ ] Portfolio history page (chart of net worth over time) with range buttons:
      1D, 1W, 1M, YTD, 1Y, MAX (MAX = from account creation, indefinitely)
- [ ] Per-user cost basis setting (weighted average / FIFO), persisted on the
      user, switchable at runtime; applies to portfolio and statements
- [ ] Price history rollups so MAX charts stay fast over very long histories
- [ ] Tests: each range boundary (incl. YTD at year start, leap days), both cost basis methods
- [ ] Authorization: users can see only their own portfolio
- [ ] Money formatting helper (cents → `$1,234.56`); no floats
- [ ] Replace default `root` route and the placeholder README stubs

## Tooling / ops

- [x] Mandatory brakeman (CI, `bin/ci`, `script/test`), STANDARDS.md, `script/{build,run,test}`
- [x] Ruby coverage gate (SimpleCov, 100% line+branch when `COVERAGE=1`)
- [x] CI job for `ledger_core` (build + GNATprove)
- [ ] GitHub: protect `main`, require all CI jobs (manual setting)
- [ ] Install GNATprove locally (`script/test` fails without it, on purpose)
- [ ] Ada unit test harness (`ledger_core/tests/`, AUnit) and an Ada coverage
      gate (GNATcov) to enforce "every subprogram tested"
- [ ] Verify the CI action `alire-project/setup-alire` version/inputs on first run
- [ ] Add `bin/rails db:migrate` first migration; `db:prepare` needs a schema
- [ ] Dockerfile: build `ledger_core` into the image
- [ ] Update Kamal config for the real app name and host
