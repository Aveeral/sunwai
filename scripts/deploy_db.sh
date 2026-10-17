#!/usr/bin/env bash
# Load (or reset) the Sunwai database on Neon.
#
# First time:   bash scripts/deploy_db.sh "postgresql://neondb_owner:...neon.tech/neondb?sslmode=require"
# Every reset:  bash scripts/deploy_db.sh
#
# The first run remembers the Neon string and the app password in .deploy.env
# (never committed: it is in .gitignore). Later runs reuse both, so the
# DATABASE_URL on Render stays the same and never needs updating.
# Use --new-password to make a fresh app password (then update Render once).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/.deploy.env"

OWNER_URL=""; NEW_PW=0
for a in "$@"; do
  case "$a" in
    --new-password) NEW_PW=1 ;;
    *) OWNER_URL="$a" ;;
  esac
done

# shellcheck disable=SC1090
[ -f "$STATE" ] && source "$STATE"
OWNER_URL="${OWNER_URL:-${NEON_OWNER_URL:-}}"
if [ -z "$OWNER_URL" ]; then
  echo "First time: give the Neon connection string (the owner one) in quotes:"
  echo '  bash scripts/deploy_db.sh "postgresql://neondb_owner:...@...neon.tech/neondb?sslmode=require"'
  exit 1
fi
APP_PASSWORD="${APP_PASSWORD:-}"
if [ -z "$APP_PASSWORD" ] || [ "$NEW_PW" = 1 ]; then
  APP_PASSWORD="$(openssl rand -hex 24)"
  PW_CHANGED=1
else
  PW_CHANGED=0
fi
umask 077
printf 'NEON_OWNER_URL=%q\nAPP_PASSWORD=%q\n' "$OWNER_URL" "$APP_PASSWORD" > "$STATE"

# The build relies on session settings, so it uses a direct connection,
# not Neon's pooler ("-pooler" in the host name).
BUILD_URL="${OWNER_URL/-pooler./.}"

cd "$ROOT/database"
echo "Rebuilding the Sunwai database on Neon (about a minute)..."
psql "$BUILD_URL" -q -v ON_ERROR_STOP=1 -v app_password="$APP_PASSWORD" -f run_all.sql > /dev/null
psql "$BUILD_URL" -c "SELECT * FROM sunwai.v_dashboard_summary;"

APP_URL="$(python3 - "$OWNER_URL" "$APP_PASSWORD" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit
u = urlsplit(sys.argv[1])
host = u.hostname + (f":{u.port}" if u.port else "")
print(urlunsplit((u.scheme, f"sunwai_app:{sys.argv[2]}@{host}", u.path, u.query, "")))
PY
)"
echo
if [ "$PW_CHANGED" = 1 ]; then
  echo "Done. NEW app password: put this in Render as DATABASE_URL, then Save:"
  echo
  echo "  $APP_URL"
else
  echo "Done. Fresh demo data loaded. Render's DATABASE_URL is unchanged; nothing to update."
  echo "(If the site shows errors for a minute, Render -> Manual Deploy -> Restart service.)"
fi
