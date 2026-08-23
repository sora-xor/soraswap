#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
python_bin="${commands[python3]:-python3}"

exec "$python_bin" "$ROOT/scripts/verify_production_cutover_approval.py" --root "$ROOT" "$@"
