# ledger_core design contract (v1)

This is the design behind the SPARK engine. `ABI.md` is the authoritative C
ABI; where the two differ, `ABI.md` wins. The goal: **every calculation on
money, prices and quantities in the app is done by formally verified SPARK
code.** Rails only stores and retrieves integers, hands them to the engine, and
formats strings out of pieces the engine computed.

Documented exceptions that stay outside the engine: calendar and time-zone
arithmetic (`1.month.ago`, start of year, bucket boundaries), and the SHA-256
randomness that picks the random basis-point change (the engine turns it into a
bounded change and validates it).

The engine is **stateless**: no globals, no allocation. Rails persists
everything in SQLite and passes plain data in; the engine validates, computes
and returns results or a status code.

## Units (all integers, no floating point anywhere)

| Thing      | Type            | Unit                                           |
|------------|-----------------|------------------------------------------------|
| Money      | int64           | USD cents                                      |
| Price      | int64           | **centicents** = 1/100 cent per round (so a $0.25 round is 2500) |
| Quantity   | int64           | whole rounds, >= 0                             |
| Rates      | int64           | basis points (1 bp = 0.01%)                    |
| Time       | int64           | Unix epoch seconds                             |

Value of a position: `value_cents = round_half_up(qty * price / 100)`.
Every function proves it cannot overflow for all inputs in range and rejects
out-of-range input with a status code. Bounds are in `ABI.md`.

## Chart of accounts (fixed, per user)

| Code | Account            | Type    | Normal side |
|------|--------------------|---------|-------------|
| 1    | Cash               | Asset   | Debit       |
| 2    | Holdings (at market, all calibers) | Asset | Debit |
| 3    | Owner's Capital    | Equity  | Credit      |
| 4    | Trading Gain/Loss  | Income  | Credit      |
| 5    | Trading Costs (spread + fees) | Expense | Debit |

No liabilities. Retained earnings are derived (account 4 minus account 5);
there are no closing entries. Sides: 0 = Debit, 1 = Credit.

## Transaction kinds and their postings

A transaction has 1..16 postings `{account, side, amount > 0}` and is valid iff
codes are valid and **sum(debits) = sum(credits)**. The engine *builds* every
posting list; Rails never chooses an amount.

- `deposit` (kind 0): Dr Cash X / Cr Owner's Capital X.
- `buy` (kind 1): Dr Holdings V, Dr Trading Costs C / Cr Cash V + C.
- `sell` (kind 2): Dr Cash V - C, Dr Trading Costs C / Cr Holdings V.
- `revalue` (kind 3): new market value M of all holdings vs carrying balance H.
  M > H: Dr Holdings M-H / Cr Trading Gain/Loss M-H; M < H the reverse; equal:
  no transaction. The engine sums the per-caliber market values itself.

Spread and fee on value V: `spread = ceil(V * spread_bps / 10000)`,
`fee = round_half_up(V * fee_bps / 10000)`, `C = spread + fee`.

## Running totals instead of SQL SUM

The ledger state is the **running totals**: cumulative debits and credits per
`[kind 0..3][account 1..5]` (4 x 5 x 2 = 40 int64). `apply_transaction` takes
the previous totals and a posting set and returns the new totals; Rails stores
the 40 numbers on each ledger transaction row. A balance as of time T is read
from the latest row at or before T. The engine proves, for every cell,
`new = prev + exactly what the postings put there`, that no cell overflows, and
that total debits = total credits is preserved. Period activity is
`diff_totals(closing, opening)`; statements come from `period_report`.

Holdings quantity is the same idea: `apply_trade_quantity` takes the held
quantity and the trade and returns the new held quantity, which Rails stores on
the trade row (`quantity_after`).

## Cost basis

`cost_basis` replays a user's trades in **one linear pass, with constant state
per caliber and no scratch memory**. There is no limit on the number of trades
or calibers. The trades must be grouped by caliber (ascending) and time
ordered inside a caliber. Weighted average keeps (units, basis); FIFO keeps the
current lot and the units used from it (lots are consumed in order, and a lot is
only ever looked at once). Proved: basis is conserved
(`purchased = consumed + remaining`), the cumulative consumed basis never
decreases, and it never exceeds the cost purchased.

## Display and chart math

`split_money`, `split_price` (whole + fraction, any int64), `negate`, `scale`
(chart position, exact floor), `min_max`, `sample_times` (evenly spaced chart
times) replace the arithmetic in the helpers.

## Prices

`next_price` is the mock random walk step (truncation toward zero of the
move, then clamp), `bps_from_random` maps a random 64-bit number to a bounded
basis-point change, `ohlc` / `ohlc_merge` aggregate prices into candles.

## Proof and test expectations

- `gnatprove` (command in `ABI.md`/`script/test`): every check proved, no
  `Assume`, no `Annotate`, no unproved check. SPARK_Mode is on everywhere except
  the C export shim (`Ledger_Core.C_API`), which only compares pointers to NULL,
  views C memory as Ada arrays/records and turns the status into its code.
- Run-time checks (overflow, range, index) stay enabled in the shipped library
  (`-gnato`, no `-gnatp`, no `pragma Suppress`). The shim catches every Ada
  exception and returns status 10 (`Internal_Error`), so no exception can cross
  the C ABI. Contract and ghost evaluation is switched off for the shipped
  library (`ledger_core.adc`): they are proved, and evaluating whole-array
  quantifiers at run time would turn linear algorithms quadratic.
- Properties proved as postconditions include: validated and built
  transactions balance; no overflow; running totals exact per cell and
  balanced; basis conservation and monotone consumption; assets = liabilities
  + equity; net income = change in net income to date; cash flow reconciles;
  rounding functions equal the mathematical floor/ceiling (stated without the
  division operator); `split_*` reconstruct the input exactly; `scale` is in
  `[0, size]` with exact floor semantics; `sample_times` is strictly increasing,
  ends at `finish` and fits the buffer.
- Every subprogram has a direct test in `ledger_core/tests/` (AUnit-style plain
  Ada). Ghost code is proved, never run. `ledger_core/tests/differential/
  diff_test.rb` compares every exported function against an independent
  pure-Ruby reference on seeded random inputs.
