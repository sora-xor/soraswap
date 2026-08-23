#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

export SORASWAP_PUBLIC_ENV=production
0="$SCRIPT_ROOT/record_rwa_compliance.sh"
source "$SCRIPT_ROOT/record_rwa_compliance.sh" "$@"
