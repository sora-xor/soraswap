#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "${0:A:h}" && pwd)"
REPO_ROOT="${SCRIPT_DIR:h}"
source "$REPO_ROOT/scripts/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
RUN_SMOKE="${SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE:-0}"
soraswap_require_binary_integer_setting "SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE" "$RUN_SMOKE" || exit 1

if [[ "$RUN_SMOKE" != "1" ]]; then
  echo "skipping live contract console SCCP smoke for $public_env; set SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE=1 to enable"
  exit 0
fi
soraswap_validate_torii_read_max_time || exit 1

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
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -o "$TMP_DIR/capabilities.json" \
    -w '%{http_code}' \
    "$BASE_URL/v1/sccp/capabilities"
)"

registry_status="$(
  curl -sS \
    --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
    -o "$TMP_DIR/registry.json" \
    -w '%{http_code}' \
    "$BASE_URL/v1/sccp/registry"
)"

if [[ "$capabilities_status" != "200" ]]; then
  echo "live SCCP capabilities probe failed with HTTP $capabilities_status"
  cat "$TMP_DIR/capabilities.json"
  exit 1
fi

if [[ "$registry_status" != "200" ]]; then
  echo "live SCCP registry probe failed with HTTP $registry_status"
  cat "$TMP_DIR/registry.json"
  exit 1
fi

jq -e '
  .version == 1
  and .registry_path == "/v1/sccp/registry"
  and .message_bundle_path == "/v1/sccp/proofs/message/{message_id}"
  and .proof_request_path == "/v1/sccp/proof-requests/{message_id}"
  and .recent_messages_path == "/v1/sccp/messages/recent"
' "$TMP_DIR/capabilities.json" >/dev/null
jq -e '.version == 1 and (.lanes | type == "array")' "$TMP_DIR/registry.json" >/dev/null

lane_count="$(jq '.lanes | length' "$TMP_DIR/registry.json")"
route_count="$(jq '[.lanes[].routes[]?] | length' "$TMP_DIR/registry.json")"

echo "live SCCP smoke ok ($public_env): $BASE_URL"
echo "governed_lanes=$lane_count retained_route_revisions=$route_count"
