#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "${0:A:h}" && pwd)"
REPO_ROOT="${SCRIPT_DIR:h}"
source "$REPO_ROOT/scripts/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
RUN_SMOKE="${SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE:-0}"

if [[ "$RUN_SMOKE" != "1" ]]; then
  echo "skipping live contract console SCCP smoke for $public_env; set SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE=1 to enable"
  exit 0
fi

case "$public_env" in
  testnet)
    TORII_URL="${SORASWAP_CONTRACT_CONSOLE_LIVE_TORII_URL:-https://taira.sora.org}"
    ;;
  production)
    TORII_URL="${SORASWAP_CONTRACT_CONSOLE_LIVE_TORII_URL:-}"
    if [[ -z "$TORII_URL" ]]; then
      production_config="$(client_config_or_default production 2>/dev/null || true)"
      if [[ -n "$production_config" && -f "$production_config" ]]; then
        TORII_URL="$(torii_base_from_config "$production_config")"
      fi
    fi
    if [[ -z "$TORII_URL" ]]; then
      echo "production live contract console smoke requires SORASWAP_CONTRACT_CONSOLE_LIVE_TORII_URL or SORASWAP_PRODUCTION_CLIENT_CONFIG" >&2
      exit 1
    fi
    ;;
  *)
    echo "unsupported SORASWAP_PUBLIC_ENV for live contract console smoke: $public_env" >&2
    exit 1
    ;;
esac

BASE_URL="${TORII_URL%/}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

capabilities_status="$(
  curl -sS \
    -o "$TMP_DIR/capabilities.json" \
    -w '%{http_code}' \
    "$BASE_URL/v1/sccp/capabilities"
)"

manifests_status="$(
  curl -sS \
    -o "$TMP_DIR/manifests.json" \
    -w '%{http_code}' \
    "$BASE_URL/v1/sccp/manifests"
)"

if [[ "$capabilities_status" != "200" ]]; then
  echo "live SCCP capabilities probe failed with HTTP $capabilities_status"
  cat "$TMP_DIR/capabilities.json"
  exit 1
fi

if [[ "$manifests_status" != "200" ]]; then
  echo "live SCCP manifests probe failed with HTTP $manifests_status"
  cat "$TMP_DIR/manifests.json"
  exit 1
fi

jq -e '.counterparties | arrays' "$TMP_DIR/capabilities.json" >/dev/null
jq -e '.manifests | arrays' "$TMP_DIR/manifests.json" >/dev/null

counterparty_count="$(jq '.counterparties | length' "$TMP_DIR/capabilities.json")"
manifest_count="$(jq '.manifests | length' "$TMP_DIR/manifests.json")"

echo "live SCCP smoke ok ($public_env): $BASE_URL"
echo "counterparties=$counterparty_count manifests=$manifest_count"
