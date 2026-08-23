#!/bin/zsh
set -euo pipefail

requested_soraswap_root="${SORASWAP_ROOT:-}"
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
if [[ -n "$requested_soraswap_root" ]]; then
  SORASWAP_ROOT="$requested_soraswap_root"
fi

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "taira_preflight.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac
export SORASWAP_PUBLIC_ENV="$public_env"
preflight_timeout_secs="${SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS:-10}"
soraswap_require_nonnegative_number_setting "SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS" "$preflight_timeout_secs" || exit 1
public_preflight_queued_stall_max_ms="${SORASWAP_PUBLIC_PREFLIGHT_QUEUED_STALL_MAX_MS:-180000}"
soraswap_require_nonnegative_integer_setting "SORASWAP_PUBLIC_PREFLIGHT_QUEUED_STALL_MAX_MS" "$public_preflight_queued_stall_max_ms" || exit 1
if (( ! ${+SORASWAP_SKIP_IROHA_CLI_BUILD} )); then
  export SORASWAP_SKIP_IROHA_CLI_BUILD=1
fi
case "$public_env" in
  testnet)
    public_label="taira"
    public_display_label="Taira"
    setup_config_example="config/testnet/taira.client.toml.example"
    setup_config_path="${SORASWAP_CLIENT_CONFIG:-$DEFAULT_TESTNET_CLIENT}"
    setup_target="taira-preflight"
    chain_id="${SORASWAP_TESTNET_CHAIN_ID:-$SORASWAP_TESTNET_CHAIN_ID_DEFAULT}"
    chain_id_setup_hint="SORASWAP_TESTNET_CHAIN_ID"
    mutation_gate_var="SORASWAP_ALLOW_TESTNET_MUTATIONS"
    nested_probe_setup_command="SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe"
    ;;
  production)
    public_label="production"
    public_display_label="production"
    setup_config_example="config/production/production.client.toml.example"
    setup_config_path="${SORASWAP_CLIENT_CONFIG:-${SORASWAP_PRODUCTION_CLIENT_CONFIG:-$DEFAULT_PRODUCTION_CLIENT}}"
    setup_target="production-preflight"
    chain_id="${SORASWAP_PRODUCTION_CHAIN_ID:-}"
    chain_id_setup_hint="SORASWAP_PRODUCTION_CHAIN_ID"
    mutation_gate_var="SORASWAP_ALLOW_PRODUCTION_MUTATIONS"
    nested_probe_setup_command="SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe"
    ;;
esac
config="$(client_config_or_default "$public_env" 2>/dev/null || printf '%s' "$setup_config_path")"
config_report_path="$(soraswap_display_path "$config")"
timestamp="$(utc_timestamp)"
evidence_dir="$(deployments_dir_for_env "$public_env")"
report_dir="${SORASWAP_PUBLIC_PREFLIGHT_REPORT_DIR:-}"
if [[ -z "$report_dir" ]]; then
  case "$public_env" in
    testnet)
      report_dir="${SORASWAP_TAIRA_PREFLIGHT_REPORT_DIR:-$evidence_dir}"
      ;;
    production)
      report_dir="${SORASWAP_PRODUCTION_PREFLIGHT_REPORT_DIR:-$evidence_dir}"
      ;;
  esac
fi
latest_report="$report_dir/preflight.latest.json"
timestamped_report="$report_dir/preflight.${timestamp}.json"
mkdir -p "$report_dir"

typeset -a blockers
typeset -a warnings
blockers=()
warnings=()

add_blocker() {
  blockers+=("$(soraswap_redact_sensitive_text "$1")")
}

add_warning() {
  warnings+=("$(soraswap_redact_sensitive_text "$1")")
}

print_setup_hint() {
  cat <<EOF
next setup:
  cp $setup_config_example $config_report_path
  # edit the copied file with real untracked $public_label credentials
  chmod 600 $config_report_path
  export SORASWAP_CLIENT_CONFIG="$config_report_path"
  export $mutation_gate_var=1
  # Optional: override the default oracle provider, which is the client config signer.
  export SORASWAP_ORACLE_PUBLIC_KEY_HEX=<public oracle key>
  export SORASWAP_ORACLE_PRIVATE_KEY_HEX=<private oracle key>
  # Production additionally requires an explicit account chain_discriminant and approved fee minimum.
  export SORASWAP_PRODUCTION_MIN_FEE_BALANCE=<approved minimum>
  make $setup_target
EOF
}

json_array_from_args() {
  if (( $# == 0 )); then
    printf '[]\n'
    return 0
  fi
  printf '%s\0' "$@" | jq -Rs 'split("\u0000")[:-1]'
}

http_status_for() {
  local url="$1"
  local http_status
  http_status="$(soraswap_curl_for_config "${preflight_request_config:-}" -sS -o /dev/null --max-time "$preflight_timeout_secs" -w '%{http_code}' "$url" 2>/dev/null || true)"
  if [[ -z "$http_status" ]]; then
    printf '000'
  else
    printf '%s' "$http_status"
  fi
}

json_get_for() {
  local url="$1"
  soraswap_curl_for_config "${preflight_request_config:-}" -fsS --max-time "$preflight_timeout_secs" "$url" 2>/dev/null || true
}

bool_json=false
config_exists=false
config_tracked=false
config_has_placeholders=false
config_env_mismatch=false
config_security_valid=true
config_usable=false
config_path_environment=""
mutation_gate=false
oracle_public_key_present=false
oracle_private_key_present=false
oracle_keypair_verified=false
oracle_public_key_source="missing"
oracle_private_key_source="missing"
authority=""
authority_source="unset"
authority_derivable=false
signer_account_exists=false
signer_assets_query_available=false
signer_fee_balance=""
signer_fee_asset_id=""
signer_fee_asset_label=""
production_min_fee_balance=""
account_chain_discriminant=""
operator_permissions_json="null"
preflight_request_config=""
if [[ "$public_env" == "production" ]]; then
  config_security_valid=false
fi
chain_fingerprint_json="null"
chain_fingerprint_available=false
chain_snapshot_exists=false
chain_snapshot_matches="null"
chain_snapshot_environment=""
current_block_height=""
health_snapshot_json="null"
health_issues_json="[]"
health_summary=""
direct_validator_health_json="null"
direct_torii_port_health_json="null"
nested_probe_exists=false
nested_probe_matches_current_chain="null"
nested_probe_supported="null"
nested_probe_summary=""
nested_probe_health_summary=""
skip_existing_nested_probe_check="${SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK:-0}"
case "$skip_existing_nested_probe_check" in
  0|1)
    ;;
  *)
    add_blocker "SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK must be 0 or 1; got '$skip_existing_nested_probe_check'"
    skip_existing_nested_probe_check=0
    ;;
esac

if [[ -f "$config" ]]; then
  config_exists=true
else
  add_blocker "real $public_display_label client config is missing: $config_report_path"
fi

if [[ "$config_exists" == "true" ]]; then
  config_abs="${config:A}"
  config_path_environment="$(public_env_for_config_path "$config" 2>/dev/null || true)"
  if [[ -n "$config_path_environment" && "$config_path_environment" != "$public_env" ]]; then
    config_env_mismatch=true
    add_blocker "refusing to use a $config_path_environment client config for $public_env preflight: $config_report_path"
  fi
  if [[ "$public_env" == "testnet" && "$config_env_mismatch" == "false" ]]; then
    testnet_chain_blocker="$(testnet_client_config_unexpected_chain_blocker_message "$config" 2>/dev/null || true)"
    if [[ -n "$testnet_chain_blocker" ]]; then
      add_blocker "$testnet_chain_blocker"
    fi
  fi
  if [[ "$public_env" == "production" && "$config_env_mismatch" == "false" ]]; then
    config_security_valid=false
    if config_security_error="$(soraswap_require_secure_production_client_config "$config" 2>&1)"; then
      config_security_valid=true
      production_taira_chain_blocker="$(production_client_config_taira_chain_blocker_message "$config" 2>/dev/null || true)"
      if [[ -n "$production_taira_chain_blocker" ]]; then
        add_blocker "$production_taira_chain_blocker"
      fi
    else
      add_blocker "${config_security_error:-production client config failed secure-file validation}"
    fi
  fi

  if [[ "$config_abs" == "$SORASWAP_ROOT/"* ]]; then
    config_rel="${config_abs#$SORASWAP_ROOT/}"
    if git -C "$SORASWAP_ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
      config_tracked=true
      add_blocker "$public_display_label client config must be untracked: $config_rel"
    fi
  fi

  if [[ "$config_security_valid" == "true" && "$config_abs" == *.example ]]; then
    config_has_placeholders=true
    add_blocker "$public_display_label client config points at an example file: $config_report_path"
  elif [[ "$config_security_valid" == "true" ]] && soraswap_client_config_has_placeholder_values "$config_abs"; then
    config_has_placeholders=true
    add_blocker "$public_display_label client config still contains example credentials or local endpoints"
  fi
fi

if [[ "$config_exists" == "true" \
  && "$config_has_placeholders" == "false" \
  && "$config_env_mismatch" == "false" \
  && "$config_security_valid" == "true" ]]; then
  config_usable=true
  preflight_request_config="$config"
  if ! account_chain_discriminant="$(chain_discriminant_for_env_config "$public_env" "$config" 2>/dev/null)"; then
    account_chain_discriminant=""
    add_blocker "$public_display_label account chain discriminant is unavailable; set it explicitly in [account].chain_discriminant"
  fi
fi

if [[ "$public_env" == "production" ]]; then
  if ! production_minimum_error="$(soraswap_production_min_fee_balance 2>&1)"; then
    add_blocker "$production_minimum_error"
  else
    production_min_fee_balance="$production_minimum_error"
  fi
fi

torii_root="${SORASWAP_TORII_URL:-}"
if [[ -z "$torii_root" && "$config_usable" == "true" ]]; then
  torii_root="$(torii_url_from_config "$config" 2>/dev/null || true)"
fi
if [[ -z "$torii_root" ]]; then
  case "$public_env" in
    testnet)
      torii_root="https://taira.sora.org/"
      add_warning "using default Taira Torii root because no client config is available"
      ;;
    production)
      torii_root="http://127.0.0.1.invalid"
      add_blocker "production Torii root is unavailable; set SORASWAP_TORII_URL or provide a production client config"
      ;;
  esac
fi
torii_root="${torii_root%/}"
torii_root_report="$(soraswap_redact_sensitive_text "$torii_root")"

mcp_status="$(http_status_for "$torii_root/v1/mcp")"
mcp_payload_json="$(json_get_for "$torii_root/v1/mcp")"
mcp_enabled="null"
mcp_metadata_valid=false
mcp_protocol_version=""
mcp_server_name=""
mcp_server_version=""
mcp_tool_count=0
mcp_toolset_version=""
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$mcp_payload_json"; then
  mcp_payload_json="null"
else
  mcp_enabled="$(jq -c '.enabled // null' <<<"$mcp_payload_json")"
  mcp_protocol_version="$(jq -r '.protocolVersion // ""' <<<"$mcp_payload_json")"
  mcp_server_name="$(jq -r '.serverInfo.name // ""' <<<"$mcp_payload_json")"
  mcp_server_version="$(jq -r '.serverInfo.version // ""' <<<"$mcp_payload_json")"
  mcp_tool_count="$(jq -r '.capabilities.tools.count // 0' <<<"$mcp_payload_json")"
  if [[ ! "$mcp_tool_count" =~ '^[0-9]+$' ]]; then
    mcp_tool_count=0
  fi
  mcp_toolset_version="$(jq -r '.capabilities.tools.toolsetVersion // ""' <<<"$mcp_payload_json")"
  if jq -e '
    (.enabled == true)
    and ((.protocolVersion // "") | type == "string" and length > 0)
    and ((.serverInfo.name // "") | type == "string" and length > 0)
    and ((.serverInfo.version // "") | type == "string" and length > 0)
    and ((.capabilities.tools.count // 0) | type == "number" and . > 0)
    and ((.capabilities.tools.toolsetVersion // "") | type == "string" and length > 0)
    and ((.capabilities.tools.listChanged // null) | type == "boolean")
  ' >/dev/null 2>&1 <<<"$mcp_payload_json"; then
    mcp_metadata_valid=true
  fi
fi
faucet_status="$(http_status_for "$torii_root/v1/accounts/faucet/puzzle")"
block_1_json="$(json_get_for "$torii_root/v1/explorer/blocks/1")"
current_block_height="$(json_get_for "$torii_root/status/blocks" | tr -d '\r\n[:space:]')"
if [[ "$config_usable" == "true" ]]; then
  health_snapshot_json="$(soraswap_public_chain_health_snapshot_json "$config" 2>/dev/null || printf 'null')"
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$health_snapshot_json"; then
    health_snapshot_json="null"
  fi
  if [[ "$health_snapshot_json" != "null" ]]; then
    health_summary="$(soraswap_public_chain_health_summary_text_from_json "$health_snapshot_json" 2>/dev/null || true)"
  fi
fi
if [[ "$public_env" == "testnet" && "${SORASWAP_TAIRA_DIRECT_VALIDATOR_HEALTH:-1}" != "0" ]]; then
  direct_validator_dns_records_path="${SORASWAP_TAIRA_DNS_RECORDS_JSON:-$SORASWAP_IROHA_ROOT/configs/soranexus/taira/dns_records.json}"
  if [[ -s "$direct_validator_dns_records_path" ]]; then
    direct_validator_health_json="$(soraswap_taira_direct_validator_health_json "$direct_validator_dns_records_path" 2>/dev/null || printf 'null')"
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$direct_validator_health_json"; then
      direct_validator_health_json="null"
    fi
  fi
fi
if [[ "$public_env" == "testnet" && -n "${SORASWAP_TAIRA_DIRECT_TORII_HOST:-}" && -n "${SORASWAP_TAIRA_DIRECT_TORII_PORTS:-}" ]]; then
  direct_torii_port_health_json="$(soraswap_taira_direct_torii_port_health_json "$SORASWAP_TAIRA_DIRECT_TORII_HOST" "$SORASWAP_TAIRA_DIRECT_TORII_PORTS" 2>/dev/null || printf 'null')"
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$direct_torii_port_health_json"; then
    direct_torii_port_health_json="null"
  fi
fi

if [[ "$config_usable" == "true" ]]; then
  chain_id="$(chain_id_override_for_config "$config" 2>/dev/null || true)"
  if [[ -z "$chain_id" ]]; then
    chain_id="$(config_chain_id_from_config "$config" 2>/dev/null || true)"
  fi
fi
if [[ -z "$chain_id" ]]; then
  add_blocker "$public_display_label chain id is unavailable; set $chain_id_setup_hint or provide chain in the client config"
fi

if [[ -n "$block_1_json" && -n "$chain_id" ]] && jq -e . >/dev/null 2>&1 <<<"$block_1_json"; then
  block_1_hash="$(jq -er '.hash // empty' <<<"$block_1_json" 2>/dev/null || true)"
  if [[ -n "$block_1_hash" ]]; then
    chain_fingerprint_json="$(jq -cn \
      --arg torii_url "$torii_root_report" \
      --arg chain "$chain_id" \
      --arg block_1_hash "$block_1_hash" \
      '{torii_url: $torii_url, chain: $chain, block_1_hash: $block_1_hash}')"
    chain_fingerprint_available=true
  fi
fi

if [[ "$chain_fingerprint_available" != "true" ]]; then
  if [[ -z "$chain_id" ]]; then
    add_warning "could not assemble live chain fingerprint because $chain_id_setup_hint/client config chain is unavailable"
  else
    add_warning "could not fetch live chain fingerprint from $torii_root/v1/explorer/blocks/1"
  fi
fi

chain_snapshot_path="$(chain_snapshot_latest_path_for_env "$public_env")"
if [[ -s "$chain_snapshot_path" ]]; then
  chain_snapshot_exists=true
  chain_snapshot_environment="$(jq -er '.environment // empty' "$chain_snapshot_path" 2>/dev/null || true)"
  if ! jq -e '
    ((.generated_at // "") | type == "string" and length > 0)
    and ((.torii_url // "") | type == "string" and length > 0)
    and ((.chain // "") | type == "string" and length > 0)
    and ((.block_1_hash // "") | type == "string" and length > 0)
  ' "$chain_snapshot_path" >/dev/null 2>&1; then
    chain_snapshot_matches=false
    add_blocker "saved chain.latest.json must include generated_at, torii_url, chain, and block_1_hash"
  elif [[ -z "$chain_snapshot_environment" ]]; then
    chain_snapshot_matches=false
    add_blocker "saved chain.latest.json must record environment \"$public_env\""
  elif [[ "$chain_snapshot_environment" != "$public_env" ]]; then
    chain_snapshot_matches=false
    add_blocker "saved chain.latest.json was recorded for environment \"$chain_snapshot_environment\", not \"$public_env\""
  elif [[ "$chain_fingerprint_available" == "true" ]]; then
    if chain_snapshot_matches_json "$chain_snapshot_path" "$chain_fingerprint_json" "$public_env"; then
      chain_snapshot_matches=true
    else
      chain_snapshot_matches=false
      add_blocker "saved chain.latest.json does not match the live $public_display_label block-1 fingerprint"
    fi
  fi
else
  case "$public_env" in
    testnet)
      add_blocker "saved chain.latest.json is missing for $public_display_label; run make refresh-testnet-chain"
      ;;
    production)
      add_blocker "saved chain.latest.json is missing for $public_display_label; run make refresh-production-chain"
      ;;
  esac
fi

if [[ "$chain_fingerprint_available" != "true" && "$chain_snapshot_exists" == "true" && "$chain_snapshot_matches" != "false" ]]; then
  saved_chain_fingerprint_json="$(current_or_saved_chain_fingerprint_json_for_env "$public_env" 2>/dev/null || printf 'null')"
  if chain_fingerprint_json_is_complete "$saved_chain_fingerprint_json"; then
    chain_fingerprint_json="$saved_chain_fingerprint_json"
    chain_fingerprint_available=true
    chain_snapshot_matches=true
    add_warning "using saved chain.latest.json fingerprint because live $public_display_label block-1 fingerprint is unavailable"
  fi
fi

if [[ "$mcp_status" == "404" ]]; then
  add_blocker "native Torii MCP is not enabled at $torii_root/v1/mcp"
elif [[ "$mcp_status" == "000" ]]; then
  add_blocker "could not reach native Torii MCP at $torii_root/v1/mcp"
elif [[ "$mcp_status" != "200" ]]; then
  add_blocker "native Torii MCP returned HTTP $mcp_status at $torii_root/v1/mcp"
elif [[ "$mcp_payload_json" == "null" ]]; then
  add_blocker "native Torii MCP returned HTTP 200 without a JSON capability document"
elif [[ "$mcp_enabled" != "true" ]]; then
  add_blocker "native Torii MCP capability document reports enabled=false"
elif [[ "$mcp_metadata_valid" != "true" ]]; then
  add_blocker "native Torii MCP capability metadata or advertised tool surface is incomplete"
fi

if [[ "$public_env" == "testnet" && "$faucet_status" != "200" ]]; then
  add_warning "faucet puzzle endpoint returned HTTP $faucet_status at $torii_root/v1/accounts/faucet/puzzle"
fi

case "$public_env" in
  production)
    if [[ "${SORASWAP_ALLOW_PRODUCTION_MUTATIONS:-}" == "1" ]]; then
      mutation_gate=true
    else
      add_blocker "SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 is required for the full production release gate"
    fi
    ;;
  *)
    if [[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-}" == "1" ]]; then
      mutation_gate=true
    else
      add_blocker "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 is required for the full $public_display_label release gate"
    fi
    ;;
esac

if [[ "$mutation_gate" == "true" ]]; then
  if health_issues_json="$(soraswap_public_write_health_issues_json "$health_snapshot_json" 2>/dev/null)"; then
    while IFS= read -r health_issue || [[ -n "$health_issue" ]]; do
      [[ -n "$health_issue" ]] || continue
      add_blocker "$public_display_label public write health is degraded: $health_issue"
    done < <(jq -r '.[]' <<<"$health_issues_json")
  else
    health_issues_json='["public chain health could not be evaluated"]'
    add_blocker "$public_display_label public write health could not be evaluated"
  fi

  if [[ "$health_snapshot_json" != "null" ]] && soraswap_public_chain_queued_stall_detected "$health_snapshot_json" "$public_preflight_queued_stall_max_ms"; then
    if [[ -n "$health_summary" ]]; then
      add_blocker "$public_display_label public finality path has queued writes stalled: $health_summary"
    else
      add_blocker "$public_display_label public finality path has queued writes stalled"
    fi
  fi
fi

if soraswap_value_looks_placeholder "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}"; then
  add_blocker "SORASWAP_ORACLE_PUBLIC_KEY_HEX is an example value"
elif [[ -n "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" ]]; then
  if soraswap_oracle_public_key_hex_for_config "$config" >/dev/null 2>&1; then
    oracle_public_key_present=true
    oracle_public_key_source="env"
  else
    add_blocker "SORASWAP_ORACLE_PUBLIC_KEY_HEX is not a usable Ed25519 public key"
  fi
elif [[ "$config_usable" == "true" ]] \
  && soraswap_oracle_public_key_hex_for_config "$config" >/dev/null 2>&1; then
  oracle_public_key_present=true
  oracle_public_key_source="client_config_signer"
else
    add_blocker "oracle public key is unavailable; set SORASWAP_ORACLE_PUBLIC_KEY_HEX or provide public_key in the $public_display_label client config"
fi

if soraswap_value_looks_placeholder "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}"; then
  add_blocker "SORASWAP_ORACLE_PRIVATE_KEY_HEX is an example value"
elif [[ -n "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" ]]; then
  if soraswap_oracle_private_key_hex_for_config "$config" >/dev/null 2>&1; then
    oracle_private_key_present=true
    oracle_private_key_source="env"
  else
    add_blocker "SORASWAP_ORACLE_PRIVATE_KEY_HEX is not usable"
  fi
elif [[ "$config_usable" == "true" ]] \
  && soraswap_oracle_private_key_hex_for_config "$config" >/dev/null 2>&1; then
  oracle_private_key_present=true
  oracle_private_key_source="client_config_signer"
else
    add_blocker "oracle private key is unavailable; set SORASWAP_ORACLE_PRIVATE_KEY_HEX or provide private_key in the $public_display_label client config"
fi

if [[ "$oracle_public_key_present" == "true" && "$oracle_private_key_present" == "true" ]]; then
  oracle_keypair_error=""
  if oracle_keypair_error="$(soraswap_oracle_keypair_matches_for_config "$config" 2>&1 >/dev/null)"; then
    oracle_keypair_verified=true
  else
    if [[ -n "$oracle_keypair_error" ]]; then
      add_blocker "$oracle_keypair_error"
    else
      add_blocker "oracle private key does not match configured oracle public key"
    fi
  fi
fi

if [[ "$config_usable" == "true" ]]; then
  if [[ -n "${SORASWAP_AUTHORITY:-}" ]]; then
    authority="$SORASWAP_AUTHORITY"
    authority_source="env"
    authority_derivable=true
  elif authority="$(authority_from_config "$config" 2>/dev/null || true)"; [[ -n "$authority" ]]; then
    authority_source="client_config_public_key"
    authority_derivable=true
  else
    add_blocker "SORASWAP_AUTHORITY is unset and could not be derived from the client config public key"
  fi

  if [[ -n "$authority" ]]; then
    signer_fee_asset_id="$(fee_asset_definition_id_for_config "$config" 2>/dev/null || true)"
    signer_fee_asset_label="$(fee_asset_label_for_config "$config" 2>/dev/null || true)"
    if account_exists "$config" "$authority"; then
      signer_account_exists=true
      if signer_assets_json="$(account_assets_json "$config" "$authority" 200)"; then
        signer_assets_query_available=true
        signer_fee_balance="$(asset_value_from_account_assets_json "$signer_assets_json" "$signer_fee_asset_id")"
      else
        add_blocker "$public_display_label signer asset listing query failed; Torii account assets are unavailable"
      fi
      if [[ "$signer_assets_query_available" == "true" ]] \
        && { [[ -z "$signer_fee_balance" ]] || ! numeric_gt_zero "$signer_fee_balance"; }; then
        case "$public_env" in
          testnet)
            add_warning "signer exists but does not currently show a positive $signer_fee_asset_label fee balance; deploy-testnet will try the faucet"
            ;;
          production)
            add_blocker "production signer exists but does not currently show a positive $signer_fee_asset_label fee balance"
            ;;
        esac
      fi
      if [[ "$public_env" == "production" \
        && "$signer_assets_query_available" == "true" \
        && -n "$production_min_fee_balance" ]] \
        && soraswap_require_nonnegative_number_setting "SORASWAP_PRODUCTION_MIN_FEE_BALANCE" "$production_min_fee_balance" >/dev/null 2>&1 \
        && numeric_gt_zero "$production_min_fee_balance" \
        && numeric_gt_zero "$signer_fee_balance" \
        && ! numeric_gte "$signer_fee_balance" "$production_min_fee_balance"; then
        add_blocker "production signer fee balance is below the approved minimum"
      fi
      if [[ "$public_env" == "production" ]]; then
        operator_permissions_json="$(production_operator_permission_readiness_json "$config" "$authority")"
        if ! jq -e '.query_available == true and .ready == true' >/dev/null <<<"$operator_permissions_json"; then
          if jq -e '.query_available == true' >/dev/null <<<"$operator_permissions_json"; then
            missing_operator_permissions="$(jq -r '[.required[] | select(.present != true) | .label] | join(", ")' <<<"$operator_permissions_json")"
            add_blocker "production operator is missing preprovisioned permissions: $missing_operator_permissions"
          else
            add_blocker "production operator permissions could not be queried"
          fi
        fi
      fi
    else
      case "$public_env" in
        testnet)
          add_warning "signer account is not query-visible yet; deploy-testnet will try self-registration/onboard/faucet"
          ;;
        production)
          add_blocker "production signer account is not query-visible; create and fund the signer before running production release"
          ;;
      esac
    fi
  fi
fi

artifacts_json='{}'
for artifact in \
  chain.latest.json \
  nested_call_probe.latest.json \
  deploy.latest.json \
  contracts.latest.json \
  smoke.latest.json \
  contract_console_smoke.latest.json \
  trader_readonly.latest.json \
  trader.latest.json \
  trader_api_bundle.latest.json \
  rwa_compliance.latest.json; do
  artifact_path="$evidence_dir/$artifact"
  bool_json=false
  [[ -s "$artifact_path" ]] && bool_json=true
  artifacts_json="$(jq -c \
    --arg artifact "$artifact" \
    --arg path "$(soraswap_display_path "$artifact_path")" \
    --argjson exists "$bool_json" \
    '. + {($artifact): {path: $path, exists: $exists}}' \
    <<<"$artifacts_json")"
done

nested_probe_path="$evidence_dir/nested_call_probe.latest.json"
if [[ -s "$nested_probe_path" && "$skip_existing_nested_probe_check" != "1" ]]; then
  nested_probe_exists=true
  if ! jq -e --arg public_env "$public_env" '
    ((.generated_at // "") | type == "string" and length > 0)
    and ((.environment // "") | type == "string" and . == $public_env)
  ' "$nested_probe_path" >/dev/null 2>&1; then
    nested_probe_matches_current_chain=false
    nested_probe_supported=false
    add_blocker "latest nested-call probe evidence does not match selected environment $public_env"
  elif [[ "$chain_fingerprint_available" == "true" ]] \
    && nested_call_probe_matches_current_chain "$nested_probe_path" "$chain_fingerprint_json" "$public_env"; then
    nested_probe_matches_current_chain=true
    nested_probe_summary="$(jq -r '.summary // empty' "$nested_probe_path" 2>/dev/null || true)"
    nested_probe_health_summary="$(nested_call_probe_health_summary_text "$nested_probe_path" 2>/dev/null || true)"
    [[ -z "$nested_probe_summary" ]] || nested_probe_summary="$(soraswap_redact_sensitive_text "$nested_probe_summary")"
    [[ -z "$nested_probe_health_summary" ]] || nested_probe_health_summary="$(soraswap_redact_sensitive_text "$nested_probe_health_summary")"
    if jq -e '.supported == true' "$nested_probe_path" >/dev/null 2>&1; then
      nested_probe_supported=true
    else
      nested_probe_supported=false
      add_blocker "latest nested-call probe for current $public_display_label chain is unsupported: ${nested_probe_summary:-see $(soraswap_display_path "$nested_probe_path")}"
    fi
  elif [[ "$chain_fingerprint_available" == "true" ]]; then
    nested_probe_matches_current_chain=false
    add_blocker "latest nested-call probe evidence does not match the live $public_display_label chain fingerprint"
  fi
elif [[ -s "$nested_probe_path" ]]; then
  nested_probe_exists=true
elif [[ "$skip_existing_nested_probe_check" != "1" ]]; then
  nested_probe_matches_current_chain=false
  nested_probe_supported=false
  add_blocker "current nested-call probe evidence is missing for $public_display_label; run $nested_probe_setup_command"
fi

blockers_json="$(json_array_from_args "${blockers[@]}")"
warnings_json="$(json_array_from_args "${warnings[@]}")"
preflight_status="ready"
if (( ${#blockers[@]} > 0 )); then
  preflight_status="blocked"
fi

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg target_environment "$public_env" \
  --arg status "$preflight_status" \
  --arg config "$config_report_path" \
  --arg config_path_environment "$config_path_environment" \
  --arg torii_root "$torii_root_report" \
  --arg mcp_status "$mcp_status" \
  --arg mcp_protocol_version "$mcp_protocol_version" \
  --arg mcp_server_name "$mcp_server_name" \
  --arg mcp_server_version "$mcp_server_version" \
  --arg mcp_toolset_version "$mcp_toolset_version" \
  --arg faucet_status "$faucet_status" \
  --arg current_block_height "$current_block_height" \
  --arg authority "$authority" \
  --arg authority_source "$authority_source" \
  --arg oracle_public_key_source "$oracle_public_key_source" \
  --arg oracle_private_key_source "$oracle_private_key_source" \
  --arg signer_fee_asset_id "$signer_fee_asset_id" \
  --arg signer_fee_asset_label "$signer_fee_asset_label" \
  --arg signer_fee_balance "$signer_fee_balance" \
  --arg production_min_fee_balance "$production_min_fee_balance" \
  --arg account_chain_discriminant "$account_chain_discriminant" \
  --arg chain_snapshot_environment "$chain_snapshot_environment" \
  --arg health_summary "$health_summary" \
  --arg nested_probe_summary "$nested_probe_summary" \
  --arg nested_probe_health_summary "$nested_probe_health_summary" \
  --argjson config_exists "$config_exists" \
  --argjson config_tracked "$config_tracked" \
  --argjson config_has_placeholders "$config_has_placeholders" \
  --argjson config_env_mismatch "$config_env_mismatch" \
  --argjson config_security_valid "$config_security_valid" \
  --argjson mutation_gate "$mutation_gate" \
  --argjson mcp_enabled "$mcp_enabled" \
  --argjson mcp_metadata_valid "$mcp_metadata_valid" \
  --argjson mcp_tool_count "$mcp_tool_count" \
  --argjson oracle_public_key_present "$oracle_public_key_present" \
  --argjson oracle_private_key_present "$oracle_private_key_present" \
  --argjson oracle_keypair_verified "$oracle_keypair_verified" \
  --argjson authority_derivable "$authority_derivable" \
  --argjson signer_account_exists "$signer_account_exists" \
  --argjson signer_assets_query_available "$signer_assets_query_available" \
  --argjson operator_permissions "$operator_permissions_json" \
  --argjson chain_fingerprint "$chain_fingerprint_json" \
  --argjson chain_fingerprint_available "$chain_fingerprint_available" \
  --argjson chain_snapshot_exists "$chain_snapshot_exists" \
  --argjson chain_snapshot_matches "$chain_snapshot_matches" \
  --argjson health_snapshot "$health_snapshot_json" \
  --argjson health_issues "$health_issues_json" \
  --argjson direct_validator_health "$direct_validator_health_json" \
  --argjson direct_torii_port_health "$direct_torii_port_health_json" \
  --argjson nested_probe_exists "$nested_probe_exists" \
  --argjson nested_probe_matches_current_chain "$nested_probe_matches_current_chain" \
  --argjson nested_probe_supported "$nested_probe_supported" \
  --argjson blockers "$blockers_json" \
  --argjson warnings "$warnings_json" \
  --argjson artifacts "$artifacts_json" \
  '{
    generated_at: $generated_at,
    target_environment: $target_environment,
    status: $status,
    blockers: $blockers,
    warnings: $warnings,
    config: {
      path: $config,
      exists: $config_exists,
      tracked: $config_tracked,
      security_valid: $config_security_valid,
      has_placeholders: $config_has_placeholders,
      path_environment: (if $config_path_environment == "" then null else $config_path_environment end),
      environment_mismatch: $config_env_mismatch
    },
    environment: {
      mutations_allowed: $mutation_gate,
      oracle_public_key_present: $oracle_public_key_present,
      oracle_private_key_present: $oracle_private_key_present,
      oracle_keypair_verified: $oracle_keypair_verified,
      oracle_public_key_source: $oracle_public_key_source,
      oracle_private_key_source: $oracle_private_key_source
    },
    endpoint: {
      torii_root: $torii_root,
      mcp_http_status: $mcp_status,
      mcp: {
        enabled: $mcp_enabled,
        metadata_valid: $mcp_metadata_valid,
        protocol_version: (if $mcp_protocol_version == "" then null else $mcp_protocol_version end),
        server_name: (if $mcp_server_name == "" then null else $mcp_server_name end),
        server_version: (if $mcp_server_version == "" then null else $mcp_server_version end),
        tool_count: $mcp_tool_count,
        toolset_version: (if $mcp_toolset_version == "" then null else $mcp_toolset_version end)
      },
      faucet_puzzle_http_status: $faucet_status,
      current_block_height: ($current_block_height | tonumber? // null),
      health_summary: (if $health_summary == "" then null else $health_summary end),
      health_issues: $health_issues,
      health: $health_snapshot,
      direct_validator_health: $direct_validator_health,
      direct_torii_port_health: $direct_torii_port_health
    },
    chain: {
      account_chain_discriminant: (if $account_chain_discriminant == "" then null else ($account_chain_discriminant | tonumber? // $account_chain_discriminant) end),
      fingerprint_available: $chain_fingerprint_available,
      fingerprint: $chain_fingerprint,
      saved_snapshot_exists: $chain_snapshot_exists,
      saved_snapshot_environment: (if $chain_snapshot_environment == "" then null else $chain_snapshot_environment end),
      saved_snapshot_matches: $chain_snapshot_matches
    },
    nested_call_probe: {
      latest_exists: $nested_probe_exists,
      matches_current_chain: $nested_probe_matches_current_chain,
      supported: $nested_probe_supported,
      summary: (if $nested_probe_summary == "" then null else $nested_probe_summary end),
      health_summary: (if $nested_probe_health_summary == "" then null else $nested_probe_health_summary end)
    },
    signer: {
      authority: (if $authority == "" then null else $authority end),
      authority_source: $authority_source,
      authority_derivable: $authority_derivable,
      account_exists: $signer_account_exists,
      assets_query_available: $signer_assets_query_available,
      fee_asset_id: (if $signer_fee_asset_id == "" then null else $signer_fee_asset_id end),
      fee_asset_label: (if $signer_fee_asset_label == "" then null else $signer_fee_asset_label end),
      fee_balance: (if $signer_fee_balance == "" then null else $signer_fee_balance end),
      minimum_required_fee_balance: (if $production_min_fee_balance == "" then null else $production_min_fee_balance end),
      permissions: $operator_permissions
    },
    artifacts: $artifacts
  }')"

soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

echo "$public_label preflight: $preflight_status"
if (( ${#blockers[@]} > 0 )); then
  printf 'blockers:\n'
  for item in "${blockers[@]}"; do
    printf '  - %s\n' "$item"
  done
fi
if (( ${#warnings[@]} > 0 )); then
  printf 'warnings:\n'
  for item in "${warnings[@]}"; do
    printf '  - %s\n' "$item"
  done
fi
if [[ -n "$nested_probe_health_summary" ]]; then
  printf 'nested-call health:\n'
  printf '  - %s\n' "$nested_probe_health_summary"
fi
if [[ "$direct_validator_health_json" != "null" ]] \
  && jq -e '(.validators // []) | type == "array" and length > 0' >/dev/null 2>&1 <<<"$direct_validator_health_json"; then
  printf 'direct-validator health:\n'
  while IFS= read -r direct_health_summary; do
    [[ -n "$direct_health_summary" ]] || continue
    printf '  - %s\n' "$direct_health_summary"
  done < <(soraswap_direct_validator_health_summary_text_from_json "$direct_validator_health_json" 2>/dev/null || true)
  while IFS= read -r direct_health_diagnosis; do
    [[ -n "$direct_health_diagnosis" ]] || continue
    printf '  - %s\n' "$direct_health_diagnosis"
  done < <(soraswap_direct_validator_health_diagnosis_text_from_json "$direct_validator_health_json" 2>/dev/null || true)
fi
if [[ "$direct_torii_port_health_json" != "null" ]] \
  && jq -e '(.validators // []) | type == "array" and length > 0' >/dev/null 2>&1 <<<"$direct_torii_port_health_json"; then
  printf 'direct-torii-port health:\n'
  while IFS= read -r port_health_summary; do
    [[ -n "$port_health_summary" ]] || continue
    printf '  - %s\n' "$port_health_summary"
  done < <(soraswap_direct_validator_health_summary_text_from_json "$direct_torii_port_health_json" 2>/dev/null || true)
  while IFS= read -r port_health_diagnosis; do
    [[ -n "$port_health_diagnosis" ]] || continue
    printf '  - %s\n' "$port_health_diagnosis"
  done < <(soraswap_direct_validator_health_diagnosis_text_from_json "$direct_torii_port_health_json" 2>/dev/null || true)
fi
blockers_joined="${(j: :)blockers}"
if (( ${#blockers[@]} > 0 )) \
  && [[ "$blockers_joined" == *"client config"* \
    || "$blockers_joined" == *"$mutation_gate_var=1 is required"* \
    || "$blockers_joined" == *"SORASWAP_ORACLE"* \
    || "$blockers_joined" == *"SORASWAP_AUTHORITY"* ]]; then
  print_setup_hint
fi
echo "evidence: $(soraswap_display_path "$latest_report")"

[[ "$preflight_status" == "ready" ]]
