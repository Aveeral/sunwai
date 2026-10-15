#!/usr/bin/env bash
# Reset the database, run the backend tests (offline classifier, no OpenAI cost),
# then reset again so the demo data is clean.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/reset_db.sh" > /dev/null
cd "$ROOT/backend"
.venv/bin/python -m pytest -q tests "$@" || status=$?
bash "$ROOT/scripts/reset_db.sh" > /dev/null
exit ${status:-0}
