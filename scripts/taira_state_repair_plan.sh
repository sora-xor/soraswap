#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$ROOT/scripts/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet)
    ;;
  *)
    echo "taira repair plan only supports SORASWAP_PUBLIC_ENV=testnet; got $public_env" >&2
    exit 1
    ;;
esac

donor_storage="${SORASWAP_TAIRA_REPAIR_DONOR_STORAGE:-}"
reason="${SORASWAP_TAIRA_REPAIR_REASON:-}"
height="${SORASWAP_TAIRA_REPAIR_HEIGHT:-}"
parent_root="${SORASWAP_TAIRA_REPAIR_PARENT_ROOT:-}"
post_root="${SORASWAP_TAIRA_REPAIR_POST_ROOT:-}"
snapshot_policy="${SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY:-}"
operator="${SORASWAP_TAIRA_REPAIR_OPERATOR:-}"
operator_platform="${SORASWAP_TAIRA_REPAIR_PLATFORM:-darwin}"
trace_config_path="${SORASWAP_TAIRA_REPAIR_TRACE_CONFIG:-}"
status_json_path="${SORASWAP_TAIRA_REPAIR_STATUS_JSON:-}"
volatile_dist="${SORASWAP_TAIRA_REPAIR_VOLATILE_DIST:-}"
volatile_runtime_bin="${SORASWAP_TAIRA_REPAIR_VOLATILE_RUNTIME_BIN:-}"
volatile_expected_runtime_sha="${SORASWAP_TAIRA_REPAIR_VOLATILE_EXPECTED_RUNTIME_SHA:-}"
volatile_torii_ports_default="29080,29081,29082,29083"
volatile_torii_ports="${SORASWAP_TAIRA_REPAIR_VOLATILE_TORII_PORTS-$volatile_torii_ports_default}"
volatile_torii_ports_supplied=false
if (( ${+SORASWAP_TAIRA_REPAIR_VOLATILE_TORII_PORTS} )); then
  volatile_torii_ports_supplied=true
fi
report_dir="${SORASWAP_TAIRA_REPAIR_REPORT_DIR:-$(deployments_dir_for_env "$public_env")}"
timestamp="$(utc_timestamp)"
latest_report="$report_dir/taira_state_repair_plan.latest.json"
timestamped_report="$report_dir/taira_state_repair_plan.${timestamp}.json"
typeset -a target_storages

usage() {
  cat >&2 <<EOF
Usage: $0 --donor-storage DIR --target-storage DIR [--target-storage DIR ...] [options]
       $0 --volatile-dist DIR --volatile-runtime-bin PATH --volatile-expected-runtime-sha SHA256 [options]

Options:
  --reason TEXT
  --height HEIGHT
  --parent-root HEX
  --post-root HEX
  --snapshot-policy TEXT
  --operator TEXT
  --operator-platform darwin|linux|manual  default: darwin
  --trace-config PATH
  --status-json PATH
  --volatile-dist DIR
  --volatile-runtime-bin PATH
  --volatile-expected-runtime-sha SHA256
  --volatile-torii-ports CSV  default: 29080,29081,29082,29083
  --report-dir DIR

This command writes a plan-only JSON report. It does not copy, delete, stop,
restart, or modify validator storage. Omit donor/target storage only for a
volatile consensus quarantine plan that uses the --volatile-* inputs.

Prefer SORASWAP_TAIRA_REPAIR_REASON, SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY,
and SORASWAP_TAIRA_REPAIR_OPERATOR for sensitive free-form notes; command-line
arguments can be visible in local process listings while the helper runs.
EOF
}

fail_with_usage() {
  echo "taira repair plan: $(soraswap_redact_sensitive_text "$*")" >&2
  usage
  exit 1
}

abs_path_existing() {
  local input_path="$1"
  local dir base

  [[ -e "$input_path" ]] || return 1
  if [[ -d "$input_path" ]]; then
    (cd "$input_path" && pwd)
    return
  fi

  dir="$(cd "$(dirname "$input_path")" && pwd)" || return 1
  base="$(basename "$input_path")"
  printf '%s/%s\n' "$dir" "$base"
}

require_nonnegative_integer() {
  local label="$1"
  local value="$2"

  [[ -z "$value" ]] && return
  case "$value" in
    ''|*[!0-9]*)
      fail_with_usage "$label must be a nonnegative integer: $value"
      ;;
  esac
}

require_hex_root() {
  local label="$1"
  local value="$2"
  local candidate

  [[ -z "$value" ]] && return
  candidate="$value"
  case "$candidate" in
    0x*)
      candidate="${candidate#0x}"
      ;;
    0X*)
      candidate="${candidate#0X}"
      ;;
  esac
  if [[ ${#candidate} -ne 64 || "$candidate" == *[!0-9A-Fa-f]* ]]; then
    fail_with_usage "$label must be 64 hex characters with optional 0x prefix: $value"
  fi
}

require_sha256_hex() {
  local label="$1"
  local value="$2"

  [[ -z "$value" ]] && return
  if [[ ${#value} -ne 64 || "$value" == *[!0-9A-Fa-f]* ]]; then
    fail_with_usage "$label must be a 64 character SHA-256 hex digest: $value"
  fi
}

require_volatile_dist_layout() {
  local peer_config_count peer_storage_count

  [[ -d "$volatile_dist" ]] || fail_with_usage "volatile-dist directory does not exist: $volatile_dist"

  if [[ ! -e "$volatile_dist/start.sh" ]]; then
    if [[ -d "$volatile_dist/bin" && ( -f "$volatile_dist/rollout.manifest.json" || -f "$volatile_dist/sha256sums.txt" ) ]]; then
      fail_with_usage "volatile-dist appears to be a rollout binary bundle, not a rendered Taira validator dist; provide a dist root containing start.sh, peer*.toml, and storage/peer*"
    fi
    fail_with_usage "volatile-dist is missing start.sh: $(soraswap_display_path "$volatile_dist")/start.sh"
  fi

  [[ -x "$volatile_dist/start.sh" ]] || fail_with_usage "volatile-dist start.sh is not executable: $(soraswap_display_path "$volatile_dist")/start.sh"
  peer_config_count="$(find "$volatile_dist" -maxdepth 1 -type f -name 'peer*.toml' -print 2>/dev/null | wc -l | tr -d '[:space:]')"
  [[ "$peer_config_count" != "0" ]] || fail_with_usage "volatile-dist is missing peer*.toml validator configs: $(soraswap_display_path "$volatile_dist")/peer*.toml"
  [[ -d "$volatile_dist/storage" ]] || fail_with_usage "volatile-dist is missing storage/peer* validator storage directories: $(soraswap_display_path "$volatile_dist")/storage/peer*"
  peer_storage_count="$(find "$volatile_dist/storage" -maxdepth 1 -type d -name 'peer*' -print 2>/dev/null | wc -l | tr -d '[:space:]')"
  [[ "$peer_storage_count" != "0" ]] || fail_with_usage "volatile-dist is missing storage/peer* validator storage directories: $(soraswap_display_path "$volatile_dist")/storage/peer*"
}

normalize_operator_platform() {
  local value="$1"
  local normalized

  normalized="${value:l}"
  case "$normalized" in
    darwin|macos)
      printf 'darwin\n'
      ;;
    linux|systemd)
      printf 'linux\n'
      ;;
    manual)
      printf 'manual\n'
      ;;
    *)
      fail_with_usage "operator-platform must be one of darwin, linux, or manual"
      ;;
  esac
}

normalize_torii_ports_csv() {
  local value="$1"
  local port trimmed port_number normalized
  typeset -a ports
  typeset -A seen_ports

  [[ -n "$value" ]] || fail_with_usage "volatile-torii-ports must contain at least one numeric port"

  ports=("${(@s:,:)value}")
  for port in "${ports[@]}"; do
    trimmed="$(printf '%s' "$port" | tr -d '[:space:]')"
    [[ -n "$trimmed" ]] || fail_with_usage "volatile-torii-ports contains an empty port entry"
    case "$trimmed" in
      *[!0-9]*)
        fail_with_usage "volatile-torii-ports must be a comma-separated list of numeric ports: $value"
        ;;
    esac
    port_number=$((10#$trimmed))
    if (( port_number < 1 || port_number > 65535 )); then
      fail_with_usage "volatile-torii-ports contains out-of-range port $trimmed; expected 1..65535"
    fi
    [[ -z "${seen_ports[$port_number]:-}" ]] || fail_with_usage "volatile-torii-ports contains duplicate port $port_number"
    seen_ports[$port_number]=1
    if [[ -z "$normalized" ]]; then
      normalized="$port_number"
    else
      normalized="${normalized},${port_number}"
    fi
  done
  printf '%s\n' "$normalized"
}

require_readable_file_path() {
  local label="$1"
  local input_path="$2"

  [[ -z "$input_path" ]] && return
  [[ -e "$input_path" ]] || fail_with_usage "$label does not exist: $input_path"
  [[ -f "$input_path" ]] || fail_with_usage "$label must be a file: $input_path"
  [[ -r "$input_path" ]] || fail_with_usage "$label is not readable: $input_path"
}

require_valid_json_file() {
  local label="$1"
  local input_path="$2"

  [[ -z "$input_path" ]] && return
  require_readable_file_path "$label" "$input_path"
  jq -e . "$input_path" >/dev/null || fail_with_usage "$label must contain valid JSON: $input_path"
}

sha256_file() {
  local input_path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$input_path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$input_path" | awk '{print $1}'
  else
    fail_with_usage "neither shasum nor sha256sum is available for runtime digest verification"
  fi
}

json_string_array_from_find() {
  local find_root="$1"
  shift

  if [[ ! -e "$find_root" ]]; then
    printf '[]\n'
    return
  fi

  find "$find_root" "$@" -print 2>/dev/null \
    | sort \
    | while IFS= read -r found_path; do
        soraswap_display_path "$found_path"
      done \
    | jq -R -s 'split("\n") | map(select(length > 0))'
}

storage_summary_json() {
  local label="$1"
  local storage_path="$2"
  local abs_storage snapshot_dir snapshot_dir_exists size_kib children_json snapshot_files_json transient_json

  [[ -d "$storage_path" ]] || fail_with_usage "$label storage directory does not exist: $storage_path"
  abs_storage="$(abs_path_existing "$storage_path")"
  snapshot_dir="$abs_storage/snapshot"
  snapshot_dir_exists=false
  [[ -d "$snapshot_dir" ]] && snapshot_dir_exists=true
  size_kib="$(du -sk "$abs_storage" | awk '{print $1}')"
  children_json="$(json_string_array_from_find "$abs_storage" -mindepth 1 -maxdepth 1)"
  snapshot_files_json="$(json_string_array_from_find "$snapshot_dir" -type f -maxdepth 3)"
  transient_json="$(json_string_array_from_find "$abs_storage" -maxdepth 4 \( -iname '*queue*' -o -iname '*pending*' -o -iname '*mempool*' -o -iname '*tmp*' -o -iname '*transient*' -o -iname 'rbc_sessions' -o -iname '*rbc*' \))"

  jq -cn \
    --arg label "$label" \
    --arg path "$(soraswap_display_path "$abs_storage")" \
    --arg snapshot_dir "$(soraswap_display_path "$snapshot_dir")" \
    --argjson snapshot_dir_exists "$snapshot_dir_exists" \
    --argjson size_kib "$size_kib" \
    --argjson children "$children_json" \
    --argjson snapshot_files "$snapshot_files_json" \
    --argjson transient_candidates "$transient_json" \
    '{
      label: $label,
      path: $path,
      size_kib: $size_kib,
      snapshot_dir: $snapshot_dir,
      snapshot_dir_exists: $snapshot_dir_exists,
      top_level_entries: $children,
      snapshot_files: $snapshot_files,
      transient_candidates: $transient_candidates
    }'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --donor-storage)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --donor-storage"
      donor_storage="$2"
      shift 2
      ;;
    --target-storage)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --target-storage"
      target_storages+=("$2")
      shift 2
      ;;
    --reason)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --reason"
      reason="$2"
      shift 2
      ;;
    --height)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --height"
      height="$2"
      shift 2
      ;;
    --parent-root)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --parent-root"
      parent_root="$2"
      shift 2
      ;;
    --post-root)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --post-root"
      post_root="$2"
      shift 2
      ;;
    --snapshot-policy)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --snapshot-policy"
      snapshot_policy="$2"
      shift 2
      ;;
    --operator)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --operator"
      operator="$2"
      shift 2
      ;;
    --operator-platform)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --operator-platform"
      operator_platform="$2"
      shift 2
      ;;
    --trace-config)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --trace-config"
      trace_config_path="$2"
      shift 2
      ;;
    --status-json)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --status-json"
      status_json_path="$2"
      shift 2
      ;;
    --volatile-dist)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --volatile-dist"
      volatile_dist="$2"
      shift 2
      ;;
    --volatile-runtime-bin)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --volatile-runtime-bin"
      volatile_runtime_bin="$2"
      shift 2
      ;;
    --volatile-expected-runtime-sha)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --volatile-expected-runtime-sha"
      volatile_expected_runtime_sha="$2"
      shift 2
      ;;
    --volatile-torii-ports)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --volatile-torii-ports"
      volatile_torii_ports="$2"
      volatile_torii_ports_supplied=true
      shift 2
      ;;
    --report-dir)
      [[ $# -ge 2 ]] || fail_with_usage "missing value for --report-dir"
      report_dir="$2"
      latest_report="$report_dir/taira_state_repair_plan.latest.json"
      timestamped_report="$report_dir/taira_state_repair_plan.${timestamp}.json"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail_with_usage "unknown argument: $1"
      ;;
  esac
done

if [[ -n "${SORASWAP_TAIRA_REPAIR_TARGET_STORAGES:-}" ]]; then
  target_storages+=("${(@s/:/)SORASWAP_TAIRA_REPAIR_TARGET_STORAGES}")
fi

volatile_inputs_supplied=false
if [[ -n "$volatile_dist$volatile_runtime_bin$volatile_expected_runtime_sha" || "$volatile_torii_ports_supplied" == true ]]; then
  volatile_inputs_supplied=true
fi
state_repair_enabled=true
repair_mode="state_snapshot_repair"
if [[ -z "$donor_storage" && ${#target_storages[@]} -eq 0 && "$volatile_inputs_supplied" == true ]]; then
  state_repair_enabled=false
  repair_mode="volatile_consensus_quarantine"
fi

if [[ "$state_repair_enabled" == true ]]; then
  [[ -n "$donor_storage" ]] || fail_with_usage "missing donor storage"
  (( ${#target_storages[@]} > 0 )) || fail_with_usage "missing at least one target storage"
  [[ -d "$donor_storage" ]] || fail_with_usage "donor storage directory does not exist: $donor_storage"
else
  [[ "$volatile_inputs_supplied" == true ]] || fail_with_usage "missing donor storage"
fi
require_nonnegative_integer height "$height"
require_hex_root parent-root "$parent_root"
require_hex_root post-root "$post_root"
operator_platform="$(normalize_operator_platform "$operator_platform")"
require_readable_file_path trace-config "$trace_config_path"
require_valid_json_file status-json "$status_json_path"
require_sha256_hex volatile-expected-runtime-sha "$volatile_expected_runtime_sha"

donor_abs=""
donor_json="null"
targets_json="[]"
typeset -a target_abs_paths
typeset -A seen_target_storages
if [[ "$state_repair_enabled" == true ]]; then
  donor_abs="$(abs_path_existing "$donor_storage")"
  for target_storage in "${target_storages[@]}"; do
    [[ -d "$target_storage" ]] || fail_with_usage "target storage directory does not exist: $target_storage"
    target_abs="$(abs_path_existing "$target_storage")"
    [[ "$target_abs" != "$donor_abs" ]] || fail_with_usage "target storage must differ from donor storage: $(soraswap_display_path "$target_abs")"
    [[ -z "${seen_target_storages[$target_abs]:-}" ]] || fail_with_usage "duplicate target storage: $(soraswap_display_path "$target_abs")"
    seen_target_storages[$target_abs]=1
    target_abs_paths+=("$target_abs")
  done

  donor_json="$(storage_summary_json donor "$donor_abs")"
  for target_storage in "${target_abs_paths[@]}"; do
    target_json="$(storage_summary_json target "$target_storage")"
    targets_json="$(jq -cn --argjson existing "$targets_json" --argjson next "$target_json" '$existing + [$next]')"
  done
fi

trace_config_abs=""
if [[ -n "$trace_config_path" ]]; then
  trace_config_abs="$(abs_path_existing "$trace_config_path")"
fi
status_json_abs=""
if [[ -n "$status_json_path" ]]; then
  status_json_abs="$(abs_path_existing "$status_json_path")"
fi

volatile_enabled=false
volatile_dist_abs=""
volatile_runtime_abs=""
volatile_actual_runtime_sha=""
volatile_torii_ports_normalized=""
volatile_json="null"
if [[ "$volatile_inputs_supplied" == true ]]; then
  volatile_enabled=true
  [[ -n "$volatile_dist" ]] || fail_with_usage "volatile-dist is required when volatile repair inputs are supplied"
  [[ -n "$volatile_runtime_bin" ]] || fail_with_usage "volatile-runtime-bin is required when volatile repair inputs are supplied"
  [[ -n "$volatile_expected_runtime_sha" ]] || fail_with_usage "volatile-expected-runtime-sha is required when volatile repair inputs are supplied"
  require_volatile_dist_layout
  [[ -f "$volatile_runtime_bin" ]] || fail_with_usage "volatile-runtime-bin does not exist: $volatile_runtime_bin"
  [[ -x "$volatile_runtime_bin" ]] || fail_with_usage "volatile-runtime-bin is not executable: $volatile_runtime_bin"
  volatile_torii_ports_normalized="$(normalize_torii_ports_csv "$volatile_torii_ports")"
  volatile_dist_abs="$(abs_path_existing "$volatile_dist")"
  volatile_runtime_abs="$(abs_path_existing "$volatile_runtime_bin")"
  volatile_actual_runtime_sha="$(sha256_file "$volatile_runtime_abs")"
  volatile_actual_runtime_sha_lower="${volatile_actual_runtime_sha:l}"
  volatile_expected_runtime_sha_lower="${volatile_expected_runtime_sha:l}"
  [[ "$volatile_actual_runtime_sha_lower" == "$volatile_expected_runtime_sha_lower" ]] || \
    fail_with_usage "volatile runtime SHA mismatch: expected ${volatile_expected_runtime_sha}, got ${volatile_actual_runtime_sha}"
  volatile_json="$(jq -cn \
    --arg dist "$(soraswap_display_path "$volatile_dist_abs")" \
    --arg runtime_bin "$(soraswap_display_path "$volatile_runtime_abs")" \
    --arg expected_runtime_sha "$volatile_expected_runtime_sha" \
    --arg actual_runtime_sha "$volatile_actual_runtime_sha" \
    --arg torii_ports "$volatile_torii_ports_normalized" \
    '{
      enabled: true,
      mutation_performed: false,
      helper: "../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh",
      dist: $dist,
      runtime_bin: $runtime_bin,
      expected_runtime_sha: $expected_runtime_sha,
      actual_runtime_sha: $actual_runtime_sha,
      runtime_sha_matches: true,
      start_after_quarantine: true,
      torii_ports: $torii_ports,
      apply_requires_peer_owner_or_sudo: true,
      dry_run_must_not_report_apply_completion: true,
      dry_run_warning_exit_status: 2,
      dry_run_command: "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
      apply_command: "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply"
    }')"
fi

case "$operator_platform" in
  darwin)
    if [[ "$state_repair_enabled" == true ]]; then
      operator_action_templates="$(jq -cn '[
        "operator-approved stop peer processes launched from the Taira dist",
        "sudo rsync -a --numeric-ids <target-storage>/ <backup-dir>/",
        "sudo rsync -a --numeric-ids <donor-approved-state-artifacts>/ <target-storage>/",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "operator-approved restart through the Taira dist/start.sh or supervisor already used by the host"
      ]')"
    else
      operator_action_templates="$(jq -cn '[
        "operator-approved stop peer processes launched from the Taira dist",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "operator-approved restart through the Taira dist/start.sh or supervisor already used by the host"
      ]')"
    fi
    ;;
  linux)
    if [[ "$state_repair_enabled" == true ]]; then
      operator_action_templates="$(jq -cn '[
        "sudo systemctl stop taira-irohad.service",
        "sudo rsync -a --numeric-ids <target-storage>/ <backup-dir>/",
        "sudo rsync -a --numeric-ids <donor-approved-state-artifacts>/ <target-storage>/",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "sudo systemctl start taira-irohad.service"
      ]')"
    else
      operator_action_templates="$(jq -cn '[
        "sudo systemctl stop taira-irohad.service",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "sudo systemctl start taira-irohad.service"
      ]')"
    fi
    ;;
  manual)
    if [[ "$state_repair_enabled" == true ]]; then
      operator_action_templates="$(jq -cn '[
        "operator-approved stop peer processes",
        "operator-approved backup of each target storage directory",
        "operator-approved copy of donor persistent state artifacts",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "operator-approved restart of recovered peers"
      ]')"
    else
      operator_action_templates="$(jq -cn '[
        "operator-approved stop peer processes",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
        "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports> --apply",
        "operator-approved restart of recovered peers"
      ]')"
    fi
    ;;
esac

if [[ "$state_repair_enabled" == true ]]; then
  required_manual_checks="$(jq -cn '[
    "confirm donor and targets are stopped before any storage mutation",
    "confirm donor height, parent root, and post root match the rollout incident record",
    "confirm target snapshot verification policy and sidecars are compatible with the donor",
    "back up each target storage directory before copying state",
    "copy only operator-approved persistent state artifacts",
    "clear only transient consensus queues and RBC sessions after state copy",
    "run the volatile consensus quarantine helper without --apply first and treat warning exit status 2 as not apply-ready",
    "run the volatile consensus quarantine helper with --apply only as the peer process owner or with sudo after the runtime digest matches",
    "restart one target first and verify /status, /v1/mcp, validator-set, and SoraSwap preflight before rolling forward more peers"
  ]')"
  proposed_non_destructive_commands="$(jq -cn '[
    "sudo find <target-storage> -maxdepth 4 \\( -iname \"*queue*\" -o -iname \"*rbc*\" \\) -print",
    "bash ../iroha/configs/soranexus/taira/check_mcp_rollout.sh --skip-local --public-root \"$PUBLIC_TORII_ROOT\" --skip-write-canary"
  ]')"
else
  required_manual_checks="$(jq -cn '[
    "confirm peer processes launched from the Taira dist are stopped before any volatile-state mutation",
    "confirm the runtime digest matches the approved rollout binary before any restart",
    "quarantine only queue_plan_journal* and rbc_sessions; preserve durable ledger state, validator keys, snapshots, configs, and snapshot signer material",
    "run the volatile consensus quarantine helper without --apply first and treat warning exit status 2 as not apply-ready",
    "run the volatile consensus quarantine helper with --apply only as the peer process owner or with sudo after the runtime digest matches",
    "verify /status, /v1/mcp, validator-set, and SoraSwap preflight after restart before any signed public mutation"
  ]')"
  proposed_non_destructive_commands="$(jq -cn '[
    "find <dist>/storage -maxdepth 2 \\( -name \"queue_plan_journal*\" -o -name \"rbc_sessions\" \\) -print",
    "bash ../iroha/configs/soranexus/taira/clear_volatile_consensus_state.sh --dist <dist> --runtime-bin <runtime-bin> --expected-runtime-sha <sha256> --start --torii-ports <ports>",
    "bash ../iroha/configs/soranexus/taira/check_mcp_rollout.sh --skip-local --public-root \"$PUBLIC_TORII_ROOT\" --skip-write-canary"
  ]')"
fi

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg repair_mode "$repair_mode" \
  --arg reason "$(soraswap_redact_sensitive_text "$reason")" \
  --arg height "$height" \
  --arg parent_root "$parent_root" \
  --arg post_root "$post_root" \
  --arg snapshot_policy "$(soraswap_redact_sensitive_text "$snapshot_policy")" \
  --arg operator "$(soraswap_redact_sensitive_text "$operator")" \
  --arg operator_platform "$operator_platform" \
  --arg trace_config_path "$(soraswap_display_path "$trace_config_abs")" \
  --arg status_json_path "$(soraswap_display_path "$status_json_abs")" \
  --argjson volatile_enabled "$volatile_enabled" \
  --argjson volatile_consensus_quarantine "$volatile_json" \
  --argjson operator_action_templates "$operator_action_templates" \
  --argjson required_manual_checks "$required_manual_checks" \
  --argjson proposed_non_destructive_commands "$proposed_non_destructive_commands" \
  --argjson donor "$donor_json" \
  --argjson targets "$targets_json" \
  '{
    generated_at: $generated_at,
    status: "plan_created",
    environment: $environment,
    repair_mode: $repair_mode,
    dry_run: true,
    mutation_performed: false,
    donor: $donor,
    targets: $targets,
    volatile_consensus_quarantine: $volatile_consensus_quarantine,
    operator_inputs: {
      reason: (if $reason == "" then null else $reason end),
      height: (if $height == "" then null else $height end),
      parent_root: (if $parent_root == "" then null else $parent_root end),
      post_root: (if $post_root == "" then null else $post_root end),
      snapshot_policy: (if $snapshot_policy == "" then null else $snapshot_policy end),
      operator: (if $operator == "" then null else $operator end),
      operator_platform: $operator_platform,
      trace_config_path: (if $trace_config_path == "" then null else $trace_config_path end),
      status_json_path: (if $status_json_path == "" then null else $status_json_path end),
      volatile_quarantine_enabled: $volatile_enabled
    },
    required_manual_checks: $required_manual_checks,
    operator_action_templates: $operator_action_templates,
    proposed_non_destructive_commands: $proposed_non_destructive_commands,
    post_repair_verification_commands: [
      "SORASWAP_ALLOW_TESTNET_MUTATIONS=1 SORASWAP_SKIP_IROHA_CLI_BUILD=1 make taira-preflight"
    ]
  }')"

mkdir -p "$report_dir"
soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

echo "taira repair plan: wrote $(soraswap_display_path "$latest_report")"
