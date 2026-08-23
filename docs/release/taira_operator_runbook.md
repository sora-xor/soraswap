# Taira Operator Rollout Runbook

This runbook is the SoraSwap-facing checklist for public Taira node rollout. It does not replace `../iroha/configs/soranexus/taira/README.md`; it records the runtime inputs that must be present before SoraSwap can make a release claim.

## Scope
- Use `../iroha` as the canonical runtime source.
- Keep validator keys, onboarding/faucet authorities, canary signers, and production client configs out of this repository.
- Capture resolved config and health evidence in the rollout ticket before running `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira`.
- Treat `https://taira.sora.org` as a convenience endpoint only after at least one direct validator root has passed the checks below.

## Mandatory Runtime Inputs
- Build and stage a fresh sibling runtime bundle with `bash ../iroha/configs/soranexus/taira/build_taira_rollout_bundle.sh`.
- Render per-validator configs from `../iroha/configs/soranexus/taira/config.toml`, the active roster, and untracked validator secrets.
- Preserve `[network].max_frame_bytes_tx_gossip = 1048576`; SoraSwap bundle deploys depend on that frame budget.
- Preserve `[torii.mcp]` with `enabled = true`, `profile = "writer"`, `expose_operator_routes = false`, and `allow_tool_prefixes = ["iroha."]`.
- Preserve `[nexus.fees].fee_asset_id = "xor#universal"` and `[pipeline.gas].accepted_assets = ["6TEAJqbb8oEPmLncoNiMRbLEK6tw"]`.
- Preserve `[sumeragi.npos].use_stake_snapshot_roster = true`; active validators come from public-lane staking state, not only from bootstrap peer files.
- Preserve explicit non-universal `manifest_hash` values for the `governance`, `zk`, and `is` dataspace catalog entries.
- Keep `[zk].sccp_allow_unready_transparent_proofs` explicit. Public Taira should use the checked-in value `false`; any temporary testnet-only deviation must be recorded in the rollout ticket before bridge evidence is trusted.
- Use a runtime-only canary/write signer config such as `/run/secrets/taira-canary-client.toml` for rollout scripts. Start from `../iroha/configs/soranexus/taira/taira-canary-client.example.toml`, never from a generic zero-chain client config.

## Restart Evidence
After each validator restart, capture:

```bash
sudo journalctl -u taira-irohad.service -n 200 --no-pager
cd /opt/iroha
/usr/local/bin/irohad --sora \
  --config "${IROHA_TAIRA_CONFIG:-configs/soranexus/taira/config.toml}" \
  --genesis-manifest-json "${IROHA_TAIRA_GENESIS:-configs/soranexus/taira/genesis.json}" \
  --trace-config | tee /tmp/taira-trace-config.txt
```

The trace config must show the MCP block, `nexus.fees.fee_asset_id = "xor#universal"`, the canonical gas asset id, explicit dataspace manifest hashes, and `sumeragi.npos.use_stake_snapshot_roster = true`.

## Direct Node Verification
Run the sibling rollout checks against the direct node root before using shared public ingress:

```bash
export PUBLIC_TORII_ROOT=https://taira-validator-1.sora.org
bash ../iroha/configs/soranexus/taira/check_mcp_rollout.sh \
  --public-root "$PUBLIC_TORII_ROOT" \
  --write-config /run/secrets/taira-canary-client.toml
bash ../iroha/configs/soranexus/taira/check_sorafs_rollout.sh \
  --public-root "$PUBLIC_TORII_ROOT" \
  --write-config /run/secrets/taira-canary-client.toml
```

Required signals:
- `/v1/mcp` is HTTP `200` and `tools/list` advertises only compatible `iroha.*` schemas.
- HTTP `502` or `503` from `/v1/mcp`, `/status`, faucet, SoraFS, or rollout-check reads is public ingress/upstream health. Stop signed SoraSwap release work there and fix the edge/upstream path before debugging signer material or contract payloads.
- `/status` publishes a commit-QC snapshot with at least four validators in the commit-QC set.
- SCCP, ZK, validator-set, public-lane validator/stake, bridge-message, contract deploy, and contract state routes are reachable on the same direct node.
- The signed canary lands with the configured gas asset metadata; do not pass `--gas-asset-id ""` on public Taira.
- A SoraSwap `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe` run must get past `/v1/contracts/deploy` admission and its later `confirm_deploy_*` visibility checks. Repeated `queue_unresolved_route` / `PRTRY:ROUTE_UNRESOLVED` responses while public reads are reachable mean public transaction routing is not release-ready even if `/v1/mcp` and basic status probes are reachable. A `confirm_deploy_*` stage that submits a transaction but never exposes pipeline status or committed-transaction visibility is still a public transaction-visibility/finality blocker. If Sumeragi reports queue count/depth saturation, age-based saturation, or a view-change cause such as `quorum_timeout`, record that nuance separately and continue treating the release as blocked on public write-route/admission/finality health until the scratch deploy probe clears.
- If this failure appears on a universal contract alias such as SoraSwap's scratch probe, include the `../iroha` router fix that makes universal `smartcontract::deploy` policy matches build a Native AMX plan. `configs/soranexus/taira/verify_soraswap_rollout.sh` now runs both focused local SoraSwap regressions before the public probes: `cargo test -p iroha_core queue::router::tests::smart_contract_deploy_rule --lib` and `cargo test -p iroha_core contract_call_transaction_preserves_three_hop_transfer_authorities --lib`. Use `--skip-local-regressions` only for diagnostics against an already-validated runtime bundle.
- Because the SoraSwap nested-call probe deploys scratch contracts on public Taira, the rollout verifier requires `--allow-testnet-mutations` before it runs that probe or any optional SoraSwap deploy/smoke phase.

## Edge TCP Exhaustion Check
When public endpoints return HTTP `502`/`503`, check for host-local TCP source-port exhaustion and restart bind failures before retrying SoraSwap release phases. On the edge host, capture only aggregate counts and redact hostnames/IPs before copying diagnostics into tickets:

```bash
sysctl -n net.inet.tcp.pcbcount
sysctl -n net.inet.ip.portrange.hifirst net.inet.ip.portrange.hilast
sysctl -n net.inet.tcp.msl
netstat -an -p tcp | awk '
  NR > 2 {
    state=$NF
    if (state == "" || state ~ /^[0-9.*:]+$/) state="UNKNOWN"
    states[state]++
    if ($4 ~ /[.:]2908[0-3]$/ || $5 ~ /[.:]2908[0-3]$/) torii[state]++
  }
  END {
    for (s in states) printf "tcp_state[%s]=%d\n", s, states[s]
    for (s in torii) printf "torii_tcp_state[%s]=%d\n", s, torii[s]
  }'
pgrep -fl 'irohad|iroha3d' || echo "no Iroha peer process is running"
for p in 29080 29081 29082 29083; do
  nc -z -w 2 127.0.0.1 "$p" || echo "loopback Torii port $p is not connectable"
done
```

Treat very high `tcp_pcbcount` / `TIME_WAIT` counts, `EADDRNOTAVAIL` or `Can't assign requested address` in nginx/upstream diagnostics, or failing loopback Torii probes while the Torii ports still show `LISTEN` as edge TCP exhaustion. Do not rerun `deploy-testnet`, signed smoke, contract-console, signed trader, or trader API publication from that state; first drain/restart the affected edge/upstream processes according to the Taira operator policy, then verify loopback Torii probes and public `/status`, `/v1/sumeragi/status`, `/v1/mcp`, and faucet puzzle all return release-ready HTTP `200`/JSON health before refreshing SoraSwap evidence.

If the public-lane start exits with `Address already in use (os error 48)` for peer `network.address` or Torii ports after stale pidfiles were cleared and no live `irohad`/`iroha3d` process owns the listener, treat that as a runtime listener-rebind defect under heavy `TIME_WAIT`, not as a SoraSwap deployment problem. Roll out the `../iroha` reusable TCP listener fix for p2p and Torii (`SO_REUSEADDR` without `SO_REUSEPORT`, so active listeners are still rejected), then start the public lane and repeat the loopback/public health checks before any SoraSwap evidence refresh.

## Snapshot And Repair Policy
- Do not treat `trusted_peers` as the active validator set; use `/status`, `/v1/sumeragi/validator-sets`, and `/v1/nexus/public_lanes/0/{validators,stake}`.
- Before any state repair, record the donor peer, target peers, block height, parent root, post root, configured snapshot signer/verification policy, and snapshot sidecar paths.
- Do not copy a snapshot directory across validators unless the target node's snapshot verification policy and sidecars are compatible with the donor state.
- Clear only transient consensus queues during repair. Preserve chain state, validator keys, and configured snapshot signer material unless the runtime operator explicitly approves a fresh reset.
- Run the volatile-state quarantine helper as the peer process owner or with sudo. A dry-run warning that peers cannot be signalled is not apply-ready; the helper must refuse `--apply` before pidfile or storage changes in that state.
- After repair, re-run the direct node verification above before any SoraSwap public mutation.

Before touching validator storage, create a plan-only evidence record:

```bash
make taira-state-repair-plan \
  SORASWAP_TAIRA_REPAIR_DONOR_STORAGE=/var/lib/iroha/taira-validator-1 \
  SORASWAP_TAIRA_REPAIR_TARGET_STORAGES=/var/lib/iroha/taira-validator-2:/var/lib/iroha/taira-validator-3 \
  SORASWAP_TAIRA_REPAIR_REASON="height 621 state-root split" \
  SORASWAP_TAIRA_REPAIR_HEIGHT=621 \
  SORASWAP_TAIRA_REPAIR_PARENT_ROOT=<parent_root> \
  SORASWAP_TAIRA_REPAIR_POST_ROOT=<post_root> \
  SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY=<policy_summary> \
  SORASWAP_TAIRA_REPAIR_PLATFORM=darwin \
  SORASWAP_TAIRA_REPAIR_VOLATILE_DIST=/Users/administrator/dev/iroha/dist/taira-localnet \
  SORASWAP_TAIRA_REPAIR_VOLATILE_RUNTIME_BIN=/Users/administrator/dev/iroha-build-taira-latest/target/release/irohad \
  SORASWAP_TAIRA_REPAIR_VOLATILE_EXPECTED_RUNTIME_SHA=<64-hex-sha256> \
  SORASWAP_TAIRA_REPAIR_VOLATILE_TORII_PORTS=29080,29081,29082,29083
```

For a volatile-consensus-only stall where no persistent state copy is intended, omit `SORASWAP_TAIRA_REPAIR_DONOR_STORAGE` and `SORASWAP_TAIRA_REPAIR_TARGET_STORAGES` and provide only the `SORASWAP_TAIRA_REPAIR_VOLATILE_*` inputs plus optional incident notes. The volatile dist must be the rendered validator dist root that contains `start.sh`, `peer*.toml`, and `storage/peer*`; a rollout binary bundle with `bin/irohad` and `rollout.manifest.json` is not enough for the clear-volatile dry-run. The report records `repair_mode: "volatile_consensus_quarantine"`, `donor: null`, empty `targets`, and action templates limited to stop, dry-run/apply quarantine, and restart; it does not include rsync or donor-copy actions.

The helper writes `deployments/testnet/taira_state_repair_plan.latest.json` plus a timestamped copy. In state-repair mode it inventories donor/target storage, snapshot files, and transient queue/RBC candidates. In volatile-only mode it records the verified dist/runtime/Torii-port inputs and the no-copy manual checks. Both modes use repo-relative or basename-only path labels, redact secret-like and local-path text from free-form operator inputs and setup-failure diagnostics, and record required manual checks. When volatile-quarantine inputs are supplied, the helper verifies the runtime SHA and validates the Torii port list before writing the plan, then records the exact dry-run/apply command shape without performing either action. It intentionally performs no mutation; actual backup, copy, queue cleanup, volatile-state quarantine, and peer restart remain explicit operator actions until the runtime storage layout and process owner are approved for an apply-capable tool.

Use environment variables, not CLI flags, for sensitive incident notes or operator tokens because command-line arguments may appear in local process listings while the helper runs.

The repair-plan helper fails before writing evidence when the selected mode is ambiguous: state-repair mode requires donor and target directories, targets must be unique after path normalization, and volatile-only mode requires the volatile dist/runtime/SHA inputs instead of donor/target storage. `SORASWAP_TAIRA_REPAIR_HEIGHT` must be a nonnegative integer, parent/post roots must be 64 hex characters with an optional `0x` prefix, and `SORASWAP_TAIRA_REPAIR_PLATFORM` must be `darwin`, `linux`, or `manual`. The current Taira host is Darwin, so Linux/systemd action templates must be requested explicitly rather than inferred. If `SORASWAP_TAIRA_REPAIR_TRACE_CONFIG` or `SORASWAP_TAIRA_REPAIR_STATUS_JSON` is supplied, the path must exist and be readable; the status file must also parse as JSON. If any volatile-quarantine input is supplied, the dist, executable `start.sh`, executable runtime, matching expected runtime SHA, and unique numeric comma-separated Torii ports are all required before evidence is written.

## SoraSwap Handoff
Once the direct node rollout is green:

```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight
bash ../iroha/configs/soranexus/taira/verify_soraswap_rollout.sh \
  --public-root "$PUBLIC_TORII_ROOT" \
  --write-config /run/secrets/taira-canary-client.toml \
  --soraswap-client-config "$SORASWAP_CLIENT_CONFIG" \
  --allow-testnet-mutations
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira
```

The runner's twelfth phase prepares a fail-closed status-doc closeout. Both steps require all three exact-candidate pin settings and `SORASWAP_RELEASE_EXPECTED_GIT_SHA` for the signed SoraSwap RC. Before phase 1 the runner verifies both signed commits, the clean RC source, exhaustive bundle checksums, exact features and embedded binary SHAs, and the matching sibling archive/sidecar. It then creates ignored mode-`0600` `tmp/release-closeout/testnet.phase-journal.json`. Each of phases 1–11 snapshots its fixed artifact paths before dispatch and must replace file identity, bytes, hash, and `generated_at` with phase-fresh evidence; the nested-call probe is forced. Numbered mode-`0600` receipts must all share one chain fingerprint and the phase-5 deploy/contracts snapshot. Phase 12 rejects incomplete, stale, reordered, duplicate, escaping, symlinked, hard-linked, wrong-mode, or mixed-snapshot state; read-back verifies the atomic mode-`0600` checkpoint before consuming receipts. The checkpoint binds the signed RC/tree, HEAD source, candidate/archive hashes, target/local evidence and timestamps, RWA mode, and receipts. Stage only the validated status-doc bytes without changing identity/type/mode, preserve all pins, and run:

```bash
SORASWAP_RELEASE_RESUME_CLOSEOUT=1 make release-taira
```

Resume performs no signed Taira mutation and does not rerun local E2E. It rejects any changed checkpoint, HEAD, source/index state, evidence, chain, RWA mode, or candidate, then runs the strict checklist, shell/static gate, generated-evidence redaction check mode, `git diff --cached --check`, `git diff --check`, and `git diff HEAD --check`. Only success removes the pending checkpoint and completes phase 12. Commit the verified staged status-doc update only after that success. A journal retained after an interrupted or failed full run blocks both environments until the exact failed-run state is deliberately inspected and removed. Journals and checkpoints protect against accidental reuse, partial writes, and drift under the same operator account; they are not a security boundary against that same user deliberately rewriting the repository and recomputing integrity hashes.

For an explicit RWA market launch, opt in before the release and provide concrete external references:

```bash
export SORASWAP_ENABLE_RWA_RELEASE=1
export SORASWAP_RWA_ISSUER_APPROVAL_REF=<external approval id or URL>
export SORASWAP_RWA_LEGAL_REVIEW_REF=<external legal review id or URL>
export SORASWAP_RWA_COMPLIANCE_POLICY_REF=<external compliance policy id or URL>
export SORASWAP_RWA_NAV_SOURCE_REF=<external NAV source id or URL>
export SORASWAP_RWA_REDEMPTION_TERMS_REF=<external redemption terms id or URL>
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira
```

`SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` must report native MCP HTTP `200`, JSON-readable `/status` and `/v1/sumeragi/status` with `endpoint.health_issues: []`, current-chain fingerprint availability, signer readiness, account asset-listing availability, and no blockers or warnings. When sibling `../iroha` Taira DNS metadata is present, blocked preflight also retains diagnostic-only `endpoint.direct_validator_health` samples for `taira-validator-*` hostnames using the runbook `curl -k --resolve` path; `tls_verified: false` there is a direct-SNI certificate coverage warning, not release-ready evidence. Before `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira` exports its mutation environment or starts `[1/12]`, it rejects non-Kotodama files under `contracts/` except `contracts/shared/README.md`. With default public `SORASWAP_ENABLE_RWA_RELEASE=0`, RWA evidence is recorded as `not_applicable` and no real-world asset market is launched. When `SORASWAP_ENABLE_RWA_RELEASE=1`, it validates the five `SORASWAP_RWA_*_REF` values for missing, placeholder, local/wildcard endpoint, reserved-domain, and control-character content before phase 1. If setup stops before the first phase, the runner prints the retained `deployments/testnet/preflight.latest.json` status, timestamp, blockers, warnings, and health issues when available; that summary is diagnostic only and does not turn blocked preflight into release evidence. The runner then records the full twelve-phase SoraSwap evidence set under `deployments/testnet/`. Each phase prints `evidence ready` only after `docs/parity/migration_register.md` has at least one `ported` production row with no non-reference release rows outside `ported`, and the produced JSON has selected-environment/timestamp metadata, current chain provenance when the artifact records `chain_fingerprint`, no raw local `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, `/private/var/folders/...`, `file://` local-path diagnostic forms, or unredacted sensitive diagnostics, and the immediate phase status expected by the release runner. Failed public deploy attempts retain `deploy.failed.latest.json` and timestamped `deploy.failed.<generated_at>.json` diagnostics, while `deploy.latest.json` is restored to the previous completed deploy report when one exists; only completed `deploy.latest.json` can satisfy release gates. The final preflight phase must match a real `chain.latest.json` with `generated_at`, selected environment, `torii_url`, `chain`, and `block_1_hash`, plus the current supported `nested_call_probe.latest.json`, and the preflight timestamp must be no older than the probe timestamp before RWA compliance evidence is recorded. The deploy report must be no older than that final ready preflight, show completed preflight, compile, nested-call probe, deploy, contract-state bootstrap, and deployment-record snapshot phases, have `deployment_records_snapshot.detail.snapshot` name the current contracts timestamp, and its preflight detail must prove signer readiness without `SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK`; `contracts.latest.json` must have `status: "completed"` and be no older than the deploy report, and every per-contract deploy record plus manifest must carry matching code/ABI hashes, selected-environment/timestamp metadata, a filename-matching `contract_key`, successful response/instance proof, and a deployed bundle receipt when produced by the bundle deploy path. If the aggregate `soraswap.bundle.deploy.json` receipt is present, it must also be successful, timestamped, selected-environment-scoped, path-clean, match `chain.latest.json`, match the current contracts snapshot by key/address/nonce/code hash/ABI hash, and contain no diagnostics that would change under the shared redactor. RWA evidence must match the current chain, be no older than that final ready preflight, and be either explicit `not_applicable` for DEX-only release mode or completed external-reference evidence for an enabled RWA launch. Post-deploy smoke, console, trader, and trader API reports must embed current completed contracts/deploy snapshots by `generated_at`, status, selected environment, and chain fingerprint. Mutating smoke must have `status: "completed"`, reference the current supported nested-call probe plus current readonly-smoke verification, and prove first-release module transaction and state evidence plus risk-vault views, perps-liquidation transaction hashes plus numeric positive liquidation counters, and 2026 primitive transaction/rejection evidence. The contract-console report must have `status: "completed"` and prove governed-route provenance plus a valid proof/message submission outcome. Trader reports must prove all required route probes with account-scoped query parameters (`authority`, list `limit`, and swap-candle `bucket_secs`) plus signed numeric `route_swap` evidence where the base-input path decreases XOR and increases USDT. Trader API publication must have `status: "completed"` and prove the exact route manifest, matching SoraFS pin/registry receipts, and numeric matching CID probe attempt, success, and manifest-match counts. `make release-checklist` rejects `chain.latest.json`, `preflight.latest.json`, and any retained `nested_call_probe.latest.json` that would change under the shared redactor before printing blocked-preflight diagnostics, and after the rest of the release-evidence checks pass it rejects required target-chain summaries, per-contract deploy records and manifests, aggregate bundle receipts, and local evidence JSON that would change under that redactor. Release runners also reject `SORASWAP_INIT_CONTRACT_STATE=0`, globally exported `SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK=1`, exported internal checklist prerequisite flags `SORASWAP_RELEASE_CHECKLIST_TAIRA_PREREQ_ONLY` or `SORASWAP_RELEASE_CHECKLIST_INTERNAL_PRODUCTION_PREREQ`, and the private `RELEASE_CHECKLIST_INTERNAL_TOKEN`; the nested-probe skip is runner-managed for the first refresh-safe preflight only, the production prerequisite narrowing is entered only by the scrubbed tokenized checklist path, and nested release `make` calls clear generic `CHAIN`, `ACCOUNT_CHAIN_DISCRIMINANT`, and `IROHA_ACCOUNT_CHAIN_DISCRIMINANT` plus `MAKEFLAGS`, `MFLAGS`, `GNUMAKEFLAGS`, `MAKEFILES`, and `MAKEOVERRIDES` before phase dispatch. Missing or non-release migration register, warning-only preflight, blocked preflight, stale preflight/probe ordering, preflight health issues, missing or malformed chain snapshot, unsupported nested-call probe, failed or partial deploy, skipped signer readiness, skipped contract-state bootstrap, incomplete deploy records, stale or mismatched aggregate bundle receipt, incomplete or degraded current contracts/deploy snapshots, stale deploy/preflight ordering, stale contracts/deploy ordering, stale deploy snapshot detail, stale RWA/preflight ordering, stale smoke nested-probe evidence, stale readonly-smoke evidence, wrong-chain smoke/trader/console evidence, incomplete RWA/trader/smoke/console/trader API reports, unredacted RWA notes, unredacted sensitive diagnostics, raw local diagnostic paths, degraded trader API publication, dry-run make flags, injected makefile state, or stale generic chain/account-discriminator state stop before the next phase.

When the retained direct-validator diagnostics are JSON-readable and every sampled validator is one height ahead of both committed and highest QC while queues or `missing_qc` / `quorum_timeout` pressure are present, preflight and checklist output prints a direct-validator diagnosis. Treat that as an operator-side Taira finality recovery signal: pause SoraSwap signed writes, follow the sibling Taira state-repair/rollout runbook, and rerun preflight only after public finality and queue age stay stable.

When SSH is unavailable but the operator host exposes local Torii listeners, run preflight with `SORASWAP_TAIRA_DIRECT_TORII_HOST=<operator host>` and `SORASWAP_TAIRA_DIRECT_TORII_PORTS=29080,29081,29082,29083`. The retained `endpoint.direct_torii_port_health` evidence uses only `port-<port>` labels and redacted endpoint URLs, so the operator host/IP is not written into release artifacts.

If a failed deploy attempt left `deployments/testnet/deploy.latest.json` in `status: "failed"`, run `make maintain-testnet-deploy-latest` first as a dry run. Apply the maintenance script only when it finds a completed deploy report that matches the saved Taira chain fingerprint and current `contracts.latest.json`; otherwise keep the failed latest report and produce fresh deploy evidence after public write health recovers.

If preflight reports that saved `chain.latest.json` is stale against live Taira, run `make refresh-testnet-chain` only after accepting that public reset. The target is read-only against Taira, archives stale local `deployments/testnet` evidence, and writes the current chain snapshot; it does not replace the signed `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe` runtime check.

Before long signed SoraSwap writes, preflight plus the mutating smoke, signed trader, and trader API publication wrappers sample `/status` and `/v1/sumeragi/status` through the shared public write-health guard before starting. Public contract-call submissions use the longer `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT` / `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS` window, mint `creation_time_ms` only after that submit-health wait passes, pin it per logical contract call, and retry transient transport or wrapped submit failures with `SORASWAP_CONTRACT_CALL_RETRY_COUNT` / `SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS` so retries preserve transaction identity. Public calls also use `SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS` so queued transactions do not expire during finality stalls. Transaction visibility waits continue until terminal/committed status or the elapsed timeout while recording health at timeout; public contract calls default that visibility timeout to `max(SORASWAP_TX_COMMITTED_WAIT_SECS, 300)` unless `SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS` is set, abort early when `SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS` sees queued writes behind stale public block production, and classify an elapsed visibility timeout as a public finality/write-health blocker when Taira still reports degraded write health. Smoke views that must observe a just-applied mutation use bounded read-after-write retries through `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT` / `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS` before their results feed later assertions. Treat non-JSON health endpoint responses, `blocks: 0`, no recent committed block within `SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS`, transaction queue count/depth saturation, age-only queue pressure whose oldest queued transaction is at or above that age threshold, queued writes with no committed block for at least `SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS`, `missing_qc` / `quorum_timeout` view-change causes, or excessive highest-QC versus committed-QC lag as a public finality/write-health blocker only when it persists through the relevant retry window. Tune only the numeric thresholds with `SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX`, `SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX`, `SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS`, `SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT`, `SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS`, `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT`, `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS`, `SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS`, `SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS`, `SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS`, `SORASWAP_CONTRACT_CALL_RETRY_COUNT`, `SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS`, `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT`, and `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS`; do not bypass the guard for release evidence. If mutating smoke exits during or after its readonly prerequisite, inspect `deployments/testnet/smoke.failed.latest.json` for diagnostic submitted-call traces when any were submitted, `run_suffix`, `smoke_names`, and the latest public write-health sample, but keep treating `deployments/testnet/smoke.latest.json` as the only signed mutating smoke artifact that can satisfy release gates. If contract-console smoke exits after a setup, proof, or bridge-message transaction is submitted, inspect `deployments/testnet/contract_console_smoke.failed.latest.json` for `submissions.submitted_calls`, proof/message submission state, and the latest public write-health sample, but keep treating `deployments/testnet/contract_console_smoke.latest.json` as the only console smoke artifact that can satisfy release gates. If signed trader exits after submitting `route_swap`, inspect `deployments/testnet/trader.latest.json` fields `mutation.submitted_calls`, `mutation.latest_submitted_call`, and `public_write_health`, but keep treating any non-completed top-level status as release-blocking.

Contract-console bridge status validation is exact. Apply-path evidence requires both proof and message `status_kind` values to be `Applied` or `Committed`; replay fallback requires message `Rejected` with replay/duplicate/consumed/proof-overlap detail or the current bridge-contract `assertion failed (constraint violation)` text, so substring values such as `NotApplied` and generic rejection records do not pass the release gates.

Use only untracked public client configs and oracle override values with real endpoints and key material. Public preflight, release runners, and standalone public wrappers apply the same validation to explicit config env vars and the default ignored paths `config/testnet/taira.client.toml` plus `config/production/production.client.toml`: they reject example files, local/wildcard/example endpoints such as `127.0.0.1`, `0.0.0.0`, IPv6 `[::1]` / `[::]`, reserved `.example`, `.test`, `.invalid`, `.localhost`, `example.com`, `example.org`, and `example.net` hosts, embedded placeholder fragments such as `CHANGE_ME`, `TODO`, `TBD`, `changeme`, `replace_me`, `replaceme`, or `placeholder`, Taira configs whose chain does not match the expected Taira chain unless `SORASWAP_TESTNET_CHAIN_ID` pins an intentional public reset, and production configs or stale generic `CHAIN` overrides that still carry Taira's canonical chain id unless `SORASWAP_PRODUCTION_CHAIN_ID` pins the intended chain before any signed public action.
