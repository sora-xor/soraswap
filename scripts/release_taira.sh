#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
config="${SORASWAP_CLIENT_CONFIG:-$ROOT/config/testnet/taira.client.toml}"
testnet_dir="$ROOT/deployments/testnet"

fail() {
  echo "release-taira: $*" >&2
  exit 1
}

print_setup_hint() {
  cat >&2 <<EOF

Required setup:
  cp config/testnet/taira.client.toml.example config/testnet/taira.client.toml
  # edit the copied file with real untracked Taira credentials
  export SORASWAP_CLIENT_CONFIG="$config"
  export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
  # Optional: override the default oracle provider, which is the client config signer.
  export SORASWAP_ORACLE_PUBLIC_KEY_HEX=<public oracle key>
  export SORASWAP_ORACLE_PRIVATE_KEY_HEX=<private oracle key>
  make release-taira

The client config and optional oracle private key are runtime-only secrets. Do not commit them.
EOF
}

fail_with_setup_hint() {
  echo "release-taira: $*" >&2
  print_setup_hint
  exit 1
}

abs_path() {
  local input_path="$1"
  local dir base
  dir="$(cd "$(dirname "$input_path")" && pwd)" || return 1
  base="$(basename "$input_path")"
  printf '%s/%s\n' "$dir" "$base"
}

require_artifacts() {
  local artifact
  for artifact in "$@"; do
    [[ -s "$artifact" ]] || fail "missing required evidence after target: $artifact"
  done
}

run_target() {
  local target="$1"
  shift

  echo "release-taira: make $target"
  make -C "$ROOT" "$target"
  require_artifacts "$@"
}

[[ -f "$config" ]] || fail_with_setup_hint "real Taira client config not found: $config"
config_abs="$(abs_path "$config")"
example_abs="$(abs_path "$ROOT/config/testnet/taira.client.toml.example")"
[[ "$config_abs" != "$example_abs" ]] || fail_with_setup_hint "refusing to use the tracked example Taira config"
[[ "$config_abs" != *.example ]] || fail_with_setup_hint "refusing to use an example Taira config: $config_abs"

if [[ "$config_abs" == "$ROOT/"* ]]; then
  config_rel="${config_abs#$ROOT/}"
  if git -C "$ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
    fail "Taira client config must be untracked: $config_rel"
  fi
fi

if rg -n 'CHANGE_ME|change-me|example\\.invalid|localhost|127\\.0\\.0\\.1' "$config_abs" >/dev/null 2>&1; then
  fail_with_setup_hint "Taira client config still contains example credentials or local endpoints"
fi

[[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-}" == "1" ]] || \
  fail_with_setup_hint "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 is required for the full Taira release gate"
[[ "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" != *CHANGE_ME* ]] || fail "oracle public key is an example value"
[[ "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" != *CHANGE_ME* ]] || fail "oracle private key is an example value"

source "$ROOT/scripts/common.sh"
if ! soraswap_required_oracle_public_key_hex "$config_abs" >/dev/null; then
  fail_with_setup_hint "could not derive oracle public key from SORASWAP_ORACLE_PUBLIC_KEY_HEX or the Taira client config signer"
fi
if ! soraswap_oracle_private_key_hex_for_config "$config_abs" >/dev/null; then
  fail_with_setup_hint "could not derive oracle private key from SORASWAP_ORACLE_PRIVATE_KEY_HEX or the Taira client config signer"
fi

export SORASWAP_CLIENT_CONFIG="$config_abs"
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1

run_target taira-preflight \
  "$testnet_dir/preflight.latest.json"
run_target testnet-nested-call-probe \
  "$testnet_dir/chain.latest.json" \
  "$testnet_dir/nested_call_probe.latest.json"
run_target deploy-testnet \
  "$testnet_dir/deploy.latest.json" \
  "$testnet_dir/contracts.latest.json"
run_target smoke-testnet-readonly \
  "$testnet_dir/smoke.latest.json"
run_target smoke-testnet \
  "$testnet_dir/smoke.latest.json"
run_target test-contract-console-testnet \
  "$testnet_dir/contract_console_smoke.latest.json"
run_target smoke-testnet-trader-readonly \
  "$testnet_dir/trader_readonly.latest.json"
run_target smoke-testnet-trader \
  "$testnet_dir/trader.latest.json"
run_target publish-trader-api \
  "$testnet_dir/trader_api_bundle.latest.json"
run_target release-checklist \
  "$testnet_dir/rwa_compliance.latest.json"

echo "release-taira: completed"
