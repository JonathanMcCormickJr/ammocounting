# Project Standards

These are mandatory. CI enforces them; a red check blocks merge.

## Scripts

| Script        | Purpose                                                        |
|---------------|----------------------------------------------------------------|
| `script/build`| Install gems and build `ledger_core` (`alr build`)             |
| `script/run`  | Build, prepare the DB, start the Rails server                  |
| `script/test` | Run **every** mandatory check below; CI runs the same checks   |

If `script/test` passes locally, CI should pass.

## Mandatory checks

**Rails**

1. `bin/brakeman --exit-on-warn --exit-on-error` — zero warnings. Never ignore a
   warning without a justified, reviewed entry in `config/brakeman.ignore`.
2. `bin/bundler-audit` — no known-vulnerable gems.
3. `bin/importmap audit` — no known-vulnerable JS packages.
4. `bin/rubocop` — style clean.
5. `bin/rails test` with `COVERAGE=1` — **100% line and branch coverage**.

**ledger_core (SPARK Ada)**

1. `alr build` with no warnings.
2. `gnatprove --level=2` with no unproved checks and no unjustified `pragma
   Annotate`/`Assume`. Proof failures fail the build.
3. Unit tests for every subprogram (see below).

## Every function has a unit test

- Every method/function/procedure, public or private-with-logic, has at least one
  unit test that exercises it directly, including its error and boundary cases.
- Ruby: enforced mechanically by the 100% line + branch coverage gate. Coverage
  proves a line ran, not that it was checked, so tests must assert behavior.
- Ada: every subprogram has a test case in `ledger_core/tests/`. Proofs
  complement tests; they don't replace them. (Coverage gate for Ada: see TODO.md.)
- A bug fix starts with a failing test that reproduces it.

## Correctness rules

- Money is integer cents. No `Float`, no `BigDecimal` rounding, no Ruby-side
  money arithmetic; the ledger does it.
- Every ledger operation preserves debits = credits. Never write a posting
  outside the ledger engine.
- Users can access only their own data; every controller action is scoped to
  the current user and has a test proving another user is refused.

## Repository settings (not enforceable from code)

Configure on GitHub: protect `main`, require pull requests, require all CI jobs to
pass, and disallow bypass. These make the checks above truly mandatory.
