#!/bin/zsh
set -euo pipefail

ROOT="${SORASWAP_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
source "$ROOT/scripts/common.sh"

public_env="${SORASWAP_PUBLIC_ENV:-testnet}"
case "$public_env" in
  testnet)
    ;;
  *)
    echo "taira diagnosis only supports SORASWAP_PUBLIC_ENV=testnet; got $public_env" >&2
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
trace_config_path="${SORASWAP_TAIRA_REPAIR_TRACE_CONFIG:-}"
status_json_path="${SORASWAP_TAIRA_REPAIR_STATUS_JSON:-}"
report_dir="${SORASWAP_TAIRA_REPAIR_REPORT_DIR:-$(deployments_dir_for_env "$public_env")}"
timestamp="$(utc_timestamp)"
latest_report="$report_dir/taira_state_repair_plan.latest.json"
timestamped_report="$report_dir/taira_state_repair_plan.${timestamp}.json"
typeset -a target_storages

usage() {
  cat >&2 <<EOF
Usage: $0 --donor-storage DIR --target-storage DIR [--target-storage DIR ...] [options]

Options:
  --reason TEXT
  --height HEIGHT
  --parent-root HEX
  --post-root HEX
  --snapshot-policy TEXT
  --operator TEXT
  --trace-config PATH
  --status-json PATH
  --report-dir DIR

This command writes diagnosis-only JSON evidence. It inventories the supplied
storage and evidence files without copying, deleting, stopping, restarting, or
modifying validator state. The report never authorizes a repair operation.

Prefer SORASWAP_TAIRA_REPAIR_REASON, SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY,
and SORASWAP_TAIRA_REPAIR_OPERATOR for sensitive free-form notes; command-line
arguments can be visible in local process listings while the helper runs.
EOF
}

fail_with_usage() {
  echo "taira diagnosis: $(soraswap_redact_sensitive_text "$*")" >&2
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

[[ -n "$donor_storage" ]] || fail_with_usage "missing donor storage"
(( ${#target_storages[@]} > 0 )) || fail_with_usage "missing at least one target storage"
[[ -d "$donor_storage" ]] || fail_with_usage "donor storage directory does not exist: $donor_storage"
require_nonnegative_integer height "$height"
require_hex_root parent-root "$parent_root"
require_hex_root post-root "$post_root"
require_readable_file_path trace-config "$trace_config_path"
require_valid_json_file status-json "$status_json_path"

donor_abs="$(abs_path_existing "$donor_storage")"
donor_json="$(storage_summary_json donor "$donor_abs")"
targets_json="[]"
typeset -a target_abs_paths
typeset -A seen_target_storages
for target_storage in "${target_storages[@]}"; do
  [[ -d "$target_storage" ]] || fail_with_usage "target storage directory does not exist: $target_storage"
  target_abs="$(abs_path_existing "$target_storage")"
  [[ "$target_abs" != "$donor_abs" ]] || fail_with_usage "target storage must differ from donor storage: $(soraswap_display_path "$target_abs")"
  [[ -z "${seen_target_storages[$target_abs]:-}" ]] || fail_with_usage "duplicate target storage: $(soraswap_display_path "$target_abs")"
  seen_target_storages[$target_abs]=1
  target_abs_paths+=("$target_abs")
done

for target_storage in "${target_abs_paths[@]}"; do
  target_json="$(storage_summary_json target "$target_storage")"
  targets_json="$(jq -cn --argjson existing "$targets_json" --argjson next "$target_json" '$existing + [$next]')"
done

trace_config_abs=""
if [[ -n "$trace_config_path" ]]; then
  trace_config_abs="$(abs_path_existing "$trace_config_path")"
fi
status_json_abs=""
if [[ -n "$status_json_path" ]]; then
  status_json_abs="$(abs_path_existing "$status_json_path")"
fi

report_json="$(jq -cn \
  --arg generated_at "$timestamp" \
  --arg environment "$public_env" \
  --arg reason "$(soraswap_redact_sensitive_text "$reason")" \
  --arg height "$height" \
  --arg parent_root "$parent_root" \
  --arg post_root "$post_root" \
  --arg snapshot_policy "$(soraswap_redact_sensitive_text "$snapshot_policy")" \
  --arg operator "$(soraswap_redact_sensitive_text "$operator")" \
  --arg trace_config_path "$(soraswap_display_path "$trace_config_abs")" \
  --arg status_json_path "$(soraswap_display_path "$status_json_abs")" \
  --argjson donor "$donor_json" \
  --argjson targets "$targets_json" \
  '{
    generated_at: $generated_at,
    status: "diagnosis_created",
    environment: $environment,
    diagnosis_mode: "state_snapshot_evidence",
    mutation_performed: false,
    repair_authorized: false,
    donor: $donor,
    targets: $targets,
    operator_inputs: {
      reason: (if $reason == "" then null else $reason end),
      height: (if $height == "" then null else $height end),
      parent_root: (if $parent_root == "" then null else $parent_root end),
      post_root: (if $post_root == "" then null else $post_root end),
      snapshot_policy: (if $snapshot_policy == "" then null else $snapshot_policy end),
      operator: (if $operator == "" then null else $operator end),
      trace_config_path: (if $trace_config_path == "" then null else $trace_config_path end),
      status_json_path: (if $status_json_path == "" then null else $status_json_path end)
    },
    diagnostic_checks: [
      "compare donor and target snapshot inventories against the incident record",
      "review transient candidate paths as evidence only; do not mutate validator storage",
      "confirm height and state roots with the current public Taira doctor output"
    ],
    verification_commands: [
      "iroha -c \"$SORASWAP_CLIENT_CONFIG\" taira doctor --public-root \"$PUBLIC_TORII_ROOT\" --json"
    ]
  }')"

mkdir -p "$report_dir"
soraswap_write_json_report_pair "$report_json" "$latest_report" "$timestamped_report"

echo "taira diagnosis: wrote $(soraswap_display_path "$latest_report")"
