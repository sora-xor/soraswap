#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
report_dir="$ROOT/deployments/local"
snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-foundation-latest.XXXXXX")"

copy_file_atomic() {
  local source="$1"
  local destination="$2"
  local tmp

  mkdir -p "${destination:h}"
  tmp="$(mktemp "${destination}.XXXXXX")" || return 1
  if ! cp -p "$source" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$destination"; then
    rm -f "$tmp"
    return 1
  fi
}

snapshot_retained_latest() {
  local file source contract_key

  mkdir -p "$report_dir"
  for file in \
    chain.latest.json \
    deploy.latest.json \
    contracts.latest.json \
    smoke.latest.json; do
    source="$report_dir/$file"
    if [[ -f "$source" ]]; then
      copy_file_atomic "$source" "$snapshot_dir/$file"
    fi
  done

  for source in "$report_dir"/*.deploy.json(N); do
    contract_key="$(jq -r '.contract_key // empty' "$source" 2>/dev/null || true)"
    [[ -n "$contract_key" && "${source:t}" == "${contract_key}.deploy.json" ]] || continue
    copy_file_atomic "$source" "$snapshot_dir/${source:t}"
  done
  for source in "$report_dir"/*.manifest.json(N); do
    copy_file_atomic "$source" "$snapshot_dir/${source:t}"
  done
}

publish_foundation_latest() {
  local file source destination

  for file in chain deploy contracts smoke; do
    source="$report_dir/${file}.latest.json"
    destination="$report_dir/${file}.foundation.latest.json"
    if [[ -f "$source" ]]; then
      copy_file_atomic "$source" "$destination"
    fi
  done
}

restore_retained_latest() {
  local file source destination

  for file in \
    chain.latest.json \
    deploy.latest.json \
    contracts.latest.json \
    smoke.latest.json; do
    source="$snapshot_dir/$file"
    destination="$report_dir/$file"
    if [[ -f "$source" ]]; then
      copy_file_atomic "$source" "$destination"
    else
      rm -f "$destination"
    fi
  done

  rm -f "$report_dir"/*.deploy.json(N)
  rm -f "$report_dir"/*.manifest.json(N)

  for source in "$snapshot_dir"/*.deploy.json(N) "$snapshot_dir"/*.manifest.json(N); do
    copy_file_atomic "$source" "$report_dir/${source:t}"
  done
}

cleanup() {
  local exit_status=$?

  if [[ -d "$snapshot_dir" ]]; then
    if (( exit_status == 0 )); then
      publish_foundation_latest || exit_status=$?
    fi
    restore_retained_latest || exit_status=$?
    rm -rf "$snapshot_dir"
  fi

  exit "$exit_status"
}

snapshot_retained_latest
trap cleanup EXIT

export SORASWAP_BOOTSTRAP_SCOPE="${SORASWAP_BOOTSTRAP_SCOPE:-foundation}"
export SORASWAP_DEPLOY_SCOPE="${SORASWAP_DEPLOY_SCOPE:-foundation}"
export SORASWAP_SMOKE_SCOPE="${SORASWAP_SMOKE_SCOPE:-foundation}"

zsh "$ROOT/tests/isolated_e2e.sh"
