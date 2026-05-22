#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_IROHA_ROOT="$TMP_DIR/iroha"
mkdir -p "$FAKE_IROHA_ROOT/target/debug"

cat > "$FAKE_IROHA_ROOT/target/debug/kagami" <<'EOF'
#!/usr/bin/env python3
import sys

if len(sys.argv) > 1 and sys.argv[1] == "keys":
    print("ed0120DEADBEEF")
    raise SystemExit(0)

raise SystemExit(1)
EOF

cat > "$FAKE_IROHA_ROOT/target/debug/iroha" <<'EOF'
#!/bin/sh
network_prefix=""
last=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --network-prefix)
      network_prefix="$2"
      shift 2
      ;;
    *)
      last="$1"
      shift
      ;;
  esac
done
printf 'acct:%s:%s\n' "$network_prefix" "$last"
EOF

chmod +x "$FAKE_IROHA_ROOT/target/debug/kagami" "$FAKE_IROHA_ROOT/target/debug/iroha"

export SORASWAP_IROHA_ROOT="$FAKE_IROHA_ROOT"
export SORASWAP_SKIP_IROHA_CLI_BUILD=1

source "$ROOT/scripts/common.sh"

production_cfg="$TMP_DIR/production.client.toml"
cat > "$production_cfg" <<'EOF'
chain = "wrong-production-chain"
torii_url = "https://production.example.invalid/"
EOF

export SORASWAP_PUBLIC_ENV=production
export SORASWAP_PRODUCTION_CHAIN_ID="prod-chain-id"
export SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT="369"
export SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID="prod-fee-id"
export SORASWAP_PRODUCTION_FEE_ASSET_LABEL="Prod Fee"

[[ "$(config_chain_id_from_config "$production_cfg")" == "prod-chain-id" ]]
[[ "$(network_prefix_for_config "$production_cfg")" == "369" ]]
[[ "$(fee_asset_definition_id_for_config "$production_cfg")" == "prod-fee-id" ]]
[[ "$(fee_asset_label_for_config "$production_cfg")" == "Prod Fee" ]]
[[ "$(gas_metadata_asset_id_for_config "$production_cfg")" == "Prod Fee" ]]

export SORASWAP_TESTNET_RUN_SUFFIX="testnet-leak"
export SORASWAP_TESTNET_BRIDGE_ROUTE="testnet_route_leak"
export SORASWAP_TESTNET_XOR_TOPUP_MAX_ATTEMPTS="99"
export SORASWAP_PUBLIC_RUN_SUFFIX="public-shared"
export SORASWAP_PUBLIC_BRIDGE_ROUTE="public_route"
export SORASWAP_PUBLIC_XOR_TOPUP_MAX_ATTEMPTS="7"

public_env_upper="${(U)SORASWAP_PUBLIC_ENV}"
run_suffix_var="SORASWAP_${public_env_upper}_RUN_SUFFIX"
bridge_route_var="SORASWAP_${public_env_upper}_BRIDGE_ROUTE"
max_attempts_var="SORASWAP_${public_env_upper}_XOR_TOPUP_MAX_ATTEMPTS"

[[ "${(P)run_suffix_var:-${SORASWAP_PUBLIC_RUN_SUFFIX:-$(utc_timestamp)}}" == "public-shared" ]]
[[ "${(P)bridge_route_var:-${SORASWAP_PUBLIC_BRIDGE_ROUTE:-${SORASWAP_BRIDGE_ROUTE:-eth_sora_usdt}}}" == "public_route" ]]
[[ "${(P)max_attempts_var:-${SORASWAP_PUBLIC_XOR_TOPUP_MAX_ATTEMPTS:-5}}" == "7" ]]

configure_cli_account_chain_discriminant "$production_cfg"
[[ "${CHAIN:-}" == "prod-chain-id" ]]
[[ "${ACCOUNT_CHAIN_DISCRIMINANT:-}" == "369" ]]
[[ "${IROHA_ACCOUNT_CHAIN_DISCRIMINANT:-}" == "369" ]]

contract_literal="tairac1qyqqqqqqqqqqqqrcew9a497j0j5glh9q0xcgzq4hypfyrqctpk8nc"
production_subject="$(contract_subject_account_for_literal "$production_cfg" "$contract_literal")"
[[ "$production_subject" == "acct:369:ed0120DEADBEEF" ]]

unset SORASWAP_PUBLIC_ENV SORASWAP_PRODUCTION_CHAIN_ID SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT
unset SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID SORASWAP_PRODUCTION_FEE_ASSET_LABEL
unset SORASWAP_TESTNET_RUN_SUFFIX SORASWAP_TESTNET_BRIDGE_ROUTE SORASWAP_TESTNET_XOR_TOPUP_MAX_ATTEMPTS
unset SORASWAP_PUBLIC_RUN_SUFFIX SORASWAP_PUBLIC_BRIDGE_ROUTE SORASWAP_PUBLIC_XOR_TOPUP_MAX_ATTEMPTS
unset CHAIN ACCOUNT_CHAIN_DISCRIMINANT IROHA_ACCOUNT_CHAIN_DISCRIMINANT

base_subject="$(contract_subject_account_for_literal "$production_cfg" "$contract_literal")"
[[ "$base_subject" == "acct:753:ed0120DEADBEEF" ]]
[[ "$production_subject" != "$base_subject" ]]

taira_cfg="$TMP_DIR/taira.client.toml"
cat > "$taira_cfg" <<'EOF'
chain = "wrong-testnet-chain"
torii_url = "https://direct-testnet-node.example.invalid/"
EOF

export SORASWAP_PUBLIC_ENV=testnet
[[ "$(config_chain_id_from_config "$taira_cfg")" == "$SORASWAP_TESTNET_CHAIN_ID" ]]
[[ "$(network_prefix_for_config "$taira_cfg")" == "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT" ]]
[[ "$(fee_asset_definition_id_for_config "$taira_cfg")" == "$SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID" ]]
[[ "$(fee_asset_label_for_config "$taira_cfg")" == "$SORASWAP_TESTNET_FEE_ASSET_LABEL" ]]
[[ "$(gas_metadata_asset_id_for_config "$taira_cfg")" == "$SORASWAP_TESTNET_FEE_ASSET_LABEL" ]]
unset SORASWAP_PUBLIC_ENV

current_fingerprint='{"torii_url":"https://node-a.example.invalid","chain":"same-chain","block_1_hash":"same-block-1"}'
same_chain_different_url_snapshot="$TMP_DIR/chain.same.json"
cat > "$same_chain_different_url_snapshot" <<'EOF'
{"generated_at":"20260414T000000Z","torii_url":"https://node-b.example.invalid","chain":"same-chain","block_1_hash":"same-block-1"}
EOF
chain_snapshot_matches_json "$same_chain_different_url_snapshot" "$current_fingerprint"

different_block_snapshot="$TMP_DIR/chain.different.json"
cat > "$different_block_snapshot" <<'EOF'
{"generated_at":"20260414T000000Z","torii_url":"https://node-b.example.invalid","chain":"same-chain","block_1_hash":"different-block-1"}
EOF
! chain_snapshot_matches_json "$different_block_snapshot" "$current_fingerprint"

deploy_record_same_chain="$TMP_DIR/deploy.same.json"
cat > "$deploy_record_same_chain" <<'EOF'
{"chain_fingerprint":{"torii_url":"https://node-b.example.invalid","chain":"same-chain","block_1_hash":"same-block-1"}}
EOF
deployment_record_matches_current_chain "$deploy_record_same_chain" "$current_fingerprint"

probe_same_chain="$TMP_DIR/probe.same.json"
cat > "$probe_same_chain" <<'EOF'
{"chain_fingerprint":{"torii_url":"https://node-b.example.invalid","chain":"same-chain","block_1_hash":"same-block-1"}}
EOF
nested_call_probe_matches_current_chain "$probe_same_chain" "$current_fingerprint"

echo "public env helper smoke ok"
