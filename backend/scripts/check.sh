#!/usr/bin/env bash
# No dependency installation, services, model downloads or default development DB.
set -euo pipefail

case "${1:-}" in
  "") run_model=false ;;
  --model) run_model=true ;;
  *) echo "Usage: check.sh [--model]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  echo "Usage: check.sh [--model]" >&2
  exit 2
fi

backend_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check_python="${NAV_CHECK_PYTHON:-$backend_dir/.venv/bin/python}"
if [[ ! -x "$check_python" ]]; then
  echo "Pinned backend Python is unavailable; sync the locked environment first" >&2
  exit 2
fi
if [[ -z "${NAV_TEST_DB_URL:-}" ]]; then
  echo "NAV_TEST_DB_URL must identify a PostgreSQL database ending in _test" >&2
  exit 2
fi
if ! "$check_python" -c '
import os
from urllib.parse import unquote, urlsplit
try:
    url = urlsplit(os.environ["NAV_TEST_DB_URL"])
    name = unquote(url.path).removeprefix("/")
    valid = url.scheme in {"postgresql", "postgresql+psycopg"} and name.endswith("_test")
    valid = valid and "/" not in name and bool(url.hostname)
except ValueError:
    valid = False
raise SystemExit(0 if valid else 1)
'; then
  echo "NAV_TEST_DB_URL must identify a PostgreSQL database ending in _test" >&2
  exit 2
fi

cd -- "$backend_dir"
export NAV_ENV=test
export NAV_DB_URL="$NAV_TEST_DB_URL"
"$check_python" -m ruff format --check src tests
"$check_python" -m ruff check src tests
"$check_python" -m pytest tests/unit -q
"$check_python" -m pytest tests/integration -q
if "$run_model"; then
  "$check_python" -m pytest tests/model -m model -q
fi
