#!/bin/zsh
set -euo pipefail

SORASWAP_ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SORASWAP_IROHA_ROOT="${SORASWAP_IROHA_ROOT:-$(cd "$SORASWAP_ROOT/../iroha" && pwd)}"
SORASWAP_BASE_ASSET_ALIAS="${SORASWAP_BASE_ASSET_ALIAS:-xor#universal}"
SORASWAP_FEE_ASSET_ALIAS="${SORASWAP_FEE_ASSET_ALIAS:-$SORASWAP_BASE_ASSET_ALIAS}"
SORASWAP_XOR_ASSET_DEFINITION_ID="${SORASWAP_XOR_ASSET_DEFINITION_ID:-6qLb5RYJbzychndCXgFa9aZzjWyx}"
SORASWAP_TREASURY_ACCOUNT_DEFAULT="${SORASWAP_TREASURY_ACCOUNT_DEFAULT:-6cmzPVPX94geMqaWMCxbiapYWDHgqvTDmrJvsMZab7asaSfntxyMza6}"
DEFAULT_LOCALNET_DIR="${SORASWAP_LOCALNET_DIR:-$SORASWAP_ROOT/tmp/iroha-localnet}"
DEFAULT_LOCAL_CLIENT="$DEFAULT_LOCALNET_DIR/client.toml"
DEFAULT_TESTNET_CLIENT="$SORASWAP_ROOT/config/testnet/taira.client.toml"
SORASWAP_SNS_DOMAIN_SUFFIX_ID="${SORASWAP_SNS_DOMAIN_SUFFIX_ID:-4098}"
SORASWAP_SNS_PAYMENT_ASSET_ID="${SORASWAP_SNS_PAYMENT_ASSET_ID:-61CtjvNd9T3THAR65GsMVHr82Bjc}"
# The `/v1/contracts/call` wrapper expects an explicit positive gas limit.
# Keep the default aligned with the verified local smoke path and README docs;
# callers can still override this per-run for heavier scenarios.
SORASWAP_SMOKE_GAS_LIMIT="${SORASWAP_SMOKE_GAS_LIMIT:-100000}"
SORASWAP_TESTNET_CHAIN_DISCRIMINANT="${SORASWAP_TESTNET_CHAIN_DISCRIMINANT:-369}"
SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP="${SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP:-1048576}"
SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS="${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-45}"

utc_timestamp() {
  env TZ=UTC date '+%Y%m%dT%H%M%SZ'
}

json_equals() {
  local left_json="$1"
  local right_json="$2"
  jq -en --argjson left "$left_json" --argjson right "$right_json" '$left == $right' >/dev/null
}

numeric_gt_zero() {
  local value="${1:-0}"
  /usr/bin/python3 - "$value" <<'PY'
from decimal import Decimal, InvalidOperation
import sys

raw = sys.argv[1].strip() or "0"
try:
    value = Decimal(raw)
except InvalidOperation:
    value = Decimal("0")
sys.exit(0 if value > 0 else 1)
PY
}

path_is_newer_than() {
  local target="$1"
  shift
  local candidate

  if [[ ! -e "$target" ]]; then
    return 0
  fi

  for candidate in "$@"; do
    if [[ ! -e "$candidate" ]]; then
      continue
    fi
    if [[ -d "$candidate" ]]; then
      if find "$candidate" -type f -newer "$target" -print -quit | grep -q .; then
        return 0
      fi
      continue
    fi
    if [[ "$candidate" -nt "$target" ]]; then
      return 0
    fi
  done

  return 1
}

ensure_iroha_cli_bin() {
  local bin="$SORASWAP_IROHA_ROOT/target/debug/iroha"
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    if [[ -x "$bin" ]]; then
      echo "cli tool: reusing existing iroha binary" >&2
      return 0
    fi
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_crypto"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build --bin iroha
    )
  fi
}

ensure_split_contract_deploy_bin() {
  local bin="$SORASWAP_IROHA_ROOT/target/debug/split_contract_deploy"
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    if [[ -x "$bin" ]]; then
      echo "cli tool: reusing existing split_contract_deploy binary" >&2
      return 0
    fi
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_crypto"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_cli --bin split_contract_deploy
    )
  fi
}

split_contract_deploy_cli() {
  ensure_split_contract_deploy_bin
  "$SORASWAP_IROHA_ROOT/target/debug/split_contract_deploy" "$@"
}

ensure_localnet_tool_bins() {
  local irohad_bin="$SORASWAP_IROHA_ROOT/target/debug/irohad"
  local iroha_bin="$SORASWAP_IROHA_ROOT/target/debug/iroha"
  local kagami_bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"

  if [[ "${SORASWAP_SKIP_LOCALNET_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$irohad_bin" && -x "$iroha_bin" && -x "$kagami_bin" ]]; then
      echo "localnet tools: reusing existing iroha/kagami binaries" >&2
      return 0
    fi
  fi

  if [[ ! -x "$irohad_bin" || ! -x "$iroha_bin" || ! -x "$kagami_bin" ]] || \
    path_is_newer_than "$irohad_bin" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/irohad" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_core" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_torii" || \
    path_is_newer_than "$iroha_bin" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_crypto" || \
    path_is_newer_than "$kagami_bin" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_kagami" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_swarm" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_test_samples"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build --bin kagami --bin irohad --bin iroha
    )
  fi
}

ensure_irohad_bin() {
  local bin="$SORASWAP_IROHA_ROOT/target/debug/irohad"
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/irohad" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_core" \
    "$SORASWAP_IROHA_ROOT/crates/ivm" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_torii"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build --bin irohad
    )
  fi
}

ensure_koto_compile_bin() {
  local compile_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_compile"
  if [[ "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$compile_bin" ]]; then
      echo "koto tool: reusing existing koto_compile binary" >&2
      return 0
    fi
  fi
  if [[ ! -x "$compile_bin" ]] || \
    path_is_newer_than "$compile_bin" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p ivm --bin koto_compile
    )
  fi
}

ensure_koto_lint_bin() {
  local lint_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_lint"
  if [[ "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$lint_bin" ]]; then
      echo "koto tool: reusing existing koto_lint binary" >&2
      return 0
    fi
  fi
  if [[ ! -x "$lint_bin" ]] || \
    path_is_newer_than "$lint_bin" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p ivm --bin koto_lint
    )
  fi
}

ensure_koto_tools_bins() {
  ensure_koto_compile_bin
  ensure_koto_lint_bin
}

iroha_cli() {
  ensure_iroha_cli_bin
  "$SORASWAP_IROHA_ROOT/target/debug/iroha" "$@"
}

iroha_cli_json() {
  iroha_cli --machine --output-format json "$@"
}

normalize_hash_literal() {
  local value="$1"
  value="${value#hash:}"
  value="${value%%#*}"
  echo "${value:l}"
}

manifest_code_hash_hex() {
  local manifest_path="$1"
  normalize_hash_literal "$(jq -r '.code_hash' "$manifest_path")"
}

manifest_abi_hash_hex() {
  local manifest_path="$1"
  normalize_hash_literal "$(jq -r '.abi_hash' "$manifest_path")"
}

decode_state_entry_int_b64() {
  local value_b64="$1"
  local decoded

  if [[ -z "$value_b64" || "$value_b64" == "null" ]]; then
    echo "missing state entry value_b64" >&2
    return 1
  fi

  decoded="$(
    printf '%s' "$value_b64" \
      | base64 -d 2>/dev/null \
      | tail -c 40 \
      | head -c 8 \
      | od -An -v -t u8 \
      | tr -d '[:space:]'
  )"

  if [[ -z "$decoded" ]]; then
    echo "failed to decode Norito integer payload from state entry" >&2
    return 1
  fi

  echo "$decoded"
}

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "missing required file: $file_path" >&2
    exit 1
  fi
}

client_config_or_default() {
  local mode="$1"
  if [[ -n "${SORASWAP_CLIENT_CONFIG:-}" ]]; then
    echo "$SORASWAP_CLIENT_CONFIG"
    return
  fi
  if [[ "$mode" == "local" ]]; then
    echo "$DEFAULT_LOCAL_CLIENT"
  else
    echo "$DEFAULT_TESTNET_CLIENT"
  fi
}

torii_url_from_config() {
  local config="$1"
  if [[ -n "${SORASWAP_TORII_URL:-}" ]]; then
    echo "$SORASWAP_TORII_URL"
    return
  fi
  awk -F '"' '/^torii_url = / {print $2; exit}' "$config"
}

torii_base_from_config() {
  local config="$1"
  local torii_url
  torii_url="$(torii_url_from_config "$config")"
  echo "${torii_url%/}"
}

uri_encode() {
  local value="$1"
  jq -rn --arg value "$value" '$value|@uri'
}

deployments_dir_for_env() {
  local env="$1"
  echo "$SORASWAP_ROOT/deployments/${env}"
}

chain_snapshot_latest_path_for_env() {
  local env="$1"
  echo "$(deployments_dir_for_env "$env")/chain.latest.json"
}

current_chain_fingerprint_json() {
  local config="$1"
  local torii_base chain_id block_hash

  torii_base="$(torii_base_from_config "$config")"
  chain_id="$(config_chain_id_from_config "$config")"
  block_hash="$(curl -sS "$torii_base/v1/explorer/blocks/1" | jq -er '.hash')"
  jq -cn \
    --arg torii_url "$torii_base" \
    --arg chain "$chain_id" \
    --arg block_1_hash "$block_hash" \
    '{
      torii_url: $torii_url,
      chain: $chain,
      block_1_hash: $block_1_hash
    }'
}

chain_snapshot_matches_json() {
  local snapshot_path="$1"
  local fingerprint_json="$2"

  if [[ ! -f "$snapshot_path" ]]; then
    return 1
  fi

  jq -e \
    --argjson current "$fingerprint_json" \
    '.torii_url == $current.torii_url and .chain == $current.chain and .block_1_hash == $current.block_1_hash' \
    "$snapshot_path" >/dev/null
}

write_chain_fingerprint_snapshot() {
  local env="$1"
  local config="$2"
  local report_dir latest timestamp timestamped fingerprint_json snapshot_json

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(chain_snapshot_latest_path_for_env "$env")"
  timestamp="$(utc_timestamp)"
  timestamped="$report_dir/chain.${timestamp}.json"
  mkdir -p "$report_dir"

  if [[ -z "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]]; then
    SORASWAP_CHAIN_FINGERPRINT_JSON="$(current_chain_fingerprint_json "$config")"
  fi
  fingerprint_json="$SORASWAP_CHAIN_FINGERPRINT_JSON"
  snapshot_json="$(jq -cn \
    --arg generated_at "$timestamp" \
    --argjson fingerprint "$fingerprint_json" \
    '$fingerprint + {generated_at: $generated_at}')"
  printf '%s\n' "$snapshot_json" > "$latest"
  printf '%s\n' "$snapshot_json" > "$timestamped"
}

archive_deployment_evidence_for_chain_reset() {
  local env="$1"
  local config="$2"
  local report_dir latest timestamp archive_dir block_hash entry_path base

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(chain_snapshot_latest_path_for_env "$env")"
  if [[ ! -f "$latest" ]]; then
    return 0
  fi

  if [[ -z "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]]; then
    SORASWAP_CHAIN_FINGERPRINT_JSON="$(current_chain_fingerprint_json "$config")"
  fi
  if chain_snapshot_matches_json "$latest" "$SORASWAP_CHAIN_FINGERPRINT_JSON"; then
    return 0
  fi

  timestamp="$(utc_timestamp)"
  block_hash="$(jq -r '.block_1_hash // "unknown-block-1"' <<<"$SORASWAP_CHAIN_FINGERPRINT_JSON")"
  archive_dir="$report_dir/archive/${timestamp}-${block_hash}"
  mkdir -p "$archive_dir"
  for entry_path in "$report_dir"/*; do
    if [[ ! -e "$entry_path" ]]; then
      continue
    fi
    base="$(basename "$entry_path")"
    if [[ "$base" == "archive" ]]; then
      continue
    fi
    mv "$entry_path" "$archive_dir/$base"
  done
  echo "archived stale deployment evidence to $archive_dir" >&2
}

prepare_env_chain_state() {
  local env="$1"
  local config="$2"

  SORASWAP_CHAIN_FINGERPRINT_JSON="$(current_chain_fingerprint_json "$config")"
  if [[ "$env" == "testnet" ]]; then
    archive_deployment_evidence_for_chain_reset "$env" "$config"
  fi
  write_chain_fingerprint_snapshot "$env" "$config"
}

config_chain_id_from_config() {
  local config="$1"
  awk -F '"' '/^chain = / {print $2; exit}' "$config"
}

account_private_key_from_config() {
  local config="$1"
  awk -F '"' '/^private_key = / {print $2; exit}' "$config"
}

chain_discriminant_for_env() {
  local env="${1:-testnet}"
  case "$env" in
    testnet)
      echo "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT"
      ;;
    *)
      echo "${SORASWAP_CHAIN_DISCRIMINANT:-753}"
      ;;
  esac
}

deploy_report_latest_path_for_env() {
  local env="$1"
  echo "$(deployments_dir_for_env "$env")/deploy.latest.json"
}

deploy_report_update() {
  local env="$1"
  shift
  local latest timestamped tmp filter
  local -a jq_args

  latest="$(deploy_report_latest_path_for_env "$env")"
  timestamped="${SORASWAP_DEPLOY_REPORT_TIMESTAMPED:-}"
  tmp="$(mktemp)"
  jq_args=("$@")
  filter="${jq_args[-1]}"
  jq_args=("${jq_args[@]:0:${#jq_args[@]}-1}")
  jq "${jq_args[@]}" "$filter" "$latest" > "$tmp"
  mv "$tmp" "$latest"
  if [[ -n "$timestamped" ]]; then
    cp "$latest" "$timestamped"
  fi
}

deploy_report_init() {
  local env="$1"
  local config="$2"
  local report_dir latest timestamped timestamp

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(deploy_report_latest_path_for_env "$env")"
  timestamp="$(utc_timestamp)"
  timestamped="$report_dir/deploy.${timestamp}.json"
  mkdir -p "$report_dir"
  SORASWAP_DEPLOY_REPORT_TIMESTAMPED="$timestamped"
  jq -n \
    --arg generated_at "$timestamp" \
    --arg authority "${SORASWAP_AUTHORITY:-}" \
    --arg client_config "$config" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
    '{
      generated_at: $generated_at,
      authority: $authority,
      client_config: $client_config,
      torii_url: $torii_url,
      chain_fingerprint: $chain_fingerprint,
      status: "running",
      phases: {},
      contracts: {}
    }' > "$latest"
  cp "$latest" "$timestamped"
}

deploy_report_set_phase() {
  local env="$1"
  local phase="$2"
  local phase_status="$3"
  local detail_json="${4:-null}"

  deploy_report_update "$env" \
    --arg phase "$phase" \
    --arg status "$phase_status" \
    --argjson detail "$detail_json" \
    '.phases[$phase] = {
      status: $status,
      detail: (if $detail == null then null else $detail end),
      updated_at: now | floor
    }'
}

deploy_report_set_contract() {
  local env="$1"
  local contract_key="$2"
  local contract_status="$3"
  local detail_json="${4:-null}"

  deploy_report_update "$env" \
    --arg contract_key "$contract_key" \
    --arg status "$contract_status" \
    --argjson detail "$detail_json" \
    '.contracts[$contract_key] = {
      status: $status,
      detail: (if $detail == null then null else $detail end),
      updated_at: now | floor
    }'
}

deploy_report_finish() {
  local env="$1"
  local report_status="$2"

  deploy_report_update "$env" \
    --arg status "$report_status" \
    '.status = $status | .finished_at = (now | floor)'
}

account_public_key_from_config() {
  local config="$1"
  awk -F '"' '/^public_key *= / {print $2; exit}' "$config"
}

authority_from_config() {
  local config="$1"
  local public_key torii_base network_prefix
  public_key="$(account_public_key_from_config "$config")"
  if [[ -z "$public_key" ]]; then
    return 1
  fi

  torii_base="$(torii_base_from_config "$config")"
  network_prefix="${SORASWAP_ADDRESS_NETWORK_PREFIX:-753}"
  if [[ "$torii_base" == "https://taira.sora.org" ]]; then
    network_prefix="${SORASWAP_TESTNET_CHAIN_DISCRIMINANT}"
  fi

  iroha_cli --output-format text tools address convert \
    --network-prefix "$network_prefix" \
    "$public_key" 2>/dev/null \
    | tail -n 1 \
    | tr -d '\r\n'
}

ensure_authority() {
  local config="$1"
  if [[ -n "${SORASWAP_AUTHORITY:-}" ]]; then
    return 0
  fi

  if SORASWAP_AUTHORITY="$(authority_from_config "$config")"; [[ -n "$SORASWAP_AUTHORITY" ]]; then
    export SORASWAP_AUTHORITY
    return 0
  fi

  cat >&2 <<'EOF'
SORASWAP_AUTHORITY is not set and could not be derived from the client config.
Set it to the canonical I105 account id used for deploy and mint flows. Example:
  export SORASWAP_AUTHORITY='i105...'
EOF
  exit 1
}

treasury_account_for_mode() {
  local mode="$1"
  if [[ -n "${SORASWAP_TREASURY_ACCOUNT:-}" ]]; then
    echo "$SORASWAP_TREASURY_ACCOUNT"
    return 0
  fi

  if [[ -n "${SORASWAP_AUTHORITY:-}" ]]; then
    echo "$SORASWAP_AUTHORITY"
    return 0
  fi

  case "$mode" in
    local|testnet)
      echo "$SORASWAP_TREASURY_ACCOUNT_DEFAULT"
      ;;
    *)
      echo "$SORASWAP_TREASURY_ACCOUNT_DEFAULT"
      ;;
  esac
}

account_exists() {
  local config="$1"
  local account_id="$2"
  iroha_cli_json --config "$config" ledger account get --id "$account_id" >/dev/null 2>&1
}

wait_for_account_exists() {
  local config="$1"
  local account_id="$2"
  local attempts="${3:-15}"
  local sleep_seconds="${4:-1}"
  local attempt=1

  while (( attempt <= attempts )); do
    if account_exists "$config" "$account_id"; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  return 1
}

ensure_account_registered() {
  local config="$1"
  local account_id="$2"
  local domain="$3"

  if account_exists "$config" "$account_id"; then
    echo "account already present: $account_id"
    return 0
  fi

  echo "register account: $account_id -> $domain"
  iroha_cli --machine --config "$config" ledger account register \
    --id "$account_id" \
    --domain "$domain"
}

read_norito_error_message() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    return 1
  fi

  /usr/bin/python3 - "$file_path" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
parts = []
current = []
for byte in data:
    if 32 <= byte <= 126:
        current.append(chr(byte))
    else:
        if current:
            parts.append("".join(current))
            current = []
if current:
    parts.append("".join(current))
if parts:
    print(parts[-1])
PY
}

extract_expected_chain_id_from_error() {
  local text="$1"
  printf '%s\n' "$text" \
    | sed -n 's/.*Expected ChainId("\([^"]*\)").*/\1/p' \
    | tail -n 1
}

try_public_self_register_account() {
  local config="$1"
  local account_id="$2"
  local output

  SORASWAP_LAST_SELF_REGISTER_ERROR=""
  if output="$(iroha_cli --machine --output-format json --config "$config" \
    ledger account register --id "$account_id" --domainless 2>&1)"; then
    SORASWAP_LAST_SELF_REGISTER_ERROR="$output"
    return 0
  fi

  SORASWAP_LAST_SELF_REGISTER_ERROR="$output"
  return 1
}

try_public_onboard_account() {
  local config="$1"
  local account_id="$2"
  local alias="$3"
  local torii_base payload tmp http_code

  SORASWAP_LAST_ONBOARD_STATUS=""
  SORASWAP_LAST_ONBOARD_ERROR=""

  torii_base="$(torii_base_from_config "$config")"
  payload="$(jq -cn --arg alias "$alias" --arg account_id "$account_id" \
    '{alias: $alias, account_id: $account_id}')"
  tmp="$(mktemp)"
  http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H 'Accept: application/json' \
    -H 'X-Iroha-API-Version: 1.1' \
    -H 'Content-Type: application/json' \
    -X POST \
    "$torii_base/v1/accounts/onboard" \
    -d "$payload" || true)"
  SORASWAP_LAST_ONBOARD_STATUS="$http_code"

  if [[ "$http_code" == "200" || "$http_code" == "202" ]]; then
    rm -f "$tmp"
    return 0
  fi

  SORASWAP_LAST_ONBOARD_ERROR="$(read_norito_error_message "$tmp" || true)"
  rm -f "$tmp"
  return 1
}

probe_public_faucet() {
  local config="$1"
  fetch_public_faucet_puzzle_json "$config" >/dev/null
}

fetch_public_faucet_puzzle_json() {
  local config="$1"
  local torii_base tmp http_code

  SORASWAP_LAST_FAUCET_STATUS=""
  SORASWAP_LAST_FAUCET_ERROR=""

  torii_base="$(torii_base_from_config "$config")"
  tmp="$(mktemp)"
  http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H 'Accept: application/json' \
    -H 'X-Iroha-API-Version: 1.1' \
    "$torii_base/v1/accounts/faucet/puzzle" || true)"
  SORASWAP_LAST_FAUCET_STATUS="$http_code"

  if [[ "$http_code" == "200" ]]; then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi

  SORASWAP_LAST_FAUCET_ERROR="$(read_norito_error_message "$tmp" || true)"
  rm -f "$tmp"
  return 1
}

scrypt_capable_python() {
  local candidate

  for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi
    if "$candidate" - <<'PY' >/dev/null 2>&1
import hashlib
raise SystemExit(0 if hasattr(hashlib, "scrypt") else 1)
PY
    then
      echo "$candidate"
      return 0
    fi
  done

  echo "no python interpreter with hashlib.scrypt support is available" >&2
  return 1
}

solve_public_faucet_nonce_hex() {
  local account_id="$1"
  local puzzle_json="$2"
  local python_bin

  python_bin="$(scrypt_capable_python)"

  PUZZLE_JSON="$puzzle_json" "$python_bin" - "$account_id" <<'PY'
import hashlib
import json
import os
import sys

DOMAIN = b"iroha:accounts:faucet:pow:v2"

def leading_zero_bits(data: bytes) -> int:
    total = 0
    for byte in data:
        if byte == 0:
            total += 8
            continue
        total += 8 - byte.bit_length()
        break
    return total

account_id = sys.argv[1]
puzzle = json.loads(os.environ["PUZZLE_JSON"])
difficulty = int(puzzle.get("difficulty_bits", 0) or 0)
if difficulty <= 0:
    print("")
    raise SystemExit(0)

anchor_height = int(puzzle["anchor_height"])
anchor_hash = bytes.fromhex(puzzle["anchor_block_hash_hex"])
challenge_salt_hex = puzzle.get("challenge_salt_hex")
challenge_salt = bytes.fromhex(challenge_salt_hex) if challenge_salt_hex else b""

challenge = hashlib.sha256(
    DOMAIN
    + account_id.encode("utf-8")
    + anchor_height.to_bytes(8, "big")
    + anchor_hash
    + challenge_salt
).digest()
n = 1 << int(puzzle["scrypt_log_n"])
r = int(puzzle["scrypt_r"])
p = int(puzzle["scrypt_p"])

counter = 0
while True:
    nonce = counter.to_bytes(8, "big")
    digest = hashlib.scrypt(nonce, salt=challenge, n=n, r=r, p=p, dklen=32)
    if leading_zero_bits(digest) >= difficulty:
        print(nonce.hex())
        break
    counter += 1
PY
}

wait_for_positive_asset_balance() {
  local config="$1"
  local alias="$2"
  local account="$3"
  local attempts="${4:-60}"
  local sleep_seconds="${5:-1}"
  local attempt=1
  local current="0"

  while (( attempt <= attempts )); do
    current="$(asset_value_for_account "$config" "$alias" "$account")"
    if numeric_gt_zero "$current"; then
      printf '%s\n' "$current"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  printf '%s\n' "$current"
  return 1
}

account_contract_deploy_nonce() {
  local config="$1"
  local account_id="$2"
  local response

  if ! response="$(iroha_cli_json --config "$config" ledger account get --id "$account_id" 2>/dev/null)"; then
    echo 0
    return 0
  fi

  ACCOUNT_JSON="$response" /usr/bin/python3 - <<'PY'
import json
import os
import sys

def coerce(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    if isinstance(value, dict):
        for key in ("value", "u64", "U64", "int", "Int", "raw"):
            if key in value:
                converted = coerce(value[key])
                if converted is not None:
                    return converted
    return None

def visit(value):
    if isinstance(value, dict):
        if "contract_deploy_nonce" in value:
            converted = coerce(value["contract_deploy_nonce"])
            if converted is not None:
                return converted
        if value.get("key") == "contract_deploy_nonce":
            converted = coerce(value.get("value"))
            if converted is not None:
                return converted
        for nested in value.values():
            converted = visit(nested)
            if converted is not None:
                return converted
    elif isinstance(value, list):
        for item in value:
            converted = visit(item)
            if converted is not None:
                return converted
    return None

document = json.loads(os.environ["ACCOUNT_JSON"])
print(visit(document) or 0)
PY
}

claim_public_testnet_faucet() {
  local config="$1"
  local account_id="$2"
  local torii_base puzzle_json nonce_hex payload_json response http_code body tx_hash

  puzzle_json="$(fetch_public_faucet_puzzle_json "$config")" || return 1
  nonce_hex="$(solve_public_faucet_nonce_hex "$account_id" "$puzzle_json")"
  torii_base="$(torii_base_from_config "$config")"
  payload_json="$(jq -cn \
    --arg account_id "$account_id" \
    --argjson anchor_height "$(jq -r '.anchor_height' <<<"$puzzle_json")" \
    --arg nonce_hex "$nonce_hex" \
    --argjson difficulty_bits "$(jq -r '.difficulty_bits // 0' <<<"$puzzle_json")" \
    '{
      account_id: $account_id
    } + (if $difficulty_bits > 0 then {
      pow_anchor_height: $anchor_height,
      pow_nonce_hex: $nonce_hex
    } else {} end)')"

  response="$(curl -sS \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'X-Iroha-API-Version: 1.1' \
    -w $'\n%{http_code}' \
    -X POST \
    "$torii_base/v1/accounts/faucet" \
    -d "$payload_json")" || {
      echo "failed to reach $torii_base/v1/accounts/faucet" >&2
      return 1
    }
  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" && "$http_code" != "202" ]]; then
    echo "faucet claim failed for $account_id: HTTP $http_code: $body" >&2
    return 1
  fi

  tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$body")"
  if [[ -n "$tx_hash" ]]; then
    local pipeline_json pipeline_kind
    if pipeline_json="$(wait_for_transaction_terminal_status "$config" "$tx_hash" 90 1 auto)"; then
      pipeline_kind="$(jq -r '.content.status.kind // empty' <<<"$pipeline_json")"
      case "$pipeline_kind" in
        Applied|Committed)
          :
          ;;
        *)
          echo "faucet claim transaction did not commit cleanly: $pipeline_json" >&2
          return 1
          ;;
      esac
    fi
  fi

  printf '%s\n' "$body"
}

warn_if_testnet_tx_gossip_cap_low() {
  local config="$1"
  local torii_base frame_cap

  torii_base="$(torii_base_from_config "$config")"
  frame_cap="$(curl -sS "$torii_base/status" 2>/dev/null | jq -r '.tx_gossip.caps.frame_cap_bytes // 0' 2>/dev/null || true)"
  if [[ -z "$frame_cap" || "$frame_cap" == "null" ]]; then
    return 0
  fi
  if (( frame_cap < SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP )); then
    echo "warning: live tx_gossip frame cap is $frame_cap bytes; recommended minimum is $SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP bytes for routine SoraSwap deploys" >&2
  fi
}

asset_definition_alias_exists() {
  local config="$1"
  local alias="$2"
  iroha_cli_json --config "$config" ledger asset definition get --alias "$alias" >/dev/null 2>&1
}

asset_definition_id_for_alias() {
  local config="$1"
  local alias="$2"
  iroha_cli_json --config "$config" ledger asset definition get --alias "$alias" \
    | jq -r '.id'
}

ensure_asset_definition_alias() {
  local config="$1"
  local asset_id="$2"
  local name="$3"
  local alias="$4"
  local scale="$5"
  local existing_id

  if asset_definition_alias_exists "$config" "$alias"; then
    existing_id="$(asset_definition_id_for_alias "$config" "$alias")"
    if [[ "$existing_id" != "$asset_id" ]]; then
      echo "asset alias $alias is already bound to unexpected definition id $existing_id" >&2
      return 1
    fi
    echo "asset definition alias already present: $alias -> $existing_id"
    return 0
  fi

  echo "register asset definition alias: $alias -> $asset_id"
  iroha_cli --machine --config "$config" ledger asset definition register \
    --id "$asset_id" \
    --name "$name" \
    --alias "$alias" \
    --scale "$scale"
}

asset_value_for_account() {
  local config="$1"
  local alias="$2"
  local account="$3"
  local torii_base encoded_account encoded_asset response

  torii_base="$(torii_base_from_config "$config")"
  encoded_account="$(uri_encode "$account")"
  encoded_asset="$(uri_encode "$alias")"
  if ! response="$(
    curl -fsS \
      "$torii_base/v1/accounts/${encoded_account}/assets?asset=${encoded_asset}&scope=global&limit=1" \
      2>/dev/null
  )"; then
    echo 0
    return 0
  fi

  jq -r 'if (.items | length) == 0 then "0" else (.items[0].quantity // "0") end' <<<"$response"
}

wait_for_asset_balance() {
  local config="$1"
  local alias="$2"
  local account="$3"
  local expected="$4"
  local attempts="${5:-15}"
  local sleep_seconds="${6:-1}"
  local attempt=1
  local current

  while (( attempt <= attempts )); do
    current="$(asset_value_for_account "$config" "$alias" "$account")"
    if [[ "$current" == "$expected" ]]; then
      echo "$current"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "$current"
  return 1
}

ensure_asset_balance_min() {
  local config="$1"
  local alias="$2"
  local account="$3"
  local minimum="$4"
  local current delta

  current="$(asset_value_for_account "$config" "$alias" "$account")"
  if (( current >= minimum )); then
    echo "asset balance already sufficient: $alias -> $current"
    return 0
  fi

  delta=$(( minimum - current ))
  echo "mint asset balance: $alias +$delta -> $account"
  iroha_cli --machine --config "$config" ledger asset mint \
    --definition-alias "$alias" \
    --account "$account" \
    --quantity "$delta"
}

contract_instance_exists() {
  local config="$1"
  local dataspace="$2"
  local contract_id="$3"
  local response

  response="$(iroha_cli_json --config "$config" app contracts instances \
    --dataspace "$dataspace" \
    --contains "$contract_id")"
  jq -e --arg cid "$contract_id" \
    'any(.instances[]?; .contract_id == $cid)' <<<"$response" >/dev/null
}

contract_instance_json() {
  local config="$1"
  local dataspace="$2"
  local contract_id="$3"
  local response

  response="$(iroha_cli_json --config "$config" app contracts instances \
    --dataspace "$dataspace" \
    --contains "$contract_id")"
  jq -c --arg cid "$contract_id" \
    '.instances[]? | select(.contract_id == $cid)' <<<"$response"
}

wait_for_contract_instance() {
  local config="$1"
  local dataspace="$2"
  local contract_id="$3"
  local expected_code_hash="${4:-}"
  local attempts="${5:-60}"
  local sleep_seconds="${6:-1}"
  local attempt=1
  local instance_json current_code_hash

  while (( attempt <= attempts )); do
    if instance_json="$(contract_instance_json "$config" "$dataspace" "$contract_id" 2>/dev/null)"; then
      if [[ -n "$instance_json" ]]; then
        current_code_hash="$(jq -r '.code_hash_hex // empty' <<<"$instance_json")"
        if [[ -n "$expected_code_hash" && "$current_code_hash" != "$expected_code_hash" ]]; then
          echo "contract instance $contract_id committed with unexpected code hash: $current_code_hash (expected $expected_code_hash)" >&2
          return 1
        fi
        printf '%s\n' "$instance_json"
        return 0
      fi
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract instance $contract_id was not visible after ${attempts}s" >&2
  return 1
}

submit_contract_call() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local gas_limit="${4:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local payload_json="${5:-null}"
  local torii_base private_key request response http_code body

  ensure_authority "$config"
  torii_base="$(torii_base_from_config "$config")"
  private_key="$(account_private_key_from_config "$config")"

  if is_contract_address_literal "$contract_id"; then
    request="$(jq -cn \
      --arg authority "$SORASWAP_AUTHORITY" \
      --arg private_key "$private_key" \
      --arg contract_address "$contract_id" \
      --arg entrypoint "$entrypoint" \
      --argjson gas_limit "$gas_limit" \
      --argjson payload "$payload_json" \
      '{
        authority: $authority,
        private_key: $private_key,
        contract_address: $contract_address,
        entrypoint: $entrypoint,
        gas_limit: $gas_limit
      } + (if $payload == null then {} else {payload: $payload} end)')"
  else
    echo "contract call requires a canonical contract address, got: $contract_id" >&2
    return 1
  fi

  response="$(curl -sS \
    -H 'Content-Type: application/json' \
    -w $'\n%{http_code}' \
    -X POST \
    "$torii_base/v1/contracts/call" \
    -d "$request")" || {
      echo "failed to reach $torii_base/v1/contracts/call for $contract_id.$entrypoint" >&2
      return 1
    }

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "contract call request failed for $contract_id.$entrypoint: HTTP $http_code: $body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

submit_contract_view() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local gas_limit="${4:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local payload_json="${5:-null}"
  local torii_base request response http_code body curl_args

  ensure_authority "$config"
  torii_base="$(torii_base_from_config "$config")"

  if is_contract_address_literal "$contract_id"; then
    request="$(jq -cn \
      --arg authority "$SORASWAP_AUTHORITY" \
      --arg contract_address "$contract_id" \
      --arg entrypoint "$entrypoint" \
      --argjson gas_limit "$gas_limit" \
      --argjson payload "$payload_json" \
      '{
        authority: $authority,
        contract_address: $contract_address,
        entrypoint: $entrypoint,
        gas_limit: $gas_limit
      } + (if $payload == null then {} else {payload: $payload} end)')"
  else
    echo "contract view requires a canonical contract address, got: $contract_id" >&2
    return 1
  fi

  curl_args=(
    -sS
    -H 'Content-Type: application/json'
    -w $'\n%{http_code}'
    -X POST
  )
  if [[ -n "${SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS:-}" ]]; then
    curl_args+=(--max-time "$SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS")
  fi
  curl_args+=(
    "$torii_base/v1/contracts/view"
    -d "$request"
  )

  response="$(curl "${curl_args[@]}")" || {
      echo "failed to reach $torii_base/v1/contracts/view for $contract_id.$entrypoint" >&2
      return 1
    }

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "contract view request failed for $contract_id.$entrypoint: HTTP $http_code: $body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

submit_contract_deploy_file() {
  local config="$1"
  local code_file="$2"
  local dataspace="${3:-universal}"
  local torii_base private_key code_b64 request response http_code body curl_args

  ensure_authority "$config"
  torii_base="$(torii_base_from_config "$config")"
  private_key="$(account_private_key_from_config "$config")"
  code_b64="$(base64 < "$code_file" | tr -d '\r\n')"

  request="$(jq -cn \
    --arg authority "$SORASWAP_AUTHORITY" \
    --arg private_key "$private_key" \
    --arg code_b64 "$code_b64" \
    --arg dataspace "$dataspace" \
    '{
      authority: $authority,
      private_key: $private_key,
      code_b64: $code_b64,
      dataspace: $dataspace
    }')"

  curl_args=(
    -sS
    -H 'Content-Type: application/json'
    -H 'Accept: application/json'
    -H 'X-Iroha-API-Version: 1.1'
    -w $'\n%{http_code}'
    -X POST
  )
  if [[ -n "${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-}" ]]; then
    curl_args+=(--max-time "$SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS")
  fi
  curl_args+=(
    "$torii_base/v1/contracts/deploy"
    -d "$request"
  )

  response="$(curl "${curl_args[@]}")" || {
    echo "failed to reach $torii_base/v1/contracts/deploy" >&2
    return 1
  }
  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "contract deploy request failed for $code_file: HTTP $http_code: $body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

derive_contract_address_for_deploy() {
  local config="$1"
  local authority="$2"
  local deploy_nonce="$3"
  local dataspace="${4:-universal}"
  local env="${5:-testnet}"
  local chain_discriminant

  chain_discriminant="$(chain_discriminant_for_env "$env")"
  iroha_cli_json --config "$config" app contracts derive-address \
    --authority "$authority" \
    --dataspace "$dataspace" \
    --deploy-nonce "$deploy_nonce" \
    --chain-discriminant "$chain_discriminant" \
    | jq -r '.contract_address'
}

contract_view_result_json() {
  local response_json="$1"
  jq -cer 'if .ok == true then .result else error("contract view response did not succeed") end' <<<"$response_json"
}

contract_view_result_object() {
  local response_json="$1"
  shift
  local keys_json

  keys_json="$(printf '%s\n' "$@" | jq -R . | jq -cs .)"
  jq -cn \
    --argjson response "$response_json" \
    --argjson keys "$keys_json" \
    '
      if $response.ok != true then
        error("contract view response did not succeed")
      elif ($response.result | type) != "array" then
        error("contract view result is not a tuple")
      elif ($response.result | length) != ($keys | length) then
        error("contract view tuple length mismatch")
      else
        reduce range(0; $keys | length) as $idx ({}; . + {($keys[$idx]): $response.result[$idx]})
      end
    '
}

pipeline_transaction_status_json() {
  local config="$1"
  local tx_hash="$2"
  local scope="${3:-auto}"
  local torii_base response http_code body

  torii_base="$(torii_base_from_config "$config")"
  response="$(curl -sS \
    -H 'Accept: application/json' \
    -w $'\n%{http_code}' \
    "$torii_base/v1/pipeline/transactions/status?hash=$tx_hash&scope=$scope")" || return 1

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  case "$http_code" in
    200)
      printf '%s\n' "$body"
      ;;
    404)
      return 2
      ;;
    *)
      echo "failed to fetch pipeline status for $tx_hash: HTTP $http_code: $body" >&2
      return 1
      ;;
  esac
}

wait_for_transaction_commit() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local attempt=1

  while (( attempt <= attempts )); do
    if iroha_cli_json --config "$config" ledger transaction get --hash "$tx_hash" \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "transaction $tx_hash was not committed after ${attempts}s" >&2
  return 1
}

wait_for_transaction_terminal_status() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local scope="${5:-auto}"
  local attempt=1
  local response kind latest_kind=""

  while (( attempt <= attempts )); do
    if response="$(pipeline_transaction_status_json "$config" "$tx_hash" "$scope" 2>/dev/null)"; then
      kind="$(jq -r '.content.status.kind // empty' <<<"$response")"
      latest_kind="$kind"
      case "$kind" in
        Applied|Committed|Rejected|Expired)
          printf '%s\n' "$response"
          return 0
          ;;
      esac
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$latest_kind" ]]; then
    echo "transaction $tx_hash did not reach a terminal pipeline status after ${attempts}s (latest: $latest_kind)" >&2
  else
    echo "transaction $tx_hash did not expose pipeline status after ${attempts}s" >&2
  fi
  return 1
}

committed_transaction_json() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local attempt=1
  local response

  while (( attempt <= attempts )); do
    if response="$(iroha_cli_json --config "$config" ledger transaction get --hash "$tx_hash" 2>/dev/null)"; then
      echo "$response"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "transaction $tx_hash was not committed after ${attempts}s" >&2
  return 1
}

assert_transaction_ok() {
  local tx_json="$1"
  local tx_hash="${2:-unknown}"
  local context="${3:-transaction}"
  local rejection

  if jq -e '.result | has("Ok")' <<<"$tx_json" >/dev/null; then
    return 0
  fi

  rejection="$(jq -c '.result.Err // .result' <<<"$tx_json")"
  echo "$context failed for transaction $tx_hash: $rejection" >&2
  return 1
}

call_contract_and_wait() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local payload_json="${4:-null}"
  local gas_limit="${5:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local response tx_hash tx_json pipeline_json pipeline_kind pipeline_content

  response="$(submit_contract_call "$config" "$contract_id" "$entrypoint" "$gas_limit" "$payload_json")"
  echo "$response" \
    | jq -e '.ok == true and .submitted == true and (.tx_hash_hex | type == "string") and (.tx_hash_hex | length > 0)' \
    >/dev/null
  tx_hash="$(echo "$response" | jq -r '.tx_hash_hex')"
  if pipeline_json="$(wait_for_transaction_terminal_status "$config" "$tx_hash" 60 1 auto)"; then
    pipeline_kind="$(jq -r '.content.status.kind // empty' <<<"$pipeline_json")"
    case "$pipeline_kind" in
      Applied|Committed)
        if tx_json="$(committed_transaction_json "$config" "$tx_hash" 5 1 2>/dev/null)"; then
          assert_transaction_ok "$tx_json" "$tx_hash" "$contract_id.$entrypoint"
        fi
        ;;
      Rejected|Expired)
        pipeline_content="$(jq -c '.content.status.content // .content.status' <<<"$pipeline_json")"
        echo "$contract_id.$entrypoint failed for transaction $tx_hash: $pipeline_content" >&2
        return 1
        ;;
      *)
        echo "$contract_id.$entrypoint reached unexpected pipeline status for transaction $tx_hash: $pipeline_kind" >&2
        return 1
        ;;
    esac
  else
    tx_json="$(committed_transaction_json "$config" "$tx_hash")"
    assert_transaction_ok "$tx_json" "$tx_hash" "$contract_id.$entrypoint"
  fi
  echo "$tx_hash"
}

list_contracts() {
  find "$SORASWAP_ROOT/contracts" -type f -name '*.ko' | sort
}

expected_contract_ids() {
  local contract
  while IFS= read -r contract; do
    contract_id_for "$contract"
  done < <(list_contracts)
}

expected_contract_ids_for_env() {
  local env="$1"
  local contract_key
  while IFS= read -r contract_key; do
    deployed_contract_id_for_env "$env" "$contract_key"
  done < <(expected_contract_ids)
}

compiled_path_for() {
  local src="$1"
  local rel="${src#$SORASWAP_ROOT/contracts/}"
  echo "$SORASWAP_ROOT/artifacts/compiled/${rel%.ko}.to"
}

manifest_path_for() {
  local src="$1"
  local rel="${src#$SORASWAP_ROOT/contracts/}"
  echo "$SORASWAP_ROOT/artifacts/compiled/${rel%.ko}.manifest.json"
}

contract_id_for() {
  local src="$1"
  local rel="${src#$SORASWAP_ROOT/contracts/}"
  rel="${rel%.ko}"
  echo "${rel//\//.}"
}

deployment_record_path_for_env() {
  local env="$1"
  local contract_key="$2"
  echo "$SORASWAP_ROOT/deployments/${env}/${contract_key}.deploy.json"
}

deployed_contract_id_for_env() {
  local env="$1"
  local contract_key="$2"
  local record

  record="$(deployment_record_path_for_env "$env" "$contract_key")"
  if [[ -f "$record" ]]; then
    jq -r '.contract_address // .contract_id // empty' "$record"
    return 0
  fi

  echo "$contract_key"
}

deployed_contract_dataspace_for_env() {
  local env="$1"
  local contract_key="$2"
  local record

  record="$(deployment_record_path_for_env "$env" "$contract_key")"
  if [[ -f "$record" ]]; then
    jq -r '.dataspace // .namespace // "universal"' "$record"
    return 0
  fi

  echo "universal"
}

is_contract_address_literal() {
  local value="$1"
  [[ "$value" != *.* && "$value" == *1* ]]
}

compile_one() {
  local src="$1"
  local out manifest out_dir compiler_bin output filtered
  out="$(compiled_path_for "$src")"
  manifest="$(manifest_path_for "$src")"
  compiler_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_compile"
  if [[ "${SORASWAP_FORCE_COMPILE:-0}" != "1" && -f "$out" && -f "$manifest" \
      && "$out" -nt "$src" && "$manifest" -nt "$src" ]]; then
    if [[ ! -x "$compiler_bin" || ( "$out" -nt "$compiler_bin" && "$manifest" -nt "$compiler_bin" ) ]]; then
      echo "compile: up-to-date $src"
      return 0
    fi
  fi
  ensure_koto_compile_bin
  if [[ "${SORASWAP_FORCE_COMPILE:-0}" != "1" && -f "$out" && -f "$manifest" \
      && "$out" -nt "$src" && "$manifest" -nt "$src" \
      && "$out" -nt "$compiler_bin" && "$manifest" -nt "$compiler_bin" ]]; then
    echo "compile: up-to-date $src"
    return 0
  fi
  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"
  if ! output="$(
    cd "$SORASWAP_IROHA_ROOT"
    "$compiler_bin" \
      "$src" \
      --out "$out" \
      --manifest-out "$manifest" \
      --abi 1 2>&1
  )"; then
    printf '%s\n' "$output" >&2
    return 1
  fi

  filtered="$(
    while IFS= read -r line; do
      if [[ "$line" == lint:\ literal\ *\ appears\ multiple\ times\ in\ pointer\ constructors\;* ]]; then
        continue
      fi
      if [[ "$line" == lint:\ state\ map\ *\ uses\ a\ non-literal\ key\;\ access\ hints\ will\ be\ skipped ]]; then
        continue
      fi
      if [[ "$line" == access-hint:\ * ]]; then
        continue
      fi
      printf '%s\n' "$line"
    done <<< "$output"
  )"

  if [[ -n "${filtered//[$'\r\n\t ']}" ]]; then
    printf '%s\n' "$filtered"
  fi
}

lint_one() {
  local src="$1"
  ensure_koto_lint_bin
  (
    cd "$SORASWAP_IROHA_ROOT"
    "$SORASWAP_IROHA_ROOT/target/debug/koto_lint" "$src"
  )
}

deployment_record_matches_current_chain() {
  local record_path="$1"
  local fingerprint_json="$2"

  if [[ ! -f "$record_path" ]]; then
    return 1
  fi

  jq -e \
    --argjson current "$fingerprint_json" \
    '
      (.chain_fingerprint // {}) as $stored
      | $stored.torii_url == $current.torii_url
      and $stored.chain == $current.chain
      and $stored.block_1_hash == $current.block_1_hash
    ' "$record_path" >/dev/null
}

live_contract_instance_from_record() {
  local config="$1"
  local record_path="$2"
  local expected_code_hash="$3"
  local dataspace contract_address instance_json current_code_hash

  dataspace="$(jq -r '.dataspace // "universal"' "$record_path")"
  contract_address="$(jq -r '.contract_address // .contract_id // empty' "$record_path")"
  if [[ -z "$contract_address" ]]; then
    return 1
  fi

  instance_json="$(contract_instance_json "$config" "$dataspace" "$contract_address" 2>/dev/null || true)"
  if [[ -z "$instance_json" ]]; then
    return 1
  fi

  current_code_hash="$(jq -r '.code_hash_hex // empty' <<<"$instance_json")"
  if [[ -n "$expected_code_hash" && "${current_code_hash:l}" != "$expected_code_hash" ]]; then
    return 1
  fi

  printf '%s\n' "$instance_json"
}

deploy_one() {
  local config="$1"
  local src="$2"
  local env="$3"
  local contract_key manifest_out deploy_out code_file compiled_manifest dataspace
  local expected_code_hash expected_abi_hash instance_json record_json existing_instance
  local pre_nonce post_nonce predicted_address response_json normal_output normal_error
  local split_output deploy_strategy detail_json

  contract_key="$(contract_id_for "$src")"
  dataspace="universal"
  manifest_out="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
  deploy_out="$(deployment_record_path_for_env "$env" "$contract_key")"
  code_file="$(compiled_path_for "$src")"
  compiled_manifest="$(manifest_path_for "$src")"
  expected_code_hash="$(manifest_code_hash_hex "$compiled_manifest")"
  expected_abi_hash="$(manifest_abi_hash_hex "$compiled_manifest")"
  mkdir -p "$(dirname "$manifest_out")"

  if deployment_record_matches_current_chain "$deploy_out" "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}"; then
    if existing_instance="$(live_contract_instance_from_record "$config" "$deploy_out" "$expected_code_hash")"; then
      cp "$compiled_manifest" "$manifest_out"
      detail_json="$(jq -cn \
        --arg contract_key "$contract_key" \
        --argjson record "$(cat "$deploy_out")" \
        --argjson instance "$existing_instance" \
        '{
          contract_key: $contract_key,
          reason: "matching live deployment record",
          record: $record,
          instance: $instance
        }')"
      deploy_report_set_contract "$env" "$contract_key" "skipped" "$detail_json"
      return 0
    fi
  fi

  pre_nonce="$(account_contract_deploy_nonce "$config" "$SORASWAP_AUTHORITY")"
  predicted_address="$(derive_contract_address_for_deploy "$config" "$SORASWAP_AUTHORITY" "$pre_nonce" "$dataspace" "$env")"
  response_json=""
  normal_error=""
  deploy_strategy=""

  if normal_output="$(submit_contract_deploy_file "$config" "$code_file" "$dataspace" 2>&1)"; then
    if ! jq -e \
      --arg expected_address "$predicted_address" \
      --arg dataspace "$dataspace" \
      --arg code_hash_hex "$expected_code_hash" \
      '
        .ok == true
        and .dataspace == $dataspace
        and .contract_address == $expected_address
        and ((.code_hash_hex | ascii_downcase) == $code_hash_hex)
      ' <<<"$normal_output" >/dev/null; then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg response "$normal_output" \
        '{contract_key: $contract_key, stage: "normal_deploy_validate", response: $response}')"
      echo "unexpected deploy response for $contract_key: $normal_output" >&2
      return 1
    fi
    response_json="$normal_output"
    instance_json="$(wait_for_contract_instance "$config" "$dataspace" "$predicted_address" "$expected_code_hash" 90 1 2>/dev/null || true)"
    if [[ -n "$instance_json" ]]; then
      deploy_strategy="normal"
    fi
  else
    normal_error="$normal_output"
  fi

  if [[ -z "$instance_json" ]]; then
    post_nonce="$(account_contract_deploy_nonce "$config" "$SORASWAP_AUTHORITY")"
    if (( post_nonce > pre_nonce )); then
      instance_json="$(wait_for_contract_instance "$config" "$dataspace" "$predicted_address" "$expected_code_hash" 90 1 2>/dev/null || true)"
      if [[ -z "$instance_json" ]]; then
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg contract_address "$predicted_address" \
          --argjson pre_nonce "$pre_nonce" \
          --argjson post_nonce "$post_nonce" \
          --arg normal_error "$normal_error" \
          '{
            contract_key: $contract_key,
            stage: "adopt_committed_wait",
            contract_address: $contract_address,
            pre_nonce: $pre_nonce,
            post_nonce: $post_nonce
          } + (if ($normal_error | length) > 0 then {normal_deploy_error: $normal_error} else {} end)')"
        echo "deploy nonce advanced for $contract_key but instance did not become visible at $predicted_address" >&2
        return 1
      fi
      if [[ -z "$response_json" ]]; then
        response_json="$(jq -cn \
          --arg contract_address "$predicted_address" \
          --arg dataspace "$dataspace" \
          --arg code_hash_hex "$expected_code_hash" \
          --arg abi_hash_hex "$expected_abi_hash" \
          --arg normal_error "$normal_error" \
          --argjson deploy_nonce "$pre_nonce" \
          '{
            ok: true,
            contract_address: $contract_address,
            dataspace: $dataspace,
            deploy_nonce: $deploy_nonce,
            code_hash_hex: $code_hash_hex,
            abi_hash_hex: $abi_hash_hex
          } + (if ($normal_error | length) > 0 then {normal_deploy_error: $normal_error} else {} end)')"
      fi
      deploy_strategy="adopted_committed"
    fi
  fi

  if [[ -z "$instance_json" ]]; then
    split_output="$(split_contract_deploy_cli \
      --config "$config" \
      --authority "$SORASWAP_AUTHORITY" \
      --private-key "$(account_private_key_from_config "$config")" \
      --code-file "$code_file" \
      --contract-address "$predicted_address" \
      --dataspace "$dataspace" \
      --chain-discriminant "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT" \
      --deploy-nonce "$pre_nonce" 2>&1)" || {
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg predicted_address "$predicted_address" \
          --arg error "$split_output" \
          '{contract_key: $contract_key, stage: "split_fallback", contract_address: $predicted_address, error: $error}')"
        echo "$split_output" >&2
        return 1
      }
    if ! jq -e \
      --arg expected_address "$predicted_address" \
      --arg dataspace "$dataspace" \
      --arg code_hash_hex "$expected_code_hash" \
      '
        .ok == true
        and .dataspace == $dataspace
        and .contract_address == $expected_address
        and ((.code_hash_hex | ascii_downcase) == $code_hash_hex)
      ' <<<"$split_output" >/dev/null; then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg response "$split_output" \
        '{contract_key: $contract_key, stage: "split_fallback_validate", response: $response}')"
      echo "unexpected split deploy response for $contract_key: $split_output" >&2
      return 1
    fi
    response_json="$split_output"
    instance_json="$(wait_for_contract_instance "$config" "$dataspace" "$predicted_address" "$expected_code_hash" 90 1 2>/dev/null || true)"
    if [[ -z "$instance_json" ]]; then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg response "$split_output" \
        '{contract_key: $contract_key, stage: "split_fallback_wait", contract_address: $contract_address, response: $response}')"
      echo "split deploy completed for $contract_key but instance did not become visible at $predicted_address" >&2
      return 1
    fi
    deploy_strategy="split_fallback"
  fi

  record_json="$(jq -cn \
    --arg contract_key "$contract_key" \
    --arg contract_source "$src" \
    --arg dataspace "$dataspace" \
    --arg deploy_strategy "$deploy_strategy" \
    --argjson response "$response_json" \
    --argjson instance "$instance_json" \
    --argjson chain_fingerprint "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
    '{
      contract_key: $contract_key,
      contract_source: $contract_source,
      dataspace: $dataspace,
      contract_address: ($response.contract_address // $instance.contract_id),
      deploy_nonce: ($response.deploy_nonce // 0),
      code_hash_hex: ($response.code_hash_hex // $instance.code_hash_hex),
      abi_hash_hex: ($response.abi_hash_hex // ""),
      deploy_strategy: $deploy_strategy,
      chain_fingerprint: $chain_fingerprint,
      response: $response,
      instance: $instance
    }')"
  printf '%s\n' "$record_json" > "$deploy_out"
  cp "$compiled_manifest" "$manifest_out"
  deploy_report_set_contract "$env" "$contract_key" "$deploy_strategy" "$record_json"
}

ensure_client() {
  local config="$1"
  require_file "$config"
}

ensure_account_exists() {
  local config="$1"
  local account_id="$2"

  if account_exists "$config" "$account_id"; then
    return 0
  fi

  echo "account does not exist on the target chain: $account_id" >&2
  echo "use a signer that already exists on-chain before running public deploy or smoke flows" >&2
  exit 1
}

ensure_public_testnet_signer_ready() {
  local config="$1"
  local account_id="$2"
  local mode="${3:-autofund}"
  local fee_alias="$SORASWAP_FEE_ASSET_ALIAS"
  local balance="0"
  local faucet_claimed=0

  if [[ "${SORASWAP_SKIP_TESTNET_SIGNER_READY_CHECK:-0}" == "1" ]]; then
    echo "skipping testnet signer readiness check for $account_id"
    return 0
  fi

  if account_exists "$config" "$account_id"; then
    balance="$(asset_value_for_account "$config" "$fee_alias" "$account_id")"
    if numeric_gt_zero "$balance"; then
      echo "testnet signer ready: $account_id holds $balance of $fee_alias"
      return 0
    fi
  fi

  if [[ "$mode" == "autofund" ]]; then
    echo "claim faucet funding for testnet signer: $account_id"
    claim_public_testnet_faucet "$config" "$account_id" >/dev/null
    faucet_claimed=1
    wait_for_account_exists "$config" "$account_id" 15 1 >/dev/null || true
    if balance="$(wait_for_positive_asset_balance "$config" "$fee_alias" "$account_id" 15 1)"; then
      echo "testnet signer funded: $account_id -> $balance $fee_alias"
      return 0
    fi
  fi

  if (( faucet_claimed == 1 )); then
    echo "testnet signer faucet claim committed; continuing before $fee_alias balance becomes query-visible" >&2
    return 0
  fi

  probe_public_faucet "$config" || true
  echo "testnet signer is not funded for public deploy/smoke: $account_id" >&2
  if [[ -n "${SORASWAP_LAST_FAUCET_STATUS:-}" ]]; then
    echo "faucet endpoint response: HTTP ${SORASWAP_LAST_FAUCET_STATUS}${SORASWAP_LAST_FAUCET_ERROR:+ - ${SORASWAP_LAST_FAUCET_ERROR}}" >&2
  fi
  echo "run: SORASWAP_CLIENT_CONFIG=\"$config\" \"$SORASWAP_ROOT/scripts/fund_testnet_signer.sh\"" >&2
  return 1
}

ensure_domain_sns_lease() {
  local config="$1"
  local domain_label="$2"
  local output
  if iroha_cli_json --config "$config" app sns registration --selector "${domain_label}.domain" \
    >/dev/null 2>&1; then
    return 0
  fi

  if output="$(
    iroha_cli --config "$config" app sns register \
      --label "$domain_label" \
      --suffix-id "$SORASWAP_SNS_DOMAIN_SUFFIX_ID" \
      --term-years 1 \
      --pricing-class 0 \
      --payment-asset-id "$SORASWAP_SNS_PAYMENT_ASSET_ID" \
      --payment-gross 120 \
      --payment-settlement '"dummy-tx"' \
      --payment-signature '"dummy-signature"' 2>&1
  )"; then
    return 0
  fi

  if [[ "$output" == *"ERR_UNEXPECTED_NETWORK_PREFIX"* ]]; then
    local torii_base payload_json tmp http_code

    torii_base="$(torii_base_from_config "$config")"
    payload_json="$(jq -cn \
      --arg owner "$SORASWAP_AUTHORITY" \
      --arg payer "$SORASWAP_AUTHORITY" \
      --arg label "$domain_label" \
      --arg asset_id "$SORASWAP_SNS_PAYMENT_ASSET_ID" \
      --argjson suffix_id "$SORASWAP_SNS_DOMAIN_SUFFIX_ID" \
      '{
        selector: {
          version: 1,
          suffix_id: $suffix_id,
          label: $label
        },
        owner: $owner,
        controllers: [{
          controller_type: {
            kind: "Account"
          },
          account_address: $owner,
          resolver_template_id: null,
          payload: {}
        }],
        term_years: 1,
        pricing_class_hint: 0,
        payment: {
          asset_id: $asset_id,
          gross_amount: 120,
          net_amount: 120,
          settlement_tx: "dummy-tx",
          payer: $payer,
          signature: "dummy-signature"
        },
        governance: null,
        metadata: {}
      }')"
    tmp="$(mktemp)"
    http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H 'X-Iroha-API-Version: 1.1' \
      -X POST \
      "$torii_base/v1/sns/names" \
      -d "$payload_json" || true)"
    if [[ "$http_code" == "201" ]]; then
      rm -f "$tmp"
      return 0
    fi
    if [[ "$http_code" == "409" ]]; then
      rm -f "$tmp"
      return 0
    fi
    echo "sns register fallback failed for ${domain_label}.domain: HTTP ${http_code}: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  fi

  printf '%s\n' "$output" >&2
  return 1
}
