#!/bin/zsh
set -euo pipefail

export SORASWAP_PUBLIC_ENV=production
exec "$(cd "$(dirname "$0")" && pwd)/public_nested_call_probe.sh" "$@"
