#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export SORASWAP_LOCALNET_DIR="${SORASWAP_LOCALNET_DIR:-$ROOT/tmp/iroha-localnet-verify}"
export SORASWAP_LOCALNET_BASE_API_PORT="${SORASWAP_LOCALNET_BASE_API_PORT:-18080}"
export SORASWAP_LOCALNET_BASE_P2P_PORT="${SORASWAP_LOCALNET_BASE_P2P_PORT:-11337}"
export SORASWAP_LOCALNET_CONSENSUS_MODE="${SORASWAP_LOCALNET_CONSENSUS_MODE:-permissioned}"
export SORASWAP_ASSERT_BOOTSTRAP_STATE="${SORASWAP_ASSERT_BOOTSTRAP_STATE:-1}"
export SORASWAP_RUN_TESTNET_SMOKE="${SORASWAP_RUN_TESTNET_SMOKE:-0}"
export SORASWAP_BOOTSTRAP_SCOPE="${SORASWAP_BOOTSTRAP_SCOPE:-full}"
export SORASWAP_SMOKE_SCOPE="${SORASWAP_SMOKE_SCOPE:-$SORASWAP_BOOTSTRAP_SCOPE}"
export SORASWAP_IROHA_CLI_BIN="${SORASWAP_IROHA_CLI_BIN:-$ROOT/../iroha/target/debug/iroha}"
export SORASWAP_SKIP_IROHA_CLI_BUILD="${SORASWAP_SKIP_IROHA_CLI_BUILD:-1}"

cleanup() {
  "$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
}

trap cleanup EXIT

"$ROOT/scripts/local_down.sh" >/dev/null 2>&1 || true
"$ROOT/scripts/local_up.sh"
"$ROOT/scripts/deploy_local.sh"
SORASWAP_CLIENT_CONFIG="$SORASWAP_LOCALNET_DIR/client.toml" \
  "$ROOT/scripts/smoke_local.sh"

if [[ "$SORASWAP_RUN_TESTNET_SMOKE" == "1" ]]; then
  SORASWAP_CLIENT_CONFIG="$SORASWAP_LOCALNET_DIR/client.toml" \
    "$ROOT/scripts/smoke_testnet.sh"
fi

if command -v rg >/dev/null 2>&1; then
  if rg -n "failed to canonicalize default gas asset id" "$SORASWAP_LOCALNET_DIR" -g '*.log' >/dev/null 2>&1; then
    echo "isolated local smoke failed: local peer log contains default gas asset canonicalization warnings" >&2
    rg -n "failed to canonicalize default gas asset id" "$SORASWAP_LOCALNET_DIR" -g '*.log' >&2 || true
    exit 1
  fi
fi
