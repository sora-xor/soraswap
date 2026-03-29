#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export SORASWAP_BOOTSTRAP_SCOPE="${SORASWAP_BOOTSTRAP_SCOPE:-foundation}"
export SORASWAP_SMOKE_SCOPE="${SORASWAP_SMOKE_SCOPE:-foundation}"

"$ROOT/tests/isolated_e2e.sh"
