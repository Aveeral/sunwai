#!/usr/bin/env bash
# Start the website on http://localhost:5173 (the backend must be running too).
set -euo pipefail
cd "$(dirname "$0")/../frontend"
exec npm run dev
