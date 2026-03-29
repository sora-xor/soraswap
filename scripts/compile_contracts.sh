#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

while IFS= read -r contract; do
  echo "compile: $contract"
  compile_one "$contract"
done < <(list_contracts)
