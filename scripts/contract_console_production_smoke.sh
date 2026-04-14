#!/bin/zsh
set -euo pipefail

export SORASWAP_PUBLIC_ENV=production
exec "$(cd "$(dirname "$0")" && pwd)/contract_console_public_smoke.sh" "$@"
