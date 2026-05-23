#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="testnet"
export SORASWAP_PUBLIC_ENV="$public_env"
config="$(client_config_or_default "$public_env")"
timestamp="$(utc_timestamp)"
evidence_dir="$(deployments_dir_for_env "$public_env")"
report_dir="${SORASWAP_TAIRA_PREFLIGHT_REPORT_DIR:-$evidence_dir}"
latest_report="$report_dir/preflight.latest.json"
timestamped_report="$report_dir/preflight.${timestamp}.json"
mkdir -p "$report_dir"

typeset -a blockers
typeset -a warnings
blockers=()
warnings=()

add_blocker() {
  blockers+=("$1")
}

add_warning() {
  warnings+=("$1")
}

print_setup_hint() {
  cat <<EOF
next setup:
  cp config/testnet/taira.client.toml.example config/testnet/taira.client.toml
  # edit the copied file with real untracked Taira credentials
  export SORASWAP_CLIENT_CONFIG="$config"
  export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
  # Optional: override the default oracle provider, which is the client config signer.
  export SORASWAP_ORACLE_PUBLIC_KEY_HEX=<public oracle key>
  export SORASWAP_ORACLE_PRIVATE_KEY_HEX=<private oracle key>
  make taira-preflight
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
  local timeout="${SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS:-10}"
  curl -L -sS -o /dev/null --max-time "$timeout" -w '%{http_code}' "$url" 2>/dev/null || printf '000'
}

json_get_for() {
  local url="$1"
  local timeout="${SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS:-10}"
  curl -L -fsS --max-time "$timeout" "$url" 2>/dev/null || true
}

bool_json=false
config_exists=false
config_tracked=false
config_has_placeholders=false
mutation_gate=false
oracle_public_key_present=false
oracle_private_key_present=false
oracle_public_key_source="missing"
oracle_private_key_source="missing"
authority=""
authority_source="unset"
authority_derivable=false
signer_account_exists=false
signer_fee_balance=""
signer_fee_asset_id=""
signer_fee_asset_label=""
chain_id="$SORASWAP_TESTNET_CHAIN_ID"
chain_fingerprint_json="null"
chain_fingerprint_available=false
chain_snapshot_exists=false
chain_snapshot_matches="null"
current_block_height=""
nested_probe_exists=false
nested_probe_matches_current_chain="null"
nested_probe_supported="null"
nested_probe_summary=""

if [[ -f "$config" ]]; then
  config_exists=true
else
  add_blocker "real Taira client config is missing: $config"
fi

if [[ "$config_exists" == "true" ]]; then
  config_abs="${config:A}"
  if [[ "$config_abs" == "$SORASWAP_ROOT/"* ]]; then
    config_rel="${config_abs#$SORASWAP_ROOT/}"
    if git -C "$SORASWAP_ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
      config_tracked=true
      add_blocker "Taira client config must be untracked: $config_rel"
    fi
  fi

  if [[ "$config_abs" == *.example ]]; then
    config_has_placeholders=true
    add_blocker "Taira client config points at an example file: $config_abs"
  elif rg -n 'CHANGE_ME|change-me|example\.invalid|localhost|127\.0\.0\.1' "$config_abs" >/dev/null 2>&1; then
    config_has_placeholders=true
    add_blocker "Taira client config still contains example credentials or local endpoints"
  fi
fi

torii_root="${SORASWAP_TORII_URL:-}"
if [[ -z "$torii_root" && "$config_exists" == "true" ]]; then
  torii_root="$(torii_url_from_config "$config" 2>/dev/null || true)"
fi
if [[ -z "$torii_root" ]]; then
  torii_root="https://taira.sora.org/"
  add_warning "using default Taira Torii root because no client config is available"
fi
torii_root="${torii_root%/}"

mcp_status="$(http_status_for "$torii_root/v1/mcp")"
faucet_status="$(http_status_for "$torii_root/v1/accounts/faucet/puzzle")"
block_1_json="$(json_get_for "$torii_root/v1/explorer/blocks/1")"
current_block_height="$(json_get_for "$torii_root/status/blocks" | tr -d '\r\n[:space:]')"

if [[ "$config_exists" == "true" && "$config_has_placeholders" == "false" ]]; then
  chain_id="$(config_chain_id_from_config "$config" 2>/dev/null || printf '%s' "$SORASWAP_TESTNET_CHAIN_ID")"
fi

if [[ -n "$block_1_json" ]] && jq -e . >/dev/null 2>&1 <<<"$block_1_json"; then
  block_1_hash="$(jq -er '.hash // empty' <<<"$block_1_json" 2>/dev/null || true)"
  if [[ -n "$block_1_hash" ]]; then
    chain_fingerprint_json="$(jq -cn \
      --arg torii_url "$torii_root" \
      --arg chain "$chain_id" \
      --arg block_1_hash "$block_1_hash" \
      '{torii_url: $torii_url, chain: $chain, block_1_hash: $block_1_hash}')"
    chain_fingerprint_available=true
  fi
fi

if [[ "$chain_fingerprint_available" != "true" ]]; then
  add_warning "could not fetch live chain fingerprint from $torii_root/v1/explorer/blocks/1"
fi

chain_snapshot_path="$(chain_snapshot_latest_path_for_env "$public_env")"
if [[ -s "$chain_snapshot_path" ]]; then
  chain_snapshot_exists=true
  if [[ "$chain_fingerprint_available" == "true" ]]; then
    if chain_snapshot_matches_json "$chain_snapshot_path" "$chain_fingerprint_json"; then
      chain_snapshot_matches=true
    else
      chain_snapshot_matches=false
      add_warning "saved chain.latest.json does not match the live Taira block-1 fingerprint"
    fi
  fi
fi

if [[ "$mcp_status" == "404" ]]; then
  add_blocker "native Torii MCP is not enabled at $torii_root/v1/mcp"
elif [[ "$mcp_status" == "000" ]]; then
  add_blocker "could not reach native Torii MCP at $torii_root/v1/mcp"
elif [[ "$mcp_status" != "200" ]]; then
  add_blocker "native Torii MCP returned HTTP $mcp_status at $torii_root/v1/mcp"
fi

if [[ "$faucet_status" != "200" ]]; then
  add_warning "faucet puzzle endpoint returned HTTP $faucet_status at $torii_root/v1/accounts/faucet/puzzle"
fi

if [[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-}" == "1" ]]; then
  mutation_gate=true
else
  add_blocker "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 is required for the full Taira release gate"
fi

if [[ "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" == *CHANGE_ME* ]]; then
  add_blocker "SORASWAP_ORACLE_PUBLIC_KEY_HEX is an example value"
elif [[ -n "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" ]]; then
  if soraswap_oracle_public_key_hex_for_config "$config" >/dev/null 2>&1; then
    oracle_public_key_present=true
    oracle_public_key_source="env"
  else
    add_blocker "SORASWAP_ORACLE_PUBLIC_KEY_HEX is not a usable Ed25519 public key"
  fi
elif [[ "$config_exists" == "true" && "$config_has_placeholders" == "false" ]] \
  && soraswap_oracle_public_key_hex_for_config "$config" >/dev/null 2>&1; then
  oracle_public_key_present=true
  oracle_public_key_source="client_config_signer"
else
  add_blocker "oracle public key is unavailable; set SORASWAP_ORACLE_PUBLIC_KEY_HEX or provide public_key in the Taira client config"
fi

if [[ "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" == *CHANGE_ME* ]]; then
  add_blocker "SORASWAP_ORACLE_PRIVATE_KEY_HEX is an example value"
elif [[ -n "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" ]]; then
  if soraswap_oracle_private_key_hex_for_config "$config" >/dev/null 2>&1; then
    oracle_private_key_present=true
    oracle_private_key_source="env"
  else
    add_blocker "SORASWAP_ORACLE_PRIVATE_KEY_HEX is not usable"
  fi
elif [[ "$config_exists" == "true" && "$config_has_placeholders" == "false" ]] \
  && soraswap_oracle_private_key_hex_for_config "$config" >/dev/null 2>&1; then
  oracle_private_key_present=true
  oracle_private_key_source="client_config_signer"
else
  add_blocker "oracle private key is unavailable; set SORASWAP_ORACLE_PRIVATE_KEY_HEX or provide private_key in the Taira client config"
fi

if [[ "$config_exists" == "true" && "$config_has_placeholders" == "false" ]]; then
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
      signer_fee_balance="$(asset_value_for_account_id "$config" "$signer_fee_asset_id" "$authority" 2>/dev/null || true)"
      if [[ -z "$signer_fee_balance" ]] || ! numeric_gt_zero "$signer_fee_balance"; then
        add_warning "signer exists but does not currently show a positive $signer_fee_asset_label fee balance; deploy-testnet will try the faucet"
      fi
    else
      add_warning "signer account is not query-visible yet; deploy-testnet will try self-registration/onboard/faucet"
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
    --arg path "$artifact_path" \
    --argjson exists "$bool_json" \
    '. + {($artifact): {path: $path, exists: $exists}}' \
    <<<"$artifacts_json")"
done

nested_probe_path="$evidence_dir/nested_call_probe.latest.json"
if [[ -s "$nested_probe_path" ]]; then
  nested_probe_exists=true
  nested_probe_summary="$(jq -r '.summary // empty' "$nested_probe_path" 2>/dev/null || true)"
  if [[ "$chain_fingerprint_available" == "true" ]] \
    && nested_call_probe_matches_current_chain "$nested_probe_path" "$chain_fingerprint_json"; then
    nested_probe_matches_current_chain=true
    if jq -e '.supported == true' "$nested_probe_path" >/dev/null 2>&1; then
      nested_probe_supported=true
    else
      nested_probe_supported=false
      add_blocker "latest nested-call probe for current Taira chain is unsupported: ${nested_probe_summary:-see $nested_probe_path}"
    fi
  elif [[ "$chain_fingerprint_available" == "true" ]]; then
    nested_probe_matches_current_chain=false
    add_warning "latest nested-call probe evidence does not match the live Taira chain fingerprint"
  fi
fi

blockers_json="$(json_array_from_args "${blockers[@]}")"
warnings_json="$(json_array_from_args "${warnings[@]}")"
preflight_status="ready"
if (( ${#blockers[@]} > 0 )); then
  preflight_status="blocked"
fi

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg status "$preflight_status" \
  --arg config "$config" \
  --arg torii_root "$torii_root" \
  --arg mcp_status "$mcp_status" \
  --arg faucet_status "$faucet_status" \
  --arg current_block_height "$current_block_height" \
  --arg authority "$authority" \
  --arg authority_source "$authority_source" \
  --arg oracle_public_key_source "$oracle_public_key_source" \
  --arg oracle_private_key_source "$oracle_private_key_source" \
  --arg signer_fee_asset_id "$signer_fee_asset_id" \
  --arg signer_fee_asset_label "$signer_fee_asset_label" \
  --arg signer_fee_balance "$signer_fee_balance" \
  --arg nested_probe_summary "$nested_probe_summary" \
  --argjson config_exists "$config_exists" \
  --argjson config_tracked "$config_tracked" \
  --argjson config_has_placeholders "$config_has_placeholders" \
  --argjson mutation_gate "$mutation_gate" \
  --argjson oracle_public_key_present "$oracle_public_key_present" \
  --argjson oracle_private_key_present "$oracle_private_key_present" \
  --argjson authority_derivable "$authority_derivable" \
  --argjson signer_account_exists "$signer_account_exists" \
  --argjson chain_fingerprint "$chain_fingerprint_json" \
  --argjson chain_fingerprint_available "$chain_fingerprint_available" \
  --argjson chain_snapshot_exists "$chain_snapshot_exists" \
  --argjson chain_snapshot_matches "$chain_snapshot_matches" \
  --argjson nested_probe_exists "$nested_probe_exists" \
  --argjson nested_probe_matches_current_chain "$nested_probe_matches_current_chain" \
  --argjson nested_probe_supported "$nested_probe_supported" \
  --argjson blockers "$blockers_json" \
  --argjson warnings "$warnings_json" \
  --argjson artifacts "$artifacts_json" \
  '{
    generated_at: $generated_at,
    status: $status,
    blockers: $blockers,
    warnings: $warnings,
    config: {
      path: $config,
      exists: $config_exists,
      tracked: $config_tracked,
      has_placeholders: $config_has_placeholders
    },
    environment: {
      mutations_allowed: $mutation_gate,
      oracle_public_key_present: $oracle_public_key_present,
      oracle_private_key_present: $oracle_private_key_present,
      oracle_public_key_source: $oracle_public_key_source,
      oracle_private_key_source: $oracle_private_key_source
    },
    endpoint: {
      torii_root: $torii_root,
      mcp_http_status: $mcp_status,
      faucet_puzzle_http_status: $faucet_status,
      current_block_height: ($current_block_height | tonumber? // null)
    },
    chain: {
      fingerprint_available: $chain_fingerprint_available,
      fingerprint: $chain_fingerprint,
      saved_snapshot_exists: $chain_snapshot_exists,
      saved_snapshot_matches: $chain_snapshot_matches
    },
    nested_call_probe: {
      latest_exists: $nested_probe_exists,
      matches_current_chain: $nested_probe_matches_current_chain,
      supported: $nested_probe_supported,
      summary: (if $nested_probe_summary == "" then null else $nested_probe_summary end)
    },
    signer: {
      authority: (if $authority == "" then null else $authority end),
      authority_source: $authority_source,
      authority_derivable: $authority_derivable,
      account_exists: $signer_account_exists,
      fee_asset_id: (if $signer_fee_asset_id == "" then null else $signer_fee_asset_id end),
      fee_asset_label: (if $signer_fee_asset_label == "" then null else $signer_fee_asset_label end),
      fee_balance: (if $signer_fee_balance == "" then null else $signer_fee_balance end)
    },
    artifacts: $artifacts
  }')"

printf '%s\n' "$report_json" > "$latest_report"
printf '%s\n' "$report_json" > "$timestamped_report"

echo "taira preflight: $preflight_status"
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
blockers_joined="${(j: :)blockers}"
if (( ${#blockers[@]} > 0 )) \
  && [[ "$blockers_joined" == *"client config"* \
    || "$blockers_joined" == *"SORASWAP_ALLOW_TESTNET_MUTATIONS"* \
    || "$blockers_joined" == *"SORASWAP_ORACLE"* \
    || "$blockers_joined" == *"SORASWAP_AUTHORITY"* ]]; then
  print_setup_hint
fi
echo "evidence: $latest_report"

[[ "$preflight_status" == "ready" ]]
