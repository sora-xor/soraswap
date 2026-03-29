#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

stopped=0
setopt null_glob

if [[ -x "$DEFAULT_LOCALNET_DIR/stop.sh" ]]; then
  localnet_pid_files=("$DEFAULT_LOCALNET_DIR"/peer*.pid)
  (
    cd "$DEFAULT_LOCALNET_DIR"
    ./stop.sh || true
  )
  if (( ${#localnet_pid_files[@]} > 0 )); then
    rm -f -- "${localnet_pid_files[@]}"
  fi
  echo "stopped local Nexus localnet in $DEFAULT_LOCALNET_DIR"
  stopped=1
fi

legacy_pid_file="$SORASWAP_ROOT/tmp/irohad.local.pid"
if [[ -f "$legacy_pid_file" ]]; then
  pid="$(cat "$legacy_pid_file")"
  kill "$pid" || true
  rm -f "$legacy_pid_file"
  echo "stopped legacy local Nexus pid $pid"
  stopped=1
fi

if [[ "$stopped" -eq 0 ]]; then
  echo "no local Nexus localnet found"
fi
