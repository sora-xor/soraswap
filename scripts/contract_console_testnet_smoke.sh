#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

export SORASWAP_PUBLIC_ENV=testnet
0="$SCRIPT_ROOT/contract_console_public_smoke.sh"
source "$SCRIPT_ROOT/contract_console_public_smoke.sh" "$@"
