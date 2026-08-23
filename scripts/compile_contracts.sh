#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export SORASWAP_ROOT="$ROOT"
source "$SCRIPT_DIR/common.sh"

soraswap_require_contract_source_hygiene "$ROOT" "compile contracts failed" || exit 1

manifest="${SORASWAP_CONTRACTS_MANIFEST:-$ROOT/iroha.contracts.toml}"
if [[ "$manifest" != /* ]]; then
  manifest="$ROOT/$manifest"
fi
0="$SCRIPT_DIR/dev_iroha.sh"
source "$SCRIPT_DIR/dev_iroha.sh" build --manifest "$manifest" --profile "${SORASWAP_PROFILE:-local}" "$@"
