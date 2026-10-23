# TODO

Legend: `[x]` done, `[ ]` not started.

## ⚠️ Needs Jonathan's review

Assumptions and deviations made while you were away. Please skim and overrule
anything you disagree with. Nothing is committed; all changes are in the working tree.

### Decisions I made where your answers left a gap

1. **Tick interval 5 min; spread 0.5% + fee 1% per trade** (the defaults I proposed;
   `config.x.spread_bps = 50`, `config.x.fee_bps = 100`, `config.x.tick_interval_minutes = 5`).
   The 5-minute schedule is duplicated in `config/recurring.yml`; change both.
2. **Spread and fee are both booked as "Trading Costs"** (expense) on top of the
   market value of the ammo, so holdings are carried at market value and a trade
   does not create an instant unrealized loss.
3. **Price unit is the centicent (1/100 cent per round)**, not whole cents, so cheap
   rounds (.22 LR ≈ 10¢) can move by realistic amounts. Money is still integer cents.
   Value of a position = round-half-up(qty × price / 100).
4. **Cost basis (both methods)** is computed by replaying the trade history in
   the engine, per the user's current setting; the ledger itself is method-independent.
   Net worth and net income are identical under both methods; only the
   realized/unrealized split differs (verified with hand-computed fixtures).
5. **Seed calibers and prices** are my plausible guesses (e.g. 9mm $0.25, .22 LR
   $0.10, 12 ga $0.35); the mock price walk is ±2% per tick, clamped to $0.01–$10.00
   per round, seeded from `config.x.price_index_seed = 1776`.
6. **Indefinite history:** raw ticks are kept for 7 days, then rolled up into
   hourly/daily/weekly OHLC buckets (nothing deleted). Chart resolution: 1D/1W raw,
   1M hourly, YTD/1Y daily, MAX weekly.
7. **Retained earnings** are derived (income − expense to date); there are no
   period-closing entries. Equity = Owner's Capital + net income to date.

### Deviations from the stated principles

8. **All money/price/quantity math is in the SPARK engine** (you asked for this
   after the first version). Rails stores and retrieves integers and calls the
   engine; running cumulative totals per transaction replace every SQL `SUM`.
   `test/architecture/no_money_math_test.rb` is a ratchet that fails on arithmetic
   in `app/`; its allowlist (`test/architecture/math_allowlist.yml`, 20 entries)
   holds only calendar/time math and engine bindings. Please skim the allowlist.
   Remaining in Ruby by design: calendar/time-zone arithmetic, SHA-256 randomness
   (the engine maps it to a bounded change), string assembly, comparisons for control flow.
9. **Proof status:** all 1444 checks proved at GNATprove `--level=4` (CVC5/Z3/
   Alt-Ergo), no `Assume`/`Annotate`/`Suppress`. Caveats: (a) the C export shim
   (`ledger_core-c_api`) is not SPARK (it only marshals, null-checks and catches
   exceptions); (b) contracts/ghost code are compiled out of the shipped library
   (`ledger_core.adc` `Assertion_Policy (Ignore)`) because evaluating them made
   `cost_basis` cubic; they are proved, and overflow/range/index checks stay on;
   (c) ghost code has no direct unit tests (covered by proof and the differential
   test); (d) a level-4 proof takes about 7.5 minutes, and building in
   `ledger_core/obj` while it runs breaks it ("no checks generated").
10. **Append-only postings are enforced in the Rails models and by SQLite triggers**
    (BEFORE UPDATE/DELETE on `ledger_transactions`, `ledger_postings`, `trades`; UPDATE on
    `price_ticks`), so `update_all`/raw SQL are refused too. The primary DB now uses
    `db/structure.sql` (needs the `sqlite3` CLI) because `schema.rb` can't carry triggers.
11. **Holdings carrying value can differ from exact market value by ≤ 1¢ per
    caliber right after a trade**, until the next tick's revaluation, because the
    sold/bought portion and the remainder are rounded separately. Balances still
    always balance.
12. **Engine limits (new, much larger):** no trade-count or caliber limit and
    `cost_basis` is linear, but trades must be ordered by caliber then time;
    holdings are capped at 10^9 rounds per caliber, totals at 10^17 cents (cells
    at 2.5e16). A buy past 10^9 rounds is refused with a message. The Rails trade
    limit was removed.
13. **Statements:** all times are UTC; periods are `(from, to]`; a custom `from`/`to`
    date covers whole days; a start before the account began is clamped (with a
    note); future end dates, end ≤ start, and bad input return 422 with a message.
    Engine check failures (`Unbalanced`, `Not_Reconciled`) deliberately raise
    (500) rather than render a statement.
14. **Auth:** I used Rails 8's generator but removed password-reset, mailers and
    ActionCable (no mail setup; untested code isn't allowed by the coverage gate).
    Login column is `email_address`, min password length 8, login/signup rate
    limited to 10 per 3 minutes. There is no email verification and no password reset.
15. **Net worth chart** does one indexed as-of lookup per sample (≤ 200 points + 1
    query), then the engine's balance sheet; it rejects accounts that start
    before 1970 (engine `sample_times` needs start ≥ 0).
16. **Dev environment:** Solid Queue runs inside Puma in development
    (`SOLID_QUEUE_IN_PUMA=""` opts out); `config/database.yml` gained a dev queue DB;
    the test cache store is now `:memory_store` (for rate-limit tests).
17. **Ledger errors from the engine for out-of-range quotes** (price > 10^7 or
    value > 10^12) would show as a 500 rather than a friendly message. Unreachable
    with the mock index.
18. **Test count gate:** the 100% coverage gate passes vacuously with zero tests
    (not a risk now that there are 300+ tests, but still true).
19. **Shared library runtime:** the `.so` needs `libgnat-16.so` from the Alire
    toolchain (found via RUNPATH). A production image must include it or set
    `LD_LIBRARY_PATH`. The Dockerfile has **not** been updated to build the engine
    (see Tooling below), so a container deploy won't work yet.
20. **CI untested:** `.github/workflows/ci.yml` changes (Alire setup in the Rails
    test jobs, `ledger_core` job) have never run on GitHub; verify the
    `alire-project/setup-alire@v5` inputs on the first run.
21. **Ledger rows must be chronological per user:** a row older than the user's
    latest row raises `Ledger::Poster::OutOfOrder` (the running totals chain
    depends on it). Writers read the clock inside the user lock.
22. **Migrations:** `20261023000200` adds 40 cumulative totals columns and
    `quantity_after`; `…0300` backfills by replaying through the engine. I edited
    000200 after migrating the dev DB; a fresh `db:prepare` is fine, but any old
    dev DB should be recreated.
23. **`.rubocop.yml` now excludes `ledger_core/**`** (the Ruby differential test there
    gave 591 offenses). Revert if you'd rather lint it.
24. **Differential test** (`ledger_core/tests/differential/diff_test.rb`, ~443k
    checks against pure-Ruby reference) runs in `script/test` and CI.
25. **`next_price` semantics** keep the old Ruby behavior,
    `price + trunc(price × bps / 10000)`, which differs from price × (10000+bps)/10000
    for downward moves.

## Security & correctness audit (2026-10-22)

Findings from a read-only audit (web/auth, Rails ledger, FFI/C shim, SPARK engine).
Nothing was executed during the audit; items marked *(verify)* must be confirmed
(and the claim either fixed or struck out with a note) before being closed.
Every fix starts with a failing test (STANDARDS.md). IDs: W=web, L=ledger/DB,
F=FFI, E=engine, T=tooling/tests/docs.

### High
- [x] **W1** TLS not enforced in production: enable `assume_ssl`/`force_ssl` (exclude `/up`
      from redirect), HSTS, `Secure` cookie; enable proxy SSL in `config/deploy.yml`
      - *done: force_ssl/assume_ssl/HSTS/Secure cookie, kamal proxy ssl. `APP_HOST` and deploy `host` are still placeholders (app.example.com): set the real domain*
- [x] **W2** Set `config.hosts` in production (exclude `/up`); no Host-header poisoning
- [x] **W3** Session cookie is 20-year permanent and `Session` rows never expire: add TTL
      (checked in `find_session_by_cookie`), `secure:` flag, cleanup job for expired rows
- [x] **L1** Per-user `with_lock` is a no-op on SQLite (`FOR UPDATE` ignored): set the SQLite
      transaction mode to IMMEDIATE explicitly (*verify* Rails 8.1 default) and add a
      two-thread/process concurrent-trade test proving no overspend / no 500
      - *STRUCK OUT: Rails 8.1.4 SQLite already runs every joinable transaction as `BEGIN IMMEDIATE`, so `with_lock` serializes; pinned with a real concurrent-trade test (`test/concurrency`)*
- [x] **L2** Ledger guarantees exist only in Ruby: add DB backstops: drop the `default: 0`
      on running-total columns (after backfill), per-user unique `seq` (chain guard),
      CHECKs for cash/holdings debits >= credits and total debits == credits,
      FK/consistency of `trades.user_id` with its ledger transaction
- [x] **L3** Append-only bypassable (`update_all`, `delete_all`, raw SQL, `insert_all`,
      `Caliber dependent: :destroy` on ticks): SQLite BEFORE UPDATE/DELETE triggers on
      `ledger_transactions`, `ledger_postings`, `trades` (and ticks/buckets as documented);
      supersedes "Decision" 10
- [x] **E1** Cost-basis postconditions are vacuous for value correctness
      (`cost_basis.ads` Sound / segment posts / `Compute`): state `Sales`, `End_Purchased`,
      `Realized_Gain = Sales - (Consumed - Start_Consumed)` via the ghost `Buys_*` functions;
      re-prove at level 4
- [x] **E2** Realized/unrealized split is a residual (`reports.adb:64`): compute unrealized
      independently (market - basis) and return `Not_Reconciled` if it differs from
      `Gain_Total - Realized`; stop `Revalue.all_holders` from swallowing errors silently

### Medium
- [x] **E3** Zero/low-cost trade gap: with `spread_bps = 0` and tiny fees the fee rounds to 0 and
      repeated tiny buys book free revalue gain (hand-derived, price 149 centicents). Enforce
      minimum total cost of 1 cent when V > 0 (or reject spread 0); add an economic property
      test: equity never increases from round trips when costs > 0. Reproduce first
- [x] **E4** `Apply_Transaction` doesn't bind `Kind` to posting shape: typed
      `apply_buy/sell/deposit/revalue` entry points (or kind-vs-shape check); update ABI.md
- [x] **E5** Quote returns `Ok` for V = 0 but builder returns `Bad_Argument` (500): make quote
      return `Bad_Argument`; qty 0 consistency; confirm price clamp >= 100 centicents is enforced
- [x] **E6** Revalue difference > `Max_Amount` (1e12) refused though totals reach 1e17 (wedges
      a huge holder); weighted-average basis > 1e17 fails whole report: decide, document or fix
      - *decided and documented in ABI.md 'Decided limits' (a single posting is capped at 1e12; practically unreachable); no code change*
- [x] **E7** Quote postconditions don't state `Quote.Value = Value_Of(Qty, Price)`; add
- [x] **E8** `running.adb` `Next := Zero_Totals` before `Prev` read (aliasing); also `Diff_Totals`:
      reorder/guard so aliased buffers can't bypass the balance check
- [x] **L4** `Poster::OutOfOrder` unrescued -> 500 and user blocked after a backward clock step:
      post at `max(now, previous.occurred_at)` or map to a refusal
- [x] **L5** No idempotency/double-submit protection on trades: per-form nonce with unique
      `(user_id, nonce)` index
- [x] **L6** `PriceRollup#roll` not atomic; crash leaves stale/missing daily/weekly buckets;
      late ticks never rolled up: transaction per caliber and recompute from earliest changed hour
- [x] **L7** `TickRunner`/`Mock` read `latest` outside the transaction; rescue `RecordNotUnique`,
      use `insert_all unique_by`
      - *mostly STRUCK OUT: reads were already inside the IMMEDIATE transaction (pinned by a test); hardened with validation + `insert_all unique_by`*
- [x] **L8** Missing CHECKs: price > 0 on ticks/buckets/trades (model says > 0, DB allows 0),
      `low <= open/close <= high`
- [x] **F1** Library loaded with no identity check: assert `engine_version == 200` at boot;
      ignore/restrict `LEDGER_CORE_LIB` in production (absolute path, owned by app user, not
      group/world-writable); wrap unknown status codes (`KeyError`) in `LedgerEngine::Error`
- [x] **F2** Ruby input coercion: one strict `coerce_int64` helper (reject Float, out-of-range,
      non-Integer) mapping to `LedgerEngine::Error`/refusal; validate `bps_from_random` range;
      `pack` row-length check; `Deposit` huge amounts become a refusal not a 500
- [x] **F3** `sample_times` allocates before bounds check: validate `1..10**6` in Ruby first
- [x] **F4** `audit_chain` `flatten` can desync buffer length: `flatten(1)` + size assertion on
      every `int64s(...)` followed by a count
- [x] **F5** Threads/fork smoke test (8 threads x `apply_transaction`/`cost_basis`; once after
      fork); check whether GNAT installs SIGSEGV handlers that turn faults into status 10 *(verify)*
      - *done: threads/fork tests added. Measured: the GNAT runtime installs fault handlers; a bad pointer returns status 10 instead of crashing Ruby (so Ruby's crash reporter will not fire for engine faults)*
- [x] **W4** Content-Security-Policy (script_src self + nonces)
- [x] **W5** Rate limiting: add per-account key, verify `trusted_proxies`/`remote_ip` behind the
      proxy *(verify)*, note signup account-creation abuse
- [x] **T1** Replace the line-based ratchet scanner with an AST (Prism) scanner; scan
      migrations, rake, `script/`, `app/javascript`, other `config/*.rb`; catch unspaced operators,
      multi-line expressions, SQL arithmetic in strings (`update_all`, `Arel.sql`), `.average`,
      `.clamp`, `.increment!`, `.send(:+)`; make allowlist entries exact (not whole-line substrings)
      - *done: Prism AST scanner, exact allowlist entries (41); scans migrations, rake, script, JS*

### Low
- [x] **E9** Proof-boundary: CI rule that no exported subprogram called by the shim carries a `Pre`
      (contracts are compiled out by `Assertion_Policy (Ignore)`); document aliasing/length contract
- [x] **T2** Differential/property tests: add independent economic and Rails-flow property tests
      (round-trip equity, account 4 == realized + unrealized, larger/mixed-caliber cost-basis
      generators, multiple seeds)
- [x] **F6** RUNPATH into the Alire toolchain: ship `libgnat` beside the library (`$ORIGIN`) or
      link statically (also in Dockerfile item below)
      - *done: Dockerfile builds relocatable library + libgnat with `$ORIGIN`, build-time `ldd` check (agent ran a full `docker build` and a boot check; not re-run by the reviewer). Uses `--release`, not `--validation`: confirm profile difference. x86_64 only*
- [x] **L9** `Portfolio.for` reads without a snapshot (wrap in a read transaction)
- [x] **L10** `Revalue.all_holders` reads prices before the per-user lock (older revalue can overwrite)
- [x] **L11** Quantity parsing accepts `1_000`, `+5`, ` 5 `: validate `/\A[1-9]\d*\z/` after strip
- [x] **L12** Backfill migration: assert totals match postings afterwards, accept symbol/integer kind
      consistently *(verify)*, document that it depends on live engine code
- [x] **W6** Password max length 72 on the model *(verify bcrypt behaviour)*; common-password check
      - *done except max length, struck out: Rails 8.1 `has_secure_password` already rejects > 72 bytes (verified); added common-password denylist*
- [ ] **W7** (pins done; the master.key part needs you: `git ls-files config/master.key` must print
      nothing, the reviewer's shell cannot run git) `config/master.key` untracked (`git ls-files`) and excluded by `.dockerignore`
      *(verify)*; pin GitHub Actions to commit SHAs
- [x] **T3** Stale docs: README "integer cents per round" (centicents), `Holdings:<caliber>`/`Market`
      accounts (single Holdings account), "properties to be proved or tested"; re-run gnatprove and
      update the "1444 checks" figure; update "Decisions" 10, 11, 17 when fixed
- [x] **T4** SQLite backups for production (volume snapshot/`.backup`), document in deploy docs

## What exists

- [x] Rails 8.1 app with users, login/signup/logout, per-user cost basis setting
- [x] `ledger_core` SPARK engine: validation, quotes, cost basis (weighted average
      and FIFO), balance sheet, income statement, cash flow; all proved
      (`gnatprove --level=4`, 1444 checks), 12742 unit checks, differential test, C ABI documented in
      `ledger_core/ABI.md`
- [x] Ruby ffi bridge (`LedgerEngine`), append-only ledger tables, services for
      deposit / buy / sell / revalue, per-tick revaluation hook, $1,776 signup grant
- [x] Mock price index, 15 calibers, Solid Queue tick job, rollups, history ranges
- [x] Dashboard (portfolio, trading, net worth chart with 1D/1W/1M/YTD/1Y/MAX)
- [x] Balance sheet, income statement, statement of cash flows with period picker
- [x] Mandatory gates: rubocop, brakeman, bundler-audit, importmap audit, 100%
      line+branch coverage, GNATprove, Ada unit tests; `script/{build,run,test}`
- [x] `script/test` passes end to end locally (Rails 516 tests, Ada 12742 checks,
      1444 proofs)

## Next

### Product
- [ ] Email verification and password reset (needs mail setup)
- [ ] Real market-data feed behind the `PriceIndex` interface

### Ledger core
- [ ] Make the C export shim provably thin (or SPARK) and test ghost code directly (item 9)
- [ ] Ada coverage gate (GNATcov) to enforce "every subprogram tested"

### Tooling / ops
- [ ] GitHub: protect `main`, require all CI jobs (manual setting)
- [ ] Dockerfile: install Alire/GNAT, build the relocatable `ledger_core` library
      into the image, ship `libgnat`, set `LEDGER_CORE_LIB`
- [ ] Update Kamal config for the real app name and host
- [ ] Run CI on GitHub and fix any setup-alire issues (item 20)
- [ ] Mention `LEDGER_CORE_LIB` and the `.so` build in deployment docs
