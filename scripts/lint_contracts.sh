#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

exit_code=0

while IFS= read -r contract; do
  echo "lint: $contract"
  if output="$(lint_one "$contract" 2>&1)"; then
    deduped="$(printf '%s\n' "$output" | awk '!seen[$0]++')"
    if [[ -n "${deduped//[$'\r\n\t ']}" ]]; then
      echo "$deduped"
    fi
    continue
  fi

  deduped="$(printf '%s\n' "$output" | awk '!seen[$0]++')"
  echo "$deduped"
  unexpected="$(printf '%s\n' "$deduped" | rg -v 'duplicate-pointer-literal|nonliteral-state-map-key|access-hint:|^koto tool: (reusing existing|building|rebuilding) koto_lint binary' || true)"
  if [[ -n "${unexpected//[$'\r\n\t ']}" ]]; then
    exit_code=1
  fi
done < <(list_contracts)

exit "$exit_code"
