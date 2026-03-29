#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  "$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT

"$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
"$ROOT/scripts/local_up.sh"
"$ROOT/scripts/deploy_local.sh"
"$ROOT/scripts/smoke_local.sh"
