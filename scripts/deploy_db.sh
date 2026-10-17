#!/usr/bin/env bash
# Load (or reload) the Sunwai database on Neon.
#
# Usage:  bash scripts/deploy_db.sh "postgresql://neondb_owner:...@ep-xxx.neon.tech/neondb?sslmode=require"
#
# Builds everything (schema, data, roles, security), gives the sunwai_app login
# a long random password, and prints the DATABASE_URL to paste into Render.
# Running it again resets the demo data (handy right before the viva) and
# creates a new password, so update Render afterwards.
set -euo pipefail
OWNER_URL="${1:-}"
if [ -z "$OWNER_URL" ]; then
  echo "Give the Neon connection string (the owner one) in quotes:"
  echo '  bash scripts/deploy_db.sh "postgresql://neondb_owner:...@...neon.tech/neondb?sslmode=require"'
  exit 1
fi
cd "$(dirname "$0")/../database"

APP_PASSWORD="$(openssl rand -hex 24)"
echo "Building the Sunwai database on Neon (about a minute)..."
psql "$OWNER_URL" -q -v ON_ERROR_STOP=1 -v app_password="$APP_PASSWORD" -f run_all.sql > /dev/null
psql "$OWNER_URL" -c "SELECT * FROM sunwai.v_dashboard_summary;"

# same address, but logging in as sunwai_app instead of the owner
APP_URL="$(python3 - "$OWNER_URL" "$APP_PASSWORD" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit
u = urlsplit(sys.argv[1])
host = u.hostname + (f":{u.port}" if u.port else "")
print(urlunsplit((u.scheme, f"sunwai_app:{sys.argv[2]}@{host}", u.path, u.query, "")))
PY
)"
echo
echo "Done. Put this in Render as DATABASE_URL (keep it secret):"
echo
echo "  $APP_URL"
