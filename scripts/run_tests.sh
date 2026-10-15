#!/usr/bin/env bash
# Runs every SQL test. Nothing is changed (each test rolls back).
set -uo pipefail
cd "$(dirname "$0")/../database"
DB="${DATABASE_URL:-sunwai}"
OUT=$(psql "$DB" -q -f run_tests.sql 2>&1)
echo "$OUT" | grep -E "^---|PASS|FAIL|ERROR" | sed -E 's/^psql:[^ ]+ //; s/^(NOTICE|ERROR): +//'
PASS=$(echo "$OUT" | grep -c "PASS")
FAIL=$(echo "$OUT" | grep -cE "FAIL|ERROR")
echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
