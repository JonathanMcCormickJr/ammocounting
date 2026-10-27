#!/usr/bin/env bash
# Build, then run the app (Rails server). Extra args go to `rails server`.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh
bin/rails db:prepare
exec bin/rails server "$@"
