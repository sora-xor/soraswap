#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

exec env SORASWAP_PUBLIC_ENV=production "$SCRIPT_ROOT/contract_console_public_smoke.sh" "$@"
