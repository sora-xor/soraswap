#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

stopped=0
setopt null_glob

peer_pid_matches_localnet_dir() {
  local pid="$1"
  local config="$2"
  local command_line

  [[ "$pid" == <-> ]] || return 1
  command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ -n "$command_line" ]] || return 1
  [[ "$command_line" == *"/iroha3d"* ]] || return 1
  [[ "$command_line" == *"--config $config"* || "$command_line" == *"--config=$config"* ]]
}

if [[ -x "$DEFAULT_LOCALNET_DIR/stop.sh" ]]; then
  localnet_pid_files=("$DEFAULT_LOCALNET_DIR"/peer*.pid)
  live_peer_found=0
  stale_peer_files=()
  for pid_file in "${localnet_pid_files[@]}"; do
    [[ -f "$pid_file" ]] || continue
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    peer_name="${pid_file:t:r}"
    if peer_pid_matches_localnet_dir "$pid" "$DEFAULT_LOCALNET_DIR/${peer_name}.toml"; then
      live_peer_found=1
    else
      stale_peer_files+=("$pid_file")
    fi
  done

  if (( live_peer_found != 0 )); then
    (
      cd "$DEFAULT_LOCALNET_DIR"
      ./stop.sh || true
    )
    if (( ${#localnet_pid_files[@]} > 0 )); then
      rm -f -- "${localnet_pid_files[@]}"
    fi
    echo "stopped local Nexus localnet in $DEFAULT_LOCALNET_DIR"
    stopped=1
  elif (( ${#stale_peer_files[@]} > 0 )); then
    rm -f -- "${stale_peer_files[@]}"
    echo "removed stale local Nexus pid files in $DEFAULT_LOCALNET_DIR"
    stopped=1
  fi
fi

if [[ "$stopped" -eq 0 ]]; then
  echo "no local Nexus localnet found"
fi
