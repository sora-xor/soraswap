#!/bin/zsh
# Shared fail-closed evidence helpers for the dedicated validation-fee release.

if [[ -z "${SORASWAP_ROOT:-}" ]]; then
  readonly SORASWAP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

readonly VALIDATION_FEE_ONE_WRITE_PAUSE_STATUS="paused_after_applied_write"
readonly VALIDATION_FEE_ONE_WRITE_PAUSE_RETURN_STATUS=75
typeset -g VALIDATION_FEE_APPLY_LOCK_DIR=""
typeset -g VALIDATION_FEE_APPLY_LOCK_TOKEN=""
typeset -g VALIDATION_FEE_APPLY_LOCK_OWNED=0

validation_fee_isolated_python() {
  local requested_python="${SORASWAP_VALIDATION_FEE_PYTHON_BIN:-/opt/homebrew/bin/python3}"
  local python_bin="${requested_python:A}"

  [[ "$requested_python" == /* && "$python_bin" == /* \
    && "$python_bin" == "${python_bin:A}" \
    && -f "$python_bin" && ! -L "$python_bin" && -x "$python_bin" ]] || {
    echo "validation-fee Python runtime must be an absolute canonical executable" >&2
    return 1
  }
  /usr/bin/env -i \
    LANG=C \
    LC_ALL=C \
    PATH=/usr/bin:/bin \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONHASHSEED=0 \
    PYTHONNOUSERSITE=1 \
    PYTHONUTF8=1 \
    TZ=UTC \
      "$python_bin" -I -S "$@"
}

validation_fee_bound_plan_sha256() {
  local evidence_path="${SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH:-}"
  local expected_sha256="${SORASWAP_VALIDATION_FEE_REVIEWED_PLAN_SHA256:-}"
  local actual_sha256

  [[ -n "$evidence_path" && "$evidence_path" == /* \
    && "$evidence_path" == "${evidence_path:A}" ]] || {
    echo "validation-fee writes require the canonical immutable P1 plan-evidence path" >&2
    return 1
  }
  [[ "$expected_sha256" =~ '^[0-9a-f]{64}$' \
    && "$expected_sha256" != '0000000000000000000000000000000000000000000000000000000000000000' ]] || {
    echo "validation-fee writes require the resolved reviewed P1 plan SHA-256" >&2
    return 1
  }
  actual_sha256="$(
    validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/validate_validation_fee_plan_binding.py" \
      --plan-evidence "$evidence_path" \
      --expected-plan-sha256 "$expected_sha256"
  )" || return 1
  [[ "$actual_sha256" == "$expected_sha256" ]] || {
    echo "validation-fee plan validator returned a different reviewed digest" >&2
    return 1
  }
  printf '%s\n' "$actual_sha256"
}

validation_fee_taira_p1_apply_lock_dir() {
  local state_root lock_dir

  state_root="$(validation_fee_taira_p1_state_root)" || return 1
  lock_dir="$state_root/apply.lock"
  printf '%s\n' "$lock_dir"
}

validation_fee_taira_p1_state_root() {
  local requested="${SORASWAP_VALIDATION_FEE_STATE_ROOT:-}"
  local source_root="${SORASWAP_ROOT:A}"
  local state_root state_parent mode

  [[ -n "$requested" && "$requested" == /* ]] || {
    echo "validation-fee apply requires an absolute external SORASWAP_VALIDATION_FEE_STATE_ROOT" >&2
    return 1
  }
  state_root="${requested:A}"
  if [[ "$requested" != "$state_root" ]]; then
    echo "validation-fee state root must be canonical and contain no symlink traversal" >&2
    return 1
  fi
  if [[ "$state_root" == "$source_root" || "$state_root" == "$source_root/"* ]]; then
    echo "validation-fee durable state must remain outside the source/evidence tree" >&2
    return 1
  fi
  state_parent="${state_root:h}"
  [[ -d "$state_parent" && ! -L "$state_parent" \
    && "${state_parent:A}" == "$state_parent" ]] || {
    echo "validation-fee state-root parent must be an existing canonical directory" >&2
    return 1
  }
  if [[ -L "$state_root" || ( -e "$state_root" && ! -d "$state_root" ) ]]; then
    echo "validation-fee state root must be a real directory" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "$state_root" || return 1
  mode="$(stat -f '%Lp' "$state_root" 2>/dev/null \
    || stat -c '%a' "$state_root" 2>/dev/null)" || return 1
  [[ "$mode" == "700" ]] || {
    echo "validation-fee state root must be mode 0700" >&2
    return 1
  }
  printf '%s\n' "$state_root"
}

validation_fee_bound_root_identity_sha256() {
  local root_path="$1"
  local root_role="$2"
  local allow_create="$3"
  local binding_path="$root_path/root.binding.json"
  local root_uuid binding_json

  [[ "$root_role" == "evidence" || "$root_role" == "work" ]] || return 1
  if [[ ! -e "$binding_path" ]]; then
    (( allow_create == 1 )) || {
      echo "validation-fee $root_role root identity disappeared" >&2
      return 1
    }
    root_uuid="$(
      LC_ALL=C od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]'
    )" || return 1
    [[ "$root_uuid" =~ '^[0-9a-f]{64}$' ]] || return 1
    binding_json="$(jq -cn \
      --arg root_role "$root_role" \
      --arg canonical_root "$root_path" \
      --arg root_uuid "$root_uuid" \
      '{
        schema_version: 1,
        phase: "validation_fee_bound_root",
        root_role: $root_role,
        canonical_root: $canonical_root,
        root_uuid: $root_uuid
      }')"
    validation_fee_write_immutable_json \
      "$binding_json" "$binding_path" >/dev/null || return 1
  fi
  validation_fee_require_immutable_json_file "$binding_path" || return 1
  if ! jq -e \
    --arg root_role "$root_role" \
    --arg canonical_root "$root_path" \
    '
      .schema_version == 1
      and .phase == "validation_fee_bound_root"
      and .root_role == $root_role
      and .canonical_root == $canonical_root
      and (.root_uuid | type == "string" and test("^[0-9a-f]{64}$"))
      and (
        keys == [
          "canonical_root",
          "phase",
          "root_role",
          "root_uuid",
          "schema_version"
        ]
      )
    ' "$binding_path" >/dev/null; then
    echo "validation-fee $root_role root identity is invalid" >&2
    return 1
  fi
  shasum -a 256 "$binding_path" | awk '{print $1}'
}

validation_fee_taira_p1_state_binding_sha256() {
  local producer_sha256="$1"
  local allow_create="${2:-0}"
  local evidence_root="$3"
  local work_root="$4"
  local state_root binding_path binding_json state_uuid
  local evidence_root_binding_sha256 work_root_binding_sha256

  [[ "$producer_sha256" =~ '^[0-9a-f]{64}$' ]] || {
    echo "validation-fee state binding requires the reviewed producer digest" >&2
    return 1
  }
  [[ "$allow_create" == "0" || "$allow_create" == "1" ]] || return 1
  [[ -n "$evidence_root" && "$evidence_root" == /* \
    && "$evidence_root" == "${evidence_root:A}" \
    && -d "$evidence_root" && ! -L "$evidence_root" ]] || {
    echo "validation-fee state binding requires the canonical evidence root" >&2
    return 1
  }
  [[ -n "$work_root" && "$work_root" == /* \
    && "$work_root" == "${work_root:A}" \
    && -d "$work_root" && ! -L "$work_root" ]] || {
    echo "validation-fee state binding requires the canonical work root" >&2
    return 1
  }
  state_root="$(validation_fee_taira_p1_state_root)" || return 1
  evidence_root_binding_sha256="$(
    validation_fee_bound_root_identity_sha256 \
      "$evidence_root" evidence "$allow_create"
  )" || return 1
  work_root_binding_sha256="$(
    validation_fee_bound_root_identity_sha256 \
      "$work_root" work "$allow_create"
  )" || return 1
  binding_path="$state_root/state.binding.json"
  if [[ ! -e "$binding_path" ]]; then
    (( allow_create == 1 )) || {
      echo "immutable validation-fee state binding disappeared" >&2
      return 1
    }
    state_uuid="$(
      LC_ALL=C od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]'
    )" || return 1
    [[ "$state_uuid" =~ '^[0-9a-f]{64}$' ]] || return 1
    binding_json="$(jq -cn \
      --arg chain_id fc56984b-2be7-431d-840e-21514d1883f0 \
      --arg release p1 \
      --arg canonical_state_root "$state_root" \
      --arg canonical_evidence_root "$evidence_root" \
      --arg canonical_work_root "$work_root" \
      --arg evidence_root_binding_sha256 "$evidence_root_binding_sha256" \
      --arg work_root_binding_sha256 "$work_root_binding_sha256" \
      --arg state_uuid "$state_uuid" \
      --arg gate_command_sha256 "$producer_sha256" \
      '{
        schema_version: 1,
        phase: "validation_fee_state_binding",
        chain_id: $chain_id,
        release: $release,
        canonical_state_root: $canonical_state_root,
        canonical_evidence_root: $canonical_evidence_root,
        canonical_work_root: $canonical_work_root,
        evidence_root_binding_sha256: $evidence_root_binding_sha256,
        work_root_binding_sha256: $work_root_binding_sha256,
        state_uuid: $state_uuid,
        gate_command_sha256: $gate_command_sha256
      }')"
    validation_fee_write_immutable_json \
      "$binding_json" "$binding_path" >/dev/null || return 1
  fi
  validation_fee_require_immutable_json_file "$binding_path" || return 1
  if ! jq -e \
    --arg state_root "$state_root" \
    --arg evidence_root "$evidence_root" \
    --arg work_root "$work_root" \
    --arg evidence_root_binding_sha256 "$evidence_root_binding_sha256" \
    --arg work_root_binding_sha256 "$work_root_binding_sha256" \
    --arg gate_command_sha256 "$producer_sha256" \
    '
      .schema_version == 1
      and .phase == "validation_fee_state_binding"
      and .chain_id == "fc56984b-2be7-431d-840e-21514d1883f0"
      and .release == "p1"
      and .canonical_state_root == $state_root
      and .canonical_evidence_root == $evidence_root
      and .canonical_work_root == $work_root
      and .evidence_root_binding_sha256 == $evidence_root_binding_sha256
      and .work_root_binding_sha256 == $work_root_binding_sha256
      and (.state_uuid | type == "string" and test("^[0-9a-f]{64}$"))
      and .gate_command_sha256 == $gate_command_sha256
      and (
        keys == [
          "canonical_evidence_root",
          "canonical_state_root",
          "canonical_work_root",
          "chain_id",
          "evidence_root_binding_sha256",
          "gate_command_sha256",
          "phase",
          "release",
          "schema_version",
          "state_uuid",
          "work_root_binding_sha256"
        ]
      )
    ' "$binding_path" >/dev/null; then
    echo "validation-fee state binding differs from this chain/P1/producer" >&2
    return 1
  fi
  shasum -a 256 "$binding_path" | awk '{print $1}'
}

validation_fee_taira_p1_invocation_journal_dir() {
  local state_dir

  state_dir="$(validation_fee_taira_p1_state_root)" || return 1
  printf '%s/invocations\n' "$state_dir"
}

validation_fee_acquire_apply_lock() {
  local lock_dir="$1"
  local owner_path token owner_json

  [[ -n "$lock_dir" && "$lock_dir" == /* ]] || {
    echo "validation-fee apply lock path must be absolute" >&2
    return 1
  }
  [[ -d "${lock_dir:h}" && ! -L "${lock_dir:h}" ]] || {
    echo "validation-fee apply lock parent must be a real directory" >&2
    return 1
  }
  if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "another validation-fee apply invocation holds the exclusive lock: $lock_dir" >&2
    return 1
  fi
  chmod 0700 "$lock_dir" || {
    rmdir "$lock_dir" 2>/dev/null || true
    return 1
  }
  token="$(
    printf '%s:%s:%s:%s\n' "$$" "$PPID" "$RANDOM" "$(date -u +%s)" \
      | shasum -a 256 \
      | awk '{print $1}'
  )" || {
    rmdir "$lock_dir" 2>/dev/null || true
    return 1
  }
  owner_path="$lock_dir/owner.json"
  owner_json="$(jq -cn \
    --arg lock_dir "$lock_dir" \
    --arg token "$token" \
    --argjson owner_pid "$$" \
    '{
      schema_version: 1,
      phase: "validation_fee_apply_lock",
      lock_dir: $lock_dir,
      owner_pid: $owner_pid,
      token: $token
    }')"
  validation_fee_write_immutable_json "$owner_json" "$owner_path" >/dev/null \
    || {
      chmod u+w "$owner_path" 2>/dev/null || true
      rm -f "$owner_path"
      rmdir "$lock_dir" 2>/dev/null || true
      return 1
    }
  VALIDATION_FEE_APPLY_LOCK_DIR="$lock_dir"
  VALIDATION_FEE_APPLY_LOCK_TOKEN="$token"
  VALIDATION_FEE_APPLY_LOCK_OWNED=1
}

validation_fee_borrow_parent_apply_lock() {
  local lock_dir="$1"
  local token="$2"
  local owner_path="$lock_dir/owner.json"
  local mode

  [[ -n "$lock_dir" && "$lock_dir" == /* ]] || {
    echo "parent validation-fee apply lock path must be absolute" >&2
    return 1
  }
  [[ "$token" =~ '^[0-9a-f]{64}$' ]] || {
    echo "parent validation-fee apply lock token is invalid" >&2
    return 1
  }
  [[ -d "$lock_dir" && ! -L "$lock_dir" ]] || {
    echo "parent validation-fee apply lock is not held" >&2
    return 1
  }
  mode="$(stat -f '%Lp' "$lock_dir" 2>/dev/null \
    || stat -c '%a' "$lock_dir" 2>/dev/null)" || return 1
  [[ "$mode" == "700" ]] || {
    echo "parent validation-fee apply lock must be mode 0700" >&2
    return 1
  }
  validation_fee_require_immutable_json_file "$owner_path" || return 1
  if ! jq -e \
    --arg lock_dir "$lock_dir" \
    --arg token "$token" \
    '
      .schema_version == 1
      and .phase == "validation_fee_apply_lock"
      and .lock_dir == $lock_dir
      and (.owner_pid | type == "number" and . >= 1)
      and .token == $token
      and (
        keys
        == [
          "lock_dir",
          "owner_pid",
          "phase",
          "schema_version",
          "token"
        ]
      )
    ' "$owner_path" >/dev/null; then
    echo "parent validation-fee apply lock ownership proof is invalid" >&2
    return 1
  fi
  VALIDATION_FEE_APPLY_LOCK_DIR="$lock_dir"
  VALIDATION_FEE_APPLY_LOCK_TOKEN="$token"
  VALIDATION_FEE_APPLY_LOCK_OWNED=0
}

validation_fee_assert_apply_lock_held() {
  local expected_lock_dir owner_path mode

  expected_lock_dir="$(validation_fee_taira_p1_apply_lock_dir)" || return 1
  if [[ "$VALIDATION_FEE_APPLY_LOCK_DIR" != "$expected_lock_dir" \
    || ! "$VALIDATION_FEE_APPLY_LOCK_TOKEN" =~ '^[0-9a-f]{64}$' ]]; then
    echo "validation-fee mutation does not hold the fixed Taira P1 apply lock" >&2
    return 1
  fi
  [[ -d "$VALIDATION_FEE_APPLY_LOCK_DIR" \
    && ! -L "$VALIDATION_FEE_APPLY_LOCK_DIR" ]] || {
    echo "fixed Taira P1 validation-fee apply lock disappeared" >&2
    return 1
  }
  mode="$(stat -f '%Lp' "$VALIDATION_FEE_APPLY_LOCK_DIR" 2>/dev/null \
    || stat -c '%a' "$VALIDATION_FEE_APPLY_LOCK_DIR" 2>/dev/null)" \
    || return 1
  [[ "$mode" == "700" ]] || {
    echo "fixed Taira P1 validation-fee apply lock is not mode 0700" >&2
    return 1
  }
  owner_path="$VALIDATION_FEE_APPLY_LOCK_DIR/owner.json"
  validation_fee_require_immutable_json_file "$owner_path" || return 1
  jq -e \
    --arg lock_dir "$VALIDATION_FEE_APPLY_LOCK_DIR" \
    --arg token "$VALIDATION_FEE_APPLY_LOCK_TOKEN" \
    '
      .schema_version == 1
      and .phase == "validation_fee_apply_lock"
      and .lock_dir == $lock_dir
      and .token == $token
    ' "$owner_path" >/dev/null || {
    echo "fixed Taira P1 validation-fee apply lock ownership changed" >&2
    return 1
  }
}

validation_fee_release_apply_lock() {
  local owner_path owner_token

  if [[ -z "$VALIDATION_FEE_APPLY_LOCK_DIR" ]]; then
    return 0
  fi
  if (( VALIDATION_FEE_APPLY_LOCK_OWNED == 0 )); then
    VALIDATION_FEE_APPLY_LOCK_DIR=""
    VALIDATION_FEE_APPLY_LOCK_TOKEN=""
    return 0
  fi
  owner_path="$VALIDATION_FEE_APPLY_LOCK_DIR/owner.json"
  validation_fee_require_immutable_json_file "$owner_path" || return 1
  owner_token="$(jq -er '.token' "$owner_path")" || return 1
  [[ "$owner_token" == "$VALIDATION_FEE_APPLY_LOCK_TOKEN" ]] || {
    echo "refusing to release a validation-fee apply lock owned by another invocation" >&2
    return 1
  }
  chmod 0600 "$owner_path" || return 1
  rm -f "$owner_path" || return 1
  rmdir "$VALIDATION_FEE_APPLY_LOCK_DIR" || return 1
  VALIDATION_FEE_APPLY_LOCK_DIR=""
  VALIDATION_FEE_APPLY_LOCK_TOKEN=""
  VALIDATION_FEE_APPLY_LOCK_OWNED=0
}

validation_fee_require_one_write_mode() {
  local setting="${SORASWAP_VALIDATION_FEE_ONE_WRITE_PER_INVOCATION:-}"
  local invocation_id="${SORASWAP_VALIDATION_FEE_INVOCATION_ID:-}"
  local invocation_journal_dir="${SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR:-}"
  local required_journal_dir state_dir

  if [[ "$setting" != "1" ]]; then
    echo "validation-fee apply requires SORASWAP_VALIDATION_FEE_ONE_WRITE_PER_INVOCATION=1" >&2
    return 1
  fi
  if [[ -z "$invocation_id" ]]; then
    invocation_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
    export SORASWAP_VALIDATION_FEE_INVOCATION_ID="$invocation_id"
  fi
  if [[ ! "$invocation_id" =~ '^[0-9A-Za-z._-]+$' ]]; then
    echo "SORASWAP_VALIDATION_FEE_INVOCATION_ID contains unsafe characters" >&2
    return 1
  fi
  required_journal_dir="$(validation_fee_taira_p1_invocation_journal_dir)" \
    || return 1
  if [[ -n "$invocation_journal_dir" \
    && "${invocation_journal_dir:A}" != "${required_journal_dir:A}" ]]; then
    echo "validation-fee gate history must use the externally bound Taira P1 state directory" >&2
    return 1
  fi
  invocation_journal_dir="$required_journal_dir"
  state_dir="${invocation_journal_dir:h}"
  if [[ -L "$state_dir" || ( -e "$state_dir" && ! -d "$state_dir" ) ]]; then
    echo "external Taira P1 validation-fee state path must be a real directory" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "$state_dir" || return 1
  if [[ -L "$invocation_journal_dir" \
    || ( -e "$invocation_journal_dir" && ! -d "$invocation_journal_dir" ) ]]; then
    echo "validation-fee invocation journal must be a real directory" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "$invocation_journal_dir" || return 1
  export SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR="$invocation_journal_dir"
}

validation_fee_reviewed_gate_producer_sha256() {
  local command_path="$1"
  local expected_sha="$2"
  local command_sha mode ancestor executable_format

  [[ -n "$command_path" && "$command_path" == /* ]] || {
    echo "validation-fee writes require an absolute write-gate producer path" >&2
    return 1
  }
  [[ "$command_path" == "${command_path:A}" ]] || {
    echo "validation-fee write-gate producer path must be canonical and symlink-free" >&2
    return 1
  }
  [[ -f "$command_path" && ! -L "$command_path" && -x "$command_path" ]] || {
    echo "validation-fee write-gate producer must be an executable regular file" >&2
    return 1
  }
  executable_format="$(file -b "$command_path" 2>/dev/null)" || return 1
  if [[ "$executable_format" != *"Mach-O"*"executable"* \
    && "$executable_format" != *"ELF"*"executable"* ]]; then
    echo "validation-fee write-gate producer must be a reviewed native executable, not an interpreter script" >&2
    return 1
  fi
  [[ "$expected_sha" =~ '^[0-9a-f]{64}$' ]] || {
    echo "validation-fee write-gate producer pin must be lowercase SHA-256" >&2
    return 1
  }
  mode="$(stat -f '%Lp' "$command_path" 2>/dev/null \
    || stat -c '%a' "$command_path" 2>/dev/null)" || return 1
  if (( (8#$mode & 8#222) != 0 )) || [[ -w "$command_path" ]]; then
    echo "validation-fee write-gate producer must be operator-read-only" >&2
    return 1
  fi
  ancestor="${command_path:h}"
  while [[ "$ancestor" != "/" ]]; do
    [[ -d "$ancestor" && ! -L "$ancestor" \
      && "$ancestor" == "${ancestor:A}" ]] || {
      echo "validation-fee write-gate producer has a mutable or symlinked ancestor" >&2
      return 1
    }
    if [[ -w "$ancestor" ]]; then
      echo "validation-fee write-gate producer must live on a reviewed read-only mount" >&2
      return 1
    fi
    ancestor="${ancestor:h}"
  done
  command_sha="$(shasum -a 256 "$command_path" | awk '{print $1}')" \
    || return 1
  [[ "$command_sha" == "$expected_sha" ]] || {
    echo "validation-fee write-gate producer differs from its reviewed SHA-256" >&2
    return 1
  }
  printf '%s\n' "$command_sha"
}

validation_fee_write_gate_json() {
  local operation="$1"
  local command_path="${SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND:-}"
  local expected_sha="${SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND_SHA256:-}"
  local block_1_hash="${SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH:-}"
  local invocation_id="$SORASWAP_VALIDATION_FEE_INVOCATION_ID"
  local gate_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$invocation_id.gate.json"
  local request_path marker_path validated_path command_sha mode plan_sha256
  local previous='null' previous_file previous_sequence=0 sequence request_json
  local previous_command_sha
  local command_status=0 marker_size
  local -A observed_sequences=()
  local -a existing_gate_files

  validation_fee_assert_apply_lock_held || return 1
  validation_fee_validate_imminent_operation_json "$operation" || return 1
  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  if [[ "$(jq -er '.plan_sha256' <<<"$operation")" != "$plan_sha256" ]]; then
    echo "validation-fee imminent operation differs from the reviewed P1 plan" >&2
    return 1
  fi
  command_sha="$(
    validation_fee_reviewed_gate_producer_sha256 \
      "$command_path" "$expected_sha"
  )" || return 1
  if [[ ! "$block_1_hash" =~ '^[0-9a-f]{64}$' ]]; then
    echo "validation-fee write gate requires the reviewed lowercase block-1 SHA-256" >&2
    return 1
  fi
  [[ ! -e "$gate_path" && ! -L "$gate_path" ]] || {
    echo "validation-fee invocation already has a direct/public/MCP gate marker" >&2
    return 1
  }
  existing_gate_files=(
    "$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR"/*.gate.json(N)
  )
  if (( ${#existing_gate_files[@]} > 0 )); then
    validation_fee_assert_write_gate_history_dir \
      "$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR" || return 1
  fi

  for previous_file in \
    "$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR"/*.gate.json(N); do
    validation_fee_require_immutable_json_file "$previous_file" || return 1
    if ! jq -e '
      .schema == "soraswap.validation-fee-write-gate.v1"
      and (.sequence | type == "number" and . >= 1)
      and (.created_at | type == "string" and length > 0)
      and (
        .consensus.block_height
        | type == "number" and . >= 1
      )
      and (
        .consensus.block_hash
        | type == "string" and test("^[0-9a-f]{64}$")
      )
    ' "$previous_file" >/dev/null; then
      echo "existing validation-fee write-gate history is invalid" >&2
      return 1
    fi
    local observed_sequence
    observed_sequence="$(jq -er '.sequence' "$previous_file")" || return 1
    if [[ -n "${observed_sequences[$observed_sequence]:-}" ]]; then
      echo "validation-fee write-gate history repeats sequence $observed_sequence" >&2
      return 1
    fi
    observed_sequences[$observed_sequence]=1
    previous_command_sha="$(jq -er '.gate_command_sha256' "$previous_file")" \
      || return 1
    if [[ "$previous_command_sha" != "$command_sha" ]]; then
      echo "validation-fee write-gate producer digest changed across the deployment history" >&2
      return 1
    fi
    if (( observed_sequence > previous_sequence )); then
      previous_sequence="$observed_sequence"
      previous="$(jq -c \
        --arg sha256 "$(shasum -a 256 "$previous_file" | awk '{print $1}')" \
        '{
          sha256: $sha256,
          block_height: .consensus.block_height,
          block_hash: .consensus.block_hash,
          created_at: .created_at
        }' "$previous_file")"
    fi
  done
  if [[ "$(find "$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR" \
    -mindepth 1 -maxdepth 1 -name '*.gate.json' -type f | wc -l \
    | tr -d '[:space:]')" != "$previous_sequence" ]]; then
    echo "validation-fee write-gate history sequences are not contiguous" >&2
    return 1
  fi
  sequence=$(( previous_sequence + 1 ))
  request_json="$(jq -cn \
    --arg schema soraswap.validation-fee-write-gate-request.v1 \
    --arg chain_id fc56984b-2be7-431d-840e-21514d1883f0 \
    --argjson chain_discriminant 369 \
    --arg block_1_hash "$block_1_hash" \
    --arg plan_sha256 "$plan_sha256" \
    --arg authority_account_id \
      'testuﾛ1PｵEmｷjMZZﾑﾙeｱﾁﾎﾅﾂﾊmECepdbﾎｳ2uWﾃｸﾊﾘvｵi2ｦP1Y18A' \
    --argjson sequence "$sequence" \
    --arg invocation_id "$invocation_id" \
    --argjson operation "$operation" \
    --arg gate_command_sha256 "$command_sha" \
    --argjson previous_observation "$previous" \
    '{
      schema: $schema,
      chain_id: $chain_id,
      chain_discriminant: $chain_discriminant,
      block_1_hash: $block_1_hash,
      plan_sha256: $plan_sha256,
      authority_account_id: $authority_account_id,
      sequence: $sequence,
      invocation_id: $invocation_id,
      operation: $operation,
      gate_command_sha256: $gate_command_sha256,
      previous_observation: $previous_observation,
      direct: [
        {name: "validator-1", url: "http://127.0.0.1:39080"},
        {name: "validator-2", url: "http://127.0.0.1:39081"},
        {name: "validator-3", url: "http://127.0.0.1:39082"},
        {name: "validator-4", url: "http://127.0.0.1:39083"}
      ],
      public: {name: "public", url: "https://taira.sora.org"},
      mcp: {
        endpoint: "https://taira.sora.org/v1/mcp",
        tools: [
          "iroha.health",
          "iroha.status",
          "iroha.sumeragi.status",
          "iroha.blocks.get"
        ]
      }
    }')"
  request_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-write-gate-request.XXXXXX")" \
    || return 1
  marker_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-write-gate-marker.XXXXXX")" \
    || {
      rm -f "$request_path"
      return 1
    }
  validated_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-write-gate-validated.XXXXXX")" \
    || {
      rm -f "$request_path" "$marker_path"
      return 1
    }
  {
    jq -S . <<<"$request_json" >"$request_path" || return 1
    chmod 0600 "$request_path" "$marker_path" "$validated_path"
    if /usr/bin/env -i \
      LANG=C \
      LC_ALL=C \
      PATH=/usr/bin:/bin \
      TZ=UTC \
        "$command_path" <"$request_path" >"$marker_path"; then
      command_status=0
    else
      command_status=$?
    fi
    if (( command_status != 0 )); then
      echo "validation-fee direct/public/MCP write gate refused the imminent mutation" >&2
      return "$command_status"
    fi
    marker_size="$(wc -c <"$marker_path" | tr -d '[:space:]')"
    if [[ -z "$marker_size" || "$marker_size" != <-> \
      || "$marker_size" -gt 1048576 ]]; then
      echo "validation-fee write-gate marker exceeds its 1 MiB bound" >&2
      return 1
    fi
    validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/validate_validation_fee_write_gate.py" \
      --request "$request_path" \
      --marker "$marker_path" \
      --expected-plan-sha256 "$plan_sha256" \
      --max-age-seconds \
      "${SORASWAP_VALIDATION_FEE_WRITE_GATE_MAX_AGE_SECS:-60}" \
      >"$validated_path" || return 1
    validation_fee_write_immutable_json \
      "$(jq -ce . "$validated_path")" "$gate_path" >/dev/null || return 1
    printf '%s\n' "$gate_path"
  } always {
    rm -f "$request_path" "$marker_path" "$validated_path"
  }
}

validation_fee_validate_imminent_operation_json() {
  local operation_json="$1"
  local operation_path validated_path plan_sha256

  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  operation_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-operation.XXXXXX")" \
    || return 1
  validated_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-operation-valid.XXXXXX")" \
    || {
      rm -f "$operation_path"
      return 1
  }
  {
    print -rn -- "$operation_json" >"$operation_path" || return 1
    chmod 0600 "$operation_path" "$validated_path"
    validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/validate_validation_fee_write_gate.py" \
      --operation "$operation_path" \
      --expected-plan-sha256 "$plan_sha256" >"$validated_path" || return 1
    [[ "$(jq -cS . "$validated_path")" == "$(jq -cS . <<<"$operation_json")" ]] \
      || {
        echo "validation-fee imminent operation changed under exact validation" >&2
        return 1
      }
  } always {
    rm -f "$operation_path" "$validated_path"
  }
}

validation_fee_revalidate_current_write_gate() {
  local gate_path="$1"
  local plan_sha256

  validation_fee_require_immutable_json_file "$gate_path" || return 1
  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  [[ "$(jq -er '.plan_sha256' "$gate_path")" == "$plan_sha256" ]] || {
    echo "validation-fee gate marker changed its reviewed plan digest" >&2
    return 1
  }
  validation_fee_isolated_python \
    "$SORASWAP_ROOT/scripts/validate_validation_fee_write_gate.py" \
    --revalidate-marker "$gate_path" \
    --expected-plan-sha256 "$plan_sha256" \
    --max-age-seconds \
    "${SORASWAP_VALIDATION_FEE_WRITE_GATE_MAX_AGE_SECS:-60}" \
    >/dev/null
}

validation_fee_contract_call_immediate_gate() {
  local operation_json="${SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON:-}"
  local journal_prefix="${SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX:-}"
  local gate_path

  if [[ -z "$operation_json" ]] \
    || ! validation_fee_validate_imminent_operation_json "$operation_json" \
    || ! jq -e '.kind == "contract_call"' >/dev/null <<<"$operation_json"; then
    echo "validation-fee contract call lacks its exact immediate gate operation" >&2
    return 1
  fi
  [[ -n "$journal_prefix" ]] || {
    echo "validation-fee contract call lacks its durable mutation journal" >&2
    return 1
  }
  gate_path="$(validation_fee_write_gate_json "$operation_json")" || return $?
  validation_fee_start_mutation_intent "$journal_prefix" "$operation_json" \
    || return 1
  validation_fee_revalidate_current_write_gate "$gate_path"
}

validation_fee_contract_call_accepted_submission() {
  local transaction_hash="${3:-}"
  local operation_json="${SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON:-}"
  local journal_prefix="${SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX:-}"
  local transaction_json

  [[ -n "$journal_prefix" && -n "$operation_json" ]] || {
    echo "accepted validation-fee contract call lacks its durable journal binding" >&2
    return 1
  }
  [[ "$(validation_fee_mutation_journal_state "$journal_prefix")" \
    == "intent" ]] || {
    echo "accepted validation-fee contract call is not in its unique intent state" >&2
    return 1
  }
  validation_fee_assert_mutation_journal "$journal_prefix" "$operation_json" \
    || return 1
  transaction_json="$(
    validation_fee_normalized_transaction_hash_json "$transaction_hash"
  )" || return 1
  validation_fee_record_mutation_submission \
    "$journal_prefix" "$transaction_json"
}

validation_fee_ledger_immediate_gate() {
  local operation_json="${SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON:-}"
  local journal_prefix="${SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX:-}"

  if [[ -z "$operation_json" ]] \
    || ! validation_fee_validate_imminent_operation_json "$operation_json" \
    || ! jq -e '
      .kind == "account_registration"
      or .kind == "permission_grant"
      or .kind == "permission_revoke"
    ' >/dev/null <<<"$operation_json"; then
    echo "validation-fee Iroha CLI mutation lacks its exact immediate gate operation" >&2
    return 1
  fi
  [[ -n "$journal_prefix" ]] || {
    echo "validation-fee Iroha CLI mutation lacks its durable mutation journal" >&2
    return 1
  }
  echo "validation-fee ledger mutation is blocked: the current Iroha CLI has no reviewed signed-payload prepare/direct-submit boundary for an immediate gate" >&2
  return 1
}

validation_fee_prepared_ledger_transaction_immediate_gate() {
  local operation_json="${SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON:-}"
  local journal_prefix="${SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX:-}"
  local transaction_json="${SORASWAP_VALIDATION_FEE_IMMINENT_TRANSACTION_JSON:-}"
  local payload_sha256="${SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_SHA256:-}"
  local payload_size_bytes="${SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_SIZE_BYTES:-}"
  local prepared_dir="${SORASWAP_VALIDATION_FEE_IMMINENT_PREPARED_DIR:-}"
  local payload_fd="${SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_FD:-}"
  local gate_path

  if [[ -z "$operation_json" || -z "$transaction_json" \
    || ! "$payload_sha256" =~ '^[0-9a-f]{64}$' \
    || "$payload_size_bytes" != <1-> ]] \
    || ! validation_fee_validate_imminent_operation_json "$operation_json" \
    || ! jq -e \
      --arg payload_sha256 "$payload_sha256" \
      --argjson payload_size_bytes "$payload_size_bytes" \
      --argjson transaction "$transaction_json" \
      '
        (
          .kind == "account_registration"
          or .kind == "permission_grant"
          or .kind == "permission_revoke"
        )
        and .payload_sha256 == $payload_sha256
        and .payload_size_bytes == $payload_size_bytes
        and .transaction == $transaction
      ' >/dev/null <<<"$operation_json"; then
    echo "prepared validation-fee ledger transaction lacks its exact payload-bound operation" >&2
    return 1
  fi
  [[ -n "$journal_prefix" ]] || {
    echo "prepared validation-fee ledger transaction lacks its durable mutation journal" >&2
    return 1
  }
  [[ -n "$prepared_dir" && "$payload_fd" == <-> ]] || {
    echo "prepared validation-fee ledger transaction lacks its frozen payload package or open descriptor" >&2
    return 1
  }
  validation_fee_assert_prepared_ledger_operation_json \
    "$prepared_dir" "$operation_json" "$payload_fd" || return 1
  gate_path="$(validation_fee_write_gate_json "$operation_json")" || return $?
  validation_fee_start_mutation_intent "$journal_prefix" "$operation_json" \
    || return 1
  validation_fee_record_mutation_submission "$journal_prefix" "$transaction_json" \
    || return 1
  validation_fee_revalidate_current_write_gate "$gate_path" || return 1
  # This is the last operation before curl opens the payload. If the package
  # changed during the network gate, retain the submission journal and refuse
  # the POST as an intentionally ambiguous, fail-closed recovery state.
  validation_fee_assert_prepared_ledger_operation_json \
    "$prepared_dir" "$operation_json" "$payload_fd"
}

validation_fee_prepared_transaction_immediate_gate() {
  local operation_json="${SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON:-}"
  local journal_prefix="${SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX:-}"
  local transaction_json="${SORASWAP_VALIDATION_FEE_IMMINENT_TRANSACTION_JSON:-}"
  local gate_path

  if [[ -z "$operation_json" || -z "$transaction_json" ]] \
    || ! validation_fee_validate_imminent_operation_json "$operation_json" \
    || ! jq -e --argjson transaction "$transaction_json" '
      .kind == "split_deploy_transaction"
      and .transaction == $transaction
    ' >/dev/null <<<"$operation_json"; then
    echo "prepared validation-fee transaction lacks its exact immediate gate operation" >&2
    return 1
  fi
  [[ -n "$journal_prefix" ]] || {
    echo "prepared validation-fee transaction lacks its durable mutation journal" >&2
    return 1
  }
  gate_path="$(validation_fee_write_gate_json "$operation_json")" || return $?
  validation_fee_start_mutation_intent "$journal_prefix" "$operation_json" \
    || return 1
  validation_fee_record_mutation_submission "$journal_prefix" "$transaction_json" \
    || return 1
  validation_fee_revalidate_current_write_gate "$gate_path"
}

validation_fee_assert_historical_write_gate_file() {
  local gate_path="$1"
  local request_path validated_path request_json plan_sha256

  validation_fee_require_immutable_json_file "$gate_path" || return 1
  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  request_json="$(jq -ce '
    {
      schema: "soraswap.validation-fee-write-gate-request.v1",
      chain_id: .chain_id,
      chain_discriminant: .chain_discriminant,
      block_1_hash: .block_1_hash,
      plan_sha256: .plan_sha256,
      authority_account_id: .authority_account_id,
      sequence: .sequence,
      invocation_id: .invocation_id,
      operation: .operation,
      gate_command_sha256: .gate_command_sha256,
      previous_observation: (
        if .previous_observation == null then null
        else {
          sha256: .previous_observation.sha256,
          block_height: .previous_observation.block_height,
          block_hash: .previous_observation.block_hash,
          created_at: .previous_observation.created_at
        }
        end
      ),
      direct: [
        {name: "validator-1", url: "http://127.0.0.1:39080"},
        {name: "validator-2", url: "http://127.0.0.1:39081"},
        {name: "validator-3", url: "http://127.0.0.1:39082"},
        {name: "validator-4", url: "http://127.0.0.1:39083"}
      ],
      public: {name: "public", url: "https://taira.sora.org"},
      mcp: {
        endpoint: "https://taira.sora.org/v1/mcp",
        tools: [
          "iroha.health",
          "iroha.status",
          "iroha.sumeragi.status",
          "iroha.blocks.get"
        ]
      }
    }
  ' "$gate_path")" || return 1
  request_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-gate-history-request.XXXXXX")" \
    || return 1
  validated_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-gate-history-marker.XXXXXX")" \
    || {
      rm -f "$request_path"
      return 1
    }
  {
    jq -S . <<<"$request_json" >"$request_path" || return 1
    chmod 0600 "$request_path" "$validated_path"
    validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/validate_validation_fee_write_gate.py" \
      --request "$request_path" \
      --marker "$gate_path" \
      --expected-plan-sha256 "$plan_sha256" \
      --max-age-seconds 60 \
      --historical >"$validated_path" || return 1
    if [[ "$(jq -cS . "$validated_path")" != "$(jq -cS . "$gate_path")" ]]; then
      echo "historical validation-fee write-gate marker changed under validation" >&2
      return 1
    fi
  } always {
    rm -f "$request_path" "$validated_path"
  }
}

validation_fee_assert_write_gate_history_dir() {
  local history_dir="$1"
  local history='[]' gate_file marker sha256 gate_command_sha256
  local expected_gate_command_sha256=""
  local expected_block_1_hash="${SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH:-}"
  local -a gate_files

  [[ -d "$history_dir" && ! -L "$history_dir" ]] || {
    echo "validation-fee write-gate history is not a real directory" >&2
    return 1
  }
  gate_files=("$history_dir"/*.gate.json(N))
  (( ${#gate_files[@]} > 0 )) || {
    echo "validation-fee write-gate history is empty" >&2
    return 1
  }
  for gate_file in "${gate_files[@]}"; do
    validation_fee_assert_historical_write_gate_file "$gate_file" || return 1
    marker="$(jq -ce . "$gate_file")" || return 1
    gate_command_sha256="$(jq -er '.gate_command_sha256' <<<"$marker")" \
      || return 1
    if [[ -z "$expected_gate_command_sha256" ]]; then
      expected_gate_command_sha256="$gate_command_sha256"
    elif [[ "$gate_command_sha256" != "$expected_gate_command_sha256" ]]; then
      echo "validation-fee write-gate history changes producer digest" >&2
      return 1
    fi
    if [[ "${gate_file:t}" \
      != "$(jq -er '.invocation_id' <<<"$marker").gate.json" ]]; then
      echo "validation-fee write-gate filename differs from its invocation" >&2
      return 1
    fi
    sha256="$(shasum -a 256 "$gate_file" | awk '{print $1}')"
    history="$(jq -c \
      --arg sha256 "$sha256" \
      --argjson marker "$marker" \
      '. + [{sha256: $sha256, marker: $marker}]' <<<"$history")" \
      || return 1
  done
  if ! jq -e '
    sort_by(.marker.sequence) as $history
    | ($history | length) as $length
    | ($history | map(.marker.sequence)) == [range(1; ($length + 1))]
      and (
        $history
        | map(.marker.gate_command_sha256)
        | unique
        | length
      ) == 1
      and (
        $history
        | map(.marker.block_1_hash)
        | unique
        | length
      ) == 1
      and $history[0].marker.previous_observation == null
      and all(
        range(1; $length);
        . as $index
        | $history[$index].marker.previous_observation == {
            sha256: $history[$index - 1].sha256,
            block_height:
              $history[$index - 1].marker.consensus.block_height,
            block_hash:
              $history[$index - 1].marker.consensus.block_hash,
            created_at: $history[$index - 1].marker.created_at,
            verified_ancestor: true
          }
      )
  ' >/dev/null <<<"$history"; then
    echo "validation-fee write-gate history is not an exact ancestor chain" >&2
    return 1
  fi
  if [[ ! "$expected_block_1_hash" =~ '^[0-9a-f]{64}$' ]] \
    || ! jq -e \
      --arg block_1_hash "$expected_block_1_hash" \
      'all(.[]; .marker.block_1_hash == $block_1_hash)' \
      >/dev/null <<<"$history"; then
    echo "validation-fee write-gate history differs from the reviewed block-1 hash" >&2
    return 1
  fi
}

validation_fee_assert_write_reservation_history_dir() {
  local history_dir="$1"
  local bound_work_root="${SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT:-}"
  local gate_file reservation_file reservation_json invocation_id
  local journal_prefix intent_path
  local -a gate_files reservation_files

  [[ -d "$history_dir" && ! -L "$history_dir" ]] || return 1
  [[ -n "$bound_work_root" && "$bound_work_root" == /* \
    && "$bound_work_root" == "${bound_work_root:A}" ]] || {
    echo "validation-fee reservation history lacks its bound work root" >&2
    return 1
  }
  for reservation_file in "$history_dir"/*(DN); do
    if [[ "${reservation_file:t}" != *.gate.json \
      && "${reservation_file:t}" != *.intent.json ]]; then
      echo "validation-fee invocation history contains an unexpected entry" >&2
      return 1
    fi
  done
  gate_files=("$history_dir"/*.gate.json(N))
  reservation_files=("$history_dir"/*.intent.json(N))
  if (( ${#gate_files[@]} != ${#reservation_files[@]} )); then
    echo "validation-fee gate history is not fully linked to durable write reservations" >&2
    return 1
  fi
  for gate_file in "${gate_files[@]}"; do
    validation_fee_require_immutable_json_file "$gate_file" || return 1
    invocation_id="${gate_file:t:r:r}"
    reservation_file="$history_dir/$invocation_id.intent.json"
    validation_fee_require_immutable_json_file "$reservation_file" || {
      echo "validation-fee gate lacks its durable write reservation" >&2
      return 1
    }
    reservation_json="$(jq -ce . "$reservation_file")" || return 1
    if ! jq -e \
      --arg invocation_id "$invocation_id" \
      --argjson operation "$(jq -ce '.operation' "$gate_file")" \
      '
        .schema_version == 1
        and .phase == "write_intent_reserved"
        and .invocation_id == $invocation_id
        and .operation == $operation
        and (.journal_prefix | type == "string" and length > 0)
        and (
          keys == [
            "invocation_id",
            "journal_prefix",
            "operation",
            "phase",
            "schema_version"
          ]
        )
      ' >/dev/null <<<"$reservation_json"; then
      echo "validation-fee write reservation differs from its gate" >&2
      return 1
    fi
    journal_prefix="$(jq -er '.journal_prefix' <<<"$reservation_json")" \
      || return 1
    if [[ "$journal_prefix" != /* \
      || "$journal_prefix" != "${journal_prefix:A}" \
      || "$journal_prefix" != "$bound_work_root/"* ]]; then
      echo "validation-fee write reservation escapes its bound work root" >&2
      return 1
    fi
    intent_path="$journal_prefix.intent.json"
    validation_fee_require_immutable_json_file "$intent_path" || {
      echo "validation-fee write reservation lost its mutation intent" >&2
      return 1
    }
    if ! jq -e \
      --arg invocation_id "$invocation_id" \
      --argjson operation "$(jq -ce '.operation' "$gate_file")" \
      '
        .schema_version == 1
        and .phase == "intent"
        and .invocation_id == $invocation_id
        and .operation == $operation
      ' "$intent_path" >/dev/null; then
      echo "validation-fee reserved mutation intent differs from its gate" >&2
      return 1
    fi
  done
}

validation_fee_mutation_journal_state() {
  local prefix="$1"
  local intent_path="$prefix.intent.json"
  local submission_path="$prefix.submission.json"
  local applied_path="$prefix.Applied.json"

  if [[ -e "$applied_path" ]]; then
    [[ -e "$intent_path" && -e "$submission_path" ]] || {
      echo "validation-fee Applied journal lacks its intent or submission predecessor: $prefix" >&2
      return 1
    }
    printf '%s\n' Applied
  elif [[ -e "$submission_path" ]]; then
    [[ -e "$intent_path" ]] || {
      echo "validation-fee submission journal lacks its intent predecessor: $prefix" >&2
      return 1
    }
    printf '%s\n' submission
  elif [[ -e "$intent_path" ]]; then
    printf '%s\n' intent
  else
    printf '%s\n' absent
  fi
}

validation_fee_assert_mutation_journal() {
  local prefix="$1"
  local expected_operation="$2"
  local state intent submission applied intent_sha256 submission_sha256
  local gate_path gate_sha256 intent_invocation_id

  state="$(validation_fee_mutation_journal_state "$prefix")" || return 1
  [[ "$state" != "absent" ]] || {
    echo "validation-fee mutation journal is absent: $prefix" >&2
    return 1
  }
  validation_fee_require_immutable_json_file "$prefix.intent.json" || return 1
  intent="$(jq -ce . "$prefix.intent.json")" || return 1
  if ! jq -e \
    --argjson operation "$expected_operation" \
    '
      .schema_version == 1
      and .phase == "intent"
      and (
        keys == [
          "invocation_id",
          "operation",
          "phase",
          "schema_version"
        ]
      )
      and (.invocation_id | type == "string" and length > 0)
      and .operation == $operation
    ' >/dev/null <<<"$intent"; then
    echo "validation-fee mutation intent does not match the exact operation: $prefix" >&2
    return 1
  fi
  intent_invocation_id="$(jq -er '.invocation_id' <<<"$intent")" || return 1
  [[ "$state" != "intent" ]] || return 0

  validation_fee_require_immutable_json_file "$prefix.submission.json" || return 1
  submission="$(jq -ce . "$prefix.submission.json")" || return 1
  intent_sha256="$(shasum -a 256 "$prefix.intent.json" | awk '{print $1}')"
  if ! jq -e \
    --arg intent_sha256 "$intent_sha256" \
    --arg intent_invocation_id "$intent_invocation_id" \
    '
      .schema_version == 1
      and .phase == "submission"
      and (
        keys == [
          "intent_sha256",
          "invocation_id",
          "phase",
          "schema_version",
          "transaction",
          "write_gate_sha256"
        ]
      )
      and .intent_sha256 == $intent_sha256
      and .invocation_id == $intent_invocation_id
      and (.write_gate_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (
        .transaction.tx_hash
        | type == "string"
        and test("^(hash:[0-9A-F]{64}#[0-9A-F]{4}|(0x)?[0-9A-Fa-f]{64})$")
      )
      and (
        .transaction.tx_hash_hex
        | type == "string"
        and test("^[0-9a-f]{64}$")
      )
    ' >/dev/null <<<"$submission"; then
    echo "validation-fee mutation submission journal is invalid: $prefix" >&2
    return 1
  fi
  gate_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$(
    jq -er '.invocation_id' <<<"$submission"
  ).gate.json"
  validation_fee_assert_write_gate_history_dir \
    "$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR" || return 1
  gate_sha256="$(shasum -a 256 "$gate_path" | awk '{print $1}')"
  if [[ "$gate_sha256" != "$(jq -er '.write_gate_sha256' <<<"$submission")" ]] \
    || ! jq -e \
      --argjson operation "$expected_operation" \
      '.operation == $operation' "$gate_path" >/dev/null; then
    echo "validation-fee mutation submission is not bound to its exact direct/public/MCP gate" >&2
    return 1
  fi
  validation_fee_assert_transaction_evidence_json \
    "$(jq -ce '.transaction' <<<"$submission")" \
    "$(jq -cn \
      --arg tx_hash_hex "$(jq -er '.transaction.tx_hash_hex' <<<"$submission")" \
      '{
        source: "pipeline",
        status: {status: {kind: "Applied"}},
        queried_tx_hash_hex: $tx_hash_hex
      }')" >/dev/null || return 1
  [[ "$state" != "submission" ]] || return 0

  validation_fee_require_immutable_json_file "$prefix.Applied.json" || return 1
  applied="$(jq -ce . "$prefix.Applied.json")" || return 1
  submission_sha256="$(
    shasum -a 256 "$prefix.submission.json" | awk '{print $1}'
  )"
  if ! jq -e \
    --arg submission_sha256 "$submission_sha256" \
    --argjson transaction "$(jq -ce '.transaction' <<<"$submission")" \
    '
      .schema_version == 1
      and .phase == "Applied"
      and (
        keys == [
          "invocation_id",
          "phase",
          "receipt",
          "schema_version",
          "submission_sha256"
        ]
      )
      and .submission_sha256 == $submission_sha256
      and (.invocation_id | type == "string" and length > 0)
      and (.receipt | type == "object")
      and .receipt.transaction == $transaction
      and (.receipt.terminal | type == "object")
    ' >/dev/null <<<"$applied"; then
    echo "validation-fee Applied journal is invalid: $prefix" >&2
    return 1
  fi
  validation_fee_assert_transaction_evidence_json \
    "$(jq -ce '.receipt.transaction' <<<"$applied")" \
    "$(jq -ce '.receipt.terminal' <<<"$applied")"
}

validation_fee_start_mutation_intent() {
  local prefix="$1"
  local operation="$2"
  local invocation_id marker_path marker_json intent_json state

  validation_fee_require_one_write_mode || return 1
  state="$(validation_fee_mutation_journal_state "$prefix")" || return 1
  if [[ "$state" != "absent" ]]; then
    echo "refusing to resubmit validation-fee mutation with existing $state journal: $prefix" >&2
    return 1
  fi
  validation_fee_ensure_durable_directory "${prefix:h}" || return 1
  invocation_id="$SORASWAP_VALIDATION_FEE_INVOCATION_ID"
  marker_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$invocation_id.intent.json"
  marker_json="$(jq -cn \
    --arg invocation_id "$invocation_id" \
    --arg journal_prefix "$prefix" \
    --argjson operation "$operation" \
    '{
      schema_version: 1,
      phase: "write_intent_reserved",
      invocation_id: $invocation_id,
      journal_prefix: $journal_prefix,
      operation: $operation
    }')"
  if [[ -e "$marker_path" || -L "$marker_path" ]]; then
    echo "one-write validation-fee invocation already reserved a mutation" >&2
    return 1
  fi
  validation_fee_write_immutable_json "$marker_json" "$marker_path" >/dev/null \
    || return 1
  intent_json="$(jq -cn \
    --arg invocation_id "$invocation_id" \
    --argjson operation "$operation" \
    '{
      schema_version: 1,
      phase: "intent",
      invocation_id: $invocation_id,
      operation: $operation
    }')"
  validation_fee_write_immutable_json \
    "$intent_json" "$prefix.intent.json" >/dev/null
}

validation_fee_record_mutation_submission() {
  local prefix="$1"
  local transaction="$2"
  local invocation_id intent_invocation_id intent_sha256
  local gate_path gate_sha256 submission_json

  validation_fee_require_immutable_json_file "$prefix.intent.json" || return 1
  [[ ! -e "$prefix.submission.json" && ! -L "$prefix.submission.json" ]] || {
    echo "refusing to replace validation-fee mutation submission journal: $prefix" >&2
    return 1
  }
  validation_fee_assert_transaction_evidence_json \
    "$transaction" \
    "$(jq -cn \
      --arg tx_hash_hex "$(jq -er '.tx_hash_hex' <<<"$transaction")" \
      '{
        source: "pipeline",
        status: {status: {kind: "Applied"}},
        queried_tx_hash_hex: $tx_hash_hex
      }')" >/dev/null || return 1
  invocation_id="$SORASWAP_VALIDATION_FEE_INVOCATION_ID"
  intent_invocation_id="$(jq -er '.invocation_id' "$prefix.intent.json")" \
    || return 1
  if [[ "$invocation_id" != "$intent_invocation_id" ]]; then
    echo "validation-fee submission invocation differs from its immutable intent" >&2
    return 1
  fi
  if jq -e '.operation | has("transaction")' \
    "$prefix.intent.json" >/dev/null \
    && ! jq -e \
      --argjson transaction "$transaction" \
      '.operation.transaction == $transaction' \
      "$prefix.intent.json" >/dev/null; then
    echo "validation-fee submission transaction differs from its prepared operation" >&2
    return 1
  fi
  intent_sha256="$(shasum -a 256 "$prefix.intent.json" | awk '{print $1}')"
  gate_path="$SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR/$invocation_id.gate.json"
  validation_fee_require_immutable_json_file "$gate_path" || {
    echo "validation-fee mutation submission lacks its immediate direct/public/MCP gate" >&2
    return 1
  }
  gate_sha256="$(shasum -a 256 "$gate_path" | awk '{print $1}')"
  submission_json="$(jq -cn \
    --arg invocation_id "$invocation_id" \
    --arg intent_sha256 "$intent_sha256" \
    --arg write_gate_sha256 "$gate_sha256" \
    --argjson transaction "$transaction" \
    '{
      schema_version: 1,
      phase: "submission",
      invocation_id: $invocation_id,
      intent_sha256: $intent_sha256,
      write_gate_sha256: $write_gate_sha256,
      transaction: $transaction
    }')"
  validation_fee_write_immutable_json \
    "$submission_json" "$prefix.submission.json" >/dev/null
}

validation_fee_record_mutation_applied() {
  local prefix="$1"
  local receipt="$2"
  local expected_operation="$3"
  local invocation_id submission_sha256 applied_json

  validation_fee_require_immutable_json_file "$prefix.submission.json" || return 1
  validation_fee_assert_transaction_evidence_json \
    "$(jq -ce '.transaction' <<<"$receipt")" \
    "$(jq -ce '.terminal' <<<"$receipt")" || return 1
  invocation_id="$SORASWAP_VALIDATION_FEE_INVOCATION_ID"
  submission_sha256="$(
    shasum -a 256 "$prefix.submission.json" | awk '{print $1}'
  )"
  applied_json="$(jq -cn \
    --arg invocation_id "$invocation_id" \
    --arg submission_sha256 "$submission_sha256" \
    --argjson receipt "$receipt" \
    '{
      schema_version: 1,
      phase: "Applied",
      invocation_id: $invocation_id,
      submission_sha256: $submission_sha256,
      receipt: $receipt
    }')"
  validation_fee_write_immutable_json \
    "$applied_json" "$prefix.Applied.json" >/dev/null || return 1
  validation_fee_assert_mutation_journal "$prefix" "$expected_operation"
}

validation_fee_fail_on_ambiguous_mutation() {
  local prefix="$1"
  local expected_operation="$2"
  local state

  state="$(validation_fee_mutation_journal_state "$prefix")" || return 1
  [[ "$state" != "absent" ]] || return 0
  validation_fee_assert_mutation_journal "$prefix" "$expected_operation" \
    || return 1
  case "$state" in
    Applied)
      return 0
      ;;
    intent|submission)
      echo "validation-fee mutation is ambiguous at durable $state; refusing automatic retry: $prefix" >&2
      return 1
      ;;
  esac
  return 1
}

validation_fee_pause_result_json() {
  local operation_key="$1"
  local applied_path="$2"

  jq -cn \
    --arg status "$VALIDATION_FEE_ONE_WRITE_PAUSE_STATUS" \
    --arg operation_key "$operation_key" \
    --arg applied_journal "$applied_path" \
    --arg invocation_id "$SORASWAP_VALIDATION_FEE_INVOCATION_ID" \
    '{
      status: $status,
      operation_key: $operation_key,
      applied_journal: $applied_journal,
      invocation_id: $invocation_id,
      submitted_mutations_this_invocation: 1,
      resume_required: true
    }'
}

validation_fee_account_presence() {
  local config="$1"
  local account_id="$2"
  local torii_base encoded_account response http_code

  soraswap_validate_torii_read_max_time || return 1
  torii_base="$(torii_base_from_config "$config")" || return 1
  encoded_account="$(uri_encode "$account_id")" || return 1
  response="$(
    soraswap_curl_for_config "$config" \
      -sS \
      --max-time "$SORASWAP_TORII_READ_MAX_TIME_SECS" \
      -o /dev/null \
      -w '%{http_code}' \
      "${torii_base%/}/v1/accounts/$encoded_account"
  )" || {
    echo "could not query validation-fee account presence for $account_id" >&2
    return 1
  }
  http_code="$response"
  case "$http_code" in
    200)
      printf '%s\n' present
      ;;
    404)
      printf '%s\n' absent
      ;;
    *)
      echo "validation-fee account presence query returned HTTP $http_code" >&2
      return 1
      ;;
  esac
}

validation_fee_require_immutable_json_file() {
  local evidence_file="$1"
  local mode

  [[ -f "$evidence_file" && ! -L "$evidence_file" ]] || {
    echo "validation-fee evidence is not a regular file: $evidence_file" >&2
    return 1
  }
  mode="$(stat -f '%Lp' "$evidence_file" 2>/dev/null \
    || stat -c '%a' "$evidence_file" 2>/dev/null)" || return 1
  if [[ "$mode" != "444" ]]; then
    echo "validation-fee evidence must be immutable mode 0444: $evidence_file" >&2
    return 1
  fi
  jq -e . "$evidence_file" >/dev/null || {
    echo "validation-fee evidence is not valid JSON: $evidence_file" >&2
    return 1
  }
}

validation_fee_transaction_hash_json() {
  local output="$1"
  local parsed hash_literal hash_hex

  if ! parsed="$(jq -ce . <<<"$output" 2>/dev/null)"; then
    parsed="$(extract_last_json_object <<<"$output")" || {
      echo "validation-fee mutation did not return JSON" >&2
      return 1
    }
  fi
  hash_literal="$(jq -er '.hash' <<<"$parsed" 2>/dev/null || true)"
  if [[ ! "$hash_literal" =~ '^hash:[0-9A-F]{64}#[0-9A-F]{4}$' ]]; then
    echo "validation-fee mutation did not return one canonical transaction hash literal" >&2
    return 1
  fi
  hash_hex="$(normalize_hash_literal "$hash_literal")"
  if [[ ! "$hash_hex" =~ '^[0-9a-f]{64}$' ]]; then
    echo "validation-fee mutation hash did not normalize to 64 lowercase hex characters" >&2
    return 1
  fi
  jq -cn \
    --arg tx_hash "$hash_literal" \
    --arg tx_hash_hex "$hash_hex" \
    '{tx_hash: $tx_hash, tx_hash_hex: $tx_hash_hex}'
}

validation_fee_normalized_transaction_hash_json() {
  local hash_literal="$1"
  local hash_hex

  if [[ "$hash_literal" =~ '^hash:[0-9A-F]{64}#[0-9A-F]{4}$' ]]; then
    hash_hex="$(normalize_hash_literal "$hash_literal")"
  elif [[ "$hash_literal" =~ '^(0x)?[0-9A-Fa-f]{64}$' ]]; then
    hash_hex="${hash_literal#0x}"
    hash_hex="${hash_hex:l}"
  else
    echo "validation-fee evidence contains a non-canonical transaction hash" >&2
    return 1
  fi
  if [[ ! "$hash_hex" =~ '^[0-9a-f]{64}$' ]]; then
    echo "validation-fee evidence hash did not normalize to 64 lowercase hex characters" >&2
    return 1
  fi
  jq -cn \
    --arg tx_hash "$hash_literal" \
    --arg tx_hash_hex "$hash_hex" \
    '{tx_hash: $tx_hash, tx_hash_hex: $tx_hash_hex}'
}

validation_fee_applied_transaction_json() {
  local config="$1"
  local tx_hash_hex="$2"
  local terminal source pipeline kind result

  terminal="$(
    wait_for_transaction_terminal_or_committed \
      "$config" \
      "$tx_hash_hex" \
      "${SORASWAP_VALIDATION_FEE_TX_WAIT_SECS:-120}" \
      1 \
      auto \
      "$tx_hash_hex"
  )" || return $?
  source="$(jq -er '.source' <<<"$terminal")" || return 1
  case "$source" in
    pipeline)
      pipeline="$(jq -c '.status' <<<"$terminal")" || return 1
      kind="$(pipeline_status_kind_from_json "$pipeline")"
      case "$kind" in
        Applied|Committed)
          ;;
        *)
          echo "validation-fee mutation reached terminal pipeline state $kind" >&2
          return 1
          ;;
      esac
      ;;
    committed)
      result="$(jq -c '.transaction_result // null' <<<"$terminal")"
      assert_transaction_result_ok "$result" "$tx_hash_hex" "validation-fee mutation" \
        || return 1
      ;;
    *)
      echo "validation-fee mutation returned unknown terminal proof source $source" >&2
      return 1
      ;;
  esac
  jq -c \
    --arg queried_tx_hash_hex "$tx_hash_hex" \
    '. + {queried_tx_hash_hex: $queried_tx_hash_hex}' <<<"$terminal"
}

validation_fee_assert_applied_terminal_json() {
  local terminal_json="$1"

  if ! jq -e '
    (.queried_tx_hash_hex | type == "string" and test("^[0-9a-f]{64}$"))
    and (
      (
      .source == "pipeline"
      and (
        .status.status.kind
        // .status.content.status.kind
        // ""
      ) as $kind
      | ($kind == "Applied" or $kind == "Committed")
    )
    or (
      .source == "committed"
      and (.transaction_result | type == "object")
      and (.transaction_result | has("Ok"))
      )
    )
  ' >/dev/null <<<"$terminal_json"; then
    echo "validation-fee evidence does not prove an applied transaction" >&2
    return 1
  fi
}

validation_fee_assert_transaction_evidence_json() {
  local transaction_json="$1"
  local terminal_json="$2"
  local tx_hash tx_hash_hex normalized

  tx_hash="$(jq -er '.tx_hash' <<<"$transaction_json")" || return 1
  tx_hash_hex="$(jq -er '.tx_hash_hex' <<<"$transaction_json")" || return 1
  normalized="$(validation_fee_normalized_transaction_hash_json "$tx_hash")" \
    || return 1
  if [[ "$(jq -r '.tx_hash_hex' <<<"$normalized")" != "$tx_hash_hex" ]]; then
    echo "validation-fee transaction hash literal and normalized hash differ" >&2
    return 1
  fi
  if [[ "$(jq -r '.queried_tx_hash_hex // empty' <<<"$terminal_json")" \
    != "$tx_hash_hex" ]]; then
    echo "validation-fee terminal evidence is not bound to its transaction hash" >&2
    return 1
  fi
  validation_fee_assert_applied_terminal_json "$terminal_json"
}

validation_fee_reverify_transaction_evidence_json() {
  local config="$1"
  local transaction_json="$2"
  local tx_hash_hex terminal_json

  tx_hash_hex="$(jq -er '.tx_hash_hex' <<<"$transaction_json")" || return 1
  terminal_json="$(
    validation_fee_applied_transaction_json "$config" "$tx_hash_hex"
  )" || return $?
  validation_fee_assert_applied_terminal_json "$terminal_json"
}

validation_fee_signal_cleanup_and_exit() {
  local signal_name="$1"
  local signal_status="$2"
  local cleanup_function="$3"
  local handler_status=0

  trap '' INT TERM
  trap - EXIT
  echo "validation-fee bootstrap received $signal_name; revoking temporary permissions" >&2
  "$cleanup_function" "$signal_status" || handler_status=$?
  if (( handler_status == 0 )); then
    handler_status="$signal_status"
  fi
  exit "$handler_status"
}

validation_fee_reviewed_ledger_adapter_sha256() {
  local adapter_path="${SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN:-}"
  local expected_sha256="${SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_SHA256:-}"

  validation_fee_reviewed_gate_producer_sha256 \
    "$adapter_path" "$expected_sha256"
}

validation_fee_reviewed_ledger_adapter_source_sha256() {
  local expected_sha256="${SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_SOURCE_SHA256:-}"

  [[ "$expected_sha256" =~ '^[0-9a-f]{64}$' \
    && "$expected_sha256" \
      != '0000000000000000000000000000000000000000000000000000000000000000' ]] || {
    echo "validation-fee ledger adapter source pin must be a resolved lowercase SHA-256" >&2
    return 1
  }
  printf '%s\n' "$expected_sha256"
}

validation_fee_verify_prepared_ledger_manifest_fd() {
  local payload_fd="$1"
  local semantic_operation_json="$2"
  local adapter_path="${SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN:-}"
  local authority='testuﾛ1PｵEmｷjMZZﾑﾙeｱﾁﾎﾅﾂﾊmECepdbﾎｳ2uWﾃｸﾊﾘvｵi2ｦP1Y18A'
  local operation_path manifest_raw manifest_json adapter_status=0
  local seek_status=0

  [[ "$payload_fd" == <-> ]] || {
    echo "validation-fee ledger verification requires one already-open payload descriptor" >&2
    return 1
  }
  validation_fee_reviewed_ledger_adapter_sha256 >/dev/null || return 1
  validation_fee_reviewed_ledger_adapter_source_sha256 >/dev/null || return 1
  zmodload zsh/system || {
    echo "validation-fee ledger verification requires zsh descriptor seeking" >&2
    return 1
  }
  operation_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-ledger-operation.XXXXXX")" \
    || return 1
  {
    print -rn -- "$semantic_operation_json" >"$operation_path" || return 1
    chmod 0600 "$operation_path" || return 1
    sysseek -u "$payload_fd" 0 || return 1
    if manifest_raw="$(
      "$adapter_path" verify \
        --authority "$authority" \
        --plan-evidence \
          "$SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH" \
        --operation-json "$operation_path" <&$payload_fd
    )"; then
      adapter_status=0
    else
      adapter_status=$?
    fi
  } always {
    sysseek -u "$payload_fd" 0 || seek_status=$?
    rm -f "$operation_path"
  }
  if (( adapter_status != 0 || seek_status != 0 )); then
    echo "reviewed validation-fee ledger adapter rejected the frozen signed payload" >&2
    soraswap_redact_sensitive_text <<<"$manifest_raw" >&2
    return 1
  fi
  manifest_json="$(jq -ce . <<<"$manifest_raw")" || {
    echo "reviewed validation-fee ledger adapter did not return one verified manifest" >&2
    return 1
  }
  printf '%s\n' "$manifest_json"
}

validation_fee_validate_prepared_ledger_transaction_json() {
  local prepared_dir="$1"
  local semantic_operation_json="$2"
  local supplied_payload_fd="${3:-}"
  local plan_sha256 adapter_sha256 adapter_source_sha256
  local operation_path validated_path wrapper_json verified_manifest_json
  local payload_fd="$supplied_payload_fd"
  local opened_payload_fd=0

  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  adapter_sha256="$(validation_fee_reviewed_ledger_adapter_sha256)" || return 1
  adapter_source_sha256="$(
    validation_fee_reviewed_ledger_adapter_source_sha256
  )" || return 1
  operation_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-ledger-operation.XXXXXX")" \
    || return 1
  validated_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-ledger-prepared.XXXXXX")" \
    || {
      rm -f "$operation_path"
      return 1
  }
  {
    print -rn -- "$semantic_operation_json" >"$operation_path" || return 1
    chmod 0600 "$operation_path" "$validated_path"
    validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/validate_validation_fee_prepared_ledger.py" \
      --prepared-dir "$prepared_dir" \
      --operation "$operation_path" \
      --expected-plan-sha256 "$plan_sha256" \
      --expected-adapter-sha256 "$adapter_sha256" \
      --expected-adapter-source-sha256 "$adapter_source_sha256" \
      >"$validated_path" || return 1
    wrapper_json="$(jq -ce . "$validated_path")" || return 1
    if [[ "$(jq -cS . "$prepared_dir/plan.json")" \
      != "$(jq -cS . <<<"$wrapper_json")" ]]; then
      echo "prepared validation-fee ledger wrapper changed under exact validation" >&2
      return 1
    fi
    if [[ -z "$payload_fd" ]]; then
      exec {payload_fd}< "$prepared_dir/transaction.norito" || {
        echo "could not open frozen validation-fee ledger payload" >&2
        return 1
      }
      opened_payload_fd=1
    fi
    verified_manifest_json="$(
      validation_fee_verify_prepared_ledger_manifest_fd \
        "$payload_fd" "$semantic_operation_json"
    )" || return 1
    if [[ "$(jq -cS . <<<"$verified_manifest_json")" \
      != "$(jq -cS '.manifest' <<<"$wrapper_json")" ]]; then
      echo "prepared validation-fee ledger manifest differs from the signed Norito envelope" >&2
      return 1
    fi
    printf '%s\n' "$wrapper_json"
  } always {
    if (( opened_payload_fd == 1 )); then
      exec {payload_fd}<&-
    fi
    rm -f "$operation_path" "$validated_path"
  }
}

validation_fee_prepare_ledger_transaction_json() {
  local config="$1"
  local semantic_operation_json="$2"
  local prepared_dir="$3"
  local plan_path="$prepared_dir/plan.json"
  local plan_sha256 adapter_path adapter_sha256 authority
  local staging_dir operation_path private_key_file fee_payment_file gas_limit
  local manifest_raw manifest_json wrapper_json adapter_status=0

  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  adapter_path="${SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN:-}"
  adapter_sha256="$(validation_fee_reviewed_ledger_adapter_sha256)" || return 1
  authority="${SORASWAP_AUTHORITY:-}"
  [[ -n "$authority" ]] || {
    echo "validation-fee ledger preparation requires the exact client authority" >&2
    return 1
  }
  if [[ -e "$plan_path" ]]; then
    validation_fee_validate_prepared_ledger_transaction_json \
      "$prepared_dir" "$semantic_operation_json"
    return
  fi
  if [[ -e "$prepared_dir" || -L "$prepared_dir" ]]; then
    echo "refusing incomplete prepared validation-fee ledger directory: $prepared_dir" >&2
    return 1
  fi
  [[ "$prepared_dir" == /* && "${prepared_dir:h}" == "${prepared_dir:h:A}" ]] || {
    echo "prepared validation-fee ledger path must have a canonical absolute parent" >&2
    return 1
  }
  validation_fee_ensure_durable_directory "${prepared_dir:h}" || return 1
  staging_dir="$(mktemp -d "${prepared_dir:h}/.validation-fee-ledger.XXXXXX")" \
    || return 1
  chmod 0700 "$staging_dir"
  operation_path="$staging_dir/operation.json"
  print -rn -- "$semantic_operation_json" >"$operation_path" || {
    rm -rf "$staging_dir"
    return 1
  }
  chmod 0600 "$operation_path"
  private_key_file="$(
    soraswap_config_private_key_temp_file \
      "$config" validation-fee-ledger-adapter-key
  )" || {
    rm -rf "$staging_dir"
    return 1
  }
  gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
  soraswap_require_positive_integer_setting \
    "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      rm -rf "$staging_dir"
      return 1
    }
  fee_payment_file="$(jq -cn \
    --argjson gas_limit "$gas_limit" \
    '{payer: "authority", value: {charge_limits: [], gas_limit: $gas_limit}}' \
    | soraswap_secret_temp_from_stdin validation-fee-ledger-fee-payment)" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      rm -rf "$staging_dir"
      return 1
    }
  {
    if manifest_raw="$(
      "$adapter_path" prepare \
        --config "$config" \
        --authority "$authority" \
        --private-key-file "$private_key_file" \
        --fee-payment-json "$fee_payment_file" \
        --plan-evidence \
          "$SORASWAP_VALIDATION_FEE_DEPLOYMENT_PLAN_EVIDENCE_PATH" \
        --operation-json "$operation_path" \
        --out-file "$staging_dir/transaction.norito"
    )"; then
      adapter_status=0
    else
      adapter_status=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_files \
      "$private_key_file" "$fee_payment_file"; then
      adapter_status=1
    fi
  }
  if (( adapter_status != 0 )); then
    echo "reviewed validation-fee ledger adapter failed to prepare the typed transaction" >&2
    soraswap_redact_sensitive_text <<<"$manifest_raw" >&2
    rm -rf "$staging_dir"
    return "$adapter_status"
  fi
  manifest_json="$(jq -ce . <<<"$manifest_raw")" || {
    echo "reviewed validation-fee ledger adapter did not return one JSON manifest" >&2
    rm -rf "$staging_dir"
    return 1
  }
  rm -f "$operation_path"
  wrapper_json="$(jq -cn \
    --argjson schema_version 1 \
    --arg phase prepared_validation_fee_ledger_transaction \
    --arg plan_sha256 "$plan_sha256" \
    --arg adapter_binary_sha256 "$adapter_sha256" \
    --argjson manifest "$manifest_json" \
    '{
      schema_version: $schema_version,
      phase: $phase,
      plan_sha256: $plan_sha256,
      adapter_binary_sha256: $adapter_binary_sha256,
      manifest: $manifest
    }')"
  validation_fee_write_immutable_json \
    "$wrapper_json" "$staging_dir/plan.json" >/dev/null || {
      rm -rf "$staging_dir"
      return 1
    }
  chmod 0555 "$staging_dir"
  validation_fee_fsync_directory "$staging_dir" || {
    chmod 0700 "$staging_dir" 2>/dev/null || true
    rm -rf "$staging_dir"
    return 1
  }
  mv "$staging_dir" "$prepared_dir"
  validation_fee_fsync_directory "${prepared_dir:h}" || return 1
  validation_fee_fsync_directory "$prepared_dir" || return 1
  validation_fee_validate_prepared_ledger_transaction_json \
    "$prepared_dir" "$semantic_operation_json"
}

validation_fee_prepared_ledger_operation_json() {
  local semantic_operation_json="$1"
  local prepared_wrapper_json="$2"

  jq -cn \
    --argjson operation "$semantic_operation_json" \
    --argjson manifest "$(jq -ce '.manifest' <<<"$prepared_wrapper_json")" \
    '
      $operation + {
        payload_sha256: $manifest.payload.sha256,
        payload_size_bytes: $manifest.payload.size_bytes,
        transaction: $manifest.transaction
      }
    '
}

validation_fee_assert_prepared_ledger_operation_json() {
  local prepared_dir="$1"
  local operation_json="$2"
  local payload_fd="${3:-}"
  local semantic_operation_json wrapper_json rebound_operation_json

  validation_fee_validate_imminent_operation_json "$operation_json" || return 1
  semantic_operation_json="$(jq -ce '
    if (
      .kind == "account_registration"
      or .kind == "permission_grant"
      or .kind == "permission_revoke"
    ) then
      del(.payload_sha256, .payload_size_bytes, .transaction)
    else
      error("not a prepared validation-fee ledger operation")
    end
  ' <<<"$operation_json")" || return 1
  wrapper_json="$(
    validation_fee_validate_prepared_ledger_transaction_json \
      "$prepared_dir" "$semantic_operation_json" "$payload_fd"
  )" || return 1
  rebound_operation_json="$(
    validation_fee_prepared_ledger_operation_json \
      "$semantic_operation_json" "$wrapper_json"
  )" || return 1
  if [[ "$(jq -cS . <<<"$rebound_operation_json")" \
    != "$(jq -cS . <<<"$operation_json")" ]]; then
    echo "prepared validation-fee ledger operation differs from its exact frozen manifest" >&2
    return 1
  fi
}

validation_fee_prepare_bound_ledger_operation_json() {
  local config="$1"
  local semantic_operation_json="$2"
  local prepared_dir="$3"
  local wrapper_json operation_json

  wrapper_json="$(
    validation_fee_prepare_ledger_transaction_json \
      "$config" "$semantic_operation_json" "$prepared_dir"
  )" || return $?
  operation_json="$(
    validation_fee_prepared_ledger_operation_json \
      "$semantic_operation_json" "$wrapper_json"
  )" || return 1
  validation_fee_validate_imminent_operation_json "$operation_json" || return 1
  printf '%s\n' "$operation_json"
}

validation_fee_submit_prepared_ledger_transaction_json() {
  local config="$1"
  local operation_json="$2"
  local prepared_dir="$3"
  local journal_prefix="$4"
  local transaction payload_sha256 payload_size_bytes torii_base
  local response_path http_code submit_status=0 response_text terminal_json
  local payload_fd

  validation_fee_assert_prepared_ledger_operation_json \
    "$prepared_dir" "$operation_json" || return 1
  transaction="$(jq -ce '.transaction' <<<"$operation_json")" || return 1
  payload_sha256="$(jq -er '.payload_sha256' <<<"$operation_json")" || return 1
  payload_size_bytes="$(jq -er '.payload_size_bytes' <<<"$operation_json")" \
    || return 1
  [[ "$(shasum -a 256 "$prepared_dir/transaction.norito" | awk '{print $1}')" \
    == "$payload_sha256" \
    && "$(wc -c <"$prepared_dir/transaction.norito" | tr -d '[:space:]')" \
    == "$payload_size_bytes" ]] || {
    echo "prepared validation-fee ledger payload changed before submission" >&2
    return 1
  }
  zmodload zsh/system || {
    echo "validation-fee ledger submit requires zsh descriptor seeking" >&2
    return 1
  }
  exec {payload_fd}< "$prepared_dir/transaction.norito" || {
    echo "could not hold the frozen validation-fee ledger payload open" >&2
    return 1
  }
  validation_fee_assert_prepared_ledger_operation_json \
    "$prepared_dir" "$operation_json" "$payload_fd" || {
    exec {payload_fd}<&-
    return 1
  }
  [[ "$(validation_fee_mutation_journal_state "$journal_prefix")" == "absent" ]] \
    || {
      echo "prepared validation-fee ledger submit requires an absent mutation journal" >&2
      exec {payload_fd}<&-
      return 1
    }
  soraswap_require_public_submit_health_ready_for_config \
    "$config" "validation-fee prepared typed ledger transaction" || {
      local health_status=$?
      exec {payload_fd}<&-
      return "$health_status"
    }
  torii_base="$(torii_base_from_config "$config")" || {
    exec {payload_fd}<&-
    return 1
  }
  response_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-validation-fee-ledger-submit.XXXXXX")" \
    || {
      exec {payload_fd}<&-
      return 1
    }
  {
    if http_code="$(
      SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_prepared_ledger_transaction_immediate_gate \
      SORASWAP_IMMEDIATE_CURL_GATE_LABEL="validation-fee prepared typed ledger transaction" \
      SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$operation_json" \
      SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$journal_prefix" \
      SORASWAP_VALIDATION_FEE_IMMINENT_TRANSACTION_JSON="$transaction" \
      SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_SHA256="$payload_sha256" \
      SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_SIZE_BYTES="$payload_size_bytes" \
      SORASWAP_VALIDATION_FEE_IMMINENT_PREPARED_DIR="$prepared_dir" \
      SORASWAP_VALIDATION_FEE_IMMINENT_PAYLOAD_FD="$payload_fd" \
        soraswap_curl_for_config "$config" \
          -sS \
          --max-time "${SORASWAP_VALIDATION_FEE_SUBMIT_MAX_TIME_SECS:-120}" \
          -o "$response_path" \
          -w '%{http_code}' \
          -X POST \
          -H 'Content-Type: application/x-norito' \
          -H 'Accept: application/json' \
          -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
          --data-binary @- \
          "${torii_base%/}/v1/pipeline/transactions" <&$payload_fd
    )"; then
      submit_status=0
    else
      submit_status=$?
    fi
    if (( submit_status != 0 )); then
      echo "validation-fee typed ledger transport outcome is ambiguous; refusing retry" >&2
      return "$submit_status"
    fi
    if [[ "$http_code" != "200" && "$http_code" != "202" ]]; then
      response_text="$(soraswap_redact_sensitive_text <"$response_path")"
      echo "validation-fee typed ledger transaction was not accepted (HTTP $http_code): $response_text" >&2
      return 1
    fi
    terminal_json="$(
      validation_fee_applied_transaction_json \
        "$config" "$(jq -er '.tx_hash_hex' <<<"$transaction")"
    )" || return $?
    jq -cn \
      --argjson transaction "$transaction" \
      --argjson terminal "$terminal_json" \
      '{transaction: $transaction, terminal: $terminal}'
  } always {
    exec {payload_fd}<&-
    rm -f "$response_path"
  }
}

validation_fee_contract_call_with_evidence() {
  local config="$1"
  local contract_address="$2"
  local entrypoint="$3"
  local payload_json="${4:-null}"
  local journal_prefix="${5:-}"
  local operation_json receipt tx_hash hash_json terminal_json plan_sha256

  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  operation_json="$(jq -cn \
    --arg kind contract_call \
    --arg plan_sha256 "$plan_sha256" \
    --arg contract_address "$contract_address" \
    --arg entrypoint "$entrypoint" \
    --argjson arguments "$payload_json" \
    '{
      kind: $kind,
      plan_sha256: $plan_sha256,
      contract_address: $contract_address,
      entrypoint: $entrypoint,
      arguments: $arguments
    }')"
  tx_hash="$(
    SORASWAP_IMMEDIATE_SUBMIT_GATE_FUNCTION=validation_fee_contract_call_immediate_gate \
    SORASWAP_ACCEPTED_SUBMISSION_FUNCTION=validation_fee_contract_call_accepted_submission \
    SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$operation_json" \
    SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$journal_prefix" \
    SORASWAP_CONTRACT_CALL_RETRY_COUNT=1 \
    SORASWAP_CONTRACT_CALL_INVISIBLE_RETRY_COUNT=0 \
      call_contract_and_wait \
        "$config" \
        "$contract_address" \
        "$entrypoint" \
        "$payload_json"
  )" || return $?
  hash_json="$(validation_fee_normalized_transaction_hash_json "$tx_hash")" \
    || return 1
  validation_fee_assert_mutation_journal "$journal_prefix" "$operation_json" \
    || return 1
  if ! jq -e \
    --argjson transaction "$hash_json" \
    '.transaction == $transaction' \
    "$journal_prefix.submission.json" >/dev/null; then
    echo "accepted validation-fee contract-call journal changed transaction hash" >&2
    return 1
  fi
  terminal_json="$(
    validation_fee_applied_transaction_json \
      "$config" \
      "$(jq -r '.tx_hash_hex' <<<"$hash_json")"
  )" || return $?
  receipt="$(jq -cn \
    --arg contract_address "$contract_address" \
    --arg entrypoint "$entrypoint" \
    --argjson arguments "$payload_json" \
    --argjson transaction "$hash_json" \
    --argjson terminal "$terminal_json" \
    '{
      contract_address: $contract_address,
      entrypoint: $entrypoint,
      arguments: $arguments,
      transaction: $transaction,
      terminal: $terminal
    }')"
  if [[ -n "$journal_prefix" ]]; then
    validation_fee_record_mutation_applied \
      "$journal_prefix" "$receipt" "$operation_json" || return 1
  fi
  printf '%s\n' "$receipt"
}

validation_fee_register_account_with_evidence() {
  local config="$1"
  local account_id="$2"
  local purpose="$3"
  local journal_prefix="${4:-}"
  local prepared_dir="$5"
  local operation_json="${6:-}"
  local semantic_operation_json submission_json hash_json terminal_json receipt
  local plan_sha256

  if [[ "$(validation_fee_account_presence "$config" "$account_id")" != "absent" ]]; then
    echo "fresh validation-fee deployment requires unregistered subject $account_id" >&2
    return 1
  fi
  if [[ -z "$operation_json" ]]; then
    plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
    semantic_operation_json="$(jq -cn \
      --arg kind account_registration \
      --arg plan_sha256 "$plan_sha256" \
      --arg account_id "$account_id" \
      --arg purpose "$purpose" \
      '{
        kind: $kind,
        plan_sha256: $plan_sha256,
        account_id: $account_id,
        purpose: $purpose
      }')"
    operation_json="$(
      validation_fee_prepare_bound_ledger_operation_json \
        "$config" "$semantic_operation_json" "$prepared_dir"
    )" || return $?
  fi
  if ! jq -e \
    --arg account_id "$account_id" \
    --arg purpose "$purpose" \
    '
      .kind == "account_registration"
      and .account_id == $account_id
      and .purpose == $purpose
    ' >/dev/null <<<"$operation_json"; then
    echo "prepared validation-fee registration changed its reviewed subject mapping" >&2
    return 1
  fi
  submission_json="$(
    validation_fee_submit_prepared_ledger_transaction_json \
      "$config" "$operation_json" "$prepared_dir" "$journal_prefix"
  )" || return $?
  hash_json="$(jq -ce '.transaction' <<<"$submission_json")" || return 1
  terminal_json="$(jq -ce '.terminal' <<<"$submission_json")" || return 1
  if ! wait_for_account_exists "$config" "$account_id" 30 1; then
    echo "registered validation-fee subject did not become query-visible: $account_id" >&2
    return 1
  fi
  if [[ "$(validation_fee_account_presence "$config" "$account_id")" \
    != "present" ]]; then
    echo "registered validation-fee subject lacks an exact HTTP readback" >&2
    return 1
  fi
  receipt="$(jq -cn \
    --arg account_id "$account_id" \
    --arg purpose "$purpose" \
    --argjson transaction "$hash_json" \
    --argjson terminal "$terminal_json" \
    '{
      account_id: $account_id,
      purpose: $purpose,
      preexisting: false,
      transaction: $transaction,
      terminal: $terminal
    }')"
  validation_fee_record_mutation_applied \
    "$journal_prefix" "$receipt" "$operation_json" || return 1
  printf '%s\n' "$receipt"
}

validation_fee_grant_exact_permission_with_evidence() {
  local config="$1"
  local account_id="$2"
  local permission_json="$3"
  local journal_prefix="${4:-}"
  local prepared_dir="$5"
  local operation_json="${6:-}"
  local semantic_operation_json submission_json hash_json terminal_json receipt
  local plan_sha256

  if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    echo "fresh validation-fee bootstrap found a preexisting temporary permission" >&2
    return 1
  fi
  if [[ -z "$operation_json" ]]; then
    plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
    semantic_operation_json="$(jq -cn \
      --arg kind permission_grant \
      --arg plan_sha256 "$plan_sha256" \
      --arg account_id "$account_id" \
      --argjson permission "$permission_json" \
      '{
        kind: $kind,
        plan_sha256: $plan_sha256,
        account_id: $account_id,
        permission: $permission
      }')"
    operation_json="$(
      validation_fee_prepare_bound_ledger_operation_json \
        "$config" "$semantic_operation_json" "$prepared_dir"
    )" || return $?
  fi
  if ! jq -e \
    --arg account_id "$account_id" \
    --argjson permission "$permission_json" \
    '
      .kind == "permission_grant"
      and .account_id == $account_id
      and .permission == $permission
    ' >/dev/null <<<"$operation_json"; then
    echo "prepared validation-fee permission grant changed its exact typed selector" >&2
    return 1
  fi
  submission_json="$(
    validation_fee_submit_prepared_ledger_transaction_json \
      "$config" "$operation_json" "$prepared_dir" "$journal_prefix"
  )" || return $?
  hash_json="$(jq -ce '.transaction' <<<"$submission_json")" || return 1
  terminal_json="$(jq -ce '.terminal' <<<"$submission_json")" || return 1
  if ! account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    echo "validation-fee permission grant did not become query-visible" >&2
    return 1
  fi
  receipt="$(jq -cn \
    --arg account_id "$account_id" \
    --argjson permission "$permission_json" \
    --argjson transaction "$hash_json" \
    --argjson terminal "$terminal_json" \
    '{
      account_id: $account_id,
      permission: $permission,
      transaction: $transaction,
      terminal: $terminal
    }')"
  validation_fee_record_mutation_applied \
    "$journal_prefix" "$receipt" "$operation_json" || return 1
  printf '%s\n' "$receipt"
}

validation_fee_revoke_exact_permission_with_evidence() {
  local config="$1"
  local account_id="$2"
  local permission_json="$3"
  local journal_prefix="${4:-}"
  local prepared_dir="$5"
  local operation_json="${6:-}"
  local semantic_operation_json submission_json hash_json terminal_json receipt
  local plan_sha256

  if ! account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    echo "validation-fee bootstrap permission is absent before required revoke" >&2
    return 1
  fi
  if [[ -z "$operation_json" ]]; then
    plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
    semantic_operation_json="$(jq -cn \
      --arg kind permission_revoke \
      --arg plan_sha256 "$plan_sha256" \
      --arg account_id "$account_id" \
      --argjson permission "$permission_json" \
      '{
        kind: $kind,
        plan_sha256: $plan_sha256,
        account_id: $account_id,
        permission: $permission
      }')"
    operation_json="$(
      validation_fee_prepare_bound_ledger_operation_json \
        "$config" "$semantic_operation_json" "$prepared_dir"
    )" || return $?
  fi
  if ! jq -e \
    --arg account_id "$account_id" \
    --argjson permission "$permission_json" \
    '
      .kind == "permission_revoke"
      and .account_id == $account_id
      and .permission == $permission
    ' >/dev/null <<<"$operation_json"; then
    echo "prepared validation-fee permission revoke changed its exact typed selector" >&2
    return 1
  fi
  submission_json="$(
    validation_fee_submit_prepared_ledger_transaction_json \
      "$config" "$operation_json" "$prepared_dir" "$journal_prefix"
  )" || return $?
  hash_json="$(jq -ce '.transaction' <<<"$submission_json")" || return 1
  terminal_json="$(jq -ce '.terminal' <<<"$submission_json")" || return 1
  if account_has_exact_permission_json "$config" "$account_id" "$permission_json"; then
    echo "validation-fee permission revoke did not become query-visible" >&2
    return 1
  fi
  receipt="$(jq -cn \
    --arg account_id "$account_id" \
    --argjson permission "$permission_json" \
    --argjson transaction "$hash_json" \
    --argjson terminal "$terminal_json" \
    '{
      account_id: $account_id,
      permission: $permission,
      transaction: $transaction,
      terminal: $terminal
    }')"
  validation_fee_record_mutation_applied \
    "$journal_prefix" "$receipt" "$operation_json" || return 1
  printf '%s\n' "$receipt"
}

validation_fee_direct_permission_topology_json() {
  local config="$1"
  local permissions_json="$2"
  local observations='[]'
  local item holder expected direct present presence

  while IFS= read -r item; do
    holder="$(jq -er '.holder' <<<"$item")" || return 1
    expected="$(jq -c '{name, payload}' <<<"$item")" || return 1
    presence="$(validation_fee_account_presence "$config" "$holder")" || return 1
    if [[ "$presence" == "present" ]]; then
      direct="$(iroha_cli_json --config "$config" account permission list --id "$holder")" \
        || return 1
    elif [[ "$presence" == "absent" ]]; then
      direct='[]'
    else
      echo "unknown validation-fee account presence state for $holder" >&2
      return 1
    fi
    if ! jq -e 'type == "array"' >/dev/null <<<"$direct"; then
      echo "permission query for $holder did not return an array" >&2
      return 1
    fi
    present=false
    if jq -e \
      --argjson expected "$expected" \
      'any(.[]; .name == $expected.name and .payload == $expected.payload)' \
      >/dev/null <<<"$direct"; then
      present=true
    fi
    observations="$(jq -c \
      --arg holder "$holder" \
      --argjson permission "$expected" \
      --argjson present "$present" \
      '. + [{holder: $holder, permission: $permission, present: $present}]' \
      <<<"$observations")"
  done < <(jq -c '.[]' <<<"$permissions_json")
  printf '%s\n' "$observations"
}

validation_fee_protected_permission_topology_json() {
  local config="$1"
  local permissions_json="$2"
  local direct role_ids role_id role_permissions role_matches='[]'
  local subject_roles='[]' subject_direct_permissions='[]'
  local holder roles holder_permissions presence

  if ! jq -e 'type == "array" and length == 3' >/dev/null <<<"$permissions_json"; then
    echo "protected validation-fee topology requires exactly three permissions" >&2
    return 1
  fi
  direct="$(validation_fee_direct_permission_topology_json "$config" "$permissions_json")" \
    || return 1
  role_ids="$(iroha_cli_json --config "$config" ledger role list all)" || return 1
  if ! jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null <<<"$role_ids"; then
    echo "role list did not return an array of role IDs" >&2
    return 1
  fi
  while IFS= read -r role_id; do
    [[ -n "$role_id" ]] || continue
    role_permissions="$(
      iroha_cli_json --config "$config" ledger role permission list --id "$role_id"
    )" || return 1
    if ! jq -e 'type == "array"' >/dev/null <<<"$role_permissions"; then
      echo "permission list for role $role_id did not return an array" >&2
      return 1
    fi
    while IFS= read -r expected; do
      if jq -e \
        --argjson expected "$expected" \
        'any(.[]; .name == $expected.name and .payload == $expected.payload)' \
        >/dev/null <<<"$role_permissions"; then
        role_matches="$(jq -c \
          --arg role_id "$role_id" \
          --argjson permission "$expected" \
          '. + [{role_id: $role_id, permission: $permission}]' \
          <<<"$role_matches")"
      fi
    done < <(jq -c '.[] | {name, payload}' <<<"$permissions_json")
  done < <(jq -r '.[]' <<<"$role_ids")

  while IFS= read -r holder; do
    [[ -n "$holder" ]] || continue
    presence="$(validation_fee_account_presence "$config" "$holder")" || return 1
    if [[ "$presence" == "present" ]]; then
      roles="$(iroha_cli_json --config "$config" account role list --id "$holder")" \
        || return 1
      holder_permissions="$(
        iroha_cli_json --config "$config" account permission list --id "$holder"
      )" || return 1
    elif [[ "$presence" == "absent" ]]; then
      roles='[]'
      holder_permissions='[]'
    else
      echo "unknown validation-fee account presence state for $holder" >&2
      return 1
    fi
    if ! jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null <<<"$roles"; then
      echo "account role list for $holder did not return an array" >&2
      return 1
    fi
    if ! jq -e 'type == "array"' >/dev/null <<<"$holder_permissions"; then
      echo "account permission list for $holder did not return an array" >&2
      return 1
    fi
    subject_roles="$(jq -c \
      --arg account_id "$holder" \
      --argjson roles "$roles" \
      '. + [{account_id: $account_id, roles: $roles}]' \
      <<<"$subject_roles")"
    subject_direct_permissions="$(jq -c \
      --arg account_id "$holder" \
      --argjson permissions "$holder_permissions" \
      '. + [{account_id: $account_id, permissions: $permissions}]' \
      <<<"$subject_direct_permissions")"
  done < <(jq -r 'map(.holder) | unique[]' <<<"$permissions_json")

  jq -cn \
    --argjson direct "$direct" \
    --argjson role_permission_matches "$role_matches" \
    --argjson subject_roles "$subject_roles" \
    --argjson subject_direct_permissions "$subject_direct_permissions" \
    '{
      direct: $direct,
      role_permission_matches: $role_permission_matches,
      subject_roles: $subject_roles,
      subject_direct_permissions: $subject_direct_permissions,
      direct_absent: (all($direct[]; .present == false)),
      role_permissions_absent: ($role_permission_matches | length == 0),
      subject_permissions_absent: (
        all($subject_direct_permissions[]; .permissions | length == 0)
      ),
      subject_roles_absent: (all($subject_roles[]; .roles | length == 0)),
      absent: (
        all($direct[]; .present == false)
        and ($role_permission_matches | length == 0)
        and all($subject_direct_permissions[]; .permissions | length == 0)
        and all($subject_roles[]; .roles | length == 0)
      )
    }'
}

validation_fee_assert_protected_permission_topology_absent() {
  local topology_json="$1"

  if ! jq -e '
    type == "object"
    and (.direct | type == "array" and length == 3)
    and all(.direct[]; .present == false)
    and (.role_permission_matches | type == "array" and length == 0)
    and (
      .subject_roles
      | type == "array"
      and length == 2
      and all(.[]; .roles | type == "array" and length == 0)
    )
    and (
      .subject_direct_permissions
      | type == "array"
      and length == 2
      and all(.[]; .permissions | type == "array" and length == 0)
    )
    and .direct_absent == true
    and .role_permissions_absent == true
    and .subject_permissions_absent == true
    and .subject_roles_absent == true
    and .absent == true
  ' >/dev/null <<<"$topology_json"; then
    echo "protected validation-fee permission topology is not completely absent" >&2
    return 1
  fi
}

validation_fee_validate_split_deploy_receipt_json() {
  local split_json="$1"
  local spec_json="$2"
  local contract_json="$3"
  local expected_chain expected_discriminant expected_dataspace
  local expected_address expected_alias expected_subject expected_nonce
  local expected_code_hash

  expected_chain="$(jq -er '.chain_id' <<<"$spec_json")" || return 1
  expected_discriminant="$(jq -er '.chain_discriminant' <<<"$spec_json")" \
    || return 1
  expected_dataspace="$(jq -er '.dataspace' <<<"$spec_json")" || return 1
  expected_address="$(jq -er '.contract_address' <<<"$contract_json")" \
    || return 1
  expected_alias="$(jq -er '.alias' <<<"$contract_json")" || return 1
  expected_subject="$(jq -er '.subject_account_id' <<<"$contract_json")" \
    || return 1
  expected_nonce="$(jq -er '.deploy_nonce' <<<"$contract_json")" || return 1
  expected_code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1

  if ! jq -e \
    --arg chain_id "$expected_chain" \
    --argjson chain_discriminant "$expected_discriminant" \
    --arg dataspace "$expected_dataspace" \
    --arg contract_address "$expected_address" \
    --arg contract_alias "$expected_alias" \
    --arg contract_subject "$expected_subject" \
    --argjson deploy_nonce "$expected_nonce" \
    --arg code_hash "$expected_code_hash" \
    '
      def normalized_hash:
        tostring
        | ascii_downcase
        | sub("^0x"; "")
        | sub("^hash:"; "")
        | split("#")[0];
      .ok == true
      and .submitted == true
      and .chain_id == $chain_id
      and .chain_discriminant == $chain_discriminant
      and .dataspace == $dataspace
      and .contract_address == $contract_address
      and .contract_alias == $contract_alias
      and .contract_subject_account == $contract_subject
      and .deploy_nonce == $deploy_nonce
      and .next_deploy_nonce == ($deploy_nonce + 1)
      and .expected_previous_contract_address == null
      and ((.code_hash_hex | normalized_hash) == $code_hash)
      and (.register_bytes_tx_strategy == "native_chunks")
      and (.register_bytes_chunk_count | type == "number" and . >= 1)
      and (
        .register_bytes_chunk_count as $chunk_count
        | .register_bytes_stage_tx_hashes
          | type == "array"
          and length == ($chunk_count - 1)
          and all(.[];
            type == "string"
            and test("^(hash:[0-9A-F]{64}#[0-9A-F]{4}|(0x)?[0-9A-Fa-f]{64})$")
          )
      )
      and (
        .register_bytes_tx_hash
        | type == "string"
        and test("^(hash:[0-9A-F]{64}#[0-9A-F]{4}|(0x)?[0-9A-Fa-f]{64})$")
      )
      and (
        .register_manifest_tx_hash
        | type == "string"
        and test("^(hash:[0-9A-F]{64}#[0-9A-F]{4}|(0x)?[0-9A-Fa-f]{64})$")
      )
      and (
        .commit_tx_hash
        | type == "string"
        and test("^(hash:[0-9A-F]{64}#[0-9A-F]{4}|(0x)?[0-9A-Fa-f]{64})$")
      )
      and (
        (
          .register_bytes_stage_tx_hashes
          + [
              .register_bytes_tx_hash,
              .register_manifest_tx_hash,
              .commit_tx_hash
            ]
          | map(normalized_hash)
        ) as $transaction_hashes
        | ($transaction_hashes | length)
          == ($transaction_hashes | unique | length)
      )
    ' >/dev/null <<<"$split_json"; then
    echo "split validation-fee deploy receipt differs from the reviewed contract binding" >&2
    return 1
  fi
  printf '%s\n' "$split_json"
}

validation_fee_split_deploy_transactions_json() {
  local config="$1"
  local split_json="$2"
  local records='[]'
  local item label hash_literal hash_json terminal_json

  while IFS= read -r item; do
    label="$(jq -er '.label' <<<"$item")" || return 1
    hash_literal="$(jq -er '.hash' <<<"$item")" || return 1
    hash_json="$(validation_fee_normalized_transaction_hash_json "$hash_literal")" \
      || return 1
    terminal_json="$(
      validation_fee_applied_transaction_json \
        "$config" \
        "$(jq -r '.tx_hash_hex' <<<"$hash_json")"
    )" || return $?
    records="$(jq -c \
      --arg label "$label" \
      --argjson transaction "$hash_json" \
      --argjson terminal "$terminal_json" \
      '. + [{label: $label, transaction: $transaction, terminal: $terminal}]' \
      <<<"$records")"
  done < <(jq -c '
    [
      (.register_bytes_stage_tx_hashes | to_entries[] | {
        label: ("register_bytes_stage_" + (.key | tostring)),
        hash: .value
      }),
      {label: "register_bytes_finalize", hash: .register_bytes_tx_hash},
      {label: "register_manifest", hash: .register_manifest_tx_hash},
      {label: "commit", hash: .commit_tx_hash}
    ][]
  ' <<<"$split_json")

  if ! jq -e '
    length >= 3
    and ([.[].transaction.tx_hash_hex] | length == (unique | length))
  ' >/dev/null <<<"$records"; then
    echo "split validation-fee deploy transaction evidence is incomplete or duplicated" >&2
    return 1
  fi
  printf '%s\n' "$records"
}

validation_fee_assert_manifest_hashes() {
  local manifest_json="$1"
  local contract_json="$2"
  local expected_code_hash expected_abi_hash

  expected_code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1
  expected_abi_hash="$(jq -er '.abi_hash' <<<"$contract_json")" || return 1
  if ! jq -e \
    --arg code_hash "$expected_code_hash" \
    --arg abi_hash "$expected_abi_hash" \
    '
      def normalized_hash:
        tostring
        | ascii_downcase
        | sub("^0x"; "")
        | sub("^hash:"; "")
        | split("#")[0];
      (
        .manifest.code_hash
        // .manifest.code_hash_hex
        // .code_hash
        // .code_hash_hex
        // ""
        | normalized_hash
      ) == $code_hash
      and (
        .manifest.abi_hash
        // .manifest.abi_hash_hex
        // .abi_hash
        // .abi_hash_hex
        // ""
        | normalized_hash
      ) == $abi_hash
    ' >/dev/null <<<"$manifest_json"; then
    echo "live validation-fee manifest code/ABI hashes differ from the reviewed artifact" >&2
    return 1
  fi
}

validation_fee_assert_alias_resolution() {
  local resolution_json="$1"
  local contract_json="$2"
  local expected_address expected_dataspace

  expected_address="$(jq -er '.contract_address' <<<"$contract_json")" \
    || return 1
  expected_dataspace="${3:-universal}"
  if ! jq -e \
    --arg contract_address "$expected_address" \
    --arg dataspace "$expected_dataspace" \
    '
      .contract_address == $contract_address
      and (.dataspace // "universal") == $dataspace
    ' >/dev/null <<<"$resolution_json"; then
    echo "live validation-fee contract alias does not resolve to the reviewed address" >&2
    return 1
  fi
}

validation_fee_split_deploy_with_evidence() {
  echo "multi-transaction validation-fee deploy is disabled; use the frozen prepared one-write workflow" >&2
  return 1

  local config="$1"
  local authority="$2"
  local spec_json="$3"
  local contract_json="$4"
  local split_bin="$5"
  local deploy_nonce contract_address contract_alias contract_subject dataspace
  local chain_discriminant code_file code_hash abi_hash current_nonce next_nonce
  local private_key_file fee_payment_file gas_limit split_output_raw split_output
  local split_status=0 transactions_json alias_json manifest_json

  deploy_nonce="$(jq -er '.deploy_nonce' <<<"$contract_json")" || return 1
  contract_address="$(jq -er '.contract_address' <<<"$contract_json")" \
    || return 1
  contract_alias="$(jq -er '.alias' <<<"$contract_json")" || return 1
  contract_subject="$(jq -er '.subject_account_id' <<<"$contract_json")" \
    || return 1
  dataspace="$(jq -er '.dataspace' <<<"$spec_json")" || return 1
  chain_discriminant="$(jq -er '.chain_discriminant' <<<"$spec_json")" \
    || return 1
  code_file="$SORASWAP_ROOT/$(jq -er '.artifact' <<<"$contract_json")" \
    || return 1
  code_hash="$(jq -er '.code_hash' <<<"$contract_json")" || return 1
  abi_hash="$(jq -er '.abi_hash' <<<"$contract_json")" || return 1

  [[ -x "$split_bin" ]] || {
    echo "reviewed split_contract_deploy binary is not executable: $split_bin" >&2
    return 1
  }
  [[ -f "$code_file" && ! -L "$code_file" ]] || {
    echo "reviewed validation-fee artifact is missing or not a regular file: $code_file" >&2
    return 1
  }
  [[ "$(validation_fee_account_presence "$config" "$contract_subject")" \
    == "present" ]] || {
    echo "validation-fee contract subject is not registered: $contract_subject" >&2
    return 1
  }
  if contract_alias_resolve_json "$config" "$contract_alias" >/dev/null 2>&1; then
    echo "fresh validation-fee deploy requires absent alias $contract_alias" >&2
    return 1
  elif (( $? != 2 )); then
    echo "could not prove validation-fee alias absence: $contract_alias" >&2
    return 1
  fi
  current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
    || {
      echo "could not query the exact validation-fee deploy nonce" >&2
      return 1
    }
  if [[ "$current_nonce" != "$deploy_nonce" ]]; then
    echo "validation-fee deploy nonce is $current_nonce, expected exactly $deploy_nonce" >&2
    return 1
  fi

  soraswap_require_public_submit_health_ready_for_config \
    "$config" \
    "validation-fee contract deploy $contract_alias" || return $?
  private_key_file="$(soraswap_config_private_key_temp_file \
    "$config" validation-fee-split-deploy-key)" || return 1
  gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
  soraswap_require_positive_integer_setting \
    "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      return 1
    }
  fee_payment_file="$(jq -cn \
    --argjson gas_limit "$gas_limit" \
    '{payer: "authority", value: {charge_limits: [], gas_limit: $gas_limit}}' \
    | soraswap_secret_temp_from_stdin validation-fee-deploy-fee-payment)" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      return 1
    }
  {
    if split_output_raw="$(
      "$split_bin" \
        --config "$config" \
        --authority "$authority" \
        --private-key-file "$private_key_file" \
        --code-file "$code_file" \
        --contract-address "$contract_address" \
        --contract-alias "$contract_alias" \
        --dataspace "$dataspace" \
        --chain-discriminant "$chain_discriminant" \
        --deploy-nonce "$deploy_nonce" \
        --fee-payment-json "$fee_payment_file" \
        2>&1
    )"; then
      split_status=0
    else
      split_status=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_files \
      "$private_key_file" "$fee_payment_file"; then
      split_status=1
    fi
  }
  if (( split_status != 0 )); then
    echo "exact validation-fee split deploy failed for $contract_alias" >&2
    soraswap_redact_sensitive_text <<<"$split_output_raw" >&2
    return "$split_status"
  fi
  split_output="$(extract_last_json_object <<<"$split_output_raw")" || {
    echo "exact validation-fee split deploy did not return JSON" >&2
    return 1
  }
  validation_fee_validate_split_deploy_receipt_json \
    "$split_output" "$spec_json" "$contract_json" >/dev/null || return 1
  transactions_json="$(
    validation_fee_split_deploy_transactions_json "$config" "$split_output"
  )" || return $?
  alias_json="$(
    wait_for_contract_alias_activation \
      "$config" \
      "$contract_alias" \
      "$contract_address" \
      "$(jq -r '.commit_tx_hash' <<<"$split_output")"
  )" || return 1
  validation_fee_assert_alias_resolution \
    "$alias_json" "$contract_json" "$dataspace" || return 1
  manifest_json="$(
    wait_for_contract_manifest_by_code_hash \
      "$config" "$code_hash" "${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-120}" 1
  )" || return 1
  validation_fee_assert_manifest_hashes "$manifest_json" "$contract_json" \
    || return 1
  wait_for_contract_code_bytes_by_code_hash \
    "$config" "$code_hash" "${SORASWAP_DEPLOY_MANIFEST_WAIT_SECS:-120}" 1 \
    >/dev/null || return 1
  next_nonce=$(( deploy_nonce + 1 ))
  current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
    || return 1
  if [[ "$current_nonce" != "$next_nonce" ]]; then
    echo "validation-fee deploy nonce is $current_nonce after deploy, expected $next_nonce" >&2
    return 1
  fi
  jq -cn \
    --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
    --arg contract_address "$contract_address" \
    --arg contract_alias "$contract_alias" \
    --arg subject_account_id "$contract_subject" \
    --arg code_hash "$code_hash" \
    --arg abi_hash "$abi_hash" \
    --argjson deploy_nonce "$deploy_nonce" \
    --argjson next_deploy_nonce "$next_nonce" \
    --argjson split_receipt "$split_output" \
    --argjson transactions "$transactions_json" \
    --argjson alias_resolution "$alias_json" \
    --argjson manifest "$manifest_json" \
    '{
      contract_key: $contract_key,
      contract_address: $contract_address,
      contract_alias: $contract_alias,
      subject_account_id: $subject_account_id,
      deploy_nonce: $deploy_nonce,
      next_deploy_nonce: $next_deploy_nonce,
      code_hash: $code_hash,
      abi_hash: $abi_hash,
      split_receipt: $split_receipt,
      transactions: $transactions,
      alias_resolution: $alias_resolution,
      manifest: $manifest,
      code_bytes_visible: true
    }'
}

validation_fee_split_transaction_plan_json() {
  local split_json="$1"

  jq -c '
    [
      (
        .register_bytes_stage_tx_hashes
        | to_entries[]
        | {
            label: ("register_bytes_stage_" + (.key | tostring)),
            tx_hash: .value
          }
      ),
      {
        label: "register_bytes_finalize",
        tx_hash: .register_bytes_tx_hash
      },
      {
        label: "register_manifest",
        tx_hash: .register_manifest_tx_hash
      },
      {label: "commit", tx_hash: .commit_tx_hash}
    ]
  ' <<<"$split_json"
}

validation_fee_validate_prepared_split_deploy_json() {
  local prepared_json="$1"
  local prepared_dir="$2"
  local spec_json="$3"
  local contract_json="$4"
  local split_json expected_transactions transaction item file_path file_sha mode
  local actual_size expected_size actual_entries expected_entries entry dir_mode

  if ! jq -e '
    .schema_version == 1
    and .phase == "prepared_split_deploy"
    and (
      keys == [
        "contract_key",
        "phase",
        "schema_version",
        "split_receipt",
        "transactions"
      ]
    )
    and (.contract_key | type == "string" and length > 0)
    and (.split_receipt | type == "object")
    and (.transactions | type == "array" and length >= 3)
    and all(
      .transactions[];
      (
        keys == [
          "emitted_name",
          "emitted_size",
          "file",
          "label",
          "payload_sha256",
          "sequence",
          "transaction"
        ]
      )
      and (.sequence | type == "number" and . >= 1)
      and (.label | type == "string" and test("^[0-9A-Za-z_-]+$"))
      and (.emitted_name | type == "string" and test("^[0-9A-Za-z_-]+$"))
      and (.emitted_size | type == "number" and . >= 1)
      and (.file | type == "string" and test("^[0-9]{4}\\.[0-9A-Za-z_-]+\\.norito$"))
      and (.payload_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (.transaction | type == "object")
    )
  ' >/dev/null <<<"$prepared_json"; then
    echo "prepared validation-fee split deploy journal is invalid" >&2
    return 1
  fi
  split_json="$(jq -ce '.split_receipt' <<<"$prepared_json")" || return 1
  for entry in "$prepared_dir" "$prepared_dir/transactions"; do
    [[ -d "$entry" && ! -L "$entry" ]] || {
      echo "prepared validation-fee split path is not a real directory" >&2
      return 1
    }
    dir_mode="$(stat -f '%Lp' "$entry" 2>/dev/null \
      || stat -c '%a' "$entry" 2>/dev/null)" || return 1
    [[ "$dir_mode" == "555" ]] || {
      echo "prepared validation-fee split directories must be mode 0555" >&2
      return 1
    }
  done
  validation_fee_validate_split_deploy_receipt_json \
    "$split_json" "$spec_json" "$contract_json" >/dev/null || return 1
  expected_transactions="$(
    validation_fee_split_transaction_plan_json "$split_json"
  )" || return 1
  if ! jq -e \
    --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
    --argjson expected "$expected_transactions" \
    '
      .contract_key == $contract_key
      and (.transactions | length) == ($expected | length)
      and (
        .transactions
        | map({label, tx_hash: .transaction.tx_hash})
      ) == $expected
      and (
        .transactions as $transactions
        | ($transactions | map(.sequence))
          == [range(1; (($transactions | length) + 1))]
      )
    ' >/dev/null <<<"$prepared_json"; then
    echo "prepared validation-fee transactions do not match the split receipt" >&2
    return 1
  fi
  while IFS= read -r item; do
    transaction="$(jq -ce '.transaction' <<<"$item")" || return 1
    validation_fee_normalized_transaction_hash_json \
      "$(jq -er '.tx_hash' <<<"$transaction")" >/dev/null || return 1
    if [[ "$(jq -er '.tx_hash_hex' <<<"$transaction")" \
      != "$(validation_fee_normalized_transaction_hash_json \
        "$(jq -er '.tx_hash' <<<"$transaction")" | jq -r '.tx_hash_hex')" ]]; then
      echo "prepared validation-fee transaction hash forms differ" >&2
      return 1
    fi
    file_path="$prepared_dir/transactions/$(jq -er '.file' <<<"$item")"
    [[ -f "$file_path" && ! -L "$file_path" ]] || {
      echo "prepared validation-fee transaction payload is missing: $file_path" >&2
      return 1
    }
    mode="$(stat -f '%Lp' "$file_path" 2>/dev/null \
      || stat -c '%a' "$file_path" 2>/dev/null)" || return 1
    [[ "$mode" == "444" ]] || {
      echo "prepared validation-fee transaction payload must be mode 0444" >&2
      return 1
    }
    file_sha="$(shasum -a 256 "$file_path" | awk '{print $1}')"
    [[ "$file_sha" == "$(jq -er '.payload_sha256' <<<"$item")" ]] || {
      echo "prepared validation-fee transaction payload digest changed" >&2
      return 1
    }
    actual_size="$(wc -c <"$file_path" | tr -d '[:space:]')"
    expected_size="$(jq -er '.emitted_size' <<<"$item")" || return 1
    [[ "$actual_size" == "$expected_size" ]] || {
      echo "prepared validation-fee transaction payload size changed" >&2
      return 1
    }
  done < <(jq -c '.transactions[]' <<<"$prepared_json")
  actual_entries='[]'
  for entry in "$prepared_dir"/*(DN); do
    [[ "${entry:t}" == "plan.json" || "${entry:t}" == "transactions" ]] || {
      echo "prepared validation-fee split directory contains an unexpected entry" >&2
      return 1
    }
    actual_entries="$(jq -c --arg entry "${entry:t}" '. + [$entry]' \
      <<<"$actual_entries")"
  done
  [[ "$(jq -cS . <<<"$actual_entries")" == '["plan.json","transactions"]' ]] || {
    echo "prepared validation-fee split directory is incomplete" >&2
    return 1
  }
  [[ -d "$prepared_dir/transactions" && ! -L "$prepared_dir/transactions" ]] \
    || {
      echo "prepared validation-fee transaction directory is invalid" >&2
      return 1
    }
  actual_entries='[]'
  for entry in "$prepared_dir/transactions"/*(DN); do
    [[ -f "$entry" && ! -L "$entry" ]] || {
      echo "prepared validation-fee transaction directory contains a non-file" >&2
      return 1
    }
    actual_entries="$(jq -c --arg entry "${entry:t}" '. + [$entry]' \
      <<<"$actual_entries")"
  done
  expected_entries="$(jq -c '[.transactions[].file]' <<<"$prepared_json")" \
    || return 1
  if [[ "$(jq -cS 'sort' <<<"$actual_entries")" \
    != "$(jq -cS 'sort' <<<"$expected_entries")" ]]; then
    echo "prepared validation-fee transaction file set changed" >&2
    return 1
  fi
}

validation_fee_prepare_split_deploy_one_write_json() {
  local config="$1"
  local authority="$2"
  local spec_json="$3"
  local contract_json="$4"
  local split_bin="$5"
  local prepared_dir="$6"
  local plan_path="$prepared_dir/plan.json"
  local deploy_nonce contract_address contract_alias contract_subject dataspace
  local chain_discriminant code_file current_nonce private_key_file fee_payment_file
  local gas_limit staging_dir staging_transactions split_output_raw split_output
  local split_status=0 transaction_plan='[]' transaction_count index item
  local emitted_file emitted_name emitted_size actual_size destination_file
  local payload_sha transaction hash_json prepared_json actual_emitted_count

  if [[ -e "$plan_path" ]]; then
    validation_fee_require_immutable_json_file "$plan_path" || return 1
    prepared_json="$(jq -ce . "$plan_path")" || return 1
    validation_fee_validate_prepared_split_deploy_json \
      "$prepared_json" "$prepared_dir" "$spec_json" "$contract_json" || return 1
    printf '%s\n' "$prepared_json"
    return 0
  fi
  if [[ -e "$prepared_dir" || -L "$prepared_dir" ]]; then
    echo "refusing incomplete prepared validation-fee split directory: $prepared_dir" >&2
    return 1
  fi

  deploy_nonce="$(jq -er '.deploy_nonce' <<<"$contract_json")" || return 1
  contract_address="$(jq -er '.contract_address' <<<"$contract_json")" \
    || return 1
  contract_alias="$(jq -er '.alias' <<<"$contract_json")" || return 1
  contract_subject="$(jq -er '.subject_account_id' <<<"$contract_json")" \
    || return 1
  dataspace="$(jq -er '.dataspace' <<<"$spec_json")" || return 1
  chain_discriminant="$(jq -er '.chain_discriminant' <<<"$spec_json")" \
    || return 1
  code_file="$SORASWAP_ROOT/$(jq -er '.artifact' <<<"$contract_json")" \
    || return 1
  [[ -x "$split_bin" ]] || {
    echo "reviewed split_contract_deploy binary is not executable: $split_bin" >&2
    return 1
  }
  [[ -f "$code_file" && ! -L "$code_file" ]] || {
    echo "reviewed validation-fee artifact is missing or not a regular file: $code_file" >&2
    return 1
  }
  [[ "$(validation_fee_account_presence "$config" "$contract_subject")" \
    == "present" ]] || {
    echo "validation-fee contract subject is not registered: $contract_subject" >&2
    return 1
  }
  if contract_alias_resolve_json "$config" "$contract_alias" >/dev/null 2>&1; then
    echo "fresh validation-fee deploy requires absent alias $contract_alias" >&2
    return 1
  elif (( $? != 2 )); then
    echo "could not prove validation-fee alias absence: $contract_alias" >&2
    return 1
  fi
  current_nonce="$(contract_deploy_nonce_for_authority "$config" "$authority")" \
    || {
      echo "could not query the exact validation-fee deploy nonce" >&2
      return 1
    }
  [[ "$current_nonce" == "$deploy_nonce" ]] || {
    echo "validation-fee deploy nonce is $current_nonce, expected exactly $deploy_nonce" >&2
    return 1
  }

  validation_fee_ensure_durable_directory "${prepared_dir:h}" || return 1
  staging_dir="$(mktemp -d "${prepared_dir:h}/.validation-fee-prepared.XXXXXX")" \
    || return 1
  staging_transactions="$staging_dir/transactions"
  mkdir "$staging_transactions"
  chmod 0700 "$staging_dir" "$staging_transactions"
  private_key_file="$(soraswap_config_private_key_temp_file \
    "$config" validation-fee-split-deploy-key)" || {
      rm -rf "$staging_dir"
      return 1
    }
  gas_limit="${SORASWAP_LEDGER_GAS_LIMIT:-2000000}"
  soraswap_require_positive_integer_setting \
    "SORASWAP_LEDGER_GAS_LIMIT" "$gas_limit" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      rm -rf "$staging_dir"
      return 1
    }
  fee_payment_file="$(jq -cn \
    --argjson gas_limit "$gas_limit" \
    '{payer: "authority", value: {charge_limits: [], gas_limit: $gas_limit}}' \
    | soraswap_secret_temp_from_stdin validation-fee-deploy-fee-payment)" || {
      soraswap_secure_unlink_owned_file "$private_key_file" || true
      rm -rf "$staging_dir"
      return 1
    }
  {
    if split_output_raw="$(
      "$split_bin" \
        --config "$config" \
        --authority "$authority" \
        --private-key-file "$private_key_file" \
        --code-file "$code_file" \
        --contract-address "$contract_address" \
        --contract-alias "$contract_alias" \
        --dataspace "$dataspace" \
        --chain-discriminant "$chain_discriminant" \
        --deploy-nonce "$deploy_nonce" \
        --fee-payment-json "$fee_payment_file" \
        --out-dir "$staging_transactions" \
        --emit-only \
        2>&1
    )"; then
      split_status=0
    else
      split_status=$?
    fi
  } always {
    if ! soraswap_secure_unlink_owned_files \
      "$private_key_file" "$fee_payment_file"; then
      split_status=1
    fi
  }
  if (( split_status != 0 )); then
    echo "exact validation-fee split preparation failed for $contract_alias" >&2
    soraswap_redact_sensitive_text <<<"$split_output_raw" >&2
    rm -rf "$staging_dir"
    return "$split_status"
  fi
  split_output="$(extract_last_json_object <<<"$split_output_raw")" || {
    echo "exact validation-fee split preparation did not return JSON" >&2
    rm -rf "$staging_dir"
    return 1
  }
  if ! jq -e '.submitted == false and (.files | type == "array")' \
    >/dev/null <<<"$split_output"; then
    echo "split validation-fee preparation claimed a live submission" >&2
    rm -rf "$staging_dir"
    return 1
  fi
  validation_fee_validate_split_deploy_receipt_json \
    "$(jq -c '.submitted = true' <<<"$split_output")" \
    "$spec_json" "$contract_json" >/dev/null || {
      rm -rf "$staging_dir"
      return 1
    }
  transaction_plan="$(
    validation_fee_split_transaction_plan_json "$split_output"
  )" || {
    rm -rf "$staging_dir"
    return 1
  }
  transaction_count="$(jq -r 'length' <<<"$transaction_plan")"
  if [[ "$(jq -r '.files | length' <<<"$split_output")" != "$transaction_count" ]]; then
    echo "split validation-fee preparation emitted an unexpected file count" >&2
    rm -rf "$staging_dir"
    return 1
  fi
  actual_emitted_count="$(
    find "$staging_transactions" -mindepth 1 -maxdepth 1 -type f \
      | wc -l | tr -d '[:space:]'
  )"
  if [[ "$actual_emitted_count" != "$transaction_count" ]] \
    || [[ -n "$(
      find "$staging_transactions" -mindepth 1 -maxdepth 1 ! -type f -print -quit
    )" ]]; then
    echo "split validation-fee preparation emitted an unexpected filesystem shape" >&2
    rm -rf "$staging_dir"
    return 1
  fi
  index=0
  while (( index < transaction_count )); do
    item="$(jq -ce --argjson index "$index" '.[$index]' \
      <<<"$transaction_plan")" || {
        rm -rf "$staging_dir"
        return 1
      }
    emitted_file="$(jq -er --argjson index "$index" '.files[$index].path' \
      <<<"$split_output")" || {
        rm -rf "$staging_dir"
        return 1
      }
    emitted_name="$(jq -er --argjson index "$index" '.files[$index].name' \
      <<<"$split_output")" || {
        rm -rf "$staging_dir"
        return 1
      }
    emitted_size="$(jq -er --argjson index "$index" '.files[$index].size' \
      <<<"$split_output")" || {
        rm -rf "$staging_dir"
        return 1
      }
    if [[ ! "$emitted_name" =~ '^[0-9A-Za-z_-]+$' \
      || "$emitted_size" != <-> || "$emitted_size" -lt 1 ]]; then
      echo "split validation-fee preparation emitted invalid file metadata" >&2
      rm -rf "$staging_dir"
      return 1
    fi
    case "$(jq -er '.label' <<<"$item")" in
      register_bytes_stage_*)
        [[ "$emitted_name" == register_bytes_chunk_* ]] || {
          echo "split validation-fee chunk file order differs from its receipt" >&2
          rm -rf "$staging_dir"
          return 1
        }
        ;;
      *)
        [[ "$emitted_name" == "$(jq -er '.label' <<<"$item")" ]] || {
          echo "split validation-fee emitted file label differs from its receipt" >&2
          rm -rf "$staging_dir"
          return 1
        }
        ;;
    esac
    if [[ "${emitted_file:A:h}" != "${staging_transactions:A}" \
      || ! -f "$emitted_file" || -L "$emitted_file" ]]; then
      echo "split validation-fee preparation emitted an unsafe transaction path" >&2
      rm -rf "$staging_dir"
      return 1
    fi
    actual_size="$(wc -c <"$emitted_file" | tr -d '[:space:]')"
    if [[ "$actual_size" != "$emitted_size" ]]; then
      echo "split validation-fee emitted file size differs from its receipt" >&2
      rm -rf "$staging_dir"
      return 1
    fi
    printf -v destination_file '%04d.%s.norito' \
      "$(( index + 1 ))" "$(jq -er '.label' <<<"$item")"
    mv "$emitted_file" "$staging_transactions/$destination_file"
    chmod 0444 "$staging_transactions/$destination_file"
    validation_fee_fsync_file \
      "$staging_transactions/$destination_file" || {
        rm -rf "$staging_dir"
        return 1
      }
    payload_sha="$(
      shasum -a 256 "$staging_transactions/$destination_file" | awk '{print $1}'
    )"
    hash_json="$(
      validation_fee_normalized_transaction_hash_json \
        "$(jq -er '.tx_hash' <<<"$item")"
    )" || {
      rm -rf "$staging_dir"
      return 1
    }
    transaction="$(jq -cn \
      --argjson sequence "$(( index + 1 ))" \
      --arg label "$(jq -er '.label' <<<"$item")" \
      --arg emitted_name "$emitted_name" \
      --argjson emitted_size "$emitted_size" \
      --arg file "$destination_file" \
      --arg payload_sha256 "$payload_sha" \
      --argjson transaction "$hash_json" \
      '{
        sequence: $sequence,
        label: $label,
        emitted_name: $emitted_name,
        emitted_size: $emitted_size,
        file: $file,
        payload_sha256: $payload_sha256,
        transaction: $transaction
      }')"
    transaction_plan="$(jq -c \
      --argjson index "$index" \
      --argjson transaction "$transaction" \
      '.[$index] = $transaction' <<<"$transaction_plan")"
    index=$(( index + 1 ))
  done
  prepared_json="$(jq -cn \
    --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
    --argjson split_receipt "$(
      jq -c '.submitted = true | del(.files)' <<<"$split_output"
    )" \
    --argjson transactions "$transaction_plan" \
    '{
      schema_version: 1,
      phase: "prepared_split_deploy",
      contract_key: $contract_key,
      split_receipt: $split_receipt,
      transactions: $transactions
    }')"
  validation_fee_write_immutable_json \
    "$prepared_json" "$staging_dir/plan.json" >/dev/null || {
      rm -rf "$staging_dir"
      return 1
    }
  chmod 0555 "$staging_transactions" "$staging_dir"
  validation_fee_fsync_directory "$staging_transactions" || {
    chmod 0700 "$staging_transactions" "$staging_dir" 2>/dev/null || true
    rm -rf "$staging_dir"
    return 1
  }
  validation_fee_fsync_directory "$staging_dir" || {
    chmod 0700 "$staging_transactions" "$staging_dir" 2>/dev/null || true
    rm -rf "$staging_dir"
    return 1
  }
  mv "$staging_dir" "$prepared_dir"
  validation_fee_fsync_directory "${prepared_dir:h}" || return 1
  validation_fee_fsync_directory "$prepared_dir" || return 1
  validation_fee_validate_prepared_split_deploy_json \
    "$prepared_json" "$prepared_dir" "$spec_json" "$contract_json" || return 1
  printf '%s\n' "$prepared_json"
}

validation_fee_submit_prepared_transaction_one_write_json() {
  local config="$1"
  local contract_json="$2"
  local prepared_dir="$3"
  local item="$4"
  local journal_prefix="$5"
  local operation_json state transaction terminal_json receipt torii_base
  local plan_sha256
  local response_path http_code submit_status=0 response_text

  transaction="$(jq -ce '.transaction' <<<"$item")" || return 1
  plan_sha256="$(validation_fee_bound_plan_sha256)" || return 1
  operation_json="$(jq -cn \
    --arg kind split_deploy_transaction \
    --arg plan_sha256 "$plan_sha256" \
    --arg contract_key "$(jq -er '.key' <<<"$contract_json")" \
    --arg contract_alias "$(jq -er '.alias' <<<"$contract_json")" \
    --arg label "$(jq -er '.label' <<<"$item")" \
    --arg payload_sha256 "$(jq -er '.payload_sha256' <<<"$item")" \
    --argjson transaction "$transaction" \
    '{
      kind: $kind,
      plan_sha256: $plan_sha256,
      contract_key: $contract_key,
      contract_alias: $contract_alias,
      label: $label,
      payload_sha256: $payload_sha256,
      transaction: $transaction
    }')"
  state="$(validation_fee_mutation_journal_state "$journal_prefix")" || return 1
  case "$state" in
    Applied)
      validation_fee_assert_mutation_journal \
        "$journal_prefix" "$operation_json" || return 1
      validation_fee_reverify_transaction_evidence_json \
        "$config" "$transaction" || return $?
      receipt="$(jq -ce '.receipt' "$journal_prefix.Applied.json")" || return 1
      jq -cn --argjson receipt "$receipt" \
        '{new_submission: false, receipt: $receipt}'
      return 0
      ;;
    submission)
      validation_fee_assert_mutation_journal \
        "$journal_prefix" "$operation_json" || return 1
      terminal_json="$(
        validation_fee_applied_transaction_json \
          "$config" "$(jq -er '.tx_hash_hex' <<<"$transaction")"
      )" || {
        echo "prepared validation-fee submission remains ambiguous; refusing retry: $journal_prefix" >&2
        return 1
      }
      receipt="$(jq -cn \
        --arg label "$(jq -er '.label' <<<"$item")" \
        --argjson transaction "$transaction" \
        --argjson terminal "$terminal_json" \
        '{label: $label, transaction: $transaction, terminal: $terminal}')"
      validation_fee_record_mutation_applied \
        "$journal_prefix" "$receipt" "$operation_json" || return 1
      jq -cn --argjson receipt "$receipt" \
        '{new_submission: false, recovered_submission: true, receipt: $receipt}'
      return 0
      ;;
    intent)
      validation_fee_assert_mutation_journal \
        "$journal_prefix" "$operation_json" || return 1
      echo "prepared validation-fee mutation has intent without a durable transaction submission; refusing retry: $journal_prefix" >&2
      return 1
      ;;
    absent)
      ;;
    *)
      return 1
      ;;
  esac

  soraswap_require_public_submit_health_ready_for_config \
    "$config" \
    "validation-fee split transaction $(jq -er '.label' <<<"$item")" \
    || return $?
  torii_base="$(torii_base_from_config "$config")" || return 1
  response_path="$(mktemp "${TMPDIR:-/tmp}/soraswap-validation-fee-submit.XXXXXX")" \
    || return 1
  {
    if http_code="$(
      SORASWAP_IMMEDIATE_CURL_GATE_FUNCTION=validation_fee_prepared_transaction_immediate_gate \
      SORASWAP_IMMEDIATE_CURL_GATE_LABEL="validation-fee split transaction $(jq -er '.label' <<<"$item")" \
      SORASWAP_VALIDATION_FEE_IMMINENT_OPERATION_JSON="$operation_json" \
      SORASWAP_VALIDATION_FEE_IMMINENT_JOURNAL_PREFIX="$journal_prefix" \
      SORASWAP_VALIDATION_FEE_IMMINENT_TRANSACTION_JSON="$transaction" \
        soraswap_curl_for_config "$config" \
          -sS \
          --max-time "${SORASWAP_VALIDATION_FEE_SUBMIT_MAX_TIME_SECS:-120}" \
          -o "$response_path" \
          -w '%{http_code}' \
          -X POST \
          -H 'Content-Type: application/x-norito' \
          -H 'Accept: application/json' \
          -H "X-Iroha-API-Version: $SORASWAP_TORII_API_VERSION" \
          --data-binary \
          "@$prepared_dir/transactions/$(jq -er '.file' <<<"$item")" \
          "${torii_base%/}/v1/pipeline/transactions"
    )"; then
      submit_status=0
    else
      submit_status=$?
    fi
    if (( submit_status != 0 )); then
      echo "validation-fee prepared transaction transport outcome is ambiguous; refusing retry" >&2
      return "$submit_status"
    fi
    if [[ "$http_code" != "200" && "$http_code" != "202" ]]; then
      response_text="$(soraswap_redact_sensitive_text <"$response_path")"
      echo "validation-fee prepared transaction was not accepted (HTTP $http_code): $response_text" >&2
      return 1
    fi
    terminal_json="$(
      validation_fee_applied_transaction_json \
        "$config" "$(jq -er '.tx_hash_hex' <<<"$transaction")"
    )" || return $?
    receipt="$(jq -cn \
      --arg label "$(jq -er '.label' <<<"$item")" \
      --argjson transaction "$transaction" \
      --argjson terminal "$terminal_json" \
      '{label: $label, transaction: $transaction, terminal: $terminal}')"
    validation_fee_record_mutation_applied \
      "$journal_prefix" "$receipt" "$operation_json" || return 1
    jq -cn --argjson receipt "$receipt" \
      '{new_submission: true, receipt: $receipt}'
  } always {
    rm -f "$response_path"
  }
}

validation_fee_write_immutable_json() {
  local payload="$1"
  local evidence_path="$2"
  local canonical

  canonical="$(jq -S . <<<"$payload")" || return 1
  printf '%s\n' "$canonical" \
    | validation_fee_isolated_python \
      "$SORASWAP_ROOT/scripts/publish_immutable_json.py" \
      --output "$evidence_path"
}

validation_fee_ensure_durable_directory() {
  local directory_path="$1"

  validation_fee_isolated_python \
    "$SORASWAP_ROOT/scripts/publish_immutable_json.py" \
    --directory "$directory_path" </dev/null >/dev/null
}

validation_fee_fsync_file() {
  validation_fee_isolated_python \
    "$SORASWAP_ROOT/scripts/publish_immutable_json.py" \
    --fsync-file "$1" </dev/null >/dev/null
}

validation_fee_fsync_directory() {
  validation_fee_isolated_python \
    "$SORASWAP_ROOT/scripts/publish_immutable_json.py" \
    --fsync-directory "$1" </dev/null >/dev/null
}
