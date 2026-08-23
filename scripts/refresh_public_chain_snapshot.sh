#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet|production)
    ;;
  *)
    echo "refresh_public_chain_snapshot.sh only supports SORASWAP_PUBLIC_ENV=testnet|production; got $public_env" >&2
    exit 1
    ;;
esac
export SORASWAP_PUBLIC_ENV="$public_env"

case "$public_env" in
  testnet)
    public_display_label="Taira"
    setup_config_example="config/testnet/taira.client.toml.example"
    setup_config_path="${SORASWAP_CLIENT_CONFIG:-$DEFAULT_TESTNET_CLIENT}"
    setup_target="refresh-testnet-chain"
    ;;
  production)
    public_display_label="production"
    setup_config_example="config/production/production.client.toml.example"
    setup_config_path="${SORASWAP_CLIENT_CONFIG:-${SORASWAP_PRODUCTION_CLIENT_CONFIG:-$DEFAULT_PRODUCTION_CLIENT}}"
    setup_target="refresh-production-chain"
    ;;
esac

print_setup_hint() {
  local setup_config_report_path
  setup_config_report_path="$(soraswap_display_path "$setup_config_path")"
  cat >&2 <<EOF
next setup:
  cp $setup_config_example $setup_config_report_path
  # edit the copied file with real untracked $public_env credentials
  chmod 600 $setup_config_report_path
  export SORASWAP_CLIENT_CONFIG="$setup_config_report_path"
  make $setup_target
EOF
}

if [[ "$public_env" == "production" \
  && -z "${SORASWAP_CLIENT_CONFIG:-}" \
  && -z "${SORASWAP_PRODUCTION_CLIENT_CONFIG:-}" \
  && ! -f "$DEFAULT_PRODUCTION_CLIENT" ]]; then
  echo "real production client config is missing: $(soraswap_display_path "$DEFAULT_PRODUCTION_CLIENT")" >&2
  print_setup_hint
  exit 1
fi

if ! config="$(client_config_or_default "$public_env")"; then
  print_setup_hint
  exit 1
fi
if [[ ! -f "$config" ]]; then
  echo "real $public_display_label client config is missing: $(soraswap_display_path "$config")" >&2
  print_setup_hint
  exit 1
fi
if ! require_public_client_config_matches_env "$public_env" "$config"; then
  print_setup_hint
  exit 1
fi

prepare_env_chain_state "$public_env" "$config" >/dev/null

latest="$(chain_snapshot_latest_path_for_env "$public_env")"
report_dir="$(deployments_dir_for_env "$public_env")"
generated_at="$(jq -r '.generated_at' "$latest")"
timestamped="$report_dir/chain.${generated_at}.json"

echo "$public_env chain snapshot refreshed: $(soraswap_display_path "$latest")"
if [[ -s "$timestamped" ]]; then
  echo "$public_env chain snapshot timestamped: $(soraswap_display_path "$timestamped")"
fi
jq -r '"fingerprint: torii_url=\(.torii_url) chain=\(.chain) block_1_hash=\(.block_1_hash)"' "$latest"
