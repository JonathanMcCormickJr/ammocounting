#!/usr/bin/env bash
# Run every mandatory check. Any failure fails the script (and CI).
# Same checks as bin/ci plus coverage enforcement and the Ada side.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Rails: style"
bin/rubocop
echo "== Rails: brakeman (mandatory)"
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
echo "== Rails: gem audit"
bin/bundler-audit
echo "== Rails: importmap audit"
bin/importmap audit
echo "== ledger_core: shared library for Ruby FFI (needed by the Rails tests)"
(cd ledger_core && LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --validation)
echo "== Rails: tests (100% line+branch coverage required)"
RAILS_ENV=test COVERAGE=1 bin/rails db:prepare test
echo "== ledger_core: build (validation profile, warnings are errors)"
(cd ledger_core && alr build --validation)
echo "== ledger_core: SPARK proof"
(cd ledger_core && alr exec -- gnatprove -P ledger_core.gpr --level=4 --warnings=error -j0)
echo "== ledger_core: unit tests"
(cd ledger_core/tests && alr build --validation && ./bin/tests)
echo "== ledger_core: shared library for Ruby FFI"
(cd ledger_core && LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --validation)
echo "== ledger_core: differential test against the pure-Ruby reference"
ruby ledger_core/tests/differential/diff_test.rb ledger_core/lib/libLedger_Core.so
echo "All checks passed."
