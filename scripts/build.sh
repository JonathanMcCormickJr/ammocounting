#!/usr/bin/env bash
# Build everything: Rails dependencies + ledger_core (SPARK Ada).
set -euo pipefail
cd "$(dirname "$0")/.."

bundle install
(cd ledger_core && alr build)
# Shared library for Rails (ffi). Default path: ledger_core/lib/libLedger_Core.so
# (override with LEDGER_CORE_LIB).
(cd ledger_core && LEDGER_CORE_LIBRARY_TYPE=relocatable alr build --validation)
