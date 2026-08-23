#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"

export SORASWAP_RELEASE_ENV=production
0="$SCRIPT_ROOT/release_checklist.sh"
source "$SCRIPT_ROOT/release_checklist.sh" "$@"
