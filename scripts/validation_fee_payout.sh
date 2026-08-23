#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

command="${1:-}"
config="${2:-${SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG:-}}"
output="$ROOT/artifacts/rendered/validation_fee/autonomous_payout.ko"
artifact="$ROOT/artifacts/compiled/validation_fee/autonomous_payout.to"
test_source="$ROOT/tests/kotodama/validation_fee_autonomous_payout_regressions.test.ko"
template="$ROOT/validation_fee/autonomous_payout.ko.template"
chain_discriminant=369

case "$command" in
  render|check|build|test) ;;
  *)
    echo "usage: $0 <render|check|build|test> <reviewed-public-binding.json>" >&2
    exit 2
    ;;
esac

if [[ -z "$config" || ! -f "$config" ]]; then
  echo "validation-fee payout: reviewed public binding JSON is required" >&2
  exit 2
fi

renderer_args=("$config" --output "$output")
if [[ "$command" == "check" ]]; then
  renderer_args+=(--check)
fi
python3 "$SCRIPT_DIR/render_validation_fee_payout.py" "${renderer_args[@]}"

if [[ "$command" == "render" ]]; then
  exit 0
fi

ensure_koto_bin >/dev/null
koto="$SORASWAP_ACTIVE_KOTO_BIN"

case "$command" in
  check)
    "$koto" check \
      --chain-discriminant "$chain_discriminant" \
      "$output"
    "$koto" fmt --check "$template" "$output" "$test_source"
    ;;
  build)
    "$koto" build \
      --chain-discriminant "$chain_discriminant" \
      --profile validation-fee-taira \
      --out "$artifact" \
      "$output"
    ;;
  test)
    "$koto" test run \
      --chain-discriminant "$chain_discriminant" \
      --format human \
      "$test_source"
    ;;
esac
