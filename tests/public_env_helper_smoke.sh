#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
FIXTURE_SERVER_PID=""
trap '[[ -z "${FIXTURE_SERVER_PID:-}" ]] || kill "$FIXTURE_SERVER_PID" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"' EXIT

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

cat > "$TMP_DIR/taira_preflight_fixture.py" <<'PY'
#!/usr/bin/env python3
import json
import socketserver
import sys
from http.server import BaseHTTPRequestHandler


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/v1/explorer/blocks/1":
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "hash": "fixture-block-1",
                "height": 1,
            }).encode())
            return

        if self.path == "/status/blocks":
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(b"42")
            return

        if self.path == "/v1/accounts/faucet/puzzle":
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"algorithm":"fixture"}')
            return

        if self.path == "/v1/mcp":
            self.send_response(404)
            self.end_headers()
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *_args):
        pass


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    port_path = sys.argv[1]
    with open(port_path, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY

fixture_port_file="$TMP_DIR/taira_preflight.port"
python3 "$TMP_DIR/taira_preflight_fixture.py" "$fixture_port_file" &
FIXTURE_SERVER_PID="$!"
for _ in {1..50}; do
  [[ -s "$fixture_port_file" ]] && break
  sleep 0.1
done
[[ -s "$fixture_port_file" ]]

fixture_root="http://127.0.0.1:$(cat "$fixture_port_file")"
missing_cfg="$TMP_DIR/missing-taira.client.toml"
preflight_output="$TMP_DIR/taira_preflight.out"
preflight_status=0
(
  unset SORASWAP_PUBLIC_ENV
  export SORASWAP_TORII_URL="$fixture_root"
  export SORASWAP_CLIENT_CONFIG="$missing_cfg"
  export SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS=2
  export SORASWAP_TAIRA_PREFLIGHT_REPORT_DIR="$TMP_DIR/preflight-reports"
  "$ROOT/scripts/taira_preflight.sh"
) >"$preflight_output" 2>&1 || preflight_status="$?"
[[ "$preflight_status" != "0" ]]
rg -q "taira preflight: blocked" "$preflight_output"
rg -q "native Torii MCP is not enabled" "$preflight_output"
rg -q "next setup:" "$preflight_output"

preflight_report="$TMP_DIR/preflight-reports/preflight.latest.json"
[[ -s "$preflight_report" ]]
jq -e \
  --arg fixture_root "$fixture_root" \
  '.status == "blocked"
    and (.endpoint.torii_root == $fixture_root)
    and (.endpoint.mcp_http_status == "404")
    and (.blockers | any(contains("native Torii MCP is not enabled")))
    and (.endpoint.faucet_puzzle_http_status == "200")
    and (.endpoint.current_block_height == 42)
    and (.chain.fingerprint_available == true)
    and (.chain.fingerprint.block_1_hash == "fixture-block-1")
    and (.config.exists == false)' \
  "$preflight_report" >/dev/null

kill "$FIXTURE_SERVER_PID" >/dev/null 2>&1 || true
wait "$FIXTURE_SERVER_PID" 2>/dev/null || true
FIXTURE_SERVER_PID=""

unreachable_output="$TMP_DIR/taira_preflight_unreachable.out"
unreachable_status=0
(
  unset SORASWAP_PUBLIC_ENV
  export SORASWAP_TORII_URL="$fixture_root"
  export SORASWAP_CLIENT_CONFIG="$missing_cfg"
  export SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS=1
  export SORASWAP_TAIRA_PREFLIGHT_REPORT_DIR="$TMP_DIR/preflight-unreachable-reports"
  "$ROOT/scripts/taira_preflight.sh"
) >"$unreachable_output" 2>&1 || unreachable_status="$?"
[[ "$unreachable_status" != "0" ]]
rg -q "could not reach native Torii MCP" "$unreachable_output"
! rg -q "000000" "$unreachable_output"

unreachable_report="$TMP_DIR/preflight-unreachable-reports/preflight.latest.json"
[[ -s "$unreachable_report" ]]
jq -e \
  --arg fixture_root "$fixture_root" \
  '.status == "blocked"
    and (.endpoint.torii_root == $fixture_root)
    and (.endpoint.mcp_http_status == "000")
    and (.blockers | any(contains("could not reach native Torii MCP")))' \
  "$unreachable_report" >/dev/null
! rg -q "000000" "$unreachable_report"

echo "public env helper smoke ok"
