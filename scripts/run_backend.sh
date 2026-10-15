#!/usr/bin/env bash
# Start the API on http://localhost:8000  (interactive docs: http://localhost:8000/docs)
set -euo pipefail
cd "$(dirname "$0")/../backend"
exec .venv/bin/uvicorn app.main:app --reload --port 8000
