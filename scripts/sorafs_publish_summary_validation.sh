#!/bin/zsh

# Closed-schema validators for the exact SoraFS summaries consumed by
# publish_trader_api_bundle.sh. Each function prints the validated object as
# compact JSON and rejects unknown fields, alternate spellings, and unbound
# artifact metadata.

soraswap_validate_sorafs_car_directory_summary() {
  local summary_path="$1"
  local expected_input_path="$2"
  local expected_output_car="$3"
  local expected_file_count="$4"
  local expected_car_size="$5"
  local expected_payload_bytes="$6"

  jq -ce \
    --arg expected_input_path "$expected_input_path" \
    --arg expected_output_car "$expected_output_car" \
    --arg expected_chunker_handle "sorafs.sf1@1.0.0" \
    --argjson expected_chunker_profile_id 1 \
    --argjson expected_file_count "$expected_file_count" \
    --argjson expected_car_size "$expected_car_size" \
    --argjson expected_payload_bytes "$expected_payload_bytes" '
      def unsigned_integer:
        type == "number" and floor == . and . >= 0;
      def positive_integer:
        unsigned_integer and . > 0;
      def lowercase_hash:
        type == "string" and test("^[0-9a-f]{64}$");
      def lowercase_even_hex:
        type == "string"
        and length > 0
        and (length % 2) == 0
        and test("^[0-9a-f]+$");
      select(
        type == "object"
        and keys == [
          "car_cid_hex",
          "car_digest_hex",
          "car_payload_digest_hex",
          "car_size",
          "chunk_count",
          "chunk_digest_sha3_256_hex",
          "chunker_handle",
          "chunker_profile_canonical",
          "chunker_profile_id",
          "file_count",
          "input_file_count",
          "input_kind",
          "input_path",
          "output_car",
          "payload_bytes",
          "por_root_hex",
          "root_cids_hex"
        ]
        and .chunker_handle == $expected_chunker_handle
        and .chunker_profile_canonical == $expected_chunker_handle
        and .chunker_profile_id == $expected_chunker_profile_id
        and .input_kind == "directory"
        and .input_path == $expected_input_path
        and .output_car == $expected_output_car
        and .file_count == $expected_file_count
        and .input_file_count == $expected_file_count
        and .payload_bytes == $expected_payload_bytes
        and (.payload_bytes | positive_integer)
        and (.chunk_count | positive_integer)
        and .car_size == $expected_car_size
        and (.car_size | positive_integer)
        and (.car_payload_digest_hex | lowercase_hash)
        and (.car_digest_hex | lowercase_hash)
        and (.chunk_digest_sha3_256_hex | lowercase_hash)
        and (.por_root_hex | lowercase_hash)
        and (.car_cid_hex | lowercase_even_hex)
        and (.root_cids_hex | type) == "array"
        and (.root_cids_hex | length) == 1
        and all(.root_cids_hex[]; lowercase_even_hex)
      )
    ' "$summary_path"
}

soraswap_validate_sorafs_manifest_build_summary() {
  local summary_path="$1"
  local expected_manifest_path="$2"
  local expected_manifest_json_path="$3"
  local car_summary_json="$4"

  jq -ce \
    --arg expected_manifest_path "$expected_manifest_path" \
    --arg expected_manifest_json_path "$expected_manifest_json_path" \
    --argjson car_summary "$car_summary_json" '
      def lowercase_hash:
        type == "string" and test("^[0-9a-f]{64}$");
      select(
        type == "object"
        and keys == [
          "chunker_handle",
          "chunker_profile_id",
          "manifest_digest_hex",
          "manifest_json_path",
          "manifest_path",
          "pin_policy"
        ]
        and .manifest_path == $expected_manifest_path
        and .manifest_json_path == $expected_manifest_json_path
        and .chunker_handle == $car_summary.chunker_handle
        and .chunker_profile_id == $car_summary.chunker_profile_id
        and (.manifest_digest_hex | lowercase_hash)
        and (.pin_policy | type) == "object"
        and (.pin_policy | keys) == ["min_replicas", "retention_epoch", "storage_class"]
        and .pin_policy.min_replicas == 1
        and .pin_policy.retention_epoch == 86400
        and .pin_policy.storage_class == "hot"
      )
    ' "$summary_path"
}

soraswap_validate_sorafs_storage_prepare_summary() {
  local summary_path="$1"
  local expected_manifest_path="$2"
  local expected_payload_path="$3"
  local expected_payload_out="$4"
  local expected_files_out="$5"
  local manifest_summary_json="$6"
  local car_summary_json="$7"
  local expected_payload_bytes="$8"

  jq -ce \
    --arg expected_manifest_path "$expected_manifest_path" \
    --arg expected_payload_path "$expected_payload_path" \
    --arg expected_payload_out "$expected_payload_out" \
    --arg expected_files_out "$expected_files_out" \
    --argjson manifest_summary "$manifest_summary_json" \
    --argjson car_summary "$car_summary_json" \
    --argjson expected_payload_bytes "$expected_payload_bytes" '
      def positive_integer:
        type == "number" and floor == . and . > 0;
      def lowercase_hash:
        type == "string" and test("^[0-9a-f]{64}$");
      def lowercase_even_hex:
        type == "string"
        and length > 0
        and (length % 2) == 0
        and test("^[0-9a-f]+$");
      select(
        type == "object"
        and keys == [
          "chunker_handle",
          "files_out",
          "manifest_digest_hex",
          "manifest_id_hex",
          "manifest_path",
          "payload_bytes",
          "payload_file_count",
          "payload_kind",
          "payload_out",
          "payload_path"
        ]
        and .manifest_path == $expected_manifest_path
        and .payload_path == $expected_payload_path
        and .payload_out == $expected_payload_out
        and .files_out == $expected_files_out
        and .payload_kind == "directory"
        and .chunker_handle == $manifest_summary.chunker_handle
        and .chunker_handle == $car_summary.chunker_handle
        and .manifest_digest_hex == $manifest_summary.manifest_digest_hex
        and (.manifest_digest_hex | lowercase_hash)
        and .manifest_id_hex == $car_summary.root_cids_hex[0]
        and (.manifest_id_hex | lowercase_even_hex)
        and .payload_bytes == $expected_payload_bytes
        and .payload_bytes == $car_summary.payload_bytes
        and (.payload_bytes | positive_integer)
        and .payload_file_count == $car_summary.file_count
        and (.payload_file_count | positive_integer)
      )
    ' "$summary_path"
}

soraswap_validate_sorafs_storage_directory_files() {
  local files_path="$1"
  local expected_relative_path="$2"
  local expected_file_size="$3"

  jq -ce \
    --arg expected_relative_path "$expected_relative_path" \
    --argjson expected_file_size "$expected_file_size" '
      select(
        type == "array"
        and length == 1
        and (.[0] | type) == "object"
        and (.[0] | keys) == ["path", "size"]
        and .[0].path == [$expected_relative_path]
        and .[0].size == $expected_file_size
        and (.[0].size | type) == "number"
        and (.[0].size | floor) == .[0].size
        and .[0].size > 0
      )
    ' "$files_path"
}
