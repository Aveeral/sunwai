#!/usr/bin/env bash
# One-time: install the frontend's packages (needs Node.js 18 or newer).
set -euo pipefail
cd "$(dirname "$0")/../frontend"
if ! command -v node >/dev/null; then
  echo "Node.js is not installed. Get the LTS version from https://nodejs.org and run this again."
  exit 1
fi
npm install
echo "Frontend ready. Start it with:  bash scripts/run_frontend.sh"
