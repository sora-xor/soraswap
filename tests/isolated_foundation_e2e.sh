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
  local file source

  mkdir -p "$report_dir"
  for file in \
    chain.latest.json \
    deploy.latest.json \
    contracts.latest.json \
    smoke.latest.json \
    soraswap.bundle.deploy.json; do
    source="$report_dir/$file"
    if [[ -f "$source" ]]; then
      copy_file_atomic "$source" "$snapshot_dir/$file"
    fi
  done

  for source in "$report_dir"/*.deploy.json(N) "$report_dir"/*.manifest.json(N); do
    if [[ "${source:t}" == "soraswap.foundation.bundle.deploy.json" ]]; then
      continue
    fi
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

  source="$snapshot_dir/foundation-deploy/soraswap.bundle.deploy.json"
  if [[ ! -f "$source" ]]; then
    source="$report_dir/soraswap.bundle.deploy.json"
  fi
  destination="$report_dir/soraswap.foundation.bundle.deploy.json"
  if [[ -f "$source" ]]; then
    copy_file_atomic "$source" "$destination"
  fi
}

restore_retained_latest() {
  local file source destination

  for file in \
    chain.latest.json \
    deploy.latest.json \
    contracts.latest.json \
    smoke.latest.json \
    soraswap.bundle.deploy.json; do
    source="$snapshot_dir/$file"
    destination="$report_dir/$file"
    if [[ -f "$source" ]]; then
      copy_file_atomic "$source" "$destination"
    else
      rm -f "$destination"
    fi
  done

  for destination in "$report_dir"/*.deploy.json(N); do
    if [[ "${destination:t}" != "soraswap.bundle.deploy.json" \
      && "${destination:t}" != "soraswap.foundation.bundle.deploy.json" ]]; then
      rm -f "$destination"
    fi
  done
  rm -f "$report_dir"/*.manifest.json(N)

  for source in "$snapshot_dir"/*.deploy.json(N) "$snapshot_dir"/*.manifest.json(N); do
    if [[ "${source:t}" != "soraswap.bundle.deploy.json" \
      && "${source:t}" != "soraswap.foundation.bundle.deploy.json" ]]; then
      copy_file_atomic "$source" "$report_dir/${source:t}"
    fi
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
export SORASWAP_ISOLATED_DEPLOY_ARTIFACT_SNAPSHOT_DIR="$snapshot_dir/foundation-deploy"

zsh "$ROOT/tests/isolated_e2e.sh"
