#!/usr/bin/env bash
# Rebuilds the Sunwai database from scratch (drops and reloads everything).
# Usage:  ./scripts/reset_db.sh                 -> local database "sunwai"
#         DATABASE_URL="postgres://..." ./scripts/reset_db.sh   -> any database (e.g. Neon)
set -euo pipefail
cd "$(dirname "$0")/../database"

if [ -z "${DATABASE_URL:-}" ]; then
  createdb sunwai 2>/dev/null || true
  DATABASE_URL="sunwai"
fi

echo "Building the Sunwai database..."
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f run_all.sql
echo
psql "$DATABASE_URL" -c "SELECT * FROM sunwai.v_dashboard_summary;"
echo "Database ready."
