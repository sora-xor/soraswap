#!/bin/zsh
set -euo pipefail

export SORASWAP_PUBLIC_ENV=testnet
exec "$(cd "$(dirname "$0")" && pwd)/public_nested_call_probe.sh" "$@"
