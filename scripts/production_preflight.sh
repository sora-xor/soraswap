#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

export SORASWAP_PUBLIC_ENV=production
0="$SCRIPT_ROOT/taira_preflight.sh"
source "$SCRIPT_ROOT/taira_preflight.sh" "$@"
