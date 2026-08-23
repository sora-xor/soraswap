#!/bin/zsh
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SORASWAP_ROOT:-$(cd "$SCRIPT_ROOT/.." && pwd)}"

source "$SCRIPT_ROOT/common.sh"

mode="rewrite"
if (( $# > 1 )); then
  echo "usage: ${0:t} [--check]" >&2
  exit 2
fi
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
elif [[ -n "${1:-}" ]]; then
  echo "usage: ${0:t} [--check]" >&2
  exit 2
fi

typeset -a evidence_roots
evidence_roots=("$ROOT/deployments" "$ROOT/artifacts/telemetry")

checked=0
updated=0
failed=0
reported_pending=0
max_pending_reports=20
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-redact-generated.XXXXXX")"
raw_normalized_path="$tmp_dir/raw-normalized.json"
redacted_normalized_path="$tmp_dir/redacted-normalized.json"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

write_json_file_from_path_atomic() {
  local json_path="$1"
  local output_path="$2"
  local tmp_path

  tmp_path="$(mktemp "${output_path}.XXXXXX")" || return 1
  if ! cp "$json_path" "$tmp_path"; then
    rm -f "$tmp_path"
    return 1
  fi
  if ! jq -e . "$tmp_path" >/dev/null 2>&1; then
    rm -f "$tmp_path"
    echo "refusing to publish invalid JSON artifact: $(soraswap_display_path "$output_path")" >&2
    return 1
  fi
  if ! mv "$tmp_path" "$output_path"; then
    rm -f "$tmp_path"
    return 1
  fi
}

for evidence_root in "${evidence_roots[@]}"; do
  [[ -d "$evidence_root" ]] || continue

  while IFS= read -r -d '' evidence_path; do
    [[ -n "$evidence_path" ]] || continue
    rel_path="${evidence_path#$ROOT/}"
    checked=$(( checked + 1 ))

    if ! jq -e . "$evidence_path" >/dev/null 2>&1; then
      failed=1
      echo "generated evidence redaction failed: $rel_path is not valid JSON" >&2
      continue
    fi

    redacted_path="$tmp_dir/redacted.json"
    if ! soraswap_redact_sensitive_text < "$evidence_path" > "$redacted_path"; then
      failed=1
      echo "generated evidence redaction failed: $rel_path could not be redacted" >&2
      continue
    fi
    if ! jq -e . "$redacted_path" >/dev/null 2>&1; then
      failed=1
      echo "generated evidence redaction failed: $rel_path redaction did not produce valid JSON" >&2
      continue
    fi

    if ! jq -cS . "$evidence_path" > "$raw_normalized_path" \
      || ! jq -cS . "$redacted_path" > "$redacted_normalized_path"; then
      failed=1
      echo "generated evidence redaction failed: $rel_path redaction comparison could not be computed" >&2
      continue
    fi

    if cmp -s "$raw_normalized_path" "$redacted_normalized_path"; then
      continue
    fi

    if [[ "$mode" == "check" ]]; then
      failed=1
      updated=$(( updated + 1 ))
      if (( reported_pending < max_pending_reports )); then
        echo "generated evidence redaction check failed: $rel_path would change under shared redactor; run make redact-generated-evidence" >&2
      elif (( reported_pending == max_pending_reports )); then
        echo "generated evidence redaction check failed: additional generated artifacts would change under shared redactor" >&2
      fi
      reported_pending=$(( reported_pending + 1 ))
      continue
    fi

    write_json_file_from_path_atomic "$redacted_path" "$evidence_path" || {
      failed=1
      echo "generated evidence redaction failed: $rel_path could not be rewritten" >&2
      continue
    }
    updated=$(( updated + 1 ))
  done < <(find "$evidence_root" -type f -name '*.json' -print0 | LC_ALL=C sort -z)
done

if (( failed != 0 )); then
  exit 1
fi

if [[ "$mode" == "check" ]]; then
  echo "generated evidence redaction check: inspected $checked JSON artifacts; pending $updated"
else
  echo "generated evidence redaction: inspected $checked JSON artifacts; updated $updated"
fi
