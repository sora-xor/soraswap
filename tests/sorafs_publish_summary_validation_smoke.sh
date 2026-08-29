#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/scripts/sorafs_publish_summary_validation.sh"

fail() {
  echo "SoraFS publish summary validation smoke failed: $*" >&2
  exit 1
}

expect_rejection() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label was accepted"
  fi
}

payload_path="/tmp/soraswap-sorafs-validation/payload"
car_path="/tmp/soraswap-sorafs-validation/app-api.car"
manifest_path="/tmp/soraswap-sorafs-validation/app-api.manifest.to"
manifest_json_path="/tmp/soraswap-sorafs-validation/app-api.manifest.json"
payload_out="/tmp/soraswap-sorafs-validation/provider.payload.bin"
files_out="/tmp/soraswap-sorafs-validation/provider.files.json"

car_json="$(jq -cn \
  --arg input_path "$payload_path" \
  --arg output_car "$car_path" '
  {
    car_cid_hex: "0171abcd",
    car_digest_hex: ("ab" * 32),
    car_payload_digest_hex: ("bc" * 32),
    car_size: 512,
    chunk_count: 1,
    chunk_digest_sha3_256_hex: ("cd" * 32),
    chunker_handle: "sorafs.sf1@1.0.0",
    chunker_profile_canonical: "sorafs.sf1@1.0.0",
    chunker_profile_id: 1,
    file_count: 1,
    input_file_count: 1,
    input_kind: "directory",
    input_path: $input_path,
    output_car: $output_car,
    payload_bytes: 128,
    por_root_hex: ("de" * 32),
    root_cids_hex: ["0171beef"]
  }
')"

soraswap_validate_sorafs_car_directory_summary \
  <(printf '%s' "$car_json") "$payload_path" "$car_path" 1 512 128 >/dev/null \
  || fail "valid current car directory summary was rejected"
expect_rejection "car summary unknown field" \
  soraswap_validate_sorafs_car_directory_summary \
  <(jq -c '.legacy = true' <<<"$car_json") "$payload_path" "$car_path" 1 512 128
expect_rejection "car summary uppercase digest" \
  soraswap_validate_sorafs_car_directory_summary \
  <(jq -c '.car_digest_hex |= ascii_upcase' <<<"$car_json") "$payload_path" "$car_path" 1 512 128
expect_rejection "car summary unbound output path" \
  soraswap_validate_sorafs_car_directory_summary \
  <(jq -c '.output_car = "/tmp/other.car"' <<<"$car_json") "$payload_path" "$car_path" 1 512 128
expect_rejection "car summary unbound file count" \
  soraswap_validate_sorafs_car_directory_summary \
  <(jq -c '.file_count = 2' <<<"$car_json") "$payload_path" "$car_path" 1 512 128
expect_rejection "car summary unbound payload size" \
  soraswap_validate_sorafs_car_directory_summary \
  <(jq -c '.payload_bytes = 127' <<<"$car_json") "$payload_path" "$car_path" 1 512 128

manifest_json="$(jq -cn \
  --arg manifest_path "$manifest_path" \
  --arg manifest_json_path "$manifest_json_path" '
  {
    chunker_handle: "sorafs.sf1@1.0.0",
    chunker_profile_id: 1,
    manifest_digest_hex: ("ef" * 32),
    manifest_json_path: $manifest_json_path,
    manifest_path: $manifest_path,
    pin_policy: {
      min_replicas: 1,
      retention_epoch: 86400,
      storage_class: "hot"
    }
  }
')"

soraswap_validate_sorafs_manifest_build_summary \
  <(printf '%s' "$manifest_json") "$manifest_path" "$manifest_json_path" "$car_json" >/dev/null \
  || fail "valid current manifest build summary was rejected"
expect_rejection "manifest summary unknown field" \
  soraswap_validate_sorafs_manifest_build_summary \
  <(jq -c '.metadata_kv = []' <<<"$manifest_json") "$manifest_path" "$manifest_json_path" "$car_json"
expect_rejection "manifest summary uppercase digest" \
  soraswap_validate_sorafs_manifest_build_summary \
  <(jq -c '.manifest_digest_hex |= ascii_upcase' <<<"$manifest_json") "$manifest_path" "$manifest_json_path" "$car_json"
expect_rejection "manifest summary alternate pin policy" \
  soraswap_validate_sorafs_manifest_build_summary \
  <(jq -c '.pin_policy.storage_class = "warm"' <<<"$manifest_json") "$manifest_path" "$manifest_json_path" "$car_json"

storage_json="$(jq -cn \
  --arg manifest_path "$manifest_path" \
  --arg payload_path "$payload_path" \
  --arg payload_out "$payload_out" \
  --arg files_out "$files_out" '
  {
    chunker_handle: "sorafs.sf1@1.0.0",
    files_out: $files_out,
    manifest_digest_hex: ("ef" * 32),
    manifest_id_hex: "0171beef",
    manifest_path: $manifest_path,
    payload_bytes: 128,
    payload_file_count: 1,
    payload_kind: "directory",
    payload_out: $payload_out,
    payload_path: $payload_path
  }
')"

soraswap_validate_sorafs_storage_prepare_summary \
  <(printf '%s' "$storage_json") \
  "$manifest_path" "$payload_path" "$payload_out" "$files_out" \
  "$manifest_json" "$car_json" 128 >/dev/null \
  || fail "valid current storage prepare summary was rejected"
expect_rejection "storage summary unknown field" \
  soraswap_validate_sorafs_storage_prepare_summary \
  <(jq -c '.legacy = true' <<<"$storage_json") \
  "$manifest_path" "$payload_path" "$payload_out" "$files_out" \
  "$manifest_json" "$car_json" 128
expect_rejection "storage summary unbound manifest id" \
  soraswap_validate_sorafs_storage_prepare_summary \
  <(jq -c '.manifest_id_hex = "0171cafe"' <<<"$storage_json") \
  "$manifest_path" "$payload_path" "$payload_out" "$files_out" \
  "$manifest_json" "$car_json" 128
expect_rejection "storage summary unbound payload size" \
  soraswap_validate_sorafs_storage_prepare_summary \
  <(jq -c '.payload_bytes = 127' <<<"$storage_json") \
  "$manifest_path" "$payload_path" "$payload_out" "$files_out" \
  "$manifest_json" "$car_json" 128
expect_rejection "storage summary alternate payload kind" \
  soraswap_validate_sorafs_storage_prepare_summary \
  <(jq -c '.payload_kind = "file"' <<<"$storage_json") \
  "$manifest_path" "$payload_path" "$payload_out" "$files_out" \
  "$manifest_json" "$car_json" 128

files_json='[{"path":["app-api.json"],"size":42}]'
soraswap_validate_sorafs_storage_directory_files \
  <(printf '%s' "$files_json") app-api.json 42 >/dev/null \
  || fail "valid current storage file index was rejected"
expect_rejection "storage file index unknown field" \
  soraswap_validate_sorafs_storage_directory_files \
  <(jq -c '.[0].legacy = true' <<<"$files_json") app-api.json 42
expect_rejection "storage file index unbound path" \
  soraswap_validate_sorafs_storage_directory_files \
  <(jq -c '.[0].path = ["legacy.json"]' <<<"$files_json") app-api.json 42

echo "SoraFS publish summary validation smoke passed"
