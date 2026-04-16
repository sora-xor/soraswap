#!/bin/zsh
set -euo pipefail

export SORASWAP_PUBLIC_ENV=testnet
exec "$(cd "$(dirname "$0")" && pwd)/trader_public.sh" mutating "$@"
