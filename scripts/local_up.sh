#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

localnet_dir="$DEFAULT_LOCALNET_DIR"
peer_pid_file="$localnet_dir/peer0.pid"
base_api_port="${SORASWAP_LOCALNET_BASE_API_PORT:-8080}"
base_p2p_port="${SORASWAP_LOCALNET_BASE_P2P_PORT:-1337}"
consensus_mode="${SORASWAP_LOCALNET_CONSENSUS_MODE:-npos}"
localnet_guest_stack_bytes="${SORASWAP_LOCALNET_GUEST_STACK_BYTES:-8388608}"
localnet_gas_to_stack_multiplier="${SORASWAP_LOCALNET_GAS_TO_STACK_MULTIPLIER:-8}"
localnet_memory_budget_profile="${SORASWAP_LOCALNET_MEMORY_BUDGET_PROFILE:-soraswap-dlmm}"
localnet_max_stack_bytes="${SORASWAP_LOCALNET_MAX_STACK_BYTES:-$localnet_guest_stack_bytes}"
localnet_commit_inflight_timeout_ms="${SORASWAP_LOCALNET_COMMIT_INFLIGHT_TIMEOUT_MS:-}"
localnet_block_time_ms="${SORASWAP_LOCALNET_BLOCK_TIME_MS:-}"
localnet_commit_time_ms="${SORASWAP_LOCALNET_COMMIT_TIME_MS:-}"

mkdir -p "$SORASWAP_ROOT/tmp"
ensure_localnet_tool_bins

if [[ -f "$peer_pid_file" ]]; then
  pid="$(cat "$peer_pid_file")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "local Nexus already appears to be running under pid $pid" >&2
    exit 1
  fi
fi

localnet_args=(
  --iroha-dir "$SORASWAP_IROHA_ROOT"
  --out-dir "$localnet_dir"
  --peers 1
  --build-line iroha3
  --consensus-mode "$consensus_mode"
  --base-api-port "$base_api_port"
  --base-p2p-port "$base_p2p_port"
  --bind-host 127.0.0.1
  --public-host 127.0.0.1
  --skip-asset-register
  --timeout 60
  --force
)

if [[ -n "$localnet_block_time_ms" ]]; then
  localnet_args+=(--block-time-ms "$localnet_block_time_ms")
fi
if [[ -n "$localnet_commit_time_ms" ]]; then
  localnet_args+=(--commit-time-ms "$localnet_commit_time_ms")
fi

IROHA_LOCALNET_GUEST_STACK_BYTES="$localnet_guest_stack_bytes" \
IROHA_LOCALNET_GAS_TO_STACK_MULTIPLIER="$localnet_gas_to_stack_multiplier" \
IROHA_LOCALNET_MEMORY_BUDGET_PROFILE="$localnet_memory_budget_profile" \
IROHA_LOCALNET_MAX_STACK_BYTES="$localnet_max_stack_bytes" \
IROHA_LOCALNET_COMMIT_INFLIGHT_TIMEOUT_MS="$localnet_commit_inflight_timeout_ms" \
IROHA_LOCALNET_EXTRA_GAS_ASSETS="${IROHA_LOCALNET_EXTRA_GAS_ASSETS:-$SORASWAP_LOCAL_FEE_ASSET_LABEL}" \
NORITO_SKIP_BINDINGS_SYNC=1 SKIP_TOOL_BUILD=true \
  "$SORASWAP_IROHA_ROOT/scripts/deploy_localnet.sh" "${localnet_args[@]}"

torii_url="$(torii_url_from_config "$DEFAULT_LOCAL_CLIENT")"

echo "started local Nexus using generated localnet in $localnet_dir"
echo "client config: $DEFAULT_LOCAL_CLIENT"
echo "torii url: $torii_url"
