#!/bin/zsh
set -euo pipefail

SORASWAP_SCRIPT_DIR="${SORASWAP_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
SORASWAP_ROOT="${SORASWAP_ROOT:-$(cd "$SORASWAP_SCRIPT_DIR/.." && pwd)}"
SORASWAP_IROHA_ROOT="${SORASWAP_IROHA_ROOT:-$(cd "$SORASWAP_ROOT/../iroha" && pwd)}"
SORASWAP_COMMON_SOURCE_FILE="${${(%):-%N}:A}"
SORASWAP_SECURE_CLIENT_CONFIG_TOOL="${SORASWAP_SECURE_CLIENT_CONFIG_TOOL:-${SORASWAP_COMMON_SOURCE_FILE:h}/secure_client_config.py}"
SORASWAP_BASE_ASSET_ALIAS="${SORASWAP_BASE_ASSET_ALIAS:-xor#universal}"
SORASWAP_FEE_ASSET_ALIAS="${SORASWAP_FEE_ASSET_ALIAS:-$SORASWAP_BASE_ASSET_ALIAS}"
SORASWAP_LOCAL_FEE_ASSET_LABEL="${SORASWAP_LOCAL_FEE_ASSET_LABEL:-xor#wonderland}"
SORASWAP_LOCAL_FEE_ASSET_SCALE="${SORASWAP_LOCAL_FEE_ASSET_SCALE:-9}"
SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID="${SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID:-6TEAJqbb8oEPmLncoNiMRbLEK6tw}"
SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID="${SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID:-6TEAJqbb8oEPmLncoNiMRbLEK6tw}"
SORASWAP_TESTNET_FEE_ASSET_LABEL="${SORASWAP_TESTNET_FEE_ASSET_LABEL:-$SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID}"
SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID="${SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID:-}"
SORASWAP_PRODUCTION_FEE_ASSET_LABEL="${SORASWAP_PRODUCTION_FEE_ASSET_LABEL:-}"
SORASWAP_XOR_ASSET_DEFINITION_ID="${SORASWAP_XOR_ASSET_DEFINITION_ID:-6TEAJqbb8oEPmLncoNiMRbLEK6tw}"
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
# The `/v1/contracts/call` wrapper expects an explicit positive gas limit.
# Keep the default aligned with the verified local smoke path and README docs;
# callers can still override this per-run for heavier scenarios.
SORASWAP_SMOKE_GAS_LIMIT="${SORASWAP_SMOKE_GAS_LIMIT:-500000}"
SORASWAP_TESTNET_CHAIN_ID_DEFAULT="${SORASWAP_TESTNET_CHAIN_ID_DEFAULT:-fc56984b-2be7-431d-840e-21514d1883f0}"
SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT="${SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT:-369}"
SORASWAP_TESTNET_CHAIN_ID="${SORASWAP_TESTNET_CHAIN_ID:-}"
SORASWAP_TESTNET_CHAIN_DISCRIMINANT="${SORASWAP_TESTNET_CHAIN_DISCRIMINANT:-}"
SORASWAP_PRODUCTION_CHAIN_ID="${SORASWAP_PRODUCTION_CHAIN_ID:-}"
SORASWAP_PRODUCTION_MIN_FEE_BALANCE="${SORASWAP_PRODUCTION_MIN_FEE_BALANCE:-}"
SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP="${SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP:-1048576}"
SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS="${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-45}"
SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS="${SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS:-3600}"
SORASWAP_DEPLOY_PIPELINE_WAIT_SECS="${SORASWAP_DEPLOY_PIPELINE_WAIT_SECS:-300}"
SORASWAP_DEPLOY_COMMITTED_WAIT_SECS="${SORASWAP_DEPLOY_COMMITTED_WAIT_SECS:-120}"
SORASWAP_DEPLOY_MANIFEST_WAIT_SECS="${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-180}"
SORASWAP_DEPLOY_NONCE_WAIT_SECS="${SORASWAP_DEPLOY_NONCE_WAIT_SECS:-120}"
SORASWAP_TX_PIPELINE_WAIT_SECS="${SORASWAP_TX_PIPELINE_WAIT_SECS:-120}"
SORASWAP_TX_COMMITTED_WAIT_SECS="${SORASWAP_TX_COMMITTED_WAIT_SECS:-120}"
SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS="${SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS:-}"
SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS="${SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS:-2}"
SORASWAP_PIPELINE_APPLIED_COMMITTED_VERIFY_SECS="${SORASWAP_PIPELINE_APPLIED_COMMITTED_VERIFY_SECS:-5}"
SORASWAP_ACCEPT_PIPELINE_APPLIED_WITHOUT_COMMITTED_TX="${SORASWAP_ACCEPT_PIPELINE_APPLIED_WITHOUT_COMMITTED_TX:-auto}"
SORASWAP_CONTRACT_CALL_MAX_TIME_SECS="${SORASWAP_CONTRACT_CALL_MAX_TIME_SECS:-120}"
SORASWAP_CONTRACT_CALL_RETRY_COUNT="${SORASWAP_CONTRACT_CALL_RETRY_COUNT:-4}"
SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS="${SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS:-2}"
SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS="${SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS:-900000}"
SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS="${SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS:-1800000}"
SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS="${SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS:-$SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS}"
SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS="${SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS:-30}"
SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT="${SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT:-60}"
SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS="${SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS:-2}"
SORASWAP_TORII_READ_MAX_TIME_SECS="${SORASWAP_TORII_READ_MAX_TIME_SECS:-10}"
SORASWAP_TORII_READ_RETRY_COUNT="${SORASWAP_TORII_READ_RETRY_COUNT:-6}"
SORASWAP_TORII_READ_RETRY_DELAY_SECS="${SORASWAP_TORII_READ_RETRY_DELAY_SECS:-2}"
SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX="${SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX:-10}"
SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX="${SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX:-8}"
SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS="${SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS:-30000}"
SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT="${SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT:-3}"
SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS="${SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS:-5}"
SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT="${SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT:-24}"
SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS="${SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS:-5}"
SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS="${SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS:-180000}"
SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT="${SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT:-5}"
SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS="${SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS:-1}"
SORASWAP_TORII_API_VERSION="${SORASWAP_TORII_API_VERSION:-1.0}"
SORASWAP_ORACLE_SCHEME="${SORASWAP_ORACLE_SCHEME:-1}"
typeset -gA SORASWAP_LOCAL_ORACLE_KEYPAIR_CACHE
SORASWAP_PLACEHOLDER_TOKEN_PATTERN='change[_ -]?me|changeme|replace[_ -]?me|replaceme|todo|tbd|placeholder'
SORASWAP_PLACEHOLDER_VALUE_PATTERN="${SORASWAP_PLACEHOLDER_TOKEN_PATTERN}|^[[:space:]]*<[^<>[:cntrl:]]+>[[:space:]]*$|^[[:space:]]*(none|null|n/?a|example)[[:space:]]*$"
SORASWAP_RESERVED_PUBLIC_ENDPOINT_PATTERN='(^|[^[:alnum:]_-])(([[:alnum:]-]+\.)*(example|invalid|test|localhost)|([[:alnum:]-]+\.)*example\.(com|org|net))([/:"[:space:]]|$)'
SORASWAP_CLIENT_CONFIG_PLACEHOLDER_PATTERN="${SORASWAP_PLACEHOLDER_TOKEN_PATTERN}|${SORASWAP_RESERVED_PUBLIC_ENDPOINT_PATTERN}|127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::1\\]|\\[::\\]|=[[:space:]]*[\"'](none|null|n/?a|example)[\"']|=[[:space:]]*[\"']<[^\"'\r\n]+>[\"']"

utc_timestamp() {
  env TZ=UTC date '+%Y%m%dT%H%M%SZ'
}

soraswap_current_time_millis() {
  local now seconds fraction millis_part

  if zmodload zsh/datetime 2>/dev/null; then
    now="${EPOCHREALTIME:-}"
    if [[ "$now" == <->.* ]]; then
      seconds="${now%%.*}"
      fraction="${now#*.}000"
      millis_part="${fraction[1,3]}"
      printf '%s\n' $(( seconds * 1000 + 10#$millis_part ))
      return 0
    fi
  fi

  printf '%s\n' $(( $(date '+%s') * 1000 ))
}

soraswap_next_contract_call_creation_time_ms() {
  local now

  typeset -gi SORASWAP_LAST_CONTRACT_CALL_CREATION_TIME_MS="${SORASWAP_LAST_CONTRACT_CALL_CREATION_TIME_MS:-0}"
  now="$(soraswap_current_time_millis)" || return 1
  soraswap_require_nonnegative_integer_setting "contract call creation_time_ms" "$now" || return 1
  if (( now <= SORASWAP_LAST_CONTRACT_CALL_CREATION_TIME_MS )); then
    now=$(( SORASWAP_LAST_CONTRACT_CALL_CREATION_TIME_MS + 1 ))
  fi
  SORASWAP_LAST_CONTRACT_CALL_CREATION_TIME_MS="$now"
  printf '%s\n' "$now"
}

soraswap_value_looks_placeholder() {
  local value="${1:-}"
  [[ -n "$value" ]] || return 1
  soraswap_regex_match_i "$SORASWAP_PLACEHOLDER_VALUE_PATTERN" "$value"
}

soraswap_regex_match_i() {
  local pattern="$1"
  local value="${2:-}"

  if (( $+commands[rg] )); then
    rg -i -q "$pattern" <<<"$value"
    return $?
  fi

  grep -Eiq -- "$pattern" <<<"$value"
}

soraswap_env_value() {
  local name="$1"
  local value

  eval "value=\"\${${name}:-}\""
  printf '%s' "$value"
}

soraswap_trim_rwa_ref() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

soraswap_rwa_ref_looks_placeholder() {
  local value="$1"
  local trimmed lowered

  trimmed="$(soraswap_trim_rwa_ref "$value")"
  lowered="${(L)trimmed}"

  [[ -z "$trimmed" ]] && return 0
  case "$lowered" in
    \<*\>|*change_me*|*change-me*|*change\ me*|*changeme*|*replace_me*|*replace-me*|*replace\ me*|*replaceme*|*todo*|*tbd*|*placeholder*|none|null|n/a|na|example)
      return 0
      ;;
    *127.0.0.1*)
      return 0
      ;;
    *external\ approval\ id\ or\ url*|*external\ legal\ review\ id\ or\ url*|*external\ compliance\ policy\ id\ or\ url*|*external\ nav\ source\ id\ or\ url*|*external\ redemption\ terms\ id\ or\ url*)
      return 0
      ;;
  esac
  if [[ "$lowered" == *0.0.0.0* || "$lowered" == *"[::1]"* || "$lowered" == *"[::]"* ]]; then
    return 0
  fi

  if soraswap_regex_match_i "$SORASWAP_RESERVED_PUBLIC_ENDPOINT_PATTERN" "$trimmed"; then
    return 0
  fi

  return 1
}

soraswap_rwa_ref_has_control_chars() {
  local value="$1"
  local trimmed

  trimmed="$(soraswap_trim_rwa_ref "$value")"
  [[ "$trimmed" == *[$'\001'-$'\037'$'\177']* ]]
}

soraswap_required_rwa_ref_fields() {
  printf '%s\n' \
    issuer_approval_ref \
    legal_review_ref \
    compliance_policy_ref \
    nav_source_ref \
    redemption_terms_ref
}

soraswap_rwa_ref_env_name_for_field() {
  case "$1" in
    issuer_approval_ref)
      printf '%s\n' SORASWAP_RWA_ISSUER_APPROVAL_REF
      ;;
    legal_review_ref)
      printf '%s\n' SORASWAP_RWA_LEGAL_REVIEW_REF
      ;;
    compliance_policy_ref)
      printf '%s\n' SORASWAP_RWA_COMPLIANCE_POLICY_REF
      ;;
    nav_source_ref)
      printf '%s\n' SORASWAP_RWA_NAV_SOURCE_REF
      ;;
    redemption_terms_ref)
      printf '%s\n' SORASWAP_RWA_REDEMPTION_TERMS_REF
      ;;
    *)
      return 1
      ;;
  esac
}

soraswap_rwa_ref_value_for_field() {
  local field="$1"
  local env_name

  env_name="$(soraswap_rwa_ref_env_name_for_field "$field")" || return 1
  soraswap_trim_rwa_ref "$(soraswap_env_value "$env_name")"
}

soraswap_validate_required_rwa_refs() {
  local field value

  for field in $(soraswap_required_rwa_ref_fields); do
    value="$(soraswap_rwa_ref_value_for_field "$field")"
    if [[ -z "$value" ]]; then
      printf 'missing %s\n' "$field"
      return 1
    fi
    if soraswap_rwa_ref_has_control_chars "$value"; then
      printf '%s contains control characters\n' "$field"
      return 1
    fi
    if soraswap_rwa_ref_looks_placeholder "$value"; then
      printf '%s looks like placeholder content\n' "$field"
      return 1
    fi
  done

  return 0
}

soraswap_default_rwa_release_enabled_for_env() {
  case "$1" in
    local)
      printf '%s\n' 1
      ;;
    testnet|production)
      printf '%s\n' 0
      ;;
    *)
      printf '%s\n' 0
      ;;
  esac
}

soraswap_rwa_release_enabled_setting_for_env() {
  local env="$1"
  local default_value value

  default_value="$(soraswap_default_rwa_release_enabled_for_env "$env")"
  value="${SORASWAP_ENABLE_RWA_RELEASE:-$default_value}"
  soraswap_require_binary_integer_setting "SORASWAP_ENABLE_RWA_RELEASE" "$value" || return 1
  printf '%s\n' "$value"
}

soraswap_rwa_release_enabled_json_for_env() {
  local value

  value="$(soraswap_rwa_release_enabled_setting_for_env "$1")" || return 1
  if [[ "$value" == "1" ]]; then
    printf '%s\n' true
  else
    printf '%s\n' false
  fi
}

soraswap_client_config_has_placeholder_values() {
  local config="$1"
  local uncommented_config

  [[ -f "$config" ]] || return 1
  uncommented_config="$(awk '
    {
      output = ""
      quote = ""
      for (idx = 1; idx <= length($0); idx++) {
        char = substr($0, idx, 1)
        if (quote != "") {
          output = output char
          if (char == quote) {
            quote = ""
          }
        } else if (char == "\"" || char == sprintf("%c", 39)) {
          quote = char
          output = output char
        } else if (char == "#") {
          break
        } else {
          output = output char
        }
      }
      if (output ~ /[^[:space:]]/) {
        print output
      }
    }
  ' "$config")"
  soraswap_regex_match_i "$SORASWAP_CLIENT_CONFIG_PLACEHOLDER_PATTERN" "$uncommented_config"
}

soraswap_secure_client_config_tool() {
  local root="${1:-$SORASWAP_ROOT}"
  shift

  python3 "$SORASWAP_SECURE_CLIENT_CONFIG_TOOL" \
    --repo-root "$root" \
    --public-env "${SORASWAP_PUBLIC_ENV:-}" \
    --taira-chain-id "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT" \
    --taira-discriminant "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT" \
    "$@"
}

soraswap_inspect_client_config() {
  local config="$1"
  local mode="${2:-metadata}"
  local root="${3:-$SORASWAP_ROOT}"
  local inferred_public_env=""
  local -a production_args

  if (( $+functions[public_env_for_config_path] )); then
    inferred_public_env="$(public_env_for_config_path "$config" 2>/dev/null || true)"
  fi
  production_args=()
  if [[ "$mode" == "production" \
    || "${SORASWAP_PUBLIC_ENV:-}" == "production" \
    || "$inferred_public_env" == "production" ]]; then
    production_args=(--production)
  fi
  [[ "$mode" != "production" ]] || mode=metadata
  case "$mode" in
    metadata|curl|auth-toml)
      ;;
    *)
      echo "unsupported client config inspection mode: $mode" >&2
      return 1
      ;;
  esac

  soraswap_secure_client_config_tool "$root" inspect \
    --config "$config" \
    "${production_args[@]}" \
    --format "$mode"
}

soraswap_validate_client_basic_auth() {
  soraswap_inspect_client_config "$1" metadata >/dev/null
}

soraswap_client_basic_auth_configured() {
  local metadata
  metadata="$(soraswap_inspect_client_config "$1" metadata)" || return 1
  jq -e '.basic_auth_configured == true' >/dev/null <<<"$metadata"
}

soraswap_emit_curl_basic_auth_config() {
  local inspected auth_line
  inspected="$(soraswap_inspect_client_config "$1" curl)" || return 1
  auth_line="${inspected#*$'\n'}"
  [[ "$auth_line" != "-" ]] || return 0
  printf '%s\n' "$auth_line"
}

soraswap_secure_temp_file() {
  local family="${1:-secret}"

  soraswap_secure_client_config_tool "$SORASWAP_ROOT" write-secret --family "$family" </dev/null
}

soraswap_secret_temp_from_stdin() {
  local family="$1"

  soraswap_secure_client_config_tool "$SORASWAP_ROOT" write-secret --family "$family"
}

soraswap_secure_unlink_owned_file() {
  local owned_path="${1:-}"

  [[ -n "$owned_path" ]] || return 0
  soraswap_secure_client_config_tool "$SORASWAP_ROOT" unlink-owned --path "$owned_path"
}

soraswap_secure_unlink_owned_files() {
  local owned_path
  local cleanup_status=0

  for owned_path in "$@"; do
    [[ -n "$owned_path" ]] || continue
    if ! soraswap_secure_unlink_owned_file "$owned_path"; then
      echo "refusing unsafe cleanup of generated file: $(soraswap_display_path "$owned_path")" >&2
      cleanup_status=1
    fi
  done
  return "$cleanup_status"
}

soraswap_secure_temp_directory() {
  local family="${1:-secrets}"

  soraswap_secure_client_config_tool "$SORASWAP_ROOT" create-owned-dir --family "$family"
}

soraswap_secure_cleanup_owned_directory() {
  local owned_dir="${1:-}"

  [[ -n "$owned_dir" ]] || return 0
  soraswap_secure_client_config_tool "$SORASWAP_ROOT" cleanup-owned-dir --path "$owned_dir"
}

soraswap_config_private_key_temp_file() {
  local config="$1"
  local family="${2:-private-key}"
  local public_env
  local -a production_args

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  production_args=()
  [[ "$public_env" != "production" ]] || production_args=(--production)
  SORASWAP_PUBLIC_ENV="$public_env" \
    soraswap_secure_client_config_tool "$SORASWAP_ROOT" private-key-file \
      --config "$config" \
      "${production_args[@]}" \
      --family "$family"
}

soraswap_assert_client_output_clean() {
  local config="$1"
  shift
  local public_env secret_file
  local -a production_args secret_args

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  production_args=()
  [[ "$public_env" != "production" ]] || production_args=(--production)
  secret_args=()
  for secret_file in "$@"; do
    [[ -n "$secret_file" ]] || continue
    secret_args+=(--secret-file "$secret_file")
  done
  SORASWAP_PUBLIC_ENV="$public_env" \
    soraswap_secure_client_config_tool "$SORASWAP_ROOT" assert-output-clean \
      --config "$config" \
      "${production_args[@]}" \
      "${secret_args[@]}"
}

soraswap_url_origin() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse

raw = sys.argv[1]
if any(char.isspace() for char in raw) or "\\" in raw:
    raise SystemExit(1)
try:
    parsed = urllib.parse.urlsplit(raw)
    port = parsed.port
except ValueError:
    raise SystemExit(1)
if parsed.scheme.lower() not in {"http", "https"} or not parsed.hostname:
    raise SystemExit(1)
if parsed.username is not None or parsed.password is not None:
    raise SystemExit(1)
host = parsed.hostname.lower()
host_literal = f"[{host}]" if ":" in host else host
default = 443 if parsed.scheme.lower() == "https" else 80
origin = f"{parsed.scheme.lower()}://{host_literal}"
if port is not None and port != default:
    origin += f":{port}"
print(origin)
PY
}

soraswap_validate_production_torii_root_url() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse

try:
    parsed = urllib.parse.urlsplit(sys.argv[1])
    _ = parsed.port
except ValueError:
    raise SystemExit(1)
if parsed.scheme.lower() != "https" or not parsed.hostname:
    raise SystemExit(1)
if parsed.username is not None or parsed.password is not None:
    raise SystemExit(1)
if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
    raise SystemExit(1)
PY
}

soraswap_canonical_u16_decimal() {
  local label="$1"
  local value="${2:-}"
  python3 - "$label" "$value" <<'PY'
import re
import sys

label, raw = sys.argv[1:3]
if not re.fullmatch(r"0|[1-9][0-9]*", raw):
    raise SystemExit(f"{label} must be a canonical unsigned decimal integer")
value = int(raw)
if value > 65535:
    raise SystemExit(f"{label} must fit u16")
print(raw)
PY
}

soraswap_invoke_immediate_submit_gate() {
  local function_name="${1:-}"
  local config="${2:-}"
  local label="${3:-ledger submission}"

  [[ -n "$function_name" ]] || return 0
  if [[ ! "$function_name" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]; then
    echo "invalid immediate submission gate function name" >&2
    return 1
  fi
  if (( ! $+functions[$function_name] )); then
    echo "immediate submission gate is not a shell function: $function_name" >&2
    return 1
  fi
  "$function_name" "$config" "$label"
}

soraswap_invoke_accepted_submission_callback() {
  local function_name="${1:-}"
  local config="${2:-}"
  local label="${3:-ledger submission}"
  local transaction_hash="${4:-}"

  [[ -n "$function_name" ]] || return 0
  if [[ ! "$function_name" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]]; then
    echo "invalid accepted-submission callback function name" >&2
    return 1
  fi
  if (( ! $+functions[$function_name] )); then
    echo "accepted-submission callback is not a shell function: $function_name" >&2
    return 1
  fi
  [[ -n "$transaction_hash" ]] || {
    echo "accepted-submission callback requires a transaction hash" >&2
    return 1
  }
  "$function_name" "$config" "$label" "$transaction_hash"
}

soraswap_curl_for_config() {
  local config="$1"
  shift
  local curl_bin="${SORASWAP_CURL_BIN:-curl}"
  local inspected configured_origin auth_line request_url request_origin arg header header_name public_env output_target
  local stdout_file="" stderr_file="" curl_status=1 copy_status=0 cleanup_status=0 gate_status=0
  local -a curl_args output_arg_indices output_arg_styles output_targets output_temp_files
  local idx output_index
  local authenticated_url_seen=0
  local protected_request=0

  curl_args=("$@")

  if [[ -z "$config" ]]; then
    soraswap_invoke_immediate_submit_gate \
      "${SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION:-}" \
      "$config" \
      "${SORASWAP_IMMEDIATE_CURL_GATE_LABEL:-curl submission}" || return $?
    "$curl_bin" -q "$@"
    return $?
  fi
  inspected="$(soraswap_inspect_client_config "$config" curl)" || return 1
  configured_origin="${inspected%%$'\n'*}"
  auth_line="${inspected#*$'\n'}"
  [[ "$auth_line" != "-" ]] || auth_line=""
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -n "$auth_line" || "$public_env" == "testnet" || "$public_env" == "production" ]]; then
    protected_request=1
  fi

  if (( protected_request == 1 )); then
    output_arg_indices=()
    output_arg_styles=()
    output_targets=()
    output_temp_files=()
    idx=1
    while (( idx <= ${#curl_args[@]} )); do
      arg="${curl_args[$idx]}"
      case "$arg" in
        -[sSfFgGiINORvq]*L*|-[sSfFgGiINORvq]*k*)
          echo "authenticated Torii requests must not use combined redirect or insecure curl flags" >&2
          return 1
          ;;
        -[sSfFgGiINORvq]*H*|-[sSfFgGiINORvq]*u*|-[sSfFgGiINORvq]*K*)
          echo "authenticated Torii requests must not hide header, authentication, or config options in combined curl flags" >&2
          return 1
          ;;
        -L|--location|--location-trusted|--location-trusted=*)
          echo "authenticated Torii requests must not follow redirects" >&2
          return 1
          ;;
        -u|-u*|--user|--user=*|--oauth2-bearer|--oauth2-bearer=*|--netrc|--netrc-optional|--netrc-file|--netrc-file=*|--anyauth|--basic|--digest|--negotiate|--ntlm|--ntlm-wb|--aws-sigv4|--aws-sigv4=*)
          echo "caller-supplied curl authentication is not permitted for authenticated Torii requests" >&2
          return 1
          ;;
        --connect-to|--connect-to=*|--resolve|--resolve=*|--unix-socket|--unix-socket=*|--abstract-unix-socket|--abstract-unix-socket=*|--request-target|--request-target=*)
          echo "authenticated Torii requests must not remap the configured origin" >&2
          return 1
          ;;
        -k|--insecure)
          echo "authenticated Torii requests must verify TLS certificates" >&2
          return 1
          ;;
        -K|-K*|--config|--config=*|--variable|--variable=*|--expand-*)
          echo "caller-supplied curl config is not permitted for authenticated Torii requests" >&2
          return 1
          ;;
        -o|--output)
          (( idx < ${#curl_args[@]} )) || {
            echo "curl output option is missing its value" >&2
            return 1
          }
          idx=$(( idx + 1 ))
          output_target="${curl_args[$idx]}"
          if [[ "$output_target" != "/dev/null" && "$output_target" != "-" ]]; then
            [[ "$output_target" != *'#'* ]] || {
              echo "authenticated Torii requests do not permit dynamic curl output paths" >&2
              return 1
            }
            output_arg_indices+=("$idx")
            output_arg_styles+=(value)
            output_targets+=("$output_target")
          fi
          ;;
        --output=*)
          output_target="${arg#*=}"
          [[ -n "$output_target" ]] || {
            echo "curl output option is missing its value" >&2
            return 1
          }
          if [[ "$output_target" != "/dev/null" && "$output_target" != "-" ]]; then
            [[ "$output_target" != *'#'* ]] || {
              echo "authenticated Torii requests do not permit dynamic curl output paths" >&2
              return 1
            }
            output_arg_indices+=("$idx")
            output_arg_styles+=(equals)
            output_targets+=("$output_target")
          fi
          ;;
        -o?*|-[sSfFgGiINORvq]*o*)
          echo "authenticated Torii requests require a separate -o/--output path argument" >&2
          return 1
          ;;
        -O|--remote-name|--remote-name-all|--remote-header-name|--output-dir|--output-dir=*)
          echo "authenticated Torii requests must use an explicit local output path" >&2
          return 1
          ;;
        -D|--dump-header|--dump-header=*|--stderr|--stderr=*|--trace|--trace=*|--trace-ascii|--trace-ascii=*|--trace-config|--trace-config=*|--trace-time)
          echo "authenticated Torii requests must not write credential-bearing diagnostics outside the protected response channel" >&2
          return 1
          ;;
        -H|--header|--proxy-header)
          (( idx < ${#curl_args[@]} )) || {
            echo "curl header option is missing its value" >&2
            return 1
          }
          idx=$(( idx + 1 ))
          header="${curl_args[$idx]}"
          if [[ "$header" == @* ]]; then
            echo "file-backed caller headers are not permitted for authenticated Torii requests" >&2
            return 1
          fi
          header_name="${${header%%:*}:l}"
          header_name="${header_name//[[:space:]]/}"
          if [[ "$header_name" == "authorization" || "$header_name" == "proxy-authorization" ]]; then
            echo "caller-supplied authorization headers are not permitted" >&2
            return 1
          fi
          ;;
        --header=*|--proxy-header=*)
          header="${arg#*=}"
          if [[ "$header" == @* ]]; then
            echo "file-backed caller headers are not permitted for authenticated Torii requests" >&2
            return 1
          fi
          header_name="${${header%%:*}:l}"
          header_name="${header_name//[[:space:]]/}"
          if [[ "$header_name" == "authorization" || "$header_name" == "proxy-authorization" ]]; then
            echo "caller-supplied authorization headers are not permitted" >&2
            return 1
          fi
          ;;
        --url)
          (( idx < ${#curl_args[@]} )) || {
            echo "request option --url is missing its value" >&2
            return 1
          }
          idx=$(( idx + 1 ))
          request_url="${curl_args[$idx]}"
          authenticated_url_seen=1
          request_origin="$(soraswap_url_origin "$request_url")" || {
            echo "authenticated request URL is invalid" >&2
            return 1
          }
          [[ "$request_origin" == "$configured_origin" ]] || {
            echo "refusing to send client authentication to a different Torii origin" >&2
            return 1
          }
          ;;
        --url=*)
          request_url="${arg#*=}"
          authenticated_url_seen=1
          request_origin="$(soraswap_url_origin "$request_url")" || {
            echo "authenticated request URL is invalid" >&2
            return 1
          }
          [[ "$request_origin" == "$configured_origin" ]] || {
            echo "refusing to send client authentication to a different Torii origin" >&2
            return 1
          }
          ;;
        http://*|https://*)
          request_url="$arg"
          authenticated_url_seen=1
          request_origin="$(soraswap_url_origin "$request_url")" || {
            echo "authenticated request URL is invalid" >&2
            return 1
          }
          if [[ "$request_origin" != "$configured_origin" ]]; then
            echo "refusing to send client authentication to a different Torii origin" >&2
            return 1
          fi
          ;;
      esac
      idx=$(( idx + 1 ))
    done
    if (( authenticated_url_seen == 0 )); then
      echo "authenticated curl invocation must include an explicit request URL" >&2
      return 1
    fi
    if [[ -n "$auth_line" || -n "$public_env" ]]; then
      for (( output_index = 1; output_index <= ${#output_targets[@]}; output_index++ )); do
        output_temp_files+=("$(soraswap_secure_temp_file curl-response)") || {
          soraswap_secure_unlink_owned_files "${output_temp_files[@]}" || true
          return 1
        }
        idx="${output_arg_indices[$output_index]}"
        if [[ "${output_arg_styles[$output_index]}" == "equals" ]]; then
          curl_args[$idx]="--output=${output_temp_files[$output_index]}"
        else
          curl_args[$idx]="${output_temp_files[$output_index]}"
        fi
      done
      stdout_file="$(soraswap_secure_temp_file curl-stdout)" || {
        soraswap_secure_unlink_owned_files "${output_temp_files[@]}" || true
        return 1
      }
      stderr_file="$(soraswap_secure_temp_file curl-stderr)" || {
        soraswap_secure_unlink_owned_files "$stdout_file" "${output_temp_files[@]}" || true
        return 1
      }
      if [[ -n "$auth_line" ]]; then
        soraswap_invoke_immediate_submit_gate \
          "${SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION:-}" \
          "$config" \
          "${SORASWAP_IMMEDIATE_CURL_GATE_LABEL:-curl submission}" || {
          gate_status=$?
          soraswap_secure_unlink_owned_files \
            "$stdout_file" "$stderr_file" "${output_temp_files[@]}" || true
          return "$gate_status"
        }
        if "$curl_bin" -q --compressed --config <(printf '%s\n' "$auth_line") "${curl_args[@]}" \
          >"$stdout_file" 2>"$stderr_file"; then
          curl_status=0
        else
          curl_status=$?
        fi
      else
        soraswap_invoke_immediate_submit_gate \
          "${SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION:-}" \
          "$config" \
          "${SORASWAP_IMMEDIATE_CURL_GATE_LABEL:-curl submission}" || {
          gate_status=$?
          soraswap_secure_unlink_owned_files \
            "$stdout_file" "$stderr_file" "${output_temp_files[@]}" || true
          return "$gate_status"
        }
        if "$curl_bin" -q --compressed "${curl_args[@]}" >"$stdout_file" 2>"$stderr_file"; then
          curl_status=0
        else
          curl_status=$?
        fi
      fi
      if ! {
        command cat "$stdout_file"
        command cat "$stderr_file"
        for output_target in "${output_temp_files[@]}"; do
          command cat "$output_target"
        done
      } | soraswap_assert_client_output_clean "$config"; then
        soraswap_secure_unlink_owned_files "$stdout_file" "$stderr_file" "${output_temp_files[@]}" || true
        echo "authenticated Torii response credential echo was suppressed" >&2
        return 1
      fi
      for (( output_index = 1; output_index <= ${#output_targets[@]}; output_index++ )); do
        if ! command cp "${output_temp_files[$output_index]}" "${output_targets[$output_index]}"; then
          copy_status=1
        fi
      done
      if ! command cat "$stdout_file"; then
        copy_status=1
      fi
      if ! command cat "$stderr_file" >&2; then
        copy_status=1
      fi
      if ! soraswap_secure_unlink_owned_files "$stdout_file" "$stderr_file" "${output_temp_files[@]}"; then
        cleanup_status=1
      fi
      if (( copy_status != 0 || cleanup_status != 0 )); then
        return 1
      fi
      return "$curl_status"
    fi
    soraswap_invoke_immediate_submit_gate \
      "${SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION:-}" \
      "$config" \
      "${SORASWAP_IMMEDIATE_CURL_GATE_LABEL:-curl submission}" || return $?
    "$curl_bin" -q "${curl_args[@]}"
    return $?
  fi
  soraswap_invoke_immediate_submit_gate \
    "${SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION:-}" \
    "$config" \
    "${SORASWAP_IMMEDIATE_CURL_GATE_LABEL:-curl submission}" || return $?
  "$curl_bin" -q "${curl_args[@]}"
}

soraswap_require_secure_production_client_config() {
  local config="$1"
  local root="${2:-$SORASWAP_ROOT}"
  local config_abs root_abs config_rel

  if ! soraswap_inspect_client_config "$config" production "$root" >/dev/null; then
    echo "production client config failed secure file, TOML, Torii URL, auth, or discriminant validation: $(soraswap_display_path "$config")" >&2
    return 1
  fi

  config_abs="${config:A}"
  root_abs="${root:A}"
  if [[ "$config_abs" != "$root_abs/"* ]] \
    || ! git -C "$root_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "production client config must be an ignored, untracked file inside the SoraSwap worktree" >&2
    return 1
  fi
  config_rel="${config_abs#$root_abs/}"
  if git -C "$root_abs" ls-files --error-unmatch -- "$config_rel" >/dev/null 2>&1; then
    echo "production client config must be untracked: $config_rel" >&2
    return 1
  fi
  if ! git -C "$root_abs" check-ignore -q -- "$config_rel"; then
    echo "production client config must be ignored by git: $config_rel" >&2
    return 1
  fi
}

soraswap_display_path() {
  local path="${1:-}"
  local root_abs path_abs

  if [[ -z "$path" ]]; then
    return 0
  fi

  root_abs="${SORASWAP_ROOT:A}"
  path_abs="${path:A}"
  if [[ "$path_abs" == "$root_abs" ]]; then
    printf '.\n'
  elif [[ "$path_abs" == "$root_abs/"* ]]; then
    printf '%s\n' "${path_abs#$root_abs/}"
  elif [[ "$path" == /* ]]; then
    printf '%s\n' "${path:t}"
  else
    printf '%s\n' "$path"
  fi
}

soraswap_require_contract_source_hygiene() {
  local root="${1:-$SORASWAP_ROOT}"
  local prefix="${2:-soraswap}"
  local contract_path rel_contract_path

  [[ -d "$root/contracts" ]] || return 0

  while IFS= read -r -d '' contract_path; do
    [[ -n "$contract_path" ]] || continue
    rel_contract_path="${contract_path#$root/}"

    if [[ "$contract_path" == *.ko ]]; then
      continue
    fi
    if [[ "$rel_contract_path" == "contracts/shared/README.md" ]]; then
      continue
    fi

    echo "$prefix: contract source hygiene failed: $rel_contract_path is not a Kotodama .ko source" >&2
    return 1
  done < <(find "$root/contracts" -type f -print0 | LC_ALL=C sort -z)
}

soraswap_redact_runtime_paths_text() {
  local value

  if (( $# > 0 )); then
    value="${1:-}"
  else
    value="$(cat)"
  fi
  if [[ -z "$value" ]]; then
    return 0
  fi

  perl -0pe '
    sub _soraswap_path_basename {
      my $path = shift;
      $path =~ s#.*/##;
      return $path;
    }
    sub _soraswap_path_redaction {
      my $path = shift;
      my $kind = ($path =~ m#(?:^|/)Users/#) ? "[local-path]" : "[runtime-path]";
      return $kind . "/" . _soraswap_path_basename($path);
    }
    s#file://(?:localhost)?/(?:Users|private/var/folders|var/folders|private/tmp|tmp)/[^\s",}\]]+#_soraswap_path_redaction($&)#ge;
    s#file:/(?:Users|private/var/folders|var/folders|private/tmp|tmp)/[^\s",}\]]+#_soraswap_path_redaction($&)#ge;
    s#(?<![A-Za-z0-9:/])(?:/private)?/var/folders/[^\s",}\]]+#"[runtime-path]/" . _soraswap_path_basename($&)#ge;
    s#(?<![A-Za-z0-9:/])(?:/private)?/tmp/[^\s",}\]]+#"[runtime-path]/" . _soraswap_path_basename($&)#ge;
    s#(?<![A-Za-z0-9:/])/Users/[^\s",}\]]+#"[local-path]/" . _soraswap_path_basename($&)#ge;
  ' <<<"$value"
}

soraswap_redact_sensitive_text() {
  local value
  local redacted_json

  if (( $# > 0 )); then
    value="${1:-}"
  else
    value="$(cat)"
  fi
  if [[ -z "$value" ]]; then
    return 0
  fi
  if jq -e . >/dev/null 2>&1 <<<"$value"; then
    redacted_json="$(python3 -c '
import json
import re
import sys
import urllib.parse

SENSITIVE_KEYS = {
    "privatekey",
    "secret",
    "mnemonic",
    "token",
    "accesstoken",
    "refreshtoken",
    "apitoken",
    "apikey",
    "authorization",
    "bearertoken",
    "clientsecret",
    "password",
    "passphrase",
}
SENSITIVE_PATTERNS = [
    re.compile(r"((?:authorization)\s*[:=]\s*)Bearer\s+[^,\r\n\s]+", re.IGNORECASE),
    re.compile(r"((?:authorization)\s*[:=]\s*)Basic\s+[A-Za-z0-9+/=]+", re.IGNORECASE),
    re.compile(r"((?:--?)authorization(?:=|\s+))Bearer\s+[^,\r\n\s]+", re.IGNORECASE),
    re.compile(r"((?:--?)authorization(?:=|\s+))Basic\s+[A-Za-z0-9+/=]+", re.IGNORECASE),
    re.compile(
        r"(?<![?&#A-Za-z0-9_-])((?:\"(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase)\"|(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase))\s*[:=]\s*)(\"[^\"]*\"|[^,}\s]+)",
        re.IGNORECASE,
    ),
    re.compile(
        r"(?<![?&#A-Za-z0-9_-])((?:--?)(?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)(?:=|\s+))(\"[^\"]*\"|[^,\s]+)",
        re.IGNORECASE,
    ),
]
URL_PATTERN = re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s\"\)\]}>]+", re.IGNORECASE)


def sensitive_key(value):
    normalized = re.sub(r"[^a-z0-9]", "", str(value).lower())
    return normalized in SENSITIVE_KEYS


def redact_url_params(value):
    if not value:
        return value
    parts = []
    changed = False
    for raw_part in value.split("&"):
        if "=" in raw_part:
            key, raw_param_value = raw_part.split("=", 1)
        else:
            key, raw_param_value = raw_part, ""
        if sensitive_key(urllib.parse.unquote_plus(key)):
            parts.append(f"{key}=[redacted]")
            changed = True
        else:
            parts.append(raw_part)
    return "&".join(parts) if changed else value


def redact_url_value(match):
    raw = match.group(0)
    try:
        parsed = urllib.parse.urlsplit(raw)
    except ValueError:
        return raw
    if not parsed.scheme or not parsed.netloc:
        return raw

    netloc = parsed.netloc
    if "@" in netloc:
        netloc = "[redacted]@" + netloc.rsplit("@", 1)[1]

    query = redact_url_params(parsed.query)
    fragment = redact_url_params(parsed.fragment)
    if netloc == parsed.netloc and query == parsed.query and fragment == parsed.fragment:
        return raw
    return urllib.parse.urlunsplit((parsed.scheme, netloc, parsed.path, query, fragment))


def redact_text(value):
    text = str(value)
    text = URL_PATTERN.sub(redact_url_value, text)
    for pattern in SENSITIVE_PATTERNS:
        text = pattern.sub(lambda match: match.group(1) + "\"[redacted]\"", text)
    return text


def redact(value):
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        redacted = {}
        for raw_key, item in value.items():
            key = redact_text(raw_key)
            redacted[key] = "[redacted]" if sensitive_key(raw_key) else redact(item)
        return redacted
    return value


print(json.dumps(redact(json.load(sys.stdin)), separators=(",", ":"), ensure_ascii=False))
' <<<"$value" 2>/dev/null)" && {
      soraswap_redact_runtime_paths_text "$redacted_json"
      return 0
    }
  fi

  perl -0pe '
    s~\b([a-z][a-z0-9+.-]*://)[^/\s:@?#]+(?::[^/\s@?#]*)?@~${1}[redacted]@~gim;
    s~([?&#](?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)=)[^&#\s",}\]]+~${1}[redacted]~gim;
    s/((?:authorization)\s*[:=]\s*)Bearer\s+[^,\r\n[:space:]]+/$1"[redacted]"/gim;
    s/((?:authorization)\s*[:=]\s*)Basic\s+[A-Za-z0-9+\/=]+/$1"[redacted]"/gim;
    s/((?:--?)authorization(?:=|\s+))Bearer\s+[^,\r\n[:space:]]+/$1"[redacted]"/gim;
    s/((?:--?)authorization(?:=|\s+))Basic\s+[A-Za-z0-9+\/=]+/$1"[redacted]"/gim;
    s/(?<![?&#A-Za-z0-9_-])((?:"(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase)"|(?:private[_ -]?key|privateKey|secret|mnemonic|api[_ -]?token|apiToken|access[_ -]?token|accessToken|refresh[_ -]?token|refreshToken|api[_ -]?key|apiKey|authorization|bearer[_ -]?token|bearerToken|client[_ -]?secret|clientSecret|token|password|passphrase))\s*[:=]\s*)("[^"]*"|'\''[^'\'']*'\''|[^,}\s]+)/$1"[redacted]"/gim;
    s/(?<![?&#A-Za-z0-9_-])((?:--?)(?:private[-_]?key|secret|mnemonic|api[-_]?token|access[-_]?token|refresh[-_]?token|api[-_]?key|authorization|bearer[-_]?token|client[-_]?secret|token|password|passphrase)(?:=|\s+))("[^"]*"|'\''[^'\'']*'\''|[^,\s]+)/$1"[redacted]"/gim;
  ' <<<"$value" | soraswap_redact_runtime_paths_text
}

soraswap_print_preflight_report_reasons() {
  local preflight_file="$1"
  local label="${2-preflight}"
  local reason_prefix

  if [[ -n "$label" ]]; then
    reason_prefix="$label "
  else
    reason_prefix=""
  fi

  if jq -e '(.blockers // []) | type == "array" and length > 0' "$preflight_file" >/dev/null 2>&1; then
    while IFS= read -r blocker; do
      [[ -n "$blocker" ]] || continue
      echo "  ${reason_prefix}blocker: $(soraswap_redact_sensitive_text "$blocker")" >&2
    done < <(jq -r '(.blockers // [])[] | tostring' "$preflight_file" 2>/dev/null || true)
  fi

  if jq -e '(.warnings // []) | type == "array" and length > 0' "$preflight_file" >/dev/null 2>&1; then
    while IFS= read -r warning; do
      [[ -n "$warning" ]] || continue
      echo "  ${reason_prefix}warning: $(soraswap_redact_sensitive_text "$warning")" >&2
    done < <(jq -r '(.warnings // [])[] | tostring' "$preflight_file" 2>/dev/null || true)
  fi

  if jq -e '(.endpoint.health_issues // []) | type == "array" and length > 0' "$preflight_file" >/dev/null 2>&1; then
    while IFS= read -r health_issue; do
      [[ -n "$health_issue" ]] || continue
      echo "  ${reason_prefix}health issue: $(soraswap_redact_sensitive_text "$health_issue")" >&2
    done < <(jq -r '(.endpoint.health_issues // [])[] | tostring' "$preflight_file" 2>/dev/null || true)
  fi

  if jq -e '(.status // "") == "ready" or (.endpoint.health != null)' "$preflight_file" >/dev/null 2>&1; then
    if ! jq -e '((.endpoint.health.status.http_status // "") | tostring) == "200" and .endpoint.health.status.json_available == true' "$preflight_file" >/dev/null 2>&1; then
      echo "  ${reason_prefix}health issue: status endpoint health snapshot is not JSON-ready" >&2
    fi
    if ! jq -e '((.endpoint.health.sumeragi.http_status // "") | tostring) == "200" and .endpoint.health.sumeragi.json_available == true' "$preflight_file" >/dev/null 2>&1; then
      echo "  ${reason_prefix}health issue: sumeragi endpoint health snapshot is not JSON-ready" >&2
    fi
  fi

  if jq -e '(.endpoint.direct_validator_health.validators // []) | type == "array" and length > 0' "$preflight_file" >/dev/null 2>&1; then
    while IFS= read -r direct_health_summary; do
      [[ -n "$direct_health_summary" ]] || continue
      echo "  ${reason_prefix}$(soraswap_redact_sensitive_text "$direct_health_summary")" >&2
    done < <(soraswap_direct_validator_health_summary_text_from_json "$(jq -c '.endpoint.direct_validator_health' "$preflight_file" 2>/dev/null)" 2>/dev/null || true)
    while IFS= read -r direct_health_diagnosis; do
      [[ -n "$direct_health_diagnosis" ]] || continue
      echo "  ${reason_prefix}$(soraswap_redact_sensitive_text "$direct_health_diagnosis")" >&2
    done < <(soraswap_direct_validator_health_diagnosis_text_from_json "$(jq -c '.endpoint.direct_validator_health' "$preflight_file" 2>/dev/null)" 2>/dev/null || true)
  fi

  if jq -e '(.endpoint.direct_torii_port_health.validators // []) | type == "array" and length > 0' "$preflight_file" >/dev/null 2>&1; then
    while IFS= read -r port_health_summary; do
      [[ -n "$port_health_summary" ]] || continue
      echo "  ${reason_prefix}$(soraswap_redact_sensitive_text "$port_health_summary")" >&2
    done < <(soraswap_direct_validator_health_summary_text_from_json "$(jq -c '.endpoint.direct_torii_port_health' "$preflight_file" 2>/dev/null)" 2>/dev/null || true)
    while IFS= read -r port_health_diagnosis; do
      [[ -n "$port_health_diagnosis" ]] || continue
      echo "  ${reason_prefix}$(soraswap_redact_sensitive_text "$port_health_diagnosis")" >&2
    done < <(soraswap_direct_validator_health_diagnosis_text_from_json "$(jq -c '.endpoint.direct_torii_port_health' "$preflight_file" 2>/dev/null)" 2>/dev/null || true)
  fi
}

json_equals() {
  local left_json="$1"
  local right_json="$2"
  local left_tmp="" right_tmp=""
  if [[ -z "${left_json//[$'\r\n\t ']}" || -z "${right_json//[$'\r\n\t ']}" ]]; then
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$left_json"; then
    return 1
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$right_json"; then
    return 1
  fi
  left_tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-json-left.XXXXXX")" || return 1
  right_tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-json-right.XXXXXX")" || {
    rm -f "$left_tmp"
    return 1
  }
  printf '%s\n' "$left_json" > "$left_tmp"
  printf '%s\n' "$right_json" > "$right_tmp"
  local json_compare_status=0
  if jq -en --slurpfile left "$left_tmp" --slurpfile right "$right_tmp" \
    '($left | length) == 1 and ($right | length) == 1 and $left[0] == $right[0]' >/dev/null; then
    json_compare_status=0
  else
    json_compare_status=$?
  fi
  rm -f "$left_tmp" "$right_tmp"
  return "$json_compare_status"
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

soraswap_first_json_value_from_output_or_null() {
  local raw_output="${1:-}"
  local line json_value

  if json_value="$(jq -ce . <<<"$raw_output" 2>/dev/null)"; then
    printf '%s\n' "$json_value"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "${line//[$'\r\n\t ']}" ]] && continue
    if json_value="$(jq -ce . <<<"$line" 2>/dev/null)"; then
      printf '%s\n' "$json_value"
      return 0
    fi
  done <<<"$raw_output"

  echo 'null'
}

soraswap_json_array_from_output_or_empty() {
  local raw_output="${1:-}"
  local json_value

  json_value="$(soraswap_first_json_value_from_output_or_null "$raw_output")"
  jq -c 'if type == "array" then . else [] end' <<<"$json_value" 2>/dev/null || echo '[]'
}

soraswap_iroha_trigger_list_array_json() {
  local config="$1"
  local active="${2:-0}"
  local tmp_output
  typeset -a args

  args=(trigger list all)
  if [[ "$active" == "1" ]]; then
    args+=(--active)
  fi

  tmp_output="$(mktemp "${TMPDIR:-/tmp}/soraswap-trigger-list.XXXXXX")" || return 1
  if iroha_cli_json --config "$config" "${args[@]}" >"$tmp_output" 2>/dev/null \
    && jq -e . "$tmp_output" >/dev/null 2>&1; then
    jq -c 'if type == "array" then . else [] end' "$tmp_output" 2>/dev/null || echo '[]'
  else
    echo '[]'
  fi
  rm -f "$tmp_output"
}

soraswap_write_json_file_atomic() {
  local json_value="$1"
  local output_path="$2"
  local tmp_path

  tmp_path="$(mktemp "${output_path}.XXXXXX")" || return 1
  if ! printf '%s\n' "$json_value" > "$tmp_path"; then
    rm -f "$tmp_path"
    return 1
  fi
  if ! jq -e . "$tmp_path" >/dev/null 2>&1; then
    rm -f "$tmp_path"
    echo "refusing to publish invalid JSON artifact: $(soraswap_display_path "$output_path")" >&2
    return 1
  fi
  if ! mv "$tmp_path" "$output_path"; then
    rm -f "$tmp_path"
    return 1
  fi
}

soraswap_write_json_report_pair() {
  local json_value="$1"
  local latest_path="$2"
  local timestamped_path="${3:-}"

  if [[ -n "$timestamped_path" ]]; then
    soraswap_write_json_file_atomic "$json_value" "$timestamped_path" || return 1
  fi
  soraswap_write_json_file_atomic "$json_value" "$latest_path"
}

soraswap_require_positive_integer_setting() {
  local name="$1"
  local value="${2:-}"
  local pattern='^[1-9][0-9]*$'

  if [[ ! "$value" =~ $pattern ]]; then
    echo "$name must be a positive integer; got '$value'" >&2
    return 1
  fi
}

soraswap_require_nonnegative_integer_setting() {
  local name="$1"
  local value="${2:-}"
  local pattern='^[0-9]+$'

  if [[ ! "$value" =~ $pattern ]]; then
    echo "$name must be a nonnegative integer; got '$value'" >&2
    return 1
  fi
}

soraswap_require_nonnegative_integer_at_most_setting() {
  local name="$1"
  local value="${2:-}"
  local max="$3"

  soraswap_require_nonnegative_integer_setting "$name" "$value" || return 1
  if (( value > max )); then
    echo "$name must be at most $max; got '$value'" >&2
    return 1
  fi
}

soraswap_require_integer_setting() {
  local name="$1"
  local value="${2:-}"
  local pattern='^-?[0-9]+$'

  if [[ ! "$value" =~ $pattern ]]; then
    echo "$name must be an integer; got '$value'" >&2
    return 1
  fi
}

soraswap_require_positive_integer_at_most_setting() {
  local name="$1"
  local value="${2:-}"
  local max="$3"

  soraswap_require_positive_integer_setting "$name" "$value" || return 1
  if (( value > max )); then
    echo "$name must be at most $max; got '$value'" >&2
    return 1
  fi
}

soraswap_require_tcp_port_setting() {
  local name="$1"
  local value="${2:-}"

  soraswap_require_positive_integer_at_most_setting "$name" "$value" 65535
}

soraswap_require_binary_integer_setting() {
  local name="$1"
  local value="${2:-}"

  case "$value" in
    0|1)
      return 0
      ;;
    *)
      echo "$name must be 0 or 1; got '$value'" >&2
      return 1
      ;;
  esac
}

soraswap_require_nonnegative_number_setting() {
  local name="$1"
  local value="${2:-}"
  local pattern='^[0-9]+([.][0-9]+)?$'

  if [[ ! "$value" =~ $pattern ]]; then
    echo "$name must be a nonnegative number; got '$value'" >&2
    return 1
  fi
}

soraswap_validate_torii_read_max_time() {
  soraswap_require_nonnegative_number_setting "SORASWAP_TORII_READ_MAX_TIME_SECS" "$SORASWAP_TORII_READ_MAX_TIME_SECS"
}

soraswap_validate_torii_read_retry_settings() {
  soraswap_require_positive_integer_setting "SORASWAP_TORII_READ_RETRY_COUNT" "$SORASWAP_TORII_READ_RETRY_COUNT" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_TORII_READ_RETRY_DELAY_SECS" "$SORASWAP_TORII_READ_RETRY_DELAY_SECS"
}

soraswap_validate_public_write_health_settings() {
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX" "$SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX" "$SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS" "$SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT" "$SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS" "$SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT" "$SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS" "$SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS" "$SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS"
}

soraswap_torii_read_retryable_http_code() {
  case "${1:-}" in
    000|408|425|429|500|502|503|504)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

soraswap_validate_contract_alias_resolve_retry_settings() {
  soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT" "$SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS" "$SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS"
}

soraswap_contract_alias_resolve_retryable_http_code() {
  soraswap_torii_read_retryable_http_code "$1"
}

soraswap_validate_poll_window() {
  local label="$1"
  local attempts="$2"
  local sleep_seconds="${3:-1}"

  soraswap_require_nonnegative_integer_setting "$label attempts" "$attempts" || return 1
  soraswap_require_nonnegative_number_setting "$label sleep seconds" "$sleep_seconds" || return 1
}

soraswap_require_positive_json_number_setting() {
  local name="$1"
  local value="${2:-}"

  if ! jq -en --argjson value "$value" '$value | type == "number" and . > 0' >/dev/null 2>&1; then
    echo "$name must be a positive JSON number; got '$value'" >&2
    return 1
  fi
}

soraswap_require_nonnegative_json_number_setting() {
  local name="$1"
  local value="${2:-}"

  if ! jq -en --argjson value "$value" '$value | type == "number" and . >= 0' >/dev/null 2>&1; then
    echo "$name must be a nonnegative JSON number; got '$value'" >&2
    return 1
  fi
}

soraswap_require_json_number_setting() {
  local name="$1"
  local value="${2:-}"

  if ! jq -en --argjson value "$value" '$value | type == "number"' >/dev/null 2>&1; then
    echo "$name must be a JSON number; got '$value'" >&2
    return 1
  fi
}

soraswap_normalize_oracle_public_key_hex() {
  local raw_key="${1:-}"
  local value
  if [[ -z "$raw_key" ]]; then
    echo "SORASWAP_ORACLE_PUBLIC_KEY_HEX is required" >&2
    return 1
  fi
  value="${raw_key#ed25519:}"
  value="${value#ED25519:}"
  value="${value#0x}"
  value="${value#0X}"
  value="$(printf '%s' "$value" | tr -d '[:space:]')"
  if [[ "${#value}" == "70" && "${value[1,6]:l}" == "ed0120" ]]; then
    value="${value[7,-1]}"
  fi
  if [[ "${#value}" != "64" || ! "$value" =~ '^[0-9A-Fa-f]+$' ]]; then
    echo "public key must be a raw 32-byte Ed25519 key or ed0120-prefixed Iroha key" >&2
    return 1
  fi
  printf '0x%s\n' "${value:l}"
}

soraswap_local_oracle_keypair_json_for_config() {
  local config="$1"
  local chain torii_base seed cache_key key_output public_key private_key kagami_bin

  if public_env_for_config "$config" >/dev/null 2>&1; then
    return 1
  fi

  chain="$(config_chain_id_from_config "$config")"
  torii_base="$(torii_base_from_config "$config")"
  cache_key="${chain}|${torii_base}"
  if [[ -n "${SORASWAP_LOCAL_ORACLE_KEYPAIR_CACHE[$cache_key]:-}" ]]; then
    printf '%s\n' "${SORASWAP_LOCAL_ORACLE_KEYPAIR_CACHE[$cache_key]}"
    return 0
  fi

  seed="soraswap:oracle:v1:${chain}:${torii_base}"

  ensure_kagami_bin >/dev/null
  kagami_bin="${KAGAMI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/kagami}"
  key_output="$("$kagami_bin" keys --algorithm ed25519 --seed "$seed" --compact 2>/dev/null)"
  public_key="$(awk '/^ed[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  private_key="$(awk '/^8026[0-9A-Fa-f]+$/ { print; exit }' <<<"$key_output")"
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "failed to derive local oracle keypair for $(soraswap_display_path "$config")" >&2
    return 1
  fi

  SORASWAP_LOCAL_ORACLE_KEYPAIR_CACHE[$cache_key]="$( \
    SORASWAP_TMP_PUBLIC_KEY="$public_key" SORASWAP_TMP_PRIVATE_KEY="$private_key" \
      jq -cn '{public_key: env.SORASWAP_TMP_PUBLIC_KEY, private_key: env.SORASWAP_TMP_PRIVATE_KEY}'
  )"
  printf '%s\n' "${SORASWAP_LOCAL_ORACLE_KEYPAIR_CACHE[$cache_key]}"
}

soraswap_oracle_public_key_hex_for_config() {
  local config="${1:-}"
  local keypair_json

  if [[ -n "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" ]]; then
    soraswap_normalize_oracle_public_key_hex "$SORASWAP_ORACLE_PUBLIC_KEY_HEX"
    return
  fi

  if [[ -n "$config" ]]; then
    local config_public_key
    config_public_key="$(account_public_key_from_config "$config" 2>/dev/null || true)"
    if [[ -n "$config_public_key" ]]; then
      soraswap_normalize_oracle_public_key_hex "$config_public_key"
      return
    fi
  fi

  if [[ -n "$config" ]] && keypair_json="$(soraswap_local_oracle_keypair_json_for_config "$config")"; then
    soraswap_normalize_oracle_public_key_hex "$(jq -r '.public_key' <<<"$keypair_json")"
    return
  fi

  echo "SORASWAP_ORACLE_PUBLIC_KEY_HEX is required for public bootstrap; local configs use the signer key unless explicitly overridden" >&2
  return 1
}

soraswap_oracle_private_key_hex_for_config() {
  local config="${1:-}"
  local keypair_json

  if [[ -n "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" ]]; then
    printf '%s\n' "$SORASWAP_ORACLE_PRIVATE_KEY_HEX"
    return
  fi

  if [[ -n "$config" ]]; then
    local config_private_key
    config_private_key="$(account_private_key_from_config "$config" 2>/dev/null || true)"
    if [[ -n "$config_private_key" ]]; then
      printf '%s\n' "$config_private_key"
      return
    fi
  fi

  if [[ -n "$config" ]] && keypair_json="$(soraswap_local_oracle_keypair_json_for_config "$config")"; then
    jq -r '.private_key' <<<"$keypair_json"
    return
  fi

  echo "SORASWAP_ORACLE_PRIVATE_KEY_HEX is required for signed oracle smoke on public configs; local configs use the signer key unless explicitly overridden" >&2
  return 1
}

soraswap_required_oracle_public_key_hex() {
  soraswap_oracle_public_key_hex_for_config "${1:-}"
}

soraswap_oracle_payload_python() {
  local candidate candidate_path
  local -a candidates

  candidates=()
  if [[ -n "${SORASWAP_ORACLE_PYTHON_BIN:-}" ]]; then
    candidates+=("$SORASWAP_ORACLE_PYTHON_BIN")
  fi
  candidates+=(python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3)

  for candidate in "${candidates[@]}"; do
    candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
    if [[ -z "$candidate_path" ]]; then
      continue
    fi
    if "$candidate_path" - <<'PY' >/dev/null 2>&1; then
import nacl.signing
PY
      printf '%s\n' "$candidate_path"
      return 0
    fi
  done

  echo "no Python interpreter with PyNaCl/nacl.signing is available for oracle signing" >&2
  echo "install PyNaCl for python3 or set SORASWAP_ORACLE_PYTHON_BIN to a compatible interpreter" >&2
  return 1
}

soraswap_oracle_payload_script_path() {
  local candidate
  typeset -a candidates

  candidates=(
    "$SORASWAP_SCRIPT_DIR/oracle_payload.py"
    "$SORASWAP_SCRIPT_DIR/scripts/oracle_payload.py"
    "$SORASWAP_ROOT/scripts/oracle_payload.py"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "oracle payload signing helper not found under script directory or SORASWAP_ROOT" >&2
  return 1
}

soraswap_current_block_height() {
  local config="$1"
  local torii_base response height best_height attempt sample_attempts

  soraswap_validate_torii_read_max_time || return 1
  sample_attempts="${SORASWAP_BLOCK_HEIGHT_SAMPLE_ATTEMPTS:-}"
  torii_base="$(torii_base_from_config "$config")"
  if [[ -z "$sample_attempts" ]]; then
    case "$torii_base" in
      http://127.0.0.1*|http://localhost*|https://127.0.0.1*|https://localhost*)
        sample_attempts=1
        ;;
      *)
        sample_attempts=3
        ;;
    esac
  fi
  soraswap_require_positive_integer_setting "SORASWAP_BLOCK_HEIGHT_SAMPLE_ATTEMPTS" "$sample_attempts" || return 1

  best_height=0
  for (( attempt = 1; attempt <= sample_attempts; attempt++ )); do
    response="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/status/blocks" 2>/dev/null || true)"
    if [[ -n "$response" ]]; then
      height="$(jq -r 'if type == "number" then . else empty end' <<<"$response" 2>/dev/null || true)"
      if [[ -n "$height" && "$height" == <-> && "$height" -gt "$best_height" ]]; then
        best_height="$height"
      fi
    fi

    response="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/status" 2>/dev/null || true)"
    if [[ -n "$response" ]]; then
      height="$(jq -r '[.blocks?, .sumeragi.commit_qc_height?] | map(tonumber? // empty) | max // empty' <<<"$response" 2>/dev/null || true)"
      if [[ -n "$height" && "$height" == <-> && "$height" -gt "$best_height" ]]; then
        best_height="$height"
      fi
    fi

    response="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/v1/sumeragi/status" 2>/dev/null || true)"
    if [[ -n "$response" ]]; then
      height="$(jq -r '[.commit_qc.height?, .highest_qc.height?] | map(tonumber? // empty) | max // empty' <<<"$response" 2>/dev/null || true)"
      if [[ -n "$height" && "$height" == <-> && "$height" -gt "$best_height" ]]; then
        best_height="$height"
      fi
    fi
  done

  echo "$best_height"
}

soraswap_submit_block_height_tick() {
  local config="$1"
  local label="${2:-block-height-wait}"
  local safe_label

  safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9_.:-' '-' | cut -c1-48)"
  if [[ -z "$safe_label" ]]; then
    safe_label="block-height-wait"
  fi

  iroha_cli_with_gas_metadata "$config" ledger transaction ping \
    --msg "soraswap-${safe_label}-tick" \
    --no-wait >/dev/null 2>&1
}

soraswap_wait_for_block_height_at_least() {
  local config="$1"
  local target_height="$2"
  local label="${3:-block height}"
  local attempts="${4:-${SORASWAP_BLOCK_WAIT_ATTEMPTS:-120}}"
  local tick_blocks="${5:-${SORASWAP_BLOCK_WAIT_TICK:-0}}"
  local queued_stall_max_ms="${6:-${SORASWAP_BLOCK_WAIT_QUEUED_STALL_MAX_MS:-0}}"
  local height last_tick_height health_snapshot health_summary iteration

  if [[ -z "$target_height" || "$target_height" == "null" || "$target_height" != <-> ]]; then
    echo "invalid target block height for $label: $target_height" >&2
    return 1
  fi
  soraswap_require_positive_integer_setting "block wait attempts for $label" "$attempts" || return 1
  soraswap_require_nonnegative_integer_setting "queued-write stall threshold for $label" "$queued_stall_max_ms" || return 1
  case "$tick_blocks" in
    0|1|true|false|yes|no|on|off)
      ;;
    *)
      echo "block wait tick flag for $label must be 0, 1, true, false, yes, no, on, or off; got '$tick_blocks'" >&2
      return 1
      ;;
  esac

  last_tick_height=""
  iteration=0
  while (( attempts > 0 )); do
    iteration=$(( iteration + 1 ))
    height="$(soraswap_current_block_height "$config")"
    if [[ -n "$height" && "$height" != "null" && "$height" == <-> ]]; then
      if (( height >= target_height )); then
        return 0
      fi
    fi
    if [[ "$tick_blocks" == "1" || "$tick_blocks" == "true" || "$tick_blocks" == "yes" || "$tick_blocks" == "on" ]]; then
      if [[ -z "$height" || "$height" == "null" || "$height" != <-> || "$height" != "$last_tick_height" ]]; then
        soraswap_submit_block_height_tick "$config" "$label" || true
        last_tick_height="$height"
      fi
    fi
    if (( queued_stall_max_ms > 0 && iteration % 15 == 0 )); then
      health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
      if [[ -n "$health_snapshot" && "$health_snapshot" != "null" ]] \
        && soraswap_public_chain_queued_stall_detected "$health_snapshot" "$queued_stall_max_ms"; then
        health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
        if [[ -n "$health_summary" ]]; then
          echo "queued-write finality stall while waiting for $label block height >= $target_height: $health_summary" >&2
        else
          echo "queued-write finality stall while waiting for $label block height >= $target_height" >&2
        fi
        return 75
      fi
    fi
    attempts=$(( attempts - 1 ))
    sleep 1
  done

  echo "timed out waiting for $label block height >= $target_height; last height=${height:-unknown}" >&2
  health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
  if [[ -n "$health_snapshot" && "$health_snapshot" != "null" ]]; then
    health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
    if [[ -n "$health_summary" ]]; then
      echo "chain health while waiting for $label: $health_summary" >&2
    fi
  fi
  return 1
}

soraswap_oracle_slot_lag_for_config() {
  local config="$1"
  local lag="${SORASWAP_ORACLE_SLOT_LAG:-}"

  if [[ -z "$lag" ]]; then
    if public_env_for_config "$config" >/dev/null 2>&1; then
      lag=2
    else
      lag=0
    fi
  fi
  soraswap_require_nonnegative_integer_setting "SORASWAP_ORACLE_SLOT_LAG" "$lag" || return 1
  printf '%s\n' "$lag"
}

soraswap_observe_oracle_slot() {
  local slot="${1:-}"

  typeset -g SORASWAP_LAST_ORACLE_SLOT="${SORASWAP_LAST_ORACLE_SLOT:-0}"
  if [[ "$slot" == <-> && "$slot" != "" && "$slot" != "null" ]]; then
    if (( slot > SORASWAP_LAST_ORACLE_SLOT )); then
      SORASWAP_LAST_ORACLE_SLOT="$slot"
    fi
  fi
}

soraswap_next_oracle_slot() {
  local config="$1"
  local height attempts lag candidate

  typeset -g SORASWAP_LAST_ORACLE_SLOT="${SORASWAP_LAST_ORACLE_SLOT:-0}"
  lag="$(soraswap_oracle_slot_lag_for_config "$config")" || return 1
  attempts=0
  while true; do
    height="$(soraswap_current_block_height "$config")"
    if [[ -z "$height" || "$height" == "null" || "$height" != <-> ]]; then
      height=0
    fi
    if (( height < 1 )); then
      if (( SORASWAP_LAST_ORACLE_SLOT < 1 )); then
        SORASWAP_LAST_ORACLE_SLOT=1
      fi
      echo "$SORASWAP_LAST_ORACLE_SLOT"
      return 0
    fi
    candidate=$(( height - lag ))
    if (( candidate < 1 )); then
      candidate=1
    fi
    if (( candidate > SORASWAP_LAST_ORACLE_SLOT )); then
      SORASWAP_LAST_ORACLE_SLOT="$candidate"
      echo "$candidate"
      return 0
    fi
    if (( attempts >= 12 )); then
      echo "oracle block height did not advance past $SORASWAP_LAST_ORACLE_SLOT with lag $lag" >&2
      return 1
    fi
    sleep 1
    attempts=$(( attempts + 1 ))
  done
}

soraswap_native_oracle_attestation_json() {
  local config="$1"
  local domain="$2"
  local subject_id="$3"
  local response_json="" torii_base endpoint response http_code body

  torii_base="$(torii_base_from_config "$config")"
  endpoint="$torii_base/v1/soracles/defi/attestations/latest?domain=$(uri_encode "$domain")&subject_id=$(uri_encode "$subject_id")"
  if response="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -w $'\n%{http_code}' \
    "$endpoint" 2>/dev/null)"; then
    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"
    if [[ "$http_code" == "200" ]] && jq -e . >/dev/null 2>&1 <<<"$body"; then
      response_json="$body"
    elif [[ "$http_code" == "404" ]]; then
      echo "native DeFi oracle attestation not found for domain=$domain subject_id=$subject_id" >&2
      return 1
    fi
  fi

  if [[ -z "$response_json" ]]; then
    response_json="$(iroha_cli_json --config "$config" app soracles query defi-attestation \
      --domain "$domain" \
      --subject-id "$subject_id")" || {
        echo "native DeFi oracle attestation not found for domain=$domain subject_id=$subject_id" >&2
        return 1
      }
  fi

  jq -ce . <<<"$response_json"
}

soraswap_native_oracle_fields_json() {
  local config="$1"
  local domain="$2"
  local subject_id="$3"
  local response_json

  response_json="$(soraswap_native_oracle_attestation_json "$config" "$domain" "$subject_id")" || return 1

  jq -ce --argjson raw "$response_json" '
    def hex_digit:
      ((. / 16) | floor) as $hi
      | (. % 16) as $lo
      | "0123456789abcdef"[$hi:$hi + 1]
        + "0123456789abcdef"[$lo:$lo + 1];
    def bytes_hex:
      if type == "string" then
        if startswith("0x") or startswith("0X") then . else "0x" + . end
      elif type == "array" then
        "0x" + (map(hex_digit) | join(""))
      else
        empty
      end;
    ($raw.data // $raw.result // $raw) as $a
    | {
        oracle_payload: (($a.oracle_payload // $a.oraclePayload) | bytes_hex),
        oracle_signature: (($a.oracle_signature // $a.oracleSignature) | bytes_hex)
      }
    | select(.oracle_payload != null and .oracle_signature != null)
  ' || {
    echo "native DeFi oracle attestation response did not include oracle payload/signature" >&2
    return 1
  }
}

soraswap_sign_oracle_payload_json() {
  local config="$1"
  local payload_json="$2"
  local private_key expected_public_key actual_public_key python_bin payload_script private_key_file signed_status public_env

  expected_public_key="$(soraswap_oracle_public_key_hex_for_config "$config")" || return 1
  python_bin="$(soraswap_oracle_payload_python)" || return 1
  payload_script="$(soraswap_oracle_payload_script_path)" || return 1
  local signed_json
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -n "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" ]]; then
    private_key_file="$(printf '%s\n' "$SORASWAP_ORACLE_PRIVATE_KEY_HEX" \
      | soraswap_secret_temp_from_stdin oracle-private-key)" || return 1
  elif [[ -n "$public_env" ]]; then
    private_key_file="$(soraswap_config_private_key_temp_file "$config" oracle-private-key)" || return 1
  else
    private_key="$(soraswap_oracle_private_key_hex_for_config "$config")" || return 1
    private_key_file="$(printf '%s\n' "$private_key" \
      | soraswap_secret_temp_from_stdin oracle-private-key)" || return 1
  fi
  {
    if signed_json="$(SORASWAP_ORACLE_PRIVATE_KEY_HEX= "$python_bin" "$payload_script" \
      --payload-json "$payload_json" \
      --private-key-file "$private_key_file")"; then
      signed_status=0
    else
      signed_status=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_file "$private_key_file"; then
      signed_status=1
    fi
  }
  (( signed_status == 0 )) || return "$signed_status"
  actual_public_key="$(soraswap_normalize_oracle_public_key_hex "$(jq -r '.oracle_public_key' <<<"$signed_json")")" || return 1
  if [[ "$actual_public_key" != "$expected_public_key" ]]; then
    echo "oracle private key does not match SORASWAP_ORACLE_PUBLIC_KEY_HEX/config signer public key" >&2
    return 1
  fi

  printf '%s\n' "$signed_json"
}

soraswap_oracle_keypair_matches_for_config() {
  local config="${1:-}"
  local probe_payload

  probe_payload='{"soraswap_oracle_keypair_probe":1}'
  soraswap_sign_oracle_payload_json "$config" "$probe_payload" >/dev/null
}

soraswap_submit_native_defi_attestation() {
  local config="$1"
  local domain="$2"
  local subject_id="$3"
  local oracle_slot="$4"
  local status_flags="$5"
  local attestation_hash="$6"
  local signed_json="$7"
  local provider account_public_key oracle_public_key attestation_file
  local exit_code

  provider="$(authority_from_config "$config")" || {
    echo "failed to derive DeFi oracle provider account from $(soraswap_display_path "$config")" >&2
    return 1
  }
  account_public_key="$(soraswap_normalize_oracle_public_key_hex "$(account_public_key_from_config "$config")")"
  oracle_public_key="$(soraswap_oracle_public_key_hex_for_config "$config")"
  if [[ "$account_public_key" != "$oracle_public_key" ]]; then
    echo "native DeFi oracle attestations must be signed by the submitting provider account key" >&2
    return 1
  fi

  attestation_file="$(mktemp "${TMPDIR:-/tmp}/soraswap-defi-attestation.XXXXXX")"
  jq -cn \
    --arg provider "$provider" \
    --argjson domain "$domain" \
    --argjson subject_id "$subject_id" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    --argjson oracle_payload "$(jq -c '.oracle_payload_bytes' <<<"$signed_json")" \
    --argjson oracle_signature "$(jq -c '.oracle_signature_bytes' <<<"$signed_json")" \
    --argjson signer_public_key "$(jq -c '.oracle_public_key_bytes' <<<"$signed_json")" \
    '{
      key: {
        domain: $domain,
        subject_id: $subject_id
      },
      provider: $provider,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash,
      oracle_payload: $oracle_payload,
      oracle_signature: $oracle_signature,
      signer_public_key: $signer_public_key,
      oracle_scheme: 1,
      source_events: []
    }' > "$attestation_file"

  if iroha_cli_with_gas_metadata "$config" app soracles tx attest-defi --attestation-json "$attestation_file" >/dev/null; then
    exit_code=0
  else
    exit_code=$?
  fi
  rm -f "$attestation_file"
  return "$exit_code"
}

soraswap_wait_native_oracle_attestation_json() {
  local config="$1"
  local domain="$2"
  local subject_id="$3"
  local attempts=0
  local attestation_json

  while (( attempts < 20 )); do
    if attestation_json="$(soraswap_native_oracle_attestation_json "$config" "$domain" "$subject_id" 2>/dev/null)"; then
      printf '%s\n' "$attestation_json"
      return 0
    fi
    attempts=$(( attempts + 1 ))
    sleep 1
  done

  soraswap_native_oracle_attestation_json "$config" "$domain" "$subject_id"
}

soraswap_use_native_oracle_fields_json() {
  local config="$1"
  local domain="$2"
  local subject_id="$3"
  local payload_json="$4"
  local oracle_slot="$5"
  local status_flags="$6"
  local attestation_hash="$7"
  local signed_json

  signed_json="$(soraswap_sign_oracle_payload_json "$config" "$payload_json")" || return 1
  soraswap_submit_native_defi_attestation \
    "$config" \
    "$domain" \
    "$subject_id" \
    "$oracle_slot" \
    "$status_flags" \
    "$attestation_hash" \
    "$signed_json" || return 1
  soraswap_wait_native_oracle_attestation_json "$config" "$domain" "$subject_id" >/dev/null || return 1
  jq -ce '{oracle_payload, oracle_signature}' <<<"$signed_json"
}

soraswap_perps_oracle_fields_json() {
  local config="$1"
  local market_id="$2"
  local mark_price_bps="$3"
  local index_price_bps="$4"
  local confidence_bps="$5"
  local attestation_hash="$6"
  local status_flags="${7:-0}"
  local oracle_slot="${8:-}"
  if [[ -z "$oracle_slot" ]]; then
    oracle_slot="$(soraswap_next_oracle_slot "$config")" || return 1
  fi
  local payload_json
  payload_json="$(jq -cn \
    --argjson domain 1 \
    --argjson market_id "$market_id" \
    --argjson mark_price_bps "$mark_price_bps" \
    --argjson index_price_bps "$index_price_bps" \
    --argjson confidence_bps "$confidence_bps" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    '{
      domain: $domain,
      market_id: $market_id,
      mark_price_bps: $mark_price_bps,
      index_price_bps: $index_price_bps,
      confidence_bps: $confidence_bps,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }')"
  soraswap_use_native_oracle_fields_json "$config" 1 "$market_id" "$payload_json" "$oracle_slot" "$status_flags" "$attestation_hash"
}

soraswap_options_series_oracle_fields_json() {
  local config="$1"
  local series_id="$2"
  local final_mark="$3"
  local final_quote_mark="$4"
  local attestation_hash="$5"
  local status_flags="${6:-0}"
  local oracle_slot="${7:-}"
  if [[ -z "$oracle_slot" ]]; then
    oracle_slot="$(soraswap_next_oracle_slot "$config")" || return 1
  fi
  local payload_json
  payload_json="$(jq -cn \
    --argjson domain 2 \
    --argjson series_id "$series_id" \
    --argjson final_mark "$final_mark" \
    --argjson final_quote_mark "$final_quote_mark" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    '{
      domain: $domain,
      series_id: $series_id,
      final_mark: $final_mark,
      final_quote_mark: $final_quote_mark,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }')"
  soraswap_use_native_oracle_fields_json "$config" 2 "$series_id" "$payload_json" "$oracle_slot" "$status_flags" "$attestation_hash"
}

soraswap_shout_oracle_fields_json() {
  local config="$1"
  local position_id="$2"
  local mark_price_bps="$3"
  local attestation_hash="$4"
  local status_flags="${5:-0}"
  local oracle_slot="${6:-}"
  if [[ -z "$oracle_slot" ]]; then
    oracle_slot="$(soraswap_next_oracle_slot "$config")" || return 1
  fi
  local payload_json
  payload_json="$(jq -cn \
    --argjson domain 3 \
    --argjson position_id "$position_id" \
    --argjson mark_price_bps "$mark_price_bps" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    '{
      domain: $domain,
      position_id: $position_id,
      mark_price_bps: $mark_price_bps,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }')"
  soraswap_use_native_oracle_fields_json "$config" 3 "$position_id" "$payload_json" "$oracle_slot" "$status_flags" "$attestation_hash"
}

soraswap_cover_oracle_fields_json() {
  local config="$1"
  local policy_id="$2"
  local observed_price="$3"
  local attestation_hash="$4"
  local status_flags="${5:-0}"
  local oracle_slot="${6:-}"
  if [[ -z "$oracle_slot" ]]; then
    oracle_slot="$(soraswap_next_oracle_slot "$config")" || return 1
  fi
  local payload_json
  payload_json="$(jq -cn \
    --argjson domain 4 \
    --argjson policy_id "$policy_id" \
    --argjson observed_price "$observed_price" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    '{
      domain: $domain,
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }')"
  soraswap_use_native_oracle_fields_json "$config" 4 "$policy_id" "$payload_json" "$oracle_slot" "$status_flags" "$attestation_hash"
}

soraswap_cover_contract_oracle_fields_json() {
  local config="$1"
  local policy_id="$2"
  local observed_price="$3"
  local attestation_hash="$4"
  local status_flags="${5:-0}"
  local oracle_slot="${6:-}"
  if [[ -z "$oracle_slot" ]]; then
    oracle_slot="$(soraswap_next_oracle_slot "$config")" || return 1
  fi
  local payload_json signed_json
  payload_json="$(jq -cn \
    --argjson domain 4 \
    --argjson policy_id "$policy_id" \
    --argjson observed_price "$observed_price" \
    --argjson oracle_slot "$oracle_slot" \
    --argjson status_flags "$status_flags" \
    --argjson attestation_hash "$attestation_hash" \
    '{
      domain: $domain,
      policy_id: $policy_id,
      observed_price: $observed_price,
      oracle_slot: $oracle_slot,
      status_flags: $status_flags,
      attestation_hash: $attestation_hash
    }')"
  signed_json="$(soraswap_sign_oracle_payload_json "$config" "$payload_json")" || return 1
  jq -ce '{oracle_payload, oracle_signature}' <<<"$signed_json"
}

strict_chain_fingerprint_json_or_null() {
  local raw="${1:-}"
  local normalized

  normalized="$(normalize_json_or_null "$raw")" || return 1
  if [[ "$normalized" == "null" ]]; then
    echo 'null'
    return 0
  fi

  if ! jq -e '
    ((.torii_url // "") | type == "string" and length > 0)
      and ((.chain // "") | type == "string" and length > 0)
      and ((.block_1_hash // "") | type == "string" and length > 0)
  ' <<<"$normalized" >/dev/null; then
    echo "chain fingerprint JSON must include non-empty torii_url, chain, and block_1_hash" >&2
    return 1
  fi

  jq -c '{torii_url, chain, block_1_hash}' <<<"$normalized"
}

chain_fingerprint_json_or_null() {
  strict_chain_fingerprint_json_or_null "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}"
}

deployment_evidence_requires_chain_fingerprint() {
  local env="$1"

  case "$env" in
    local|testnet|production)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

chain_fingerprint_json_is_complete() {
  local fingerprint_json="$1"

  jq -e '
    type == "object"
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' <<<"$fingerprint_json" >/dev/null 2>&1
}

require_deployment_evidence_chain_fingerprint() {
  local env="$1"
  local fingerprint_json="$2"
  local context="$3"

  if ! deployment_evidence_requires_chain_fingerprint "$env"; then
    return 0
  fi
  if chain_fingerprint_json_is_complete "$fingerprint_json"; then
    return 0
  fi

  echo "${context} for ${env} requires a complete chain fingerprint; call prepare_env_chain_state before writing deployment evidence" >&2
  return 1
}

contract_bundle_receipt_chain_fingerprint_json_for_env() {
  local env="$1"
  local chain_fingerprint_json

  case "$env" in
    testnet|production)
      chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
      require_deployment_evidence_chain_fingerprint "$env" "$chain_fingerprint_json" "contract bundle receipt" || return 1
      printf '%s\n' "$chain_fingerprint_json"
      ;;
    *)
      chain_fingerprint_json_or_null 2>/dev/null || echo 'null'
      ;;
  esac
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

numeric_gte() {
  local value="${1:-}"
  local minimum="${2:-}"
  /usr/bin/python3 - "$value" "$minimum" <<'PY'
from decimal import Decimal, InvalidOperation
import sys

try:
    value = Decimal(sys.argv[1].strip())
    minimum = Decimal(sys.argv[2].strip())
except (InvalidOperation, IndexError):
    raise SystemExit(1)
raise SystemExit(0 if value >= minimum else 1)
PY
}

soraswap_production_min_fee_balance() {
  local minimum="${SORASWAP_PRODUCTION_MIN_FEE_BALANCE:-}"

  if [[ -z "$minimum" ]]; then
    echo "production requires an independently approved SORASWAP_PRODUCTION_MIN_FEE_BALANCE" >&2
    return 1
  fi
  soraswap_require_nonnegative_number_setting "SORASWAP_PRODUCTION_MIN_FEE_BALANCE" "$minimum" || return 1
  if ! numeric_gt_zero "$minimum"; then
    echo "SORASWAP_PRODUCTION_MIN_FEE_BALANCE must be greater than zero" >&2
    return 1
  fi
  printf '%s\n' "$minimum"
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
      if [[ -z "$override" ]]; then
        echo "production requires SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID" >&2
        return 1
      fi
      ;;
  esac

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  if [[ -n "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID" ]]; then
    printf '%s\n' "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID"
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
      if [[ -z "$override" ]]; then
        override="$SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID"
      fi
      if [[ -z "$override" ]]; then
        echo "production requires SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID" >&2
        return 1
      fi
      ;;
  esac

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  if [[ -z "$public_env" && -n "$SORASWAP_LOCAL_FEE_ASSET_LABEL" ]]; then
    printf '%s\n' "$SORASWAP_LOCAL_FEE_ASSET_LABEL"
    return 0
  fi

  printf '%s\n' "$SORASWAP_FEE_ASSET_ALIAS"
}

gas_metadata_asset_id_for_config() {
  local config="$1"
  local public_env label

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -z "$public_env" && -n "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID" ]]; then
    printf '%s\n' "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID"
    return 0
  fi

  label="$(fee_asset_label_for_config "$config" 2>/dev/null || true)"
  if [[ -n "$label" ]]; then
    if [[ "$label" == *"#"* ]] && ! asset_definition_alias_exists "$config" "$label"; then
      fee_asset_definition_id_for_config "$config"
      return 0
    fi
    printf '%s\n' "$label"
    return 0
  fi

  fee_asset_definition_id_for_config "$config"
}

localnet_fee_asset_definition_id_for_config() {
  local config="$1"
  local config_dir peer_config value

  config_dir="${config:h}"
  for peer_config in "$config_dir"/peer*.toml; do
    [[ -f "$peer_config" ]] || continue
    value="$(awk '
      function clean(raw) {
        sub(/^[^=]*=/, "", raw)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
        gsub(/^"|"$/, "", raw)
        return raw
      }
      /^\[/ {
        section = $0
        next
      }
      section == "[torii.faucet]" && $1 == "asset_definition_id" {
        print clean($0)
        found = 1
        exit
      }
      section == "[nexus.fees]" && $1 == "fee_asset_id" && fallback == "" {
        fallback = clean($0)
      }
      END {
        if (!found && fallback != "") {
          print fallback
        }
      }
    ' "$peer_config")"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
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

cargo_lock_holder_pid() {
  local cargo_lock="$1"

  { lsof -t "$cargo_lock" 2>/dev/null || true; } \
    | awk -v self="$$" '$1 != self { print; exit }'
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

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_IROHA_CLI_BUILD" "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" || return 1

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
      echo "cli tool: reusing existing iroha binary $(soraswap_display_path "$fallback_bin")" >&2
      return 0
    fi
    echo "missing iroha binary at $(soraswap_display_path "$debug_bin") or $(soraswap_display_path "$release_bin") and SORASWAP_SKIP_IROHA_CLI_BUILD=1" >&2
    return 1
  fi

  if [[ -z "$fallback_bin" ]]; then
    rebuild=1
    rebuild_reason="cli tool: building iroha binary"
  else
    bin="$fallback_bin"
  fi

  if [[ -n "$fallback_bin" ]] && path_is_newer_than "$fallback_bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_crypto" \
    "$SORASWAP_IROHA_ROOT/crates/ivm" \
    "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    rebuild=1
    rebuild_reason="cli tool: rebuilding iroha binary because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    if [[ -n "$fallback_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        SORASWAP_ACTIVE_IROHA_CLI_BIN="$fallback_bin"
        echo "cli tool: sibling cargo job holds $(soraswap_display_path "$cargo_lock"); reusing existing iroha binary $(soraswap_display_path "$fallback_bin")" >&2
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

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_IROHA_CLI_BUILD" "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" || return 1

  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    if [[ -x "$bin" ]]; then
      echo "cli tool: reusing existing split_contract_deploy binary" >&2
      SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN="$bin"
      return 0
    fi
    echo "missing split_contract_deploy binary at $(soraswap_display_path "$bin") and SORASWAP_SKIP_IROHA_CLI_BUILD=1" >&2
    return 1
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_crypto"; then
    if [[ -x "$debug_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        SORASWAP_ACTIVE_SPLIT_CONTRACT_DEPLOY_BIN="$debug_bin"
        echo "cli tool: sibling cargo job holds $(soraswap_display_path "$cargo_lock"); reusing existing split_contract_deploy binary $(soraswap_display_path "$debug_bin")" >&2
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

ensure_gov_instruction_bin() {
  local debug_bin="$SORASWAP_IROHA_ROOT/target/debug/gov_instruction"
  local bin="$debug_bin"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""
  local rebuild=0
  local rebuild_reason=""

  if [[ ! -x "$debug_bin" ]]; then
    rebuild=1
    rebuild_reason="gov instruction tool: building gov_instruction binary"
  elif path_is_newer_than "$debug_bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_cli/src/bin/gov_instruction.rs" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_core/src/zk.rs" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_core/src/smartcontracts/ivm/host.rs" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_data_model" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_sccp"; then
    rebuild=1
    rebuild_reason="gov instruction tool: rebuilding gov_instruction because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    if [[ -x "$debug_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        SORASWAP_ACTIVE_GOV_INSTRUCTION_BIN="$debug_bin"
        echo "gov instruction tool: sibling cargo job holds $(soraswap_display_path "$cargo_lock"); reusing existing binary $(soraswap_display_path "$debug_bin")" >&2
        return 0
      fi
    fi
    echo "$rebuild_reason" >&2
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_cli --bin gov_instruction
    )
  fi

  SORASWAP_ACTIVE_GOV_INSTRUCTION_BIN="$bin"
}

gov_instruction_bin() {
  ensure_gov_instruction_bin
  printf '%s\n' "$SORASWAP_ACTIVE_GOV_INSTRUCTION_BIN"
}

ensure_localnet_tool_bins() {
  local irohad_bin="$SORASWAP_IROHA_ROOT/target/debug/irohad"
  local iroha_bin="$SORASWAP_IROHA_ROOT/target/debug/iroha"
  local kagami_bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_LOCALNET_TOOL_BUILD" "${SORASWAP_SKIP_LOCALNET_TOOL_BUILD:-0}" || return 1

  if [[ -n "${IROHAD_BIN:-}" || -n "${IROHA_BIN:-}" || -n "${KAGAMI_BIN:-}" ]]; then
    irohad_bin="${IROHAD_BIN:-$irohad_bin}"
    iroha_bin="${IROHA_BIN:-$iroha_bin}"
    kagami_bin="${KAGAMI_BIN:-$kagami_bin}"
    if [[ -x "$irohad_bin" && -x "$iroha_bin" && -x "$kagami_bin" ]]; then
      echo "localnet tools: reusing explicit iroha/kagami binary paths" >&2
      return 0
    fi
    echo "localnet tools: one or more explicit binary paths are missing or not executable" >&2
    echo "  IROHAD_BIN=$irohad_bin" >&2
    echo "  IROHA_BIN=$iroha_bin" >&2
    echo "  KAGAMI_BIN=$kagami_bin" >&2
    return 1
  fi

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
    if [[ -x "$irohad_bin" && -x "$iroha_bin" && -x "$kagami_bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        echo "localnet tools: sibling cargo job holds $cargo_lock; reusing existing iroha/kagami binaries" >&2
        return 0
      fi
    fi
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_kagami --bin kagami
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p irohad --bin irohad
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_cli --bin iroha
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
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p irohad --bin irohad
    )
  fi
}

ensure_kagami_bin() {
  local default_bin="$SORASWAP_IROHA_ROOT/target/debug/kagami"
  local bin="${KAGAMI_BIN:-$default_bin}"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_IROHA_CLI_BUILD" "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" || return 1

  if [[ -n "${KAGAMI_BIN:-}" ]]; then
    if [[ ! -x "$bin" ]]; then
      echo "explicit KAGAMI_BIN is missing or not executable: $(soraswap_display_path "$bin")" >&2
      return 1
    fi
    echo "cli tool: reusing explicit kagami binary $(soraswap_display_path "$bin")" >&2
    return 0
  fi

  if [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" && -x "$bin" ]]; then
    echo "cli tool: reusing existing kagami binary" >&2
    return 0
  elif [[ "${SORASWAP_SKIP_IROHA_CLI_BUILD:-0}" == "1" ]]; then
    echo "missing kagami binary at $(soraswap_display_path "$bin") and SORASWAP_SKIP_IROHA_CLI_BUILD=1" >&2
    return 1
  fi
  if [[ ! -x "$bin" ]] || path_is_newer_than "$bin" \
    "$SORASWAP_IROHA_ROOT/Cargo.toml" \
    "$SORASWAP_IROHA_ROOT/Cargo.lock" \
    "$SORASWAP_IROHA_ROOT/crates/iroha_kagami" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_swarm" \
      "$SORASWAP_IROHA_ROOT/crates/iroha_test_samples"; then
    if [[ -x "$bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        echo "cli tool: sibling cargo job holds $(soraswap_display_path "$cargo_lock"); reusing existing kagami binary $(soraswap_display_path "$bin")" >&2
        return 0
      fi
    fi
    (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build -p iroha_kagami --bin kagami
    )
  fi
}

ensure_koto_bin() {
  local default_bin="$SORASWAP_IROHA_ROOT/target/debug/koto"
  local bin="${SORASWAP_KOTO_BIN:-$default_bin}"
  local cargo_lock="$SORASWAP_IROHA_ROOT/target/debug/.cargo-lock"
  local lock_holder=""
  local rebuild=0
  local rebuild_reason=""
  local build_log=""

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_KOTO_TOOL_BUILD" "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" || return 1

  if [[ "${SORASWAP_KOTO_BIN_READY:-0}" == "1" && -x "${SORASWAP_ACTIVE_KOTO_BIN:-}" ]]; then
    return 0
  fi
  if [[ -n "${SORASWAP_KOTO_BIN:-}" && ! -x "$bin" ]]; then
    echo "explicit SORASWAP_KOTO_BIN is missing or not executable: $(soraswap_display_path "$bin")" >&2
    return 1
  fi
  if [[ "${SORASWAP_SKIP_KOTO_TOOL_BUILD:-0}" == "1" ]]; then
    if [[ -x "$bin" ]]; then
      echo "koto tool: reusing existing unified koto binary" >&2
      export SORASWAP_ACTIVE_KOTO_BIN="$bin"
      export SORASWAP_KOTO_BIN_READY=1
      return 0
    fi
    echo "missing unified koto binary at $(soraswap_display_path "$bin") and SORASWAP_SKIP_KOTO_TOOL_BUILD=1" >&2
    return 1
  fi
  if [[ ! -x "$bin" ]]; then
    rebuild=1
    rebuild_reason="koto tool: building unified koto binary"
  elif \
    [[ -z "${SORASWAP_KOTO_BIN:-}" ]] && \
    path_is_newer_than "$bin" \
      "$SORASWAP_ROOT/scripts/common.sh" \
      "$SORASWAP_IROHA_ROOT/Cargo.toml" \
      "$SORASWAP_IROHA_ROOT/Cargo.lock" \
      "$SORASWAP_IROHA_ROOT/crates/ivm" \
      "$SORASWAP_IROHA_ROOT/crates/kotodama_lang"; then
    rebuild=1
    rebuild_reason="koto tool: rebuilding unified koto binary because sibling iroha sources are newer"
  fi

  if (( rebuild )); then
    if [[ -x "$bin" && -f "$cargo_lock" ]]; then
      lock_holder="$(cargo_lock_holder_pid "$cargo_lock")"
      if [[ -n "$lock_holder" ]]; then
        echo "koto tool: sibling cargo job holds $(soraswap_display_path "$cargo_lock"); reusing existing unified koto binary $(soraswap_display_path "$bin")" >&2
        export SORASWAP_ACTIVE_KOTO_BIN="$bin"
        export SORASWAP_KOTO_BIN_READY=1
        return 0
      fi
    fi
    echo "$rebuild_reason" >&2
    build_log="$(mktemp "${TMPDIR:-/tmp}/soraswap-koto-build.XXXXXX")"
    if ! (
      cd "$SORASWAP_IROHA_ROOT"
      NORITO_SKIP_BINDINGS_SYNC=1 CARGO_INCREMENTAL=0 cargo build \
        -p ivm \
        --bin koto >"$build_log" 2>&1
    ); then
      cat "$build_log" >&2
      rm -f "$build_log"
      return 1
    fi
    rm -f "$build_log"
    bin="$default_bin"
  fi
  export SORASWAP_ACTIVE_KOTO_BIN="$bin"
  export SORASWAP_KOTO_BIN_READY=1
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
          tmp_config="$(materialize_cli_compatible_config "${args[$(( idx + 1 ))]}")" || return 1
          args[$(( idx + 1 ))]="$tmp_config"
        fi
        break
        ;;
    esac
    idx=$(( idx + 1 ))
  done

  {
    if "$iroha_bin" "${args[@]}"; then
      idx=0
    else
      idx=$?
    fi
  } always {
    if [[ -n "$tmp_config" ]] && ! soraswap_secure_unlink_owned_file "$tmp_config"; then
      idx=1
    fi
  }
  return "$idx"
}

iroha_cli_json() {
  iroha_cli --machine --output-format json "$@"
}

soraswap_run_external_with_timeout() {
  local timeout_secs="$1"
  shift

  soraswap_require_nonnegative_integer_setting "command timeout seconds" "$timeout_secs" || return 1
  if (( timeout_secs == 0 )); then
    "$@"
  elif (( $+commands[gtimeout] )); then
    gtimeout "$timeout_secs" "$@"
  elif (( $+commands[timeout] )); then
    timeout "$timeout_secs" "$@"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV' "$timeout_secs" "$@"
  fi
}

committed_transaction_lookup_json() {
  local config="$1"
  local tx_hash="$2"
  local timeout_secs="${SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS:-2}"

  iroha_cli_json_with_config_timeout \
    "$config" \
    "$timeout_secs" \
    ledger transaction get \
    --hash "$tx_hash"
}

iroha_cli_json_with_config_timeout() {
  local config="$1"
  local timeout_secs="$2"
  shift 2
  local iroha_bin
  local tmp_config exit_code

  ensure_iroha_cli_bin
  iroha_bin="${SORASWAP_ACTIVE_IROHA_CLI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/iroha}"
  soraswap_require_nonnegative_integer_setting "CLI read timeout seconds" "$timeout_secs" || return 1
  tmp_config="$(materialize_cli_compatible_config "$config")" || return 1
  {
    if soraswap_run_external_with_timeout \
      "$timeout_secs" \
      "$iroha_bin" \
      --machine \
      --output-format json \
      --config "$tmp_config" \
      "$@"; then
      exit_code=0
    else
      exit_code=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_file "$tmp_config"; then
      exit_code=1
    fi
  }
  return "$exit_code"
}

iroha_cli_with_gas_metadata() {
  local config="$1"
  shift
  local metadata_file gas_asset_id gas_limit command_timeout_secs exit_code tmp_config iroha_bin
  local -a ledger_command

  ensure_iroha_cli_bin || return 1
  iroha_bin="${SORASWAP_ACTIVE_IROHA_CLI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/iroha}"
  gas_asset_id="$(gas_metadata_asset_id_for_config "$config")"
  gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
  command_timeout_secs="${SORASWAP_LEDGER_COMMAND_TIMEOUT_SECS:-180}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_LEDGER_COMMAND_TIMEOUT_SECS" "$command_timeout_secs" || return 1
  metadata_file="$(jq -cn \
    --arg gas_asset_id "$gas_asset_id" \
    --argjson gas_limit "$gas_limit" \
    '{gas_asset_id: $gas_asset_id, gas_limit: $gas_limit}' \
    | soraswap_secret_temp_from_stdin ledger-metadata)" || return 1
  tmp_config="$(materialize_cli_compatible_config "$config")" || {
    soraswap_secure_unlink_owned_file "$metadata_file" || true
    return 1
  }
  if (( command_timeout_secs == 0 )); then
    ledger_command=(
      "$iroha_bin"
      --machine
      --config "$tmp_config"
      --metadata "$metadata_file"
      "$@"
    )
  elif (( $+commands[gtimeout] )); then
    ledger_command=(
      gtimeout "$command_timeout_secs"
      "$iroha_bin"
      --machine
      --config "$tmp_config"
      --metadata "$metadata_file"
      "$@"
    )
  elif (( $+commands[timeout] )); then
    ledger_command=(
      timeout "$command_timeout_secs"
      "$iroha_bin"
      --machine
      --config "$tmp_config"
      --metadata "$metadata_file"
      "$@"
    )
  else
    ledger_command=(
      perl -e 'alarm shift @ARGV; exec @ARGV' "$command_timeout_secs"
      "$iroha_bin"
      --machine
      --config "$tmp_config"
      --metadata "$metadata_file"
      "$@"
    )
  fi

  {
    if soraswap_invoke_immediate_submit_gate \
      "${SORASWAP_IMMEDIATE_LEDGER_SUBMIT_GATE_FUNCTION:-}" \
      "$config" \
      "${SORASWAP_IMMEDIATE_LEDGER_SUBMIT_GATE_LABEL:-Iroha CLI submission}"; then
      if "${ledger_command[@]}"; then
        exit_code=0
      else
        exit_code=$?
        if (( command_timeout_secs > 0 )); then
          case "$exit_code" in
            124|137|142|143)
              echo "ledger command timed out after ${command_timeout_secs}s" >&2
              ;;
          esac
        fi
      fi
    else
      exit_code=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_files "$metadata_file" "$tmp_config"; then
      exit_code=1
    fi
  }
  return "$exit_code"
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
    echo "missing required file: $(soraswap_display_path "$file_path")" >&2
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

public_env_for_config_path() {
  local config="$1"
  local config_abs

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

require_public_client_config_matches_env() {
  local public_env="$1"
  local config="$2"
  local config_env config_abs blocker_message public_label

  config_abs="${config:A}"
  config_env="$(public_env_for_config_path "$config" 2>/dev/null || true)"
  if [[ -z "$config_env" || "$config_env" == "$public_env" ]]; then
    if [[ "$public_env" == "production" ]]; then
      soraswap_require_secure_production_client_config "$config" || return 1
    fi
    case "$public_env" in
      testnet)
        blocker_message="$(testnet_client_config_unexpected_chain_blocker_message "$config" 2>/dev/null || true)"
        ;;
      production)
        blocker_message="$(production_client_config_taira_chain_blocker_message "$config" 2>/dev/null || true)"
        ;;
      *)
        blocker_message=""
        ;;
    esac
    if [[ -n "$blocker_message" ]]; then
      echo "$blocker_message" >&2
      return 1
    fi
    if [[ -f "$config" ]] && soraswap_client_config_has_placeholder_values "$config"; then
      case "$public_env" in
        testnet) public_label="Taira" ;;
        production) public_label="production" ;;
        *) public_label="$public_env" ;;
      esac
      echo "$public_label client config still contains example credentials or local endpoints: $(soraswap_display_path "$config_abs")" >&2
      return 1
    fi
    return 0
  fi

  echo "refusing to use a $config_env client config for $public_env public action: $(soraswap_display_path "$config_abs")" >&2
  return 1
}

testnet_client_config_unexpected_chain_blocker_message() {
  local config="$1"
  local config_chain

  [[ -z "${SORASWAP_TESTNET_CHAIN_ID:-}" ]] || return 1
  if [[ -f "$config" ]]; then
    config_chain="$(config_chain_literal_from_config "$config" 2>/dev/null || true)"
  else
    return 1
  fi
  [[ -n "$config_chain" ]] || return 1
  [[ "$config_chain" != "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT" ]] || return 1

  echo "Taira client config chain $config_chain does not match the expected Taira chain; set SORASWAP_TESTNET_CHAIN_ID if this public Taira reset is intentional"
}

production_client_config_taira_chain_blocker_message() {
  local config="$1"
  local config_chain chain_env

  if [[ "${SORASWAP_PRODUCTION_CHAIN_ID:-}" == "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT" ]]; then
    echo "SORASWAP_PRODUCTION_CHAIN_ID must not select the canonical Taira chain"
    return 0
  fi
  [[ -z "${SORASWAP_PRODUCTION_CHAIN_ID:-}" ]] || return 1
  chain_env="${CHAIN:-}"
  if [[ "$chain_env" == "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT" ]]; then
    echo "production client config uses the canonical Taira chain id; set a real production chain or SORASWAP_PRODUCTION_CHAIN_ID"
    return 0
  fi

  if [[ -f "$config" ]]; then
    config_chain="$(config_chain_literal_from_config "$config" 2>/dev/null || true)"
  else
    return 1
  fi
  [[ "$config_chain" == "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT" ]] || return 1

  echo "production client config uses the canonical Taira chain id; set a real production chain or SORASWAP_PRODUCTION_CHAIN_ID"
}

config_toml_string_value() {
  local config="$1"
  local key="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      line = $0
      sub(/\r$/, "", line)
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
      quote = substr(line, 1, 1)
      if (quote != "\"" && quote != sprintf("%c", 39)) {
        exit
      }
      value = substr(line, 2)
      for (idx = 1; idx <= length(value); idx++) {
        if (substr(value, idx, 1) == quote) {
          print substr(value, 1, idx - 1)
          exit
        }
      }
      exit
    }
  ' "$config"
}

config_toml_string_value_in_section() {
  local config="$1"
  local section="$2"
  local key="$3"
  awk -v section="$section" -v key="$key" '
    /^[[:space:]]*\[/ {
      in_section = ($0 ~ "^[[:space:]]*\\[[[:space:]]*" section "[[:space:]]*\\][[:space:]]*($|#)")
      next
    }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      line = $0
      sub(/\r$/, "", line)
      sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
      quote = substr(line, 1, 1)
      if (quote != "\"" && quote != sprintf("%c", 39)) {
        exit
      }
      value = substr(line, 2)
      for (idx = 1; idx <= length(value); idx++) {
        if (substr(value, idx, 1) == quote) {
          print substr(value, 1, idx - 1)
          exit
        }
      }
      exit
    }
  ' "$config"
}

account_toml_string_value() {
  local config="$1"
  local key="$2"
  local value

  value="$(config_toml_string_value_in_section "$config" account "$key")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  config_toml_string_value "$config" "$key"
}

account_domain_from_config() {
  local config="$1"
  local metadata

  if public_env_for_config "$config" >/dev/null 2>&1; then
    metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
    jq -r '.account_domain // empty' <<<"$metadata"
    return 0
  fi
  account_toml_string_value "$config" domain
}

config_chain_literal_from_config() {
  local config="$1"
  local metadata

  if public_env_for_config "$config" >/dev/null 2>&1; then
    metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
    jq -r '.chain // empty' <<<"$metadata"
    return 0
  fi
  config_toml_string_value "$config" chain
}

client_config_or_default() {
  local mode="$1"
  if [[ -n "${SORASWAP_CLIENT_CONFIG:-}" ]]; then
    case "$mode" in
      testnet|production)
        require_public_client_config_matches_env "$mode" "$SORASWAP_CLIENT_CONFIG" || return 1
        ;;
    esac
    echo "$SORASWAP_CLIENT_CONFIG"
    return
  fi
  case "$mode" in
    local)
      echo "$DEFAULT_LOCAL_CLIENT"
      ;;
    testnet)
      require_public_client_config_matches_env testnet "$DEFAULT_TESTNET_CLIENT" || return 1
      echo "$DEFAULT_TESTNET_CLIENT"
      ;;
    production)
      if [[ -n "${SORASWAP_PRODUCTION_CLIENT_CONFIG:-}" ]]; then
        require_public_client_config_matches_env production "$SORASWAP_PRODUCTION_CLIENT_CONFIG" || return 1
        echo "$SORASWAP_PRODUCTION_CLIENT_CONFIG"
        return 0
      fi
      if [[ -f "$DEFAULT_PRODUCTION_CLIENT" ]]; then
        require_public_client_config_matches_env production "$DEFAULT_PRODUCTION_CLIENT" || return 1
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
  local config_metadata config_origin override_origin public_env
  if [[ -n "${SORASWAP_TORII_URL:-}" ]]; then
    public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
    if [[ "$public_env" == "production" ]] \
      && ! soraswap_validate_production_torii_root_url "$SORASWAP_TORII_URL"; then
      echo "production SORASWAP_TORII_URL must be an absolute HTTPS Torii root without userinfo, query, or fragment" >&2
      return 1
    fi
    if [[ -n "$public_env" ]]; then
      config_metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
      config_origin="$(jq -r '.torii_origin' <<<"$config_metadata")"
      override_origin="$(soraswap_url_origin "$SORASWAP_TORII_URL")" || return 1
      if [[ "$override_origin" != "$config_origin" ]]; then
        echo "authenticated Torii override must use the configured client origin" >&2
        return 1
      fi
    fi
    echo "$SORASWAP_TORII_URL"
    return
  fi
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -n "$public_env" ]]; then
    config_metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
    jq -r '.torii_url // empty' <<<"$config_metadata"
    return 0
  fi
  config_toml_string_value "$config" torii_url
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

  case "${SORASWAP_PUBLIC_ENV:-}" in
    testnet|production)
      printf '%s\n' "$SORASWAP_PUBLIC_ENV"
      return 0
      ;;
  esac

  public_env_for_config_path "$config"
}

public_mutation_gate_var_for_env() {
  local public_env="$1"
  case "$public_env" in
    testnet)
      printf '%s\n' "SORASWAP_ALLOW_TESTNET_MUTATIONS"
      ;;
    production)
      printf '%s\n' "SORASWAP_ALLOW_PRODUCTION_MUTATIONS"
      ;;
    *)
      echo "unsupported public environment for mutation gate: $public_env" >&2
      return 1
      ;;
  esac
}

public_mutations_allowed_for_env() {
  local public_env="$1"
  local gate_var gate_value
  gate_var="$(public_mutation_gate_var_for_env "$public_env")" || return 1
  gate_value="${(P)gate_var:-0}"
  [[ "$gate_value" == "1" ]]
}

require_public_mutation_consent() {
  local public_env="$1"
  local action_label="${2:-$public_env public mutation}"
  local gate_var gate_value

  gate_var="$(public_mutation_gate_var_for_env "$public_env")" || return 1
  gate_value="${(P)gate_var:-0}"
  if [[ "$gate_value" != "1" ]]; then
    echo "$action_label is mutation-gated; export $gate_var=1 to continue" >&2
    return 1
  fi
}

chain_id_override_for_config() {
  local config="$1"
  local public_env config_chain

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      if [[ -n "${SORASWAP_TESTNET_CHAIN_ID:-}" ]]; then
        printf '%s\n' "$SORASWAP_TESTNET_CHAIN_ID"
        return 0
      fi
      config_chain="$(config_chain_literal_from_config "$config")"
      printf '%s\n' "${config_chain:-$SORASWAP_TESTNET_CHAIN_ID_DEFAULT}"
      ;;
    production)
      if [[ -n "${SORASWAP_PRODUCTION_CHAIN_ID:-}" ]]; then
        printf '%s\n' "$SORASWAP_PRODUCTION_CHAIN_ID"
        return 0
      fi
      printf '\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

materialize_cli_compatible_config() {
  local source_config="$1"
  local public_key_override="${2:-}"
  local private_key_override="${3:-}"
  local public_env
  local -a production_args

  public_env="$(public_env_for_config "$source_config" 2>/dev/null || true)"
  production_args=()
  [[ "$public_env" != "production" ]] || production_args=(--production)

  if [[ -n "$public_key_override" || -n "$private_key_override" ]]; then
    printf '%s\0%s\0' "$public_key_override" "$private_key_override" \
      | python3 -c '
import json
import sys

parts = sys.stdin.buffer.read().split(b"\0")
if len(parts) != 3 or parts[-1] != b"":
    raise SystemExit("invalid signer override framing")
public_key = parts[0].decode("utf-8")
private_key = parts[1].decode("utf-8")
payload = {}
if public_key:
    payload["public_key"] = public_key
if private_key:
    payload["private_key"] = private_key
json.dump(payload, sys.stdout, separators=(",", ":"))
' \
      | SORASWAP_PUBLIC_ENV="$public_env" \
          soraswap_secure_client_config_tool "$SORASWAP_ROOT" materialize \
            --config "$source_config" \
            "${production_args[@]}" \
            --family cli-config
    return $?
  fi

  printf '{}\n' \
    | SORASWAP_PUBLIC_ENV="$public_env" \
        soraswap_secure_client_config_tool "$SORASWAP_ROOT" materialize \
          --config "$source_config" \
          "${production_args[@]}" \
          --family cli-config
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
    strict_chain_fingerprint_json_or_null "$SORASWAP_CHAIN_FINGERPRINT_JSON"
    return $?
  fi

  latest="$(chain_snapshot_latest_path_for_env "$env")"
  if [[ -f "$latest" ]] \
    && jq -e --arg env "$env" '
      ((.generated_at // "") | type == "string" and length > 0)
      and (.environment // "") == $env
      and ((.torii_url // "") | type == "string" and length > 0)
      and ((.chain // "") | type == "string" and length > 0)
      and ((.block_1_hash // "") | type == "string" and length > 0)
    ' "$latest" >/dev/null 2>&1; then
    jq -c '{torii_url, chain, block_1_hash}' "$latest"
    return 0
  fi

  echo 'null'
}

deployment_records_snapshot_json_for_env() {
  local env="$1"
  local generated_at="${2:-$(utc_timestamp)}"
  local chain_fingerprint_json contracts_json expected_contract_keys_json deploy_scope

  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  require_deployment_evidence_chain_fingerprint "$env" "$chain_fingerprint_json" "deployment records snapshot" || return 1
  deploy_scope="${SORASWAP_DEPLOY_SCOPE:-full}"
  contracts_json="$(deployment_records_json_for_env "$env")"
  expected_contract_keys_json="$(expected_contract_ids_for_deploy_scope "$deploy_scope" | json_array_from_lines)" || return 1
  if ! jq -e --argjson expected_contract_keys "$expected_contract_keys_json" '
    def snapshot_keys:
      [.[]? | select(type == "object") | (.contract_key? // .name? // empty) | select(. != "")];
    ($expected_contract_keys | unique | sort) as $expected
    | snapshot_keys as $actual
    | type == "array"
      and (($expected | length) > 0)
      and (($actual | length) == ($expected | length))
      and (($actual | unique | sort) == $expected)
  ' <<<"$contracts_json" >/dev/null 2>&1; then
    echo "deployment records snapshot for $env does not exactly cover $deploy_scope deploy contract set" >&2
    return 1
  fi
  if [[ "$chain_fingerprint_json" != "null" ]] \
    && ! jq -e --argjson chain "$chain_fingerprint_json" '
      def matches_chain($fingerprint):
        (($fingerprint.torii_url // "") | type == "string" and length > 0)
        and (($fingerprint.torii_url // null) == ($chain.torii_url // null))
        and (($fingerprint.chain // null) == ($chain.chain // null))
        and (($fingerprint.block_1_hash // null) == ($chain.block_1_hash // null));
      all(.[]?; (type == "object") and matches_chain(.chain_fingerprint // {}))
    ' <<<"$contracts_json" >/dev/null 2>&1; then
    echo "deployment records snapshot for $env contains records without the current chain fingerprint" >&2
    return 1
  fi

  jq -cn \
    --arg generated_at "$generated_at" \
    --arg environment "$env" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    --argjson contracts "$contracts_json" \
    '{
      generated_at: $generated_at,
      environment: $environment,
      status: "completed",
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

  soraswap_write_json_file_atomic "$snapshot_json" "$latest" || return 1
  printf '%s\n' "$snapshot_json"
}

public_reusable_contracts_snapshot_check_json() {
  local env="$1"
  local chain_fingerprint_json="$2"
  local contracts_snapshot_path="${3:-$(contracts_snapshot_latest_path_for_env "$env")}"
  local expected_contract_keys_json contracts_generated_at current_snapshot_json output
  local -a issues

  expected_contract_keys_json="$(expected_contract_ids_for_deploy_scope "${SORASWAP_DEPLOY_SCOPE:-full}" | json_array_from_lines)" || expected_contract_keys_json='[]'

  if ! jq -e '
    type == "object"
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' <<<"$chain_fingerprint_json" >/dev/null 2>&1; then
    issues+=("current chain fingerprint is unavailable")
  fi

  if [[ ! -s "$contracts_snapshot_path" ]]; then
    issues+=("missing contracts snapshot at $(soraswap_display_path "$contracts_snapshot_path")")
  elif ! jq -e \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    --argjson expected_contract_keys "$expected_contract_keys_json" \
    '
      def nonempty_string($v): (($v // "") | type == "string" and length > 0);
      def normalized_hash($v): (($v // "") | ascii_downcase | sub("^0x"; ""));
      def bundle_deploy_proof($item):
        (($item.deploy_strategy // "") == "bundle")
        and (($item.bundle_receipt.status // "") == "deployed")
        and (($item.bundle_receipt.name // $item.bundle_receipt.contract_key // "") == ($item.contract_key // ""))
        and (($item.bundle_receipt.contract_address // "") == ($item.contract_address // $item.response.contract_address // $item.instance.contract_address // $item.instance.contract_id // ""))
        and (($item.bundle_receipt.deploy_nonce // null) | type == "number")
        and ((($item.bundle_receipt.deploy_nonce // null) | tostring) == (($item.deploy_nonce // $item.response.deploy_nonce // $item.instance.deploy_nonce // null) | tostring))
        and (normalized_hash($item.bundle_receipt.code_hash_hex) == normalized_hash($item.code_hash_hex // $item.response.code_hash_hex // $item.instance.code_hash_hex))
        and (normalized_hash($item.bundle_receipt.abi_hash_hex) == normalized_hash($item.abi_hash_hex // $item.response.abi_hash_hex // $item.instance.abi_hash_hex));
      def deploy_write_proof($item):
        nonempty_string($item.response.tx_hash_hex)
        or bundle_deploy_proof($item);
      .status == "completed"
      and nonempty_string(.generated_at)
      and (.environment // "") == $env
      and (($expected_contract_keys | type) == "array")
      and (($expected_contract_keys | length) > 0)
      and ((.contracts // []) | type == "array")
      and ([.contracts[]? | select(type == "object") | (.contract_key? // .name? // empty) | select(. != "")] as $snapshot_keys
        | (($snapshot_keys | length) == ($expected_contract_keys | unique | length))
        and (($snapshot_keys | unique | sort) == ($expected_contract_keys | unique | sort)))
      and all((.contracts // [])[]?;
        (type == "object")
        and ((.environment // "") == $env)
        and nonempty_string(.contract_key)
        and nonempty_string(.contract_source)
        and nonempty_string(.contract_alias)
        and nonempty_string(.contract_address)
        and ((.deploy_nonce // null) | type == "number")
        and ((.response.ok // false) == true)
        and deploy_write_proof(.)
        and nonempty_string(.response.code_hash_hex)
        and nonempty_string(.response.abi_hash_hex)
        and nonempty_string(.instance.contract_id)
        and nonempty_string(.instance.code_hash_hex)
        and nonempty_string(.instance.abi_hash_hex)
        and ((.instance.verification // "") == "transaction_and_manifest")
        and ((.chain_fingerprint.torii_url // null) == ($chain.torii_url // null))
        and ((.chain_fingerprint.chain // null) == ($chain.chain // null))
        and ((.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)))
      and ((.chain_fingerprint.torii_url // null) == ($chain.torii_url // null))
      and ((.chain_fingerprint.chain // null) == ($chain.chain // null))
      and ((.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null))
    ' "$contracts_snapshot_path" >/dev/null 2>&1; then
    issues+=("contracts snapshot is not reusable: missing completed status, selected environment, exact current contract set, deploy receipts, manifests, or current chain fingerprint")
  fi

  if (( ${#issues[@]} == 0 )); then
    contracts_generated_at="$(jq -r '.generated_at // empty' "$contracts_snapshot_path" 2>/dev/null || true)"
    if [[ -z "$contracts_generated_at" ]]; then
      issues+=("contracts snapshot is missing generated_at")
    elif ! current_snapshot_json="$(deployment_records_snapshot_json_for_env "$env" "$contracts_generated_at" 2>/dev/null)"; then
      issues+=("current deployment records cannot produce a complete contracts snapshot")
    elif ! jq -n -e \
      --slurpfile contracts "$contracts_snapshot_path" \
      --argjson current "$current_snapshot_json" \
      '($contracts[0] | del(.generated_at)) == ($current | del(.generated_at))' \
      >/dev/null 2>&1; then
      issues+=("contracts snapshot does not match current deployment records")
    fi
  fi

  if (( ${#issues[@]} == 0 )); then
    jq -cn \
      --arg status completed \
      --arg output "current contracts snapshot can be reused for $env" \
      --arg generated_at "$contracts_generated_at" \
      --arg path "$(soraswap_display_path "$contracts_snapshot_path")" \
      --argjson contract_count "$(jq -r '(.contracts // []) | length' "$contracts_snapshot_path")" \
      '{
        status: $status,
        output: $output,
        contracts_snapshot: {
          path: $path,
          generated_at: $generated_at,
          contract_count: $contract_count
        }
      }'
    return
  fi

  output="$(printf '%s\n' "${issues[@]}")"
  output="$(soraswap_redact_sensitive_text "$output")"
  jq -cn --arg status degraded --arg output "$output" '{status: $status, output: $output}'
}

public_current_deploy_snapshot_check_json() {
  local env="$1"
  local chain_fingerprint_json="$2"
  local contracts_snapshot_path="${3:-$(contracts_snapshot_latest_path_for_env "$env")}"
  local deploy_snapshot_path="${4:-$(deploy_report_latest_path_for_env "$env")}"
  local preflight_snapshot_path="${5:-$(deployments_dir_for_env "$env")/preflight.latest.json}"
  local nested_probe_snapshot_path="${6:-${preflight_snapshot_path:h}/nested_call_probe.latest.json}"
  local output expected_contract_keys_json
  local ready_preflight_generated_at deploy_generated_at contracts_generated_at
  local -a issues

  expected_contract_keys_json="$(expected_contract_ids 2>/dev/null | json_array_from_lines)" || expected_contract_keys_json='[]'

  if ! jq -e '
    type == "object"
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' <<<"$chain_fingerprint_json" >/dev/null 2>&1; then
    issues+=("current chain fingerprint is unavailable")
  fi

  if [[ ! -s "$contracts_snapshot_path" ]]; then
    issues+=("missing contracts snapshot at $(soraswap_display_path "$contracts_snapshot_path")")
  elif ! jq -e \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    --argjson expected_contract_keys "$expected_contract_keys_json" \
    '
      .status == "completed"
      and ((.generated_at // "") | type == "string" and length > 0)
      and (.environment // "") == $env
      and (($expected_contract_keys | type) == "array")
      and (($expected_contract_keys | length) > 0)
      and ((.contracts // []) | type == "array")
      and ([.contracts[]? | select(type == "object") | (.contract_key? // .name? // empty) | select(. != "")] as $snapshot_keys
        | (($snapshot_keys | length) == ($expected_contract_keys | unique | length))
        and (($snapshot_keys | unique | sort) == ($expected_contract_keys | unique | sort)))
      and all((.contracts // [])[]?; (type == "object") and ((.environment // "") == $env))
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
      and (.chain_fingerprint.chain // null) == ($chain.chain // null)
      and (.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
    ' "$contracts_snapshot_path" >/dev/null 2>&1; then
    issues+=("contracts snapshot is missing completed status, selected environment, current contract set, or current chain fingerprint")
  fi

  if [[ ! -s "$deploy_snapshot_path" ]]; then
    issues+=("missing deploy report at $(soraswap_display_path "$deploy_snapshot_path")")
  elif ! jq -e \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    '
      .status == "completed"
      and ((.generated_at // "") | type == "string" and length > 0)
      and (.environment // "") == $env
      and (.phases.preflight.status // "") == "completed"
      and (.phases.compile.status // "") == "completed"
      and (.phases.nested_call_probe.status // "") == "completed"
      and (.phases.deploy.status // "") == "completed"
      and (.phases.bootstrap_contract_state.status // "") == "completed"
      and (.phases.deployment_records_snapshot.status // "") == "completed"
      and ((.phases.preflight.detail.signer_ready_check.status // "") == "completed")
      and ((.phases.preflight.detail.signer_ready_check.debug_bypass_env // null) == null)
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
      and (.chain_fingerprint.chain // null) == ($chain.chain // null)
      and (.chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
    ' "$deploy_snapshot_path" >/dev/null 2>&1; then
    issues+=("deploy report is missing completed status, selected environment, current chain fingerprint, completed required deploy phases, or signer readiness proof")
  fi

  if [[ -s "$contracts_snapshot_path" && -s "$deploy_snapshot_path" ]] \
    && ! jq -n -e \
      --slurpfile contracts "$contracts_snapshot_path" \
      --slurpfile deploy "$deploy_snapshot_path" \
      '
        def current_contract_snapshot_path($snapshot; $contracts_generated):
          ($snapshot | type) == "string"
          and ("contracts." + $contracts_generated + ".json") as $contracts_file
          | ($snapshot == $contracts_file or ($snapshot | endswith("/" + $contracts_file)));

        ($contracts[0].generated_at // "") as $contracts_generated
        | (($contracts_generated | type) == "string" and ($contracts_generated | length) > 0)
          and (($deploy[0].generated_at // "") | type == "string" and length > 0)
          and ($contracts_generated >= ($deploy[0].generated_at // ""))
          and current_contract_snapshot_path(($deploy[0].phases.deployment_records_snapshot.detail.snapshot // ""); $contracts_generated)
      ' >/dev/null 2>&1; then
    issues+=("deploy report does not reference the current contracts snapshot")
  fi

  ready_preflight_generated_at=""
  if [[ ! -s "$preflight_snapshot_path" ]]; then
    issues+=("missing release-ready preflight at $(soraswap_display_path "$preflight_snapshot_path")")
  elif ! jq -e \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    '
      .status == "ready"
      and ((.generated_at // "") | type == "string" and length > 0)
      and (.target_environment // "") == $env
      and ((.blockers // []) | length) == 0
      and ((.warnings // []) | length) == 0
      and (.environment.mutations_allowed // false) == true
      and (.environment.oracle_public_key_present // false) == true
      and (.environment.oracle_private_key_present // false) == true
      and (.environment.oracle_keypair_verified // false) == true
      and ((.environment.oracle_public_key_source // "") | type == "string" and length > 0)
      and ((.environment.oracle_private_key_source // "") | type == "string" and length > 0)
      and ((.endpoint.mcp_http_status // "") | tostring) == "200"
      and (.endpoint.health_issues | type == "array" and length == 0)
      and ((.endpoint.health.status.http_status // "") | tostring) == "200"
      and (.endpoint.health.status.json_available == true)
      and ((.endpoint.health.sumeragi.http_status // "") | tostring) == "200"
      and (.endpoint.health.sumeragi.json_available == true)
      and (.chain.fingerprint_available // false) == true
      and (.chain.saved_snapshot_exists // false) == true
      and (.chain.saved_snapshot_matches // false) == true
      and (.chain.saved_snapshot_environment // "") == $env
      and ((.chain.fingerprint.torii_url // "") | type == "string" and length > 0)
      and (.chain.fingerprint.torii_url // null) == ($chain.torii_url // null)
      and (.chain.fingerprint.chain // null) == ($chain.chain // null)
      and (.chain.fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
      and (.nested_call_probe.latest_exists // false) == true
      and (.nested_call_probe.matches_current_chain // false) == true
      and (.nested_call_probe.supported // false) == true
      and (.signer.authority_derivable // false) == true
      and (.signer.account_exists // false) == true
      and (.signer.assets_query_available // false) == true
      and ((try ((.signer.fee_balance // "0") | tonumber) catch -1) > 0)
    ' "$preflight_snapshot_path" >/dev/null 2>&1; then
    issues+=("preflight report is not release-ready for current chain")
  elif [[ ! -s "$nested_probe_snapshot_path" ]]; then
    issues+=("missing current supported nested-call probe at $(soraswap_display_path "$nested_probe_snapshot_path")")
  elif ! jq -n -e \
    --arg env "$env" \
    --argjson chain "$chain_fingerprint_json" \
    --slurpfile preflight "$preflight_snapshot_path" \
    --slurpfile probe "$nested_probe_snapshot_path" \
    '
      (($probe[0].generated_at // "") | type == "string" and length > 0)
      and (($preflight[0].generated_at // "") | type == "string" and length > 0)
      and ($preflight[0].generated_at >= ($probe[0].generated_at // ""))
      and (($probe[0].environment // "") == $env)
      and ($probe[0].supported // false) == true
      and (($probe[0].chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and ($probe[0].chain_fingerprint.torii_url // null) == ($chain.torii_url // null)
      and ($probe[0].chain_fingerprint.chain // null) == ($chain.chain // null)
      and ($probe[0].chain_fingerprint.block_1_hash // null) == ($chain.block_1_hash // null)
    ' >/dev/null 2>&1; then
    issues+=("nested-call probe is missing current supported evidence or is newer than preflight")
  else
    ready_preflight_generated_at="$(jq -r '.generated_at' "$preflight_snapshot_path")"
  fi

  if [[ -n "$ready_preflight_generated_at" && -s "$deploy_snapshot_path" ]]; then
    deploy_generated_at="$(jq -r '.generated_at // empty' "$deploy_snapshot_path" 2>/dev/null || true)"
    if [[ -n "$deploy_generated_at" && "$deploy_generated_at" < "$ready_preflight_generated_at" ]]; then
      issues+=("deploy report is older than current ready preflight")
    fi
  fi

  if [[ -s "$contracts_snapshot_path" ]]; then
    contracts_generated_at="$(jq -r '.generated_at // empty' "$contracts_snapshot_path" 2>/dev/null || true)"
    if [[ -n "$contracts_generated_at" ]]; then
      if [[ -n "$ready_preflight_generated_at" && "$contracts_generated_at" < "$ready_preflight_generated_at" ]]; then
        issues+=("contracts snapshot is older than current ready preflight")
      elif [[ -s "$deploy_snapshot_path" ]]; then
        deploy_generated_at="$(jq -r '.generated_at // empty' "$deploy_snapshot_path" 2>/dev/null || true)"
        if [[ -n "$deploy_generated_at" && "$contracts_generated_at" < "$deploy_generated_at" ]]; then
          issues+=("contracts snapshot is older than current deploy report")
        fi
      fi
    fi
  fi

  if (( ${#issues[@]} == 0 )); then
    jq -cn --arg status completed --arg output "deploy snapshots are current for $env" \
      '{status: $status, output: $output}'
    return
  fi

  output="$(printf '%s\n' "${issues[@]}")"
  output="$(soraswap_redact_sensitive_text "$output")"
  jq -cn --arg status degraded --arg output "$output" '{status: $status, output: $output}'
}

current_chain_fingerprint_json() {
  local config="$1"
  local torii_base torii_base_report chain_id block_hash response
  local attempt=1
  local attempts="${SORASWAP_CHAIN_FINGERPRINT_ATTEMPTS:-15}"
  local sleep_seconds="${SORASWAP_CHAIN_FINGERPRINT_SLEEP_SECS:-1}"

  soraswap_validate_torii_read_max_time || return 1
  soraswap_validate_poll_window "chain fingerprint" "$attempts" "$sleep_seconds" || return 1

  torii_base="$(torii_base_from_config "$config")"
  torii_base_report="$(soraswap_redact_sensitive_text "$torii_base")"
  chain_id="$(config_chain_id_from_config "$config")"
  while (( attempt <= attempts )); do
    if response="$(soraswap_curl_for_config "$config" -fsS \
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
    echo "failed to fetch chain fingerprint from $torii_base_report/v1/explorer/blocks/1 after ${attempts} attempts" >&2
    return 1
  fi

  jq -cn \
    --arg torii_url "$torii_base_report" \
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
  local expected_env="${3:-}"
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
    --arg expected_env "$expected_env" \
    '((.generated_at // "") | type == "string" and length > 0)
      and ((.torii_url // "") | type == "string" and length > 0)
      and ((.chain // "") | type == "string" and length > 0)
      and ((.block_1_hash // "") | type == "string" and length > 0)
      and .torii_url == $current.torii_url
      and .chain == $current.chain
      and .block_1_hash == $current.block_1_hash
      and ($expected_env == "" or (.environment // "") == $expected_env)' \
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
    --arg environment "$env" \
    --argjson fingerprint "$fingerprint_json" \
    '$fingerprint + {generated_at: $generated_at, environment: $environment}')"
  soraswap_write_json_report_pair "$snapshot_json" "$latest" "$timestamped"
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
  if chain_snapshot_matches_json "$latest" "$SORASWAP_CHAIN_FINGERPRINT_JSON" "$env"; then
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
  echo "archived stale deployment evidence to $(soraswap_display_path "$archive_dir")" >&2
}

prepare_env_chain_state() {
  local env="$1"
  local config="$2"
  local fingerprint_json

  if [[ -n "${SORASWAP_CHAIN_FINGERPRINT_JSON:-}" ]]; then
    if ! fingerprint_json="$(strict_chain_fingerprint_json_or_null "$SORASWAP_CHAIN_FINGERPRINT_JSON")" \
      || [[ "$fingerprint_json" == "null" ]]; then
      echo "invalid SORASWAP_CHAIN_FINGERPRINT_JSON for ${env}; expected torii_url, chain, and block_1_hash" >&2
      return 1
    fi
  else
    if ! fingerprint_json="$(current_chain_fingerprint_json "$config")"; then
      echo "unable to derive chain fingerprint for ${env} from $(torii_base_from_config "$config")" >&2
      return 1
    fi
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
  local chain_override public_env

  chain_override="$(chain_id_override_for_config "$config")"
  if [[ -n "$chain_override" ]]; then
    printf '%s\n' "$chain_override"
    return 0
  fi
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet|production)
      config_chain_literal_from_config "$config"
      return 0
      ;;
  esac
  if [[ -n "${CHAIN:-}" ]]; then
    printf '%s\n' "$CHAIN"
    return 0
  fi
  config_chain_literal_from_config "$config"
}

account_private_key_from_config() {
  local config="$1"
  if public_env_for_config "$config" >/dev/null 2>&1; then
    echo "public private keys must be consumed through a secure file-backed interface" >&2
    return 1
  fi
  account_toml_string_value "$config" private_key
}

account_chain_discriminant_from_config() {
  local config="$1"
  local metadata

  metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
  jq -er '
    if .chain_discriminant == null then
      ""
    elif ((.chain_discriminant | type) == "number"
      and (.chain_discriminant | floor) == .chain_discriminant
      and .chain_discriminant >= 0
      and .chain_discriminant <= 65535) then
      (.chain_discriminant | tostring)
    else
      error("account.chain_discriminant must be a TOML u16 integer")
    end
  ' <<<"$metadata"
}

account_profile_from_config() {
  local config="$1"
  awk -F '"' '
    /^\[account\]/ { in_account = 1; next }
    /^\[/ { in_account = 0 }
    in_account && /^[[:space:]]*profile[[:space:]]*=/ {
      print $2
      exit
    }
  ' "$config"
}

chain_discriminant_for_profile() {
  case "$1" in
    taira)
      echo "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT"
      ;;
    sora|local|default)
      echo "${SORASWAP_CHAIN_DISCRIMINANT:-753}"
      ;;
    *)
      return 1
      ;;
  esac
}

chain_discriminant_for_env_config() {
  local env="${1:-testnet}"
  local config="${2:-}"
  local config_discriminant profile profile_discriminant

  case "$env" in
    testnet)
      if [[ -n "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT" ]]; then
        echo "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT"
        return 0
      fi
      if [[ -n "$config" && -f "$config" ]]; then
        config_discriminant="$(account_chain_discriminant_from_config "$config")" || return 1
        if [[ -n "$config_discriminant" ]]; then
          echo "$config_discriminant"
          return 0
        fi
        profile="$(account_profile_from_config "$config")"
        if [[ -n "$profile" ]] && profile_discriminant="$(chain_discriminant_for_profile "$profile" 2>/dev/null)"; then
          echo "$profile_discriminant"
          return 0
        fi
      fi
      echo "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT"
      ;;
    production)
      if [[ -n "${SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT:-}" ]]; then
        soraswap_canonical_u16_decimal "SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT" "$SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT"
        return 0
      fi
      if [[ -n "$config" && -f "$config" ]]; then
        config_discriminant="$(account_chain_discriminant_from_config "$config")" || return 1
        if [[ -n "$config_discriminant" ]]; then
          echo "$config_discriminant"
          return 0
        fi
      fi
      echo "production chain discriminant is required in [account].chain_discriminant or SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT" >&2
      return 1
      ;;
    *)
      echo "${SORASWAP_CHAIN_DISCRIMINANT:-753}"
      ;;
  esac
}

chain_discriminant_for_env() {
  local env="${1:-testnet}"
  case "$env" in
    testnet)
      echo "${SORASWAP_TESTNET_CHAIN_DISCRIMINANT:-$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT}"
      ;;
    production)
      if [[ -n "${SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT:-}" ]]; then
        soraswap_canonical_u16_decimal "SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT" "$SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT"
      else
        echo "production chain discriminant is required in SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT" >&2
        return 1
      fi
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

deploy_report_failed_latest_path_for_env() {
  local env="$1"
  echo "$(deployments_dir_for_env "$env")/deploy.failed.latest.json"
}

deploy_report_failed_timestamped_path_for_env() {
  local env="$1"
  local timestamp="$2"
  echo "$(deployments_dir_for_env "$env")/deploy.failed.${timestamp}.json"
}

deploy_report_restore_previous_completed_latest() {
  local env="$1"
  local previous_json="${2:-null}"
  local latest previous_generated_at previous_timestamped

  if ! jq -e --arg env "$env" '
    type == "object"
    and (.status // "") == "completed"
    and (.environment // "") == $env
    and ((.generated_at // "") | type == "string" and length > 0)
  ' >/dev/null 2>&1 <<<"$previous_json"; then
    return 1
  fi

  latest="$(deploy_report_latest_path_for_env "$env")"
  previous_generated_at="$(jq -r '.generated_at' <<<"$previous_json")"
  previous_timestamped="$(deployments_dir_for_env "$env")/deploy.${previous_generated_at}.json"
  soraswap_write_json_file_atomic "$previous_json" "$latest" || return 1
  if [[ -n "$previous_generated_at" ]]; then
    soraswap_write_json_file_atomic "$previous_json" "$previous_timestamped" || return 1
  fi
}

deploy_report_preserve_failed_latest() {
  local env="$1"
  local previous_json="${2:-null}"
  local latest failed_latest failed_timestamped current_json generated_at

  latest="$(deploy_report_latest_path_for_env "$env")"
  [[ -s "$latest" ]] || return 1
  current_json="$(jq -c . "$latest" 2>/dev/null)" || return 1
  if ! jq -e '(.status // "") == "failed"' >/dev/null 2>&1 <<<"$current_json"; then
    return 1
  fi

  generated_at="$(jq -r '.generated_at // empty' <<<"$current_json" 2>/dev/null || true)"
  failed_latest="$(deploy_report_failed_latest_path_for_env "$env")"
  if [[ -n "$generated_at" ]]; then
    failed_timestamped="$(deploy_report_failed_timestamped_path_for_env "$env" "$generated_at")"
  else
    failed_timestamped=""
  fi
  soraswap_write_json_report_pair "$current_json" "$failed_latest" "$failed_timestamped" || return 1
  deploy_report_restore_previous_completed_latest "$env" "$previous_json" || true
}

deploy_report_mark_interrupted_if_running() {
  local env="$1"
  local latest timestamp generated_at timestamped interrupted_json

  latest="$(deploy_report_latest_path_for_env "$env")"
  if [[ ! -f "$latest" ]]; then
    return 0
  fi
  if ! jq -e '(.status // "") == "running"' "$latest" >/dev/null 2>&1; then
    return 0
  fi

  timestamp="$(utc_timestamp)"
  if ! interrupted_json="$(jq -c \
    --arg interrupted_at "$timestamp" \
    --arg observer_pid "$$" \
    '
      (.phases // {} | to_entries | map(select((.value.status // "") == "running")) | last | .key) as $phase
      | .status = "failed"
      | .finished_at = (now | floor)
      | .interrupted_at = $interrupted_at
      | .error = ({
        code: "interrupted",
        message: "previous deploy report was still running when a new deploy report started",
        observed_by_pid: ($observer_pid | tonumber)
      } + (if $phase == null then {} else {phase: $phase} end))
    ' "$latest" 2>/dev/null)"; then
    return 0
  fi

  soraswap_write_json_file_atomic "$interrupted_json" "$latest" || return 1
  generated_at="$(jq -r '.generated_at // empty' <<<"$interrupted_json" 2>/dev/null || true)"
  if [[ -n "$generated_at" ]]; then
    timestamped="$(deployments_dir_for_env "$env")/deploy.${generated_at}.json"
    if [[ -f "$timestamped" ]]; then
      soraswap_write_json_file_atomic "$interrupted_json" "$timestamped" || return 1
    fi
  fi
  echo "marked interrupted deploy report before starting a new one: $(soraswap_display_path "$latest")" >&2
}

deploy_report_update() {
  local env="$1"
  shift
  local latest timestamped tmp filter
  local -a jq_args

  latest="$(deploy_report_latest_path_for_env "$env")"
  timestamped="${SORASWAP_DEPLOY_REPORT_TIMESTAMPED:-}"
  tmp="$(mktemp "${latest}.XXXXXX")" || return 1
  jq_args=("$@")
  filter="${jq_args[-1]}"
  jq_args=("${jq_args[@]:0:${#jq_args[@]}-1}")
  if ! jq "${jq_args[@]}" "$filter" "$latest" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "refusing to publish invalid deploy report: $latest" >&2
    return 1
  fi
  if ! mv "$tmp" "$latest"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ -n "$timestamped" ]]; then
    soraswap_write_json_file_atomic "$(cat "$latest")" "$timestamped" || return 1
  fi
}

deploy_report_init() {
  local env="$1"
  local config="$2"
  local report_dir latest timestamped timestamp report_json
  local chain_fingerprint_json

  report_dir="$(deployments_dir_for_env "$env")"
  latest="$(deploy_report_latest_path_for_env "$env")"
  timestamp="$(utc_timestamp)"
  timestamped="$report_dir/deploy.${timestamp}.json"
  mkdir -p "$report_dir"
  deploy_report_mark_interrupted_if_running "$env"
  SORASWAP_DEPLOY_REPORT_TIMESTAMPED="$timestamped"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  report_json="$(jq -n \
    --arg generated_at "$timestamp" \
    --arg environment "$env" \
    --arg authority "${SORASWAP_AUTHORITY:-}" \
    --arg client_config "$(soraswap_display_path "$config")" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --arg pid "$$" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    '{
      generated_at: $generated_at,
      environment: $environment,
      authority: $authority,
      client_config: $client_config,
      torii_url: $torii_url,
      chain_fingerprint: $chain_fingerprint,
      process: {
        pid: ($pid | tonumber)
      },
      status: "running",
      phases: {},
      contracts: {}
    }')"
  soraswap_write_json_report_pair "$report_json" "$latest" "$timestamped"
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

deploy_report_phase_failure_detail_json() {
  local config="$1"
  local exit_status="$2"
  local command_display="$3"
  local output_path="${4:-}"
  local output_tail=""
  local redacted_command
  local public_env=""
  local health_snapshot='null'
  local health_issues='[]'

  soraswap_require_nonnegative_integer_setting "deploy phase exit status" "$exit_status" || return 1
  redacted_command="$(soraswap_redact_sensitive_text "$command_display")"
  if [[ -n "$output_path" && -f "$output_path" ]]; then
    output_tail="$(tail -n 80 "$output_path" | soraswap_redact_sensitive_text)"
  fi

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -n "$public_env" ]]; then
    health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
    if [[ -z "$health_snapshot" || "$health_snapshot" == "null" ]]; then
      health_snapshot='null'
      health_issues='["unable to sample public chain health"]'
    elif ! health_issues="$(soraswap_public_write_health_issues_json "$health_snapshot" 2>/dev/null)"; then
      health_issues='["unable to evaluate public chain health"]'
    fi
  fi

  jq -cn \
    --argjson exit_status "$exit_status" \
    --arg command "$redacted_command" \
    --arg output_tail "$output_tail" \
    --argjson public_write_health_snapshot "$health_snapshot" \
    --argjson public_write_health_issues "$health_issues" \
    '{
      exit_status: $exit_status,
      command: $command,
      output_tail: (if $output_tail == "" then null else $output_tail end),
      public_write_health: (
        if $public_write_health_snapshot == null and ($public_write_health_issues | length) == 0 then
          null
        else
          {
            snapshot: $public_write_health_snapshot,
            issues: $public_write_health_issues
          }
        end
      )
    }'
}

deploy_report_mark_running_phase_failed() {
  local env="$1"
  local config="${2:-}"
  local exit_status="${3:-1}"
  local message="${4:-deploy report stopped before completion}"
  local latest normalized_status detail_json failed_at redacted_message

  latest="$(deploy_report_latest_path_for_env "$env")"
  [[ -s "$latest" ]] || return 0
  if ! jq -e '((.phases // {} | to_entries | map(select((.value.status // "") == "running")) | length) > 0)' \
    "$latest" >/dev/null 2>&1; then
    return 0
  fi

  normalized_status="$exit_status"
  soraswap_require_nonnegative_integer_setting "deploy cleanup exit status" "$normalized_status" || normalized_status=1
  if (( normalized_status == 0 )); then
    normalized_status=1
  fi
  redacted_message="$(soraswap_redact_sensitive_text "$message")"
  failed_at="$(utc_timestamp)"
  if [[ -n "$config" ]]; then
    detail_json="$(deploy_report_phase_failure_detail_json "$config" "$normalized_status" "$redacted_message" 2>/dev/null \
      || jq -cn --argjson exit_status "$normalized_status" --arg command "$redacted_message" '{exit_status: $exit_status, command: $command}')"
  else
    detail_json="$(jq -cn --argjson exit_status "$normalized_status" --arg command "$redacted_message" '{exit_status: $exit_status, command: $command}')"
  fi

  deploy_report_update "$env" \
    --arg failed_at "$failed_at" \
    --arg message "$redacted_message" \
    --argjson exit_status "$normalized_status" \
    --argjson detail "$detail_json" \
    '
      (.phases // {} | to_entries | map(select((.value.status // "") == "running")) | last | .key) as $phase
      | if $phase == null then
          .
        else
          .phases[$phase] = ((.phases[$phase] // {}) + {
            status: "failed",
            detail: $detail,
            updated_at: (now | floor)
          })
        end
      | .failed_at = $failed_at
      | .error = ({
        code: (if ($exit_status == 129 or $exit_status == 130 or $exit_status == 143) then "interrupted" else "failed" end),
        message: $message,
        exit_status: $exit_status
      } + (if $phase == null then {} else {phase: $phase} end))
    '
}

deploy_report_run_phase_command() {
  local env="$1"
  local config="$2"
  local phase="$3"
  shift 3
  local output_path command_display command_status had_errexit=0
  local -a pipeline_status

  output_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-${env}-${phase}.XXXXXX")" || return 1
  command_display="$*"
  [[ -o errexit ]] && had_errexit=1
  set +e
  "$@" 2>&1 | tee "$output_path"
  pipeline_status=("${pipestatus[@]}")
  if (( had_errexit == 1 )); then
    set -e
  else
    set +e
  fi
  command_status="${pipeline_status[1]:-1}"
  if (( command_status != 0 )); then
    local detail_json
    detail_json="$(deploy_report_phase_failure_detail_json "$config" "$command_status" "$command_display" "$output_path" 2>/dev/null || jq -cn --argjson exit_status "$command_status" '{exit_status: $exit_status}')"
    deploy_report_set_phase "$env" "$phase" failed "$detail_json" || true
    rm -f "$output_path"
    return "$command_status"
  fi
  rm -f "$output_path"
  return 0
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
  local expected_env="${3:-}"

  [[ -f "$report_path" ]] || return 1
  jq -e \
    --argjson chain "$chain_fingerprint_json" \
    --arg expected_env "$expected_env" \
    '
      ($chain != null)
      and ((.generated_at // "") | type == "string" and length > 0)
      and (
        ($expected_env == "")
        or (((.environment // "") | type == "string") and .environment == $expected_env)
      )
      and (.chain_fingerprint != null)
      and ((.chain_fingerprint.torii_url // "") | type == "string" and length > 0)
      and .chain_fingerprint.torii_url == $chain.torii_url
      and .chain_fingerprint.chain == $chain.chain
      and .chain_fingerprint.block_1_hash == $chain.block_1_hash
    ' \
    "$report_path" >/dev/null
}

extract_probe_tx_hash() {
  local output="${1:-}"
  local tx_hash

  tx_hash="$(LC_ALL=C sed -n 's/.* transaction \([0-9a-f]\{64\}\).*/\1/p' <<<"$output" | tail -n 1)"
  if [[ -n "$tx_hash" ]]; then
    printf '%s\n' "$tx_hash"
  fi
}

torii_json_endpoint_snapshot() {
  local config="$1"
  local url="$2"
  local tmp http_status body body_json

  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap_torii_json.XXXXXX")"
  http_status="$(soraswap_curl_for_config "$config" -sS \
    -H 'Accept: application/json' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -o "$tmp" \
    -w '%{http_code}' \
    "$url" 2>/dev/null || true)"
  if [[ -z "$http_status" ]]; then
    http_status="000"
  fi
  body="$(cat "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if jq -e . >/dev/null 2>&1 <<<"$body"; then
    body_json="$(jq -c . <<<"$body")"
  else
    body_json='null'
  fi

  jq -cn \
    --arg url "$url" \
    --arg http_status "$http_status" \
    --argjson body "$body_json" \
    '{
      url: $url,
      http_status: $http_status,
      json_available: ($body != null),
      json: $body
    }'
}

torii_json_endpoint_snapshot_with_resolve() {
  local url="$1"
  local resolve_host="$2"
  local resolve_ip="$3"
  local resolve_port="${4:-443}"
  local display_url="${5:-$url}"
  local display_host="${6:-$resolve_host}"
  local tmp http_status body body_json

  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap_torii_json.XXXXXX")"
  http_status="$(soraswap_curl_for_config "" -sS \
    -H 'Accept: application/json' \
    --insecure \
    --resolve "$resolve_host:$resolve_port:$resolve_ip" \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -o "$tmp" \
    -w '%{http_code}' \
    "$url" 2>/dev/null || true)"
  if [[ -z "$http_status" ]]; then
    http_status="000"
  fi
  body="$(cat "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if jq -e . >/dev/null 2>&1 <<<"$body"; then
    body_json="$(jq -c . <<<"$body")"
  else
    body_json='null'
  fi

  jq -cn \
    --arg url "$display_url" \
    --arg host "$display_host" \
    --arg http_status "$http_status" \
    --argjson body "$body_json" \
    '{
      url: $url,
      host: $host,
      tls_verified: false,
      http_status: $http_status,
      json_available: ($body != null),
      json: $body
    }'
}

torii_json_endpoint_snapshot_with_display_url() {
  local url="$1"
  local display_url="$2"
  local tmp http_status body body_json

  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap_torii_json.XXXXXX")"
  http_status="$(soraswap_curl_for_config "" -sS \
    -H 'Accept: application/json' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -o "$tmp" \
    -w '%{http_code}' \
    "$url" 2>/dev/null || true)"
  if [[ -z "$http_status" ]]; then
    http_status="000"
  fi
  body="$(cat "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if jq -e . >/dev/null 2>&1 <<<"$body"; then
    body_json="$(jq -c . <<<"$body")"
  else
    body_json='null'
  fi

  jq -cn \
    --arg url "$display_url" \
    --arg http_status "$http_status" \
    --argjson body "$body_json" \
    '{
      url: $url,
      http_status: $http_status,
      json_available: ($body != null),
      json: $body
    }'
}

soraswap_chain_health_snapshot_from_endpoint_snapshots_json() {
  local status_snapshot="$1"
  local sumeragi_snapshot="$2"

  jq -cn \
    --argjson status_snapshot "$status_snapshot" \
    --argjson sumeragi_snapshot "$sumeragi_snapshot" \
    '
    def normalized_sumeragi_json($json):
      if ($json | type) == "object" then
        $json
      elif ($json | type) == "array" then
        ([
          $json[]?
          | select(type == "object")
          | select(
              ((.canonical // null) | type) == "object"
              or ((.membership // null) | type) == "object"
              or ((.commit_qc // null) | type) == "object"
              or ((.highest_qc // null) | type) == "object"
              or ((.tx_queue // null) | type) == "object"
            )
        ] | if length == 0 then null else max_by(((.canonical.height // .membership.height // .height // 0) | tonumber? // 0)) end)
      else
        null
      end;

    (normalized_sumeragi_json($sumeragi_snapshot.json)) as $sumeragi_json
    | {
      status: {
        url: $status_snapshot.url,
        tls_verified: (if ($status_snapshot | has("tls_verified")) then $status_snapshot.tls_verified else null end),
        http_status: $status_snapshot.http_status,
        json_available: $status_snapshot.json_available,
        summary: (
          if $status_snapshot.json == null then null else {
            blocks: ($status_snapshot.json.blocks // null),
            peers: ($status_snapshot.json.peers // null),
            queue_size: ($status_snapshot.json.queue_size // null),
            queue_queued: ($status_snapshot.json.queue_queued // null),
            queue_inflight: ($status_snapshot.json.queue_inflight // null),
            tx_queue_depth: ($status_snapshot.json.tx_queue_depth // null),
            tx_queue_saturated: (
              if ($status_snapshot.json | has("tx_queue_saturated")) then
                $status_snapshot.json.tx_queue_saturated
              elif (($status_snapshot.json.sumeragi // {}) | has("tx_queue_saturated")) then
                $status_snapshot.json.sumeragi.tx_queue_saturated
              else
                null
              end
            ),
            time_since_last_block_ms: ($status_snapshot.json.time_since_last_block_ms // null),
            time_since_last_non_empty_block_ms: ($status_snapshot.json.time_since_last_non_empty_block_ms // null),
            last_block_committed_at_ms: ($status_snapshot.json.last_block_committed_at_ms // null),
            view_changes: ($status_snapshot.json.view_changes // null),
            teu_backlog_total: (([$status_snapshot.json.teu_dataspace_backlog[]?.backlog] | add) // 0)
          } end
        )
      },
      sumeragi: {
        url: $sumeragi_snapshot.url,
        tls_verified: (if ($sumeragi_snapshot | has("tls_verified")) then $sumeragi_snapshot.tls_verified else null end),
        http_status: $sumeragi_snapshot.http_status,
        json_available: $sumeragi_snapshot.json_available,
        summary: (
          if $sumeragi_json == null then null else {
            height: ($sumeragi_json.canonical.height // $sumeragi_json.membership.height // $sumeragi_json.height // null),
            commit_qc_height: ($sumeragi_json.commit_qc.height // $sumeragi_json.commit_qc_height // null),
            highest_qc_height: ($sumeragi_json.highest_qc.height // $sumeragi_json.highest_qc_height // null),
            phase: ($sumeragi_json.canonical.phase // $sumeragi_json.phase // null),
            rbc_status: ($sumeragi_json.canonical.rbc_status // $sumeragi_json.rbc_status // null),
            payload_status: ($sumeragi_json.canonical.payload_status // $sumeragi_json.payload_status // null),
            tx_queue: {
              depth: ($sumeragi_json.tx_queue.depth // null),
              saturated: (
                if (($sumeragi_json.tx_queue // {}) | has("saturated")) then
                  $sumeragi_json.tx_queue.saturated
                else
                  null
                end
              ),
              saturated_by_age: (
                if (($sumeragi_json.tx_queue // {}) | has("saturated_by_age")) then
                  $sumeragi_json.tx_queue.saturated_by_age
                else
                  null
                end
              ),
              saturated_by_count: (
                if (($sumeragi_json.tx_queue // {}) | has("saturated_by_count")) then
                  $sumeragi_json.tx_queue.saturated_by_count
                else
                  null
                end
              ),
              saturated_by_bytes: (
                if (($sumeragi_json.tx_queue // {}) | has("saturated_by_bytes")) then
                  $sumeragi_json.tx_queue.saturated_by_bytes
                else
                  null
                end
              ),
              oldest_queued_age_ms: ($sumeragi_json.tx_queue.oldest_queued_age_ms // null)
            },
            view_change_last_cause: ($sumeragi_json.view_change_causes.last_cause // null),
            missing_qc_total: ($sumeragi_json.view_change_causes.missing_qc_total // null),
            quorum_timeout_total: ($sumeragi_json.view_change_causes.quorum_timeout_total // null),
            missing_payload_total: ($sumeragi_json.view_change_causes.missing_payload_total // null),
            worker_stage: ($sumeragi_json.worker_loop.stage // null)
          } end
        )
      }
    }'
}

soraswap_public_chain_health_snapshot_json() {
  local config="$1"
  local torii_base status_snapshot sumeragi_snapshot

  torii_base="$(torii_base_from_config "$config")"
  status_snapshot="$(torii_json_endpoint_snapshot "$config" "$torii_base/status")"
  sumeragi_snapshot="$(torii_json_endpoint_snapshot "$config" "$torii_base/v1/sumeragi/status")"
  soraswap_chain_health_snapshot_from_endpoint_snapshots_json "$status_snapshot" "$sumeragi_snapshot"
}

soraswap_taira_direct_validator_health_json() {
  local dns_records_path="${1:-${SORASWAP_TAIRA_DNS_RECORDS_JSON:-$SORASWAP_IROHA_ROOT/configs/soranexus/taira/dns_records.json}}"
  local records_json validators_json host ip status_snapshot sumeragi_snapshot health_json validator_json validator_index validator_label

  if [[ ! -s "$dns_records_path" ]]; then
    jq -cn '{available: false, reason: "dns_records_json_missing", validator_count: 0, validators: []}'
    return 0
  fi

  if ! records_json="$(jq -c '
    [(.records // [])[]?
      | select((.type // "") == "A")
      | select((.name // "") | test("^taira-validator-[0-9]+\\.sora\\.org$"))
      | select((.value // "") | type == "string" and length > 0)
      | {host: .name, ip: .value}]
    | sort_by(.host)
    | unique_by(.host)
  ' "$dns_records_path" 2>/dev/null)"; then
    jq -cn '{available: false, reason: "dns_records_json_invalid", validator_count: 0, validators: []}'
    return 0
  fi

  if [[ "$(jq -r 'length' <<<"$records_json" 2>/dev/null || echo 0)" == "0" ]]; then
    jq -cn '{available: false, reason: "no_validator_records", validator_count: 0, validators: []}'
    return 0
  fi

  validators_json='[]'
  validator_index=1
  while IFS=$'\t' read -r host ip; do
    [[ -n "$host" && -n "$ip" ]] || continue
    validator_label="direct-validator-$validator_index"
    status_snapshot="$(torii_json_endpoint_snapshot_with_resolve "https://$host/status" "$host" "$ip" 443 "$validator_label/status" "[redacted-host]")"
    sumeragi_snapshot="$(torii_json_endpoint_snapshot_with_resolve "https://$host/v1/sumeragi/status" "$host" "$ip" 443 "$validator_label/v1/sumeragi/status" "[redacted-host]")"
    health_json="$(soraswap_chain_health_snapshot_from_endpoint_snapshots_json "$status_snapshot" "$sumeragi_snapshot")"
    validator_json="$(jq -cn \
      --arg host "$validator_label" \
      --argjson source_index "$validator_index" \
      --argjson health "$health_json" \
      '{host: $host, source_index: $source_index, health: $health}')"
    validators_json="$(jq -c --argjson validator "$validator_json" '. + [$validator]' <<<"$validators_json")"
    (( validator_index += 1 ))
  done < <(jq -r '.[] | [.host, .ip] | @tsv' <<<"$records_json")

  jq -cn \
    --argjson validators "$validators_json" \
    '{
      available: true,
      source: "sibling_iroha_dns_records",
      validator_count: ($validators | length),
      validators: $validators
    }'
}

soraswap_taira_direct_torii_port_health_json() {
  local torii_host="${1:-${SORASWAP_TAIRA_DIRECT_TORII_HOST:-}}"
  local torii_ports="${2:-${SORASWAP_TAIRA_DIRECT_TORII_PORTS:-}}"
  local validators_json port status_snapshot sumeragi_snapshot health_json validator_json

  if [[ -z "$torii_host" ]]; then
    jq -cn '{available: false, reason: "direct_torii_host_missing", validator_count: 0, validators: []}'
    return 0
  fi
  if [[ -z "$torii_ports" ]]; then
    jq -cn '{available: false, reason: "direct_torii_ports_missing", validator_count: 0, validators: []}'
    return 0
  fi

  validators_json='[]'
  for port in ${(s:,:)torii_ports}; do
    port="${port//[[:space:]]/}"
    [[ -n "$port" ]] || continue
    if [[ "$port" != <-> ]]; then
      jq -cn --arg port "$port" '{available: false, reason: "invalid_direct_torii_port", invalid_port: $port, validator_count: 0, validators: []}'
      return 0
    fi
    status_snapshot="$(torii_json_endpoint_snapshot_with_display_url "http://$torii_host:$port/status" "direct-torii-port-$port/status")"
    sumeragi_snapshot="$(torii_json_endpoint_snapshot_with_display_url "http://$torii_host:$port/v1/sumeragi/status" "direct-torii-port-$port/v1/sumeragi/status")"
    health_json="$(soraswap_chain_health_snapshot_from_endpoint_snapshots_json "$status_snapshot" "$sumeragi_snapshot")"
    validator_json="$(jq -cn \
      --arg host "port-$port" \
      --argjson port "$port" \
      --argjson health "$health_json" \
      '{host: $host, port: $port, health: $health}')"
    validators_json="$(jq -c --argjson validator "$validator_json" '. + [$validator]' <<<"$validators_json")"
  done

  jq -cn \
    --argjson validators "$validators_json" \
    '{
      available: true,
      source: "direct_torii_ports",
      host: "[redacted-host]",
      validator_count: ($validators | length),
      validators: $validators
    }'
}

soraswap_direct_validator_health_summary_text_from_json() {
  local direct_health_json="$1"

  jq -r '
    def value($v): if $v == null then "unknown" else ($v | tostring) end;
    (.validators // [])[]?
    | (.host // "unknown") as $host
    | (.health.status // {}) as $status
    | (.health.sumeragi // {}) as $sumeragi
    | ($sumeragi.summary // {}) as $summary
    | "direct-validator \($host): status_http=\(value($status.http_status)) sumeragi_http=\(value($sumeragi.http_status)) height=\(value($summary.height)) commit_qc=\(value($summary.commit_qc_height)) highest_qc=\(value($summary.highest_qc_height)) tx_queue_depth=\(value($summary.tx_queue.depth)) saturated=\(value($summary.tx_queue.saturated)) saturated_by_age=\(value($summary.tx_queue.saturated_by_age)) oldest_queued_age_ms=\(value($summary.tx_queue.oldest_queued_age_ms)) payload_status=\(value($summary.payload_status)) view_change=\(value($summary.view_change_last_cause)) missing_payload_total=\(value($summary.missing_payload_total)) worker_stage=\(value($summary.worker_stage))"
  ' <<<"$direct_health_json"
}

soraswap_direct_validator_health_diagnosis_text_from_json() {
  local direct_health_json="$1"
  local age_max_ms="${2:-$SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS}"

  soraswap_require_nonnegative_integer_setting "direct-validator age-saturation threshold" "$age_max_ms" || return 1

  jq -r --argjson age_max_ms "$age_max_ms" '
    def num($v):
      if $v == null then null else ($v | tonumber? // null) end;
    def bool($v):
      $v == true or (($v | tostring | ascii_downcase) == "true");

    (.validators // []) as $validators
    | [ $validators[]?
        | select(((.health.status.http_status // "") | tostring) == "200")
        | select(.health.status.json_available == true)
        | select(((.health.sumeragi.http_status // "") | tostring) == "200")
        | select(.health.sumeragi.json_available == true)
      ] as $ready
    | [ $ready[]? | (.health.sumeragi.summary // {}) ] as $summaries
    | ($validators | length) as $validator_count
    | ($ready | length) as $ready_count
    | [ $summaries[]?
        | select(
            (num(.height) != null)
            and (num(.commit_qc_height) != null)
            and (num(.highest_qc_height) != null)
            and (num(.height) == (num(.commit_qc_height) + 1))
            and (num(.height) == (num(.highest_qc_height) + 1))
          )
      ] as $one_height_ahead
    | [ $summaries[]?
        | select(
            ((num(.tx_queue.depth) // 0) > 0)
            or bool(.tx_queue.saturated)
            or bool(.tx_queue.saturated_by_age)
          )
      ] as $queued
    | [ $summaries[]?
        | select(
            bool(.tx_queue.saturated_by_age)
            and (
              ($age_max_ms == 0)
              or ((num(.tx_queue.oldest_queued_age_ms) // 0) >= $age_max_ms)
            )
          )
      ] as $age_saturated
    | [ $summaries[]?
        | ((.view_change_last_cause // "") | tostring | ascii_downcase)
        | select(. == "missing_qc" or . == "quorum_timeout")
      ] as $view_change_blocked
    | [ $summaries[]?
        | ((.worker_stage // "") | tostring | ascii_downcase)
        | select(. == "idle")
      ] as $idle_workers
    | if (
        $validator_count > 0
        and $ready_count == $validator_count
        and ($one_height_ahead | length) == $ready_count
        and (
          ($queued | length) > 0
          or ($age_saturated | length) > 0
          or ($view_change_blocked | length) > 0
        )
      ) then
        "direct-validator diagnosis: sampled validators are one height ahead of committed/highest QC with \($queued | length) queued/saturated peer(s), \($age_saturated | length) age-saturated peer(s), \($view_change_blocked | length) missing_qc/quorum_timeout peer(s), and \($idle_workers | length) idle worker(s); pause SoraSwap signed writes and use the Taira operator finality recovery runbook before retrying release evidence"
      else
        empty
      end
  ' <<<"$direct_health_json"
}

soraswap_public_chain_health_summary_text_from_json() {
  local health_json="$1"

  jq -r '
    def value($v): if $v == null then "unknown" else ($v | tostring) end;
    (.status.summary // {}) as $status
    | (.sumeragi.summary // {}) as $sumeragi
    | "blocks=\(value($status.blocks)) sumeragi_height=\(value($sumeragi.height)) commit_qc=\(value($sumeragi.commit_qc_height)) highest_qc=\(value($sumeragi.highest_qc_height)) queue=\(value($status.queue_size // $sumeragi.tx_queue.depth)) tx_queue_depth=\(value($sumeragi.tx_queue.depth // $status.tx_queue_depth)) tx_queue_saturated=\(value($sumeragi.tx_queue.saturated // $status.tx_queue_saturated)) saturated_by_age=\(value($sumeragi.tx_queue.saturated_by_age)) oldest_queued_age_ms=\(value($sumeragi.tx_queue.oldest_queued_age_ms)) time_since_last_block_ms=\(value($status.time_since_last_block_ms)) phase=\(value($sumeragi.phase)) rbc_status=\(value($sumeragi.rbc_status)) payload_status=\(value($sumeragi.payload_status)) view_change=\(value($sumeragi.view_change_last_cause)) missing_qc_total=\(value($sumeragi.missing_qc_total)) quorum_timeout_total=\(value($sumeragi.quorum_timeout_total)) missing_payload_total=\(value($sumeragi.missing_payload_total)) worker_stage=\(value($sumeragi.worker_stage))"
  ' <<<"$health_json"
}

soraswap_public_chain_queued_stall_detected() {
  local health_json="$1"
  local max_stall_ms="$2"

  if [[ -z "$health_json" || "$health_json" == "null" ]]; then
    return 1
  fi
  soraswap_require_nonnegative_integer_setting "queued-write stall threshold" "$max_stall_ms" || return 2
  if (( max_stall_ms <= 0 )); then
    return 1
  fi

  jq -e --argjson max_stall_ms "$max_stall_ms" '
    def num($v): ($v | tonumber? // 0);
    def bool($v): if $v == true then true else false end;
    (.status.summary // {}) as $status
    | (.sumeragi.summary // {}) as $sumeragi
    | ($sumeragi.tx_queue.oldest_queued_age_ms // null) as $oldest_queued_age_ms
    | (num($status.queue_size // $status.tx_queue_depth // $sumeragi.tx_queue.depth) > 0
        or bool($status.tx_queue_saturated)
        or bool($sumeragi.tx_queue.saturated)
        or bool($sumeragi.tx_queue.saturated_by_age)) as $has_queued_or_saturated_write
    | (num($oldest_queued_age_ms) >= $max_stall_ms
        or ($oldest_queued_age_ms == null and num($status.time_since_last_block_ms) >= $max_stall_ms)
        or ($oldest_queued_age_ms == null and bool($sumeragi.tx_queue.saturated_by_age))) as $stale
    | $has_queued_or_saturated_write and $stale
  ' >/dev/null <<<"$health_json"
}

soraswap_public_write_health_issues_json() {
  local health_json="$1"
  local queue_max="${2:-$SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX}"
  local qc_lag_max="${3:-$SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX}"
  local age_max_ms="${4:-$SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS}"

  if [[ -z "$health_json" || "$health_json" == "null" ]]; then
    printf '%s\n' '["public chain health snapshot is empty"]'
    return 0
  fi

  jq -c \
    --argjson queue_max "$queue_max" \
    --argjson qc_lag_max "$qc_lag_max" \
    --argjson age_max_ms "$age_max_ms" \
    '
      def num($v):
        if $v == null then null else ($v | tonumber? // null) end;
      def bool($v):
        $v == true or (($v | tostring | ascii_downcase) == "true");
      def present_text($v):
        ($v // "") | tostring;

      (.status.summary // {}) as $status
      | (.sumeragi.summary // {}) as $sumeragi
      | (num($status.blocks)) as $blocks
      | (num($sumeragi.height)) as $height
      | (num($sumeragi.commit_qc_height)) as $commit_qc
      | (num($sumeragi.highest_qc_height)) as $highest_qc
      | (num($status.queue_size // $status.tx_queue_depth // $sumeragi.tx_queue.depth)) as $queue_size
      | (num($status.queue_queued)) as $queue_queued
      | (num($status.queue_inflight)) as $queue_inflight
      | (num($status.time_since_last_block_ms)) as $time_since_last_block_ms
      | (num($sumeragi.tx_queue.oldest_queued_age_ms)) as $oldest_queued_age_ms
      | (bool($status.tx_queue_saturated) or bool($sumeragi.tx_queue.saturated) or bool($sumeragi.tx_queue.saturated_by_age)) as $queue_saturated
      | (
          ($queue_size != null and $queue_size > 0)
          or ($queue_queued != null and $queue_queued > 0)
          or ($queue_inflight != null and $queue_inflight > 0)
          or $queue_saturated
        ) as $queue_pressure
      | ($highest_qc != null and $commit_qc != null and (($highest_qc - $commit_qc) > $qc_lag_max)) as $qc_lag_high
      | ($height != null and (($commit_qc != null and $height > $commit_qc) or ($highest_qc != null and $height > $highest_qc))) as $canonical_ahead
      | ((present_text($sumeragi.phase) | ascii_downcase) == "pending_finality") as $pending_finality
      | ((present_text($sumeragi.view_change_last_cause) | test("^(missing_qc|quorum_timeout)$"; "i"))) as $view_change_blocked
      | ((present_text($sumeragi.payload_status) | ascii_downcase) == "missing_local_payload") as $missing_local_payload
      | [
          if ((.status.http_status // "") != "200") then
            "status endpoint returned HTTP \(.status.http_status // "unknown")"
          else empty end,
          if ((.sumeragi.http_status // "") != "200") then
            "sumeragi endpoint returned HTTP \(.sumeragi.http_status // "unknown")"
          else empty end,
          if (.status.json_available != true) then
            "status endpoint did not return JSON"
          else empty end,
          if (.sumeragi.json_available != true) then
            "sumeragi endpoint did not return JSON"
          else empty end,
          if $blocks == null then
            "status summary is missing committed block height"
          elif $blocks < 1 then
            "status blocks is \($blocks); public Torii status is not reporting committed blocks"
          else empty end,
          if $height == null then
            "sumeragi status is missing canonical height"
          elif $height < 1 then
            "sumeragi canonical height is \($height)"
          else empty end,
          if $commit_qc != null and $commit_qc < 1 then
            "sumeragi commit_qc_height is \($commit_qc)"
          else empty end,
          if $qc_lag_high then
            "sumeragi highest_qc_height is \($highest_qc - $commit_qc) ahead of commit_qc_height, above SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX=\($qc_lag_max)"
          else empty end,
          if $time_since_last_block_ms != null
              and ($age_max_ms == 0 or $time_since_last_block_ms >= $age_max_ms)
              and (
                ($blocks == null or $blocks < 1)
                or $queue_pressure
                or $qc_lag_high
                or (($canonical_ahead or $pending_finality) and $queue_pressure)
                or $view_change_blocked
                or $missing_local_payload
              ) then
            "latest committed block is stale at \($time_since_last_block_ms)ms, at or above SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS=\($age_max_ms)"
          else empty end,
          if $queue_size != null and $queue_size > $queue_max then
            "transaction queue size \($queue_size) exceeds SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX=\($queue_max)"
          else empty end,
          if bool($status.tx_queue_saturated) or bool($sumeragi.tx_queue.saturated) then
            "transaction queue is saturated"
          else empty end,
          if bool($sumeragi.tx_queue.saturated_by_age) and ($age_max_ms == 0 or ($oldest_queued_age_ms != null and $oldest_queued_age_ms >= $age_max_ms)) then
            "transaction queue is age-saturated with oldest queued age \($oldest_queued_age_ms // "unknown")ms, at or above SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS=\($age_max_ms)"
          elif bool($sumeragi.tx_queue.saturated_by_age) and $oldest_queued_age_ms == null then
            "transaction queue is age-saturated and oldest queued age is unavailable"
          else empty end,
          if $view_change_blocked then
            "sumeragi view-change cause is \(present_text($sumeragi.view_change_last_cause))"
          else empty end,
          if $missing_local_payload then
            "sumeragi payload status is missing_local_payload"
          else empty end,
          if ((present_text($sumeragi.worker_stage) | ascii_downcase) == "idle") and ($queue_size != null and $queue_size > 0) then
            "sumeragi worker is idle while the transaction queue is non-empty"
          else empty end
        ]
    ' <<<"$health_json"
}

soraswap_require_public_write_health_ready() {
  local public_env="$1"
  local config="$2"
  local label="${3:-public mutation}"
  local health_snapshot issues_json issue_count health_summary
  local retry_count="$SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT"
  local retry_delay_secs="$SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS"
  local attempt=0 last_failure="degraded"

  soraswap_validate_torii_read_max_time || return 1
  soraswap_validate_public_write_health_settings || return 1

  while (( attempt <= retry_count )); do
    health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
    if [[ -z "$health_snapshot" || "$health_snapshot" == "null" ]]; then
      last_failure="sample"
    elif ! issues_json="$(soraswap_public_write_health_issues_json "$health_snapshot")"; then
      last_failure="evaluate"
    else
      issue_count="$(jq -r 'length' <<<"$issues_json" 2>/dev/null || echo 1)"
      if [[ -z "$issue_count" || "$issue_count" != <-> ]]; then
        issue_count=1
      fi
      if (( issue_count == 0 )); then
        return 0
      fi
      last_failure="degraded"
    fi

    if (( attempt < retry_count )); then
      sleep "$retry_delay_secs"
    fi
    attempt=$(( attempt + 1 ))
  done

  case "$last_failure" in
    sample)
      echo "$label blocked: unable to sample public $public_env chain health after $(( retry_count + 1 )) attempt(s)" >&2
      return 75
      ;;
    evaluate)
      echo "$label blocked: unable to evaluate public $public_env chain health after $(( retry_count + 1 )) attempt(s)" >&2
      return 75
      ;;
    *)
      ;;
  esac

  if [[ -n "$issues_json" ]]; then
    echo "$label blocked: public $public_env write health is degraded" >&2
    jq -r '.[] | "  - " + .' <<<"$issues_json" | soraswap_redact_sensitive_text >&2
    health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
    if [[ -n "$health_summary" ]]; then
      echo "  health: $(soraswap_redact_sensitive_text "$health_summary")" >&2
    fi
    return 75
  fi

  echo "$label blocked: public $public_env write health is degraded" >&2
  return 75
}

soraswap_require_public_write_health_ready_for_config() {
  local config="$1"
  local label="${2:-public mutation}"
  local public_env

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ -z "$public_env" ]] && return 0

  soraswap_require_public_write_health_ready "$public_env" "$config" "$label"
}

soraswap_require_public_submit_health_ready_for_config() {
  local config="$1"
  local label="${2:-public mutation submit}"
  local public_env

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ -z "$public_env" ]] && return 0

  soraswap_validate_public_write_health_settings || return 1
  (
    export SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT="$SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT"
    export SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS="$SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS"
    soraswap_require_public_write_health_ready "$public_env" "$config" "$label"
  )
}

soraswap_print_public_write_health_wait_context() {
  local config="$1"
  local label="${2:-public transaction wait}"
  local public_env health_snapshot issues_json issue_count health_summary

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ -z "$public_env" ]] && return 0

  health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
  if [[ -z "$health_snapshot" || "$health_snapshot" == "null" ]]; then
    echo "$label health at timeout: unable to sample public $public_env write health" >&2
    return 0
  fi

  if ! issues_json="$(soraswap_public_write_health_issues_json "$health_snapshot" 2>/dev/null)"; then
    echo "$label health at timeout: unable to evaluate public $public_env write health" >&2
    return 0
  fi

  issue_count="$(jq -r 'length' <<<"$issues_json" 2>/dev/null || echo 1)"
  if [[ -z "$issue_count" || "$issue_count" != <-> ]]; then
    issue_count=1
  fi

  if (( issue_count > 0 )); then
    echo "$label health at timeout: public $public_env write health is degraded" >&2
    jq -r '.[] | "  - " + .' <<<"$issues_json" | soraswap_redact_sensitive_text >&2
  else
    echo "$label health at timeout: public $public_env write health is ready" >&2
  fi

  health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
  if [[ -n "$health_summary" ]]; then
    echo "  health: $(soraswap_redact_sensitive_text "$health_summary")" >&2
  fi
}

nested_call_probe_health_snapshot_json() {
  soraswap_public_chain_health_snapshot_json "$1"
}

nested_call_probe_health_summary_text() {
  local report_path="$1"

  [[ -s "$report_path" ]] || return 1
  jq -r '
    def field($object; $key):
      if (($object // {}) | has($key)) then $object[$key] else "unknown" end;
    .health_snapshot.sumeragi.summary? as $health
    | if $health == null then empty else
        "height=\($health.height // "unknown") queue_depth=\($health.tx_queue.depth // "unknown") saturated=\(field($health.tx_queue; "saturated")) saturated_by_age=\(field($health.tx_queue; "saturated_by_age")) view_change=\($health.view_change_last_cause // "none")"
      end
  ' "$report_path"
}

write_nested_call_probe_failure_report() {
  local env="$1"
  local config="$2"
  local timestamp="$3"
  local latest_report="$4"
  local timestamped_report="$5"
  local chain_fingerprint_json="$6"
  local compiler_bin="$7"
  local probe_dir="$8"
  local stage="$9"
  local output="${10:-}"
  local summary blocked_reason health_snapshot_json report_json redacted_output

  summary="nested-call runtime probe failed during $stage"
  blocked_reason="public runtime probe could not complete $stage; see stages.$stage.output"
  redacted_output="$(soraswap_redact_sensitive_text "$output")"
  health_snapshot_json="$(nested_call_probe_health_snapshot_json "$config")"
  report_json="$(jq -n \
    --arg generated_at "$timestamp" \
    --arg environment "$env" \
    --arg authority "${SORASWAP_AUTHORITY:-}" \
    --arg client_config "$(soraswap_display_path "$config")" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --arg compiler_bin "$(soraswap_display_path "$compiler_bin")" \
    --arg probe_dir "$(soraswap_display_path "$probe_dir")" \
    --arg summary "$summary" \
    --arg blocked_reason "$blocked_reason" \
    --arg stage "$stage" \
    --arg output "$redacted_output" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    --argjson health_snapshot "$health_snapshot_json" \
    '{
      generated_at: $generated_at,
      environment: $environment,
      authority: $authority,
      client_config: $client_config,
      torii_url: $torii_url,
      chain_fingerprint: $chain_fingerprint,
      state_bytes_roundtrip_supported: false,
      nested_call_supported: false,
      nested_asset_ops_supported: false,
      supported: false,
      summary: $summary,
      blocked_reason: $blocked_reason,
      health_snapshot: $health_snapshot,
      compiler_bin: $compiler_bin,
      probe_dir: $probe_dir,
      contracts: {},
      stages: {
        ($stage): {
          status: "failed",
          output: $output
        }
      }
    }')"

  soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report" || return 1
  printf '%s\n' "$report_json"
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
  local confirm_output
  local bytes_probe_contract callee_contract caller_contract asset_callee_contract asset_middle_contract asset_caller_contract
  local asset_callee_subject asset_middle_subject asset_caller_subject
  local bytes_bind_output bytes_bind_status bytes_bind_tx_hash
  local bytes_view_output bytes_view_status bytes_view_result_hex
  local bind_output bind_status ping_output ping_status bind_tx_hash ping_tx_hash
  local asset_bind_callee_output asset_bind_callee_status asset_bind_callee_tx_hash
  local asset_bind_middle_output asset_bind_middle_status asset_bind_middle_tx_hash
  local asset_bind_caller_output asset_bind_caller_status asset_bind_caller_tx_hash
  local asset_relay_output asset_relay_status asset_relay_tx_hash
  local asset_permission_output asset_probe_subject asset_probe_account_readback_json
  local asset_permission_receipt_json asset_permission_subjects_json operator_account_readback_json
  local asset_balance_check_status asset_balance_check_output
  local probe_asset_alias probe_asset_id probe_amount
  local asset_callee_balance asset_middle_balance asset_caller_balance
  local state_bytes_roundtrip_supported nested_call_supported nested_asset_ops_supported supported
  local summary blocked_reason report_json

  ensure_client "$config"
  ensure_authority "$config"
  ensure_koto_bin >/dev/null
  compiler_bin="$SORASWAP_ACTIVE_KOTO_BIN"
  timestamp="$(utc_timestamp)"
  stamp="$(env TZ=UTC date '+%Y%m%d%H%M%S')$(od -An -tx1 -N4 /dev/urandom | tr -d ' \n')"
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

  kotoage fn bind_value(value: bytes) {
    Stored = value;
  }

  view fn get_value() -> bytes {
    return Stored;
  }
}
EOF

  cat >"$callee_src" <<'EOF'
seiyaku NestedProbeCallee {
  kotoage fn noop() -> int {
    return 13;
  }
}
EOF

  cat >"$caller_src" <<'EOF'
seiyaku NestedProbeCaller {
  state bytes CalleeContract;
  state bytes CalleeEntrypoint;

  kotoage fn bind_target(callee_contract: bytes, callee_entrypoint: bytes) {
    CalleeContract = callee_contract;
    CalleeEntrypoint = callee_entrypoint;
  }

  kotoage fn ping() -> int permission(AssetOps) {
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

  kotoage fn bind_contract(contract_id: AccountId, asset: AssetDefinitionId) {
    ProbeAsset = asset;
    CalleeContractId = contract_id;
    Initialized = 1;
  }

  kotoage fn receive(amount: int) -> int permission(AssetOps) {
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), CalleeContractId, ProbeAsset, amount, dataspace_id("0"));
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

  kotoage fn bind_target(contract_id: AccountId,
                         callee_contract: bytes,
                         asset: AssetDefinitionId) {
    MiddleContractId = contract_id;
    CalleeContract = callee_contract;
    ProbeAsset = asset;
    Initialized = 1;
  }

  kotoage fn relay(amount: int) -> int permission(AssetOps) {
    let payload = json_object();
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), MiddleContractId, ProbeAsset, amount, dataspace_id("0"));
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

  kotoage fn bind_target(contract_id: AccountId,
                         middle_contract: bytes,
                         asset: AssetDefinitionId) {
    CallerContractId = contract_id;
    MiddleContract = middle_contract;
    ProbeAsset = asset;
    Initialized = 1;
  }

  kotoage fn relay(amount: int) -> int permission(AssetOps) {
    let payload = json_object();
    assert_initialized();
    assert(amount > 0, "invalid amount");
    transfer_asset(authority(), CallerContractId, ProbeAsset, amount, dataspace_id("0"));
    let payload = json_set_int(payload, name("amount"), amount);
    return decode_int(call_contract(MiddleContract, "relay", payload));
  }
}
EOF

  (
    cd "$SORASWAP_IROHA_ROOT"
    "$compiler_bin" build --out "$bytes_probe_to" --manifest-out "$bytes_probe_manifest" "$bytes_probe_src" >/dev/null
    "$compiler_bin" build --out "$callee_to" --manifest-out "$callee_manifest" "$callee_src" >/dev/null
    "$compiler_bin" build --out "$caller_to" --manifest-out "$caller_manifest" "$caller_src" >/dev/null
    "$compiler_bin" build --out "$asset_callee_to" --manifest-out "$asset_callee_manifest" "$asset_callee_src" >/dev/null
    "$compiler_bin" build --out "$asset_middle_to" --manifest-out "$asset_middle_manifest" "$asset_middle_src" >/dev/null
    "$compiler_bin" build --out "$asset_caller_to" --manifest-out "$asset_caller_manifest" "$asset_caller_src" >/dev/null
  )
  bytes_probe_code_hash="$(manifest_code_hash_hex "$bytes_probe_manifest")"
  callee_code_hash="$(manifest_code_hash_hex "$callee_manifest")"
  caller_code_hash="$(manifest_code_hash_hex "$caller_manifest")"
  asset_callee_code_hash="$(manifest_code_hash_hex "$asset_callee_manifest")"
  asset_middle_code_hash="$(manifest_code_hash_hex "$asset_middle_manifest")"
  asset_caller_code_hash="$(manifest_code_hash_hex "$asset_caller_manifest")"

  bytes_probe_alias="npb${stamp}::scratch.universal"
  callee_alias="npc${stamp}::scratch.universal"
  caller_alias="npr${stamp}::scratch.universal"
  asset_callee_alias="nac${stamp}::scratch.universal"
  asset_middle_alias="nam${stamp}::scratch.universal"
  asset_caller_alias="nar${stamp}::scratch.universal"
  probe_asset_alias="$SORASWAP_BASE_ASSET_ALIAS"
  if ! probe_asset_id="$(asset_definition_id_for_alias "$config" "$probe_asset_alias" 2>/dev/null)"; then
    probe_asset_id="$SORASWAP_XOR_ASSET_DEFINITION_ID"
    echo "$env nested-call probe: base asset alias $probe_asset_alias is not query-visible; using configured fallback $probe_asset_id" >&2
  fi
  probe_amount=1
  if ! bytes_probe_response="$(submit_contract_deploy_file "$config" "$bytes_probe_to" "$bytes_probe_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_bytes_probe" "$bytes_probe_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$bytes_probe_response" "nested_probe.bytes" "$bytes_probe_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_bytes_probe" "$confirm_output"
    return 0
  fi
  bytes_probe_response="$(normalize_contract_deploy_response_json "$bytes_probe_response")"

  if ! callee_response="$(submit_contract_deploy_file "$config" "$callee_to" "$callee_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_callee" "$callee_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$callee_response" "nested_probe.callee" "$callee_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_callee" "$confirm_output"
    return 0
  fi
  callee_response="$(normalize_contract_deploy_response_json "$callee_response")"

  if ! caller_response="$(submit_contract_deploy_file "$config" "$caller_to" "$caller_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_caller" "$caller_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$caller_response" "nested_probe.caller" "$caller_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_caller" "$confirm_output"
    return 0
  fi
  caller_response="$(normalize_contract_deploy_response_json "$caller_response")"

  if ! asset_callee_response="$(submit_contract_deploy_file "$config" "$asset_callee_to" "$asset_callee_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_asset_callee" "$asset_callee_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$asset_callee_response" "nested_probe.asset_callee" "$asset_callee_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_asset_callee" "$confirm_output"
    return 0
  fi
  asset_callee_response="$(normalize_contract_deploy_response_json "$asset_callee_response")"

  if ! asset_middle_response="$(submit_contract_deploy_file "$config" "$asset_middle_to" "$asset_middle_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_asset_middle" "$asset_middle_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$asset_middle_response" "nested_probe.asset_middle" "$asset_middle_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_asset_middle" "$confirm_output"
    return 0
  fi
  asset_middle_response="$(normalize_contract_deploy_response_json "$asset_middle_response")"

  if ! asset_caller_response="$(submit_contract_deploy_file "$config" "$asset_caller_to" "$asset_caller_alias" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "deploy_asset_caller" "$asset_caller_response"
    return 0
  fi
  if ! confirm_output="$(confirm_contract_deploy_response "$config" "$asset_caller_response" "nested_probe.asset_caller" "$asset_caller_code_hash" 2>&1)"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "confirm_deploy_asset_caller" "$confirm_output"
    return 0
  fi
  asset_caller_response="$(normalize_contract_deploy_response_json "$asset_caller_response")"
  bytes_probe_contract="$(jq -r '.contract_address' <<<"$bytes_probe_response")"
  callee_contract="$(jq -r '.contract_address' <<<"$callee_response")"
  caller_contract="$(jq -r '.contract_address' <<<"$caller_response")"
  asset_callee_contract="$(jq -r '.contract_address' <<<"$asset_callee_response")"
  asset_middle_contract="$(jq -r '.contract_address' <<<"$asset_middle_response")"
  asset_caller_contract="$(jq -r '.contract_address' <<<"$asset_caller_response")"
  asset_callee_subject="$(contract_subject_account_for_literal "$config" "$asset_callee_contract")"
  asset_middle_subject="$(contract_subject_account_for_literal "$config" "$asset_middle_contract")"
  asset_caller_subject="$(contract_subject_account_for_literal "$config" "$asset_caller_contract")"

  if ! asset_permission_output="$(
    {
      ensure_unit_account_permission "$config" "$SORASWAP_AUTHORITY" AssetOps
      for asset_probe_subject in "$asset_caller_subject" "$asset_middle_subject" "$asset_callee_subject"; do
        ensure_account_registered "$config" "$asset_probe_subject" contract-subject
        ensure_unit_account_permission "$config" "$asset_probe_subject" AssetOps
      done
    } 2>&1
  )"; then
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "prepare_asset_ops_permissions" "$asset_permission_output"
    return 0
  fi
  asset_permission_subjects_json='[]'
  typeset -A asset_probe_subject_seen
  for asset_probe_subject in "$asset_caller_subject" "$asset_middle_subject" "$asset_callee_subject"; do
    if [[ -n "${asset_probe_subject_seen[$asset_probe_subject]-}" ]]; then
      asset_permission_output="nested AssetOps probe resolved duplicate contract-subject account: $asset_probe_subject"
      write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "verify_asset_ops_permissions" "$asset_permission_output"
      return 0
    fi
    asset_probe_subject_seen[$asset_probe_subject]=1
    asset_probe_account_readback_json="$(exact_account_readback_json "$config" "$asset_probe_subject")" || return 1
    if ! jq -e '.query_available == true and .matched == true' >/dev/null <<<"$asset_probe_account_readback_json" \
      || ! account_has_unit_permission "$config" "$asset_probe_subject" AssetOps; then
      asset_permission_output="nested AssetOps probe subject account/permission is not query-visible: $asset_probe_subject"
      write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "verify_asset_ops_permissions" "$asset_permission_output"
      return 0
    fi
    asset_permission_subjects_json="$(jq -cn \
      --argjson current "$asset_permission_subjects_json" \
      --arg account "$asset_probe_subject" \
      --argjson account_readback "$asset_probe_account_readback_json" \
      '$current + [{account: $account, account_present: true, account_readback: $account_readback, permission_present: true}]')"
  done
  operator_account_readback_json="$(exact_account_readback_json "$config" "$SORASWAP_AUTHORITY")" || return 1
  if ! jq -e '.query_available == true and .matched == true' >/dev/null <<<"$operator_account_readback_json" \
    || ! account_has_unit_permission "$config" "$SORASWAP_AUTHORITY" AssetOps; then
    asset_permission_output="nested AssetOps probe operator permission is not query-visible after provisioning"
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "verify_asset_ops_permissions" "$asset_permission_output"
    return 0
  fi
  if ! jq -e '
      length == 3
      and ([.[].account] | unique | length) == 3
      and all(.[];
        .account_present == true
        and .permission_present == true
        and .account_readback.query_available == true
        and .account_readback.matched == true)
    ' >/dev/null <<<"$asset_permission_subjects_json"; then
    asset_permission_output="nested AssetOps probe permission receipt readback is incomplete or non-unique"
    write_nested_call_probe_failure_report "$env" "$config" "$timestamp" "$latest_report" "$timestamped_report" "$chain_fingerprint_json" "$compiler_bin" "$probe_dir" "verify_asset_ops_permissions" "$asset_permission_output"
    return 0
  fi
  asset_permission_receipt_json="$(jq -cn \
    --arg generated_at "$(utc_timestamp)" \
    --arg environment "$env" \
    --arg authority "$SORASWAP_AUTHORITY" \
    --arg caller "$asset_caller_subject" \
    --arg middle "$asset_middle_subject" \
    --arg callee "$asset_callee_subject" \
    --argjson subjects "$asset_permission_subjects_json" \
    --argjson operator_account_readback "$operator_account_readback_json" \
    --arg mutation_gate "$(public_mutation_gate_var_for_env "$env" 2>/dev/null || true)" \
    --argjson mutation_approved "$(if public_mutations_allowed_for_env "$env"; then echo true; else echo false; fi)" \
    '{
      status: "completed",
      generated_at: $generated_at,
      environment: $environment,
      operator: {
        authority: $authority,
        policy: (if $environment == "production" then "preprovisioned_verify_only" else "ensure_present" end),
        account_present: true,
        account_readback: $operator_account_readback,
        asset_ops_present: true
      },
      subject_grants: {
        approval: (if $environment == "production" then {gate: $mutation_gate, value: $mutation_approved} else null end),
        permission: {name: "AssetOps", payload: null},
        expected_count: 3,
        verified_count: ($subjects | length),
        accounts: [$caller, $middle, $callee],
        readback: $subjects
      }
    }')"

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
    --arg client_config "$(soraswap_display_path "$config")" \
    --arg torii_url "$(torii_base_from_config "$config")" \
    --arg compiler_bin "$(soraswap_display_path "$compiler_bin")" \
    --arg probe_dir "$(soraswap_display_path "$probe_dir")" \
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
    --argjson permission_provisioning "$asset_permission_receipt_json" \
    --argjson supported "$supported" \
    --arg summary "$summary" \
    --arg blocked_reason "$blocked_reason" \
    --arg bytes_bind_status "$bytes_bind_status" \
    --arg bytes_bind_output "$(soraswap_redact_sensitive_text "$bytes_bind_output")" \
    --arg bytes_bind_tx_hash "$bytes_bind_tx_hash" \
    --arg bytes_view_status "$bytes_view_status" \
    --arg bytes_view_output "$(soraswap_redact_sensitive_text "$bytes_view_output")" \
    --arg bytes_view_result_hex "$bytes_view_result_hex" \
    --arg bind_status "$bind_status" \
    --arg bind_output "$(soraswap_redact_sensitive_text "$bind_output")" \
    --arg bind_tx_hash "$bind_tx_hash" \
    --arg ping_status "$ping_status" \
    --arg ping_output "$(soraswap_redact_sensitive_text "$ping_output")" \
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
    --arg asset_bind_callee_output "$(soraswap_redact_sensitive_text "$asset_bind_callee_output")" \
    --arg asset_bind_callee_tx_hash "$asset_bind_callee_tx_hash" \
    --arg asset_bind_middle_status "$asset_bind_middle_status" \
    --arg asset_bind_middle_output "$(soraswap_redact_sensitive_text "$asset_bind_middle_output")" \
    --arg asset_bind_middle_tx_hash "$asset_bind_middle_tx_hash" \
    --arg asset_bind_caller_status "$asset_bind_caller_status" \
    --arg asset_bind_caller_output "$(soraswap_redact_sensitive_text "$asset_bind_caller_output")" \
    --arg asset_bind_caller_tx_hash "$asset_bind_caller_tx_hash" \
    --arg asset_relay_status "$asset_relay_status" \
    --arg asset_relay_output "$(soraswap_redact_sensitive_text "$asset_relay_output")" \
    --arg asset_relay_tx_hash "$asset_relay_tx_hash" \
    --arg asset_balance_check_status "$asset_balance_check_status" \
    --arg asset_balance_check_output "$(soraswap_redact_sensitive_text "$asset_balance_check_output")" \
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
      permission_provisioning: $permission_provisioning,
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

  soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report" || return 1
  printf '%s\n' "$report_json"
}

ensure_nested_call_runtime_supported() {
  local env="$1"
  local config="$2"
  local latest_report chain_fingerprint_json probe_json
  local force_probe="${SORASWAP_FORCE_NESTED_CALL_PROBE:-0}"

  soraswap_require_binary_integer_setting "SORASWAP_FORCE_NESTED_CALL_PROBE" "$force_probe" || return 1

  latest_report="$(nested_call_probe_latest_path_for_env "$env")"
  chain_fingerprint_json="$(chain_fingerprint_json_or_null)"
  if [[ "$force_probe" != "1" ]] \
    && nested_call_probe_matches_current_chain "$latest_report" "$chain_fingerprint_json" "$env" \
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
    echo "nested call runtime probe failed for $env: state bytes roundtrip passed but minimal nested call_contract(...) still failed; see $(soraswap_display_path "$(nested_call_probe_latest_path_for_env "$env")")" >&2
  elif jq -e '.state_bytes_roundtrip_supported == true and .nested_call_supported == true and .nested_asset_ops_supported == false' <<<"$probe_json" >/dev/null 2>&1; then
    echo "nested call runtime probe failed for $env: basic nested call_contract(...) passed but nested AssetOps relay failed; see $(soraswap_display_path "$(nested_call_probe_latest_path_for_env "$env")")" >&2
  else
    echo "nested call runtime probe failed for $env; see $(soraswap_display_path "$(nested_call_probe_latest_path_for_env "$env")")" >&2
  fi
  return 1
}

deploy_progress_note() {
  local contract_key="$1"
  local stage="$2"
  local detail="${3:-}"
  local progress_log="${SORASWAP_DEPLOY_PROGRESS_LOG:-1}"

  if [[ "$progress_log" == "0" ]]; then
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
  local metadata

  if public_env_for_config "$config" >/dev/null 2>&1; then
    metadata="$(soraswap_inspect_client_config "$config" metadata)" || return 1
    jq -r '.account_public_key // empty' <<<"$metadata"
    return 0
  fi
  account_toml_string_value "$config" public_key
}

network_prefix_for_config() {
  local config="$1"
  local public_env

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet)
      chain_discriminant_for_env_config testnet "$config"
      return 0
      ;;
    production)
      chain_discriminant_for_env_config production "$config"
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

  iroha_cli --config "$config" --output-format text tools address convert \
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
  local torii_base encoded_account http_code public_env

  soraswap_validate_torii_read_max_time || return 1
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ "$public_env" == "production" ]]; then
    account_readback_matches_exact_id "$config" "$account_id"
    return $?
  fi
  if iroha_cli_json --config "$config" ledger account get --id "$account_id" >/dev/null 2>&1; then
    return 0
  fi

  torii_base="$(torii_base_from_config "$config")"
  encoded_account="$(uri_encode "$account_id")"
  http_code="$(soraswap_curl_for_config "$config" -sS -o /dev/null -w '%{http_code}' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    "$torii_base/v1/accounts/${encoded_account}" || true)"
  [[ "$http_code" == "200" ]]
}

exact_account_readback_json() {
  local config="$1"
  local account_id="$2"
  local response

  if ! response="$(iroha_cli_json --config "$config" ledger account get --id "$account_id" 2>/dev/null)" \
    || ! jq -e . >/dev/null 2>&1 <<<"$response"; then
    jq -cn --arg requested_id "$account_id" '{
      requested_id: $requested_id,
      query_available: false,
      observed_ids: [],
      matched: false
    }'
    return 0
  fi

  jq -c --arg requested_id "$account_id" '
    def known_ids:
      [
        .id?,
        .account_id?,
        .account?.id?,
        .result?.id?,
        .result?.account_id?,
        .result?.account?.id?,
        .data?.id?,
        .data?.account_id?,
        .data?.account?.id?
      ] | map(select(type == "string" and length > 0));
    known_ids as $observed
    | {
        requested_id: $requested_id,
        query_available: true,
        observed_ids: $observed,
        matched: (($observed | length) > 0 and all($observed[]; . == $requested_id))
      }
  ' <<<"$response"
}

account_readback_matches_exact_id() {
  local readback

  readback="$(exact_account_readback_json "$1" "$2")" || return 1
  jq -e '.query_available == true and .matched == true' >/dev/null <<<"$readback"
}

wait_for_account_exists() {
  local config="$1"
  local account_id="$2"
  local attempts="${3:-15}"
  local sleep_seconds="${4:-1}"
  local attempt=1

  soraswap_validate_poll_window "account existence wait" "$attempts" "$sleep_seconds" || return 1

  while (( attempt <= attempts )); do
    if account_exists "$config" "$account_id"; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  return 1
}

contract_deploy_nonce_for_authority() {
  local config="$1"
  local authority="$2"
  local response value

  response="$(iroha_cli_json_with_config_timeout \
    "$config" \
    "$SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS" \
    ledger account meta get \
    --id "$authority" \
    --key contract_deploy_nonce 2>/dev/null)" || return 1
  value="$(jq -r '
    if type == "number" then
      tostring
    elif type == "string" then
      .
    elif type == "object" then
      (.value // .Value // .json // empty | tostring)
    else
      empty
    end
  ' <<<"$response" 2>/dev/null || true)"
  if [[ "$value" =~ '^[0-9]+$' ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  return 1
}

wait_for_contract_deploy_nonce_at_least() {
  local config="$1"
  local expected_nonce="$2"
  local attempts="${3:-30}"
  local sleep_seconds="${4:-1}"
  local authority nonce attempt=1

  soraswap_validate_poll_window "contract deploy nonce wait" "$attempts" "$sleep_seconds" || return 1
  authority="$(authority_from_config "$config" 2>/dev/null || true)"
  if [[ -z "$authority" ]]; then
    ensure_authority "$config"
    authority="$SORASWAP_AUTHORITY"
  fi

  while (( attempt <= attempts )); do
    if nonce="$(contract_deploy_nonce_for_authority "$config" "$authority" 2>/dev/null)" \
      && (( nonce >= expected_nonce )); then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract deploy nonce for $authority did not reach $expected_nonce after ${attempts}s" >&2
  return 1
}

ensure_contract_deploy_nonce_after_bundle() {
  local config="$1"
  local receipt_json="$2"
  local authority max_nonce expected_nonce current_nonce

  max_nonce="$(jq -r '[.contracts[]?.deploy_nonce // empty | select(type == "number")] | max // empty' <<<"$receipt_json")"
  if [[ -z "$max_nonce" || "$max_nonce" == "null" || "$max_nonce" != <-> ]]; then
    return 0
  fi

  expected_nonce=$(( max_nonce + 1 ))
  authority="$(authority_from_config "$config" 2>/dev/null || true)"
  if [[ -z "$authority" ]]; then
    ensure_authority "$config"
    authority="$SORASWAP_AUTHORITY"
  fi

  if current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority" 2>/dev/null)" \
    && [[ "$current_nonce" == <-> ]] \
    && (( current_nonce >= expected_nonce )); then
    return 0
  fi

  jq -cn --argjson expected_nonce "$expected_nonce" '$expected_nonce' \
    | iroha_cli_with_gas_metadata "$config" ledger account meta set \
        --id "$authority" \
        --key contract_deploy_nonce >/dev/null || {
          echo "failed to repair contract deploy nonce for $authority to $expected_nonce" >&2
          return 1
        }

  wait_for_contract_deploy_nonce_at_least \
    "$config" \
    "$expected_nonce" \
    "${SORASWAP_CONTRACT_APP_NONCE_REPAIR_WAIT_SECS:-60}" \
    1
}

ensure_account_registered() {
  local config="$1"
  local account_id="$2"
  local domain="$3"
  local max_attempts retry_delay attempt output output_status public_env

  if account_exists "$config" "$account_id"; then
    echo "account already present: $account_id"
    return 0
  fi

  max_attempts="${SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS:-6}"
  retry_delay="${SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS" "$retry_delay" || return 1

  echo "register account: $account_id -> $domain"
  attempt=1
  while (( attempt <= max_attempts )); do
    public_env="${SORASWAP_PUBLIC_ENV:-}"
    case "$public_env" in
      testnet|production)
        soraswap_require_public_submit_health_ready_for_config \
          "$config" \
          "account register $account_id" || return 75
        ;;
    esac

    output_status=0
    if output="$(
      iroha_cli_with_gas_metadata "$config" ledger account register \
        --id "$account_id" 2>&1
    )"; then
      printf '%s\n' "$(soraswap_redact_sensitive_text "$output")"
      return 0
    else
      output_status="$?"
      case "$output_status" in
        124|137|142|143)
          output="${output:-ledger account register timed out after ${SORASWAP_LEDGER_COMMAND_TIMEOUT_SECS:-180}s}"
          ;;
      esac
    fi

    if account_exists "$config" "$account_id"; then
      echo "account already present after register response failure: $account_id"
      return 0
    fi

    if soraswap_ledger_submit_error_retryable "$output" && (( attempt < max_attempts )); then
      echo "account register submit failed transiently for $account_id; retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    echo "failed to register account: $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
    return 1
  done

  echo "failed to register account after $max_attempts attempts: $account_id" >&2
  return 1
}

soraswap_ledger_submit_error_retryable() {
  local output="$1"

  soraswap_public_transport_error_needs_health_gate "$output" && return 0
  return 1
}

soraswap_public_transport_error_needs_health_gate() {
  local output="${1:-}"

  [[ -n "$output" ]] || return 1
  [[ "$output" == *"502 Bad Gateway"* ]] && return 0
  [[ "$output" == *"503 Service Unavailable"* ]] && return 0
  [[ "$output" == *"504 Gateway Timeout"* ]] && return 0
  [[ "$output" == *"HTTP 502"* ]] && return 0
  [[ "$output" == *"HTTP 503"* ]] && return 0
  [[ "$output" == *"HTTP 504"* ]] && return 0
  [[ "$output" == *"status: 502"* ]] && return 0
  [[ "$output" == *"status: 503"* ]] && return 0
  [[ "$output" == *"status: 504"* ]] && return 0
  [[ "$output" == *"Can't assign requested address"* ]] && return 0
  [[ "$output" == *"EADDRNOTAVAIL"* ]] && return 0
  [[ "$output" == *"bind failed with errno 49"* ]] && return 0
  [[ "$output" == *"no live upstreams"* ]] && return 0
  [[ "$output" == *"No live upstreams"* ]] && return 0
  [[ "$output" == *"Failed to connect"* ]] && return 0
  [[ "$output" == *"Connection refused"* ]] && return 0
  [[ "$output" == *"connection reset"* ]] && return 0
  [[ "$output" == *"Connection reset"* ]] && return 0
  [[ "$output" == *"operation timed out"* ]] && return 0
  [[ "$output" == *"Operation timed out"* ]] && return 0
  [[ "$output" == *"request timed out"* ]] && return 0
  [[ "$output" == *"deadline has elapsed"* ]] && return 0
  return 1
}

soraswap_stop_if_public_transport_health_degraded() {
  local config="$1"
  local label="${2:-public transport}"
  local output="${3:-}"
  local public_env health_status

  soraswap_public_transport_error_needs_health_gate "$output" || return 0
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  case "$public_env" in
    testnet|production) ;;
    *) return 0 ;;
  esac
  health_status=0
  soraswap_require_public_write_health_ready "$public_env" "$config" "$label" || health_status=$?
  if (( health_status != 0 )); then
    return "$health_status"
  fi
  return 0
}

read_norito_error_message() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    return 1
  fi

  if jq -er '
    if type == "object" then
      (.code // .error.code // empty) as $code
      | (.message // .error.message // empty) as $message
      | if $code != "" and $message != "" then "\($code): \($message)"
        elif $message != "" then $message
        elif $code != "" then $code
        else empty
        end
    else empty
    end
  ' "$file_path" 2>/dev/null; then
    return 0
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

norito_error_summary_from_text() {
  local text="$1"
  jq -er '
    if type == "object" then
      (.code // .error.code // empty) as $code
      | (.message // .error.message // empty) as $message
      | if $code != "" and $message != "" then "\($code): \($message)"
        elif $message != "" then $message
        elif $code != "" then $code
        else empty
        end
    else empty
    end
  ' <<<"$text" 2>/dev/null || true
}

norito_error_code_from_text() {
  local text="$1"
  jq -er '
    if type == "object" then
      (.code // .error.code // empty)
    else empty
    end
  ' <<<"$text" 2>/dev/null || true
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
  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-onboard-response.XXXXXX")"
  http_code="$(soraswap_curl_for_config "$config" -sS -o "$tmp" -w '%{http_code}' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -H 'Accept: application/json' \
    -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
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

public_onboard_alias_for_account() {
  local account_id="$1"
  local digest

  digest="$(printf '%s' "$account_id" | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
  printf 'soraswap-%s\n' "$digest"
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
  tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-faucet-puzzle.XXXXXX")"
  http_code="$(soraswap_curl_for_config "$config" -sS -o "$tmp" -w '%{http_code}' \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -H 'Accept: application/json' \
    -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
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

  soraswap_validate_poll_window "positive asset balance wait" "$attempts" "$sleep_seconds" || return 1

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

  soraswap_validate_poll_window "positive asset id balance wait" "$attempts" "$sleep_seconds" || return 1

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
  local record_path contract_key nonce max_nonce=-1
  local -A expected_contract_key_map

  for contract_key in "${(@f)$(expected_contract_ids)}"; do
    expected_contract_key_map[$contract_key]=1
  done

  for record_path in "$SORASWAP_ROOT/deployments/${env}"/*.deploy.json(N); do
    if [[ "${record_path:t}" == "soraswap.bundle.deploy.json" \
      || "${record_path:t}" == "soraswap.foundation.bundle.deploy.json" ]]; then
      continue
    fi

    contract_key="$(jq -r '.contract_key // empty' "$record_path" 2>/dev/null || true)"
    [[ -n "$contract_key" ]] || continue
    [[ -n "${expected_contract_key_map[$contract_key]:-}" ]] || continue
    jq -e '((.generated_at // "") | type == "string") and ((.generated_at // "") != "")' "$record_path" >/dev/null || continue
    deployment_record_matches_current_chain "$record_path" "$fingerprint_json" "$env" || continue
    deployment_record_matches_current_evidence "$record_path" "$env" "$contract_key" || continue

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
      soraswap_curl_for_config "$config" -fsS \
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

asset_value_from_account_assets_json() {
  local assets_json="$1"
  local asset_id="$2"

  jq -r \
    --arg asset_id "$asset_id" \
    '
      (.items // [])
      | map(select((.asset // "") == $asset_id))
      | if length == 0 then "0" else (.[0].quantity // "0") end
    ' <<<"$assets_json"
}

positive_asset_balances_from_account_assets_json() {
  local assets_json="$1"

  jq -c '
    (.items // [])
    | map(select(((.quantity | tonumber?) // 0) > 0))
    | map({
        asset: (.asset // ""),
        asset_alias: (.asset_alias // ""),
        asset_name: (.asset_name // ""),
        quantity: (.quantity // "0")
      })
  ' <<<"$assets_json"
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

  positive_asset_balances_from_account_assets_json "$response"
}

claim_public_testnet_faucet() {
  local config="$1"
  local account_id="$2"
  local torii_base puzzle_json nonce_hex payload_json response http_code body tx_hash error_code error_summary
  local attempt=1
  local max_attempts="${SORASWAP_PUBLIC_FAUCET_CLAIM_ATTEMPTS:-3}"

  soraswap_require_positive_integer_setting "SORASWAP_PUBLIC_FAUCET_CLAIM_ATTEMPTS" "$max_attempts" || return 1

  torii_base="$(torii_base_from_config "$config")"
  while (( attempt <= max_attempts )); do
    puzzle_json="$(fetch_public_faucet_puzzle_json "$config")" || return 1
    nonce_hex="$(solve_public_faucet_nonce_hex "$account_id" "$puzzle_json")"
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

    response="$(soraswap_curl_for_config "$config" -sS \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
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
      error_code="$(norito_error_code_from_text "$body")"
      error_summary="$(norito_error_summary_from_text "$body")"
      case "$error_code:$error_summary:$body" in
        *faucet_pow_anchor_stale*|*"faucet pow anchor is stale"*|*faucet_pow_solution_invalid*|*"invalid faucet pow solution"*)
          if (( attempt < max_attempts )); then
            echo "faucet claim puzzle expired or lost the PoW race for $account_id; retrying with a fresh puzzle (${attempt}/${max_attempts})" >&2
            sleep 1
            attempt=$(( attempt + 1 ))
            continue
          fi
          ;;
      esac
      if [[ -n "$error_summary" ]]; then
        echo "faucet claim failed for $account_id: HTTP $http_code: $error_summary" >&2
      else
        echo "faucet claim failed for $account_id: HTTP $http_code: $(soraswap_redact_sensitive_text "$body")" >&2
      fi
      return 1
    fi

    tx_hash="$(jq -r '.tx_hash_hex // empty' <<<"$body")"
    if [[ -n "$tx_hash" ]]; then
      local pipeline_json pipeline_kind
      if pipeline_json="$(wait_for_transaction_terminal_status "$config" "$tx_hash" 90 1 auto)"; then
        pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_json")"
        case "$pipeline_kind" in
          Applied|Committed)
            printf '%s\n' "$body"
            return 0
            ;;
          Expired)
            if (( attempt < max_attempts )); then
              echo "faucet claim expired for $account_id; retrying with a fresh puzzle (${attempt}/${max_attempts})" >&2
              sleep 1
              attempt=$(( attempt + 1 ))
              continue
            fi
            ;;
        esac
        echo "faucet claim transaction did not commit cleanly: $pipeline_json" >&2
        return 1
      fi
    fi

    printf '%s\n' "$body"
    return 0
  done
}

warn_if_public_tx_gossip_cap_low() {
  local config="$1"
  local torii_base frame_cap

  soraswap_validate_torii_read_max_time || return 1
  soraswap_require_positive_integer_setting "SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP" "$SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP" || return 1
  torii_base="$(torii_base_from_config "$config")"
  frame_cap="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/status" 2>/dev/null | jq -r '.tx_gossip.caps.frame_cap_bytes // 0' 2>/dev/null || true)"
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

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")"
  while (( attempt <= 3 )); do
    http_status="$(soraswap_curl_for_config "$config" -sS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" -o /dev/null -w '%{http_code}' \
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
  local torii_base response attempt=1 fallback_id

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")"
  while (( attempt <= 3 )); do
    if response="$(soraswap_curl_for_config "$config" -fsS --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" "$torii_base/v1/assets/definitions/$(uri_encode "$alias")" 2>/dev/null)"; then
      jq -r '.id' <<<"$response"
      return 0
    fi
    sleep 1
    attempt=$(( attempt + 1 ))
  done

  fallback_id="$(asset_definition_id_fallback_for_alias "$config" "$alias" 2>/dev/null || true)"
  if [[ -n "$fallback_id" ]]; then
    printf '%s\n' "$fallback_id"
    return 0
  fi

  return 1
}

asset_definition_id_fallback_for_alias() {
  local config="$1"
  local alias="$2"
  local public_env local_fee_id

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ -z "$public_env" && -n "$SORASWAP_LOCAL_FEE_ASSET_LABEL" && "$alias" == "$SORASWAP_LOCAL_FEE_ASSET_LABEL" ]]; then
    local_fee_id="$(localnet_fee_asset_definition_id_for_config "$config" 2>/dev/null || true)"
    if [[ -n "$local_fee_id" ]]; then
      printf '%s\n' "$local_fee_id"
      return 0
    fi
    if [[ -n "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID" ]]; then
      printf '%s\n' "$SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID"
      return 0
    fi
  fi

  case "$alias" in
    "$SORASWAP_BASE_ASSET_ALIAS"|"$SORASWAP_FEE_ASSET_ALIAS"|xor#universal)
      [[ -n "$SORASWAP_XOR_ASSET_DEFINITION_ID" ]] || return 1
      printf '%s\n' "$SORASWAP_XOR_ASSET_DEFINITION_ID"
      ;;
    usdt#soraswap.universal)
      [[ -n "$SORASWAP_USDT_ASSET_DEFINITION_ID" ]] || return 1
      printf '%s\n' "$SORASWAP_USDT_ASSET_DEFINITION_ID"
      ;;
    usdc#soraswap.universal)
      [[ -n "$SORASWAP_USDC_ASSET_DEFINITION_ID" ]] || return 1
      printf '%s\n' "$SORASWAP_USDC_ASSET_DEFINITION_ID"
      ;;
    kusd#soraswap.universal)
      [[ -n "$SORASWAP_KUSD_ASSET_DEFINITION_ID" ]] || return 1
      printf '%s\n' "$SORASWAP_KUSD_ASSET_DEFINITION_ID"
      ;;
    n3x#soraswap.universal)
      [[ -n "$SORASWAP_N3X_ASSET_DEFINITION_ID" ]] || return 1
      printf '%s\n' "$SORASWAP_N3X_ASSET_DEFINITION_ID"
      ;;
    *)
      return 1
      ;;
  esac
}

public_asset_definition_id_fallback_for_alias() {
  public_env_for_config "$1" >/dev/null 2>&1 || return 1
  asset_definition_id_fallback_for_alias "$@"
}

asset_definition_id_exists() {
  local config="$1"
  local asset_id="$2"

  iroha_cli_json --config "$config" ledger asset definition get --id "$asset_id" >/dev/null 2>&1
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

  existing_id="$(asset_definition_id_fallback_for_alias "$config" "$alias" 2>/dev/null || true)"
  if [[ "$existing_id" == "$asset_id" ]] && asset_definition_id_exists "$config" "$asset_id"; then
    echo "asset definition id already present for configured alias fallback: $alias -> $asset_id"
    return 0
  fi

  echo "register asset definition alias: $alias -> $asset_id"
  if output="$(
    iroha_cli_with_gas_metadata "$config" ledger asset definition register \
      --id "$asset_id" \
      --name "$name" \
      --alias "$alias" \
      --scale "$scale" 2>&1
  )"; then
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")"
    return 0
  fi

  if [[ "$output" == *"Repeated instruction"* || "$output" == *"Repetition of \`Register\`"* ]]; then
    existing_id="$(asset_definition_id_for_alias "$config" "$alias" 2>/dev/null || true)"
    if [[ "$existing_id" == "$asset_id" ]]; then
      echo "asset definition alias already present after duplicate register rejection: $alias -> $existing_id"
      return 0
    fi
  fi

  printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
  return 1
}

public_helper_asset_bootstrap_needed() {
  local config="$1"
  local domain_id="soraswap.universal"
  local alias

  public_env_for_config "$config" >/dev/null 2>&1 || return 1

  if ! iroha_cli_json --config "$config" ledger domain get --id "$domain_id" >/dev/null 2>&1; then
    return 0
  fi

  for alias in \
    usdt#soraswap.universal \
    usdc#soraswap.universal \
    kusd#soraswap.universal \
    n3x#soraswap.universal; do
    if ! asset_definition_alias_exists "$config" "$alias"; then
      return 0
    fi
  done

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
      soraswap_curl_for_config "$config" -fsS \
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
  local current asset_id

  current="$(asset_value_for_account_query "$config" asset "$alias" "$account")"
  if numeric_gt_zero "$current"; then
    printf '%s\n' "$current"
    return 0
  fi

  asset_id="$(asset_definition_id_for_alias "$config" "$alias" 2>/dev/null || true)"
  if [[ -n "$asset_id" ]]; then
    asset_value_for_account_id "$config" "$asset_id" "$account"
    return 0
  fi

  printf '%s\n' "$current"
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

  soraswap_validate_poll_window "asset balance wait" "$attempts" "$sleep_seconds" || return 1

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
  local current delta asset_id

  asset_id="$(asset_definition_id_for_alias "$config" "$alias" 2>/dev/null || true)"
  if [[ -n "$asset_id" ]]; then
    current="$(asset_value_for_account_id "$config" "$asset_id" "$account")"
  else
    current="$(asset_value_for_account "$config" "$alias" "$account")"
  fi
  if (( current >= minimum )); then
    echo "asset balance already sufficient: $alias -> $current"
    return 0
  fi

  delta=$(( minimum - current ))
  echo "mint asset balance: $alias +$delta -> $account"
  if [[ -n "$asset_id" ]]; then
    iroha_cli_with_gas_metadata "$config" ledger asset mint \
      --definition "$asset_id" \
      --account "$account" \
      --quantity "$delta"
  else
    iroha_cli_with_gas_metadata "$config" ledger asset mint \
      --definition-alias "$alias" \
      --account "$account" \
      --quantity "$delta"
  fi
}

contract_manifest_json_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local torii_base

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")"
  soraswap_curl_for_config "$config" -fsS \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -H 'Accept: application/json' \
    "$torii_base/v1/contracts/code/$(uri_encode "$code_hash_hex")"
}

contract_code_bytes_http_status_by_code_hash() {
  local config="$1"
  local code_hash_hex="$2"
  local torii_base http_code attempt retry_delay

  soraswap_validate_torii_read_max_time || return 1
  soraswap_validate_torii_read_retry_settings || return 1
  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"
  attempt=1
  retry_delay="$SORASWAP_TORII_READ_RETRY_DELAY_SECS"
  while (( attempt <= SORASWAP_TORII_READ_RETRY_COUNT )); do
    http_code="$(
      soraswap_curl_for_config "$config" -sS \
        -o /dev/null \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        -H 'Accept: application/octet-stream' \
        -w '%{http_code}' \
        "$torii_base/v1/contracts/code-bytes/$(uri_encode "$code_hash_hex")" 2>/dev/null || true
    )"
    if ! soraswap_torii_read_retryable_http_code "$http_code" \
      || (( attempt >= SORASWAP_TORII_READ_RETRY_COUNT )); then
      printf '%s\n' "$http_code"
      return 0
    fi
    sleep "$retry_delay"
    attempt=$(( attempt + 1 ))
  done

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

  soraswap_validate_poll_window "contract code-bytes wait" "$attempts" "$sleep_seconds" || return 1
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

  soraswap_validate_poll_window "contract manifest wait" "$attempts" "$sleep_seconds" || return 1
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
  local creation_time_ms="${6:-}"
  local torii_base authority private_key_file gas_asset_id request response http_code body redacted_body attempt=1 retry_count retry_delay max_time_secs transaction_ttl_ms
  local request_build_status
  local curl_args=()

  retry_count="${SORASWAP_CONTRACT_CALL_RETRY_COUNT:-1}"
  retry_delay="${SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS:-2}"
  max_time_secs="${SORASWAP_CONTRACT_CALL_MAX_TIME_SECS:-120}"
  transaction_ttl_ms="$(soraswap_contract_call_transaction_ttl_ms_for_config "$config")" || return 1
  soraswap_require_positive_integer_setting "contract call gas limit" "$gas_limit" || return 1
  soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_CALL_RETRY_COUNT" "$retry_count" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS" "$retry_delay" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_CALL_MAX_TIME_SECS" "$max_time_secs" || return 1
  if [[ -z "$creation_time_ms" ]]; then
    creation_time_ms="$(soraswap_next_contract_call_creation_time_ms)" || return 1
  fi
  soraswap_require_nonnegative_integer_setting "contract call creation_time_ms" "$creation_time_ms" || return 1

  authority="$(authority_from_config "$config" 2>/dev/null || true)"
  if [[ -z "$authority" ]]; then
    ensure_authority "$config"
    authority="$SORASWAP_AUTHORITY"
  fi
  torii_base="$(torii_base_from_config "$config")"
  private_key_file="$(soraswap_config_private_key_temp_file "$config" contract-call-key)" || return 1
  gas_asset_id="$(gas_metadata_asset_id_for_config "$config")"

  if is_contract_address_literal "$contract_id"; then
    {
      if request="$(jq -cn \
        --arg authority "$authority" \
        --rawfile private_key "$private_key_file" \
        --arg contract_address "$contract_id" \
        --arg entrypoint "$entrypoint" \
        --arg gas_asset_id "$gas_asset_id" \
        --argjson gas_limit "$gas_limit" \
        --argjson creation_time_ms "$creation_time_ms" \
        --argjson transaction_ttl_ms "$transaction_ttl_ms" \
        --argjson payload "$payload_json" \
        '($private_key | rtrimstr("\n") | rtrimstr("\r")) as $private_key_value
        | {
          authority: $authority,
          private_key: $private_key_value,
          contract_address: $contract_address,
          entrypoint: $entrypoint,
          gas_asset_id: $gas_asset_id,
          gas_limit: $gas_limit,
          creation_time_ms: $creation_time_ms
        }
        + (if $transaction_ttl_ms > 0 then {transaction_ttl_ms: $transaction_ttl_ms} else {} end)
        + (if $payload == null then {} else {payload: $payload} end)')"; then
        request_build_status=0
      else
        request_build_status=$?
      fi
    } always {
      if ! soraswap_secure_unlink_owned_file "$private_key_file"; then
        request_build_status=1
      fi
    }
    (( request_build_status == 0 )) || return "$request_build_status"
  else
    soraswap_secure_unlink_owned_file "$private_key_file" || true
    echo "contract call requires a canonical contract address, got: $contract_id" >&2
    return 1
  fi

  curl_args=(
    -sS
    -H 'Content-Type: application/json'
    -H 'Accept: application/json'
    -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION"
    -w $'\n%{http_code}'
    -X POST
    --max-time "$max_time_secs"
    "$torii_base/v1/contracts/call"
    --data-binary @-
  )
  while (( attempt <= retry_count )); do
    if ! response="$(
      printf '%s' "$request" \
        | SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION="${SORASWAP_IMMEDIATE_SUBMIT_GATE_FUNCTION:-}" \
          SORASWAP_IMMEDIATE_CURL_GATE_LABEL="$contract_id.$entrypoint submit" \
            soraswap_curl_for_config "$config" "${curl_args[@]}" 2>&1
    )"; then
      redacted_body="$(soraswap_redact_sensitive_text "$response")"
      if soraswap_ledger_submit_error_retryable "$response" && (( attempt < retry_count )); then
        echo "contract call submit transport failed transiently for $contract_id.$entrypoint; retrying same creation_time_ms=$creation_time_ms ($attempt/$retry_count): $redacted_body" >&2
        sleep "$retry_delay"
        attempt=$(( attempt + 1 ))
        continue
      fi
      echo "failed to reach $torii_base/v1/contracts/call for $contract_id.$entrypoint: $redacted_body" >&2
      return 1
    fi

    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [[ "$http_code" == "200" ]]; then
      if soraswap_ledger_submit_error_retryable "$body" && (( attempt < retry_count )); then
        redacted_body="$(soraswap_redact_sensitive_text "$body")"
        echo "contract call submit returned transient response for $contract_id.$entrypoint; retrying same creation_time_ms=$creation_time_ms ($attempt/$retry_count): $redacted_body" >&2
        sleep "$retry_delay"
        attempt=$(( attempt + 1 ))
        continue
      fi
      printf '%s\n' "$body"
      return 0
    fi

    redacted_body="$(soraswap_redact_sensitive_text "$body")"
    if soraswap_ledger_submit_error_retryable "HTTP $http_code $body" && (( attempt < retry_count )); then
      echo "contract call request failed transiently for $contract_id.$entrypoint; retrying same creation_time_ms=$creation_time_ms ($attempt/$retry_count): HTTP $http_code: $redacted_body" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi
    echo "contract call request failed for $contract_id.$entrypoint: HTTP $http_code: $redacted_body" >&2
    return 1
  done

  echo "contract call request failed for $contract_id.$entrypoint after $retry_count attempts" >&2
  return 1
}

submit_contract_view() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local gas_limit="${4:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local payload_json="${5:-null}"
  local torii_base authority request response http_code body redacted_body curl_args attempt=1 max_attempts retry_delay max_time_secs
  local allowed_http_codes

  max_attempts="$SORASWAP_TORII_READ_RETRY_COUNT"
  retry_delay="$SORASWAP_TORII_READ_RETRY_DELAY_SECS"
  max_time_secs="${SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS:-30}"
  soraswap_require_positive_integer_setting "contract view gas limit" "$gas_limit" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS" "$max_time_secs" || return 1
  soraswap_validate_torii_read_retry_settings || return 1

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

  curl_args=(
    -sS
    --connect-timeout 10
    --max-time "$max_time_secs"
    -H 'Content-Type: application/json'
    -H 'Accept: application/json'
    -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION"
    -w $'\n%{http_code}'
    -X POST
  )
  curl_args+=(
    "$torii_base/v1/contracts/view"
    -d "$request"
  )
  allowed_http_codes=" ${${SORASWAP_CONTRACT_VIEW_ALLOWED_HTTP_CODES:-200}//,/ } "

  while (( attempt <= max_attempts )); do
    if response="$(soraswap_curl_for_config "$config" "${curl_args[@]}")"; then
      http_code="${response##*$'\n'}"
      body="${response%$'\n'*}"

      if [[ "$allowed_http_codes" == *" $http_code "* ]]; then
        printf '%s\n' "$body"
        return 0
      fi

      if soraswap_torii_read_retryable_http_code "$http_code" && (( attempt < max_attempts )); then
        sleep "$retry_delay"
        attempt=$(( attempt + 1 ))
        continue
      fi

      redacted_body="$(soraswap_redact_sensitive_text "$body")"
      echo "contract view request failed for $contract_id.$entrypoint: HTTP $http_code: $redacted_body" >&2
      return 1
    fi
    if (( attempt == max_attempts )); then
      echo "failed to reach $torii_base/v1/contracts/view for $contract_id.$entrypoint" >&2
      return 1
    fi
    sleep "$retry_delay"
    attempt=$(( attempt + 1 ))
  done

  echo "failed to reach $torii_base/v1/contracts/view for $contract_id.$entrypoint" >&2
  return 1
}

submit_contract_view_expect() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local gas_limit="${4:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local payload_json="${5:-null}"
  local expect_jq="${6:-.ok == true}"
  local context="${7:-$contract_id.$entrypoint view expectation}"
  local attempts="${8:-$SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT}"
  local sleep_seconds="${9:-$SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS}"
  local attempt=1 response latest_response=""

  soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT" "$attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS" "$sleep_seconds" || return 1

  while (( attempt <= attempts )); do
    if response="$(submit_contract_view "$config" "$contract_id" "$entrypoint" "$gas_limit" "$payload_json")"; then
      latest_response="$response"
      if jq -e "$expect_jq" >/dev/null 2>&1 <<<"$response"; then
        printf '%s\n' "$response"
        return 0
      fi
    else
      latest_response="$response"
    fi

    if (( attempt < attempts )); then
      sleep "$sleep_seconds"
    fi
    attempt=$(( attempt + 1 ))
  done

  echo "contract view expectation was not met for $context after $attempts attempt(s)" >&2
  if [[ -n "$latest_response" ]]; then
    echo "latest $context response: $(soraswap_redact_sensitive_text "$latest_response")" >&2
  fi
  return 1
}

contract_deploy_http_error_retryable() {
  local http_code="$1"
  local body="$2"

  [[ "$http_code" == "400" ]] || return 1
  jq -e '
    (.code // "") == "queue_unresolved_route"
    or (.details.reject_code // "") == "PRTRY:ROUTE_UNRESOLVED"
  ' <<<"$body" >/dev/null 2>&1
}

submit_contract_deploy_file() {
  local config="$1"
  local code_file="$2"
  local contract_alias="$3"
  local torii_base private_key_file code_b64 request response http_code body redacted_body curl_args max_time_secs
  local attempt max_attempts retry_delay transaction_ttl_ms health_status request_build_status

  max_attempts="${SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_ATTEMPTS:-5}"
  retry_delay="${SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_DELAY_SECS:-3}"
  max_time_secs="${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-45}"
  transaction_ttl_ms="${SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS:-${SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS:-900000}}"
  soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_DELAY_SECS" "$retry_delay" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS" "$max_time_secs" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS" "$transaction_ttl_ms" || return 1

  ensure_authority "$config"
  torii_base="$(torii_base_from_config "$config")"
  private_key_file="$(soraswap_config_private_key_temp_file "$config" contract-deploy-key)" || return 1
  code_b64="$(base64 < "$code_file" | tr -d '\r\n')"

  {
    if request="$(jq -cn \
      --arg authority "$SORASWAP_AUTHORITY" \
      --rawfile private_key "$private_key_file" \
      --arg code_b64 "$code_b64" \
      --arg contract_alias "$contract_alias" \
      --argjson transaction_ttl_ms "$transaction_ttl_ms" \
      '($private_key | rtrimstr("\n") | rtrimstr("\r")) as $private_key_value
      | {
        authority: $authority,
        private_key: $private_key_value,
        code_b64: $code_b64,
        contract_alias: $contract_alias
      }
      + (if $transaction_ttl_ms > 0 then {transaction_ttl_ms: $transaction_ttl_ms} else {} end)')"; then
      request_build_status=0
    else
      request_build_status=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_file "$private_key_file"; then
      request_build_status=1
    fi
  }
  (( request_build_status == 0 )) || return "$request_build_status"

  curl_args=(
    -sS
    -H 'Content-Type: application/json'
    -H 'Accept: application/json'
    -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION"
    -w $'\n%{http_code}'
    -X POST
  )
  curl_args+=(--max-time "$max_time_secs")
  curl_args+=(
    "$torii_base/v1/contracts/deploy"
    --data-binary @-
  )

  attempt=1
  while (( attempt <= max_attempts )); do
    if ! response="$(printf '%s' "$request" | soraswap_curl_for_config "$config" "${curl_args[@]}")"; then
      health_status=0
      soraswap_stop_if_public_transport_health_degraded \
        "$config" \
        "contract deploy transport for $(soraswap_display_path "$code_file")" \
        "Failed to connect to $torii_base/v1/contracts/deploy" || health_status=$?
      if (( health_status != 0 )); then
        return "$health_status"
      fi
      if (( attempt == max_attempts )); then
        echo "failed to reach $torii_base/v1/contracts/deploy" >&2
        return 1
      fi
      echo "contract deploy request could not reach $torii_base/v1/contracts/deploy for $(soraswap_display_path "$code_file"); retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    http_code="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [[ "$http_code" == "200" ]]; then
      printf '%s\n' "$body"
      return 0
    fi

    health_status=0
    soraswap_stop_if_public_transport_health_degraded \
      "$config" \
      "contract deploy transport for $(soraswap_display_path "$code_file")" \
      "HTTP $http_code $body" || health_status=$?
    if (( health_status != 0 )); then
      return "$health_status"
    fi

    if contract_deploy_http_error_retryable "$http_code" "$body" && (( attempt < max_attempts )); then
      redacted_body="$(soraswap_redact_sensitive_text "$body")"
      echo "contract deploy route unresolved for $(soraswap_display_path "$code_file"); retrying ($attempt/$max_attempts): HTTP $http_code: $redacted_body" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    redacted_body="$(soraswap_redact_sensitive_text "$body")"
    echo "contract deploy request failed for $(soraswap_display_path "$code_file"): HTTP $http_code: $redacted_body" >&2
    return 1
  done

  echo "contract deploy request failed for $(soraswap_display_path "$code_file") after $max_attempts attempts" >&2
  return 1
}

normalize_contract_deploy_response_json() {
  local response_json="$1"

  jq -c '
    if (.ok == true and (.contract_address | type) == "string" and (.contract_address | length) > 0) then
      .
    elif (.ok == true and ((.contracts // []) | length) == 1) then
      . as $root
      | ($root.contracts[0] // {}) as $contract
      | ($root.operation_receipt // {}) as $receipt
      | {
          ok: true,
          contract_address: ($contract.contract_address // $receipt.contract_address // ""),
          contract_alias: ($contract.contract_alias // $receipt.contract_alias // $contract.name // ""),
          dataspace: ($contract.dataspace // $receipt.dataspace // "universal"),
          deploy_nonce: ($contract.deploy_nonce // 0),
          tx_hash_hex: ($contract.tx_hash_hex // $receipt.tx_hash_hex // ""),
          code_hash_hex: (($contract.code_hash_hex // $receipt.code_hash_hex // $receipt.payload_digest_hex // "") | ascii_downcase),
          abi_hash_hex: (($contract.abi_hash_hex // $receipt.abi_hash_hex // "") | ascii_downcase),
          status: ($contract.status // $receipt.status // ""),
          upgraded: ($contract.upgraded // false),
          previous_contract_address: ($contract.previous_contract_address // ""),
          pipeline_status: ($contract.pipeline_status // null),
          raw_response: $root
        }
      | if .pipeline_status == null then del(.pipeline_status) else . end
    else
      .
    end
  ' <<<"$response_json"
}

derive_contract_address_for_deploy() {
  local config="$1"
  local authority="$2"
  local deploy_nonce="$3"
  local dataspace="${4:-universal}"
  local env="${5:-testnet}"
  local chain_discriminant

  chain_discriminant="$(chain_discriminant_for_env_config "$env" "$config")"
  iroha_cli_json --config "$config" contract derive-address \
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

contract_view_report_result_json() {
  local response_json="${1:-}"
  local response_compact redacted_response raw_response
  local truncated_json="false"
  local max_chars="${SORASWAP_CONTRACT_VIEW_DIAGNOSTIC_MAX_CHARS:-4096}"

  if ! soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_VIEW_DIAGNOSTIC_MAX_CHARS" "$max_chars" >/dev/null 2>&1; then
    max_chars=4096
  fi

  if response_compact="$(jq -c . <<<"$response_json" 2>/dev/null)"; then
    jq -c '
      if .ok == true then
        .result
      else
        {
          status: "contract_view_failed",
          ok: (.ok // false),
          error: (.error // .message // .details // "contract view response did not succeed"),
          response: .
        }
      end
    ' <<<"$response_compact"
    return 0
  fi

  redacted_response="$(soraswap_redact_sensitive_text "$response_json")"
  raw_response="$redacted_response"
  if (( ${#raw_response} > max_chars )); then
    raw_response="${raw_response[1,$max_chars]}"
    truncated_json="true"
  fi
  jq -cn \
    --arg raw "$raw_response" \
    --argjson raw_truncated "$truncated_json" \
    '{
      status: "invalid_contract_view_json",
      ok: false,
      error: "contract view response was not valid JSON",
      raw: $raw,
      raw_truncated: $raw_truncated
    }'
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
  local liveness_error=""

  soraswap_validate_poll_window "contract instance liveness wait" "$attempts" "$sleep_seconds" || return 1
  while (( attempt <= attempts )); do
    if liveness_error="$(contract_instance_liveness_json "$config" "$contract_key" "$contract_address" 2>&1 >/dev/null)"; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "contract instance $contract_key at $contract_address did not answer its liveness probe after ${attempts}s" >&2
  if [[ -n "$liveness_error" ]]; then
    echo "last liveness probe error: $(soraswap_redact_sensitive_text "$liveness_error")" >&2
  fi
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

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")"
  response="$(soraswap_curl_for_config "$config" -sS \
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
      echo "failed to fetch pipeline status for $tx_hash: HTTP $http_code: $(soraswap_redact_sensitive_text "$body")" >&2
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

  soraswap_validate_poll_window "transaction commit wait" "$attempts" "$sleep_seconds" || return 1
  while (( attempt <= attempts )); do
    if committed_transaction_lookup_json "$config" "$tx_hash" \
      >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "transaction $tx_hash was not committed after ${attempts}s" >&2
  soraswap_print_public_write_health_wait_context "$config" "transaction $tx_hash commit wait"
  return 1
}

wait_for_transaction_terminal_status() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local scope="${5:-auto}"
  local queued_stall_max_ms="${6:-0}"
  local attempt=1
  local response kind latest_kind="" health_snapshot health_summary
  local start_ms deadline_ms now_ms health_status

  soraswap_validate_poll_window "transaction terminal wait" "$attempts" "$sleep_seconds" || return 1
  soraswap_require_nonnegative_integer_setting "transaction terminal queued-write stall threshold" "$queued_stall_max_ms" || return 1
  start_ms="$(soraswap_current_time_millis)" || return 1
  deadline_ms=$(( start_ms + attempts * 1000 ))
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
    if (( queued_stall_max_ms > 0 && attempt % 15 == 0 )); then
      health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
      if [[ -n "$health_snapshot" && "$health_snapshot" != "null" ]] \
        && soraswap_public_chain_queued_stall_detected "$health_snapshot" "$queued_stall_max_ms"; then
        health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
        if [[ -n "$health_summary" ]]; then
          echo "queued-write finality stall while waiting for transaction $tx_hash terminal status: $health_summary" >&2
        else
          echo "queued-write finality stall while waiting for transaction $tx_hash terminal status" >&2
        fi
        return 75
      fi
    fi
    now_ms="$(soraswap_current_time_millis)" || return 1
    if (( now_ms >= deadline_ms )); then
      break
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$latest_kind" ]]; then
    echo "transaction $tx_hash did not reach a terminal pipeline status within ${attempts}s (latest: $latest_kind)" >&2
  else
    echo "transaction $tx_hash did not expose pipeline status within ${attempts}s" >&2
  fi
  soraswap_require_public_write_health_ready_for_config "$config" "transaction $tx_hash terminal status wait" || {
    health_status=$?
    (( health_status == 75 )) && return 75
    return "$health_status"
  }
  soraswap_print_public_write_health_wait_context "$config" "transaction $tx_hash terminal status wait"
  return 1
}

wait_for_transaction_terminal_or_committed() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local scope="${5:-auto}"
  local committed_hash="${6:-$tx_hash}"
  local queued_stall_max_ms="${7:-0}"
  local attempt=1
  local response kind tx_result latest_kind="" health_snapshot health_summary
  local start_ms deadline_ms now_ms health_status

  soraswap_validate_poll_window "transaction terminal-or-committed wait" "$attempts" "$sleep_seconds" || return 1
  soraswap_require_nonnegative_integer_setting "transaction visibility queued-write stall threshold" "$queued_stall_max_ms" || return 1
  start_ms="$(soraswap_current_time_millis)" || return 1
  deadline_ms=$(( start_ms + attempts * 1000 ))
  while (( attempt <= attempts )); do
    if response="$(pipeline_transaction_status_json "$config" "$tx_hash" "$scope" 2>/dev/null)"; then
      kind="$(pipeline_status_kind_from_json "$response")"
      latest_kind="$kind"
      case "$kind" in
        Applied|Committed|Rejected|Expired)
          jq -cn --argjson status "$response" '{source:"pipeline", status:$status}'
          return 0
          ;;
      esac
    fi

    if tx_result="$(committed_transaction_result_json "$config" "$committed_hash" 2>/dev/null)"; then
      jq -cn --argjson transaction_result "$tx_result" '{source:"committed", transaction_result:$transaction_result}'
      return 0
    fi

    if (( queued_stall_max_ms > 0 && attempt % 15 == 0 )); then
      health_snapshot="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || true)"
      if [[ -n "$health_snapshot" && "$health_snapshot" != "null" ]] \
        && soraswap_public_chain_queued_stall_detected "$health_snapshot" "$queued_stall_max_ms"; then
        health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot" 2>/dev/null || true)"
        if [[ -n "$health_summary" ]]; then
          echo "queued-write finality stall while waiting for transaction $tx_hash visibility: $health_summary" >&2
        else
          echo "queued-write finality stall while waiting for transaction $tx_hash visibility" >&2
        fi
        return 75
      fi
    fi

    now_ms="$(soraswap_current_time_millis)" || return 1
    if (( now_ms >= deadline_ms )); then
      break
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$latest_kind" ]]; then
    echo "transaction $tx_hash did not reach a terminal pipeline status or committed lookup for $committed_hash within ${attempts}s (latest pipeline: $latest_kind)" >&2
  else
    echo "transaction $tx_hash did not expose pipeline status or committed lookup for $committed_hash within ${attempts}s" >&2
  fi
  soraswap_require_public_write_health_ready_for_config "$config" "transaction $tx_hash visibility wait" || {
    health_status=$?
    (( health_status == 75 )) && return 75
    return "$health_status"
  }
  soraswap_print_public_write_health_wait_context "$config" "transaction $tx_hash visibility wait"
  return 1
}

soraswap_contract_call_transaction_ttl_ms_for_config() {
  local config="$1"
  local transaction_ttl_ms="$SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS"

  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS" "$transaction_ttl_ms" || return 1
  if public_env_for_config "$config" >/dev/null 2>&1; then
    transaction_ttl_ms="${SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS:-$transaction_ttl_ms}"
    soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS" "$transaction_ttl_ms" || return 1
  fi

  printf '%s\n' "$transaction_ttl_ms"
}

soraswap_contract_call_tx_committed_wait_secs() {
  local config="$1"
  local wait_secs="$SORASWAP_TX_COMMITTED_WAIT_SECS"
  local public_wait_secs="${SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS:-}"

  soraswap_require_nonnegative_integer_setting "SORASWAP_TX_COMMITTED_WAIT_SECS" "$wait_secs" || return 1
  if public_env_for_config "$config" >/dev/null 2>&1; then
    if [[ -n "$public_wait_secs" ]]; then
      soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS" "$public_wait_secs" || return 1
      wait_secs="$public_wait_secs"
    elif (( wait_secs < 300 )); then
      wait_secs=300
    fi
  fi

  printf '%s\n' "$wait_secs"
}

soraswap_public_tx_wait_queued_stall_max_ms_for_config() {
  local config="$1"
  local max_ms=0

  if public_env_for_config "$config" >/dev/null 2>&1; then
    max_ms="$SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS"
    soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS" "$max_ms" || return 1
  fi

  printf '%s\n' "$max_ms"
}

accept_pipeline_applied_without_committed_tx() {
  local config="$1"
  local setting="${SORASWAP_ACCEPT_PIPELINE_APPLIED_WITHOUT_COMMITTED_TX:-auto}"
  local public_env

  case "$setting" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    0|false|FALSE|no|NO|off|OFF)
      return 1
      ;;
    auto|AUTO)
      ;;
    *)
      echo "SORASWAP_ACCEPT_PIPELINE_APPLIED_WITHOUT_COMMITTED_TX must be auto, 0, 1, true, false, yes, no, on, or off; got '$setting'" >&2
      return 2
      ;;
  esac

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ -n "$public_env" ]]
}

committed_transaction_json() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-60}"
  local sleep_seconds="${4:-1}"
  local attempt=1
  local response

  soraswap_validate_poll_window "committed transaction wait" "$attempts" "$sleep_seconds" || return 1
  while (( attempt <= attempts )); do
    if response="$(committed_transaction_lookup_json "$config" "$tx_hash" 2>/dev/null)"; then
      echo "$response"
      return 0
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "transaction $tx_hash was not committed after ${attempts}s" >&2
  return 1
}

committed_transaction_result_json() {
  local config="$1"
  local tx_hash="$2"
  local attempts="${3:-1}"
  local sleep_seconds="${4:-1}"
  local attempt=1
  local response tx_result

  soraswap_validate_poll_window "committed transaction result wait" "$attempts" "$sleep_seconds" || return 1
  while (( attempt <= attempts )); do
    if response="$(committed_transaction_lookup_json "$config" "$tx_hash" 2>/dev/null)"; then
      tx_result="$(jq -c '.result // empty' <<<"$response" 2>/dev/null || true)"
      if [[ -n "$tx_result" && "$tx_result" != "null" ]]; then
        printf '%s\n' "$tx_result"
        return 0
      fi
    fi
    sleep "$sleep_seconds"
    attempt=$(( attempt + 1 ))
  done

  echo "transaction $tx_hash result was not committed after ${attempts}s" >&2
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

assert_transaction_result_ok() {
  local tx_result_json="$1"
  local tx_hash="${2:-unknown}"
  local context="${3:-transaction}"
  local rejection

  if jq -e 'has("Ok")' <<<"$tx_result_json" >/dev/null; then
    return 0
  fi

  rejection="$(jq -c '.Err // .' <<<"$tx_result_json")"
  echo "$context failed for transaction $tx_hash: $rejection" >&2
  return 1
}

soraswap_record_contract_call_trace() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local tx_hash="$4"
  local committed_hash="$5"
  local submit_attempt="${6:-1}"
  local trace_file="${SORASWAP_CONTRACT_CALL_TRACE_FILE:-}"
  local trace_dir public_env torii_url trace_json

  [[ -n "$trace_file" ]] || return 0

  trace_dir="${trace_file:h}"
  if [[ -n "$trace_dir" && "$trace_dir" != "$trace_file" ]]; then
    mkdir -p "$trace_dir" 2>/dev/null || return 0
  fi

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  torii_url="$(torii_base_from_config "$config" 2>/dev/null || true)"
  trace_json="$(jq -cn \
    --arg generated_at "$(utc_timestamp)" \
    --arg environment "$public_env" \
    --arg torii_url "$torii_url" \
    --arg contract_id "$contract_id" \
    --arg entrypoint "$entrypoint" \
    --arg tx_hash "$tx_hash" \
    --arg committed_hash "$committed_hash" \
    --argjson submit_attempt "$submit_attempt" \
    '{
      generated_at: $generated_at,
      environment: $environment,
      torii_url: $torii_url,
      contract_id: $contract_id,
      entrypoint: $entrypoint,
      tx_hash_hex: $tx_hash,
      committed_lookup_hash_hex: $committed_hash,
      submit_attempt: $submit_attempt
    }'
  )" || return 0

  printf '%s\n' "$trace_json" >> "$trace_file" 2>/dev/null || true
}

call_contract_and_wait() {
  local config="$1"
  local contract_id="$2"
  local entrypoint="$3"
  local payload_json="${4:-null}"
  local gas_limit="${5:-$SORASWAP_SMOKE_GAS_LIMIT}"
  local response redacted_response tx_hash committed_hash terminal_json terminal_status terminal_source tx_result pipeline_json pipeline_kind pipeline_content
  local accept_setting_status invisible_retry_count submit_attempt tx_committed_wait_secs queued_stall_max_ms health_status
  local creation_time_ms
  local accept_pipeline_only=0 committed_verify_attempts

  creation_time_ms=""
  tx_committed_wait_secs="$(soraswap_contract_call_tx_committed_wait_secs "$config")" || return 1
  queued_stall_max_ms="$(soraswap_public_tx_wait_queued_stall_max_ms_for_config "$config")" || return 1
  committed_verify_attempts="$tx_committed_wait_secs"
  invisible_retry_count="${SORASWAP_CONTRACT_CALL_INVISIBLE_RETRY_COUNT:-}"
  if [[ -z "$invisible_retry_count" ]]; then
    if public_env_for_config "$config" >/dev/null 2>&1; then
      invisible_retry_count=1
    else
      invisible_retry_count=0
    fi
  fi
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_CALL_INVISIBLE_RETRY_COUNT" "$invisible_retry_count" || return 1

  submit_attempt=0
  while (( submit_attempt <= invisible_retry_count )); do
    submit_attempt=$(( submit_attempt + 1 ))
    soraswap_require_public_submit_health_ready_for_config \
      "$config" \
      "$contract_id.$entrypoint submit" || return $?
    if [[ -z "$creation_time_ms" ]]; then
      creation_time_ms="$(soraswap_next_contract_call_creation_time_ms)" || return 1
    fi
    if ! response="$(submit_contract_call "$config" "$contract_id" "$entrypoint" "$gas_limit" "$payload_json" "$creation_time_ms")"; then
      return 1
    fi
    if ! echo "$response" \
      | jq -e '.ok == true and .submitted == true and (.tx_hash_hex | type == "string") and (.tx_hash_hex | length > 0)' \
      >/dev/null; then
      redacted_response="$(soraswap_redact_sensitive_text "$response")"
      echo "$contract_id.$entrypoint did not return a submitted transaction hash: $redacted_response" >&2
      return 1
    fi
    tx_hash="$(echo "$response" | jq -r '.tx_hash_hex')"
    soraswap_invoke_accepted_submission_callback \
      "${SORASWAP_ACCEPTED_SUBMISSION_FUNCTION:-}" \
      "$config" \
      "$contract_id.$entrypoint accepted" \
      "$tx_hash" || return $?
    committed_hash="$(echo "$response" | jq -r '.entrypoint_hash_hex // .transaction_entrypoint_hash_hex // .entrypoint_hash // .tx_hash_hex')"
    soraswap_record_contract_call_trace "$config" "$contract_id" "$entrypoint" "$tx_hash" "$committed_hash" "$submit_attempt"
    if terminal_json="$(wait_for_transaction_terminal_or_committed "$config" "$tx_hash" "$tx_committed_wait_secs" 1 auto "$committed_hash" "$queued_stall_max_ms")"; then
      break
    else
      terminal_status=$?
    fi
    if (( terminal_status == 75 )); then
      return "$terminal_status"
    fi
    echo "$contract_id.$entrypoint did not expose transaction status for $tx_hash (committed lookup hash: $committed_hash)" >&2
    if (( submit_attempt > invisible_retry_count )); then
      return 1
    fi
    echo "$contract_id.$entrypoint retrying invisible public transaction submission ($submit_attempt/$invisible_retry_count)" >&2
  done

  terminal_source="$(jq -r '.source' <<<"$terminal_json")"
  case "$terminal_source" in
    pipeline)
      pipeline_json="$(jq -c '.status' <<<"$terminal_json")"
      pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_json")"
      case "$pipeline_kind" in
        Applied|Committed)
          if accept_pipeline_applied_without_committed_tx "$config"; then
            accept_pipeline_only=1
            committed_verify_attempts="$SORASWAP_PIPELINE_APPLIED_COMMITTED_VERIFY_SECS"
          else
            accept_setting_status=$?
            (( accept_setting_status == 1 )) || return 1
          fi
          if tx_result="$(committed_transaction_result_json "$config" "$committed_hash" "$committed_verify_attempts" 1 2>/dev/null)"; then
            assert_transaction_result_ok "$tx_result" "$tx_hash" "$contract_id.$entrypoint" || return 1
          elif (( ! accept_pipeline_only )); then
            tx_result="$(committed_transaction_result_json "$config" "$committed_hash" "$tx_committed_wait_secs" 1)" || return 1
            assert_transaction_result_ok "$tx_result" "$tx_hash" "$contract_id.$entrypoint" || return 1
          fi
          ;;
        Rejected|Expired)
          pipeline_content="$(pipeline_status_content_from_json "$pipeline_json")"
          if [[ "$pipeline_kind" == "Expired" ]]; then
            soraswap_require_public_write_health_ready_for_config \
              "$config" \
              "$contract_id.$entrypoint expired transaction $tx_hash" || {
                health_status=$?
                (( health_status == 75 )) && return 75
                return "$health_status"
              }
          fi
          echo "$contract_id.$entrypoint failed for transaction $tx_hash: $pipeline_content" >&2
          return 1
          ;;
        *)
          echo "$contract_id.$entrypoint reached unexpected pipeline status for transaction $tx_hash: $pipeline_kind" >&2
          return 1
          ;;
      esac
      ;;
    committed)
      tx_result="$(jq -c '.transaction_result // null' <<<"$terminal_json")"
      assert_transaction_result_ok "$tx_result" "$tx_hash" "$contract_id.$entrypoint" || return 1
      ;;
    *)
      echo "$contract_id.$entrypoint reached unexpected transaction wait source for $tx_hash: $terminal_source" >&2
      return 1
      ;;
  esac
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

foundation_contract_ids() {
  printf '%s\n' \
    n3x.n3x_hub \
    dlmm.dlmm_pool \
    dlmm.dlmm_router \
    batch_amm.epoch_auction \
    escrow.conditional_escrow
}

expected_contract_ids_for_deploy_scope() {
  local deploy_scope="${1:-${SORASWAP_DEPLOY_SCOPE:-full}}"

  case "$deploy_scope" in
    ""|full)
      expected_contract_ids
      ;;
    foundation)
      foundation_contract_ids
      ;;
    *)
      echo "unsupported SORASWAP_DEPLOY_SCOPE: $deploy_scope" >&2
      return 2
      ;;
  esac
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

contract_relative_path() {
  local src="$1"
  local rel="$src"

  rel="${rel#$SORASWAP_ROOT/contracts/}"
  rel="${rel#$SORASWAP_ROOT/}"
  rel="${rel#contracts/}"
  printf '%s\n' "$rel"
}

compiled_path_for() {
  local src="$1"
  local rel

  rel="$(contract_relative_path "$src")"
  echo "$SORASWAP_ROOT/artifacts/compiled/${rel%.ko}.to"
}

manifest_path_for() {
  local src="$1"
  local rel

  rel="$(contract_relative_path "$src")"
  echo "$SORASWAP_ROOT/artifacts/compiled/${rel%.ko}.manifest.json"
}

contract_artifact_manifest_json() {
  local config="$1"
  local code_file="$2"
  local output manifest_json

  [[ -n "$config" && -f "$config" && -f "$code_file" ]] || return 1
  output="$(iroha_cli_json --config "$config" contract manifest build --code-file "$code_file" 2>&1)" || {
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
    return 1
  }
  manifest_json="$(CONTRACT_MANIFEST_OUTPUT="$output" /usr/bin/python3 - <<'PY'
import json
import os
import sys

text = os.environ.get("CONTRACT_MANIFEST_OUTPUT", "")
decoder = json.JSONDecoder()
selected = None

for idx, ch in enumerate(text):
    if ch not in "{[":
        continue
    try:
        value, _ = decoder.raw_decode(text[idx:])
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and value.get("code_hash") and value.get("abi_hash"):
        selected = value

if selected is None:
    raise SystemExit(1)

print(json.dumps(selected, separators=(",", ":")))
PY
  )" || {
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
    return 1
  }
  compact_json_or_fail "contract artifact manifest" "$manifest_json"
}

contract_artifact_manifest_hashes_json() {
  local config="$1"
  local code_file="$2"
  local manifest_json code_hash abi_hash

  manifest_json="$(contract_artifact_manifest_json "$config" "$code_file")" || return 1
  code_hash="$(normalize_hash_literal "$(jq -r '.code_hash // empty' <<<"$manifest_json")")"
  abi_hash="$(normalize_hash_literal "$(jq -r '.abi_hash // empty' <<<"$manifest_json")")"
  [[ -n "$code_hash" && "$code_hash" != "null" ]] || return 1
  [[ -n "$abi_hash" && "$abi_hash" != "null" ]] || return 1
  jq -cn --arg code_hash "$code_hash" --arg abi_hash "$abi_hash" \
    '{code_hash: $code_hash, abi_hash: $abi_hash}'
}

write_deployment_manifest() {
  local compiled_manifest="$1"
  local manifest_out="$2"
  local env="$3"
  local contract_key="$4"
  local generated_at="$5"
  local contract_source="${6:-}"
  local config="${7:-}"
  local code_hash_override="${8:-}"
  local abi_hash_override="${9:-}"
  local code_file artifact_manifest_json manifest_json contract_source_label

  contract_source_label="$(soraswap_display_path "$contract_source")"

  if [[ -n "$config" && -n "$contract_source" ]]; then
    code_file="$(compiled_path_for "$contract_source")"
    if artifact_manifest_json="$(contract_artifact_manifest_json "$config" "$code_file" 2>/dev/null)"; then
      manifest_json="$(jq \
        --arg generated_at "$generated_at" \
        --arg environment "$env" \
        --arg contract_key "$contract_key" \
        --arg contract_source "$contract_source_label" \
        '. + {
          generated_at: $generated_at,
          environment: $environment,
          contract_key: $contract_key
        } + (if ($contract_source | length) > 0 then {contract_source: $contract_source} else {} end)' \
        <<<"$artifact_manifest_json")" || return 1
      soraswap_write_json_file_atomic "$manifest_json" "$manifest_out"
      return $?
    fi
  fi

  manifest_json="$(jq \
    --arg generated_at "$generated_at" \
    --arg environment "$env" \
    --arg contract_key "$contract_key" \
    --arg contract_source "$contract_source_label" \
    --arg code_hash_override "$code_hash_override" \
    --arg abi_hash_override "$abi_hash_override" \
    '. + {
      generated_at: $generated_at,
      environment: $environment,
      contract_key: $contract_key
    } + (if ($contract_source | length) > 0 then {contract_source: $contract_source} else {} end)
      + (if ($code_hash_override | length) > 0 then {code_hash: $code_hash_override} else {} end)
      + (if ($abi_hash_override | length) > 0 then {abi_hash: $abi_hash_override} else {} end)' \
    "$compiled_manifest")" || return 1
  soraswap_write_json_file_atomic "$manifest_json" "$manifest_out"
}

deployment_manifest_matches_environment() {
  local manifest_path="$1"
  local env="$2"
  local contract_key="$3"

  [[ -f "$manifest_path" ]] || return 1
  jq -e \
    --arg env "$env" \
    --arg contract_key "$contract_key" \
    '((.generated_at // "") | type == "string" and length > 0)
      and ((.environment // "") | type == "string")
      and (.environment == $env)
      and (.contract_key == $contract_key)
      and ((.code_hash // "") | type == "string" and length > 0)
      and ((.abi_hash // "") | type == "string" and length > 0)' \
    "$manifest_path" >/dev/null
}

contract_id_for() {
  local src="$1"
  local rel

  rel="$(contract_relative_path "$src")"
  rel="${rel%.ko}"
  echo "${rel//\//.}"
}

contract_alias_for() {
  local src="$1"
  local rel
  local name domain

  rel="$(contract_relative_path "$src")"
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
  echo "$SORASWAP_ROOT/${SORASWAP_CONTRACTS_MANIFEST:-iroha.contracts.toml}"
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
  local timeout_secs timeout_ms process_timeout_secs transaction_ttl_ms cli_config="" private_key_file="" metadata_file=""
  local output exit_code stdout_file stderr_file stderr_output combined_error redacted_output redacted_stderr_output
  local attempt max_attempts current_action timed_out iroha_bin gas_asset_id gas_limit
  local -a app_args

  timeout_secs="${SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS:-${SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS:-45}}"
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS" "$timeout_secs" || return 1
  timeout_ms="$(( timeout_secs * 1000 ))"
  process_timeout_secs="${SORASWAP_CONTRACT_APP_DEPLOY_PROCESS_TIMEOUT_SECS:-}"
  if [[ -z "$process_timeout_secs" ]]; then
    if (( timeout_secs > 0 )); then
      process_timeout_secs=$(( timeout_secs + 120 ))
    else
      process_timeout_secs=0
    fi
  fi
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_DEPLOY_PROCESS_TIMEOUT_SECS" "$process_timeout_secs" || return 1
  transaction_ttl_ms="${SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS:-${SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS:-900000}}"
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS" "$transaction_ttl_ms" || return 1
  max_attempts="${SORASWAP_CONTRACT_APP_DEPLOY_ATTEMPTS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_CONTRACT_APP_DEPLOY_ATTEMPTS" "$max_attempts" || return 1
  ensure_iroha_cli_bin || return 1
  iroha_bin="${SORASWAP_ACTIVE_IROHA_CLI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/iroha}"
  cli_config="$(SORASWAP_MATERIALIZE_TORII_REQUEST_TIMEOUT_MS="$timeout_ms" \
    materialize_cli_compatible_config "$config")" || return 1
  if [[ "$action" != "plan" ]]; then
    private_key_file="$(soraswap_config_private_key_temp_file "$config" contract-app-key)" || {
      soraswap_secure_unlink_owned_file "$cli_config" || true
      return 1
    }
  fi
  gas_asset_id="$(gas_metadata_asset_id_for_config "$config")"
  gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || {
    soraswap_secure_unlink_owned_files "$cli_config" "$private_key_file" || true
    return 1
  }
  metadata_file="$(jq -cn \
    --arg gas_asset_id "$gas_asset_id" \
    --argjson gas_limit "$gas_limit" \
    '{gas_asset_id: $gas_asset_id, gas_limit: $gas_limit}' \
    | soraswap_secret_temp_from_stdin contract-app-metadata)" || {
      soraswap_secure_unlink_owned_files "$cli_config" "$private_key_file" || true
      return 1
    }

  current_action="$action"
  attempt=1
  {
    while (( attempt <= max_attempts )); do
      stdout_file="$(soraswap_secure_temp_file contract-app-stdout)" || return 1
      stderr_file="$(soraswap_secure_temp_file contract-app-stderr)" || return 1
      timed_out=0
      app_args=(
        --manifest "$manifest_path"
        --authority "$SORASWAP_AUTHORITY"
      )
      if [[ "$current_action" != "plan" ]]; then
        [[ -n "$private_key_file" ]] || {
          echo "contract app $current_action requires a file-backed signing key" >&2
          return 1
        }
        app_args+=(--private-key-file "$private_key_file")
      fi
      if (( transaction_ttl_ms > 0 )); then
        app_args+=(--transaction-ttl-ms "$transaction_ttl_ms")
      fi
      if soraswap_run_external_with_timeout \
        "$process_timeout_secs" \
        "$iroha_bin" \
        --machine \
        --config "$cli_config" \
        --metadata "$metadata_file" \
        --output-format json \
        contract app "$current_action" \
        "${app_args[@]}" >"$stdout_file" 2>"$stderr_file"; then
        exit_code=0
      else
        exit_code=$?
      fi
      case "$exit_code" in
        124|137|142|143) timed_out=1 ;;
      esac
      output="$(command cat "$stdout_file" 2>/dev/null || true)"
      stderr_output="$(command cat "$stderr_file" 2>/dev/null || true)"
      if (( timed_out == 1 )); then
        stderr_output="$stderr_output"$'\n'"contract app $current_action process timed out after ${process_timeout_secs}s"
      fi
      if ! printf '%s\n%s' "$output" "$stderr_output" \
        | soraswap_assert_client_output_clean "$config" "$private_key_file"; then
        output=""
        stderr_output="contract app credential echo was suppressed"
        exit_code=1
      fi
      if ! soraswap_secure_unlink_owned_files "$stdout_file" "$stderr_file"; then
        return 1
      fi
      stdout_file=""
      stderr_file=""
      redacted_output="$(soraswap_redact_sensitive_text "$output")"
      redacted_stderr_output="$(soraswap_redact_sensitive_text "$stderr_output")"

      if (( exit_code == 0 )); then
        [[ -z "$redacted_stderr_output" ]] || printf '%s\n' "$redacted_stderr_output" >&2
        printf '%s\n' "$redacted_output"
        return 0
      fi

      combined_error="$stderr_output"$'\n'"$output"
      if [[ "$combined_error" == *"unexpected argument '--private-key-file'"* \
        || "$combined_error" == *"unknown option --private-key-file"* ]]; then
        echo "contract app requires Iroha support for --private-key-file; refusing inline private key fallback" >&2
        return 1
      fi
      if (( attempt < max_attempts )) \
        && [[ "$action" != "plan" ]] \
        && { (( timed_out == 1 )) || soraswap_contract_app_deploy_retryable_error "$combined_error"; }; then
        if (( timed_out == 1 )); then
          printf 'contract app %s timed out after %ss; resuming bundle deployment (attempt %s/%s)\n' \
            "$current_action" "$process_timeout_secs" "$(( attempt + 1 ))" "$max_attempts" >&2
        else
          printf 'contract app %s transport failed; resuming bundle deployment (attempt %s/%s)\n' \
            "$current_action" "$(( attempt + 1 ))" "$max_attempts" >&2
        fi
        current_action="resume"
        attempt=$(( attempt + 1 ))
        continue
      fi

      [[ -z "$redacted_stderr_output" ]] || printf '%s\n' "$redacted_stderr_output" >&2
      printf '%s\n' "$redacted_output" >&2
      return "$exit_code"
    done
    return 1
  } always {
    if ! soraswap_secure_unlink_owned_files "$stdout_file" "$stderr_file" "$cli_config" "$private_key_file" "$metadata_file"; then
      return 1
    fi
  }
}

contract_app_manifest_contract_names() {
  local manifest_path="$1"

  python3 - "$manifest_path" <<'PY'
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

data = tomllib.loads(Path(sys.argv[1]).read_text())
for contract in data.get("contracts", []):
    name = contract.get("name")
    if name:
        print(name)
PY
}

write_contract_app_manifest_subset() {
  local source_manifest="$1"
  local target_manifest="$2"
  shift 2

  python3 - "$source_manifest" "$target_manifest" "$@" <<'PY'
import json
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

source = Path(sys.argv[1])
target = Path(sys.argv[2])
source_root = source.parent.resolve()
selected = list(sys.argv[3:])
selected_set = set(selected)
data = tomllib.loads(source.read_text())

def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    raise TypeError(f"unsupported TOML value {value!r}")

def contract_value(key, value):
    if key in {"source", "artifact"} and isinstance(value, str):
        path = Path(value)
        if not path.is_absolute():
            return str((source_root / path).resolve())
    return value

lines = []
for key, value in data.items():
    if key in {"contracts", "profiles", "tests", "smoke"}:
        continue
    if isinstance(value, dict):
        continue
    lines.append(f"{key} = {toml_value(value)}")
if lines:
    lines.append("")

found = set()
for contract in data.get("contracts", []):
    name = contract.get("name")
    if name not in selected_set:
        continue
    found.add(name)
    lines.append("[[contracts]]")
    for key, value in contract.items():
        value = contract_value(key, value)
        lines.append(f"{key} = {toml_value(value)}")
    lines.append("")

missing = [name for name in selected if name not in found]
if missing:
    raise SystemExit(f"manifest does not contain selected contracts: {', '.join(missing)}")

for profile_name, profile in data.get("profiles", {}).items():
    lines.append(f"[profiles.{profile_name}]")
    for key, value in profile.items():
        lines.append(f"{key} = {toml_value(value)}")
    lines.append("")

target.write_text("\n".join(lines), encoding="utf-8")
PY
}

soraswap_contract_app_deploy_retryable_error() {
  local output="${1:-}"

  soraswap_public_transport_error_needs_health_gate "$output" && return 0
  grep -qiE \
    'timed out|timeout|deadline|failed to send http|connection closed|connection reset|connection refused|broken pipe|unexpected eof|end of file before message completed' \
    <<<"$output"
}

json_array_from_lines() {
  jq -Rsc 'split("\n") | map(select(length > 0))'
}

json_sha256() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

contract_bundle_receipt_with_metadata() {
  local env="$1"
  local receipt_json="$2"
  local generated_at="${3:-$(utc_timestamp)}"
  local chain_fingerprint_json

  chain_fingerprint_json="$(contract_bundle_receipt_chain_fingerprint_json_for_env "$env")" || return 1
  jq -c \
    --arg generated_at "$generated_at" \
    --arg environment "$env" \
    --argjson chain_fingerprint "$chain_fingerprint_json" \
    '. + {
      generated_at: $generated_at,
      environment: $environment,
      chain_fingerprint: $chain_fingerprint
    }' <<<"$receipt_json"
}

submit_contract_app_manifest_for_env() {
  local env="$1"
  local config="$2"
  local manifest_path="${3:-$(contract_app_manifest_path)}"
  local default_chunk_size chunk_size
  local default_chunk_block_wait_attempts chunk_block_wait_attempts
  local default_chunk_queued_stall_max_ms chunk_queued_stall_max_ms
  local chunk_wait_blocks="${SORASWAP_CONTRACT_APP_CHUNK_WAIT_BLOCKS:-1}"
  local receipt_json receipt_path aggregate_contracts_json chunks_json aggregate_json
  local chunk_manifest chunk_receipt chunk_names_json chunk_digest aggregate_digest
  local aggregate_chain_fingerprint_json submission_chain_fingerprint_json
  local receipt_generated_at aggregate_generated_at
  local chunk_count index offset end i current_height target_height
  local -a contract_names chunk_names chunk_manifest_paths

  case "$env" in
    testnet|production)
      default_chunk_size=1
      default_chunk_block_wait_attempts=300
      default_chunk_queued_stall_max_ms=180000
      ;;
    *)
      default_chunk_size=0
      default_chunk_block_wait_attempts=120
      default_chunk_queued_stall_max_ms=0
      ;;
  esac
  chunk_size="${SORASWAP_CONTRACT_APP_CHUNK_SIZE:-$default_chunk_size}"
  chunk_block_wait_attempts="${SORASWAP_CONTRACT_APP_CHUNK_BLOCK_WAIT_ATTEMPTS:-$default_chunk_block_wait_attempts}"
  chunk_queued_stall_max_ms="${SORASWAP_CONTRACT_APP_CHUNK_QUEUED_STALL_MAX_MS:-$default_chunk_queued_stall_max_ms}"
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_CHUNK_SIZE" "$chunk_size" || return 1
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_CHUNK_WAIT_BLOCKS" "$chunk_wait_blocks" || return 1
  soraswap_require_positive_integer_setting \
    "SORASWAP_CONTRACT_APP_CHUNK_BLOCK_WAIT_ATTEMPTS" \
    "$chunk_block_wait_attempts" || return 1
  soraswap_require_nonnegative_integer_setting \
    "SORASWAP_CONTRACT_APP_CHUNK_QUEUED_STALL_MAX_MS" \
    "$chunk_queued_stall_max_ms" || return 1
  case "${SORASWAP_CONTRACT_APP_CHUNK_TICK_BLOCKS:-1}" in
    0|1|true|false|yes|no|on|off)
      ;;
    *)
      echo "SORASWAP_CONTRACT_APP_CHUNK_TICK_BLOCKS must be 0, 1, true, false, yes, no, on, or off; got '${SORASWAP_CONTRACT_APP_CHUNK_TICK_BLOCKS}'" >&2
      return 1
      ;;
  esac

  contract_names=("${(@f)$(contract_app_manifest_contract_names "$manifest_path")}")
  if (( ${#contract_names[@]} == 0 )); then
    echo "contract app manifest contains no contracts: $(soraswap_display_path "$manifest_path")" >&2
    return 1
  fi
  case "$env" in
    testnet|production)
      submission_chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
      require_deployment_evidence_chain_fingerprint "$env" "$submission_chain_fingerprint_json" "contract app bundle submission" || return 1
      ;;
  esac

  if (( chunk_size <= 0 || ${#contract_names[@]} <= chunk_size )); then
    receipt_json="$(submit_contract_app_bundle "$config" deploy "$manifest_path")" || return 1
    receipt_generated_at="$(utc_timestamp)"
    receipt_json="$(contract_bundle_receipt_with_metadata "$env" "$receipt_json" "$receipt_generated_at")" || return 1
    materialize_contract_bundle_records_for_env "$env" "$receipt_json" "$config" "$receipt_generated_at"
    ensure_contract_deploy_nonce_after_bundle "$config" "$receipt_json" || return 1
    printf '%s\n' "$receipt_json"
    return 0
  fi

  receipt_path="$(contract_bundle_receipt_path_for_env "$env")"
  aggregate_contracts_json='[]'
  chunks_json='[]'
  chunk_manifest_paths=()
  mkdir -p "$SORASWAP_ROOT/tmp" || return 1

  {
  index=1
  chunk_count=$(( (${#contract_names[@]} + chunk_size - 1) / chunk_size ))

  for (( offset = 1; offset <= ${#contract_names[@]}; offset += chunk_size )); do
    end=$(( offset + chunk_size - 1 ))
    if (( end > ${#contract_names[@]} )); then
      end=${#contract_names[@]}
    fi
    chunk_names=()
    for (( i = offset; i <= end; i++ )); do
      chunk_names+=("${contract_names[$i]}")
    done

    chunk_manifest="$(mktemp "$SORASWAP_ROOT/tmp/soraswap-contract-app-chunk-${index}.XXXXXX")"
    chunk_manifest_paths+=("$chunk_manifest")
    write_contract_app_manifest_subset "$manifest_path" "$chunk_manifest" "${chunk_names[@]}" || {
      rm -f "${chunk_manifest_paths[@]}"
      return 1
    }
    printf 'deploying contract app chunk %s/%s (%s contracts): %s\n' \
      "$index" "$chunk_count" "${#chunk_names[@]}" "${(j:, :)chunk_names}" >&2

    chunk_receipt="$(submit_contract_app_bundle "$config" deploy "$chunk_manifest")" || {
      rm -f "${chunk_manifest_paths[@]}"
      return 1
    }
    materialize_contract_bundle_records_for_env "$env" "$chunk_receipt" "$config" || {
      rm -f "${chunk_manifest_paths[@]}"
      return 1
    }
    ensure_contract_deploy_nonce_after_bundle "$config" "$chunk_receipt" || {
      rm -f "${chunk_manifest_paths[@]}"
      return 1
    }

    chunk_names_json="$(printf '%s\n' "${chunk_names[@]}" | json_array_from_lines)"
    chunk_digest="$(jq -r '.bundle_digest // empty' <<<"$chunk_receipt")"
    chunks_json="$(jq -cn \
      --argjson chunks "$chunks_json" \
      --argjson names "$chunk_names_json" \
      --argjson receipt "$chunk_receipt" \
      --argjson index "$index" \
      --arg digest "$chunk_digest" \
      '$chunks + [{
        index: $index,
        bundle_digest: $digest,
        contract_count: ($names | length),
        contracts: $names,
        receipt: $receipt
      }]')"
    aggregate_contracts_json="$(jq -cn \
      --argjson existing "$aggregate_contracts_json" \
      --argjson receipt "$chunk_receipt" \
      '$existing + ($receipt.contracts // [])')"

    if (( index < chunk_count && chunk_wait_blocks > 0 )); then
      current_height="$(soraswap_current_block_height "$config")"
      if [[ -z "$current_height" || "$current_height" == "null" || "$current_height" != <-> ]]; then
        current_height=0
      fi
      target_height=$(( current_height + chunk_wait_blocks ))
      soraswap_wait_for_block_height_at_least \
        "$config" \
        "$target_height" \
        "contract-app-chunk-${index}" \
        "$chunk_block_wait_attempts" \
        "${SORASWAP_CONTRACT_APP_CHUNK_TICK_BLOCKS:-1}" \
        "$chunk_queued_stall_max_ms" || {
          local wait_status="$?"
          rm -f "${chunk_manifest_paths[@]}"
          return "$wait_status"
        }
    fi
    index=$(( index + 1 ))
  done

  aggregate_digest="$(jq -S -c --argjson chunks "$chunks_json" '$chunks' <<<"{}" | json_sha256)"
  aggregate_generated_at="$(utc_timestamp)"
  aggregate_chain_fingerprint_json="$(contract_bundle_receipt_chain_fingerprint_json_for_env "$env")" || {
    rm -f "${chunk_manifest_paths[@]}"
    return 1
  }
  aggregate_json="$(jq -cn \
    --arg generated_at "$aggregate_generated_at" \
    --arg environment "$env" \
    --arg bundle_digest "$aggregate_digest" \
    --argjson chain_fingerprint "$aggregate_chain_fingerprint_json" \
    --argjson chunks "$chunks_json" \
    --argjson contracts "$aggregate_contracts_json" \
    '{
      ok: true,
      generated_at: $generated_at,
      chunked: true,
      environment: $environment,
      chain_fingerprint: $chain_fingerprint,
      bundle_digest: $bundle_digest,
      chunk_count: ($chunks | length),
      chunks: $chunks,
      contracts: $contracts
  }')"
  soraswap_write_json_file_atomic "$aggregate_json" "$receipt_path" || {
    rm -f "${chunk_manifest_paths[@]}"
    return 1
  }
  rm -f "${chunk_manifest_paths[@]}"
  printf '%s\n' "$aggregate_json"
  } always {
    rm -f "${chunk_manifest_paths[@]}" 2>/dev/null || true
  }
}

wait_for_contract_alias_activation() {
  local config="$1"
  local contract_alias="$2"
  local expected_contract_address="$3"
  local deploy_tx_hash="${4:-}"
  local timeout_secs="${SORASWAP_CONTRACT_APP_ACTIVATION_MAX_TIME_SECS:-180}"
  local deadline now resolved_response resolved_address resolve_status tick_blocks tick_default tick_interval last_tick_at
  local pipeline_response pipeline_kind pipeline_summary

  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_ACTIVATION_MAX_TIME_SECS" "$timeout_secs" || return 1

  if public_env_for_config "$config" >/dev/null 2>&1; then
    tick_default=0
  else
    tick_default=1
  fi
  tick_blocks="${SORASWAP_CONTRACT_APP_ACTIVATION_TICK_BLOCKS:-$tick_default}"
  tick_interval="${SORASWAP_CONTRACT_APP_ACTIVATION_TICK_INTERVAL_SECS:-10}"
  case "$tick_blocks" in
    0|1|true|false|yes|no|on|off)
      ;;
    *)
      echo "SORASWAP_CONTRACT_APP_ACTIVATION_TICK_BLOCKS must be 0, 1, true, false, yes, no, on, or off; got '$tick_blocks'" >&2
      return 1
      ;;
  esac
  soraswap_require_nonnegative_integer_setting "SORASWAP_CONTRACT_APP_ACTIVATION_TICK_INTERVAL_SECS" "$tick_interval" || return 1
  last_tick_at=0
  deadline=$(( $(date +%s) + timeout_secs ))
  while true; do
    if resolved_response="$(contract_alias_resolve_json "$config" "$contract_alias" 2>/dev/null)"; then
      resolved_address="$(jq -r '.contract_address // empty' <<<"$resolved_response")"
      if [[ "$resolved_address" == "$expected_contract_address" ]]; then
        printf '%s\n' "$resolved_response"
        return 0
      fi
    else
      resolve_status=$?
      if (( resolve_status != 2 )); then
        contract_alias_resolve_json "$config" "$contract_alias" >/dev/null
        return 1
      fi
    fi

    if [[ -n "$deploy_tx_hash" ]] \
      && pipeline_response="$(pipeline_transaction_status_json "$config" "$deploy_tx_hash" auto 2>/dev/null)"; then
      pipeline_kind="$(pipeline_status_kind_from_json "$pipeline_response")"
      case "$pipeline_kind" in
        Rejected|Expired)
          pipeline_summary="$(jq -c '{
            summary: (.summary // null),
            status: (.status // .content.status // null),
            diagnostics: (.diagnostics // [])
          }' <<<"$pipeline_response")"
          echo "contract deploy transaction $deploy_tx_hash for $contract_alias reached $pipeline_kind before alias activation: $pipeline_summary" >&2
          return 1
          ;;
      esac
    fi

    now="$(date +%s)"
    if (( now >= deadline )); then
      echo "timed out waiting for $contract_alias to activate at $expected_contract_address" >&2
      return 1
    fi
    if [[ "$tick_blocks" == "1" || "$tick_blocks" == "true" || "$tick_blocks" == "yes" || "$tick_blocks" == "on" ]] \
      && (( now - last_tick_at >= tick_interval )); then
      soraswap_submit_block_height_tick "$config" "contract-activation" || true
      last_tick_at="$now"
    fi
    sleep 1
  done
}

materialize_contract_bundle_records_for_env() {
  local env="$1"
  local receipt_json="$2"
  local config="${3:-$(client_config_or_default "$env")}"
  local generated_at="${4:-}"
  local report_dir receipt_path chain_fingerprint_json contract_entry contract_key contract_source
  local contract_alias contract_address previous_contract_address upgraded dataspace deploy_nonce
  local contract_status pipeline_kind pipeline_final activation_response activation_address
  local code_hash_hex abi_hash_hex tx_hash_hex response_json instance_json record_json
  local record_path manifest_out compiled_manifest detail_json

  if ! jq -e '.ok == true' <<<"$receipt_json" >/dev/null; then
    echo "contract bundle receipt is not successful" >&2
    return 1
  fi

  report_dir="$SORASWAP_ROOT/deployments/${env}"
  receipt_path="$(contract_bundle_receipt_path_for_env "$env")"
  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  require_deployment_evidence_chain_fingerprint "$env" "$chain_fingerprint_json" "contract bundle materialization" || return 1
  if [[ -z "$generated_at" ]]; then
    generated_at="$(jq -r '.generated_at // empty' <<<"$receipt_json" 2>/dev/null || true)"
  fi
  if [[ -z "$generated_at" ]]; then
    generated_at="$(utc_timestamp)"
  fi
  receipt_json="$(contract_bundle_receipt_with_metadata "$env" "$receipt_json" "$generated_at")" || return 1
  mkdir -p "$report_dir"
  soraswap_write_json_file_atomic "$receipt_json" "$receipt_path" || return 1

  while IFS= read -r contract_entry; do
    contract_key="$(jq -r '.name' <<<"$contract_entry")"
    if [[ -z "$contract_key" || "$contract_key" == "null" ]]; then
      echo "bundle receipt contained a contract without a name" >&2
      return 1
    fi
    contract_alias="$(jq -r '.contract_alias' <<<"$contract_entry")"
    contract_address="$(jq -r '.contract_address' <<<"$contract_entry")"
    contract_status="$(jq -r '.status // empty' <<<"$contract_entry")"
    tx_hash_hex="$(jq -r '.tx_hash_hex // empty' <<<"$contract_entry")"
    pipeline_kind="$(jq -r '.pipeline_status.status.kind // .pipeline_status.content.status.kind // .pipeline_status.kind // empty' <<<"$contract_entry")"
    case "$pipeline_kind" in
      ""|Applied|Committed)
        pipeline_final=1
        ;;
      *)
        pipeline_final=0
        ;;
    esac

    contract_source="$(contract_source_for_key "$contract_key")" || {
      echo "unable to map bundle receipt contract ${contract_key} to a repo source file" >&2
      return 1
    }
    compiled_manifest="$(manifest_path_for "$contract_source")"
    if [[ ! -f "$compiled_manifest" ]]; then
      echo "missing compiled manifest for ${contract_key}: ${compiled_manifest}" >&2
      return 1
    fi

    if [[ "$contract_status" != "deployed" || "$pipeline_final" != "1" ]]; then
      activation_response="$(wait_for_contract_alias_activation "$config" "$contract_alias" "$contract_address" "$tx_hash_hex")" || {
        echo "bundle receipt contract ${contract_key} is not fully deployed" >&2
        return 1
      }
      activation_address="$(jq -r '.contract_address // empty' <<<"$activation_response")"
      if [[ "$activation_address" != "$contract_address" ]]; then
        echo "bundle receipt contract ${contract_key} resolved to $activation_address, expected $contract_address" >&2
        return 1
      fi
      contract_entry="$(jq '
        .status = "deployed"
        | if ((.pipeline_status // null) | type) == "object" then
            .pipeline_status.status.kind = "Committed"
          else
            .
          end
      ' <<<"$contract_entry")"
      receipt_json="$(jq --arg contract_key "$contract_key" '
        (.contracts[] | select(.name == $contract_key)) |= (
          .status = "deployed"
          | if ((.pipeline_status // null) | type) == "object" then
              .pipeline_status.status.kind = "Committed"
            else
              .
            end
        )
      ' <<<"$receipt_json")"
      contract_status="deployed"
    fi

    previous_contract_address="$(jq -r '.previous_contract_address // empty' <<<"$contract_entry")"
    upgraded="$(jq -r '.upgraded // false' <<<"$contract_entry")"
    dataspace="$(jq -r '.dataspace // "universal"' <<<"$contract_entry")"
    deploy_nonce="$(jq -r '.deploy_nonce // 0' <<<"$contract_entry")"
    code_hash_hex="$(jq -r '.code_hash_hex // empty' <<<"$contract_entry")"
    abi_hash_hex="$(jq -r '.abi_hash_hex // empty' <<<"$contract_entry")"

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
      --arg generated_at "$generated_at" \
      --arg environment "$env" \
      --arg contract_source "$(soraswap_display_path "$contract_source")" \
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
        generated_at: $generated_at,
        environment: $environment,
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
    soraswap_write_json_file_atomic "$record_json" "$record_path" || return 1
    write_deployment_manifest \
      "$compiled_manifest" \
      "$manifest_out" \
      "$env" \
      "$contract_key" \
      "$generated_at" \
      "$contract_source" \
      "$config" \
      "$code_hash_hex" \
      "$abi_hash_hex"

    detail_json="$(jq -cn \
      --arg record_path "$(soraswap_display_path "$record_path")" \
      --argjson receipt "$contract_entry" \
      '{record_path: $record_path, receipt: $receipt}')"
    deploy_report_set_contract "$env" "$contract_key" "completed" "$detail_json"
  done < <(jq -c '.contracts[]' <<<"$receipt_json")

  soraswap_write_json_file_atomic "$receipt_json" "$receipt_path"
}

deployment_record_path_for_env() {
  local env="$1"
  local contract_key="$2"
  echo "$SORASWAP_ROOT/deployments/${env}/${contract_key}.deploy.json"
}

deployment_records_json_for_env() {
  local env="$1"
  local contract_key
  local deploy_scope="${SORASWAP_DEPLOY_SCOPE:-full}"
  local record_paths=()
  local record_path
  local -A expected_contract_key_map

  for contract_key in "${(@f)$(expected_contract_ids_for_deploy_scope "$deploy_scope")}"; do
    expected_contract_key_map[$contract_key]=1
  done

  for record_path in "$SORASWAP_ROOT/deployments/${env}"/*.deploy.json(N); do
    if [[ "${record_path:t}" == "soraswap.bundle.deploy.json" \
      || "${record_path:t}" == "soraswap.foundation.bundle.deploy.json" ]]; then
      continue
    fi

    contract_key="$(jq -r '.contract_key // empty' "$record_path" 2>/dev/null || true)"
    [[ -n "$contract_key" ]] || continue
    [[ -n "${expected_contract_key_map[$contract_key]:-}" ]] || continue
    deployment_record_matches_current_evidence "$record_path" "$env" "$contract_key" || continue
    record_paths+=("$record_path")
  done

  if (( ${#record_paths[@]} == 0 )); then
    echo '[]'
    return 0
  fi

  jq -sc 'sort_by(.contract_key)' "${record_paths[@]}"
}

cleanup_stale_deployment_records_for_env() {
  local env="$1"
  local report_dir contract_key record_name record_stem manifest_name manifest_stem
  local deploy_scope="${SORASWAP_DEPLOY_SCOPE:-full}"
  local record_path
  local manifest_path
  local -A expected_contract_key_map

  report_dir="$(deployments_dir_for_env "$env")"
  for contract_key in "${(@f)$(expected_contract_ids_for_deploy_scope "$deploy_scope")}"; do
    expected_contract_key_map[$contract_key]=1
  done

  for record_path in "$report_dir"/*.deploy.json(N); do
    if [[ "${record_path:t}" == "soraswap.bundle.deploy.json" \
      || "${record_path:t}" == "soraswap.foundation.bundle.deploy.json" ]]; then
      continue
    fi

    contract_key="$(jq -r '.contract_key // empty' "$record_path" 2>/dev/null || true)"
    if [[ -n "$contract_key" ]] \
      && [[ -n "${expected_contract_key_map[$contract_key]:-}" ]] \
      && deployment_record_matches_current_evidence "$record_path" "$env" "$contract_key"; then
      continue
    fi

    record_name="${record_path:t}"
    record_stem="${record_name%.deploy.json}"
    rm -f "$record_path"
    rm -f "$report_dir/${record_stem}.manifest.json"
  done

  for manifest_path in "$report_dir"/*.manifest.json(N); do
    manifest_name="${manifest_path:t}"
    manifest_stem="${manifest_name%.manifest.json}"

    if [[ -z "${expected_contract_key_map[$manifest_stem]:-}" ]] \
      || ! deployment_record_matches_current_evidence "$report_dir/${manifest_stem}.deploy.json" "$env" "$manifest_stem"; then
      rm -f "$manifest_path"
    fi
  done
}

deployment_snapshot_record_json_for_env() {
  local env="$1"
  local contract_key="$2"
  local snapshot
  local chain_fingerprint_json

  snapshot="$(contracts_snapshot_latest_path_for_env "$env")"
  if [[ ! -f "$snapshot" ]]; then
    return 1
  fi

  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1

  jq -cer --arg key "$contract_key" --arg env "$env" --argjson current_chain "$chain_fingerprint_json" '
    def named_record:
      select((.name? // .contract_key? // .key? // "") == $key)
      | select((.environment // "") == $env);
    def current_chain_match:
      $current_chain == null
      or (
        (.chain_fingerprint // {}) as $stored
        | (($stored.torii_url // "") | type == "string" and length > 0)
        and $stored.torii_url == $current_chain.torii_url
        and $stored.chain == $current_chain.chain
        and $stored.block_1_hash == $current_chain.block_1_hash
      );
    def records:
      (.contracts? // empty) as $contracts
      | if ($contracts | type) == "array" then
          $contracts[] | (., (.contracts[]?))
        elif ($contracts | type) == "object" then
          $contracts[]? | (., (.contracts[]?))
        else
          empty
        end;
    select((.environment // "") == $env)
    | select(current_chain_match)
    | records | named_record
  ' "$snapshot" | tail -n 1
}

deployed_contract_id_for_env() {
  local env="$1"
  local contract_key="$2"
  local record snapshot_record

  record="$(deployment_record_path_for_env "$env" "$contract_key")"
  if deployment_record_matches_current_evidence "$record" "$env" "$contract_key"; then
    jq -r '.contract_address // .contract_id // empty' "$record"
    return 0
  fi
  if snapshot_record="$(deployment_snapshot_record_json_for_env "$env" "$contract_key" 2>/dev/null)"; then
    jq -r '.contract_address // .contract_id // .instance.contract_address // empty' <<<"$snapshot_record"
    return 0
  fi

  echo "$contract_key"
}

deployed_contract_dataspace_for_env() {
  local env="$1"
  local contract_key="$2"
  local record snapshot_record

  record="$(deployment_record_path_for_env "$env" "$contract_key")"
  if deployment_record_matches_current_evidence "$record" "$env" "$contract_key"; then
    jq -r '.dataspace // .namespace // "universal"' "$record"
    return 0
  fi
  if snapshot_record="$(deployment_snapshot_record_json_for_env "$env" "$contract_key" 2>/dev/null)"; then
    jq -r '.dataspace // .namespace // .instance.dataspace // "universal"' <<<"$snapshot_record"
    return 0
  fi

  echo "universal"
}

contract_alias_resolve_json() {
  local config="$1"
  local contract_alias="$2"
  local torii_base request response http_code body attempt=1 retry_after_failure=0
  local last_http_code="" last_body=""

  soraswap_validate_torii_read_max_time || return 1
  soraswap_validate_contract_alias_resolve_retry_settings || return 1
  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"
  request="$(jq -cn --arg contract_alias "$contract_alias" '{contract_alias: $contract_alias}')"

  while (( attempt <= SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT )); do
    retry_after_failure=0
    if response="$(
      soraswap_curl_for_config "$config" -sS \
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
      if soraswap_contract_alias_resolve_retryable_http_code "$http_code"; then
        retry_after_failure=1
      else
        break
      fi
    else
      last_http_code="000"
      last_body="transport failure"
      retry_after_failure=1
    fi

    if (( retry_after_failure == 0 || attempt >= SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT )); then
      break
    fi
    sleep "$SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS"
    attempt=$(( attempt + 1 ))
  done

  if [[ -n "$last_http_code" ]]; then
    echo "contract alias resolve request failed for $contract_alias: HTTP $last_http_code: $(soraswap_redact_sensitive_text "$last_body")" >&2
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

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")"
  torii_base="${torii_base%/}"

  while (( page <= max_pages && ${#aliases[@]} < max_aliases )); do
    if ! response="$(
      soraswap_curl_for_config "$config" -fsS \
        --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
        "$torii_base/v1/explorer/transactions?page=$page&per_page=10" 2>/dev/null
    )"; then
      break
    fi

    page_hashes=("${(@f)$(jq -r '.items[] | select(.executable == "Instructions" and .status == "Committed") | .hash' <<<"$response")}")
    for hash in "${page_hashes[@]}"; do
      [[ -z "$hash" ]] && continue
      encoded="$(
        soraswap_curl_for_config "$config" -fsS \
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
  local bundle_receipt_path bundle_contract_json bundle_contract_address
  local response_json instance_json record_json recent_aliases recovered=0 resolve_status
  local report_dir="$SORASWAP_ROOT/deployments/${env}"
  local chain_fingerprint_json generated_at
  local -a contract_paths
  local -a missing_aliases=()
  local -a missing_manifests=()

  mkdir -p "$report_dir"
  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  require_deployment_evidence_chain_fingerprint "$env" "$chain_fingerprint_json" "deployment record recovery" || return 1
  generated_at="$(utc_timestamp)"

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

    if artifact_hashes_json="$(contract_artifact_manifest_hashes_json "$config" "$(compiled_path_for "$contract_path")" 2>/dev/null)"; then
      expected_code_hash="$(jq -r '.code_hash' <<<"$artifact_hashes_json")"
      expected_abi_hash="$(jq -r '.abi_hash' <<<"$artifact_hashes_json")"
    else
      expected_code_hash="$(manifest_code_hash_hex "$compiled_manifest")"
      expected_abi_hash="$(manifest_abi_hash_hex "$compiled_manifest")"
    fi
    contract_address="$(jq -r '.contract_address // empty' <<<"$resolved_response")"
    dataspace="$(jq -r '.dataspace // "universal"' <<<"$resolved_response")"
    if [[ -z "$contract_address" ]]; then
      echo "contract alias resolve response for $contract_alias did not include a contract address" >&2
      return 1
    fi

    bundle_receipt_path="$(contract_bundle_receipt_path_for_env "$env")"
    if [[ -f "$bundle_receipt_path" ]]; then
      bundle_contract_json="$(jq -c --arg contract_key "$contract_key" '.contracts[]? | select(.name == $contract_key)' "$bundle_receipt_path" 2>/dev/null || true)"
      if [[ -n "$bundle_contract_json" ]]; then
        bundle_contract_address="$(jq -r '.contract_address // empty' <<<"$bundle_contract_json")"
        if [[ "$bundle_contract_address" == "$contract_address" ]]; then
          expected_code_hash="$(jq -r '.code_hash_hex // empty | ascii_downcase' <<<"$bundle_contract_json")"
          expected_abi_hash="$(jq -r '.abi_hash_hex // empty | ascii_downcase' <<<"$bundle_contract_json")"
        fi
      fi
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
	      --arg generated_at "$generated_at" \
	      --arg environment "$env" \
      --arg contract_source "$(soraswap_display_path "$contract_path")" \
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
	        generated_at: $generated_at,
	        environment: $environment,
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

    soraswap_write_json_file_atomic "$record_json" "$record_path" || return 1
    write_deployment_manifest \
      "$compiled_manifest" \
      "$manifest_out" \
      "$env" \
      "$contract_key" \
      "$generated_at" \
      "$contract_path" \
      "$config" \
      "$expected_code_hash" \
      "$expected_abi_hash"
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
  local chain_discriminant helper_bin

  if [[ -z "$literal" ]]; then
    return 1
  fi
  if ! is_contract_address_literal "$literal"; then
    echo "$literal"
    return 0
  fi

  chain_discriminant="$(network_prefix_for_config "$config")" || return 1
  helper_bin="${SORASWAP_ACCOUNT_LITERAL_REENCODE_BIN:-}"
  if [[ -z "$helper_bin" ]]; then
    if [[ -x "$SORASWAP_IROHA_ROOT/target/release/account_literal_reencode" ]]; then
      helper_bin="$SORASWAP_IROHA_ROOT/target/release/account_literal_reencode"
    elif [[ -x "$SORASWAP_IROHA_ROOT/target/debug/account_literal_reencode" ]]; then
      helper_bin="$SORASWAP_IROHA_ROOT/target/debug/account_literal_reencode"
    elif (( $+commands[account_literal_reencode] )); then
      helper_bin="$commands[account_literal_reencode]"
    fi
  fi
  if [[ -z "$helper_bin" || ! -x "$helper_bin" ]]; then
    echo "account_literal_reencode is required to derive non-signable contract subjects" >&2
    return 1
  fi

  "$helper_bin" \
    --contract-address "$literal" \
    --to-chain-discriminant "$chain_discriminant" 2>/dev/null \
    | tail -n 1 \
    | tr -d '\r\n'
}

compile_one() {
  local src="$1"
  local out manifest out_dir compiler_bin output filtered
  out="$(compiled_path_for "$src")"
  manifest="$(manifest_path_for "$src")"
  soraswap_require_binary_integer_setting "SORASWAP_FORCE_COMPILE" "${SORASWAP_FORCE_COMPILE:-0}" || return 1
  ensure_koto_bin
  compiler_bin="$SORASWAP_ACTIVE_KOTO_BIN"
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
      build \
      --out "$out" \
      --manifest-out "$manifest" \
      "$src" 2>&1
  )"; then
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
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
  ensure_koto_bin
  (
    cd "$SORASWAP_IROHA_ROOT"
    "$SORASWAP_ACTIVE_KOTO_BIN" check "$src"
  )
}

deployment_record_matches_current_chain() {
  local record_path="$1"
  local fingerprint_json="$2"
  local expected_env="${3:-}"
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
    --arg expected_env "$expected_env" \
    '
      ((.generated_at // "") | type == "string" and length > 0)
      and (
        ($expected_env == "")
        or (((.environment // "") | type == "string") and .environment == $expected_env)
      )
      and (
        (.chain_fingerprint // {}) as $stored
        | (($stored.torii_url // "") | type == "string" and length > 0)
        and $stored.torii_url == $current.torii_url
        and $stored.chain == $current.chain
        and $stored.block_1_hash == $current.block_1_hash
      )
	    ' "$record_path" >/dev/null
}

deployment_record_matches_environment() {
  local record_path="$1"
  local env="$2"

  [[ -f "$record_path" ]] || return 1
  jq -e --arg env "$env" \
    '((.environment // "") | type == "string") and .environment == $env' \
    "$record_path" >/dev/null
}

deployment_record_hashes_match_manifest() {
  local record_path="$1"
  local manifest_path="$2"
  local manifest_code_hash manifest_abi_hash

  [[ -f "$record_path" && -f "$manifest_path" ]] || return 1
  manifest_code_hash="$(manifest_code_hash_hex "$manifest_path")"
  manifest_abi_hash="$(manifest_abi_hash_hex "$manifest_path")"
  [[ -n "$manifest_code_hash" && "$manifest_code_hash" != "null" ]] || return 1
  [[ -n "$manifest_abi_hash" && "$manifest_abi_hash" != "null" ]] || return 1

  jq -e \
    --arg manifest_code_hash "$manifest_code_hash" \
    --arg manifest_abi_hash "$manifest_abi_hash" \
    '
      def normalized_hash:
        tostring
        | ascii_downcase
        | sub("^hash:"; "")
        | split("#")[0]
        | sub("^0x"; "");
      ((.code_hash_hex // .code_hash // .instance.code_hash_hex // .instance.code_hash // .response.code_hash_hex // .response.code_hash // "") | normalized_hash) == $manifest_code_hash
      and ((.abi_hash_hex // .abi_hash // .instance.abi_hash_hex // .instance.abi_hash // .response.abi_hash_hex // .response.abi_hash // "") | normalized_hash) == $manifest_abi_hash
    ' "$record_path" >/dev/null
}

deployment_record_matches_current_evidence() {
  local record_path="$1"
  local env="$2"
  local contract_key="${3:-}"
  local chain_fingerprint_json manifest_path

  [[ -f "$record_path" ]] || return 1
  if [[ -z "$contract_key" ]]; then
    contract_key="$(jq -r '.contract_key // empty' "$record_path" 2>/dev/null || true)"
  fi
  [[ -n "$contract_key" ]] || return 1
  jq -e --arg contract_key "$contract_key" \
    '(.contract_key // "") == $contract_key
      and ((.generated_at // "") | type == "string")
      and ((.generated_at // "") != "")' \
    "$record_path" >/dev/null || return 1
  deployment_record_matches_environment "$record_path" "$env" || return 1

  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  if [[ "$chain_fingerprint_json" != "null" ]] \
    && ! deployment_record_matches_current_chain "$record_path" "$chain_fingerprint_json" "$env"; then
    return 1
  fi

  manifest_path="$(deployments_dir_for_env "$env")/${contract_key}.manifest.json"
  deployment_manifest_matches_environment "$manifest_path" "$env" "$contract_key" || return 1
  deployment_record_hashes_match_manifest "$record_path" "$manifest_path"
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
    if deployment_manifest_matches_environment "$manifest_path" "$env" "$contract_key"; then
      expected_code_hash="$(manifest_code_hash_hex "$manifest_path")"
    fi
    if [[ ! -f "$record_path" ]] \
      || [[ -z "$expected_code_hash" ]] \
      || ! deployment_record_matches_current_evidence "$record_path" "$env" "$contract_key" \
      || ! live_contract_deployment_from_record "$config" "$record_path" "$expected_code_hash" "$env" >/dev/null 2>&1; then
      needs_record_recovery=1
      break
    fi
  done

  if (( needs_record_recovery )); then
    zsh "$SORASWAP_ROOT/scripts/compile_contracts.sh"
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
      tx_hash_hex: ($response.tx_hash_hex // $response.commit_tx_hash // ""),
      verification: "transaction_and_manifest"
    }'
}

confirm_contract_deploy_response() {
  local config="$1"
  local response_json="$2"
  local contract_key="$3"
  local expected_code_hash="$4"
  local normalized_response_json tx_hash pipeline_json pipeline_kind pipeline_content tx_json contract_address
  local deploy_nonce next_deploy_nonce deploy_nonce_wait_secs
  local code_bytes_visible=0

  if normalized_response_json="$(normalize_contract_deploy_response_json "$response_json" 2>/dev/null)" \
    && [[ -n "$normalized_response_json" ]]; then
    response_json="$normalized_response_json"
  fi

  contract_address="$(jq -r '.contract_address // empty' <<<"$response_json")"
  if [[ -z "$contract_address" ]]; then
    echo "$contract_key.deploy confirmation response did not include a contract address" >&2
    return 1
  fi

  tx_hash="$(jq -r '.tx_hash_hex // .commit_tx_hash // empty' <<<"$response_json")"
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

  if contract_code_bytes_visible_by_code_hash "$config" "$expected_code_hash"; then
    code_bytes_visible=1
    deploy_progress_note "$contract_key" "code-bytes already visible" "$expected_code_hash"
  fi

  if (( ! code_bytes_visible )); then
    deploy_progress_note "$contract_key" "wait manifest" "$expected_code_hash"
    wait_for_contract_manifest_by_code_hash "$config" "$expected_code_hash" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
    deploy_progress_note "$contract_key" "manifest visible" "$expected_code_hash"
    deploy_progress_note "$contract_key" "wait code-bytes" "$expected_code_hash"
    wait_for_contract_code_bytes_by_code_hash "$config" "$expected_code_hash" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
    deploy_progress_note "$contract_key" "code-bytes visible" "$expected_code_hash"
  fi

  deploy_nonce="$(jq -r '.deploy_nonce // empty' <<<"$response_json")"
  if [[ "$deploy_nonce" =~ '^[0-9]+$' ]]; then
    next_deploy_nonce=$(( deploy_nonce + 1 ))
    deploy_nonce_wait_secs="${SORASWAP_DEPLOY_NONCE_WAIT_SECS:-120}"
    soraswap_require_nonnegative_integer_setting "SORASWAP_DEPLOY_NONCE_WAIT_SECS" "$deploy_nonce_wait_secs" || return 1
    if (( deploy_nonce_wait_secs > 0 )); then
      deploy_progress_note "$contract_key" "wait deploy nonce" "$next_deploy_nonce"
      wait_for_contract_deploy_nonce_at_least "$config" "$next_deploy_nonce" "$deploy_nonce_wait_secs" 1 || return 1
      deploy_progress_note "$contract_key" "deploy nonce visible" "$next_deploy_nonce"
    else
      deploy_progress_note "$contract_key" "skip deploy nonce wait" "$next_deploy_nonce"
    fi
  fi

  if contract_liveness_probe_entrypoint_for_key "$contract_key" >/dev/null 2>&1; then
    deploy_progress_note "$contract_key" "wait instance" "$contract_address"
    wait_for_contract_instance_liveness "$config" "$contract_key" "$contract_address" "$SORASWAP_DEPLOY_MANIFEST_WAIT_SECS" 1 >/dev/null || return 1
    deploy_progress_note "$contract_key" "instance live" "$contract_address"
  else
    deploy_progress_note "$contract_key" "skip instance liveness" "no liveness probe configured"
  fi
  synthetic_contract_instance_json_from_response "$response_json"
}

capture_confirm_contract_deploy_response() {
  local stderr_path output status

  stderr_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-contract-deploy-confirm.XXXXXX")" || return 1
  if output="$(confirm_contract_deploy_response "$@" 2>"$stderr_path")"; then
    if [[ -s "$stderr_path" ]]; then
      cat "$stderr_path" >&2
    fi
    rm -f "$stderr_path"
    printf '%s\n' "$output"
    return 0
  fi

  status=$?
  if [[ -s "$stderr_path" ]]; then
    cat "$stderr_path"
  fi
  rm -f "$stderr_path"
  return "$status"
}

live_contract_deployment_from_record() {
  local config="$1"
  local record_path="$2"
  local expected_code_hash="$3"
  local expected_env="${4:-}"
  local response_json current_code_hash contract_alias contract_source resolved_response
  local contract_key contract_address deploy_strategy chain_fingerprint_json
  local liveness_error resolve_error

  chain_fingerprint_json="$(chain_fingerprint_json_or_null)" || return 1
  if [[ "$chain_fingerprint_json" != "null" ]]; then
    deployment_record_matches_current_chain "$record_path" "$chain_fingerprint_json" "$expected_env" || return 1
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
  deploy_strategy="$(jq -r '.deploy_strategy // empty' "$record_path")"
  if [[ -n "$expected_code_hash" \
    && "$current_code_hash" != "$expected_code_hash" \
    && "$deploy_strategy" != "bundle" \
    && "$deploy_strategy" != "recovered_from_alias_resolve" ]]; then
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
  if contract_liveness_probe_entrypoint_for_key "$contract_key" >/dev/null 2>&1; then
    if ! liveness_error="$(wait_for_contract_instance_liveness "$config" "$contract_key" "$contract_address" 8 1 2>&1 >/dev/null)"; then
      [[ -n "$liveness_error" ]] && printf '%s\n' "$liveness_error" >&2
      return 1
    fi
  fi

  contract_alias="$(jq -r '.contract_alias // .response.contract_alias // empty' "$record_path")"
  if [[ -z "$contract_alias" ]]; then
    contract_source="$(jq -r '.contract_source // empty' "$record_path")"
    if [[ -n "$contract_source" && "$contract_source" != "null" ]]; then
      contract_alias="$(contract_alias_for "$contract_source")"
    fi
  fi
  if [[ -n "$contract_alias" ]]; then
    if ! resolved_response="$(contract_alias_resolve_json "$config" "$contract_alias" 2>&1)"; then
      resolve_error="$resolved_response"
      [[ -n "$resolve_error" ]] && printf '%s\n' "$resolve_error" >&2
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
  local expected_code_hash expected_abi_hash artifact_hashes_json instance_json record_json existing_instance
  local current_nonce deploy_nonce post_nonce predicted_address predicted_subject response_json normal_output normal_error redacted_output
  local recorded_nonce
  local split_output split_output_raw deploy_strategy detail_json confirm_output chain_discriminant
  local expected_chain_id
  local private_key_file fee_payment_file gas_limit
  local chain_fingerprint_json chain_fingerprint_json_compact response_json_compact instance_json_compact generated_at
  local normal_status split_status health_status

  contract_key="$(contract_id_for "$src")"
  contract_alias="$(contract_alias_for "$src")"
  dataspace="universal"
  manifest_out="$SORASWAP_ROOT/deployments/${env}/${contract_key}.manifest.json"
  deploy_out="$(deployment_record_path_for_env "$env" "$contract_key")"
  code_file="$(compiled_path_for "$src")"
  compiled_manifest="$(manifest_path_for "$src")"
  if artifact_hashes_json="$(contract_artifact_manifest_hashes_json "$config" "$code_file" 2>/dev/null)"; then
    expected_code_hash="$(jq -r '.code_hash' <<<"$artifact_hashes_json")"
    expected_abi_hash="$(jq -r '.abi_hash' <<<"$artifact_hashes_json")"
  else
    expected_code_hash="$(manifest_code_hash_hex "$compiled_manifest")"
    expected_abi_hash="$(manifest_abi_hash_hex "$compiled_manifest")"
  fi
  chain_discriminant="$(chain_discriminant_for_env_config "$env" "$config")"
  expected_chain_id="$(config_chain_id_from_config "$config")" || return 1
  chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$env")" || return 1
  require_deployment_evidence_chain_fingerprint "$env" "$chain_fingerprint_json" "single contract deployment" || return 1
  chain_fingerprint_json_compact="$(compact_json_or_fail "$contract_key.chain_fingerprint_json" "$chain_fingerprint_json")"
  mkdir -p "$(dirname "$manifest_out")"

  if deployment_record_matches_current_chain "$deploy_out" "$chain_fingerprint_json" "$env" \
    && deployment_record_matches_environment "$deploy_out" "$env"; then
    if existing_instance="$(live_contract_deployment_from_record "$config" "$deploy_out" "$expected_code_hash" "$env")"; then
      generated_at="$(jq -r '.generated_at // empty' "$deploy_out" 2>/dev/null || true)"
      if [[ -z "$generated_at" ]]; then
        generated_at="$(utc_timestamp)"
      fi
      existing_instance="$(compact_json_or_fail "$contract_key.existing_instance" "$existing_instance")"
      write_deployment_manifest \
        "$compiled_manifest" \
        "$manifest_out" \
        "$env" \
        "$contract_key" \
        "$generated_at" \
        "$src" \
        "$config" \
        "$expected_code_hash" \
        "$expected_abi_hash"
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
  if [[ "$chain_fingerprint_json" != "null" ]]; then
    recorded_nonce="$(max_deploy_nonce_for_env_records "$env" "$chain_fingerprint_json")"
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
    normal_output="$(normalize_contract_deploy_response_json "$normal_output")" || {
      redacted_output="$(soraswap_redact_sensitive_text "$normal_output")"
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg response "$redacted_output" \
        '{contract_key: $contract_key, stage: "normal_deploy_normalize", response: $response}')"
      echo "unable to normalize deploy response for $contract_key: $redacted_output" >&2
      return 1
    }
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
      redacted_output="$(soraswap_redact_sensitive_text "$normal_output")"
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg response "$redacted_output" \
        '{contract_key: $contract_key, stage: "normal_deploy_validate", response: $response}')"
      echo "unexpected deploy response for $contract_key: $redacted_output" >&2
      return 1
    fi
    response_json="$normal_output"
    if confirm_output="$(capture_confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash")"; then
      instance_json="$confirm_output"
      deploy_strategy="normal"
    else
      redacted_output="$(soraswap_redact_sensitive_text "$confirm_output")"
      if [[ "$redacted_output" == *"pipeline: Rejected"* \
        || "$redacted_output" == *"deploy failed for transaction"* ]]; then
        normal_error="$redacted_output"
        response_json=""
        deploy_report_set_contract "$env" "$contract_key" "running" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg contract_address "$predicted_address" \
          --arg error "$redacted_output" \
          '{
            contract_key: $contract_key,
            stage: "normal_deploy_confirm_rejected_retry_split",
            contract_address: $contract_address,
            normal_deploy_error: $error
          }')"
        echo "normal deploy for $contract_key was rejected; retrying with split deploy fallback: $redacted_output" >&2
      else
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg response "$response_json" \
        --arg error "$redacted_output" \
        '{
          contract_key: $contract_key,
          stage: "normal_deploy_confirm",
          contract_address: $contract_address,
          response: $response,
          error: $error
        }')"
        echo "normal deploy completed for $contract_key but confirmation failed: $redacted_output" >&2
        return 1
      fi
    fi
  else
    normal_status="$?"
    normal_error="$(soraswap_redact_sensitive_text "$normal_output")"
    if (( normal_status == 75 )); then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg error "$normal_error" \
        '{contract_key: $contract_key, stage: "normal_deploy_public_health", error: $error}')"
      echo "$normal_error" >&2
      return "$normal_status"
    fi
    health_status=0
    soraswap_stop_if_public_transport_health_degraded \
      "$config" \
      "contract deploy $contract_key transport" \
      "$normal_output" || health_status=$?
    if (( health_status != 0 )); then
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg error "$normal_error" \
        '{contract_key: $contract_key, stage: "normal_deploy_public_health", error: $error}')"
      echo "$normal_error" >&2
      return "$health_status"
    fi
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
      if confirm_output="$(capture_confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash")"; then
        instance_json="$confirm_output"
        deploy_strategy="adopted_committed"
      else
        redacted_output="$(soraswap_redact_sensitive_text "$confirm_output")"
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg contract_address "$predicted_address" \
          --argjson current_nonce "$current_nonce" \
          --argjson deploy_nonce "$deploy_nonce" \
          --argjson post_nonce "$post_nonce" \
          --arg normal_error "$normal_error" \
          --arg error "$redacted_output" \
          '{
            contract_key: $contract_key,
            stage: "adopt_committed_confirm",
            contract_address: $contract_address,
            current_nonce: $current_nonce,
            deploy_nonce: $deploy_nonce,
            post_nonce: $post_nonce,
            error: $error
          } + (if ($normal_error | length) > 0 then {normal_deploy_error: $normal_error} else {} end)')"
        echo "deploy nonce advanced for $contract_key but confirmation failed: $redacted_output" >&2
        return 1
      fi
    fi
  fi

  if [[ -z "$instance_json" ]]; then
    if [[ -z "$predicted_address" ]]; then
      echo "cannot use native split deploy for $contract_key without a derived contract address" >&2
      return 1
    fi
    predicted_subject="$(contract_subject_account_for_literal "$config" "$predicted_address")" || return 1
    private_key_file="$(soraswap_config_private_key_temp_file "$config" split-contract-deploy-key)" || return 1
    gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
    soraswap_require_positive_integer_setting "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      return 1
    }
    fee_payment_file="$(jq -cn \
      --argjson gas_limit "$gas_limit" \
      '{payer: "authority", value: {charge_limits: [], gas_limit: $gas_limit}}' \
      | soraswap_secret_temp_from_stdin split-contract-deploy-fee-payment)" || {
        soraswap_secure_unlink_owned_file "$private_key_file" || true
        return 1
      }
    split_status=0
    {
      if split_output_raw="$(split_contract_deploy_cli \
        --config "$config" \
        --authority "$SORASWAP_AUTHORITY" \
        --private-key-file "$private_key_file" \
        --code-file "$code_file" \
        --contract-address "$predicted_address" \
        --contract-alias "$contract_alias" \
        --dataspace "$dataspace" \
        --chain-discriminant "$chain_discriminant" \
        --deploy-nonce "$deploy_nonce" \
        --fee-payment-json "$fee_payment_file" 2>&1)"; then
        split_status=0
      else
        split_status=$?
      fi
    } always {
      if ! soraswap_secure_unlink_owned_files "$private_key_file" "$fee_payment_file"; then
        split_status=1
      fi
      private_key_file=""
      fee_payment_file=""
    }
    if (( split_status != 0 )); then
        redacted_output="$(soraswap_redact_sensitive_text "$split_output_raw")"
        if [[ "$split_output_raw" == *"--private-key-file"* && "$split_output_raw" == *("unexpected argument"|"unknown option"|"unrecognised option")* ]]; then
          redacted_output="$redacted_output
split_contract_deploy lacks required --private-key-file support; refusing inline private key fallback"
        fi
        if [[ "$split_output_raw" == *"--fee-payment-json"* && "$split_output_raw" == *("unexpected argument"|"unknown option"|"unrecognised option")* ]]; then
          redacted_output="$redacted_output
split_contract_deploy lacks required --fee-payment-json support; refusing an unsigned fee-selection fallback"
        fi
        health_status=0
        if (( split_status == 75 )); then
          health_status="$split_status"
        else
          soraswap_stop_if_public_transport_health_degraded \
            "$config" \
            "contract deploy $contract_key split fallback transport" \
            "$split_output_raw" || health_status=$?
        fi
        if (( health_status != 0 )); then
          deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
            --arg contract_key "$contract_key" \
            --arg predicted_address "$predicted_address" \
            --arg error "$redacted_output" \
            '{contract_key: $contract_key, stage: "split_fallback_public_health", contract_address: $predicted_address, error: $error}')"
          echo "$redacted_output" >&2
          return "$health_status"
        fi
        deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
          --arg contract_key "$contract_key" \
          --arg predicted_address "$predicted_address" \
          --arg error "$redacted_output" \
          '{contract_key: $contract_key, stage: "split_fallback", contract_address: $predicted_address, error: $error}')"
        echo "$redacted_output" >&2
        return 1
    fi
    if ! split_output="$(extract_last_json_object <<<"$split_output_raw")"; then
      redacted_output="$(soraswap_redact_sensitive_text "$split_output_raw")"
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg output "$redacted_output" \
        '{contract_key: $contract_key, stage: "split_fallback_parse", contract_address: $contract_address, output: $output}')"
      echo "split deploy output for $contract_key did not end in JSON: $redacted_output" >&2
      return 1
    fi
    if ! jq -e \
      --arg chain_id "$expected_chain_id" \
      --argjson chain_discriminant "$chain_discriminant" \
      --arg dataspace "$dataspace" \
      --arg contract_address "$predicted_address" \
      --arg contract_alias "$contract_alias" \
      --arg contract_subject "$predicted_subject" \
      --arg code_hash_hex "$expected_code_hash" \
      --argjson deploy_nonce "$deploy_nonce" \
      '
        .ok == true
        and .submitted == true
        and .chain_id == $chain_id
        and .chain_discriminant == $chain_discriminant
        and .dataspace == $dataspace
        and .contract_address == $contract_address
        and .contract_alias == $contract_alias
        and .contract_subject_account == $contract_subject
        and .deploy_nonce == $deploy_nonce
        and .next_deploy_nonce == ($deploy_nonce + 1)
        and .expected_previous_contract_address == null
        and ((.code_hash_hex | ascii_downcase) == $code_hash_hex)
        and (.commit_tx_hash | type == "string" and test("^(0x)?[0-9A-Fa-f]{64}$"))
      ' <<<"$split_output" >/dev/null; then
      redacted_output="$(soraswap_redact_sensitive_text "$split_output")"
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg response "$redacted_output" \
        '{contract_key: $contract_key, stage: "split_fallback_validate", response: $response}')"
      echo "unexpected split deploy response for $contract_key: $redacted_output" >&2
      return 1
    fi
    response_json="$split_output"
    if confirm_output="$(capture_confirm_contract_deploy_response "$config" "$response_json" "$contract_key" "$expected_code_hash")"; then
      instance_json="$confirm_output"
      deploy_strategy="split_fallback"
    else
      redacted_output="$(soraswap_redact_sensitive_text "$confirm_output")"
      deploy_report_set_contract "$env" "$contract_key" "failed" "$(jq -cn \
        --arg contract_key "$contract_key" \
        --arg contract_address "$predicted_address" \
        --arg response "$split_output" \
        --arg error "$redacted_output" \
        '{contract_key: $contract_key, stage: "split_fallback_confirm", contract_address: $contract_address, response: $response, error: $error}')"
      echo "split deploy completed for $contract_key but confirmation failed: $redacted_output" >&2
      return 1
    fi
  fi

  response_json_compact="$(compact_json_or_fail "$contract_key.response_json" "$response_json")"
  instance_json_compact="$(compact_json_or_fail "$contract_key.instance_json" "$instance_json")"
  generated_at="$(utc_timestamp)"
  record_json="$(jq -cn \
    --arg contract_key "$contract_key" \
    --arg generated_at "$generated_at" \
    --arg environment "$env" \
    --arg contract_source "$(soraswap_display_path "$src")" \
    --arg contract_alias "$contract_alias" \
    --arg dataspace "$dataspace" \
    --arg deploy_strategy "$deploy_strategy" \
    --argjson response "$response_json_compact" \
    --argjson instance "$instance_json_compact" \
    --argjson chain_fingerprint "$chain_fingerprint_json_compact" \
    '{
      contract_key: $contract_key,
      generated_at: $generated_at,
      environment: $environment,
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
  soraswap_write_json_file_atomic "$record_json" "$deploy_out" || return 1
  write_deployment_manifest \
    "$compiled_manifest" \
    "$manifest_out" \
    "$env" \
    "$contract_key" \
    "$generated_at" \
    "$src" \
    "$config" \
    "$(jq -r '.code_hash_hex // empty' <<<"$response_json_compact")" \
    "$(jq -r '.abi_hash_hex // empty' <<<"$response_json_compact")"
  deploy_report_set_contract "$env" "$contract_key" "$deploy_strategy" "$record_json"
}

ensure_client() {
  local config="$1"
  local public_env

  require_file "$config"
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ "$public_env" == "production" ]]; then
    soraswap_require_secure_production_client_config "$config" || return 1
  fi
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
  local assets_json
  local skip_ready_check="${SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK:-0}"
  local onboard_alias=""
  local public_env required_minimum="0"

  soraswap_require_binary_integer_setting "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK" "$skip_ready_check" || return 1
  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  if [[ "$public_env" == "production" ]]; then
    required_minimum="$(soraswap_production_min_fee_balance)" || return 1
    if [[ "$skip_ready_check" == "1" ]]; then
      echo "SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK is not permitted for production" >&2
      return 1
    fi
  fi

  fee_label="$(fee_asset_label_for_config "$config")"
  fee_asset_id="$(fee_asset_definition_id_for_config "$config")"

  if [[ "$skip_ready_check" == "1" ]]; then
    echo "skipping public signer readiness check for $account_id"
    return 0
  fi

  if account_exists "$config" "$account_id"; then
    if ! assets_json="$(account_assets_json "$config" "$account_id" 200)"; then
      echo "could not query live assets for public signer $account_id; Torii asset listing is unavailable" >&2
      return 1
    fi
    balance="$(asset_value_from_account_assets_json "$assets_json" "$fee_asset_id")"
    if [[ "$public_env" == "production" ]] && numeric_gte "$balance" "$required_minimum"; then
      echo "production signer ready: $account_id holds $balance of $fee_label ($fee_asset_id), meeting the approved minimum $required_minimum"
      return 0
    elif [[ "$public_env" != "production" ]] && numeric_gt_zero "$balance"; then
      echo "public signer ready: $account_id holds $balance of $fee_label ($fee_asset_id)"
      return 0
    fi
    positive_assets_json="$(positive_asset_balances_from_account_assets_json "$assets_json")"
  fi

  if [[ "$mode" == "autofund" ]] && is_taira_public_config "$config"; then
    if ! account_exists "$config" "$account_id"; then
      try_public_self_register_account "$config" "$account_id" >/dev/null 2>&1 || true
      wait_for_account_exists "$config" "$account_id" 5 1 >/dev/null 2>&1 || true
      if ! account_exists "$config" "$account_id"; then
        onboard_alias="$(public_onboard_alias_for_account "$account_id")"
        try_public_onboard_account "$config" "$account_id" "$onboard_alias" >/dev/null 2>&1 || true
        wait_for_account_exists "$config" "$account_id" 5 1 >/dev/null 2>&1 || true
      fi
    fi
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
    echo "run from repo root: SORASWAP_ALLOW_TESTNET_MUTATIONS=1 SORASWAP_CLIENT_CONFIG=\"$(soraswap_display_path "$config")\" scripts/fund_testnet_signer.sh" >&2
    return 1
  fi

  if [[ "$public_env" == "production" ]]; then
    echo "production signer fee balance is below the approved minimum: $balance < $required_minimum $fee_label ($fee_asset_id)" >&2
  else
    echo "public signer is not funded for deploy/smoke: $account_id" >&2
    echo "fund the configured signer with $fee_label ($fee_asset_id) before running this public environment" >&2
  fi
  return 1
}

ensure_public_testnet_signer_ready() {
  ensure_public_signer_ready "$@"
}

account_has_unit_permission() {
  local config="$1"
  local account_id="$2"
  local permission_name="$3"
  local permissions_json

  permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")" || return 1
  jq -e \
    --arg permission_name "$permission_name" \
    '.[] | select(.name == $permission_name and (.payload == null))' \
    >/dev/null <<<"$permissions_json"
}

account_has_exact_permission_json() {
  local config="$1"
  local account_id="$2"
  local expected_permission_json="$3"
  local permissions_json

  permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")" || return 1
  jq -e \
    --argjson expected "$expected_permission_json" \
    'any(.[]; .name == $expected.name and .payload == $expected.payload)' \
    >/dev/null <<<"$permissions_json"
}

ensure_exact_account_permission_json() {
  local config="$1"
  local account_id="$2"
  local permission_json="$3"
  local permission_name grant_output max_attempts retry_delay attempt

  permission_name="$(jq -er '.name' <<<"$permission_json")" || return 1
  if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    return 0
  fi
  if soraswap_production_operator_permission_grant_forbidden "$config" "$account_id"; then
    echo "production operator permission $permission_name must be preprovisioned; refusing to self-grant" >&2
    return 1
  fi

  max_attempts="${SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS:-6}"
  retry_delay="${SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS" "$retry_delay" || return 1

  attempt=1
  while (( attempt <= max_attempts )); do
    if grant_output="$(printf '%s' "$permission_json" | iroha_cli_with_gas_metadata "$config" account permission grant --id "$account_id" 2>&1)"; then
      if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
        return 0
      fi
      echo "$permission_name grant for $account_id did not become query-visible" >&2
      return 1
    fi
    if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
      return 0
    fi
    if soraswap_permission_grant_duplicate_rejection "$grant_output"; then
      echo "$permission_name already present for $account_id after duplicate grant rejection"
      return 0
    fi
    if soraswap_ledger_submit_error_retryable "$grant_output" && (( attempt < max_attempts )); then
      echo "exact permission grant submit failed transiently for $account_id/$permission_name; retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi
    echo "failed to grant exact $permission_name to $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$grant_output")" >&2
    return 1
  done
  return 1
}

revoke_exact_account_permission_json() {
  local config="$1"
  local account_id="$2"
  local permission_json="$3"
  local permission_name permissions_json revoke_output

  permission_name="$(jq -er '.name' <<<"$permission_json")" || return 1
  if ! permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")"; then
    echo "failed to query exact $permission_name on $account_id before revoke" >&2
    return 1
  fi
  if ! jq -e \
    --argjson expected "$permission_json" \
    'any(.[]; .name == $expected.name and .payload == $expected.payload)' \
    >/dev/null <<<"$permissions_json"; then
    return 0
  fi
  if ! revoke_output="$(printf '%s' "$permission_json" | iroha_cli_with_gas_metadata "$config" account permission revoke --id "$account_id" 2>&1)"; then
    echo "failed to revoke exact $permission_name from $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$revoke_output")" >&2
    return 1
  fi
  if ! permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")"; then
    echo "failed to query exact $permission_name on $account_id after revoke" >&2
    return 1
  fi
  if jq -e \
    --argjson expected "$permission_json" \
    'any(.[]; .name == $expected.name and .payload == $expected.payload)' \
    >/dev/null <<<"$permissions_json"; then
    echo "$permission_name revoke for $account_id did not become query-visible" >&2
    return 1
  fi
  return 0
}

production_operator_permission_readiness_json() {
  local config="$1"
  local authority="$2"
  local permissions_json account_readback_json account_present=false

  account_readback_json="$(exact_account_readback_json "$config" "$authority")" || return 1
  if jq -e '.query_available == true and .matched == true' >/dev/null <<<"$account_readback_json"; then
    account_present=true
  fi

  if ! permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$authority" 2>/dev/null)" \
    || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$permissions_json"; then
    jq -cn \
      --arg authority "$authority" \
      --argjson account_present "$account_present" \
      --argjson account_readback "$account_readback_json" '{
      authority: $authority,
      account_present: $account_present,
      account_readback: $account_readback,
      query_available: false,
      ready: false,
      required: [
        {label: "operator account exact readback", name: "Account", payload: {id: $authority}, present: $account_present},
        {label: "Admin", name: "Admin", payload: null, present: false},
        {label: "AssetOps", name: "AssetOps", payload: null, present: false},
        {label: "CanRegisterTrigger(operator)", name: "CanRegisterTrigger", payload: {authority: $authority}, present: false},
        {label: "CanExecuteTrigger(soraswap_escrow_settle)", name: "CanExecuteTrigger", payload: {trigger: "soraswap_escrow_settle"}, present: false}
      ]
    }'
    return 0
  fi

  jq -c \
    --arg authority "$authority" \
    --argjson account_present "$account_present" \
    --argjson account_readback "$account_readback_json" '
    def unit_permission($name):
      any(.[]; .name == $name and .payload == null);
    def register_trigger_permission:
      any(.[]; .name == "CanRegisterTrigger" and (.payload.authority // "") == $authority);
    def execute_trigger_permission($trigger):
      any(.[]; .name == "CanExecuteTrigger" and (.payload.trigger // "") == $trigger);
    (unit_permission("Admin")) as $admin |
    (unit_permission("AssetOps")) as $asset_ops |
    (register_trigger_permission) as $register_trigger |
    (execute_trigger_permission("soraswap_escrow_settle")) as $execute_escrow |
    {
      authority: $authority,
      account_present: $account_present,
      account_readback: $account_readback,
      query_available: true,
      ready: ($account_present and $admin and $asset_ops and $register_trigger and $execute_escrow),
      required: [
        {label: "operator account exact readback", name: "Account", payload: {id: $authority}, present: $account_present},
        {label: "Admin", name: "Admin", payload: null, present: $admin},
        {label: "AssetOps", name: "AssetOps", payload: null, present: $asset_ops},
        {label: "CanRegisterTrigger(operator)", name: "CanRegisterTrigger", payload: {authority: $authority}, present: $register_trigger},
        {label: "CanExecuteTrigger(soraswap_escrow_settle)", name: "CanExecuteTrigger", payload: {trigger: "soraswap_escrow_settle"}, present: $execute_escrow}
      ]
    }
  ' <<<"$permissions_json"
}

require_production_operator_permissions() {
  local config="$1"
  local authority="${2:-${SORASWAP_AUTHORITY:-}}"
  local public_env readiness_json missing

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ "$public_env" == "production" ]] || return 0
  if [[ -z "$authority" ]]; then
    authority="$(authority_from_config "$config" 2>/dev/null || true)"
  fi
  if [[ -z "$authority" ]]; then
    echo "could not derive the production operator authority for permission verification" >&2
    return 1
  fi

  readiness_json="$(production_operator_permission_readiness_json "$config" "$authority")" || return 1
  if jq -e '.query_available == true and .ready == true' >/dev/null <<<"$readiness_json"; then
    return 0
  fi
  if [[ "$(jq -r '.query_available' <<<"$readiness_json")" != "true" ]]; then
    echo "production operator permissions could not be queried; refusing to self-grant" >&2
    return 1
  fi
  missing="$(jq -r '[.required[] | select(.present != true) | .label] | join(", ")' <<<"$readiness_json")"
  echo "production operator is missing preprovisioned permissions: $missing; refusing to self-grant" >&2
  return 1
}

soraswap_production_operator_permission_grant_forbidden() {
  local config="$1"
  local account_id="$2"
  local public_env operator_authority

  public_env="$(public_env_for_config "$config" 2>/dev/null || true)"
  [[ "$public_env" == "production" ]] || return 1
  operator_authority="${SORASWAP_AUTHORITY:-}"
  if [[ -z "$operator_authority" ]]; then
    operator_authority="$(authority_from_config "$config" 2>/dev/null || true)"
  fi
  [[ -n "$operator_authority" && "$account_id" == "$operator_authority" ]]
}

soraswap_permission_grant_duplicate_rejection() {
  local output="$1"

  case "$output" in
    *"Repeated instruction"*|*'Repetition of `Grant`'*|*'Repetition of \`Grant\`'*)
      return 0
      ;;
  esac

  return 1
}

ensure_unit_account_permission() {
  local config="$1"
  local account_id="$2"
  local permission_name="$3"
  local permission_json grant_output max_attempts retry_delay attempt

  if account_has_unit_permission "$config" "$account_id" "$permission_name"; then
    return 0
  fi
  if soraswap_production_operator_permission_grant_forbidden "$config" "$account_id"; then
    echo "production operator permission $permission_name must be preprovisioned; refusing to self-grant" >&2
    return 1
  fi

  max_attempts="${SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS:-6}"
  retry_delay="${SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS" "$retry_delay" || return 1

  permission_json="$(jq -cn --arg permission_name "$permission_name" '{name: $permission_name, payload: null}')"
  attempt=1
  while (( attempt <= max_attempts )); do
    if grant_output="$(printf '%s' "$permission_json" | iroha_cli_with_gas_metadata "$config" account permission grant --id "$account_id" 2>&1)"; then
      if account_has_unit_permission "$config" "$account_id" "$permission_name"; then
        return 0
      fi
      echo "$permission_name grant for $account_id did not become query-visible" >&2
      return 1
    fi

    if account_has_unit_permission "$config" "$account_id" "$permission_name"; then
      return 0
    fi

    if soraswap_permission_grant_duplicate_rejection "$grant_output"; then
      echo "$permission_name already present for $account_id after duplicate grant rejection"
      return 0
    fi

    if soraswap_ledger_submit_error_retryable "$grant_output" && (( attempt < max_attempts )); then
      echo "permission grant submit failed transiently for $account_id/$permission_name; retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    echo "failed to grant $permission_name to $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$grant_output")" >&2
    return 1
  done

  echo "failed to grant $permission_name to $account_id after $max_attempts attempts" >&2
  return 1
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
  local permission_json grant_output max_attempts retry_delay attempt

  if account_has_can_register_trigger_permission "$config" "$account_id"; then
    return 0
  fi
  if soraswap_production_operator_permission_grant_forbidden "$config" "$account_id"; then
    echo "production operator CanRegisterTrigger permission must be preprovisioned; refusing to self-grant" >&2
    return 1
  fi

  max_attempts="${SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS:-6}"
  retry_delay="${SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS" "$retry_delay" || return 1

  permission_json="$(jq -cn \
    --arg authority "$account_id" \
    '{name: "CanRegisterTrigger", payload: {authority: $authority}}')"
  attempt=1
  while (( attempt <= max_attempts )); do
    if grant_output="$(printf '%s' "$permission_json" | iroha_cli_with_gas_metadata "$config" account permission grant --id "$account_id" 2>&1)"; then
      if account_has_can_register_trigger_permission "$config" "$account_id"; then
        return 0
      fi
      echo "CanRegisterTrigger grant for $account_id did not become query-visible" >&2
      return 1
    fi

    if account_has_can_register_trigger_permission "$config" "$account_id"; then
      return 0
    fi

    if soraswap_permission_grant_duplicate_rejection "$grant_output"; then
      echo "CanRegisterTrigger already present for $account_id after duplicate grant rejection"
      return 0
    fi

    if soraswap_ledger_submit_error_retryable "$grant_output" && (( attempt < max_attempts )); then
      echo "permission grant submit failed transiently for $account_id/CanRegisterTrigger; retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    echo "failed to grant CanRegisterTrigger to $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$grant_output")" >&2
    return 1
  done

  echo "failed to grant CanRegisterTrigger to $account_id after $max_attempts attempts" >&2
  return 1
}

account_has_can_execute_trigger_permission() {
  local config="$1"
  local account_id="$2"
  local trigger_id="$3"
  local permissions_json

  permissions_json="$(iroha_cli_json --config "$config" account permission list --id "$account_id")" || return 1
  jq -e \
    --arg trigger "$trigger_id" \
    '.[] | select(.name == "CanExecuteTrigger" and (.payload.trigger // "") == $trigger)' \
    >/dev/null <<<"$permissions_json"
}

ensure_can_execute_trigger_permission() {
  local config="$1"
  local account_id="$2"
  local trigger_id="$3"
  local permission_json grant_output max_attempts retry_delay attempt

  if account_has_can_execute_trigger_permission "$config" "$account_id" "$trigger_id"; then
    return 0
  fi
  if soraswap_production_operator_permission_grant_forbidden "$config" "$account_id"; then
    echo "production operator CanExecuteTrigger($trigger_id) permission must be preprovisioned; refusing to self-grant" >&2
    return 1
  fi

  max_attempts="${SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS:-6}"
  retry_delay="${SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS:-3}"
  soraswap_require_positive_integer_setting "SORASWAP_LEDGER_SUBMIT_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_LEDGER_SUBMIT_RETRY_DELAY_SECS" "$retry_delay" || return 1

  permission_json="$(jq -cn \
    --arg trigger "$trigger_id" \
    '{name: "CanExecuteTrigger", payload: {trigger: $trigger}}')"
  attempt=1
  while (( attempt <= max_attempts )); do
    if grant_output="$(printf '%s' "$permission_json" | iroha_cli_with_gas_metadata "$config" account permission grant --id "$account_id" 2>&1)"; then
      if account_has_can_execute_trigger_permission "$config" "$account_id" "$trigger_id"; then
        return 0
      fi
      echo "CanExecuteTrigger grant for $account_id on $trigger_id did not become query-visible" >&2
      return 1
    fi

    if account_has_can_execute_trigger_permission "$config" "$account_id" "$trigger_id"; then
      return 0
    fi

    if soraswap_permission_grant_duplicate_rejection "$grant_output"; then
      echo "CanExecuteTrigger($trigger_id) already present for $account_id after duplicate grant rejection"
      return 0
    fi

    if soraswap_ledger_submit_error_retryable "$grant_output" && (( attempt < max_attempts )); then
      echo "permission grant submit failed transiently for $account_id/CanExecuteTrigger($trigger_id); retrying ($attempt/$max_attempts)" >&2
      sleep "$retry_delay"
      attempt=$(( attempt + 1 ))
      continue
    fi

    echo "failed to grant CanExecuteTrigger($trigger_id) to $account_id" >&2
    printf '%s\n' "$(soraswap_redact_sensitive_text "$grant_output")" >&2
    return 1
  done

  echo "failed to grant CanExecuteTrigger($trigger_id) to $account_id after $max_attempts attempts" >&2
  return 1
}

soraswap_set_trigger_enabled() {
  local config="$1"
  local trigger_id="$2"
  local enabled="$3"
  local command

  case "$enabled" in
    1|true|yes|on)
      command="enable"
      ;;
    0|false|no|off)
      command="disable"
      ;;
    *)
      echo "invalid trigger enabled value for $trigger_id: $enabled" >&2
      return 1
      ;;
  esac

  iroha_cli_with_gas_metadata "$config" trigger "$command" "$trigger_id"
}

soraswap_enable_trigger() {
  soraswap_set_trigger_enabled "$1" "$2" true
}

soraswap_disable_trigger() {
  soraswap_set_trigger_enabled "$1" "$2" false
}

soraswap_expected_trigger_ids_json() {
  local trigger_scope="${1:-${SORASWAP_EXPECTED_TRIGGER_SCOPE:-${SORASWAP_DEPLOY_SCOPE:-${SORASWAP_SMOKE_SCOPE:-full}}}}"

  case "$trigger_scope" in
    foundation)
      jq -cn '[
        "soraswap_epoch_auction_close",
        "soraswap_range_governor_tick",
        "soraswap_escrow_settle"
      ]'
      ;;
    full|"")
      jq -cn '[
        "soraswap_epoch_auction_close",
        "soraswap_twamm_tick",
        "soraswap_range_governor_tick",
        "soraswap_options_lifecycle_tick",
        "soraswap_options_factory_lifecycle_tick",
        "soraswap_cover_lifecycle_tick",
        "soraswap_launchpad_lifecycle_tick",
        "soraswap_vault_lifecycle_tick",
        "soraswap_perps_lifecycle_tick",
        "soraswap_escrow_settle"
      ]'
      ;;
    *)
      echo "unsupported expected trigger scope: $trigger_scope" >&2
      return 2
      ;;
  esac
}

soraswap_trigger_detail_summary_json() {
  local config="$1"
  local trigger_id="$2"
  local output output_json summary

  if output="$(iroha_cli_json --config "$config" trigger get --id "$trigger_id" 2>&1)" \
    && output_json="$(soraswap_first_json_value_from_output_or_null "$output")" \
    && summary="$(jq -ce --arg id "$trigger_id" '
      select(type == "object") | {
        id: (.id // $id),
        repeats: (.repeats // null),
        authority: (.authority // null),
        filter: (.filter // null),
        metadata: (.metadata // {})
      }' <<<"$output_json" 2>/dev/null)"; then
    jq -cn \
      --arg id "$trigger_id" \
      --argjson trigger "$summary" \
      '{id: $id, registered: true, trigger: $trigger}'
    return 0
  fi

  jq -cn \
    --arg id "$trigger_id" \
    --arg error "$(soraswap_redact_sensitive_text "$output")" \
    '{id: $id, registered: false, error: $error}'
}

soraswap_collect_trigger_registration_evidence() {
  local config="$1"
  local expected_json="${2:-}"
  local registered_json active_json details_json missing_json detail trigger_id
  local include_details="${SORASWAP_TRIGGER_EVIDENCE_INCLUDE_DETAILS:-0}"
  local attempt max_attempts retry_delay

  soraswap_require_binary_integer_setting "SORASWAP_TRIGGER_EVIDENCE_INCLUDE_DETAILS" "$include_details" || return 1
  max_attempts="${SORASWAP_TRIGGER_LIST_RETRY_ATTEMPTS:-5}"
  retry_delay="${SORASWAP_TRIGGER_LIST_RETRY_DELAY_SECS:-1}"
  soraswap_require_positive_integer_setting "SORASWAP_TRIGGER_LIST_RETRY_ATTEMPTS" "$max_attempts" || return 1
  soraswap_require_nonnegative_number_setting "SORASWAP_TRIGGER_LIST_RETRY_DELAY_SECS" "$retry_delay" || return 1

  if [[ -z "$expected_json" ]]; then
    expected_json="$(soraswap_expected_trigger_ids_json)"
  fi
  expected_json="$(jq -c 'if type == "array" then . else [] end' <<<"$expected_json" 2>/dev/null || echo '[]')"

  registered_json='[]'
  missing_json="$expected_json"
  attempt=1
  while (( attempt <= max_attempts )); do
    registered_json="$(soraswap_iroha_trigger_list_array_json "$config" 0)"
    missing_json="$(jq -cn \
      --argjson expected "$expected_json" \
      --argjson registered "$registered_json" \
      '$expected - $registered')"
    if jq -e 'length == 0' >/dev/null 2>&1 <<<"$missing_json"; then
      break
    fi
    (( attempt == max_attempts )) && break
    sleep "$retry_delay"
    attempt=$(( attempt + 1 ))
  done

  active_json="$(soraswap_iroha_trigger_list_array_json "$config" 1)"

  details_json='[]'
  if [[ "$include_details" == "1" ]]; then
    while IFS= read -r trigger_id; do
      [[ -z "$trigger_id" ]] && continue
      detail="$(soraswap_trigger_detail_summary_json "$config" "$trigger_id")"
      details_json="$(jq -cn \
        --argjson details "$details_json" \
        --argjson detail "$detail" \
        '$details + [$detail]')"
    done < <(jq -r '.[]' <<<"$expected_json")
  fi

  jq -cn \
    --argjson registered "$registered_json" \
    --argjson active "$active_json" \
    --argjson expected "$expected_json" \
    --argjson details "$details_json" \
    --argjson missing "$missing_json" \
    '{
      registered_triggers: $registered,
      registered_trigger_ids: $registered,
      active_trigger_ids: $active,
      expected_trigger_ids: $expected,
      expected_trigger_details: $details,
      missing_expected_trigger_ids: $missing
    }'
}

soraswap_assert_expected_triggers_registered() {
  local evidence_json="$1"
  local missing

  if jq -e '.missing_expected_trigger_ids | length == 0' >/dev/null 2>&1 <<<"$evidence_json"; then
    return 0
  fi

  missing="$(jq -r '.missing_expected_trigger_ids | join(", ")' <<<"$evidence_json" 2>/dev/null || true)"
  echo "missing expected registered triggers: ${missing:-unknown}" >&2
  return 1
}

soraswap_prove_epoch_auction_native_close() {
  local config="$1"
  local contract_id="$2"
  local gas_limit="${3:-${SORASWAP_SMOKE_GAS_LIMIT:-50000000}}"
  local initial_view initial_result final_view final_result trigger_detail active_triggers_json
  local epoch_status end_slot last_close enabled_ok waited ticked

  if ! initial_view="$(submit_contract_view "$config" "$contract_id" epoch_state "$gas_limit")"; then
    echo "failed to query epoch auction state before native close proof" >&2
    return 1
  fi
  initial_result="$(contract_view_result_json "$initial_view")"
  epoch_status="$(jq -r 'if type == "array" then (.[1] // 0) else 0 end' <<<"$initial_result")"
  end_slot="$(jq -r 'if type == "array" then (.[3] // 0) else 0 end' <<<"$initial_result")"
  if [[ -z "$epoch_status" || "$epoch_status" == "null" || "$epoch_status" != <-> ]]; then
    epoch_status=0
  fi
  if [[ -z "$end_slot" || "$end_slot" == "null" || "$end_slot" != <-> ]]; then
    end_slot=0
  fi

  waited=0
  ticked=0
  if (( epoch_status == 1 && end_slot > 0 )); then
    soraswap_wait_for_block_height_at_least \
      "$config" \
      "$end_slot" \
      "epoch auction native close" \
      "${SORASWAP_EPOCH_AUCTION_CLOSE_WAIT_ATTEMPTS:-120}" \
      1
    waited=1
    soraswap_submit_block_height_tick "$config" "epoch-auction-native-close" || true
    ticked=1
  fi

  if ! final_view="$(submit_contract_view "$config" "$contract_id" epoch_state "$gas_limit")"; then
    echo "failed to query epoch auction state after native close proof" >&2
    return 1
  fi
  final_result="$(contract_view_result_json "$final_view")"
  trigger_detail="$(soraswap_trigger_detail_summary_json "$config" "soraswap_epoch_auction_close")"
  active_triggers_json="$(iroha_cli_json --config "$config" trigger list all --active 2>/dev/null || echo '[]')"
  active_triggers_json="$(jq -c 'if type == "array" then . else [] end' <<<"$active_triggers_json" 2>/dev/null || echo '[]')"
  epoch_status="$(jq -r 'if type == "array" then (.[1] // 0) else 0 end' <<<"$final_result")"
  last_close="$(jq -r 'if type == "array" then (.[10] // 0) else 0 end' <<<"$final_result")"
  if [[ -z "$epoch_status" || "$epoch_status" == "null" || "$epoch_status" != <-> ]]; then
    epoch_status=0
  fi
  if [[ -z "$last_close" || "$last_close" == "null" || "$last_close" != <-> ]]; then
    last_close=0
  fi

  if (( epoch_status != 2 )); then
    echo "epoch auction native trigger did not close the epoch; status=$epoch_status" >&2
    return 1
  fi
  if (( end_slot > 0 && last_close < end_slot )); then
    echo "epoch auction close slot $last_close is before end slot $end_slot" >&2
    return 1
  fi
  if jq -e --arg trigger_id "soraswap_epoch_auction_close" 'index($trigger_id) == null' \
    >/dev/null 2>&1 <<<"$active_triggers_json"; then
    enabled_ok=1
  else
    enabled_ok=0
  fi
  if (( enabled_ok != 1 )); then
    echo "epoch auction native trigger remained active after close" >&2
    return 1
  fi

  jq -cn \
    --argjson before "$initial_result" \
    --argjson after "$final_result" \
    --argjson trigger "$trigger_detail" \
    --argjson active_triggers "$active_triggers_json" \
    --argjson end_slot "$end_slot" \
    --argjson waited "$waited" \
    --argjson ticked "$ticked" \
    '{
      ok: true,
      end_slot: $end_slot,
      waited_for_due_slot: ($waited == 1),
      submitted_final_tick: ($ticked == 1),
      before_state: $before,
      after_state: $after,
      trigger: $trigger,
      active_trigger_ids_after_close: $active_triggers
    }'
}

soraswap_execute_trigger() {
  local config="$1"
  local trigger_id="$2"
  local args_json="${3:-}"
  local output tx_hash timeout_ms poll_interval_ms

  if [[ -z "$args_json" ]]; then
    args_json="{}"
  fi

  args_json="$(compact_json_or_fail "trigger args" "$args_json")" || return 1
  timeout_ms="${SORASWAP_TRIGGER_EXECUTE_TIMEOUT_MS:-$(( SORASWAP_TX_COMMITTED_WAIT_SECS * 1000 ))}"
  poll_interval_ms="${SORASWAP_TRIGGER_EXECUTE_POLL_INTERVAL_MS:-1000}"
  soraswap_require_nonnegative_integer_setting "SORASWAP_TRIGGER_EXECUTE_TIMEOUT_MS" "$timeout_ms" || return 1
  soraswap_require_positive_integer_setting "SORASWAP_TRIGGER_EXECUTE_POLL_INTERVAL_MS" "$poll_interval_ms" || return 1
  if ! output="$(iroha_cli_with_gas_metadata "$config" trigger execute "$trigger_id" \
    --args-json "$args_json" \
    --timeout-ms "$timeout_ms" \
    --poll-interval-ms "$poll_interval_ms")"; then
    printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
    return 1
  fi
  tx_hash="$(jq -er '.hash // .submit.tx_hash_hex // .tx_hash_hex // empty' <<<"$output" 2>/dev/null || true)"
  if [[ -z "$tx_hash" ]]; then
    printf '%s\n' "$output"
  else
    printf '%s\n' "$tx_hash"
  fi
}

soraswap_collect_trigger_completions() {
  local config="$1"
  local trigger_id="${2:-}"
  local timeout_ms="${3:-5000}"
  local limit="${4:-10}"
  local output exit_code args tmp_output

  soraswap_require_nonnegative_integer_setting "trigger completion timeout_ms" "$timeout_ms" || return 1
  soraswap_require_positive_integer_setting "trigger completion limit" "$limit" || return 1

  args=(trigger completed list --timeout-ms "$timeout_ms" --limit "$limit")
  if [[ -n "$trigger_id" ]]; then
    args+=(--id "$trigger_id")
  fi
  tmp_output="$(mktemp "${TMPDIR:-/tmp}/soraswap-trigger-completions.XXXXXX")" || return 1
  if iroha_cli_json --config "$config" "${args[@]}" >"$tmp_output" 2>/dev/null; then
    if jq -e . "$tmp_output" >/dev/null 2>&1; then
      jq -c . "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi
    output="$(cat "$tmp_output" 2>/dev/null || true)"
    rm -f "$tmp_output"
    jq -cn \
      --arg trigger_id "$trigger_id" \
      --arg output "$(soraswap_redact_sensitive_text "$output")" \
      --argjson timeout_ms "$timeout_ms" \
      --argjson limit "$limit" \
      '{
        trigger_id: (if $trigger_id == "" then null else $trigger_id end),
        timeout_ms: $timeout_ms,
        limit: $limit,
        count: 0,
        completions: [],
        error: "trigger completion list did not return valid JSON",
        output: $output
      }'
    return 0
  fi
  exit_code=$?
  output="$(cat "$tmp_output" 2>/dev/null || true)"
  rm -f "$tmp_output"
  jq -cn \
    --arg trigger_id "$trigger_id" \
    --arg error "$(soraswap_redact_sensitive_text "$output")" \
    --argjson status "$exit_code" \
    --argjson timeout_ms "$timeout_ms" \
    --argjson limit "$limit" \
    '{
      trigger_id: (if $trigger_id == "" then null else $trigger_id end),
      timeout_ms: $timeout_ms,
      limit: $limit,
      count: 0,
      completions: [],
      error: $error,
      exit_status: $status
    }'
}

soraswap_start_trigger_completion_capture() {
  local config="$1"
  local trigger_id="$2"
  local timeout_ms="$3"
  local limit="$4"
  local output_path="$5"
  local error_path="$6"

  soraswap_require_nonnegative_integer_setting "trigger completion timeout_ms" "$timeout_ms" || return 1
  soraswap_require_positive_integer_setting "trigger completion limit" "$limit" || return 1

  iroha_cli_json --config "$config" trigger completed watch \
    --id "$trigger_id" \
    --timeout-ms "$timeout_ms" \
    --limit "$limit" \
    > "$output_path" 2> "$error_path" &
  SORASWAP_TRIGGER_COMPLETION_CAPTURE_PID="$!"
}

soraswap_finish_trigger_completion_capture() {
  local pid="$1"
  local trigger_id="$2"
  local timeout_ms="$3"
  local limit="$4"
  local output_path="$5"
  local error_path="$6"
  local exit_code output error

  if wait "$pid"; then
    exit_code=0
  else
    exit_code=$?
  fi
  output="$(cat "$output_path" 2>/dev/null || true)"
  error="$(cat "$error_path" 2>/dev/null || true)"
  rm -f "$output_path" "$error_path"
  soraswap_require_nonnegative_integer_setting "trigger completion timeout_ms" "$timeout_ms" || return 1
  soraswap_require_positive_integer_setting "trigger completion limit" "$limit" || return 1
  if [[ "$exit_code" -eq 0 && -n "$output" ]] && jq -e . >/dev/null 2>&1 <<<"$output"; then
    if jq -e 'type == "object" and (has("events") or has("completions"))' >/dev/null 2>&1 <<<"$output"; then
      printf '%s\n' "$output"
    else
      jq -cn \
        --arg trigger_id "$trigger_id" \
        --argjson timeout_ms "$timeout_ms" \
        --argjson limit "$limit" \
        --slurpfile event <(printf '%s\n' "$output") \
        '{
          trigger_id: $trigger_id,
          timeout_ms: $timeout_ms,
          limit: $limit,
          count: ($event | length),
          events: $event,
          completions: []
        }'
    fi
    return 0
  fi
  jq -cn \
    --arg trigger_id "$trigger_id" \
    --arg error "$(soraswap_redact_sensitive_text "$error")" \
    --arg output "$(soraswap_redact_sensitive_text "$output")" \
    --argjson status "$exit_code" \
    --argjson timeout_ms "$timeout_ms" \
    --argjson limit "$limit" \
    '{
      trigger_id: $trigger_id,
      timeout_ms: $timeout_ms,
      limit: $limit,
      count: 0,
      events: [],
      completions: [],
      error: $error,
      raw_output: $output,
      exit_status: $status
    }'
}

soraswap_trigger_completion_capture_warmup_seconds() {
  local value="${SORASWAP_TRIGGER_COMPLETION_CAPTURE_WARMUP_SECONDS:-1}"
  soraswap_require_nonnegative_number_setting "SORASWAP_TRIGGER_COMPLETION_CAPTURE_WARMUP_SECONDS" "$value" || return 1
  printf '%s\n' "$value"
}

account_address_canonical_hex() {
  local config="$1"
  local account_literal="$2"
  local network_prefix

  network_prefix="$(network_prefix_for_config "$config")"

  iroha_cli --config "$config" --output-format text tools address convert \
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

  if ! public_env_for_config "$config" >/dev/null 2>&1; then
    payment_gross="$(/usr/bin/python3 - "$payment_gross" <<'PY'
from decimal import Decimal, ROUND_CEILING
import sys

value = Decimal(sys.argv[1])
print(value.to_integral_value(rounding=ROUND_CEILING))
PY
)"
  fi

  if output="$(
    iroha_cli_with_gas_metadata "$config" app sns register \
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
    tmp="$(mktemp "${TMPDIR:-/tmp}/soraswap-sns-register.XXXXXX")"
    http_code="$(soraswap_curl_for_config "$config" -sS -o "$tmp" -w '%{http_code}' \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
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
    echo "sns register fallback failed for ${selector_literal}: HTTP ${http_code}: $(soraswap_redact_sensitive_text "$(cat "$tmp" 2>/dev/null || true)")" >&2
    rm -f "$tmp"
    return 1
  fi

  printf '%s\n' "$(soraswap_redact_sensitive_text "$output")" >&2
  return 1
}
