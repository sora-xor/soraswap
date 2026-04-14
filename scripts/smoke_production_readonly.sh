#!/bin/zsh
set -euo pipefail

export SORASWAP_PUBLIC_ENV=production
exec "$(cd "$(dirname "$0")" && pwd)/smoke_public.sh" "$@"
