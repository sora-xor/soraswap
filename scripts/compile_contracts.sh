#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/dev_iroha.sh" build --manifest "${SORASWAP_CONTRACTS_MANIFEST:-iroha.contracts.toml}" --profile "${SORASWAP_PROFILE:-local}" "$@"
