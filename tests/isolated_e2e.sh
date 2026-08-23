#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"

isolated_require_ps() {
  local self_state self_command

  if ! command -v ps >/dev/null 2>&1; then
    echo "isolated local acceptance requires ps for exact peer PID auditing" >&2
    return 70
  fi
  if ! self_state="$(ps -p "$$" -o stat= 2>/dev/null)" \
    || [[ -z "${self_state//[[:space:]]/}" ]]; then
    echo "isolated local acceptance cannot safely inspect process state with ps" >&2
    return 70
  fi
  if ! self_command="$(ps -ww -p "$$" -o command= 2>/dev/null)" \
    || [[ -z "${self_command//[[:space:]]/}" ]]; then
    echo "isolated local acceptance cannot safely inspect process command lines with ps" >&2
    return 70
  fi
}

isolated_python3_bin() {
  local python_bin

  python_bin="$(command -v python3 2>/dev/null || true)"
  if [[ -z "$python_bin" || ! -x "$python_bin" ]]; then
    echo "isolated local acceptance requires python3 for path and port validation" >&2
    return 1
  fi
  printf '%s\n' "$python_bin"
}

isolated_candidate_tag() {
  local expected_sha="${SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA:-}"

  if [[ -z "$expected_sha" ]]; then
    printf 'dev\n'
    return 0
  fi
  if [[ ! "$expected_sha" =~ '^[0-9a-f]{40}$' ]]; then
    echo "SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA must be a 40-character lowercase Git SHA" >&2
    return 1
  fi
  printf '%s\n' "${expected_sha[1,8]}"
}

isolated_default_localnet_dir() {
  local candidate_tag="${1:-$(isolated_candidate_tag)}"
  local utc_stamp="${2:-$(env TZ=UTC date '+%Y%m%dT%H%M%SZ')}"
  local process_id="${3:-$$}"

  if [[ ! "$candidate_tag" =~ '^(dev|[0-9a-f]{8})$' ]]; then
    echo "isolated local acceptance candidate tag must be dev or eight lowercase hexadecimal characters" >&2
    return 1
  fi
  if [[ ! "$utc_stamp" =~ '^[0-9]{8}T[0-9]{6}Z$' ]]; then
    echo "isolated local acceptance timestamp must use UTC YYYYMMDDTHHMMSSZ format" >&2
    return 1
  fi
  if [[ "$process_id" != <-> ]]; then
    echo "isolated local acceptance process id must be numeric" >&2
    return 1
  fi

  printf '%s/tmp/iroha-localnet-verify-%s-%s-%s\n' \
    "$ROOT" "$candidate_tag" "$utc_stamp" "$process_id"
}

isolated_resolve_localnet_dir() {
  local requested_dir="$1"
  local python_bin

  python_bin="$(isolated_python3_bin)" || return 1
  "$python_bin" - "$ROOT" "$requested_dir" <<'PY'
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
tmp = root.joinpath("tmp").resolve(strict=True)
requested = Path(sys.argv[2])
if not requested.is_absolute():
    requested = root.joinpath(requested)
resolved = requested.resolve(strict=False)

if resolved.parent != tmp:
    raise SystemExit(
        "isolated local acceptance directory must be a direct child of the repository tmp directory"
    )
if not re.fullmatch(r"[A-Za-z0-9._-]+", resolved.name):
    raise SystemExit(
        "isolated local acceptance directory name may contain only letters, digits, dot, underscore, and dash"
    )
if any(ord(character) < 32 or ord(character) == 127 for character in os.fspath(resolved)):
    raise SystemExit("isolated local acceptance directory must not contain control characters")

print(resolved)
PY
}

isolated_reserve_localnet_dir() {
  local localnet_dir="$1"

  if [[ -e "$localnet_dir" || -L "$localnet_dir" ]]; then
    echo "isolated local acceptance refuses existing run directory: $(soraswap_display_path "$localnet_dir")" >&2
    return 1
  fi
  if ! mkdir "$localnet_dir"; then
    echo "isolated local acceptance could not reserve new run directory: $(soraswap_display_path "$localnet_dir")" >&2
    return 1
  fi
}

isolated_port_pair_bindable() {
  local api_port="$1"
  local p2p_port="$2"
  local python_bin

  python_bin="$(isolated_python3_bin)" || return 1
  "$python_bin" - "$api_port" "$p2p_port" <<'PY'
import socket
import sys

sockets = []
try:
    for raw_port in sys.argv[1:]:
        candidate = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        candidate.bind(("0.0.0.0", int(raw_port)))
        sockets.append(candidate)
except OSError:
    raise SystemExit(1)
finally:
    for candidate in sockets:
        candidate.close()
PY
}

isolated_select_port_pair() {
  local api_port="$1"
  local p2p_port="$2"
  local max_attempts="$3"
  local attempt=0

  soraswap_require_positive_integer_at_most_setting \
    "SORASWAP_LOCALNET_BASE_API_PORT" "$api_port" 65535 || return 1
  soraswap_require_positive_integer_at_most_setting \
    "SORASWAP_LOCALNET_BASE_P2P_PORT" "$p2p_port" 65535 || return 1
  soraswap_require_positive_integer_at_most_setting \
    "SORASWAP_ISOLATED_PORT_SELECTION_MAX_ATTEMPTS" "$max_attempts" 162 || return 1
  if (( api_port == p2p_port )); then
    echo "isolated local acceptance API and P2P ports must differ" >&2
    return 1
  fi

  while (( attempt < max_attempts )); do
    if (( api_port > 65535 || p2p_port > 65535 )); then
      echo "isolated local acceptance exhausted the valid TCP port range" >&2
      return 1
    fi
    if isolated_port_pair_bindable "$api_port" "$p2p_port"; then
      printf '%s %s\n' "$api_port" "$p2p_port"
      return 0
    fi
    api_port=$(( api_port + 100 ))
    p2p_port=$(( p2p_port + 100 ))
    attempt=$(( attempt + 1 ))
  done

  echo "isolated local acceptance could not find a bindable API/P2P port pair after $max_attempts attempts" >&2
  return 1
}

isolated_command_matches_peer_config() {
  local command_line="$1"
  local expected_config="$2"
  local index config_count=0
  local -a command_words

  command_words=("${(@z)command_line}")
  (( ${#command_words[@]} > 0 )) || return 1
  [[ "${command_words[1]:t}" == "irohad" ]] || return 1

  for (( index = 2; index <= ${#command_words[@]}; index++ )); do
    if [[ "${command_words[$index]}" == "--config" ]]; then
      (( index < ${#command_words[@]} )) || return 1
      [[ "${command_words[$(( index + 1 ))]}" == "$expected_config" ]] || return 1
      config_count=$(( config_count + 1 ))
      index=$(( index + 1 ))
    elif [[ "${command_words[$index]}" == --config=* ]]; then
      [[ "${command_words[$index]}" == "--config=$expected_config" ]] || return 1
      config_count=$(( config_count + 1 ))
    fi
  done

  (( config_count == 1 ))
}

isolated_pid_command_line() {
  local pid="$1"
  local process_state process_command inspect_output inspect_status

  inspect_status=0
  inspect_output="$(ps -p "$pid" -o stat= 2>&1)" || inspect_status="$?"
  if (( inspect_status != 0 )); then
    if [[ -n "${inspect_output//[[:space:]]/}" ]]; then
      echo "isolated local cleanup cannot safely inspect PID $pid state" >&2
      return 70
    fi
    return 1
  fi
  process_state="$inspect_output"
  process_state="${process_state//[[:space:]]/}"
  if [[ -z "$process_state" ]]; then
    echo "isolated local cleanup received an empty process state for PID $pid" >&2
    return 70
  fi
  if [[ "$process_state" == Z* ]]; then
    return 1
  fi

  inspect_status=0
  inspect_output="$(ps -ww -p "$pid" -o command= 2>&1)" || inspect_status="$?"
  if (( inspect_status != 0 )) || [[ -z "${inspect_output//[[:space:]]/}" ]]; then
    echo "isolated local cleanup cannot safely inspect PID $pid command line" >&2
    return 70
  fi
  process_command="$inspect_output"
  printf '%s\n' "$process_command"
}

typeset -ga isolated_audited_live_pids
typeset -ga isolated_audited_live_configs

isolated_audit_live_peer_pids() {
  local localnet_dir="$1"
  local pid_file pid peer_name peer_config command_line inspect_status
  local -a pid_files

  isolated_require_ps || return $?
  isolated_audited_live_pids=()
  isolated_audited_live_configs=()
  setopt local_options null_glob
  pid_files=("$localnet_dir"/peer*.pid)

  for pid_file in "${pid_files[@]}"; do
    [[ -f "$pid_file" && ! -L "$pid_file" ]] || {
      echo "isolated local cleanup refuses non-regular peer PID file: $(soraswap_display_path "$pid_file")" >&2
      return 70
    }
    pid="$(<"$pid_file")"
    if [[ "$pid" != <-> ]]; then
      echo "isolated local cleanup refuses malformed peer PID file: $(soraswap_display_path "$pid_file")" >&2
      return 70
    fi
    peer_name="${pid_file:t:r}"
    if [[ "$peer_name" != peer<-> ]]; then
      echo "isolated local cleanup refuses unexpected peer PID filename: $(soraswap_display_path "$pid_file")" >&2
      return 70
    fi
    command_line=""
    if command_line="$(isolated_pid_command_line "$pid")"; then
      :
    else
      inspect_status="$?"
      if (( inspect_status == 1 )); then
        continue
      fi
      return "$inspect_status"
    fi

    peer_config="$localnet_dir/${peer_name}.toml"
    if [[ ! -f "$peer_config" || -L "$peer_config" ]] \
      || ! isolated_command_matches_peer_config "$command_line" "$peer_config"; then
      echo "isolated local cleanup refused live PID $pid: command line does not reference the exact $(soraswap_display_path "$peer_config") irohad config" >&2
      return 70
    fi
    isolated_audited_live_pids+=("$pid")
    isolated_audited_live_configs+=("$peer_config")
  done
}

isolated_verify_cleanup_postcondition() {
  local localnet_dir="$1"
  local pid_file pid command_line index inspect_status
  local -a pid_files

  isolated_require_ps || return $?
  for (( index = 1; index <= ${#isolated_audited_live_pids[@]}; index++ )); do
    pid="${isolated_audited_live_pids[$index]}"
    command_line=""
    if command_line="$(isolated_pid_command_line "$pid")"; then
      echo "isolated local cleanup failed: audited peer PID $pid is still live after generated stop.sh" >&2
      return 72
    else
      inspect_status="$?"
      if (( inspect_status != 1 )); then
        return "$inspect_status"
      fi
    fi
  done

  setopt local_options null_glob
  pid_files=("$localnet_dir"/peer*.pid)
  for pid_file in "${pid_files[@]}"; do
    pid="$(<"$pid_file" 2>/dev/null || true)"
    if [[ "$pid" == <-> ]]; then
      command_line=""
      if command_line="$(isolated_pid_command_line "$pid")"; then
        echo "isolated local cleanup failed: peer PID file still names live PID $pid after generated stop.sh" >&2
        return 72
      else
        inspect_status="$?"
        if (( inspect_status != 1 )); then
          return "$inspect_status"
        fi
      fi
    fi
    echo "isolated local cleanup failed: generated stop.sh left peer PID file $(soraswap_display_path "$pid_file")" >&2
    return 72
  done
}

isolated_cleanup_localnet() {
  local localnet_dir="$1"
  local stop_script="$localnet_dir/stop.sh"
  local stop_status=0
  local -a pid_files

  isolated_audit_live_peer_pids "$localnet_dir" || return $?
  setopt local_options null_glob
  pid_files=("$localnet_dir"/peer*.pid)
  if [[ ! -e "$stop_script" && ! -L "$stop_script" ]]; then
    if (( ${#pid_files[@]} == 0 && ${#isolated_audited_live_pids[@]} == 0 )); then
      return 0
    fi
    echo "isolated local cleanup failed: generated stop.sh is missing" >&2
    return 71
  fi
  if [[ ! -f "$stop_script" || -L "$stop_script" || ! -x "$stop_script" ]]; then
    echo "isolated local cleanup failed: generated stop.sh must be a regular executable file" >&2
    return 71
  fi

  if (
    cd "$localnet_dir"
    ./stop.sh
  ); then
    :
  else
    stop_status=$?
    echo "isolated local cleanup failed: generated stop.sh exited with status $stop_status" >&2
    return "$stop_status"
  fi

  isolated_verify_cleanup_postcondition "$localnet_dir"
}

isolated_resolve_final_status() {
  local run_status="$1"
  local cleanup_status="$2"

  if (( run_status != 0 )); then
    printf '%s\n' "$run_status"
  else
    printf '%s\n' "$cleanup_status"
  fi
}

isolated_exit_handler() {
  local run_status="$?"
  local cleanup_status=0
  local final_status

  trap - EXIT
  if isolated_cleanup_localnet "$SORASWAP_LOCALNET_DIR"; then
    cleanup_status=0
  else
    cleanup_status=$?
    echo "isolated local acceptance retained failed run directory: $(soraswap_display_path "$SORASWAP_LOCALNET_DIR")" >&2
  fi
  final_status="$(isolated_resolve_final_status "$run_status" "$cleanup_status")"
  exit "$final_status"
}

isolated_require_disabled_timeout() {
  local setting_name="$1"
  local value="$2"

  soraswap_require_nonnegative_integer_setting "$setting_name" "$value" || return 1
  if [[ "$value" != "0" ]]; then
    echo "$setting_name must be 0 because isolated acceptance never signals child processes outside generated stop.sh; got '$value'" >&2
    return 1
  fi
}

snapshot_post_deploy_artifacts() {
  local destination_dir="${SORASWAP_ISOLATED_DEPLOY_ARTIFACT_SNAPSHOT_DIR:-}"
  local source destination tmp

  if [[ -z "$destination_dir" ]]; then
    return 0
  fi

  mkdir -p "$destination_dir"
  source="$ROOT/deployments/local/soraswap.bundle.deploy.json"
  destination="$destination_dir/soraswap.bundle.deploy.json"
  if [[ -f "$source" ]]; then
    tmp="$(mktemp "${destination}.XXXXXX")" || return 1
    if ! cp -p "$source" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    if ! mv "$tmp" "$destination"; then
      rm -f "$tmp"
      return 1
    fi
  fi
}

isolated_main() {
  local requested_localnet_dir candidate_tag default_localnet_dir selected_ports
  local -a port_pair

  if (( $# != 0 )); then
    echo "usage: tests/isolated_e2e.sh" >&2
    return 1
  fi

  export SORASWAP_RUN_TESTNET_SMOKE="${SORASWAP_RUN_TESTNET_SMOKE:-0}"
  case "$SORASWAP_RUN_TESTNET_SMOKE" in
    0|1)
      ;;
    *)
      echo "SORASWAP_RUN_TESTNET_SMOKE must be 0 or 1; got '$SORASWAP_RUN_TESTNET_SMOKE'" >&2
      return 1
      ;;
  esac

  export SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS="${SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS:-0}"
  export SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS="${SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS:-0}"
  export SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS="${SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS:-0}"
  export SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS="${SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS:-0}"
  isolated_require_disabled_timeout SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS "$SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS" || return 1
  isolated_require_disabled_timeout SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS "$SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS" || return 1
  isolated_require_disabled_timeout SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS "$SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS" || return 1
  isolated_require_disabled_timeout SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS "$SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS" || return 1
  isolated_require_ps || return $?

  mkdir -p "$ROOT/tmp"
  candidate_tag="$(isolated_candidate_tag)" || return 1
  default_localnet_dir="$(isolated_default_localnet_dir "$candidate_tag")" || return 1
  requested_localnet_dir="${SORASWAP_LOCALNET_DIR:-$default_localnet_dir}"
  SORASWAP_LOCALNET_DIR="$(isolated_resolve_localnet_dir "$requested_localnet_dir")" || return 1
  export SORASWAP_LOCALNET_DIR
  isolated_reserve_localnet_dir "$SORASWAP_LOCALNET_DIR" || return 1
  trap isolated_exit_handler EXIT
  echo "isolated local acceptance run directory: $(soraswap_display_path "$SORASWAP_LOCALNET_DIR")"

  export SORASWAP_LOCALNET_BASE_API_PORT="${SORASWAP_LOCALNET_BASE_API_PORT:-49180}"
  export SORASWAP_LOCALNET_BASE_P2P_PORT="${SORASWAP_LOCALNET_BASE_P2P_PORT:-49337}"
  export SORASWAP_ISOLATED_PORT_SELECTION_MAX_ATTEMPTS="${SORASWAP_ISOLATED_PORT_SELECTION_MAX_ATTEMPTS:-162}"
  selected_ports="$(isolated_select_port_pair \
    "$SORASWAP_LOCALNET_BASE_API_PORT" \
    "$SORASWAP_LOCALNET_BASE_P2P_PORT" \
    "$SORASWAP_ISOLATED_PORT_SELECTION_MAX_ATTEMPTS")" || return 1
  port_pair=("${(@s: :)selected_ports}")
  export SORASWAP_LOCALNET_BASE_API_PORT="${port_pair[1]}"
  export SORASWAP_LOCALNET_BASE_P2P_PORT="${port_pair[2]}"

  export DEFAULT_LOCALNET_DIR="$SORASWAP_LOCALNET_DIR"
  export SORASWAP_LOCALNET_CONSENSUS_MODE="${SORASWAP_LOCALNET_CONSENSUS_MODE:-permissioned}"
  export SORASWAP_LOCALNET_BLOCK_TIME_MS="${SORASWAP_LOCALNET_BLOCK_TIME_MS:-5000}"
  export SORASWAP_LOCALNET_COMMIT_TIME_MS="${SORASWAP_LOCALNET_COMMIT_TIME_MS:-5000}"
  export SORASWAP_CONTRACT_APP_ACTIVATION_MAX_TIME_SECS="${SORASWAP_CONTRACT_APP_ACTIVATION_MAX_TIME_SECS:-600}"
  export SORASWAP_ASSERT_BOOTSTRAP_STATE="${SORASWAP_ASSERT_BOOTSTRAP_STATE:-1}"
  export SORASWAP_BOOTSTRAP_SCOPE="${SORASWAP_BOOTSTRAP_SCOPE:-full}"
  export SORASWAP_SMOKE_SCOPE="${SORASWAP_SMOKE_SCOPE:-$SORASWAP_BOOTSTRAP_SCOPE}"
  export SORASWAP_CONTRACT_APP_CHUNK_SIZE="${SORASWAP_CONTRACT_APP_CHUNK_SIZE:-1}"
  export SORASWAP_CONTRACT_APP_DEPLOY_PROCESS_TIMEOUT_SECS=0

  local default_release_irohad="$ROOT/../iroha/target/release/irohad"
  if [[ -z "${IROHAD_BIN:-}" && -x "$default_release_irohad" ]] \
    && ! path_is_newer_than "$default_release_irohad" \
      "$ROOT/../iroha/Cargo.toml" \
      "$ROOT/../iroha/Cargo.lock" \
      "$ROOT/../iroha/crates/irohad" \
      "$ROOT/../iroha/crates/iroha_core" \
      "$ROOT/../iroha/crates/ivm" \
      "$ROOT/../iroha/crates/iroha_torii"; then
    export IROHAD_BIN="$default_release_irohad"
  fi
  export SORASWAP_IROHA_CLI_BIN="${SORASWAP_IROHA_CLI_BIN:-$ROOT/../iroha/target/debug/iroha}"
  export SORASWAP_SKIP_IROHA_CLI_BUILD="${SORASWAP_SKIP_IROHA_CLI_BUILD:-1}"

  echo "isolated local acceptance ports: API=$SORASWAP_LOCALNET_BASE_API_PORT P2P=$SORASWAP_LOCALNET_BASE_P2P_PORT"

  zsh "$ROOT/scripts/local_up.sh"
  zsh "$ROOT/scripts/deploy_local.sh"
  snapshot_post_deploy_artifacts
  SORASWAP_CLIENT_CONFIG="$SORASWAP_LOCALNET_DIR/client.toml" \
    zsh "$ROOT/scripts/smoke_local.sh"

  if [[ "$SORASWAP_RUN_TESTNET_SMOKE" == "1" ]]; then
    SORASWAP_CLIENT_CONFIG="$SORASWAP_LOCALNET_DIR/client.toml" \
      zsh "$ROOT/scripts/smoke_testnet.sh"
  fi

  if command -v rg >/dev/null 2>&1; then
    if rg -n "failed to canonicalize default gas asset id" "$SORASWAP_LOCALNET_DIR" -g '*.log' >/dev/null 2>&1; then
      echo "isolated local smoke failed: local peer log contains default gas asset canonicalization warnings" >&2
      rg -n "failed to canonicalize default gas asset id" "$SORASWAP_LOCALNET_DIR" -g '*.log' >&2 || true
      return 1
    fi
  fi
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == *:file ]]; then
  return 0
fi

isolated_main "$@"
