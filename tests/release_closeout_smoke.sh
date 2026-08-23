#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-release-closeout.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

source "$ROOT/scripts/release_phase_guards.sh"

fail() {
  echo "release closeout smoke failed: $*" >&2
  exit 1
}

expect_failure() {
  local expected="$1"
  local output="$2"
  shift 2
  local command_status=0

  "$@" >"$output" 2>&1 || command_status="$?"
  [[ "$command_status" != "0" ]] || fail "expected command failure containing: $expected"
  rg -Fq "$expected" "$output" || {
    cat "$output" >&2
    fail "missing expected failure: $expected"
  }
}

configure_ssh_signing() {
  local repository="$1"
  local identity_dir="$2"
  local email="$3"

  mkdir -p "$identity_dir"
  ssh-keygen -q -t ed25519 -N '' -f "$identity_dir/signing_key"
  printf '%s %s\n' "$email" "$(<"$identity_dir/signing_key.pub")" \
    > "$identity_dir/allowed_signers"
  git -C "$repository" config gpg.format ssh
  git -C "$repository" config user.signingkey "$identity_dir/signing_key"
  git -C "$repository" config gpg.ssh.allowedSignersFile "$identity_dir/allowed_signers"
}

make_source_fixture() {
  local destination="$1"

  mkdir -p \
    "$destination/docs/release" \
    "$destination/scripts" \
    "$destination/deployments/testnet"
  cat > "$destination/.gitignore" <<'EOF'
/tmp*
/deployments/
EOF
  printf '%s\n' '# audit' > "$destination/docs/release/smart_contract_production_audit.md"
  printf '%s\n' '# readiness' > "$destination/docs/release/production_readiness_checklist.md"
  printf '%s\n' '# devex' > "$destination/docs/release/taira_devex_critique.md"
  printf '%s\n' 'release source' > "$destination/source.txt"
  cat > "$destination/scripts/source.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
EOF
  chmod +x "$destination/scripts/source.sh"
  git -C "$destination" init -q
  git -C "$destination" config user.name "SoraSwap Closeout Test"
  git -C "$destination" config user.email "closeout-test@example.invalid"
  configure_ssh_signing "$destination" "$destination.signing" "closeout-test@example.invalid"
  git -C "$destination" add .
  git -C "$destination" commit -S -q -m "closeout source fixture"
  git -C "$destination" verify-commit HEAD >/dev/null
}

copy_source_fixture() {
  local destination="$1"
  cp -R "$source_base" "$destination"
}

source_base="$TMP_DIR/source-base"
make_source_fixture "$source_base"

printf '%s\n' 'fresh evidence note' >> "$source_base/docs/release/production_readiness_checklist.md"
git -C "$source_base" add docs/release/production_readiness_checklist.md
release_closeout_source_state_json "$source_base" testnet | jq -e '
  (.git_head | type == "string" and length == 40)
  and .tracked_status_doc_count == 3
  and (.tracked_non_status_doc_count >= 3)
' >/dev/null

status_split_root="$TMP_DIR/status-split"
copy_source_fixture "$status_split_root"
printf '%s\n' 'staged status bytes' >> "$status_split_root/docs/release/production_readiness_checklist.md"
git -C "$status_split_root" add docs/release/production_readiness_checklist.md
printf '%s\n' 'different worktree bytes' >> "$status_split_root/docs/release/production_readiness_checklist.md"
expect_failure \
  "tracked status doc index bytes differ from the validated worktree file" \
  "$TMP_DIR/status-split.out" \
  release_closeout_source_state_json "$status_split_root" testnet

staged_delete_root="$TMP_DIR/staged-delete"
copy_source_fixture "$staged_delete_root"
git -C "$staged_delete_root" rm -q source.txt
expect_failure \
  "Git index deletes tracked source: source.txt" \
  "$TMP_DIR/staged-delete.out" \
  release_closeout_source_state_json "$staged_delete_root" testnet

staged_mode_root="$TMP_DIR/staged-mode"
copy_source_fixture "$staged_mode_root"
chmod +x "$staged_mode_root/source.txt"
git -C "$staged_mode_root" add source.txt
expect_failure \
  "Git index changes tracked source mode or type: source.txt" \
  "$TMP_DIR/staged-mode.out" \
  release_closeout_source_state_json "$staged_mode_root" testnet

untracked_root="$TMP_DIR/untracked"
copy_source_fixture "$untracked_root"
printf '%s\n' 'unbound source' > "$untracked_root/scripts/untracked.sh"
expect_failure \
  "non-ignored untracked source is present: scripts/untracked.sh" \
  "$TMP_DIR/untracked.out" \
  release_closeout_source_state_json "$untracked_root" testnet

status_symlink_root="$TMP_DIR/status-symlink"
copy_source_fixture "$status_symlink_root"
mv "$status_symlink_root/docs/release/production_readiness_checklist.md" \
  "$TMP_DIR/production_readiness_checklist.target"
ln -s "$TMP_DIR/production_readiness_checklist.target" \
  "$status_symlink_root/docs/release/production_readiness_checklist.md"
expect_failure \
  "tracked status doc must remain a regular file: docs/release/production_readiness_checklist.md" \
  "$TMP_DIR/status-symlink.out" \
  release_closeout_source_state_json "$status_symlink_root" testnet

status_mode_root="$TMP_DIR/status-mode"
copy_source_fixture "$status_mode_root"
chmod +x "$status_mode_root/docs/release/production_readiness_checklist.md"
git -C "$status_mode_root" add docs/release/production_readiness_checklist.md
expect_failure \
  "Git index changes tracked source mode or type: docs/release/production_readiness_checklist.md" \
  "$TMP_DIR/status-mode.out" \
  release_closeout_source_state_json "$status_mode_root" testnet

status_hardlink_root="$TMP_DIR/status-hardlink"
copy_source_fixture "$status_hardlink_root"
ln "$status_hardlink_root/docs/release/production_readiness_checklist.md" \
  "$TMP_DIR/status-doc-hardlink"
expect_failure \
  "tracked status doc must remain a regular file: docs/release/production_readiness_checklist.md" \
  "$TMP_DIR/status-hardlink.out" \
  release_closeout_source_state_json "$status_hardlink_root" testnet
rm "$TMP_DIR/status-doc-hardlink"

staged_whitespace_root="$TMP_DIR/staged-whitespace"
copy_source_fixture "$staged_whitespace_root"
printf '%s\n' 'staged trailing whitespace   ' >> \
  "$staged_whitespace_root/docs/release/production_readiness_checklist.md"
git -C "$staged_whitespace_root" add docs/release/production_readiness_checklist.md
expect_failure \
  "trailing whitespace" \
  "$TMP_DIR/staged-whitespace.out" \
  git -C "$staged_whitespace_root" diff HEAD --check

freshness_root="$TMP_DIR/freshness-root"
mkdir -p "$freshness_root/deployments/testnet"
freshness_artifact="$freshness_root/deployments/testnet/preflight.latest.json"
freshness_now="$(date -u '+%Y%m%dT%H%M%SZ')"
printf '{"generated_at":"%s","status":"ready"}\n' "$freshness_now" > "$freshness_artifact"
freshness_snapshot="$(release_phase_artifact_snapshot_json "$freshness_root" "$freshness_artifact")"
expect_failure \
  "phase reused the prior artifact file identity" \
  "$TMP_DIR/freshness-stale.out" \
  release_phase_require_regenerated_artifacts "$freshness_root" "$freshness_snapshot" "$freshness_artifact"
freshness_snapshot="$(release_phase_artifact_snapshot_json "$freshness_root" "$freshness_artifact")"
freshness_now="$(date -u -v+1S '+%Y%m%dT%H%M%SZ')"
printf '{"generated_at":"%s","status":"regenerated"}\n' "$freshness_now" > "${freshness_artifact}.tmp"
mv "${freshness_artifact}.tmp" "$freshness_artifact"
release_phase_require_regenerated_artifacts "$freshness_root" "$freshness_snapshot" "$freshness_artifact"

typeset -a taira_targets
taira_targets=("${(@f)$(release_closeout_expected_phase_targets testnet)}")
journal_root="$TMP_DIR/journal-root"
make_source_fixture "$journal_root"
journal="$journal_root/tmp/release-closeout/testnet.phase-journal.json"
mkdir -p "$journal_root/deployments/testnet"
export SORASWAP_RELEASE_EXPECTED_GIT_SHA="$(git -C "$journal_root" rev-parse HEAD)"
journal_fingerprint='{"torii_url":"https://taira.example.invalid","chain":"fixture-chain","block_1_hash":"fixture-block-1"}'
jq -n --argjson fingerprint "$journal_fingerprint" \
  '{generated_at:"20260711T000001Z",chain:{fingerprint:$fingerprint}}' \
  > "$journal_root/deployments/testnet/preflight.latest.json"
jq -n --argjson fingerprint "$journal_fingerprint" \
  '$fingerprint + {generated_at:"20260711T000002Z"}' \
  > "$journal_root/deployments/testnet/chain.latest.json"
jq -n --argjson fingerprint "$journal_fingerprint" \
  '{generated_at:"20260711T000003Z",chain_fingerprint:$fingerprint}' \
  > "$journal_root/deployments/testnet/nested_call_probe.latest.json"
jq -n --argjson fingerprint "$journal_fingerprint" \
  '{generated_at:"20260711T000004Z",chain_fingerprint:$fingerprint}' \
  > "$journal_root/deployments/testnet/rwa_compliance.latest.json"
jq -n --argjson fingerprint "$journal_fingerprint" \
  '{generated_at:"20260711T000005Z",chain_fingerprint:$fingerprint}' \
  > "$journal_root/deployments/testnet/deploy.latest.json"
jq -n --argjson fingerprint "$journal_fingerprint" \
  '{generated_at:"20260711T000006Z",chain_fingerprint:$fingerprint}' \
  > "$journal_root/deployments/testnet/contracts.latest.json"
for artifact in smoke contract_console_smoke trader_readonly trader trader_api_bundle; do
  jq -n --argjson fingerprint "$journal_fingerprint" --arg artifact "$artifact" '
    {
      generated_at:("20260711T0001" + $artifact),
      chain_fingerprint:$fingerprint,
      deploy_snapshot:{generated_at:"20260711T000005Z",chain_fingerprint:$fingerprint},
      contracts_snapshot:{generated_at:"20260711T000006Z",chain_fingerprint:$fingerprint}
    }
  ' > "$journal_root/deployments/testnet/${artifact}.latest.json"
done

journal_token="$(release_phase_journal_state create "$journal_root" testnet "$journal" "${taira_targets[@]}")"
[[ "$journal_token" =~ '^[0-9a-f]{64}$' ]] || fail "journal token is not hexadecimal"
[[ "$(stat -f '%Lp' "$journal")" == "600" ]] || fail "journal mode is not 0600"
expect_failure \
  "already exists: tmp/release-closeout/testnet.phase-journal.json" \
  "$TMP_DIR/journal-duplicate.out" \
  release_phase_journal_state create "$journal_root" testnet "$journal" "${taira_targets[@]}"
expect_failure \
  "phase index is not the next ordered phase" \
  "$TMP_DIR/journal-order.out" \
  release_phase_journal_state record "$journal_root" testnet "$journal" 2 \
    "${taira_targets[2]}" "$journal_root/deployments/testnet/chain.latest.json"

release_phase_journal_state record "$journal_root" testnet "$journal" 1 "${taira_targets[1]}" \
  "$journal_root/deployments/testnet/preflight.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 2 "${taira_targets[2]}" \
  "$journal_root/deployments/testnet/chain.latest.json" \
  "$journal_root/deployments/testnet/nested_call_probe.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 3 "${taira_targets[3]}" \
  "$journal_root/deployments/testnet/preflight.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 4 "${taira_targets[4]}" \
  "$journal_root/deployments/testnet/rwa_compliance.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 5 "${taira_targets[5]}" \
  "$journal_root/deployments/testnet/deploy.latest.json" \
  "$journal_root/deployments/testnet/contracts.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 6 "${taira_targets[6]}" \
  "$journal_root/deployments/testnet/smoke.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 7 "${taira_targets[7]}" \
  "$journal_root/deployments/testnet/smoke.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 8 "${taira_targets[8]}" \
  "$journal_root/deployments/testnet/contract_console_smoke.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 9 "${taira_targets[9]}" \
  "$journal_root/deployments/testnet/trader_readonly.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 10 "${taira_targets[10]}" \
  "$journal_root/deployments/testnet/trader.latest.json"
release_phase_journal_state record "$journal_root" testnet "$journal" 11 "${taira_targets[11]}" \
  "$journal_root/deployments/testnet/trader_api_bundle.latest.json"
[[ "$(release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}")" == "$journal_token" ]]

first_receipt_rel="$(jq -r '.phases[0].evidence[0].path' "$journal")"
first_receipt="$journal_root/$first_receipt_rel"
cp "$first_receipt" "$TMP_DIR/receipt.clean"
python3 - "$first_receipt" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text())
value["generated_at"] = "20990101T000000Z"
path.write_text(json.dumps(value) + "\n")
PY
chmod 0600 "$first_receipt"
expect_failure \
  "evidence receipt no longer matches its recorded hash and timestamp" \
  "$TMP_DIR/journal-receipt-tamper.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
cp "$TMP_DIR/receipt.clean" "$first_receipt"
chmod 0600 "$first_receipt"
[[ "$(release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}")" == "$journal_token" ]]

chmod 0644 "$first_receipt"
expect_failure \
  "must have mode 0600" \
  "$TMP_DIR/journal-receipt-mode.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
chmod 0600 "$first_receipt"
rm "$first_receipt"
ln -s "$TMP_DIR/receipt.clean" "$first_receipt"
expect_failure \
  "must be a regular non-symlink file" \
  "$TMP_DIR/journal-receipt-symlink.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
rm "$first_receipt"
cp "$TMP_DIR/receipt.clean" "$first_receipt"
chmod 0600 "$first_receipt"
ln "$first_receipt" "$TMP_DIR/receipt-hardlink"
expect_failure \
  "must have exactly one hard link" \
  "$TMP_DIR/journal-receipt-hardlink.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
rm "$TMP_DIR/receipt-hardlink"

rewrite_journal_path() {
  local selected_journal="$1"
  local replacement="$2"
  local phase_index="${3:-0}"
  local artifact_index="${4:-0}"

  python3 - "$selected_journal" "$replacement" "$phase_index" "$artifact_index" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text())
value["phases"][int(sys.argv[3])]["evidence"][int(sys.argv[4])]["path"] = sys.argv[2]
value.pop("journal_sha256", None)
value["journal_sha256"] = hashlib.sha256(
    json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
).hexdigest()
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
PY
  chmod 0600 "$selected_journal"
}

cp "$journal" "$TMP_DIR/journal.valid"
rewrite_journal_path "$journal" \
  'tmp/release-closeout/testnet.phase-receipts/../outside.json'
expect_failure \
  "evidence receipt path is unsafe, duplicate, or does not match its phase index" \
  "$TMP_DIR/journal-receipt-parent.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
cp "$TMP_DIR/journal.valid" "$journal"
chmod 0600 "$journal"
duplicate_receipt_path="$(jq -r '.phases[0].evidence[0].path' "$journal")"
rewrite_journal_path "$journal" "$duplicate_receipt_path" 1 0
expect_failure \
  "evidence receipt path is unsafe, duplicate, or does not match its phase index" \
  "$TMP_DIR/journal-receipt-duplicate.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
cp "$TMP_DIR/journal.valid" "$journal"
chmod 0600 "$journal"

chmod 0644 "$journal"
expect_failure \
  "must have mode 0600" \
  "$TMP_DIR/journal-mode.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
chmod 0600 "$journal"

cp "$journal" "$TMP_DIR/journal.clean"
rm "$journal"
ln -s "$TMP_DIR/journal.clean" "$journal"
expect_failure \
  "must be a regular non-symlink file" \
  "$TMP_DIR/journal-symlink.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
rm "$journal"
cp "$TMP_DIR/journal.clean" "$journal"
chmod 0600 "$journal"

ln "$journal" "$TMP_DIR/journal-hardlink"
expect_failure \
  "must have exactly one hard link" \
  "$TMP_DIR/journal-hardlink.out" \
  release_phase_journal_state verify "$journal_root" testnet "$journal" "${taira_targets[@]}"
rm "$TMP_DIR/journal-hardlink"

write_checkpoint() {
  local root="$1"
  local environment="$2"
  local token="$3"
  local checkpoint="$root/tmp/release-closeout/$environment.pending.json"

  mkdir -p "${checkpoint:h}"
  "${commands[python3]:-python3}" - "$checkpoint" "$environment" "$token" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = {
    "schema": "soraswap-release-closeout/v2",
    "status": "pending_status_docs",
    "environment": sys.argv[2],
    "created_at": "2026-07-11T00:00:00Z",
    "resume_token": sys.argv[3],
}
value["checkpoint_sha256"] = hashlib.sha256(
    json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
).hexdigest()
path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
os.chmod(path, 0o600)
PY
}

checkpoint_root="$TMP_DIR/checkpoint-root"
mkdir -p "$checkpoint_root"
checkpoint_token="$(printf '%064d' 7)"
write_checkpoint "$checkpoint_root" testnet "$checkpoint_token"
checkpoint="$checkpoint_root/tmp/release-closeout/testnet.pending.json"
[[ "$(release_closeout_checkpoint_resume_token "$checkpoint_root" testnet "$checkpoint")" == "$checkpoint_token" ]]
chmod 0644 "$checkpoint"
expect_failure \
  "must have mode 0600 and exactly one hard link" \
  "$TMP_DIR/checkpoint-mode.out" \
  release_closeout_checkpoint_resume_token "$checkpoint_root" testnet "$checkpoint"
chmod 0600 "$checkpoint"
cp "$checkpoint" "$TMP_DIR/checkpoint.clean"
rm "$checkpoint"
ln -s "$TMP_DIR/checkpoint.clean" "$checkpoint"
expect_failure \
  "must be a regular non-symlink file" \
  "$TMP_DIR/checkpoint-symlink.out" \
  release_closeout_checkpoint_resume_token "$checkpoint_root" testnet "$checkpoint"
rm "$checkpoint"
cp "$TMP_DIR/checkpoint.clean" "$checkpoint"
chmod 0600 "$checkpoint"
ln "$checkpoint" "$TMP_DIR/checkpoint-hardlink"
expect_failure \
  "must have mode 0600 and exactly one hard link" \
  "$TMP_DIR/checkpoint-hardlink.out" \
  release_closeout_checkpoint_resume_token "$checkpoint_root" testnet "$checkpoint"
rm "$TMP_DIR/checkpoint-hardlink"
expect_failure \
  "checkpoint resume capability does not match" \
  "$TMP_DIR/checkpoint-remove-token.out" \
  release_closeout_checkpoint_remove "$checkpoint_root" testnet "$checkpoint" "$(printf '%064d' 8)"
[[ -f "$checkpoint" ]]
release_closeout_checkpoint_remove "$checkpoint_root" testnet "$checkpoint" "$checkpoint_token"
[[ ! -e "$checkpoint" ]]

refresh_pin_bundle_integrity() {
  local bundle="$1"
  local archive="${bundle}.tar.gz"

  python3 - "$bundle" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
paths = []
for path in root.rglob("*"):
    metadata = path.lstat()
    if stat.S_ISREG(metadata.st_mode) and path.name != "sha256sums.txt":
        paths.append(path.relative_to(root).as_posix())
with (root / "sha256sums.txt").open("w", encoding="utf-8") as output:
    for relative in sorted(paths):
        output.write(f"{hashlib.sha256((root / relative).read_bytes()).hexdigest()}  {relative}\n")
PY
  rm -f "$archive" "${archive}.sha256"
  COPYFILE_DISABLE=1 tar -C "${bundle:h}" -czf "$archive" "${bundle:t}"
  printf '%s  %s\n' "$(shasum -a 256 "$archive" | awk '{print $1}')" "${archive:t}" \
    > "${archive}.sha256"
}

make_pin_fixture() {
  local fixture_root="$1"
  local iroha_root="$fixture_root/iroha"
  local bundle_parent="$fixture_root/bundles"
  local bundle_name

  mkdir -p \
    "$iroha_root/crates/iroha_kagami/src" \
    "$iroha_root/crates/iroha_swarm/src" \
    "$iroha_root/crates/iroha_test_samples/src"
  printf '/target/\n' > "$iroha_root/.gitignore"
  printf '[workspace]\nmembers = []\n' > "$iroha_root/Cargo.toml"
  printf '# fixture lock\n' > "$iroha_root/Cargo.lock"
  printf '// kagami\n' > "$iroha_root/crates/iroha_kagami/src/lib.rs"
  printf '// swarm\n' > "$iroha_root/crates/iroha_swarm/src/lib.rs"
  printf '// samples\n' > "$iroha_root/crates/iroha_test_samples/src/lib.rs"
  git -C "$iroha_root" init -q
  git -C "$iroha_root" config user.name "Iroha Pin Fixture"
  git -C "$iroha_root" config user.email "iroha-pin@example.invalid"
  configure_ssh_signing "$iroha_root" "$fixture_root/signing" "iroha-pin@example.invalid"
  git -C "$iroha_root" add .
  git -C "$iroha_root" commit -S -q -m "signed Iroha pin fixture"
  resume_pin_sha="$(git -C "$iroha_root" rev-parse HEAD)"
  git -C "$iroha_root" verify-commit "$resume_pin_sha" >/dev/null
  mkdir -p "$iroha_root/target/release"
  printf '#!/bin/sh\n# kagami fixture\nexit 0\n' > "$iroha_root/target/release/kagami"
  chmod +x "$iroha_root/target/release/kagami"

  bundle_name="taira-rollout-${resume_pin_sha[1,12]}-release"
  resume_pin_bundle="$bundle_parent/$bundle_name"
  resume_pin_root="$iroha_root"
  mkdir -p "$resume_pin_bundle/bin"
  for binary in irohad iroha; do
    printf '#!/bin/sh\n# Iroha Git SHA: %s\nexit 0\n' "$resume_pin_sha" \
      > "$resume_pin_bundle/bin/$binary"
    chmod +x "$resume_pin_bundle/bin/$binary"
  done
  jq -n --arg git_head "$resume_pin_sha" --arg bundle_name "$bundle_name" '{
    git_head:$git_head,
    git_signature_verified:true,
    git_tree_clean:true,
    git_status_lines:[],
    cargo_profile:"release",
    bundle_name:$bundle_name,
    irohad_features:["embedded-soracloud-runtime","sccp-test-fixtures"],
    binaries:["bin/irohad","bin/iroha"],
    prebundle_checks:[
      {name:"soraswap_smart_contract_deploy_router_regression",skipped:false},
      {name:"soraswap_three_hop_nested_transfer_canary",skipped:false}
    ]
  }' > "$resume_pin_bundle/rollout.manifest.json"
  refresh_pin_bundle_integrity "$resume_pin_bundle"
}

copy_pin_bundle() {
  local destination_parent="$1"
  local destination="$destination_parent/${resume_pin_bundle:t}"

  mkdir -p "$destination_parent"
  cp -R "$resume_pin_bundle" "$destination"
  cp "${resume_pin_bundle}.tar.gz" "${destination}.tar.gz"
  cp "${resume_pin_bundle}.tar.gz.sha256" "${destination}.tar.gz.sha256"
  printf '%s\n' "$destination"
}

make_pin_fixture "$TMP_DIR/resume-pin"
release_local_acceptance_pin_state_json \
  "$resume_pin_root" "$resume_pin_bundle" "$resume_pin_sha" >/dev/null

pin_unlisted_bundle="$(copy_pin_bundle "$TMP_DIR/pin-unlisted")"
printf 'unlisted\n' > "$pin_unlisted_bundle/unlisted.bin"
expect_failure \
  "bundle checksum manifest does not exactly cover every regular bundle file" \
  "$TMP_DIR/pin-unlisted.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_unlisted_bundle" "$resume_pin_sha"

pin_unsigned_manifest_bundle="$(copy_pin_bundle "$TMP_DIR/pin-unsigned-manifest")"
jq '.git_signature_verified = false' "$pin_unsigned_manifest_bundle/rollout.manifest.json" \
  > "$pin_unsigned_manifest_bundle/rollout.manifest.json.tmp"
mv "$pin_unsigned_manifest_bundle/rollout.manifest.json.tmp" "$pin_unsigned_manifest_bundle/rollout.manifest.json"
refresh_pin_bundle_integrity "$pin_unsigned_manifest_bundle"
expect_failure \
  "rollout manifest does not prove the signed clean release candidate" \
  "$TMP_DIR/pin-unsigned-manifest.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_unsigned_manifest_bundle" "$resume_pin_sha"

pin_features_bundle="$(copy_pin_bundle "$TMP_DIR/pin-features")"
jq '.irohad_features = ["embedded-soracloud-runtime"]' "$pin_features_bundle/rollout.manifest.json" \
  > "$pin_features_bundle/rollout.manifest.json.tmp"
mv "$pin_features_bundle/rollout.manifest.json.tmp" "$pin_features_bundle/rollout.manifest.json"
refresh_pin_bundle_integrity "$pin_features_bundle"
expect_failure \
  "exact features" \
  "$TMP_DIR/pin-features.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_features_bundle" "$resume_pin_sha"

pin_binary_bundle="$(copy_pin_bundle "$TMP_DIR/pin-binary")"
printf '#!/bin/sh\nexit 0\n' > "$pin_binary_bundle/bin/iroha"
chmod +x "$pin_binary_bundle/bin/iroha"
refresh_pin_bundle_integrity "$pin_binary_bundle"
expect_failure \
  "bundle bin/iroha does not embed the expected Iroha Git SHA" \
  "$TMP_DIR/pin-binary.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_binary_bundle" "$resume_pin_sha"

pin_archive_bundle="$(copy_pin_bundle "$TMP_DIR/pin-archive")"
printf 'tamper' >> "${pin_archive_bundle}.tar.gz"
expect_failure \
  "archive checksum sidecar is not canonical or does not match" \
  "$TMP_DIR/pin-archive.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_archive_bundle" "$resume_pin_sha"

pin_sidecar_bundle="$(copy_pin_bundle "$TMP_DIR/pin-sidecar")"
printf '%064d  wrong.tar.gz\n' 0 > "${pin_sidecar_bundle}.tar.gz.sha256"
expect_failure \
  "archive checksum sidecar is not canonical or does not match" \
  "$TMP_DIR/pin-sidecar.out" \
  release_local_acceptance_pin_state_json "$resume_pin_root" "$pin_sidecar_bundle" "$resume_pin_sha"

unsigned_candidate="$TMP_DIR/unsigned-candidate"
cp -R "$resume_pin_root" "$unsigned_candidate"
printf 'unsigned followup\n' > "$unsigned_candidate/unsigned.txt"
git -C "$unsigned_candidate" add unsigned.txt
git -C "$unsigned_candidate" -c commit.gpgsign=false commit -qm "unsigned candidate"
unsigned_sha="$(git -C "$unsigned_candidate" rev-parse HEAD)"
expect_failure \
  "Iroha candidate commit signature is not verifiable" \
  "$TMP_DIR/pin-unsigned-commit.out" \
  release_local_acceptance_pin_state_json "$unsigned_candidate" "$resume_pin_bundle" "$unsigned_sha"

make_resume_root() {
  local destination="$1"

  mkdir -p "$destination/scripts" "$destination/docs/release" "$destination/tmp/release-closeout"
  printf '/tmp*\n/deployments/\n/config/production/production.client.toml\n/config/production/cutover-approval.json\n' > "$destination/.gitignore"
  printf '# audit\n' > "$destination/docs/release/smart_contract_production_audit.md"
  printf '# readiness\n' > "$destination/docs/release/production_readiness_checklist.md"
  printf '# devex\n' > "$destination/docs/release/taira_devex_critique.md"
  cat > "$destination/scripts/common.sh" <<'EOF'
#!/bin/zsh
soraswap_require_binary_integer_setting() {
  [[ "$2" == "0" || "$2" == "1" ]] || {
    echo "$1 must be 0 or 1; got '$2'" >&2
    return 1
  }
}
soraswap_rwa_release_enabled_setting_for_env() { echo 0; }
soraswap_display_path() { print -r -- "${1:t}"; }
soraswap_require_contract_source_hygiene() { return 0; }
soraswap_require_secure_production_client_config() { return 0; }
soraswap_client_config_has_placeholder_values() { return 1; }
config_chain_id_from_config() { echo production-chain; }
production_client_config_taira_chain_blocker_message() { return 1; }
soraswap_value_looks_placeholder() { return 1; }
soraswap_required_oracle_public_key_hex() { echo "ed0120bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; }
authority_from_config() { echo "i105-production-signer"; }
soraswap_production_min_fee_balance() { echo "${SORASWAP_PRODUCTION_MIN_FEE_BALANCE:-10}"; }
soraswap_print_preflight_report_reasons() { return 0; }
EOF
  ln -s "$ROOT/scripts/release_phase_guards.sh" "$destination/scripts/release_phase_guards.sh"
}

finalize_resume_root() {
  local destination="$1"
  local email="$2"

  git -C "$destination" init -q
  git -C "$destination" config user.name "SoraSwap Resume Fixture"
  git -C "$destination" config user.email "$email"
  configure_ssh_signing "$destination" "$destination.signing" "$email"
  git -C "$destination" add .gitignore docs scripts
  if [[ -f "$destination/config/production/cutover-trust-policy.json" ]]; then
    git -C "$destination" add config/production/cutover-trust-policy.json
  fi
  git -C "$destination" commit -S -q -m "signed resume fixture"
  git -C "$destination" verify-commit HEAD >/dev/null
  git -C "$destination" rev-parse HEAD
}

fake_bin="$TMP_DIR/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/make" <<'EOF'
#!/bin/sh
case " $* " in
  *" release-checklist "*)
    if [ -n "${CLOSEOUT_TAIRA_PREREQ_LOG:-}" ]; then
      echo "taira-prerequisite-revalidated" >> "$CLOSEOUT_TAIRA_PREREQ_LOG"
    fi
    exit 0
    ;;
esac
echo "$*" >> "$CLOSEOUT_FAKE_MAKE_LOG"
exit 97
EOF
chmod +x "$fake_bin/make"

taira_resume_root="$TMP_DIR/taira-resume-root"
make_resume_root "$taira_resume_root"
cat > "$taira_resume_root/scripts/release_checklist.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
[[ "$1" == "--resume-status-doc-closeout" ]]
[[ "$2" == "$RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN" ]]
echo "$*" >> "$CLOSEOUT_CHECKLIST_LOG"
rm -f "$SORASWAP_ROOT/tmp/release-closeout/testnet.pending.json"
EOF
chmod +x "$taira_resume_root/scripts/release_checklist.sh"
taira_resume_rc_sha="$(finalize_resume_root "$taira_resume_root" "taira-resume@example.invalid")"
write_checkpoint "$taira_resume_root" testnet "$checkpoint_token"
taira_make_log="$TMP_DIR/taira-resume.make.log"
taira_checklist_log="$TMP_DIR/taira-resume.checklist.log"
: > "$taira_make_log"
: > "$taira_checklist_log"
taira_resume_output="$TMP_DIR/taira-resume.out"
(
  export PATH="$fake_bin:$PATH"
  export CLOSEOUT_FAKE_MAKE_LOG="$taira_make_log"
  export CLOSEOUT_CHECKLIST_LOG="$taira_checklist_log"
  export SORASWAP_ROOT="$taira_resume_root"
  export SORASWAP_RELEASE_RESUME_CLOSEOUT=1
  export SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT="$resume_pin_root"
  export SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR="$resume_pin_bundle"
  export SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA="$resume_pin_sha"
  export SORASWAP_RELEASE_EXPECTED_GIT_SHA="$taira_resume_rc_sha"
  zsh "$ROOT/scripts/release_taira.sh"
) > "$taira_resume_output" 2>&1
rg -Fq "completed all 12 release phases and strict status-doc closeout" "$taira_resume_output"
[[ -s "$taira_checklist_log" ]]
[[ ! -s "$taira_make_log" ]] || fail "Taira closeout resume redispatched Make phases"
[[ ! -e "$taira_resume_root/tmp/release-closeout/testnet.pending.json" ]]

write_checkpoint "$taira_resume_root" testnet "$checkpoint_token"
missing_pin_output="$TMP_DIR/taira-resume-missing-pin.out"
expect_failure \
  "full Taira release prepare/resume requires all three exact-candidate local acceptance pin settings" \
  "$missing_pin_output" \
  env PATH="$fake_bin:$PATH" \
    CLOSEOUT_FAKE_MAKE_LOG="$taira_make_log" \
    CLOSEOUT_CHECKLIST_LOG="$taira_checklist_log" \
    SORASWAP_ROOT="$taira_resume_root" \
    SORASWAP_RELEASE_RESUME_CLOSEOUT=1 \
    SORASWAP_RELEASE_EXPECTED_GIT_SHA="$taira_resume_rc_sha" \
    zsh "$ROOT/scripts/release_taira.sh"

production_resume_root="$TMP_DIR/production-resume-root"
make_resume_root "$production_resume_root"
mkdir -p "$production_resume_root/config/production" "$production_resume_root/deployments/production"
cat > "$production_resume_root/config/production/production.client.toml" <<'EOF'
chain = "production-chain"
torii_url = "https://torii.production.example"
EOF
chmod 600 "$production_resume_root/config/production/production.client.toml"
printf '{}\n' > "$production_resume_root/config/production/cutover-trust-policy.json"
printf '{}\n' > "$production_resume_root/config/production/cutover-approval.json"
chmod 600 "$production_resume_root/config/production/cutover-approval.json"
printf '{}\n' > "$production_resume_root/deployments/production/chain.latest.json"
printf '{}\n' > "$production_resume_root/deployments/production/cutover_approval.latest.json"
chmod 600 "$production_resume_root/deployments/production/cutover_approval.latest.json"
cat > "$production_resume_root/scripts/verify_production_cutover_approval.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- '{"schema":"soraswap-production-cutover-approval-state/v1","fixture":"release-closeout-resume"}'
EOF
chmod +x "$production_resume_root/scripts/verify_production_cutover_approval.sh"
cat > "$production_resume_root/scripts/release_production_checklist.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
[[ "$1" == "--resume-status-doc-closeout" ]]
[[ "$2" == "$RELEASE_CHECKLIST_INTERNAL_CLOSEOUT_TOKEN" ]]
echo "$*" >> "$CLOSEOUT_CHECKLIST_LOG"
rm -f "$SORASWAP_ROOT/tmp/release-closeout/production.pending.json"
EOF
chmod +x "$production_resume_root/scripts/release_production_checklist.sh"
production_resume_rc_sha="$(finalize_resume_root "$production_resume_root" "production-resume@example.invalid")"
production_resume_canonical_root="$(cd "$production_resume_root" && pwd)"
write_checkpoint "$production_resume_root" production "$checkpoint_token"
production_make_log="$TMP_DIR/production-resume.make.log"
production_checklist_log="$TMP_DIR/production-resume.checklist.log"
production_taira_log="$TMP_DIR/production-resume.taira.log"
: > "$production_make_log"
: > "$production_checklist_log"
: > "$production_taira_log"
production_resume_output="$TMP_DIR/production-resume.out"
if ! (
  export PATH="$fake_bin:$PATH"
  export CLOSEOUT_FAKE_MAKE_LOG="$production_make_log"
  export CLOSEOUT_CHECKLIST_LOG="$production_checklist_log"
  export CLOSEOUT_TAIRA_PREREQ_LOG="$production_taira_log"
  export SORASWAP_ROOT="$production_resume_canonical_root"
  export SORASWAP_RELEASE_RESUME_CLOSEOUT=1
  export SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT="$resume_pin_root"
  export SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR="$resume_pin_bundle"
  export SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA="$resume_pin_sha"
  export SORASWAP_RELEASE_EXPECTED_GIT_SHA="$production_resume_rc_sha"
  export SORASWAP_PRODUCTION_MIN_FEE_BALANCE=10
  export SORASWAP_PRODUCTION_ADMIN_AUTHORITY="i105-production-admin"
  export SORASWAP_PRODUCTION_TREASURY_AUTHORITY="i105-production-treasury"
  export SORASWAP_PRODUCTION_BRIDGE_AUTHORITY="i105-production-bridge"
  zsh "$ROOT/scripts/release_production.sh"
) > "$production_resume_output" 2>&1; then
  sed -n '1,240p' "$production_resume_output" >&2
  fail "production closeout resume fixture failed"
fi
rg -Fq "completed all 12 release phases and strict status-doc closeout" "$production_resume_output"
rg -Fxq "taira-prerequisite-revalidated" "$production_taira_log"
[[ ! -s "$production_make_log" ]] || fail "production closeout resume redispatched Make phases"
[[ ! -e "$production_resume_root/tmp/release-closeout/production.pending.json" ]]

rg -Fq 'git -C "$ROOT" diff HEAD --check' "$ROOT/scripts/release_checklist.sh"
rg -Fq 'git -C "$ROOT" diff --cached --check' "$ROOT/scripts/release_checklist.sh"
rg -Fq 'git -C "$ROOT" diff --check' "$ROOT/scripts/release_checklist.sh"
[[ "$(rg -c 'verify_local_acceptance_pin_unchanged ".*immediately before.*checkpoint' "$ROOT/scripts/release_checklist.sh")" -ge 3 ]]
rg -Fq 'release_phase_artifact_snapshot_json "$ROOT"' "$ROOT/scripts/release_taira.sh" "$ROOT/scripts/release_production.sh"
rg -Fq 'release_phase_require_regenerated_artifacts "$ROOT"' "$ROOT/scripts/release_taira.sh" "$ROOT/scripts/release_production.sh"
rg -Fq 'release_soraswap_rc_state_json "$ROOT"' "$ROOT/scripts/release_taira.sh" "$ROOT/scripts/release_production.sh"
rg -Fq 'phase_journal_token="$(release_phase_journal_state create' "$ROOT/scripts/release_taira.sh"
rg -Fq 'phase_journal_token="$(release_phase_journal_state create' "$ROOT/scripts/release_production.sh"
rg -Fq 'require_taira_release_gate_for_production' "$ROOT/scripts/release_checklist.sh"
awk '
  resume == 0 && /if \[\[ "\$closeout_mode" == "resume" \]\]/ { resume = NR }
  /^require_taira_release_gate_for_production$/ { if (NR > resume) verified = NR }
  END { exit !(resume > 0 && verified > resume) }
' "$ROOT/scripts/release_checklist.sh"
rg -Fq 'os.link(temporary, checkpoint)' "$ROOT/scripts/release_checklist.sh"
rg -Fq 'except FileExistsError:' "$ROOT/scripts/release_checklist.sh"
rg -Fq 'if file_hash(path) != prior_file_hash:' "$ROOT/scripts/release_phase_guards.sh"
rg -Fq '"rwa_release_enabled": rwa_release_enabled == "1"' "$ROOT/scripts/release_checklist.sh"

echo "release closeout smoke ok"
