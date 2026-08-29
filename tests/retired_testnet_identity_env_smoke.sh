#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

assert_rejected() {
  local script_path="$1"
  local variable_name="$2"
  local variable_value="$3"
  local output exit_code

  exit_code=0
  output="$(
    (
      unset SORASWAP_TESTNET_CHAIN_ID SORASWAP_TESTNET_CHAIN_DISCRIMINANT
      typeset -gx "$variable_name=$variable_value"
      zsh "$script_path"
    ) 2>&1
  )" || exit_code="$?"

  [[ "$exit_code" != "0" ]]
  [[ "$output" == *"retired environment variable is not supported: $variable_name"* ]]
}

for script_path in "$ROOT/scripts/release_production.sh" "$ROOT/scripts/release_checklist.sh"; do
  for variable_name in SORASWAP_TESTNET_CHAIN_ID SORASWAP_TESTNET_CHAIN_DISCRIMINANT; do
    assert_rejected "$script_path" "$variable_name" ""
    assert_rejected "$script_path" "$variable_name" "retired-override"
  done
done

echo "retired testnet identity env smoke ok"
