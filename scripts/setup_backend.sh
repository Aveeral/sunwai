#!/usr/bin/env bash
# One-time: create a Python virtual environment and install the backend's packages.
set -euo pipefail
cd "$(dirname "$0")/../backend"
PY=${PYTHON:-python3}
if ! $PY -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  echo "Python 3.10 or newer is needed (you have $($PY --version))."
  echo "Install it from https://www.python.org/downloads/ and run this again,"
  echo "or run:  PYTHON=python3.12 bash scripts/setup_backend.sh"
  exit 1
fi
$PY -m venv .venv
.venv/bin/pip install --upgrade pip -q
.venv/bin/pip install -r requirements.txt -q
echo "Backend ready. Start it with:  bash scripts/run_backend.sh"
