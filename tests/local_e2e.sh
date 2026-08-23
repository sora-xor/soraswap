#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  zsh "$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT

zsh "$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
zsh "$ROOT/scripts/local_up.sh"
zsh "$ROOT/scripts/deploy_local.sh"
zsh "$ROOT/scripts/smoke_local.sh"
