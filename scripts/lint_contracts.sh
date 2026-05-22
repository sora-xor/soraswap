#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/dev_iroha.sh" check --manifest "${SORASWAP_CONTRACTS_MANIFEST:-iroha.contracts.toml}" --profile "${SORASWAP_PROFILE:-local}" "$@"
