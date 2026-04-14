#!/bin/zsh
set -euo pipefail

SORASWAP_ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SORASWAP_IROHA_ROOT="${SORASWAP_IROHA_ROOT:-$(cd "$SORASWAP_ROOT/../iroha" && pwd)}"
SORASWAP_BASE_ASSET_ALIAS="${SORASWAP_BASE_ASSET_ALIAS:-xor#universal}"
SORASWAP_FEE_ASSET_ALIAS="${SORASWAP_FEE_ASSET_ALIAS:-$SORASWAP_BASE_ASSET_ALIAS}"
SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID="${SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID:-6TEAJqbb8oEPmLncoNiMRbLEK6tw}"
SORASWAP_TESTNET_FEE_ASSET_LABEL="${SORASWAP_TESTNET_FEE_ASSET_LABEL:-$SORASWAP_FEE_ASSET_ALIAS}"
SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID="${SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID:-}"
SORASWAP_PRODUCTION_FEE_ASSET_LABEL="${SORASWAP_PRODUCTION_FEE_ASSET_LABEL:-}"
SORASWAP_XOR_ASSET_DEFINITION_ID="${SORASWAP_XOR_ASSET_DEFINITION_ID:-6qLb5RYJbzychndCXgFa9aZzjWyx}"
SORASWAP_USDT_ASSET_DEFINITION_ID="${SORASWAP_USDT_ASSET_DEFINITION_ID:-7Dsw1EgqCsPmv9HpEztf26xEL2qo}"
SORASWAP_USDC_ASSET_DEFINITION_ID="${SORASWAP_USDC_ASSET_DEFINITION_ID:-4wicsaHQFueXc3GKLG7WoQaKMWWq}"
SORASWAP_KUSD_ASSET_DEFINITION_ID="${SORASWAP_KUSD_ASSET_DEFINITION_ID:-6Fjwa298w3A7KDnGxjFncsfqj8qC}"
SORASWAP_N3X_ASSET_DEFINITION_ID="${SORASWAP_N3X_ASSET_DEFINITION_ID:-5N3DQmQr8sx9bKRU87WVkqQR6D2j}"
SORASWAP_TREASURY_ACCOUNT_DEFAULT="${SORASWAP_TREASURY_ACCOUNT_DEFAULT:-6cmzPVPX94geMqaWMCxbiapYWDHgqvTDmrJvsMZab7asaSfntxyMza6}"
DEFAULT_LOCALNET_DIR="${SORASWAP_LOCALNET_DIR:-$SORASWAP_ROOT/tmp/iroha-localnet}"
DEFAULT_LOCAL_CLIENT="$DEFAULT_LOCALNET_DIR/client.toml"
DEFAULT_TESTNET_CLIENT="$SORASWAP_ROOT/config/testnet/taira.client.toml"
DEFAULT_PRODUCTION_CLIENT="$SORASWAP_ROOT/config/production/production.client.toml"
SORASWAP_SNS_DOMAIN_SUFFIX_ID="${SORASWAP_SNS_DOMAIN_SUFFIX_ID:-4098}"
SORASWAP_SNS_PAYMENT_ASSET_ID="${SORASWAP_SNS_PAYMENT_ASSET_ID:-61CtjvNd9T3THAR65GsMVHr82Bjc}"
# The `/v1/contracts/call` wrapper expects an explicit positive gas limit.
# Keep the default aligned with the verified local smoke path and README docs;
# callers can still override this per-run for heavier scenarios.
SORASWAP_SMOKE_GAS_LIMIT="${SORASWAP_SMOKE_GAS_LIMIT:-100000}"
SORASWAP_TESTNET_CHAIN_ID="${SORASWAP_TESTNET_CHAIN_ID:-809574f5-fee7-5e69-bfcf-52451e42d50f}"
SORASWAP_TESTNET_CHAIN_DISCRIMINANT="${SORASWAP_TESTNET_CHAIN_DISCRIMINANT:-369}"
SORASWAP_PRODUCTION_CHAIN_ID="${SORASWAP_PRODUCTION_CHAIN_ID:-}"
SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP="${SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP:-1048576}"
SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS="${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-45}"
SORASWAP_DEPLOY_PIPELINE_WAIT_SECS="${SORASWAP_DEPLOY_PIPELINE_WAIT_SECS:-300}"
SORASWAP_DEPLOY_COMMITTED_WAIT_SECS="${SORASWAP_DEPLOY_COMMITTED_WAIT_SECS:-120}"
SORASWAP_DEPLOY_MANIFEST_WAIT_SECS="${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-180}"
SORASWAP_TX_PIPELINE_WAIT_SECS="${SORASWAP_TX_PIPELINE_WAIT_SECS:-120}"
SORASWAP_TX_COMMITTED_WAIT_SECS="${SORASWAP_TX_COMMITTED_WAIT_SECS:-120}"
SORASWAP_CONTRACT_CALL_MAX_TIME_SECS="${SORASWAP_CONTRACT_CALL_MAX_TIME_SECS:-120}"
SORASWAP_CONTRACT_CALL_RETRY_COUNT="${SORASWAP_CONTRACT_CALL_RETRY_COUNT:-1}"
SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS="${SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS:-30}"
SORASWAP_TORII_READ_MAX_TIME_SECS="${SORASWAP_TORII_READ_MAX_TIME_SECS:-10}"

utc_timestamp() {
  env TZ=UTC date '+%Y%m%dT%H%M%SZ'
}

json_equals() {
  local left_json="$1"
  local right_json="$2"
  if [[ -z "${left_json//[$'\r\n\t ']}" || -z "${right_json//[$'\r\n\t ']}" ]]; then
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$left_json"; then
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$right_json"; then
    return 1
  fi
  jq -en --argjson left "$left_json" --argjson right "$right_json" '$left == $right' >/dev/null
}

normalize_json_or_null() {
  local raw_json="${1:-}"

  if [[ -z "${raw_json//[$'\r\n\t ']}" ]]; then
    echo 'null'
    return 0
  fi

  if ! jq -e . >/dev/null 2>&1 <<<"$raw_json"; then
    echo "invalid JSON value: $raw_json" >&2
    return 1
  fi

  printf '%s\n' "$raw_json"
}

compact_json_or_fail() {
  local label="$1"
  local raw_json="${2:-}"
  local normalized

  normalized="$(normalize_json_or_null "$raw_json")" || {
    echo "$label is not valid JSON" >&2
    return 1
  }

  jq -ce . <<<"$normalized"
}

chain_fingerprint_json_or_null() {
  normalize_json_or_null "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}"
}

extract_last_json_object() {
  /usr/bin/python3 -c '
import json
import sys

text = sys.stdin.read()
decoder = json.JSONDecoder()
last = None

for idx, ch in enumerate(text):
    if ch not in "{[":
        continue
    try:
        value, _ = decoder.raw_decode(text[idx:])
    except json.JSONDecodeError:
        continue
    last = json.dumps(value)

if last is None:
    sys.exit(1)

print(last)
'
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

fee_asset_definition_id_for_config() {
  local config="$1"
  local public_env override=""

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      override="$SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID"
      ;;
    production)
      override="$SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID"
      ;;
  esac

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  asset_definition_id_for_alias "$config" "$SORASWAP_FEE_ASSET_ALIAS"
}

fee_asset_label_for_config() {
  local config="$1"
  local public_env override=""

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      override="$SORASWAP_TESTNET_FEE_ASSET_LABEL"
      ;;
    production)
      override="$SORASWAP_PRODUCTION_FEE_ASSET_LABEL"
      ;;
  esac

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  printf '%s\n' "$SORASWAP_FEE_ASSET_ALIAS"
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
  local debug_bin="$SORASWAP_IROHA_ROOT/target/debug/iroha"
  local release_bin="$SORASWAP_IROHA_ROOT/target/release/iroha"
  local bin="$debug_bin"
  local fallback_bin=""
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""
  local rebuild=0
  local rebuild_reason=""
  if [[ -n "${SORASWAP_IROHA_CLI_BIN:-}" && -x "${SORASWAP_IROHA_CLI_BIN}" ]]; then
    fallback_bin="${SORASWAP_IROHA_CLI_BIN}"
  elif [[ -x "$debug_bin" && -x "$release_bin" ]]; then
    if [[ "$debug_bin" -nt "$release_bin" ]]; then
      fallback_bin="$debug_bin"
    else
      fallback_bin="$release_bin"
    fi
  elif [[ -x "$debug_bin" ]]; then
    fallback_bin="$debug_bin"
  elif [[ -x "$release_bin" ]]; then
    fallback_bin="$release_bin"
  fi
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    if [[ -n "$fallback_bin" ]]; then
      SORASWAP_ACTIVE_IROHA_CLI_BIN="$fallback_bin"
      echo "cli tool: reusing existing iroha binary $fallback_bin" >&2
      return 0
    fi
  fi

  if [[ -z "$fallback_bin" ]]; then
    rebuild=1
    if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
      rebuild_reason="cli tool: requested skip, but existing iroha binary is missing; building iroha"
    else
      rebuild_reason="cli tool: building iroha binary"
    fi
  else
    bin="$fallback_bin"
  fi

  if [[ -n "$fallback_bin" ]] && path_is_newer_than "$fallback_bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_crypto"; then
    rebuild=1
    rebuild_reason="cli tool: rebuilding iroha binary because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    if [[ -n "$fallback_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(lsof -t "$cargo_lock" 2>/dev/null | awk -v self="$$" '$1 != self { print; exit }')"
      if [[ -n "$lock_holder" ]]; then
        SORASWAP_ACTIVE_IROHA_CLI_BIN="$fallback_bin"
        echo "cli tool: sibling cargo job holds $cargo_lock; reusing existing iroha binary $fallback_bin" >&2
        return 0
      fi
    fi
    echo "$rebuild_reason" >&2
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build --bin iroha
    )
    bin="$debug_bin"
  fi

  SORASWAP_ACTIVE_IROHA_CLI_BIN="$bin"
}

ensure_split_contract_deploy_bin() {
  local debug_bin="$SORASWAP_IROHA_ROOT/target/debug/split_contract_deploy"
  local bin="$debug_bin"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    if [[ -x "$bin" ]]; then
      echo "cli tool: reusing existing split_contract_deploy binary" >&2
      SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN="$bin"
      return 0
    fi
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_crypto"; then
    if [[ -x "$debug_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(lsof -t "$cargo_lock" 2>/dev/null | awk -v self="$$" '$1 != self { print; exit }')"
      if [[ -n "$lock_holder" ]]; then
        SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN="$debug_bin"
        echo "cli tool: sibling cargo job holds $cargo_lock; reusing existing split_contract_deploy binary $debug_bin" >&2
        return 0
      fi
    fi
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_cli --bin split_contract_deploy
    )
  fi
  SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN="$bin"
}

split_contract_deploy_cli() {
  ensure_split_contract_deploy_bin
  local bin="${SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN:-$SORASWAP_IROHA_ROOT/target/debug/split_contract_deploy}"
  "$bin" "$@"
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

ensure_kagami_bin() {
  local bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""
  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" && -x "$bin" ]]; then
    echo "cli tool: reusing existing kagami binary" >&2
    return 0
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_kagami" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_swarm" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_test_samples"; then
    if [[ -x "$bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(lsof -t "$cargo_lock" 2>/dev/null | awk -v self="$$" '$1 != self { print; exit }')"
      if [[ -n "$lock_holder" ]]; then
        echo "cli tool: sibling cargo job holds $cargo_lock; reusing existing kagami binary $bin" >&2
        return 0
      fi
    fi
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build --bin kagami
    )
  fi
}

ensure_koto_compile_bin() {
  local compile_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_compile"
  local rebuild=0
  local rebuild_reason=""
  local build_log=""
  if [[ "${SORASWAP_KOTO_COMPILE_BIN_READY:-0}" == "1" && -x "$compile_bin" ]]; then
    return 0
  fi
  if [[ "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$compile_bin" ]]; then
      echo "koto tool: reusing existing koto_compile binary" >&2
      export SORASWAP_KOTO_COMPILE_BIN_READY=1
      return 0
    fi
  fi
  if [[ ! -x "$compile_bin" ]]; then
    rebuild=1
    rebuild_reason="koto tool: building koto_compile binary"
  elif \
    path_is_newer_than "$compile_bin" \
      "$SORASWAP_ROOT/scripts/common.sh" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    rebuild=1
    rebuild_reason="koto tool: rebuilding koto_compile binary because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    echo "$rebuild_reason" >&2
    build_log="$(mktemp)"
    if ! (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build \
        -p ivm \
        --bin koto_compile \
        --features kotodama_dynamic_bounds >"$build_log" 2>&1
    ); then
      cat "$build_log" >&2
      rm -f "$build_log"
      return 1
    fi
    rm -f "$build_log"
  fi
  export SORASWAP_KOTO_COMPILE_BIN_READY=1
}

ensure_koto_lint_bin() {
  local lint_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_lint"
  local rebuild=0
  local rebuild_reason=""
  local build_log=""
  if [[ "${SORASWAP_KOTO_LINT_BIN_READY:-0}" == "1" && -x "$lint_bin" ]]; then
    return 0
  fi
  if [[ "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$lint_bin" ]]; then
      echo "koto tool: reusing existing koto_lint binary" >&2
      export SORASWAP_KOTO_LINT_BIN_READY=1
      return 0
    fi
  fi
  if [[ ! -x "$lint_bin" ]]; then
    rebuild=1
    rebuild_reason="koto tool: building koto_lint binary"
  elif \
    path_is_newer_than "$lint_bin" \
      "$SORASWAP_ROOT/scripts/common.sh" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    rebuild=1
    rebuild_reason="koto tool: rebuilding koto_lint binary because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    echo "$rebuild_reason" >&2
    build_log="$(mktemp)"
    if ! (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build \
        -p ivm \
        --bin koto_lint \
        --features kotodama_dynamic_bounds >"$build_log" 2>&1
    ); then
      cat "$build_log" >&2
      rm -f "$build_log"
      return 1
    fi
    rm -f "$build_log"
  fi
  export SORASWAP_KOTO_LINT_BIN_READY=1
}

ensure_koto_tools_bins() {
  ensure_koto_compile_bin
  ensure_koto_lint_bin
}

iroha_cli() {
  ensure_iroha_cli_bin
  local iroha_bin="${SORASWAP_ACTIVE_IROHA_CLI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/iroha}"
  local -a args
  local idx tmp_config=""

  args=("$@")
  idx=1
  while (( idx <= ${#args[@]} )); do
    case "${args[$idx]}" in
      --config|-c)
        if (( idx < ${#args[@]} )); then
          tmp_config="$(materialize_cli_compatible_config "${args[$(( idx + 1 ))]}")"
          args[$(( idx + 1 ))]="$tmp_config"
        fi
        break
        ;;
    esac
    idx=$(( idx + 1 ))
  done

  "$iroha_bin" "${args[@]}"
  idx=$?
  if [[ -n "$tmp_config" && -f "$tmp_config" ]]; then
    rm -f "$tmp_config"
  fi
  return "$idx"
}

iroha_cli_json() {
  iroha_cli --machine --output-format json "$@"
}

normalize_hash_literal() {
  local value="$1"
  value="${value#hash:}"
  value="${value%%\#*}"
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

configure_cli_account_chain_discriminant() {
  local config="$1"
  local chain_override network_prefix

  chain_override="$(chain_id_override_for_config "$config")"
  if [[ -n "$chain_override" ]]; then
    network_prefix="$(network_prefix_for_config "$config")"
    export CHAIN="$chain_override"
    export ACCOUNT_CHAIN_DISCRIMINANT="$network_prefix"
    export IROHA_ACCOUNT_CHAIN_DISCRIMINANT="$network_prefix"
    return 0
  fi

  unset CHAIN || true
  unset ACCOUNT_CHAIN_DISCRIMINANT || true
  unset IROHA_ACCOUNT_CHAIN_DISCRIMINANT || true
}

client_config_or_default() {
  local mode="$1"
  if [[ -n "${SORASWAP_CLIENT_CONFIG:-}" ]]; then
    echo "$SORASWAP_CLIENT_CONFIG"
    return
  fi
  case "$mode" in
    local)
      echo "$DEFAULT_LOCAL_CLIENT"
      ;;
    testnet)
      echo "$DEFAULT_TESTNET_CLIENT"
      ;;
    production)
      if [[ -n "${SORASWAP_PRODUCTION_CLIENT_CONFIG:-}" ]]; then
        echo "$SORASWAP_PRODUCTION_CLIENT_CONFIG"
        return 0
      fi
      if [[ -f "$DEFAULT_PRODUCTION_CLIENT" ]]; then
        echo "$DEFAULT_PRODUCTION_CLIENT"
        return 0
      fi
      echo "production requires SORASWAP_CLIENT_CONFIG or SORASWAP_PRODUCTION_CLIENT_CONFIG (or $DEFAULT_PRODUCTION_CLIENT)" >&2
      return 1
      ;;
    *)
      echo "$mode requires an explicit client config via SORASWAP_CLIENT_CONFIG" >&2
      return 1
      ;;
  esac
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

is_taira_public_config() {
  local config="$1"
  [[ "$(public_env_for_config "$config" 2>/dev/null || true)" == "testnet" ]]
}

public_env_for_config() {
  local config="$1"
  local config_abs

  case "${SORASWAP_PUBLIC_ENV:-}" in
    testnet|production)
      printf '%s\n' "$SORASWAP_PUBLIC_ENV"
      return 0
      ;;
  esac

  config_abs="${config:A}"
  if [[ "$config_abs" == "$DEFAULT_TESTNET_CLIENT:A" || "$config_abs" == "$SORASWAP_ROOT/config/testnet/"* ]]; then
    echo "testnet"
    return 0
  fi

  if [[ "$config_abs" == "$DEFAULT_PRODUCTION_CLIENT:A" || "$config_abs" == "$SORASWAP_ROOT/config/production/"* ]]; then
    echo "production"
    return 0
  fi

  return 1
}

chain_id_override_for_config() {
  local config="$1"
  local public_env

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      printf '%s\n' "$SORASWAP_TESTNET_CHAIN_ID"
      ;;
    production)
      printf '%s\n' "$SORASWAP_PRODUCTION_CHAIN_ID"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

materialize_cli_compatible_config() {
  local source_config="$1"
  local chain torii_url domain public_key private_key ttl_ms status_timeout_ms nonce
  local tmp_config

  chain="$(config_chain_id_from_config "$source_config")"
  torii_url="$(awk -F '"' '/^[[:space:]]*torii_url[[:space:]]*=/ {print $2; exit}' "$source_config")"
  domain="$(awk -F '"' '/^[[:space:]]*domain[[:space:]]*=/ {print $2; exit}' "$source_config")"
  public_key="$(awk -F '"' '/^[[:space:]]*public_key[[:space:]]*=/ {print $2; exit}' "$source_config")"
  private_key="$(awk -F '"' '/^[[:space:]]*private_key[[:space:]]*=/ {print $2; exit}' "$source_config")"
  ttl_ms="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*time_to_live_ms[[:space:]]*=/ { gsub(/[^0-9]/, "", $0); print $0; exit }
  ' "$source_config")"
  status_timeout_ms="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*status_timeout_ms[[:space:]]*=/ { gsub(/[^0-9]/, "", $0); print $0; exit }
  ' "$source_config")"
  nonce="$(awk '
    /^\[transaction\]/ { in_tx = 1; next }
    /^\[/ { in_tx = 0 }
    in_tx && /^[[:space:]]*nonce[[:space:]]*=/ {
      sub(/^[[:space:]]*nonce[[:space:]]*=[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$source_config")"

  if [[ "$domain" != *.* ]]; then
    domain="${domain}.universal"
  fi
  ttl_ms="${ttl_ms:-120000}"
  status_timeout_ms="${status_timeout_ms:-120000}"
  nonce="${nonce:-false}"

  tmp_config="$(mktemp -t soraswap-cli-config)"
  printf '%s\n' \
    "chain = \"$chain\"" \
    "torii_url = \"$torii_url\"" \
    "" \
    "[account]" \
    "domain = \"$domain\"" \
    "public_key = \"$public_key\"" \
    "private_key = \"$private_key\"" \
    "" \
    "[transaction]" \
    "time_to_live_ms = $ttl_ms" \
    "status_timeout_ms = $status_timeout_ms" \
    "nonce = $nonce" \
    > "$tmp_config"

  echo "$tmp_config"
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

contracts_snapshot_latest_path_for_env() {
  local env="$1"
  echo "$(deployments_dir_for_env "$env")/contracts.latest.json"
}

contracts_snapshot_timestamped_path_for_env() {
  local env="$1"
  local timestamp="$2"
  echo "$(deployments_dir_for_env "$env")/contracts.${timestamp}.json"
}

current_or_saved_chain_fingerprint_json_for_env() {
  local env="$1"
  local latest

  if [[ -n "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]]; then
    normalize_json_or_null "$SORASWAP_CHAIN_FINGERPRINT_JSON"
    return 0
  fi

  latest="$(chain_snapshot_latest_path_for_env "$env")"
  if [[ -f "$latest" ]]; then
    jq -c '{torii_url, chain, block_1_hash}' "$latest"
    return 0
  fi

  echo 'null'
}

deployment_records_snapshot_json_for_env() {
  local env="$1"
  local generated_at="${2:-$(utc_timestamp)}"
  local chain_fingerprint_json contracts_json

  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  contracts_json="$(deployment_records_json_for_env "$env")"

  jq -cn \
    --arg generated_at "$generated_at" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    --argjson contracts "$contracts_json" \
    '{
      generated_at: $generated_at,
      chain_fingerprint: $chain_fingerprint,
      contracts: $contracts
    }'
}

refresh_deployment_records_snapshot_latest_for_env() {
  local env="$1"
  local report_dir latest snapshot_json

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(contracts_snapshot_latest_path_for_env "$env")"
  mkdir -p "$report_dir"
  snapshot_json="$(deployment_records_snapshot_json_for_env "$env")" || return 1

  if [[ -f "$latest" ]] \
    && jq -e --argjson current "$snapshot_json" \
      'del(.generated_at) == ($current | del(.generated_at))' \
      "$latest" >/dev/null 2>&1; then
    cat "$latest"
    return 0
  fi

  printf '%s\n' "$snapshot_json" > "$latest"
  printf '%s\n' "$snapshot_json"
}

current_chain_fingerprint_json() {
  local config="$1"
  local torii_base chain_id block_hash response
  local attempt=1
  local attempts="${SORASWAP_CHAIN_FINGERPRINT_ATTEMPTS:-15}"
  local sleep_seconds="${SORASWAP_CHAIN_FINGERPRINT_SLEEP_SECS:-1}"

  torii_base="$(torii_base_from_config "$config")"
  chain_id="$(config_chain_id_from_config "$config")"
  while (( attempt <= attempts )); do
    if response="$(curl -fsS \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      "$torii_base/v1/explorer/blocks/1" \
      2>/dev/null)"; then
      if block_hash="$(jq -er '.hash // empty' 2>/dev/null <<<"$response")" \
        && [[ -n "$block_hash" ]]; then
        break
      fi
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  if [[ -z "${block_hash:-}" ]]; then
    echo "failed to fetch chain fingerprint from $torii_base/v1/explorer/blocks/1 after ${attempts} attempts" >&2
    return 1
  fi

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
  local normalized_fingerprint_json

  if [[ ! -f "$snapshot_path" ]]; then
    return 1
  fi

  normalized_fingerprint_json="$(normalize_json_or_null "$fingerprint_json")" || return 1
  if [[ "$normalized_fingerprint_json" == "null" ]]; then
    return 1
  fi

  jq -e \
    --argjson current "$normalized_fingerprint_json" \
    '.chain == $current.chain and .block_1_hash == $current.block_1_hash' \
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
  local fingerprint_json

  if ! fingerprint_json="$(current_chain_fingerprint_json "$config")"; then
    echo "unable to derive chain fingerprint for ${env} from $(torii_base_from_config "$config")" >&2
    return 1
  fi
  SORASWAP_CHAIN_FINGERPRINT_JSON="$fingerprint_json"
  export SORASWAP_CHAIN_FINGERPRINT_JSON
  if [[ "$env" != "local" ]]; then
    archive_deployment_evidence_for_chain_reset "$env" "$config"
  fi
  write_chain_fingerprint_snapshot "$env" "$config"
}

config_chain_id_from_config() {
  local config="$1"
  local chain_override
  if [[ -n "${CHAIN:-}" ]]; then
    printf '%s\n' "$CHAIN"
    return 0
  fi

  chain_override="$(chain_id_override_for_config "$config")"
  if [[ -n "$chain_override" ]]; then
    printf '%s\n' "$chain_override"
    return 0
  fi
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
    production)
      echo "${SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT:-${SORASWAP_CHAIN_DISCRIMINANT:-753}}"
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
  local chain_fingerprint_json

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(deploy_report_latest_path_for_env "$env")"
  timestamp="$(utc_timestamp)"
  timestamped="$report_dir/deploy.${timestamp}.json"
  mkdir -p "$report_dir"
  SORASWAP_DEPLOY_REPORT_TIMESTAMPED="$timestamped"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  jq -n \
    --arg generated_at "$timestamp" \
    --arg authority "${SORASWAP_AUTHORITY:-}" \
    --arg client_config "$config" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
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

nested_call_probe_latest_path_for_env() {
  local env="$1"
  echo "$(deployments_dir_for_env "$env")/nested_call_probe.latest.json"
}

nested_call_probe_matches_current_chain() {
  local report_path="$1"
  local chain_fingerprint_json="${2:-null}"

  [[ -f "$report_path" ]] || return 1
  jq -e \
    --argjson chain "$chain_fingerprint_json" \
    '
      ($chain != null)
      and (.chain_fingerprint != null)
      and .chain_fingerprint.chain == $chain.chain
      and .chain_fingerprint.block_1_hash == $chain.block_1_hash
    ' \
    "$report_path" >/dev/null
}

extract_probe_tx_hash() {
  local output="${1:-}"
  local tx_hash

  tx_hash="$(sed -n 's/.* transaction \([0-9a-f]\{64\}\).*/\1/p' <<<"$output" | tail -n 1)"
  if [[ -n "$tx_hash" ]]; then
    printf '%s\n' "$tx_hash"
  fi
}

run_nested_call_probe() {
  local env="$1"
  local config="$2"
  local timestamp report_dir latest_report timestamped_report
  local chain_fingerprint_json compiler_bin stamp probe_dir
  local bytes_probe_src callee_src caller_src asset_callee_src asset_middle_src asset_caller_src
  local bytes_probe_to callee_to caller_to asset_callee_to asset_middle_to asset_caller_to
  local bytes_probe_manifest callee_manifest caller_manifest asset_callee_manifest asset_middle_manifest asset_caller_manifest
  local bytes_probe_code_hash callee_code_hash caller_code_hash asset_callee_code_hash asset_middle_code_hash asset_caller_code_hash
  local bytes_probe_alias callee_alias caller_alias asset_callee_alias asset_middle_alias asset_caller_alias
  local bytes_probe_response callee_response caller_response asset_callee_response asset_middle_response asset_caller_response
  local bytes_probe_contract callee_contract caller_contract asset_callee_contract asset_middle_contract asset_caller_contract
  local asset_callee_subject asset_middle_subject asset_caller_subject
  local bytes_bind_output bytes_bind_status bytes_bind_tx_hash
  local bytes_view_output bytes_view_status bytes_view_result_hex
  local bind_output bind_status ping_output ping_status bind_tx_hash ping_tx_hash
  local asset_bind_callee_output asset_bind_callee_status asset_bind_callee_tx_hash
  local asset_bind_middle_output asset_bind_middle_status asset_bind_middle_tx_hash
  local asset_bind_caller_output asset_bind_caller_status asset_bind_caller_tx_hash
  local asset_relay_output asset_relay_status asset_relay_tx_hash
  local asset_balance_check_status asset_balance_check_output
  local probe_asset_alias probe_asset_id probe_amount
  local asset_callee_balance asset_middle_balance asset_caller_balance
  local state_bytes_roundtrip_supported nested_call_supported nested_asset_ops_supported supported
  local summary blocked_reason report_json

  ensure_client "$config"
  ensure_authority "$config"
  ensure_koto_compile_bin >/dev/null
  compiler_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_compile"
  timestamp="$(utc_timestamp)"
  stamp="$(env TZ=UTC date '+%Y%m%d%H%M%S')"
  report_dir="$(deployments_dir_for_env "$env")"
  latest_report="$(nested_call_probe_latest_path_for_env "$env")"
  timestamped_report="$report_dir/nested_call_probe.${timestamp}.json"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap_nested_probe.XXXXXX")"
  mkdir -p "$report_dir"

  bytes_probe_src="$probe_dir/bytes_probe.ko"
  callee_src="$probe_dir/callee.ko"
  caller_src="$probe_dir/caller.ko"
  asset_callee_src="$probe_dir/asset_callee.ko"
  asset_middle_src="$probe_dir/asset_middle.ko"
  asset_caller_src="$probe_dir/asset_caller.ko"
  bytes_probe_to="$probe_dir/bytes_probe.to"
  callee_to="$probe_dir/callee.to"
  caller_to="$probe_dir/caller.to"
  asset_callee_to="$probe_dir/asset_callee.to"
  asset_middle_to="$probe_dir/asset_middle.to"
  asset_caller_to="$probe_dir/asset_caller.to"
  bytes_probe_manifest="$probe_dir/bytes_probe.manifest.json"
  callee_manifest="$probe_dir/callee.manifest.json"
  caller_manifest="$probe_dir/caller.manifest.json"
  asset_callee_manifest="$probe_dir/asset_callee.manifest.json"
  asset_middle_manifest="$probe_dir/asset_middle.manifest.json"
  asset_caller_manifest="$probe_dir/asset_caller.manifest.json"

  cat >"$bytes_probe_src" <<'EOF'
seiyaku NestedProbeBytesState {
  state bytes Stored;

  #[access(read="*", write="*")]
  kotoage fn bind_value(value: bytes) permission(Admin) {
    Stored = value;
  }

  view fn get_value() -> bytes {
    return Stored;
  }
}
EOF

  cat >"$callee_src" <<'EOF'
seiyaku NestedProbeCallee {
  #[access(read="*", write="*")]
  kotoage fn noop() -> int {
    return 13;
  }
}
EOF

  cat >"$caller_src" <<'EOF'
seiyaku NestedProbeCaller {
  state bytes CalleeContract;
  state bytes CalleeEntrypoint;

  #[access(read="*", write="*")]
  kotoage fn bind_target(callee_contract: bytes, callee_entrypoint: bytes) permission(Admin) {
    CalleeContract = callee_contract;
    CalleeEntrypoint = callee_entrypoint;
  }

  #[access(read="*", write="*")]
  kotoage fn ping() -> int permission(Admin) {
    let payload = json_object();
    return decode_int(call_contract(CalleeContract, CalleeEntrypoint, payload));
  }
}
EOF

  cat >"$asset_callee_src" <<'EOF'
seiyaku NestedAssetProbeCallee {
  state AssetDefinitionId ProbeAsset;
  state AccountId CalleeContractId;
  state int Initialized;

  fn assert_initialized() {
    assert(Initialized == 1, "callee not initialized");
  }

  #[access(read="*", write="*")]
  kotoage fn bind_contract(contract_id: AccountId, asset: AssetDefinitionId) permission(Admin) {
    ProbeAsset = asset;
    CalleeContractId = contract_id;
    Initialized = 1;
  }

  #[access(read="*", write="*")]
  kotoage fn receive(amount: int) -> int permission(AssetOps) {
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), CalleeContractId, ProbeAsset, amount);
    return amount;
  }
}
EOF

  cat >"$asset_middle_src" <<'EOF'
seiyaku NestedAssetProbeMiddle {
  state AssetDefinitionId ProbeAsset;
  state AccountId MiddleContractId;
  state bytes CalleeContract;
  state int Initialized;

  fn assert_initialized() {
    assert(Initialized == 1, "middle not initialized");
  }

  #[access(read="*", write="*")]
  kotoage fn bind_target(contract_id: AccountId,
                         callee_contract: bytes,
                         asset: AssetDefinitionId) permission(Admin) {
    MiddleContractId = contract_id;
    CalleeContract = callee_contract;
    ProbeAsset = asset;
    Initialized = 1;
  }

  #[access(read="*", write="*")]
  kotoage fn relay(amount: int) -> int permission(AssetOps) {
    let payload = json_object();
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), MiddleContractId, ProbeAsset, amount);
    let payload = json_set_int(payload, name("amount"), amount);
    return decode_int(call_contract(CalleeContract, "receive", payload));
  }
}
EOF

  cat >"$asset_caller_src" <<'EOF'
seiyaku NestedAssetProbeCaller {
  state AssetDefinitionId ProbeAsset;
  state AccountId CallerContractId;
  state bytes MiddleContract;
  state int Initialized;

  fn assert_initialized() {
    assert(Initialized == 1, "caller not initialized");
  }

  #[access(read="*", write="*")]
  kotoage fn bind_target(contract_id: AccountId,
                         middle_contract: bytes,
                         asset: AssetDefinitionId) permission(Admin) {
    CallerContractId = contract_id;
    MiddleContract = middle_contract;
    ProbeAsset = asset;
    Initialized = 1;
  }

  #[access(read="*", write="*")]
  kotoage fn relay(amount: int) -> int permission(AssetOps) {
    let payload = json_object();
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), CallerContractId, ProbeAsset, amount);
    let payload = json_set_int(payload, name("amount"), amount);
    return decode_int(call_contract(MiddleContract, "relay", payload));
  }
}
EOF

  (
    cd "$SORASWAP_IROHA_ROOT"
    "$compiler_bin" "$bytes_probe_src" --out "$bytes_probe_to" --manifest-out "$bytes_probe_manifest" --abi 1 >/dev/null
    "$compiler_bin" "$callee_src" --out "$callee_to" --manifest-out "$callee_manifest" --abi 1 >/dev/null
    "$compiler_bin" "$caller_src" --out "$caller_to" --manifest-out "$caller_manifest" --abi 1 >/dev/null
    "$compiler_bin" "$asset_callee_src" --out "$asset_callee_to" --manifest-out "$asset_callee_manifest" --abi 1 >/dev/null
    "$compiler_bin" "$asset_middle_src" --out "$asset_middle_to" --manifest-out "$asset_middle_manifest" --abi 1 >/dev/null
    "$compiler_bin" "$asset_caller_src" --out "$asset_caller_to" --manifest-out "$asset_caller_manifest" --abi 1 >/dev/null
  )
  bytes_probe_code_hash="$(manifest_code_hash_hex "$bytes_probe_manifest")"
  callee_code_hash="$(manifest_code_hash_hex "$callee_manifest")"
  caller_code_hash="$(manifest_code_hash_hex "$caller_manifest")"
  asset_callee_code_hash="$(manifest_code_hash_hex "$asset_callee_manifest")"
  asset_middle_code_hash="$(manifest_code_hash_hex "$asset_middle_manifest")"
  asset_caller_code_hash="$(manifest_code_hash_hex "$asset_caller_manifest")"

  bytes_probe_alias="nestedbytes${stamp}::scratch.universal"
  callee_alias="nestedcalle${stamp}::scratch.universal"
  caller_alias="nestedcaller${stamp}::scratch.universal"
  asset_callee_alias="nestedassetcalle${stamp}::scratch.universal"
  asset_middle_alias="nestedassetmidle${stamp}::scratch.universal"
  asset_caller_alias="nestedassetcaller${stamp}::scratch.universal"
  probe_asset_alias="$SORASWAP_BASE_ASSET_ALIAS"
  probe_asset_id="$(asset_definition_id_for_alias "$config" "$probe_asset_alias")"
  probe_amount=1
  bytes_probe_response="$(submit_contract_deploy_file "$config" "$bytes_probe_to" "$bytes_probe_alias")"
  callee_response="$(submit_contract_deploy_file "$config" "$callee_to" "$callee_alias")"
  caller_response="$(submit_contract_deploy_file "$config" "$caller_to" "$caller_alias")"
  asset_callee_response="$(submit_contract_deploy_file "$config" "$asset_callee_to" "$asset_callee_alias")"
  asset_middle_response="$(submit_contract_deploy_file "$config" "$asset_middle_to" "$asset_middle_alias")"
  asset_caller_response="$(submit_contract_deploy_file "$config" "$asset_caller_to" "$asset_caller_alias")"
  confirm_contract_deploy_response "$config" "$bytes_probe_response" "nested_probe.bytes" "$bytes_probe_code_hash" >/dev/null
  confirm_contract_deploy_response "$config" "$callee_response" "nested_probe.callee" "$callee_code_hash" >/dev/null
  confirm_contract_deploy_response "$config" "$caller_response" "nested_probe.caller" "$caller_code_hash" >/dev/null
  confirm_contract_deploy_response "$config" "$asset_callee_response" "nested_probe.asset_callee" "$asset_callee_code_hash" >/dev/null
  confirm_contract_deploy_response "$config" "$asset_middle_response" "nested_probe.asset_middle" "$asset_middle_code_hash" >/dev/null
  confirm_contract_deploy_response "$config" "$asset_caller_response" "nested_probe.asset_caller" "$asset_caller_code_hash" >/dev/null
  bytes_probe_contract="$(jq -r '.contract_address' <<<"$bytes_probe_response")"
  callee_contract="$(jq -r '.contract_address' <<<"$callee_response")"
  caller_contract="$(jq -r '.contract_address' <<<"$caller_response")"
  asset_callee_contract="$(jq -r '.contract_address' <<<"$asset_callee_response")"
  asset_middle_contract="$(jq -r '.contract_address' <<<"$asset_middle_response")"
  asset_caller_contract="$(jq -r '.contract_address' <<<"$asset_caller_response")"
  asset_callee_subject="$(contract_subject_account_for_literal "$config" "$asset_callee_contract")"
  asset_middle_subject="$(contract_subject_account_for_literal "$config" "$asset_middle_contract")"
  asset_caller_subject="$(contract_subject_account_for_literal "$config" "$asset_caller_contract")"

  if bytes_bind_output="$(
    call_contract_and_wait \
      "$config" \
      "$bytes_probe_contract" \
      "bind_value" \
      "$(jq -cn --arg value "noop" '{ value: $value }')" 2>&1
  )"; then
    bytes_bind_status="completed"
    bytes_bind_tx_hash="$bytes_bind_output"
  else
    bytes_bind_status="failed"
    bytes_bind_tx_hash="$(extract_probe_tx_hash "$bytes_bind_output")"
  fi

  if [[ "$bytes_bind_status" == "completed" ]]; then
    if bytes_view_output="$(submit_contract_view "$config" "$bytes_probe_contract" "get_value" 2>&1)"; then
      bytes_view_result_hex="$(jq -r '.result // empty' <<<"$bytes_view_output" 2>/dev/null || true)"
      if [[ "$bytes_view_result_hex" == "0x6e6f6f70" ]]; then
        bytes_view_status="completed"
      else
        bytes_view_status="failed"
        bytes_view_output="unexpected bytes roundtrip result: ${bytes_view_result_hex:-<empty>} response=$bytes_view_output"
      fi
    else
      bytes_view_status="failed"
      bytes_view_result_hex=""
    fi
  else
    bytes_view_status="skipped"
    bytes_view_output="probe skipped because bind_value failed"
    bytes_view_result_hex=""
  fi

  state_bytes_roundtrip_supported=false
  if [[ "$bytes_bind_status" == "completed" && "$bytes_view_status" == "completed" ]]; then
    state_bytes_roundtrip_supported=true
  fi

  if bind_output="$(
    call_contract_and_wait \
      "$config" \
      "$caller_contract" \
      "bind_target" \
      "$(jq -cn \
        --arg callee_contract "$callee_contract" \
        --arg callee_entrypoint "noop" \
        '{ callee_contract: $callee_contract, callee_entrypoint: $callee_entrypoint }')" 2>&1
  )"; then
    bind_status="completed"
    bind_tx_hash="$bind_output"
  else
    bind_status="failed"
    bind_tx_hash="$(extract_probe_tx_hash "$bind_output")"
  fi

  if [[ "$bind_status" == "completed" ]]; then
    if ping_output="$(call_contract_and_wait "$config" "$caller_contract" "ping" null 2>&1)"; then
      ping_status="completed"
      ping_tx_hash="$ping_output"
    else
      ping_status="failed"
      ping_tx_hash="$(extract_probe_tx_hash "$ping_output")"
    fi
  else
    ping_status="skipped"
    ping_output="probe skipped because bind_target failed"
    ping_tx_hash=""
  fi

  nested_call_supported=false
  if [[ "$bind_status" == "completed" && "$ping_status" == "completed" ]]; then
    nested_call_supported=true
  fi

  if asset_bind_callee_output="$(
    call_contract_and_wait \
      "$config" \
      "$asset_callee_contract" \
      "bind_contract" \
      "$(jq -cn \
        --arg contract_id "$asset_callee_subject" \
        --arg asset "$probe_asset_id" \
        '{ contract_id: $contract_id, asset: $asset }')" 2>&1
  )"; then
    asset_bind_callee_status="completed"
    asset_bind_callee_tx_hash="$asset_bind_callee_output"
  else
    asset_bind_callee_status="failed"
    asset_bind_callee_tx_hash="$(extract_probe_tx_hash "$asset_bind_callee_output")"
  fi

  if [[ "$asset_bind_callee_status" == "completed" ]]; then
    if asset_bind_middle_output="$(
      call_contract_and_wait \
        "$config" \
        "$asset_middle_contract" \
        "bind_target" \
        "$(jq -cn \
          --arg contract_id "$asset_middle_subject" \
          --arg callee_contract "$asset_callee_contract" \
          --arg asset "$probe_asset_id" \
          '{ contract_id: $contract_id, callee_contract: $callee_contract, asset: $asset }')" 2>&1
    )"; then
      asset_bind_middle_status="completed"
      asset_bind_middle_tx_hash="$asset_bind_middle_output"
    else
      asset_bind_middle_status="failed"
      asset_bind_middle_tx_hash="$(extract_probe_tx_hash "$asset_bind_middle_output")"
    fi
  else
    asset_bind_middle_status="skipped"
    asset_bind_middle_output="probe skipped because asset callee bind failed"
    asset_bind_middle_tx_hash=""
  fi

  if [[ "$asset_bind_middle_status" == "completed" ]]; then
    if asset_bind_caller_output="$(
      call_contract_and_wait \
        "$config" \
        "$asset_caller_contract" \
        "bind_target" \
        "$(jq -cn \
          --arg contract_id "$asset_caller_subject" \
          --arg middle_contract "$asset_middle_contract" \
          --arg asset "$probe_asset_id" \
          '{ contract_id: $contract_id, middle_contract: $middle_contract, asset: $asset }')" 2>&1
    )"; then
      asset_bind_caller_status="completed"
      asset_bind_caller_tx_hash="$asset_bind_caller_output"
    else
      asset_bind_caller_status="failed"
      asset_bind_caller_tx_hash="$(extract_probe_tx_hash "$asset_bind_caller_output")"
    fi
  else
    asset_bind_caller_status="skipped"
    asset_bind_caller_output="probe skipped because asset middle bind failed"
    asset_bind_caller_tx_hash=""
  fi

  if [[ "$asset_bind_caller_status" == "completed" ]]; then
    if asset_relay_output="$(
      call_contract_and_wait \
        "$config" \
        "$asset_caller_contract" \
        "relay" \
        "$(jq -cn --argjson amount "$probe_amount" '{ amount: $amount }')" 2>&1
    )"; then
      asset_relay_status="completed"
      asset_relay_tx_hash="$asset_relay_output"
    else
      asset_relay_status="failed"
      asset_relay_tx_hash="$(extract_probe_tx_hash "$asset_relay_output")"
    fi
  else
    asset_relay_status="skipped"
    asset_relay_output="probe skipped because asset caller bind failed"
    asset_relay_tx_hash=""
  fi

  if [[ "$asset_relay_status" == "completed" ]]; then
    asset_callee_balance="$(asset_value_for_account_id "$config" "$probe_asset_id" "$asset_callee_subject")"
    asset_middle_balance="$(asset_value_for_account_id "$config" "$probe_asset_id" "$asset_middle_subject")"
    asset_caller_balance="$(asset_value_for_account_id "$config" "$probe_asset_id" "$asset_caller_subject")"
    if [[ "$asset_callee_balance" == "$probe_amount" \
      && "$asset_middle_balance" == "0" \
      && "$asset_caller_balance" == "0" ]]; then
      asset_balance_check_status="completed"
      asset_balance_check_output="multi-hop nested asset relay moved ${probe_amount} of ${probe_asset_alias} into callee subject ${asset_callee_subject}"
    else
      asset_balance_check_status="failed"
      asset_balance_check_output="unexpected multi-hop nested asset relay balances: callee=${asset_callee_balance:-<empty>} middle=${asset_middle_balance:-<empty>} caller=${asset_caller_balance:-<empty>} expected callee=${probe_amount} middle=0 caller=0"
    fi
  else
    asset_callee_balance="0"
    asset_middle_balance="0"
    asset_caller_balance="0"
    asset_balance_check_status="skipped"
    asset_balance_check_output="probe skipped because nested asset relay failed"
  fi

  nested_asset_ops_supported=false
  if [[ "$asset_bind_callee_status" == "completed" \
    && "$asset_bind_middle_status" == "completed" \
    && "$asset_bind_caller_status" == "completed" \
    && "$asset_relay_status" == "completed" \
    && "$asset_balance_check_status" == "completed" ]]; then
    nested_asset_ops_supported=true
  fi

  supported=false
  if [[ "$state_bytes_roundtrip_supported" == true \
    && "$nested_call_supported" == true \
    && "$nested_asset_ops_supported" == true ]]; then
    supported=true
  fi

  if [[ "$supported" == true ]]; then
    summary="state bytes roundtrip, minimal nested call_contract(...), and multi-hop nested AssetOps relay all succeeded"
    blocked_reason=""
  elif [[ "$state_bytes_roundtrip_supported" == true && "$nested_call_supported" == false ]]; then
    summary="state bytes roundtrip succeeded but minimal nested call_contract(...) failed"
    blocked_reason="public Taira runtime still rejects nested call_contract(...) even though persisted bytes state roundtrip works"
  elif [[ "$state_bytes_roundtrip_supported" == true \
    && "$nested_call_supported" == true \
    && "$nested_asset_ops_supported" == false ]]; then
    summary="state bytes roundtrip and minimal nested call_contract(...) succeeded but multi-hop nested AssetOps relay failed"
    blocked_reason="public Taira runtime still rejects or mis-executes multi-hop nested AssetOps transfers across call_contract(...) boundaries"
  elif [[ "$state_bytes_roundtrip_supported" == false && "$nested_call_supported" == false ]]; then
    summary="state bytes roundtrip failed and minimal nested call_contract(...) failed"
    blocked_reason="public Taira runtime did not satisfy the prerequisite bytes-state roundtrip or nested call_contract(...) capability"
  elif [[ "$state_bytes_roundtrip_supported" == false ]]; then
    summary="minimal nested call_contract(...) succeeded but bytes state roundtrip failed"
    blocked_reason="probe evidence is inconsistent: nested call passed without a successful bytes-state roundtrip"
  else
    summary="probe ended in an unknown state"
    blocked_reason="probe ended in an unknown state"
  fi

  report_json="$(jq -n \
    --arg generated_at "$timestamp" \
    --arg environment "$env" \
    --arg authority "${SORASWAP_AUTHORITY:-}" \
    --arg client_config "$config" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --arg compiler_bin "$compiler_bin" \
    --arg probe_dir "$probe_dir" \
    --arg bytes_probe_alias "$bytes_probe_alias" \
    --arg callee_alias "$callee_alias" \
    --arg caller_alias "$caller_alias" \
    --arg bytes_probe_contract "$bytes_probe_contract" \
    --arg callee_contract "$callee_contract" \
    --arg caller_contract "$caller_contract" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    --argjson state_bytes_roundtrip_supported "$state_bytes_roundtrip_supported" \
    --argjson nested_call_supported "$nested_call_supported" \
    --argjson nested_asset_ops_supported "$nested_asset_ops_supported" \
    --argjson supported "$supported" \
    --arg summary "$summary" \
    --arg blocked_reason "$blocked_reason" \
    --arg bytes_bind_status "$bytes_bind_status" \
    --arg bytes_bind_output "$bytes_bind_output" \
    --arg bytes_bind_tx_hash "$bytes_bind_tx_hash" \
    --arg bytes_view_status "$bytes_view_status" \
    --arg bytes_view_output "$bytes_view_output" \
    --arg bytes_view_result_hex "$bytes_view_result_hex" \
    --arg bind_status "$bind_status" \
    --arg bind_output "$bind_output" \
    --arg bind_tx_hash "$bind_tx_hash" \
    --arg ping_status "$ping_status" \
    --arg ping_output "$ping_output" \
    --arg ping_tx_hash "$ping_tx_hash" \
    --arg probe_asset_alias "$probe_asset_alias" \
    --arg probe_asset_id "$probe_asset_id" \
    --arg asset_callee_alias "$asset_callee_alias" \
    --arg asset_middle_alias "$asset_middle_alias" \
    --arg asset_caller_alias "$asset_caller_alias" \
    --arg asset_callee_contract "$asset_callee_contract" \
    --arg asset_middle_contract "$asset_middle_contract" \
    --arg asset_caller_contract "$asset_caller_contract" \
    --arg asset_callee_subject "$asset_callee_subject" \
    --arg asset_middle_subject "$asset_middle_subject" \
    --arg asset_caller_subject "$asset_caller_subject" \
    --argjson probe_amount "$probe_amount" \
    --arg asset_bind_callee_status "$asset_bind_callee_status" \
    --arg asset_bind_callee_output "$asset_bind_callee_output" \
    --arg asset_bind_callee_tx_hash "$asset_bind_callee_tx_hash" \
    --arg asset_bind_middle_status "$asset_bind_middle_status" \
    --arg asset_bind_middle_output "$asset_bind_middle_output" \
    --arg asset_bind_middle_tx_hash "$asset_bind_middle_tx_hash" \
    --arg asset_bind_caller_status "$asset_bind_caller_status" \
    --arg asset_bind_caller_output "$asset_bind_caller_output" \
    --arg asset_bind_caller_tx_hash "$asset_bind_caller_tx_hash" \
    --arg asset_relay_status "$asset_relay_status" \
    --arg asset_relay_output "$asset_relay_output" \
    --arg asset_relay_tx_hash "$asset_relay_tx_hash" \
    --arg asset_balance_check_status "$asset_balance_check_status" \
    --arg asset_balance_check_output "$asset_balance_check_output" \
    --arg asset_callee_balance "$asset_callee_balance" \
    --arg asset_middle_balance "$asset_middle_balance" \
    --arg asset_caller_balance "$asset_caller_balance" \
    '{
      generated_at: $generated_at,
      environment: $environment,
      authority: $authority,
      client_config: $client_config,
      torii_url: $torii_url,
      chain_fingerprint: $chain_fingerprint,
      state_bytes_roundtrip_supported: $state_bytes_roundtrip_supported,
      nested_call_supported: $nested_call_supported,
      nested_asset_ops_supported: $nested_asset_ops_supported,
      supported: $supported,
      summary: $summary,
      blocked_reason: (if $blocked_reason == "" then null else $blocked_reason end),
      compiler_bin: $compiler_bin,
      probe_dir: $probe_dir,
      probe_asset: {
        alias: $probe_asset_alias,
        asset_definition_id: $probe_asset_id,
        relay_amount: $probe_amount
      },
      contracts: {
        bytes_probe: {
          alias: $bytes_probe_alias,
          contract_address: $bytes_probe_contract
        },
        callee: {
          alias: $callee_alias,
          contract_address: $callee_contract
        },
        caller: {
          alias: $caller_alias,
          contract_address: $caller_contract
        },
        asset_callee: {
          alias: $asset_callee_alias,
          contract_address: $asset_callee_contract,
          subject_account: $asset_callee_subject
        },
        asset_middle: {
          alias: $asset_middle_alias,
          contract_address: $asset_middle_contract,
          subject_account: $asset_middle_subject
        },
        asset_caller: {
          alias: $asset_caller_alias,
          contract_address: $asset_caller_contract,
          subject_account: $asset_caller_subject
        }
      },
      stages: {
        bytes_bind_value: {
          status: $bytes_bind_status,
          tx_hash: (if $bytes_bind_tx_hash == "" then null else $bytes_bind_tx_hash end),
          output: $bytes_bind_output
        },
        bytes_view_get_value: {
          status: $bytes_view_status,
          result_hex: (if $bytes_view_result_hex == "" then null else $bytes_view_result_hex end),
          output: $bytes_view_output
        },
        bind_target: {
          status: $bind_status,
          tx_hash: (if $bind_tx_hash == "" then null else $bind_tx_hash end),
          output: $bind_output
        },
        ping: {
          status: $ping_status,
          tx_hash: (if $ping_tx_hash == "" then null else $ping_tx_hash end),
          output: $ping_output
        },
        asset_bind_callee: {
          status: $asset_bind_callee_status,
          tx_hash: (if $asset_bind_callee_tx_hash == "" then null else $asset_bind_callee_tx_hash end),
          output: $asset_bind_callee_output
        },
        asset_bind_middle: {
          status: $asset_bind_middle_status,
          tx_hash: (if $asset_bind_middle_tx_hash == "" then null else $asset_bind_middle_tx_hash end),
          output: $asset_bind_middle_output
        },
        asset_bind_caller: {
          status: $asset_bind_caller_status,
          tx_hash: (if $asset_bind_caller_tx_hash == "" then null else $asset_bind_caller_tx_hash end),
          output: $asset_bind_caller_output
        },
        asset_relay: {
          status: $asset_relay_status,
          tx_hash: (if $asset_relay_tx_hash == "" then null else $asset_relay_tx_hash end),
          output: $asset_relay_output
        },
        asset_balance_check: {
          status: $asset_balance_check_status,
          output: $asset_balance_check_output,
          callee_balance: $asset_callee_balance,
          middle_balance: $asset_middle_balance,
          caller_balance: $asset_caller_balance
        }
      }
    }')"

  printf '%s\n' "$report_json" > "$latest_report"
  printf '%s\n' "$report_json" > "$timestamped_report"
  printf '%s\n' "$report_json"
}

ensure_nested_call_runtime_supported() {
  local env="$1"
  local config="$2"
  local latest_report chain_fingerprint_json probe_json

  latest_report="$(nested_call_probe_latest_path_for_env "$env")"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  if nested_call_probe_matches_current_chain "$latest_report" "$chain_fingerprint_json" \
    && jq -e '.supported == true' "$latest_report" >/dev/null 2>&1; then
    cat "$latest_report"
    return 0
  fi

  probe_json="$(run_nested_call_probe "$env" "$config")"
  if jq -e '.supported == true' <<<"$probe_json" >/dev/null; then
    printf '%s\n' "$probe_json"
    return 0
  fi

  if jq -e '.state_bytes_roundtrip_supported == true and .nested_call_supported == false' <<<"$probe_json" >/dev/null 2>&1; then
    echo "nested call runtime probe failed for $env: state bytes roundtrip passed but minimal nested call_contract(...) still failed; see $(nested_call_probe_latest_path_for_env "$env")" >&2
  elif jq -e '.state_bytes_roundtrip_supported == true and .nested_call_supported == true and .nested_asset_ops_supported == false' <<<"$probe_json" >/dev/null 2>&1; then
    echo "nested call runtime probe failed for $env: basic nested call_contract(...) passed but nested AssetOps relay failed; see $(nested_call_probe_latest_path_for_env "$env")" >&2
  else
    echo "nested call runtime probe failed for $env; see $(nested_call_probe_latest_path_for_env "$env")" >&2
  fi
  return 1
}

deploy_progress_note() {
  local contract_key="$1"
  local stage="$2"
  local detail="${3:-}"

  if [[ ! -t 2 ]]; then
    return 0
  fi

  if [[ -n "$detail" ]]; then
    printf '  [%s] %s: %s\n' "$contract_key" "$stage" "$detail" >&2
  else
    printf '  [%s] %s\n' "$contract_key" "$stage" >&2
  fi
}

account_public_key_from_config() {
  local config="$1"
  awk -F '"' '/^public_key *= / {print $2; exit}' "$config"
}

network_prefix_for_config() {
  local config="$1"
  local public_env

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      echo "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT"
      return 0
      ;;
    production)
      echo "${SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT:-${SORASWAP_CHAIN_DISCRIMINANT:-753}}"
      return 0
      ;;
  esac

  echo "${SORASWAP_ADDRESS_NETWORK_PREFIX:-${SORASWAP_CHAIN_DISCRIMINANT:-753}}"
}

authority_from_config() {
  local config="$1"
  local public_key network_prefix
  public_key="$(account_public_key_from_config "$config")"
  if [[ -z "$public_key" ]]; then
    return 1
  fi

  network_prefix="$(network_prefix_for_config "$config")"

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
  local torii_base encoded_account http_code

  if iroha_cli_json --config "$config" ledger account get --id "$account_id" >/dev/null 2>&1; then
    return 0
  fi

  torii_base="$(torii_base_from_config "$config")"
  encoded_account="$(uri_encode "$account_id")"
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    "$torii_base/v1/accounts/${encoded_account}" || true)"
  [[ "$http_code" == "200" ]]
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
    --id "$account_id"
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
    ledger account register --id "$account_id" 2>&1)"; then
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
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
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
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
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

wait_for_positive_asset_balance_id() {
  local config="$1"
  local asset_id="$2"
  local account="$3"
  local attempts="${4:-60}"
  local sleep_seconds="${5:-1}"
  local attempt=1
  local current="0"

  while (( attempt <= attempts )); do
    current="$(asset_value_for_account_id "$config" "$asset_id" "$account")"
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

max_deploy_nonce_for_env_records() {
  local env="$1"
  local fingerprint_json="$2"
  local record_path nonce max_nonce=-1

  for record_path in "$SORASWAP_ROOT/deployments/${env}"/*.deploy.json(N); do
    if ! jq -e \
      --argjson current "$fingerprint_json" \
      '
        (.chain_fingerprint // {}) as $stored
        | $stored.chain == $current.chain
        and $stored.block_1_hash == $current.block_1_hash
      ' "$record_path" >/dev/null 2>&1; then
      continue
    fi

    nonce="$(jq -r '.deploy_nonce // -1' "$record_path" 2>/dev/null || echo -1)"
    if [[ "$nonce" =~ '^[0-9]+$' ]] && (( nonce > max_nonce )); then
      max_nonce="$nonce"
    fi
  done

  if (( max_nonce < 0 )); then
    echo 0
    return 0
  fi

  echo "$max_nonce"
}

account_assets_json() {
  local config="$1"
  local account_id="$2"
  local limit="${3:-200}"
  local torii_base encoded_account response attempt=1

  torii_base="$(torii_base_from_config "$config")"
  encoded_account="$(uri_encode "$account_id")"
  while (( attempt <= 3 )); do
    if response="$(
      curl -fsS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        "$torii_base/v1/accounts/${encoded_account}/assets?scope=global&limit=${limit}" \
        2>/dev/null
    )"; then
      printf '%s\n' "$response"
      return 0
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  return 1
}

account_has_any_positive_asset_balance() {
  local config="$1"
  local account_id="$2"
  local response

  if ! response="$(account_assets_json "$config" "$account_id" 50)"; then
    return 1
  fi

  jq -e 'any(.items[]?; ((.quantity | tonumber?) // 0) > 0)' <<<"$response" >/dev/null
}

account_positive_asset_balances_json() {
  local config="$1"
  local account_id="$2"
  local response

  if ! response="$(account_assets_json "$config" "$account_id" 200)"; then
    echo '[]'
    return 1
  fi

  jq -c '
    (.items // [])
    | map(select(((.quantity | tonumber?) // 0) > 0))
    | map({
        asset: (.asset // ""),
        asset_alias: (.asset_alias // ""),
        asset_name: (.asset_name // ""),
        quantity: (.quantity // "0")
      })
  ' <<<"$response"
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
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
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
      pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_json")"
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

warn_if_public_tx_gossip_cap_low() {
  local config="$1"
  local torii_base frame_cap

  torii_base="$(torii_base_from_config "$config")"
  frame_cap="$(curl -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/status" 2>/dev/null | jq -r '.tx_gossip.caps.frame_cap_bytes // 0' 2>/dev/null || true)"
  if [[ -z "$frame_cap" || "$frame_cap" == "null" ]]; then
    return 0
  fi
  if (( frame_cap < SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP )); then
    echo "warning: live tx_gossip frame cap is $frame_cap bytes; recommended minimum is $SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP bytes for routine SoraSwap deploys" >&2
  fi
}

warn_if_testnet_tx_gossip_cap_low() {
  warn_if_public_tx_gossip_cap_low "$@"
}

asset_definition_alias_exists() {
  local config="$1"
  local alias="$2"
  local torii_base http_status attempt=1

  torii_base="$(torii_base_from_config "$config")"
  while (( attempt <= 3 )); do
    http_status="$(curl -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" -o /dev/null -w '%{http_code}' \
      "$torii_base/v1/assets/definitions/$(uri_encode "$alias")" 2>/dev/null || true)"
    case "$http_status" in
      200)
        return 0
        ;;
      404)
        return 1
        ;;
    esac
    sleep 1
    attempt=$(( attempt + 1 ))
  done
  return 1
}

asset_definition_id_for_alias() {
  local config="$1"
  local alias="$2"
  local torii_base response attempt=1

  torii_base="$(torii_base_from_config "$config")"
  while (( attempt <= 3 )); do
    if response="$(curl -fsS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/v1/assets/definitions/$(uri_encode "$alias")" 2>/dev/null)"; then
      jq -r '.id' <<<"$response"
      return 0
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done
  return 1
}

ensure_asset_definition_alias() {
  local config="$1"
  local asset_id="$2"
  local name="$3"
  local alias="$4"
  local scale="$5"
  local existing_id output

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
  if output="$(
    iroha_cli --machine --config "$config" ledger asset definition register \
      --id "$asset_id" \
      --name "$name" \
      --alias "$alias" \
      --scale "$scale" 2>&1
  )"; then
    printf '%s\n' "$output"
    return 0
  fi

  if [[ "$output" == *"Repeated instruction"* || "$output" == *"Repetition of \`Register\`"* ]]; then
    existing_id="$(asset_definition_id_for_alias "$config" "$alias" 2>/dev/null || true)"
    if [[ "$existing_id" == "$asset_id" ]]; then
      echo "asset definition alias already present after duplicate register rejection: $alias -> $existing_id"
      return 0
    fi
  fi

  echo "$output" >&2
  return 1
}

asset_value_for_account_query() {
  local config="$1"
  local query_key="$2"
  local asset_ref="$3"
  local account="$4"
  local torii_base encoded_account response attempt=1

  torii_base="$(torii_base_from_config "$config")"
  encoded_account="$(uri_encode "$account")"
  while (( attempt <= 3 )); do
    if response="$(
      curl -fsS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        "$torii_base/v1/accounts/${encoded_account}/assets?scope=global&limit=200" \
        2>/dev/null
    )"; then
      jq -r \
        --arg query_key "$query_key" \
        --arg asset_ref "$asset_ref" \
        '
          def matches:
            if $query_key == "asset_id" then
              .asset == $asset_ref
            elif $query_key == "asset" then
              .asset_alias == $asset_ref
            else
              false
            end;

          (.items // [])
          | map(select(matches))
          | if length == 0 then "0" else (.[0].quantity // "0") end
        ' <<<"$response"
      return 0
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  echo 0
  return 0
}

asset_value_for_account() {
  local config="$1"
  local alias="$2"
  local account="$3"

  asset_value_for_account_query "$config" asset "$alias" "$account"
}

asset_value_for_account_id() {
  local config="$1"
  local asset_id="$2"
  local account="$3"

  asset_value_for_account_query "$config" asset_id "$asset_id" "$account"
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

contract_manifest_json_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local torii_base

  torii_base="$(torii_base_from_config "$config")"
  curl -fsS \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -H 'Accept: application/json' \
    "$torii_base/v1/contracts/code/$(uri_encode "$code_hash_hex")"
}

contract_code_bytes_http_status_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local torii_base http_code

  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"
  http_code="$(
    curl -sS \
      -o /dev/null \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -H 'Accept: application/octet-stream' \
      -w '%{http_code}' \
      "$torii_base/v1/contracts/code-bytes/$(uri_encode "$code_hash_hex")" 2>/dev/null || true
  )"
  printf '%s\n' "$http_code"
}

contract_code_bytes_visible_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"

  [[ "$(contract_code_bytes_http_status_by_code_hash "$config" "$code_hash_hex")" == "200" ]]
}

wait_for_contract_code_bytes_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local attempt=1

  while (( attempt <= attempts )); do
    if contract_code_bytes_visible_by_code_hash "$config" "$code_hash_hex"; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract code bytes for code hash $code_hash_hex were not visible after ${attempts}s" >&2
  return 1
}

wait_for_contract_manifest_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local attempt=1
  local response

  while (( attempt <= attempts )); do
    if response="$(contract_manifest_json_by_code_hash "$config" "$code_hash_hex" 2>/dev/null)" \
      && jq -e --arg code_hash_hex "$code_hash_hex" '
        (
          .manifest.code_hash
          // .manifest.code_hash_hex
          // .code_hash
          // .code_hash_hex
          // ""
        ) as $hash
        | (($hash | tostring | ascii_downcase | sub("^0x"; "")) == $code_hash_hex)
      ' <<<"$response" >/dev/null 2>&1; then
      printf '%s\n' "$response"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract manifest for code hash $code_hash_hex was not visible after ${attempts}s" >&2
  return 1
}

submit_contract_call() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local gas_limit="${4:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local payload_json="${5:-null}"
  local torii_base authority private_key request response http_code body attempt=1 retry_count
  local curl_args=()

  authority="$(authority_from_config "$config" 2>/dev/null || true)"
  if [[ -z "$authority" ]]; then
    ensure_authority "$config"
    authority="$SORASWAP_AUTHORITY"
  fi
  torii_base="$(torii_base_from_config "$config")"
  private_key="$(account_private_key_from_config "$config")"

  if is_contract_address_literal "$contract_id"; then
    request="$(jq -cn \
      --arg authority "$authority" \
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

  retry_count="${SORASWAP_CONTRACT_CALL_RETRY_COUNT:-1}"
  if ! [[ "$retry_count" =~ '^[0-9]+$' ]] || (( retry_count < 1 )); then
    retry_count=1
  fi

  curl_args=(
    -sS
    -H 'Content-Type: application/json'
    -w $'\n%{http_code}'
    -X POST
    --max-time "$SORASWAP_CONTRACT_CALL_MAX_TIME_SECS"
    "$torii_base/v1/contracts/call"
    -d "$request"
  )
  while (( attempt <= retry_count )); do
    if response="$(curl "${curl_args[@]}")"; then
      break
    fi
    if (( attempt == retry_count )); then
      echo "failed to reach $torii_base/v1/contracts/call for $contract_id.$entrypoint" >&2
      return 1
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

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
  local torii_base authority request response http_code body curl_args attempt=1 max_attempts=6 retry_delay=2 max_time_secs
  local allowed_http_codes

  authority="$(authority_from_config "$config" 2>/dev/null || true)"
  if [[ -z "$authority" ]]; then
    ensure_authority "$config"
    authority="$SORASWAP_AUTHORITY"
  fi
  torii_base="$(torii_base_from_config "$config")"

  if is_contract_address_literal "$contract_id"; then
    request="$(jq -cn \
      --arg authority "$authority" \
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

  max_time_secs="${SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS:-30}"

  curl_args=(
    -sS
    --connect-timeout 10
    --max-time "$max_time_secs"
    -H 'Content-Type: application/json'
    -w $'\n%{http_code}'
    -X POST
  )
  curl_args+=(
    "$torii_base/v1/contracts/view"
    -d "$request"
  )

  while (( attempt <= max_attempts )); do
    if response="$(curl "${curl_args[@]}")"; then
      break
    fi
    if (( attempt == max_attempts )); then
      echo "failed to reach $torii_base/v1/contracts/view for $contract_id.$entrypoint" >&2
      return 1
    fi
    sleep "$retry_delay"
    attempt=$(( attempt + 1 ))
    retry_delay=$(( retry_delay < 10 ? retry_delay * 2 : 10 ))
  done

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"
  allowed_http_codes=" ${${SORASWAP_CONTRACT_VIEW_ALLOWED_HTTP_CODES:-200}//,/ } "

  if [[ "$allowed_http_codes" != *" $http_code "* ]]; then
    echo "contract view request failed for $contract_id.$entrypoint: HTTP $http_code: $body" >&2
    return 1
  fi

  printf '%s\n' "$body"
}

submit_contract_deploy_file() {
  local config="$1"
  local code_file="$2"
  local contract_alias="$3"
  local torii_base private_key code_b64 request response http_code body curl_args

  ensure_authority "$config"
  torii_base="$(torii_base_from_config "$config")"
  private_key="$(account_private_key_from_config "$config")"
  code_b64="$(base64 < "$code_file" | tr -d '\r\n')"

    request="$(jq -cn \
    --arg authority "$SORASWAP_AUTHORITY" \
    --arg private_key "$private_key" \
    --arg code_b64 "$code_b64" \
    --arg contract_alias "$contract_alias" \
    '{
      authority: $authority,
      private_key: $private_key,
      code_b64: $code_b64,
      contract_alias: $contract_alias
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
  jq -c 'if .ok == true then .result else error("contract view response did not succeed") end' <<<"$response_json"
}

contract_liveness_probe_entrypoint_for_key() {
  local contract_key="$1"

  case "$contract_key" in
    automation.job_queue) echo "mirror_job" ;;
    bridge.sccp_bridge) echo "listing_config" ;;
    cover.policy_manager) echo "manager_config" ;;
    dlmm.dlmm_pool) echo "pool_config" ;;
    dlmm.dlmm_router) echo "router_config" ;;
    farms.farm) echo "farm_config" ;;
    launchpad.liquidity_executor) echo "executor_config" ;;
    launchpad.sale_factory) echo "factory_binding_details" ;;
    n3x.n3x_hub) echo "hub_config" ;;
    options.factory) echo "factory_config" ;;
    options.manager) echo "manager_config" ;;
    options.outperformance_option) echo "series_state" ;;
    options.shout_option) echo "series_state" ;;
    options.vault) echo "vault_state" ;;
    perps.perps_engine) echo "engine_config" ;;
    referral.registry) echo "registry_config" ;;
    risk.risk_vault) echo "risk_state" ;;
    *)
      return 1
      ;;
  esac
}

contract_liveness_probe_payload_for_key() {
  local contract_key="$1"

  case "$contract_key" in
    automation.job_queue)
      jq -cn --arg job "deploy-probe" '{job: $job}'
      ;;
    options.outperformance_option|options.shout_option|options.vault)
      echo '{"series_id":1}'
      ;;
    *)
      echo "null"
      ;;
  esac
}

contract_instance_liveness_json() {
  local config="$1"
  local contract_key="$2"
  local contract_address="$3"
  local entrypoint payload_json gas_limit

  entrypoint="$(contract_liveness_probe_entrypoint_for_key "$contract_key")" || {
    echo "no liveness probe configured for $contract_key" >&2
    return 1
  }
  payload_json="$(contract_liveness_probe_payload_for_key "$contract_key")"
  gas_limit="${SORASWAP_DEPLOY_LIVENESS_GAS_LIMIT:-${SORASWAP_SMOKE_GAS_LIMIT:-100000}}"

  SORASWAP_CONTRACT_VIEW_ALLOWED_HTTP_CODES="200 422" \
    submit_contract_view "$config" "$contract_address" "$entrypoint" "$gas_limit" "$payload_json"
}

wait_for_contract_instance_liveness() {
  local config="$1"
  local contract_key="$2"
  local contract_address="$3"
  local attempts="${4:-60}"
  local sleep_seconds="${5:-1}"
  local attempt=1

  while (( attempt <= attempts )); do
    if contract_instance_liveness_json "$config" "$contract_key" "$contract_address" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract instance $contract_key at $contract_address did not answer its liveness probe after ${attempts}s" >&2
  return 1
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
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
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

pipeline_status_kind_from_json() {
  local response_json="$1"
  jq -r '.status.kind // .content.status.kind // empty' <<<"$response_json"
}

pipeline_status_content_from_json() {
  local response_json="$1"
  jq -c '.status.rejection_reason // .content.status.content // .content.status // null' <<<"$response_json"
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
      kind="$(pipeline_status_kind_from_json "$response")"
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
  if pipeline_json="$(wait_for_transaction_terminal_status "$config" "$tx_hash" "$SORASWAP_TX_PIPELINE_WAIT_SECS" 1 auto 2>/dev/null)"; then
    pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_json")"
    case "$pipeline_kind" in
      Applied|Committed)
        :
        ;;
      Rejected|Expired)
        pipeline_content="$(pipeline_status_content_from_json "$pipeline_json")"
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
  local -a contract_paths

  contract_paths=("${(@f)$(list_contracts)}")
  for contract in "${contract_paths[@]}"; do
    contract_id_for "$contract"
  done
}

expected_contract_ids_for_env() {
  local env="$1"
  local contract_key
  local -a contract_keys

  contract_keys=("${(@f)$(expected_contract_ids)}")
  for contract_key in "${contract_keys[@]}"; do
    deployed_contract_id_for_env "$env" "$contract_key"
  done
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

contract_alias_for() {
  local src="$1"
  local rel="${src#$SORASWAP_ROOT/contracts/}"
  local name domain

  rel="${rel%.ko}"
  name="${rel##*/}"
  domain="${rel%/*}"
  if [[ "$domain" == "$rel" ]]; then
    echo "${name}::universal"
    return 0
  fi

  domain="${domain//\//.}"
  echo "${name}::${domain}.universal"
}

contract_app_manifest_path() {
  echo "$SORASWAP_ROOT/iroha.app.toml"
}

contract_bundle_receipt_path_for_env() {
  local env="$1"
  echo "$SORASWAP_ROOT/deployments/${env}/soraswap.bundle.deploy.json"
}

contract_source_for_key() {
  local contract_key="$1"
  local contract_path

  while IFS= read -r contract_path; do
    if [[ "$(contract_id_for "$contract_path")" == "$contract_key" ]]; then
      echo "$contract_path"
      return 0
    fi
  done < <(list_contracts)

  return 1
}

submit_contract_app_bundle() {
  local config="$1"
  local action="${2:-deploy}"
  local manifest_path="${3:-$(contract_app_manifest_path)}"
  local private_key

  private_key="$(account_private_key_from_config "$config")"
  iroha_cli_json --config "$config" contract app "$action" \
    --manifest "$manifest_path" \
    --authority "$SORASWAP_AUTHORITY" \
    --private-key "$private_key"
}

materialize_contract_bundle_records_for_env() {
  local env="$1"
  local receipt_json="$2"
  local report_dir receipt_path chain_fingerprint_json contract_entry contract_key contract_source
  local contract_alias contract_address previous_contract_address upgraded dataspace deploy_nonce
  local code_hash_hex abi_hash_hex tx_hash_hex response_json instance_json record_json
  local record_path manifest_out compiled_manifest detail_json

  if ! jq -e '.ok == true' <<<"$receipt_json" >/dev/null; then
    echo "contract bundle receipt is not successful" >&2
    return 1
  fi

  report_dir="$SORASWAP_ROOT/deployments/${env}"
  receipt_path="$(contract_bundle_receipt_path_for_env "$env")"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  mkdir -p "$report_dir"
  printf '%s\n' "$receipt_json" > "$receipt_path"

  while IFS= read -r contract_entry; do
    contract_key="$(jq -r '.name' <<<"$contract_entry")"
    if [[ -z "$contract_key" || "$contract_key" == "null" ]]; then
      echo "bundle receipt contained a contract without a name" >&2
      return 1
    fi
    if [[ "$(jq -r '.status // empty' <<<"$contract_entry")" != "deployed" ]]; then
      echo "bundle receipt contract ${contract_key} is not fully deployed" >&2
      return 1
    fi

    contract_source="$(contract_source_for_key "$contract_key")" || {
      echo "unable to map bundle receipt contract ${contract_key} to a repo source file" >&2
      return 1
    }
    compiled_manifest="$(manifest_path_for "$contract_source")"
    if [[ ! -f "$compiled_manifest" ]]; then
      echo "missing compiled manifest for ${contract_key}: ${compiled_manifest}" >&2
      return 1
    fi

    contract_alias="$(jq -r '.contract_alias' <<<"$contract_entry")"
    contract_address="$(jq -r '.contract_address' <<<"$contract_entry")"
    previous_contract_address="$(jq -r '.previous_contract_address // empty' <<<"$contract_entry")"
    upgraded="$(jq -r '.upgraded // false' <<<"$contract_entry")"
    dataspace="$(jq -r '.dataspace // "universal"' <<<"$contract_entry")"
    deploy_nonce="$(jq -r '.deploy_nonce // 0' <<<"$contract_entry")"
    code_hash_hex="$(jq -r '.code_hash_hex // empty' <<<"$contract_entry")"
    abi_hash_hex="$(jq -r '.abi_hash_hex // empty' <<<"$contract_entry")"
    tx_hash_hex="$(jq -r '.tx_hash_hex // empty' <<<"$contract_entry")"

    response_json="$(jq -cn \
      --arg contract_alias "$contract_alias" \
      --arg contract_address "$contract_address" \
      --arg previous_contract_address "$previous_contract_address" \
      --argjson upgraded "$upgraded" \
      --arg dataspace "$dataspace" \
      --argjson deploy_nonce "$deploy_nonce" \
      --arg tx_hash_hex "$tx_hash_hex" \
      --arg code_hash_hex "$code_hash_hex" \
      --arg abi_hash_hex "$abi_hash_hex" \
      '{
        ok: true,
        contract_alias: $contract_alias,
        contract_address: $contract_address,
        upgraded: $upgraded,
        dataspace: $dataspace,
        deploy_nonce: $deploy_nonce,
        tx_hash_hex: $tx_hash_hex,
        code_hash_hex: $code_hash_hex,
        abi_hash_hex: $abi_hash_hex
      } + (if ($previous_contract_address | length) > 0 then {
        previous_contract_address: $previous_contract_address
      } else {} end)')"
    instance_json="$(synthetic_contract_instance_json_from_response "$response_json")"
    record_json="$(jq -cn \
      --arg contract_key "$contract_key" \
      --arg contract_source "$contract_source" \
      --arg contract_alias "$contract_alias" \
      --arg dataspace "$dataspace" \
      --arg contract_address "$contract_address" \
      --argjson deploy_nonce "$deploy_nonce" \
      --arg code_hash_hex "$code_hash_hex" \
      --arg abi_hash_hex "$abi_hash_hex" \
      --argjson chain_fingerprint "$chain_fingerprint_json" \
      --argjson bundle_receipt "$contract_entry" \
      --argjson response "$response_json" \
      --argjson instance "$instance_json" \
      '{
        contract_key: $contract_key,
        contract_source: $contract_source,
        contract_alias: $contract_alias,
        dataspace: $dataspace,
        contract_address: $contract_address,
        deploy_nonce: $deploy_nonce,
        code_hash_hex: $code_hash_hex,
        abi_hash_hex: $abi_hash_hex,
        deploy_strategy: "bundle",
        chain_fingerprint: $chain_fingerprint,
        bundle_receipt: $bundle_receipt,
        response: $response,
        instance: $instance
      }')"
    record_path="$(deployment_record_path_for_env "$env" "$contract_key")"
    manifest_out="$report_dir/${contract_key}.manifest.json"
    printf '%s\n' "$record_json" > "$record_path"
    cp "$compiled_manifest" "$manifest_out"

    detail_json="$(jq -cn \
      --arg record_path "$record_path" \
      --argjson receipt "$contract_entry" \
      '{record_path: $record_path, receipt: $receipt}')"
    deploy_report_set_contract "$env" "$contract_key" "completed" "$detail_json"
  done < <(jq -c '.contracts[]' <<<"$receipt_json")
}

deployment_record_path_for_env() {
  local env="$1"
  local contract_key="$2"
  echo "$SORASWAP_ROOT/deployments/${env}/${contract_key}.deploy.json"
}

deployment_records_json_for_env() {
  local env="$1"
  local record_paths=()
  local record_path

  for record_path in "$SORASWAP_ROOT/deployments/${env}"/*.deploy.json(N); do
    record_paths+=("$record_path")
  done

  if (( ${#record_paths[@]} == 0 )); then
    echo '[]'
    return 0
  fi

  jq -sc 'sort_by(.contract_key)' "${record_paths[@]}"
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

contract_alias_resolve_json() {
  local config="$1"
  local contract_alias="$2"
  local torii_base request response http_code body attempt=1
  local last_http_code="" last_body=""

  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"
  request="$(jq -cn --arg contract_alias "$contract_alias" '{contract_alias: $contract_alias}')"

  while (( attempt <= 3 )); do
    if response="$(
      curl -sS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -w $'\n%{http_code}' \
        -X POST \
        "$torii_base/v1/contracts/aliases/resolve" \
        -d "$request" 2>/dev/null
    )"; then
      http_code="${response##*$'\n'}"
      body="${response%$'\n'*}"
      last_http_code="$http_code"
      last_body="$body"
      case "$http_code" in
        200)
          printf '%s\n' "$body"
          return 0
          ;;
        404)
          return 2
          ;;
      esac
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$last_http_code" ]]; then
    echo "contract alias resolve request failed for $contract_alias: HTTP $last_http_code: $last_body" >&2
  else
    echo "failed to reach $torii_base/v1/contracts/aliases/resolve for $contract_alias" >&2
  fi
  return 1
}

recent_contract_aliases_from_explorer() {
  local config="$1"
  local max_aliases="${2:-8}"
  local max_pages="${3:-5}"
  local torii_base response hash encoded alias page=1
  local -a aliases=() page_hashes

  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"

  while (( page <= max_pages && ${#aliases[@]} < max_aliases )); do
    if ! response="$(
      curl -fsS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        "$torii_base/v1/explorer/transactions?page=$page&per_page=10" 2>/dev/null
    )"; then
      break
    fi

    page_hashes=("${(@f)$(jq -r '.items[] | select(.executable == "Instructions" and .status == "Committed") | .hash' <<<"$response")}")
    for hash in "${page_hashes[@]}"; do
      [[ -z "$hash" ]] && continue
      encoded="$(
        curl -fsS \
          --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
          "$torii_base/v1/explorer/instructions/$hash/3" 2>/dev/null \
          | jq -r '."r#box".json.payload.value.encoded // empty' 2>/dev/null || true
      )"
      [[ -z "$encoded" || "$encoded" == "null" ]] && continue
      alias="$(
        printf '%s' "$encoded" \
          | xxd -r -p 2>/dev/null \
          | LC_ALL=C strings \
          | LC_ALL=C awk '/::/ { value = $0 } END { print value }'
      )"
      [[ -z "$alias" ]] && continue
      if (( ${aliases[(Ie)$alias]} == 0 )); then
        aliases+=("$alias")
      fi
      if (( ${#aliases[@]} >= max_aliases )); then
        break
      fi
    done

    page=$(( page + 1 ))
  done

  if (( ${#aliases[@]} == 0 )); then
    return 1
  fi

  printf '%s\n' "${aliases[@]}"
}

recover_deployment_records_from_live_aliases() {
  local env="$1"
  local config="$2"
  local contract_path contract_key contract_alias record_path manifest_out compiled_manifest
  local expected_code_hash expected_abi_hash resolved_response contract_address dataspace
  local response_json instance_json record_json recent_aliases recovered=0 resolve_status
  local report_dir="$SORASWAP_ROOT/deployments/${env}"
  local chain_fingerprint_json
  local -a contract_paths
  local -a missing_aliases=()
  local -a missing_manifests=()

  mkdir -p "$report_dir"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"

  contract_paths=("${(@f)$(list_contracts)}")
  for contract_path in "${contract_paths[@]}"; do
    contract_key="$(contract_id_for "$contract_path")"
    contract_alias="$(contract_alias_for "$contract_path")"
    record_path="$(deployment_record_path_for_env "$env" "$contract_key")"
    manifest_out="$report_dir/${contract_key}.manifest.json"
    compiled_manifest="$(manifest_path_for "$contract_path")"

    if resolved_response="$(contract_alias_resolve_json "$config" "$contract_alias")"; then
      resolve_status=0
    else
      resolve_status=$?
    fi
    case "$resolve_status" in
      0)
        ;;
      2)
        missing_aliases+=("$contract_alias")
        continue
        ;;
      *)
        return 1
        ;;
    esac

    if [[ ! -f "$compiled_manifest" ]]; then
      missing_manifests+=("$contract_key")
      continue
    fi

    expected_code_hash="$(manifest_code_hash_hex "$compiled_manifest")"
    expected_abi_hash="$(manifest_abi_hash_hex "$compiled_manifest")"
    contract_address="$(jq -r '.contract_address // empty' <<<"$resolved_response")"
    dataspace="$(jq -r '.dataspace // "universal"' <<<"$resolved_response")"
    if [[ -z "$contract_address" ]]; then
      echo "contract alias resolve response for $contract_alias did not include a contract address" >&2
      return 1
    fi

    response_json="$(jq -cn \
      --arg contract_address "$contract_address" \
      --arg dataspace "$dataspace" \
      --arg code_hash_hex "$expected_code_hash" \
      --arg abi_hash_hex "$expected_abi_hash" \
      '{
        ok: true,
        contract_address: $contract_address,
        dataspace: $dataspace,
        deploy_nonce: 0,
        tx_hash_hex: "",
        code_hash_hex: $code_hash_hex,
        abi_hash_hex: $abi_hash_hex
      }')"
    instance_json="$(synthetic_contract_instance_json_from_response "$response_json")"
    record_json="$(jq -cn \
      --arg contract_key "$contract_key" \
      --arg contract_source "$contract_path" \
      --arg contract_alias "$contract_alias" \
      --arg dataspace "$dataspace" \
      --arg contract_address "$contract_address" \
      --arg code_hash_hex "$expected_code_hash" \
      --arg abi_hash_hex "$expected_abi_hash" \
      --argjson chain_fingerprint "$chain_fingerprint_json" \
      --argjson alias_resolution "$resolved_response" \
      --argjson response "$response_json" \
      --argjson instance "$instance_json" \
      '{
        contract_key: $contract_key,
        contract_source: $contract_source,
        contract_alias: $contract_alias,
        dataspace: $dataspace,
        contract_address: $contract_address,
        deploy_nonce: 0,
        code_hash_hex: $code_hash_hex,
        abi_hash_hex: $abi_hash_hex,
        deploy_strategy: "recovered_from_alias_resolve",
        chain_fingerprint: $chain_fingerprint,
        alias_resolution: $alias_resolution,
        response: $response,
        instance: $instance
      }')"

    printf '%s\n' "$record_json" > "$record_path"
    cp "$compiled_manifest" "$manifest_out"
    recovered=$(( recovered + 1 ))
  done

  if (( ${#missing_manifests[@]} > 0 )); then
    echo "cannot recover ${env} deployment records: missing compiled manifests for ${missing_manifests[*]}" >&2
    return 1
  fi

  if (( ${#missing_aliases[@]} > 0 )); then
    echo "could not recover ${env} deployment records from current chain; missing SoraSwap aliases:" >&2
    printf '  %s\n' "${missing_aliases[@]}" >&2
    if recent_aliases="$(recent_contract_aliases_from_explorer "$config" 8 2>/dev/null)"; then
      echo "recent live contract aliases on current chain:" >&2
      while IFS= read -r alias; do
        [[ -n "$alias" ]] && echo "  $alias" >&2
      done <<<"$recent_aliases"
    fi
    return 1
  fi

  if (( recovered > 0 )); then
    echo "recovered $recovered ${env} deployment record(s) from live contract aliases" >&2
  fi

  return 0
}

is_contract_address_literal() {
  local value="$1"
  [[ "$value" == sorac1* || "$value" == tairac1* ]]
}

contract_subject_account_for_literal() {
  local config="$1"
  local literal="$2"
  local network_prefix kagami_bin seed public_key

  if [[ -z "$literal" ]]; then
    return 1
  fi
  if ! is_contract_address_literal "$literal"; then
    echo "$literal"
    return 0
  fi

  network_prefix="$(network_prefix_for_config "$config")"

  ensure_kagami_bin >/dev/null
  kagami_bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"
  seed="iroha:contract-subject:v1:${literal}"
  public_key="$("$kagami_bin" keys --algorithm ed25519 --seed "$seed" --compact 2>/dev/null \
    | awk '/^ed[0-9A-Fa-f]+$/ { print; exit }')"
  if [[ -z "$public_key" ]]; then
    echo "failed to derive contract subject public key for $literal" >&2
    return 1
  fi

  iroha_cli --output-format text tools address convert \
    --network-prefix "$network_prefix" \
    "$public_key" 2>/dev/null \
    | tail -n 1 \
    | tr -d '\r\n'
}

compile_one() {
  local src="$1"
  local out manifest out_dir compiler_bin output filtered
  out="$(compiled_path_for "$src")"
  manifest="$(manifest_path_for "$src")"
  compiler_bin="$SORASWAP_IROHA_ROOT/target/debug/koto_compile"
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
      --strip-debug \
      --iter-cap 32 \
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
  local normalized_fingerprint_json

  if [[ ! -f "$record_path" ]]; then
    return 1
  fi

  normalized_fingerprint_json="$(normalize_json_or_null "$fingerprint_json")" || return 1
  if [[ "$normalized_fingerprint_json" == "null" ]]; then
    return 1
  fi

  jq -e \
    --argjson current "$normalized_fingerprint_json" \
    '
      (.chain_fingerprint // {}) as $stored
      | $stored.chain == $current.chain
      and $stored.block_1_hash == $current.block_1_hash
    ' "$record_path" >/dev/null
}

ensure_deployment_records_current() {
  local env="$1"
  local config="$2"
  local needs_record_recovery=0
  local record_path contract_key manifest_path expected_code_hash
  local -a expected_contract_keys

  expected_contract_keys=("${(@f)$(expected_contract_ids)}")
  for contract_key in "${expected_contract_keys[@]}"; do
    record_path="$(deployment_record_path_for_env "$env" "$contract_key")"
    manifest_path="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
    expected_code_hash=""
    if [[ -f "$manifest_path" ]]; then
      expected_code_hash="$(manifest_code_hash_hex "$manifest_path")"
    fi
    if [[ ! -f "$record_path" ]] \
      || ! deployment_record_matches_current_chain "$record_path" "${SORASWAP_CHAIN_FINGERPRINT_JSON:-null}" \
      || ! live_contract_deployment_from_record "$config" "$record_path" "$expected_code_hash" >/dev/null 2>&1; then
      needs_record_recovery=1
      break
    fi
  done

  if (( needs_record_recovery )); then
    "$SORASWAP_ROOT/scripts/compile_contracts.sh"
    recover_deployment_records_from_live_aliases "$env" "$config"
  fi

  refresh_deployment_records_snapshot_latest_for_env "$env" >/dev/null
}

synthetic_contract_instance_json_from_response() {
  local response_json="$1"

  jq -cn \
    --argjson response "$response_json" \
    '{
      contract_id: $response.contract_address,
      contract_address: $response.contract_address,
      dataspace: ($response.dataspace // "universal"),
      code_hash_hex: ($response.code_hash_hex // ""),
      abi_hash_hex: ($response.abi_hash_hex // ""),
      deploy_nonce: ($response.deploy_nonce // 0),
      tx_hash_hex: ($response.tx_hash_hex // $response.activate_tx_hash // ""),
      verification: "transaction_and_manifest"
    }'
}

confirm_contract_deploy_response() {
  local config="$1"
  local response_json="$2"
  local contract_key="$3"
  local expected_code_hash="$4"
  local tx_hash pipeline_json pipeline_kind pipeline_content tx_json contract_address
  local code_bytes_visible=0

  contract_address="$(jq -r '.contract_address // empty' <<<"$response_json")"
  if [[ -z "$contract_address" ]]; then
    echo "$contract_key.deploy confirmation response did not include a contract address" >&2
    return 1
  fi

  if contract_code_bytes_visible_by_code_hash "$config" "$expected_code_hash"; then
    code_bytes_visible=1
    deploy_progress_note "$contract_key" "code-bytes already visible" "$expected_code_hash"
  fi

  if (( ! code_bytes_visible )); then
    tx_hash="$(jq -r '.tx_hash_hex // .activate_tx_hash // empty' <<<"$response_json")"
    if [[ -n "$tx_hash" ]]; then
      deploy_progress_note "$contract_key" "wait pipeline" "$tx_hash"
      if pipeline_json="$(wait_for_transaction_terminal_status "$config" "$tx_hash" "$SORASWAP_DEPLOY_PIPELINE_WAIT_SECS" 1 auto)"; then
        pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_json")"
        deploy_progress_note "$contract_key" "pipeline" "$pipeline_kind"
        case "$pipeline_kind" in
          Applied|Committed)
            :
            ;;
          Rejected|Expired)
            pipeline_content="$(pipeline_status_content_from_json "$pipeline_json")"
            echo "$contract_key.deploy failed for transaction $tx_hash: $pipeline_content" >&2
            return 1
            ;;
          *)
            echo "$contract_key.deploy reached unexpected pipeline status for transaction $tx_hash: $pipeline_kind" >&2
            return 1
            ;;
        esac
      else
        tx_json="$(committed_transaction_json "$config" "$tx_hash" "$SORASWAP_DEPLOY_COMMITTED_WAIT_SECS" 1)" || return 1
        assert_transaction_ok "$tx_json" "$tx_hash" "$contract_key.deploy" || return 1
      fi
    fi

    deploy_progress_note "$contract_key" "wait manifest" "$expected_code_hash"
    wait_for_contract_manifest_by_code_hash "$config" "$expected_code_hash" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
    deploy_progress_note "$contract_key" "manifest visible" "$expected_code_hash"
    deploy_progress_note "$contract_key" "wait code-bytes" "$expected_code_hash"
    wait_for_contract_code_bytes_by_code_hash "$config" "$expected_code_hash" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
    deploy_progress_note "$contract_key" "code-bytes visible" "$expected_code_hash"
  fi

  deploy_progress_note "$contract_key" "wait instance" "$contract_address"
  wait_for_contract_instance_liveness "$config" "$contract_key" "$contract_address" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
  deploy_progress_note "$contract_key" "instance live" "$contract_address"
  synthetic_contract_instance_json_from_response "$response_json"
}

live_contract_deployment_from_record() {
  local config="$1"
  local record_path="$2"
  local expected_code_hash="$3"
  local response_json current_code_hash contract_alias contract_source resolved_response
  local contract_key contract_address

  if [[ -n "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]] \
    && ! deployment_record_matches_current_chain "$record_path" "${SORASWAP_CHAIN_FINGERPRINT_JSON}"; then
    return 1
  fi

  response_json="$(jq -c '
    .response // {
      contract_address: (.contract_address // .contract_id // empty),
      dataspace: (.dataspace // .namespace // "universal"),
      deploy_nonce: (.deploy_nonce // 0),
      tx_hash_hex: (.tx_hash_hex // ""),
      code_hash_hex: (.code_hash_hex // ""),
      abi_hash_hex: (.abi_hash_hex // "")
    }' "$record_path")"
  current_code_hash="$(jq -r '.code_hash_hex // empty | ascii_downcase' <<<"$response_json")"
  if [[ -z "$current_code_hash" ]]; then
    return 1
  fi
  if [[ -n "$expected_code_hash" && "$current_code_hash" != "$expected_code_hash" ]]; then
    return 1
  fi

  if ! contract_code_bytes_visible_by_code_hash "$config" "$current_code_hash"; then
    return 1
  fi

  contract_key="$(jq -r '.contract_key // "contract"' "$record_path")"
  contract_address="$(jq -r '.contract_address // .response.contract_address // empty' "$record_path")"
  if [[ -z "$contract_address" ]]; then
    return 1
  fi
  if ! wait_for_contract_instance_liveness "$config" "$contract_key" "$contract_address" 3 1 >/dev/null 2>&1; then
    return 1
  fi

  contract_alias="$(jq -r '.contract_alias // .response.contract_alias // empty' "$record_path")"
  if [[ -z "$contract_alias" ]]; then
    contract_source="$(jq -r '.contract_source // empty' "$record_path")"
    if [[ -n "$contract_source" && "$contract_source" != "null" ]]; then
      contract_alias="$(contract_alias_for "$contract_source")"
    fi
  fi
  if [[ -n "$contract_alias" ]]; then
    if ! resolved_response="$(contract_alias_resolve_json "$config" "$contract_alias" 2>/dev/null)"; then
      return 1
    fi
    if ! jq -e \
      --argjson recorded "$response_json" \
      '
        (.contract_address // empty) == ($recorded.contract_address // "")
        and (.dataspace // "universal") == ($recorded.dataspace // "universal")
      ' <<<"$resolved_response" >/dev/null; then
      return 1
    else
      synthetic_contract_instance_json_from_response "$response_json"
      return 0
    fi
  fi

  synthetic_contract_instance_json_from_response "$response_json"
}

deploy_one() {
  local config="$1"
  local src="$2"
  local env="$3"
  local contract_key contract_alias manifest_out deploy_out code_file compiled_manifest dataspace
  local expected_code_hash expected_abi_hash instance_json record_json existing_instance
  local current_nonce deploy_nonce post_nonce predicted_address response_json normal_output normal_error
  local recorded_nonce
  local split_output split_output_raw deploy_strategy detail_json confirm_output chain_discriminant
  local chain_fingerprint_json chain_fingerprint_json_compact response_json_compact instance_json_compact

  contract_key="$(contract_id_for "$src")"
  contract_alias="$(contract_alias_for "$src")"
  dataspace="universal"
  manifest_out="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
  deploy_out="$(deployment_record_path_for_env "$env" "$contract_key")"
  code_file="$(compiled_path_for "$src")"
  compiled_manifest="$(manifest_path_for "$src")"
  expected_code_hash="$(manifest_code_hash_hex "$compiled_manifest")"
  expected_abi_hash="$(manifest_abi_hash_hex "$compiled_manifest")"
  chain_discriminant="$(chain_discriminant_for_env "$env")"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  chain_fingerprint_json_compact="$(compact_json_or_fail "$contract_key.chain_fingerprint_json" "$chain_fingerprint_json")"
  mkdir -p "$(dirname "$manifest_out")"

  if deployment_record_matches_current_chain "$deploy_out" "$chain_fingerprint_json"; then
    if existing_instance="$(live_contract_deployment_from_record "$config" "$deploy_out" "$expected_code_hash")"; then
      existing_instance="$(compact_json_or_fail "$contract_key.existing_instance" "$existing_instance")"
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

  current_nonce="$(account_contract_deploy_nonce "$config" "$SORASWAP_AUTHORITY")"
  deploy_nonce="$current_nonce"
  if [[ -n "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]]; then
    recorded_nonce="$(max_deploy_nonce_for_env_records "$env" "${SORASWAP_CHAIN_FINGERPRINT_JSON}")"
    if [[ "$recorded_nonce" =~ '^[0-9]+$' ]] && (( recorded_nonce >= deploy_nonce )); then
      deploy_nonce=$(( recorded_nonce + 1 ))
    fi
  fi
  predicted_address="$(derive_contract_address_for_deploy "$config" "$SORASWAP_AUTHORITY" "$deploy_nonce" "$dataspace" "$env" 2>/dev/null || true)"
  response_json=""
  normal_error=""
  deploy_strategy=""
  detail_json="$(jq -cn \
    --arg contract_key "$contract_key" \
    --arg contract_alias "$contract_alias" \
    --arg predicted_address "$predicted_address" \
    --argjson deploy_nonce "$deploy_nonce" \
    '{
      contract_key: $contract_key,
      contract_alias: $contract_alias,
      predicted_address: ($predicted_address // ""),
      deploy_nonce: $deploy_nonce
    }')"
  deploy_report_set_contract "$env" "$contract_key" "running" "$detail_json"

  if normal_output="$(submit_contract_deploy_file "$config" "$code_file" "$contract_alias" 2>&1)"; then
    if [[ -z "$predicted_address" ]]; then
      predicted_address="$(jq -r '.contract_address // empty' <<<"$normal_output")"
    fi
    if ! jq -e \
      --arg dataspace "$dataspace" \
      --arg code_hash_hex "$expected_code_hash" \
      '
        .ok == true
        and .dataspace == $dataspace
        and (.contract_address | type == "string" and length > 0)
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
    if confirm_output="$(confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash" 2>&1)"; then
      instance_json="$confirm_output"
      deploy_strategy="normal"
    else
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg response "$response_json" \
        --arg error "$confirm_output" \
        '{
          contract_key: $contract_key,
          stage: "normal_deploy_confirm",
          contract_address: $contract_address,
          response: $response,
          error: $error
        }')"
      echo "normal deploy completed for $contract_key but confirmation failed: $confirm_output" >&2
      return 1
    fi
  else
    normal_error="$normal_output"
  fi

  if [[ -z "$instance_json" && -z "$response_json" ]]; then
    post_nonce="$(account_contract_deploy_nonce "$config" "$SORASWAP_AUTHORITY")"
    if (( post_nonce > deploy_nonce )) && [[ -n "$predicted_address" ]]; then
      response_json="$(jq -cn \
        --arg contract_address "$predicted_address" \
        --arg dataspace "$dataspace" \
        --arg code_hash_hex "$expected_code_hash" \
        --arg abi_hash_hex "$expected_abi_hash" \
        --arg normal_error "$normal_error" \
        --argjson deploy_nonce "$deploy_nonce" \
        '{
          ok: true,
          contract_address: $contract_address,
          dataspace: $dataspace,
          deploy_nonce: $deploy_nonce,
          tx_hash_hex: "",
          code_hash_hex: $code_hash_hex,
          abi_hash_hex: $abi_hash_hex
        } + (if ($normal_error | length) > 0 then {normal_deploy_error: $normal_error} else {} end)')"
      if confirm_output="$(confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash" 2>&1)"; then
        instance_json="$confirm_output"
        deploy_strategy="adopted_committed"
      else
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg contract_address "$predicted_address" \
          --argjson current_nonce "$current_nonce" \
          --argjson deploy_nonce "$deploy_nonce" \
          --argjson post_nonce "$post_nonce" \
          --arg normal_error "$normal_error" \
          --arg error "$confirm_output" \
          '{
            contract_key: $contract_key,
            stage: "adopt_committed_confirm",
            contract_address: $contract_address,
            current_nonce: $current_nonce,
            deploy_nonce: $deploy_nonce,
            post_nonce: $post_nonce,
            error: $error
          } + (if ($normal_error | length) > 0 then {normal_deploy_error: $normal_error} else {} end)')"
        echo "deploy nonce advanced for $contract_key but confirmation failed: $confirm_output" >&2
        return 1
      fi
    fi
  fi

  if [[ -z "$instance_json" ]]; then
    split_output_raw="$(split_contract_deploy_cli \
      --config "$config" \
      --authority "$SORASWAP_AUTHORITY" \
      --private-key "$(account_private_key_from_config "$config")" \
      --code-file "$code_file" \
      --contract-address "$predicted_address" \
      --dataspace "$dataspace" \
      --chain-discriminant "$chain_discriminant" \
      --deploy-nonce "$deploy_nonce" 2>&1)" || {
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg predicted_address "$predicted_address" \
          --arg error "$split_output_raw" \
          '{contract_key: $contract_key, stage: "split_fallback", contract_address: $predicted_address, error: $error}')"
        echo "$split_output_raw" >&2
        return 1
      }
    if ! split_output="$(extract_last_json_object <<<"$split_output_raw")"; then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg output "$split_output_raw" \
        '{contract_key: $contract_key, stage: "split_fallback_parse", contract_address: $contract_address, output: $output}')"
      echo "split deploy output for $contract_key did not end in JSON: $split_output_raw" >&2
      return 1
    fi
    if ! jq -e \
      --arg dataspace "$dataspace" \
      --arg code_hash_hex "$expected_code_hash" \
      '
        .ok == true
        and .dataspace == $dataspace
        and (.contract_address | type == "string" and length > 0)
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
    if confirm_output="$(confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash" 2>&1)"; then
      instance_json="$confirm_output"
      deploy_strategy="split_fallback"
    else
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg response "$split_output" \
        --arg error "$confirm_output" \
        '{contract_key: $contract_key, stage: "split_fallback_confirm", contract_address: $contract_address, response: $response, error: $error}')"
      echo "split deploy completed for $contract_key but confirmation failed: $confirm_output" >&2
      return 1
    fi
  fi

  response_json_compact="$(compact_json_or_fail "$contract_key.response_json" "$response_json")"
  instance_json_compact="$(compact_json_or_fail "$contract_key.instance_json" "$instance_json")"
  record_json="$(jq -cn \
    --arg contract_key "$contract_key" \
    --arg contract_source "$src" \
    --arg contract_alias "$contract_alias" \
    --arg dataspace "$dataspace" \
    --arg deploy_strategy "$deploy_strategy" \
    --argjson response "$response_json_compact" \
    --argjson instance "$instance_json_compact" \
    --argjson chain_fingerprint "$chain_fingerprint_json_compact" \
    '{
      contract_key: $contract_key,
      contract_source: $contract_source,
      contract_alias: $contract_alias,
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
  configure_cli_account_chain_discriminant "$config"
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

ensure_public_signer_ready() {
  local config="$1"
  local account_id="$2"
  local mode="${3:-autofund}"
  local fee_label
  local fee_asset_id
  local balance="0"
  local positive_assets_json='[]'
  local skip_ready_check="${SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK:-0}"

  fee_label="$(fee_asset_label_for_config "$config")"
  fee_asset_id="$(fee_asset_definition_id_for_config "$config")"

  if [[ "$skip_ready_check" == "1" ]]; then
    echo "skipping public signer readiness check for $account_id"
    return 0
  fi

  if account_exists "$config" "$account_id"; then
    balance="$(asset_value_for_account_id "$config" "$fee_asset_id" "$account_id")"
    if numeric_gt_zero "$balance"; then
      echo "public signer ready: $account_id holds $balance of $fee_label ($fee_asset_id)"
      return 0
    fi
    positive_assets_json="$(account_positive_asset_balances_json "$config" "$account_id" || true)"
  fi

  if [[ "$mode" == "autofund" ]] && is_taira_public_config "$config"; then
    echo "claim faucet funding for testnet signer: $account_id"
    claim_public_testnet_faucet "$config" "$account_id" >/dev/null
    wait_for_account_exists "$config" "$account_id" 15 1 >/dev/null || true
    if balance="$(wait_for_positive_asset_balance_id "$config" "$fee_asset_id" "$account_id" 15 1)"; then
      echo "testnet signer funded: $account_id -> $balance $fee_label ($fee_asset_id)"
      return 0
    fi
    positive_assets_json="$(account_positive_asset_balances_json "$config" "$account_id" || true)"
    if jq -e 'length > 0' >/dev/null <<<"$positive_assets_json"; then
      echo "testnet signer faucet funding produced unexpected live assets; expected $fee_label ($fee_asset_id): $positive_assets_json" >&2
      return 1
    fi
    echo "testnet signer faucet claim committed but $fee_label ($fee_asset_id) did not become query-visible" >&2
    return 1
  fi

  if jq -e 'length > 0' >/dev/null <<<"$positive_assets_json"; then
    echo "public signer holds live assets, but not the configured fee asset $fee_label ($fee_asset_id): $positive_assets_json" >&2
  fi

  if is_taira_public_config "$config"; then
    probe_public_faucet "$config" || true
    echo "testnet signer is not funded for public deploy/smoke: $account_id" >&2
    if [[ -n "${SORASWAP_LAST_FAUCET_STATUS:-}" ]]; then
      echo "faucet endpoint response: HTTP ${SORASWAP_LAST_FAUCET_STATUS}${SORASWAP_LAST_FAUCET_ERROR:+ - ${SORASWAP_LAST_FAUCET_ERROR}}" >&2
    fi
    echo "run: SORASWAP_CLIENT_CONFIG=\"$config\" \"$SORASWAP_ROOT/scripts/fund_testnet_signer.sh\"" >&2
    return 1
  fi

  echo "public signer is not funded for deploy/smoke: $account_id" >&2
  echo "fund the configured signer with $fee_label ($fee_asset_id) before running this public environment" >&2
  return 1
}

ensure_public_testnet_signer_ready() {
  ensure_public_signer_ready "$@"
}

account_has_can_register_trigger_permission() {
  local config="$1"
  local account_id="$2"
  local permissions_json

  permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")" || return 1
  jq -e \
    --arg authority "$account_id" \
    '.[] | select(.name == "CanRegisterTrigger" and (.payload.authority // "") == $authority)' \
    >/dev/null <<<"$permissions_json"
}

ensure_can_register_trigger_permission() {
  local config="$1"
  local account_id="$2"
  local permission_json grant_output

  if account_has_can_register_trigger_permission "$config" "$account_id"; then
    return 0
  fi

  permission_json="$(jq -cn \
    --arg authority "$account_id" \
    '{name: "CanRegisterTrigger", payload: {authority: $authority}}')"
  if ! grant_output="$(printf '%s' "$permission_json" | iroha_cli --config "$config" account permission grant --id "$account_id" 2>&1)"; then
    echo "failed to grant CanRegisterTrigger to $account_id" >&2
    printf '%s\n' "$grant_output" >&2
    return 1
  fi
  if ! account_has_can_register_trigger_permission "$config" "$account_id"; then
    echo "CanRegisterTrigger grant for $account_id did not become query-visible" >&2
    return 1
  fi
}

account_address_canonical_hex() {
  local config="$1"
  local account_literal="$2"
  local network_prefix

  network_prefix="$(network_prefix_for_config "$config")"

  iroha_cli --output-format text tools address convert \
    --expect-prefix "$network_prefix" \
    --format canonical-hex \
    "$account_literal" 2>/dev/null \
    | tail -n 1 \
    | tr -d '\r\n'
}

ensure_domain_sns_lease() {
  local config="$1"
  local domain_label="$2"
  local selector_literal policy_json payment_asset_id payment_gross output owner_hex

  selector_literal="${domain_label}.universal"
  if iroha_cli_json --config "$config" app sns registration --selector "$selector_literal" \
    >/dev/null 2>&1; then
    return 0
  fi

  policy_json="$(iroha_cli_json --config "$config" app sns policy --suffix-id "$SORASWAP_SNS_DOMAIN_SUFFIX_ID")"
  payment_asset_id="$(jq -r '.policy.payment_asset_id // empty' <<<"$policy_json")"
  payment_gross="$(jq -r \
    --arg selector "$selector_literal" \
    --arg label "$domain_label" \
    '
      .policy.pricing // []
      | map(select(
          (.label_regex as $re | (($selector | test($re)) or ($label | test($re))))
        ))
      | .[0].base_price.amount // empty
    ' <<<"$policy_json")"

  if [[ -z "$payment_asset_id" || -z "$payment_gross" || "$payment_gross" == "null" ]]; then
    echo "failed to derive SNS payment details for $selector_literal from suffix policy $SORASWAP_SNS_DOMAIN_SUFFIX_ID" >&2
    jq -c '.policy // .' <<<"$policy_json" >&2 || true
    return 1
  fi

  if output="$(
    iroha_cli --config "$config" app sns register \
      --label "$selector_literal" \
      --suffix-id "$SORASWAP_SNS_DOMAIN_SUFFIX_ID" \
      --term-years 1 \
      --payment-asset-id "$payment_asset_id" \
      --payment-gross "$payment_gross" \
      --payment-net "$payment_gross" \
      --payment-settlement '"soraswap-bootstrap"' \
      --payment-signature '"soraswap-bootstrap"' 2>&1
  )"; then
    return 0
  fi
  if [[ "$output" == *"selector \`${selector_literal}\` is already registered"* ]]; then
    return 0
  fi

  if [[ "$output" == *"ERR_UNEXPECTED_NETWORK_PREFIX"* ]]; then
    local torii_base payload_json tmp http_code

    torii_base="$(torii_base_from_config "$config")"
    owner_hex="$(account_address_canonical_hex "$config" "$SORASWAP_AUTHORITY")"
    if [[ -z "$owner_hex" ]]; then
      echo "failed to derive canonical account address for SNS fallback owner $SORASWAP_AUTHORITY" >&2
      return 1
    fi
    payload_json="$(jq -cn \
      --arg owner "$SORASWAP_AUTHORITY" \
      --arg owner_hex "$owner_hex" \
      --arg payer "$SORASWAP_AUTHORITY" \
      --arg label "$selector_literal" \
      --arg asset_id "$payment_asset_id" \
      --argjson payment_gross "$payment_gross" \
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
          account_address: $owner_hex,
          resolver_template_id: null,
          payload: {}
        }],
        term_years: 1,
        payment: {
          asset_id: $asset_id,
          gross_amount: $payment_gross,
          net_amount: $payment_gross,
          settlement_tx: "soraswap-bootstrap",
          payer: $payer,
          signature: "soraswap-bootstrap"
        },
        governance: null,
        metadata: {}
      }')"
    tmp="$(mktemp)"
    http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
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
    echo "sns register fallback failed for ${selector_literal}: HTTP ${http_code}: $(cat "$tmp")" >&2
    rm -f "$tmp"
    return 1
  fi

  printf '%s\n' "$output" >&2
  return 1
}
