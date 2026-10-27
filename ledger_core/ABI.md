# ledger_core C ABI (authoritative, version 0.3.0 = `engine_version` 300)

This file is the contract for callers (Rails via Ruby `ffi`). It is exact and
complete: every exported symbol, struct layout, status code and bound is here.
`DESIGN.md` explains the design; where it differs, this file wins.

The engine is stateless and pure: integer arithmetic only, no floating point,
no allocation, no global state. Every function is thread-safe and reentrant.
**Rails must perform no arithmetic on money, prices or quantities**: it stores
integers, passes them to these functions and formats strings from the pieces
returned. (Calendar/time-zone arithmetic such as `1.month.ago`, and the SHA-256
random number, are the only things that stay in Ruby.)

## What changed in the 2026-10-22 audit pass (`engine_version` 300)

All changes are **additive for callers**, with two deliberate behaviour changes
to quoting. `engine_version` now returns 300 (Ruby asserts it; the Ruby adoption, see
"Adopting the changes" below, is done).

**New exports (5, named `ledger_core_*`)**: `apply_deposit`, `apply_buy`,
`apply_sell`, `apply_revalue` (typed variants of `apply_transaction`, audit E4)
and `period_report_checked` (audit E2). 36 exports in total (the "33" in the
0.2.0 notes below was a miscount; the list there is correct).

**Behaviour changes (quotes, audit E3 / E5):**

* **Minimum cost (E3).** `quote_buy` / `quote_sell` now guarantee `costs >= 1`
  cent whenever the value is positive. If `ceil(V * spread_bps / 10000)` and
  `round_half_up(V * fee_bps / 10000)` are both 0 (only possible with
  `spread_bps = 0` and a small fee, or both rates 0), the **spread is raised to
  1 cent**. Reproduction: price 149 centicents, spread 0, fee 100 bps: one round
  is worth 1.49 cents but was booked at 1 cent with a fee of 0, so 100 buys booked
  100 cents of holdings that revalued to 149 cents, a free gain of 49 cents.
  **The default configuration (spread 50 bps, fee 100 bps) is numerically
  unchanged**: its spread is a ceiling, already >= 1 cent for any positive value.
  Only quotes with `spread_bps = 0` and `round_half_up(V*fee_bps/10000) = 0` (or
  both rates 0) change, by +1 cent of spread.
* **Zero value is not a quote (E5).** `quote_buy` / `quote_sell` return status
  `1` (`Bad_Argument`) when the value `V = round_half_up(qty*price/100)` is 0
  (zero quantity, or a price too low to be worth half a cent), where they used
  to return Ok with all-zero fields that `build_buy`/`build_sell` then refused
  with status 1 anyway. The order of checks is: range errors (status 2) first,
  then `V = 0` (1), then the business rules (4, 5, 6). `market_value` is
  unchanged: it still returns Ok with 0 for `qty = 0` (used per caliber by
  `revalue`). Prices under 100 centicents are the caller's policy (the engine
  accepts any price in 0..10^7; the mock price walk clamps at >= 100).
* **Proved** (E7): the quote's `value` is exactly `round_half_up(qty*price/100)`,
  `spread = max(ceil(V*spread_bps/10000), 1 if the fee is also 0)`, `fee`,
  `costs = spread + fee >= 1`, balanced.

**New behaviour (E2, `period_report_checked`)**: see the function. It returns
status 9 when the cost-basis realized/unrealized split disagrees with the
ledger. Existing `period_report` / `income_statement` are unchanged and still
compute `unrealized = trading_gain - realized` as a residual; prefer
`period_report_checked`.

**Hardening without ABI change (E8, E9):** `apply_transaction` and
`diff_totals` read (copy) every input before writing the output, so an output
that overlaps an input can no longer bypass the validity/balance checks;
`sample_times` checks its buffer bounds at run time instead of by a
precondition (see "Aliasing and lengths").

### Adopting the changes (Ruby)

1. Add the five symbols to `native.rb` (signatures in the prelude below).
2. Post transactions with the typed entry points: `apply_deposit` for the signup
   deposit and deposits, `apply_buy` / `apply_sell` for trades, `apply_revalue`
   for ticks. A set of the wrong shape for the kind is status 1.
3. Treat status 1 from `quote_buy`/`quote_sell` as a user refusal ("trade too
   small"), not an engine bug (it used to surface later from `build_*`).
4. Statements: call `period_report_checked(opening, closing, basis_report, out)`
   with the `BasisReport` of the same period and trades instead of
   `period_report`; status 9 (`Not_Reconciled`) means the ledger and the trades
   disagree and must be a loud error (never render the statement).
5. Version assertion bumped to 300 together with the engine (done).

## What changed from the first version (0.1.0)

**Removed / renamed exports: none.** All nine old symbols remain, with the
same signatures. Behaviour changes:

* `ledger_core_cost_basis`: trades must now be **grouped by caliber (ascending)
  and time-ordered inside each caliber** (was: globally time-ordered, any
  caliber order). Order by `caliber_id, occurred_at, id`. The 10000-trade and
  64-caliber limits are **gone** (see the function); caliber codes may be any
  int32. A caliber may now hold at most 10^9 units and (weighted average) at
  most 10^17 cents of basis (status 2). `purchased`, total sales and any total
  over 10^17 give status 2.
* `ledger_core_engine_version` returned 200 in 0.2.0 (300 since 0.3.0).
* New status `10` (`Internal_Error`).
* The old 5x2 `AccountTotals` and the 4x5x2 `Activity` structs are unchanged;
  `Activity` is the same layout as the new `Totals` (running totals).
* `balance_sheet`, `income_statement`, `cash_flow`: unchanged inputs. Build the
  inputs with `collapse_kinds` / `diff_totals` instead of SQL SUM.

**New exports** (33 exports in total, all named `ledger_core_*`):
`apply_transaction`, `diff_totals`, `collapse_kinds`, `audit_chain`,
`period_report`, `build_deposit`, `build_buy`, `build_sell`, `revalue`,
`apply_trade_quantity`, `portfolio_position`, `sum`, `split_money`,
`split_price`, `negate`, `scale`, `min_max`, `sample_times`, `next_price`,
`bps_from_random`, `ohlc`, `ohlc_merge`.

## Building and loading

```sh
cd ledger_core
LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --validation   # shared library
alr build --validation                                        # static (default), used by tests
```

Resulting shared library (a symlink to the versioned file next to it):

```
ledger_core/lib/libLedger_Core.so  ->  Ledger_Core.so.0.1.0-dev
```

Note the capitalised `Ledger_Core` (from the GPR `Library_Name`). The library
is a GNAT *stand-alone* library: it carries its own Ada runtime elaboration,
which runs automatically when the library is loaded. **No init or final call is
needed** from Ruby. It links dynamically to `libgnat-16.so`, which the library
finds via its RUNPATH inside the Alire toolchain directory; if the library is
moved to a machine without that toolchain, set `LD_LIBRARY_PATH` to the
directory holding `libgnat-16.so`.

Do not use symbols other than the `ledger_core_*` ones listed below; the
library also exports Ada-mangled names that are not part of the ABI.

### Run-time checks, exceptions, proofs

* Run-time checks (overflow, range, index, division by zero) are **enabled** in
  the shared library: there is no `-gnatp` and no `pragma Suppress`. Everything
  is also proved free of run-time errors by GNATprove, so none can fire; if one
  ever did it would raise, never silently wrap.
* **No Ada exception can cross the C ABI.** Every export catches all
  exceptions and returns status `10` (`Internal_Error`). Tested (calling with
  unreadable pointers). Treat 10 as a bug in the engine or in the arguments'
  memory and fail loudly.
* Contracts, ghost code and loop invariants are proved, not evaluated at run
  time in the shipped library (`ledger_core/ledger_core.adc`).
* Proof command (CI and `scripts/test.sh` run exactly this):
  `cd ledger_core && alr exec -- gnatprove -P ledger_core.gpr --level=4 --warnings=error -j0`
  (all checks proved; no `Assume`, no `Annotate`).

## Conventions

* All integers are signed (except `ledger_core_bps_from_random`'s first
  argument, `uint64`), little-endian (x86_64 / aarch64 Linux), natural
  alignment. There are no booleans, floats or strings.
* `int32`/`int64` below are Ruby ffi `:int32` / `:int64`.
* Every function except `ledger_core_engine_version` returns an `int32`
  **status** (table below). On any non-zero status every output struct/value
  is set to all zeros (when its pointer was non-null), so it is safe to ignore.
  Exception: when a pointer argument is NULL (status 1) nothing is written.
* Pointers: caller allocates all memory. Output memory must not overlap any
  input memory (outputs are zeroed first).
* **Aliasing and lengths (audit E9).** Output memory must not overlap input
  memory (above). `apply_transaction`, the typed `apply_*` entry points and
  `diff_totals` are additionally safe when it does: they copy every input before
  writing any output, so an aliased output cannot bypass a check (they then
  behave as if the memory did not overlap). Nothing else guarantees this. The
  engine cannot know the length of a C array: **the caller must pass a pointer
  to at least `count` elements** (`count * 16` bytes for postings, `* 32` for
  trades, `* 320` for `Totals` rows, `* 8` for `int64` arrays, `* 48` for
  candles, `max_points * 8` for `sample_times`) and, for structs, the full size
  in the layout table. Reading past a buffer is the caller's bug; where it faults
  the shim returns status 10 (best effort, not a guarantee). No exported
  subprogram has a `Pre` contract (contracts are compiled out of the shipped
  library): every argument is checked at run time and reported by a status. This
  is enforced by `ledger_core/tests/check_contract_boundary.rb` (run by
  `diff_test.rb`, hence by `scripts/test.sh` and CI).
* Pointers (continued): A NULL pointer where one is required
  gives status 1 (`Bad_Argument`). Arrays are pointer + `int32` count; the
  engine only reads input arrays. For an array argument with count 0 the
  pointer may be NULL; a negative count is status 1.
* Order of checks: pointers/counts, argument ranges, structure, then business
  rules. If several things are wrong the first one found is reported (each
  function below lists its order).

### Status codes

| Code | Name                  | Meaning |
|------|-----------------------|---------|
| 0    | Ok                    | Success. |
| 1    | Bad_Argument          | NULL pointer, negative count, count outside 1..16 for postings, unknown account/side/method/kind/invert code, non-positive posting or deposit amount, `t_start > t_end`, empty input where at least one element is needed, inconsistent range arguments (documented per function), a quote whose value is 0, postings whose shape does not match the typed `apply_*` entry point. |
| 2    | Out_Of_Range          | A number is outside its documented bounds (see Bounds), a total would exceed its limit. |
| 3    | Unbalanced            | Debits do not equal credits (transaction, running totals, account totals, or an inconsistent quote). |
| 4    | Insufficient_Cash     | Buy total (value + costs) exceeds `cash_available`. |
| 5    | Insufficient_Holdings | A sell exceeds the units held. |
| 6    | Negative_Proceeds     | Sell costs exceed sell value. |
| 7    | Bad_Order             | Trades not grouped/ordered as required, or running totals go backwards (`diff_totals`, `audit_chain`, `period_report`). |
| 8    | Negative_Balance      | Cash or holdings balance would be/is negative. |
| 9    | Not_Reconciled        | `cash_flow` does not reconcile; `period_report_checked`: the cost basis report is inconsistent or its realized/unrealized split disagrees with the ledger. |
| 10   | Internal_Error        | An Ada exception was caught at the C boundary (should never happen). |

### Units

| Thing    | Type  | Unit |
|----------|-------|------|
| Money    | int64 | USD cents |
| Price    | int64 | centicents per round (1/100 cent); $0.25 = 2500 |
| Quantity | int64 | whole rounds |
| Rates    | int64 | basis points; 100 bps = 1% |
| Time     | int64 | Unix epoch seconds |

Value of a position: `round_half_up(qty * price / 100)` = `floor((2*qty*price + 100) / 200)`.
Spread: `ceil(value * spread_bps / 10000)`.
Fee: `round_half_up(value * fee_bps / 10000)` = `floor((2*value*bps + 10000) / 20000)`.
All intermediate products are computed exactly in 128 bits (the proofs state
the results as exact floor/ceiling without using the division operator).

### Bounds (violations give status 2 unless stated)

| Quantity | Allowed |
|----------|---------|
| Posting amount | 1 ..= 10^12 (0 or negative: status 1) |
| Deposit cents | 1 ..= 10^12 (0 or negative: status 1) |
| Trade qty | 0 ..= 10^9 in quotes; 1 ..= 10^9 per trade in `cost_basis`/`apply_trade_quantity` |
| Units held of one caliber | 0 ..= 10^9 (`Max_Held`) |
| Price | 0 ..= 10^7 |
| Basis points | 0 ..= 10000 |
| Market value of one trade | <= 10^12 cents |
| Buy `total_cash_out` | <= 10^12 cents |
| `qty_held` (quote_sell) | >= 0 (any int64) |
| Trade value (cost_basis) | 0 ..= 10^12 |
| Trades per `cost_basis` call | up to 2147483646 (count is int32; `Int32.max` gives status 2) |
| Calibers per `cost_basis` call | unlimited (caliber is any int32) |
| `cost_basis` totals | purchased (up to the end) <= 10^17, total sales in the period <= 10^17; weighted-average basis of one caliber <= 10^17 |
| Running-total cell (`Totals`) | 0 ..= 2.5 * 10^16 (`Max_Cell` = 10^17 / 4) |
| Account totals / activity entries (5x2 and `cash_flow` input) | 0 ..= 10^17 |
| Opening/closing cash | -10^17 ..= 10^17 |
| Realized gain input | -10^18 ..= 10^18 |
| Revalue: per-caliber value | 0 ..= 10^12; their sum <= 10^17; carrying 0 ..= 10^17; difference <= 10^12 |
| `sum` values | each and every running sum within +-10^17 |
| Chart: times | 0 ..= 10^12; size 0 ..= 10^9; sample buffer 1 ..= 10^6 slots |
| Price walk | prices/floor/ceiling 0 ..= 10^7; max step 0 ..= 10000 |
| Candle | prices 0 ..= 10^7, `low <= open,close <= high`, ticks 0 ..= 10^17, tick sum <= 10^17 |

## Struct layouts

Offsets in bytes; `sizeof` in parentheses. Every field is an `int64` unless
noted. Unused/reserved fields are written as 0 and ignored on input.

```
Posting (16)         { int32 account @0;  int32 side @4;  int64 amount @8 }
PostingSet (264)     { int32 count @0; int32 reserved @4; Posting postings[16] @8 }
                     -- only postings[0 .. count-1] are meaningful; the rest are zero
Trade (32)           { int32 caliber @0;  int32 side @4;  int64 qty @8;
                       int64 value @16;   int64 time @24 }
BuyQuote (40)        { value, spread, fee, costs, total_cash_out }
SellQuote (40)       { value, spread, fee, costs, net_cash_in }
BasisReport (40)     { realized_gain, basis_at_start, basis_at_end, purchased, consumed }
AccountTotal (16)    { int64 debits @0; int64 credits @8 }
AccountTotals (80)   AccountTotal[5]   -- index 0 = account 1 ... 4 = account 5
Totals (320)         AccountTotal[20]  -- index = kind * 5 + (account - 1); (also "Activity")
BalanceSheet (56)    { cash, holdings, total_assets, owners_capital,
                       net_income_to_date, total_equity, total_liabilities }
IncomeStatement (40) { realized_gain, unrealized_gain, trading_gain_total,
                       trading_costs, net_income }
CashFlow (32)        { financing, investing, operating, net_change }
PeriodReport (184)   { BalanceSheet opening @0; BalanceSheet closing @56;
                       IncomeStatement income @112; CashFlow flow @152 }
Revaluation (24)     { int64 market_total @0; int64 amount @8;
                       int32 direction @16; int32 reserved @20 }
MoneyParts (24)      { int64 whole @0; int64 fraction @8;
                       int32 negative @16; int32 reserved @20 }
Extent (16)          { int64 low @0; int64 high @8 }
Candle (48)          { open, high, low, close, ticks, last_as_of }
```

Codes: account 1 Cash, 2 Holdings, 3 Owner's Capital, 4 Trading Gain/Loss,
5 Trading Costs. Posting side 0 = Debit, 1 = Credit. Trade side 0 = buy,
1 = sell. Method 0 = weighted average, 1 = FIFO. Transaction kind (running
totals row) 0 = deposit, 1 = buy, 2 = sell, 3 = revalue. Revaluation direction
0 = nothing to post, 1 = gain, 2 = loss.

## The running-totals model (what Rails persists)

Every ledger transaction row stores **its own postings** (account, side,
amount; take them from the `PostingSet` the engine built) **and the 40
running-total numbers** the engine returned, i.e. the cumulative debits and
credits of that user's whole ledger *including this transaction*, per
`[kind][account]`. Suggested columns on `ledger_transactions` (bigint, default
0, NOT NULL), in `Totals` index order (cell `i` = `kind * 5 + account - 1`,
debits then credits):

```
deposit_cash_debits,   deposit_cash_credits,   deposit_holdings_debits,   deposit_holdings_credits,
deposit_capital_debits, deposit_capital_credits, deposit_gain_debits, deposit_gain_credits,
deposit_costs_debits,  deposit_costs_credits,
buy_cash_debits ... buy_costs_credits,
sell_cash_debits ... sell_costs_credits,
revalue_cash_debits ... revalue_costs_credits
```

* **Latest totals** (to apply the next transaction): the 40 columns of the
  user's latest row (highest `occurred_at`, ties by `id`), or all zeros if the
  user has no row yet. Lock the user while reading and writing (as today).
* **Totals as of time T:** the 40 columns of the latest row with
  `occurred_at <= T` (ties broken by `id`), or zeros if none. No `SUM`, no
  `GROUP BY` over money anywhere.
* **Balance sheet as of T:** `collapse_kinds(totals_at(T))` -> `balance_sheet`.
* **Period (from, to]:** `period_report(totals_at(from), totals_at(to), realized_gain, out)`.
  `realized_gain` is from `cost_basis`. It returns both balance sheets, the
  income statement and the cash flow, already cross-checked. (Or use
  `diff_totals` + `collapse_kinds` + `income_statement` + `cash_flow` yourself.)
* **Chart:** `sample_times` gives the sample times; for each, read the totals
  row, `collapse_kinds`, `balance_sheet`, plot `total_equity`.
* Each trade row stores `quantity_after` (the engine's `apply_trade_quantity`
  result for that caliber). Held quantity of a caliber = `quantity_after` of its
  latest trade (ties by `id`), 0 if none. Users holding rounds = users with a
  latest `quantity_after > 0` for some caliber. No `SUM` of quantities.

Proved properties of the running totals: `apply_transaction` produces, for every
cell, exactly `prev + what the postings put on that account/side` (only for the
posted kind), no cell leaves `0 ..= Max_Cell`, and total debits = total credits
is preserved; cash and holdings never go negative; `diff_totals` is exact and
non-negative.

## Ruby ffi prelude (shared by the snippets)

```ruby
require "ffi"

module LedgerCore
  extend FFI::Library
  ffi_lib File.expand_path("ledger_core/lib/libLedger_Core.so", Rails.root)

  OK = 0
  TOTALS_BYTES = 320   # 20 cells x [debits, credits] int64
  SET_BYTES = 264      # PostingSet

  {
    engine_version: [[], :int32],
    validate_transaction: [%i[int32 pointer], :int32],
    apply_transaction: [%i[int32 pointer pointer pointer], :int32],
    apply_deposit: [%i[pointer pointer pointer], :int32],
    apply_buy: [%i[pointer pointer pointer], :int32],
    apply_sell: [%i[pointer pointer pointer], :int32],
    apply_revalue: [%i[pointer pointer pointer], :int32],
    diff_totals: [%i[pointer pointer pointer], :int32],
    collapse_kinds: [%i[pointer pointer], :int32],
    audit_chain: [%i[int32 pointer], :int32],
    build_deposit: [%i[int64 pointer], :int32],
    build_buy: [%i[pointer pointer], :int32],
    build_sell: [%i[pointer pointer], :int32],
    revalue: [%i[int32 pointer int64 pointer pointer], :int32],
    market_value: [%i[int64 int64 pointer], :int32],
    quote_buy: [%i[int64 int64 int64 int64 int64 pointer], :int32],
    quote_sell: [%i[int64 int64 int64 int64 int64 pointer], :int32],
    apply_trade_quantity: [%i[int64 int32 int64 pointer], :int32],
    portfolio_position: [%i[int64 int64 pointer], :int32],
    sum: [%i[int32 pointer pointer], :int32],
    cost_basis: [%i[int32 int32 pointer int64 int64 pointer], :int32],
    balance_sheet: [%i[pointer pointer], :int32],
    income_statement: [%i[pointer int64 pointer], :int32],
    cash_flow: [%i[pointer int64 int64 pointer], :int32],
    period_report: [%i[pointer pointer int64 pointer], :int32],
    period_report_checked: [%i[pointer pointer pointer pointer], :int32],
    split_money: [%i[int64 pointer], :int32],
    split_price: [%i[int64 pointer], :int32],
    negate: [%i[int64 pointer], :int32],
    scale: [%i[int64 int64 int64 int64 int32 pointer], :int32],
    min_max: [%i[int32 pointer pointer], :int32],
    sample_times: [%i[int64 int64 int32 pointer pointer pointer], :int32],
    next_price: [%i[int64 int64 int64 int64 int64 pointer], :int32],
    bps_from_random: [%i[uint64 int64 pointer], :int32],
    ohlc: [%i[int32 pointer pointer], :int32],
    ohlc_merge: [%i[int32 pointer pointer], :int32]
  }.each { |name, (args, ret)| attach_function name, :"ledger_core_#{name}", args, ret }
end
```

Use `FFI::MemoryPointer` for every pointer (it is zero-filled). Struct memory is
read/written with `put_int32`/`put_int64` at the offsets above, or with
`write_array_of_int64`/`read_array_of_int64` for all-int64 structs (`Totals`,
`BuyQuote`, ...). Pass Ruby Integers within int64 range; ffi raises
`RangeError` outside it, so out-of-int64 input never reaches the engine.

## Status of each function at a glance

`apply_transaction`, `diff_totals`, `collapse_kinds`, `audit_chain`,
`period_report` work on running totals. `build_*` and `revalue` build posting
sets. `market_value`, `quote_*` price a trade. `apply_trade_quantity`,
`portfolio_position`, `sum` do holdings arithmetic. `cost_basis` replays trades.
`balance_sheet`, `income_statement`, `cash_flow` are the statements.
`split_*`, `negate`, `scale`, `min_max`, `sample_times` are display math.
`next_price`, `bps_from_random`, `ohlc`, `ohlc_merge` are price math.

## Functions

### `int32 ledger_core_engine_version(void)`

Returns `major * 10000 + minor * 100 + patch`; currently `300` (0.3.0). Never fails.

### `int32 ledger_core_validate_transaction(int32 count, const Posting *postings)`

Ok iff `1 <= count <= 16`, every posting has account 1..5, side 0..1, amount
1..10^12, and sum(debits) = sum(credits). Order: count/pointer (1), then per
posting in order: account/side/amount <= 0 (1), amount > 10^12 (2), then
balance (3). No output. (Posting sets built by the engine are always valid;
this is for checking anything else.)

### `int32 ledger_core_build_deposit(int64 cents, PostingSet *out)`

Builds Dr Cash `cents` / Cr Owner's Capital `cents` (count 2, postings in that
order). `cents` < 1: 1; > 10^12: 2.

```ruby
set = FFI::MemoryPointer.new(:int8, LedgerCore::SET_BYTES)
LedgerCore.build_deposit(177_600, set) # => 0 (signup deposit); set count == 2
```

### `int32 ledger_core_build_buy(const BuyQuote *quote, PostingSet *out)`

From a quote returned by `quote_buy`, builds, in this order and each only when
its amount is non-zero: Dr Holdings `value`, Dr Trading Costs `costs`, Cr Cash
`total_cash_out`. Status: 2 (any field outside 0..10^12), 3 (`costs !=
spread + fee` or `total_cash_out != value + costs`), 1 (nothing to post:
`total_cash_out` = 0).

### `int32 ledger_core_build_sell(const SellQuote *quote, PostingSet *out)`

From a quote returned by `quote_sell`: Dr Cash `net_cash_in`, Dr Trading Costs
`costs` (each only when non-zero), then Cr Holdings `value`. Status: 2 (field
outside 0..10^12), 3 (`costs != spread + fee` or `net_cash_in + costs !=
value`), 1 (`value` = 0).

### `int32 ledger_core_revalue(int32 count, const int64 *market_values, int64 carrying_holdings, Revaluation *info, PostingSet *out)`

Marks the holdings to market. `market_values` are the per-caliber market values
(each the result of `market_value`; `count` may be 0 when nothing is held, then
the pointer may be NULL). The engine sums them (`market_total`) and compares with
`carrying_holdings` (the Holdings balance from the balance sheet). If equal:
`direction` 0, `amount` 0, empty set (count 0): **post nothing**. If market >
carrying: direction 1, `amount` = difference, set = Dr Holdings / Cr Trading
Gain/Loss. If market < carrying: direction 2, set = Dr Trading Gain/Loss / Cr
Holdings. Status: 1 (NULL/negative count), 2 (a value outside 0..10^12, carrying
outside 0..10^17, sum above 10^17, difference above 10^12). `info.reserved` = 0.

```ruby
info = FFI::MemoryPointer.new(:int8, 24)
set = FFI::MemoryPointer.new(:int8, LedgerCore::SET_BYTES)
values = FFI::MemoryPointer.new(:int64, 2).write_array_of_int64([25_000, 40_000])
LedgerCore.revalue(2, values, 63_000, info, set) # => 0
info.get_int32(16) # => 1 (gain); info.get_int64(8) # => 2000
```

### `int32 ledger_core_apply_transaction(int32 kind, const PostingSet *set, const Totals *prev, Totals *next)`

Adds the postings of `set` to the running totals `prev` as kind `kind`.
Order of checks: pointers (1); `kind` outside 0..3 (1); the set invalid —
count outside 1..16 (1), bad account/side/amount (1), amount > 10^12 (2),
unbalanced (3); `prev` has a cell outside 0..`Max_Cell` (2); `prev` unbalanced
(3); a cell would exceed `Max_Cell` (2); cash or holdings balance would become
negative (8). When Ok, `next` equals `prev` plus, for kind `kind` only, exactly
the amounts the postings put on each account and side; `next` is balanced (total
debits = total credits) and cash/holdings are >= 0. Output buffers must not overlap input buffers
(see Conventions; this function copies its inputs first, so an overlapping
`next` cannot bypass a check).

**This general entry point does not bind `kind` to the posting shape** (audit
E4): any valid balanced set may be applied under any kind, which would book,
for example, a revaluation gain as a "deposit" in the running totals (the
statements classify cash flows by kind). Prefer the typed entry points below;
this one stays for backward compatibility.

```ruby
prev = FFI::MemoryPointer.new(:int8, LedgerCore::TOTALS_BYTES)   # zeros = empty ledger
nxt  = FFI::MemoryPointer.new(:int8, LedgerCore::TOTALS_BYTES)
LedgerCore.apply_transaction(0, set, prev, nxt) # => 0; kind 0 = deposit
nxt.read_array_of_int64(40) # persist these 40 numbers on the new row
```

### `int32 ledger_core_apply_deposit` / `apply_buy` / `apply_sell` / `apply_revalue(const PostingSet *set, const Totals *prev, Totals *next)`

New. Typed variants of `apply_transaction` with the kind fixed by the entry
point (0 deposit, 1 buy, 2 sell, 3 revalue) **and the postings required to
have that kind's shape**. With P(account, side) the total amount posted to one
cell (account codes in the table below, side 0 Dr / 1 Cr):

| Export          | Allowed cells | Must be positive |
|-----------------|---------------|------------------|
| `apply_deposit` | Dr Cash, Cr Owner's Capital | Dr Cash |
| `apply_buy`     | Dr Holdings, Dr Trading Costs, Cr Cash | Cr Cash |
| `apply_sell`    | Dr Cash, Dr Trading Costs, Cr Holdings | Cr Holdings |
| `apply_revalue` | exactly one of: {Dr Holdings, Cr Trading Gain/Loss} (gain) or {Dr Trading Gain/Loss, Cr Holdings} (loss) | both cells of the chosen pair |

Any posting to another cell, or a revalue posting in both directions, is status
`1`. (The shapes are exactly what `build_deposit`, `build_buy`, `build_sell` and
`revalue` produce; a set may split an amount over several postings of the same
cell.) Order of checks: pointers (1); the set invalid (1, 2, 3 exactly as in
`apply_transaction`); wrong shape for the kind (1); then the remaining checks
and results of `apply_transaction` (2, 3, 2, 8), with the same guarantees when
Ok. Output must not overlap inputs (it is nevertheless safe, as above).

### `int32 ledger_core_diff_totals(const Totals *to, const Totals *from, Totals *diff)`

Period activity: `diff = to - from`, per cell. Status: 2 (either input invalid:
a cell outside 0..`Max_Cell`), 3 (either unbalanced), 7 (`to` below `from` in
some cell). When Ok, `diff` is valid, balanced and non-negative, so it is a
valid `Activity` for `cash_flow`. Both inputs are read before `diff` is
written, so `diff` may even overlap `to` or `from` without bypassing a check.

### `int32 ledger_core_collapse_kinds(const Totals *totals, AccountTotals *out)`

Sums the four kinds of each account, debits and credits separately, into the
5-account totals used by `balance_sheet` / `income_statement`. Status 2 if a cell
is outside 0..`Max_Cell`.

### `int32 ledger_core_audit_chain(int32 count, const Totals *rows)`

Verifies stored rows, oldest first (`rows` = `count` consecutive `Totals`). Each
row, in order: valid (2), balanced (3), cash and holdings not negative (8), and
not below the previous row in any cell (7). `count` 0 is Ok. Use it for an
integrity check of a user's persisted columns.

### `int32 ledger_core_period_report(const Totals *opening, const Totals *closing, int64 realized_gain, PeriodReport *out)`

The whole statements package for a period from running totals: activity =
`closing - opening`, balance sheets of both ends, income statement (using
`realized_gain` from `cost_basis`) and cash flow. Status order: pointers (1);
`diff_totals` problems (2, 3, 7 — 7 when `closing` is below `opening`); the
opening then the closing balance sheet (2/3/8); income statement (2: gain
outside +-10^18); cash flow (9). When Ok it is **proved** that
`income.net_income == closing.net_income_to_date - opening.net_income_to_date`,
that `opening.cash + flow.net_change == closing.cash`, and that assets =
liabilities + equity at both ends. Rails does not need any further check.
Note that `income.unrealized_gain` here is the *residual* `trading_gain -
realized_gain`; nothing checks it against the trades. Use
`period_report_checked` for that.

### `int32 ledger_core_period_report_checked(const Totals *opening, const Totals *closing, const BasisReport *basis, PeriodReport *out)`

New (audit E2). Like `period_report`, but the realized/unrealized split is
**proved against the cost basis instead of assumed**. `basis` is the
`BasisReport` that `cost_basis` returned for the same user, trades and period
`(t_start, t_end]` whose ledger rows are `opening` (as of `t_start`) and
`closing` (as of `t_end`). The income statement uses `realized_gain =
basis.realized_gain`, and the engine independently computes the change in
unrealized gain from the market side and the cost side:

`unrealized = (closing.holdings - basis.basis_at_end) - (opening.holdings - basis.basis_at_start)`

(Holdings are carried at market value, so the Holdings balance is the market
value.) The statement is returned only if it equals the ledger's residual
(`trading_gain - realized_gain`). Mathematically this holds exactly whenever the
trades given to `cost_basis` are exactly the trades that moved the Holdings
account (same `value` per trade as the quote's `value`), whatever the prices did,
because `trading_gain = delta holdings - purchases + sales` and `delta basis =
purchases - consumed`.

Status: pointers (1); any of `basis_at_start`, `basis_at_end`, `purchased`,
`consumed` outside 0..10^17 (2); then every status of `period_report` in its
order (2, 3, 7, 8, 9; `basis.realized_gain` outside +-10^18 is 2); then 9
(`Not_Reconciled`) if `basis.purchased != basis.consumed + basis.basis_at_end`
or the ledger's trading gain/loss disagrees with `realized + unrealized` as
above (the trades and the ledger tell different stories: a missing or
mis-valued trade). On Ok the report equals `period_report`'s and, additionally,
it is proved that `income.unrealized_gain` equals the independent figure and
`income.trading_gain_total = realized + unrealized`. On any non-zero status
`out` is zeroed. Treat 9 as a loud error; never render the statement.

### `int32 ledger_core_market_value(int64 qty, int64 price, int64 *value)`

`*value = round_half_up(qty * price / 100)` cents. Status 2 if qty not in
0..10^9, price not in 0..10^7, or value > 10^12 (then `*value = 0`).

### `int32 ledger_core_quote_buy(int64 qty, int64 price, int64 spread_bps, int64 fee_bps, int64 cash_available, BuyQuote *out)`

Computes value V, `spread = ceil(V*spread_bps/10000)`, `fee =
round_half_up(V*fee_bps/10000)`, `costs = spread + fee`, `total_cash_out = V +
costs`. **Minimum cost (audit E3):** when V > 0 and the spread and the fee both
come out 0, the spread is raised to 1 cent, so `costs >= 1` for every quote
(unchanged for the default 50/100 bps). Status: 2 (qty/price out of range, bps
not in 0..10000, V > 10^12, or total > 10^12), **1 (V = 0, audit E5; checked
after the range errors, before the cash check)**, 4 (`total_cash_out >
cash_available`; equality is allowed). `value` is proved to be exactly
`round_half_up(qty*price/100)`. Build the postings with `build_buy`.

```ruby
q = FFI::MemoryPointer.new(:int8, 40)
LedgerCore.quote_buy(1000, 2500, 50, 100, 200_000, q) # => 0
q.read_array_of_int64(5) # => [25000, 125, 250, 375, 25375]
```

### `int32 ledger_core_quote_sell(int64 qty, int64 qty_held, int64 price, int64 spread_bps, int64 fee_bps, SellQuote *out)`

Same value/spread/fee rules (including the 1 cent minimum cost); `net_cash_in =
value - costs`. Status: 2 (range errors as above, `qty_held < 0`), **1 (V = 0)**,
5 (`qty > qty_held`), 6 (`costs > value`; `costs == value` is allowed and gives
`net_cash_in = 0`). Build the postings with `build_sell`. Order: value (2), bps
(2), `qty_held < 0` (2), zero value (1), oversell (5), proceeds (6).

### `int32 ledger_core_apply_trade_quantity(int64 held, int32 side, int64 qty, int64 *new_held)`

Held rounds after a trade, to store as the trade row's `quantity_after`. Side 0
buy adds, 1 sell subtracts. Status: 1 (side not 0/1), 2 (`held` outside
0..10^9, `qty` outside 1..10^9, a buy that would exceed 10^9), 5 (sell exceeds
`held`). `*new_held` is always within 0..10^9.

### `int32 ledger_core_portfolio_position(int64 market_value, int64 cost_basis, int64 *gain)`

`*gain = market_value - cost_basis` (unrealized gain, may be negative). Both
inputs 0..10^17 else status 2.

### `int32 ledger_core_sum(int32 count, const int64 *values, int64 *total)`

Exact sum of `count` values (0 gives 0; pointer may be NULL then). Every value
and every running sum must be within +-10^17, else status 2. Use it for any
total Rails would otherwise add (and for tick counts).

### `int32 ledger_core_cost_basis(int32 method, int32 count, const Trade *trades, int64 t_start, int64 t_end, BasisReport *out)`

Replays one user's trades per caliber and reports for the period
`(t_start, t_end]` (start exclusive, end inclusive). `count` may be 0 (then
`trades` may be NULL; all outputs 0).

**Input order (changed):** trades must be **grouped by caliber in ascending
caliber order, and within a caliber in non-decreasing `time`** (ties keep the
given order, which is the replay order). Use `order(:caliber_id, :occurred_at,
:id)`. A caliber that reappears later, or a caliber code that goes down, is
status 7. Caliber codes may be any int32 (no dense indexing needed). To get one
caliber's basis (portfolio position) pass only that caliber's trades.

**Cost and limits:** time and memory are linear in `count`: one pass, constant
state per caliber, no scratch memory, **no limit** on the number of trades or
calibers (only `count` <= 2147483646). Bounds instead: a caliber may hold at
most 10^9 units (status 2 for a buy that would exceed it), weighted-average
basis of one caliber at most 10^17 cents, `purchased` and the period's sales at
most 10^17 cents (status 2).

Every trade (also those after `t_end`) is validated: side 0|1 (1), qty
1..10^9 and value 0..10^12 (2), order (7); first problem in trade order wins.
Trades with `time > t_end` are then not replayed (not even checked for oversell).
Replay: a sell may not exceed the units held of that caliber (5).

* Weighted average (method 0): a sell of q units from n held with basis B
  consumes `round_half_up(B * q / n)`; selling everything consumes exactly B.
* FIFO (method 1): units leave lots in purchase order; the units sold so far
  `S` have consumed `sum over lots of round_half_up(V * taken / Q)`, where
  `taken = clamp(S - units before the lot, 0, Q)` for a lot of Q units costing V.
  Pieces taken from one lot therefore sum exactly to V once the lot is empty.

Outputs (cents):

* `realized_gain` = sum over sells in `(t_start, t_end]` of (sale value - basis consumed). May be negative.
* `basis_at_start` = cost basis of units held after all trades with `time <= t_start`.
* `basis_at_end` = cost basis of units held after all trades with `time <= t_end`.
* `purchased` = total cost of all buys with `time <= t_end`.
* `consumed` = total basis consumed by all sells with `time <= t_end`.
* Proved: `purchased = consumed + basis_at_end`; all of `basis_at_start`,
  `basis_at_end` >= 0; the cumulative consumed basis never decreases (also for
  FIFO), never exceeds the cost purchased; `basis_at_end` is 0 whenever every
  unit has been sold.
* Proved against the trades themselves (audit E1, ghost sums over the input,
  independent of the replay): `purchased` = the cost of every buy with `time <=
  t_end`; `realized_gain` = (value of the sells with `t_start < time <= t_end`)
  - (`consumed` - basis consumed up to `t_start`), where the basis consumed up
  to `t_start` = (cost of the buys with `time <= t_start`) - `basis_at_start`.
  The same statement is proved for each caliber's replay (both methods). What
  is **not** proved against an independent specification is the rounded size of
  each consumed piece (weighted-average `round_half_up(B*q/n)`, FIFO per-lot
  rounding); those are proved only as stated above (exact one-step formula for
  weighted average, conservation and monotonicity for both) and are compared with
  the independent Ruby reference in the differential test.

Status: 1 (NULL `out`, NULL `trades` with count > 0, negative count, method not
0/1, `t_start > t_end`, side not 0/1), 2 (qty/value out of range, limits above),
5 (oversell), 7 (order).

```ruby
history = [[7, 0, 100, 1000, 10], [7, 0, 100, 2000, 20], [7, 1, 100, 1500, 30]]
mem = FFI::MemoryPointer.new(:int8, 32 * history.size)
history.each_with_index do |(cal, side, qty, value, time), i|
  mem.put_int32(i * 32, cal); mem.put_int32(i * 32 + 4, side)
  mem.put_int64(i * 32 + 8, qty); mem.put_int64(i * 32 + 16, value); mem.put_int64(i * 32 + 24, time)
end
out = FFI::MemoryPointer.new(:int64, 5)
LedgerCore.cost_basis(0, history.size, mem, 0, 100, out) # => 0
out.read_array_of_int64(5) # => [0, 0, 1500, 3000, 1500]  (FIFO, method 1: [500, 0, 2000, 3000, 1000])
```

### `int32 ledger_core_balance_sheet(const AccountTotals *totals, BalanceSheet *out)`

`totals` points to 5 `AccountTotal` (account 1..5 at index 0..4), e.g. from
`collapse_kinds`. Derived: `cash = D1 - C1`, `holdings = D2 - C2`,
`owners_capital = C3 - D3`, `net_income_to_date = (C4 - D4) - (D5 - C5)`,
`total_assets = cash + holdings`, `total_equity = owners_capital +
net_income_to_date`, `total_liabilities = 0`. Status: 2 (any total outside
0..10^17), 3 (sum of all debits != sum of all credits), 8 (cash < 0 or holdings
< 0). When Ok, `total_assets = total_liabilities + total_equity` is proved.

### `int32 ledger_core_income_statement(const AccountTotals *period_totals, int64 realized_gain, IncomeStatement *out)`

`period_totals` is the account activity within the period (collapsed `diff`).
Outputs: `trading_gain_total = C4 - D4`, `trading_costs = D5 - C5`,
`unrealized_gain = trading_gain_total - realized_gain`, `net_income =
trading_gain_total - trading_costs`, `realized_gain` echoed. Status: 2 (totals
outside 0..10^17 or realized gain outside +-10^18).

### `int32 ledger_core_cash_flow(const Totals *activity, int64 opening_cash, int64 closing_cash, CashFlow *out)`

`activity` is the period's `Totals` layout (e.g. `diff_totals` output; each
cell 0..10^17 here). With `N(k, a) = debits - credits` of cell (kind k, account
a): `financing = N(0, 1)`, `investing = -N(1, 2) - N(2, 2)`, `operating = -N(1,
5) - N(2, 5)`, `net_change = financing + investing + operating`. Status: 2
(entry outside 0..10^17, or opening/closing outside +-10^17), 9 (`net_change`
differs from the actual cash movement `N(0,1)+N(1,1)+N(2,1)+N(3,1)`, or
`opening_cash + net_change != closing_cash`).

### `int32 ledger_core_split_money(int64 cents, MoneyParts *out)`

Splits any int64 (negative too, including the most negative) for display:
`|cents| = whole * 100 + fraction`, `fraction` 0..99, `negative` 1 iff
`cents < 0` (also when `whole` = 0, e.g. -5 -> negative 1, whole 0, fraction 5).
Always Ok (status 1 only for NULL). Format: `"#{'-' if negative == 1}$#{delimited whole}.#{fraction.to_s.rjust(2, '0')}"`.

### `int32 ledger_core_split_price(int64 centicents, MoneyParts *out)`

Same with `|centicents| = whole * 10000 + fraction`, `fraction` 0..9999 (whole
dollars and centicents). Format: pad `fraction` to 4 digits, strip trailing
zeros, pad to at least 2 (string work only).

### `int32 ledger_core_negate(int64 x, int64 *out)`

`*out = -x`. Status 2 only for the most negative int64.

### `int32 ledger_core_scale(int64 value, int64 low, int64 high, int64 size, int32 invert, int64 *pos)`

Chart position. `raw = floor((value - low) * size / (high - low))`, or
`size / 2` (integer) when `low == high`. `pos = raw`, or `size - raw` when
`invert` = 1 (y axis). Always `0 <= pos <= size`. Status: 1 (`invert` not 0/1 or
`low > high`), 2 (`size` outside 0..10^9, or `value` outside `low..high`).
Typical: x = `scale(time, first_time, last_time, WIDTH, 0)`, y =
`scale(value, low, high, HEIGHT, 1)`, with low/high from `min_max`.

### `int32 ledger_core_min_max(int32 count, const int64 *values, Extent *out)`

`out.low`/`out.high` = smallest/largest of `count` values. `count` 0: status 1.

### `int32 ledger_core_sample_times(int64 start, int64 finish, int32 max_points, int64 *times, int32 *count, int64 *step)`

Evenly spaced increasing sample times. `times` is a caller buffer of
`max_points` int64 (1..10^6). `start <= finish` (else 1), `start >= 0`,
`finish <= 10^12` (else 2), `max_points` 0 (1) or > 10^6 (2). Result: if
`start == finish` or `max_points == 1`: `count = 1`, `step = 1`, `times[0] =
finish`. Otherwise with `span = finish - start`: `step = ceil(span / min(span,
max_points - 1))`, `count = ceil(span / step) + 1`, `times[0] = start` and
`times[i + 1] = min(times[i] + step, finish)`. Always: `step >= 1`, the last time
(`times[count - 1]`) equals `finish`, times strictly increase, `count <=
max_points`. Slots `count .. max_points - 1` are zeroed. On error `count` and
`step` are 0 and `times` is all zeros.

```ruby
times = FFI::MemoryPointer.new(:int64, 200)
count = FFI::MemoryPointer.new(:int32); step = FFI::MemoryPointer.new(:int64)
LedgerCore.sample_times(start.to_i, finish.to_i, 200, times, count, step) # => 0
times.read_array_of_int64(count.read_int32)
```

### `int32 ledger_core_next_price(int64 price, int64 change_bps, int64 max_step_bps, int64 floor, int64 ceiling, int64 *next)`

Price random-walk step. `delta = sign(change_bps) * floor(price * |change_bps| /
10000)` (truncated **toward zero**: up and down moves of the same size are
symmetric; this is the previous Ruby behaviour `price + (price*bps).quo(10000).truncate`,
not `price*(10000+bps)/10000` truncated), `next = clamp(price + delta, floor,
ceiling)`. Status: 1 (`floor > ceiling`), 2 (`price`, `floor`, `ceiling` outside
0..10^7, `max_step_bps` outside 0..10000, or `|change_bps| > max_step_bps`).

### `int32 ledger_core_bps_from_random(uint64 random, int64 max_step_bps, int64 *change)`

`*change = (random mod (2 * max_step_bps + 1)) - max_step_bps`, always within
+-`max_step_bps`. `random` is an unsigned 64-bit number (e.g. `digest.unpack1("Q>")`;
ffi `:uint64`). `max_step_bps` outside 0..10000: status 2.

### `int32 ledger_core_ohlc(int32 count, const int64 *prices, Candle *out)`

Candle of `count` >= 1 prices (each 0..10^7, else 2; count 0 gives 1):
`open` = first, `high` = largest, `low` = smallest, `close` = last, `ticks` =
`count`, `last_as_of` = 0.

### `int32 ledger_core_ohlc_merge(int32 count, const Candle *candles, Candle *out)`

Merges `count` >= 1 time-ordered candles into one: `open` of the first, `close`
of the last, `high` the largest, `low` the smallest, `ticks` the sum,
`last_as_of` the largest. Raw ticks are candles `(price, price, price, price,
1, at)`. Status per candle, in order: 2 (a price outside 0..10^7 or ticks
outside 0..10^17), 1 (not `low <= open,close <= high`), 2 (tick sum above 10^17).
`count` 0 gives 1.

## What stays proved but untested, and limits to know

* Ghost lemmas/functions (`Buys_Value`, `Lemma_*`, ...) are proved and never
  run. Everything else has direct unit tests (`ledger_core/tests`) and is
  compared with an independent Ruby reference
  (`ledger_core/tests/differential/diff_test.rb`).
* `cost_basis` count is limited by the int32 count (2147483646 trades).
* Amounts that do not fit the bounds above are rejected with status 2; they are
  never wrapped or truncated.

### Decided limits (audit E6; not changed, on purpose)

* **`revalue`: a market-vs-carrying difference above 10^12 cents
  ($10,000,000,000) is refused with status 2**, although the Holdings total may
  reach 10^17. A single posting is limited to `Max_Amount` = 10^12 everywhere in
  the engine (builders, validation, the per-transaction proofs), and one
  transaction has at most 16 postings, so a bigger revaluation cannot be one
  valid transaction; splitting it over several postings would only move the
  limit to 8 x 10^12 and not remove it. Raising `Max_Amount` would change every
  proof bound and every Rails column assumption. It is also hard to reach: one
  caliber's market value is itself limited to 10^12 (`market_value` status 2
  above that), so the carrying total is at most (number of calibers) x 10^12,
  and a one-tick difference above 10^12 needs the whole portfolio, at the
  holding limit in many calibers, to move by several percent in one tick (the
  mock walk moves +-2%, i.e. about 3 x 10^11 at the very most with 15 calibers).
  A user who somehow got there would get `revalue` status 2 on every tick: no
  revaluation is posted for that user, their books stay balanced and statements
  keep working at the stale carrying value. Callers must treat status 2 from
  `revalue` as a per-user error (log it, continue with the other users), never as
  a reason to abort a whole tick run. If this ever matters, the fix is to clamp
  the posted amount to 10^12 per transaction and converge over successive ticks;
  that changes the meaning of `Revaluation.amount` and was not done.
* **`cost_basis` weighted-average basis above 10^17 fails the whole report**
  (status 2) rather than being clamped: wrong money is worse than an error. It
  is unreachable with engine-built trades: a caliber holds at most 10^9 rounds
  and a trade's `value` comes from `quote_buy` (<= qty * 10^7 / 100 cents), so
  one caliber's basis is at most 10^9 * 10^5 = 10^14 cents, three orders below
  the limit. Only hand-supplied `value`s (up to 10^12 per trade) can reach it.
