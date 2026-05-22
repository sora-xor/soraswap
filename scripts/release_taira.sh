#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
config="${SORASWAP_CLIENT_CONFIG:-$ROOT/config/testnet/taira.client.toml}"
testnet_dir="$ROOT/deployments/testnet"

fail() {
  echo "release-taira: $*" >&2
  exit 1
}

abs_path() {
  local path="$1"
  local dir base
  dir="$(cd "$(dirname "$path")" && pwd)" || return 1
  base="$(basename "$path")"
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

[[ -f "$config" ]] || fail "real Taira client config not found: $config"
config_abs="$(abs_path "$config")"
example_abs="$(abs_path "$ROOT/config/testnet/taira.client.toml.example")"
[[ "$config_abs" != "$example_abs" ]] || fail "refusing to use the tracked example Taira config"
[[ "$config_abs" != *.example ]] || fail "refusing to use an example Taira config: $config_abs"

if [[ "$config_abs" == "$ROOT/"* ]]; then
  config_rel="${config_abs#$ROOT/}"
  if git -C "$ROOT" ls-files --error-unmatch "$config_rel" >/dev/null 2>&1; then
    fail "Taira client config must be untracked: $config_rel"
  fi
fi

if rg -n 'CHANGE_ME|change-me|example\\.invalid|localhost|127\\.0\\.0\\.1' "$config_abs" >/dev/null 2>&1; then
  fail "Taira client config still contains example credentials or local endpoints"
fi

[[ "${SORASWAP_ALLOW_TESTNET_MUTATIONS:-}" == "1" ]] || \
  fail "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 is required for the full Taira release gate"
[[ -n "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" ]] || \
  fail "SORASWAP_ORACLE_PUBLIC_KEY_HEX is required; public oracle keys are never derived"
[[ -n "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" ]] || \
  fail "SORASWAP_ORACLE_PRIVATE_KEY_HEX is required; public oracle keys are never derived"
[[ "${SORASWAP_ORACLE_PUBLIC_KEY_HEX:-}" != *CHANGE_ME* ]] || fail "oracle public key is an example value"
[[ "${SORASWAP_ORACLE_PRIVATE_KEY_HEX:-}" != *CHANGE_ME* ]] || fail "oracle private key is an example value"

export SORASWAP_CLIENT_CONFIG="$config_abs"
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1

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
