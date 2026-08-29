# Smart Contract Production Audit

Date: 2026-08-24

Scope:
- `contracts/**/*.ko`
- Local compile/test/deploy entrypoint scripts relevant to contract state bootstrap
- Interface and state-layout documentation for changed surfaces

## Executive Summary

The audit did not leave any known Critical or High smart-contract findings open in the local source tree. The main production-readiness gaps found during review were owner/admin paths that could write invalid risk state, options oracle paths that documented stale-slot rejection without enforcing it everywhere, and governed bridge route provenance that could be rewritten by a later proof-authority activation.

Those findings are fixed in source, covered by Kotodama regressions, and reflected in bootstrap/docs. The first-release manifest contains the current 20-contract Kotodama surface; no completed local deployment evidence is retained in this checkout.

Current Taira release evidence is blocked before any fresh signed release claim:
- Upstream now defines Taira as chain `fc56984b-2be7-431d-840e-21514d1883f0`, NetworkId `hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94`, and account-chain discriminant `369`.
- The current `deployments/testnet/preflight.latest.json` diagnostic (`generated_at: "20260823T162522Z"`) observes the canonical live block-1 fingerprint `d78dd3be4dcd8150ca50b9fa0184a77e16c1042e2e4ce60bdd588c42a49e6c43` and native MCP HTTP `200`, but remains blocked because no saved chain snapshot, complete MCP capability metadata, secure oracle config, mutation consent, or signed nested-call evidence exists; it cannot satisfy the first-release gate.
- A new chain snapshot and complete evidence sequence must be generated after the upgraded runtime is live. There is no compatibility or replay-success path that can promote the retained artifacts.
- Public preflight now defaults `SORASWAP_SKIP_IROHA_CLI_BUILD=1` when unset, so status checks reuse an existing `iroha` CLI and do not start a sibling `cargo build` unless an operator explicitly sets `SORASWAP_SKIP_IROHA_CLI_BUILD=0`.
- Release phase 12 is fail-closed across the documentation update boundary. Full Taira/production runners require signed SoraSwap RC and exact-candidate pins before any mutation, revalidate them around every phase, and require every fixed phase artifact to replace its pre-phase identity, hash, bytes, and `generated_at`. Atomic mode-`0600` receipts bind the fixed 11-phase mapping to one chain and one deploy/contracts snapshot. The pending checkpoint binds the signed RC/tree, HEAD source identity/type/mode and non-status bytes, staged/worktree status-doc equality, absence of non-ignored untracked source, evidence/timestamps, RWA mode, receipts, and candidate bundle/archive hashes. Resume runs all three Git whitespace checks plus strict nonmutating gates and guarded checkpoint deletion; production also revalidates Taira. Either environment's pending state is a global release lock. Same-user hashes detect corruption and drift but are not an authorization boundary against deliberate rewriting by that user.
- Production closeout now adds a signed external authorization boundary before phase 1 and a real 30-minute observation inside phase 12. The RC-bound trust policy requires distinct SSH Ed25519 keys and independent security/operations signatures; the runtime approval binds chain, RC/source, Iroha/bundle/binary/archive hashes, five distinct authorities, operational controls, monitoring watch sets, fee minimum, and trader API identity, and is reverified around every phase. The observer uses fd-bound nofollow reads, mode/single-link checks, same-origin authenticated Torii status/CID reads, an independent signed-policy monitoring origin, cryptographic peer-set identity, committed-height/commit-QC semantics, 61 samples, advancing finality, zero queue/lane/API failures, oracle/balance/readonly/CID checks, and a fail-closed external all-derivatives pause boundary without claiming that the pause occurred. Focused adversarial coverage is `make test-production-cutover`.
- This does not make production ready by itself. The real tracked `config/production/cutover-trust-policy.json`, its trusted public keys, the mode-`0600` signed runtime approval, real production client config and non-Taira chain snapshot, distinct admin/treasury/bridge inputs, approved fee minimum, independent monitoring endpoint/watch hashes, and live production evidence are external inputs and are currently absent. They must not be synthesized from examples.

Current retained local evidence:
- No local chain, deploy, contracts, or smoke release artifact is retained. A new full isolated run must create the current evidence set; earlier runs are not accepted as compatibility evidence.
- Current primitive telemetry at `artifacts/telemetry/defi_2026_primitives_latest.json` has `generated_at: "2026-08-23T15:41:53.820Z"`.

Do not declare production cutover complete until the production target has matching production evidence and external operational signoff. The retained Taira deploy/smoke evidence is not production-chain evidence, and Taira finality/write health must stay stable through a fresh ready preflight and signed smoke before any new Taira or production release claim.

## Fixed Findings

### H-001: Options stored-oracle settlement required stale-slot bounds

Impact: An old stored mark could remain exercisable within monotonic-slot constraints if no fresher value had yet been recorded for the series or shout position.

Status: Fixed.

Changes:
- Added `OptFactoryOracleStaleSlots` to the sole first-release options contract.
- Made `stale_slots` an explicit factory initialization input.
- Added owner-only `configure_oracle_stale_slots(...)` and `oracle_stale_slots()` views.
- Enforced `block_height() - oracle_slot <= oracle_stale_slots` when publishing and consuming the factory-owned typed oracle state.
- Added `SORASWAP_OPTIONS_ORACLE_STALE_SLOTS` bootstrap reconciliation.

### H-002: Perps `update_market` bypassed registration-grade risk validation

Impact: The owner could update an existing market into invalid or impossible risk state, including bad active flags, negative operational limits, invalid utilisation clamps, or out-of-bounds fee/margin values.

Status: Fixed.

Changes:
- Added shared market-risk parameter validation.
- Reused it for both `register_market(...)` and `update_market(...)`.
- Added regression coverage for accepted valid updates and rejected invalid replacements.

### M-001: Governed bridge route provenance was mutable after activation

Impact: A proof authority could re-activate an already governed route with the same route fields but a different governance message, rewriting the provenance used by release evidence.

Status: Fixed.

Changes:
- Repeated governed activation remains idempotent only for the original `message_id`.
- A different `message_id` on an already governed route now rejects with `route governance mismatch`.
- Added regression coverage for governed route provenance immutability.

### M-002: Options admin setters accepted impossible guard/template state

Impact: Owner-only options setters could configure invalid active flags or BPS thresholds above `10_000`, making later user-facing behavior difficult to reason about.

Status: Fixed.

Changes:
- `configure_utilisation_guard(...)` now caps activate, deactivate, and pause thresholds to `10_000`.
- `sync_series(...)` now rejects negative expiry slots.
- Added regression coverage for invalid options admin values.

### T-001: Kotodama `expect_reject_as` test harness used stale return arity

Impact: Rejection tests against no-return entrypoints could fail with a test-host arity error instead of observing the intended contract rejection, weakening regression reliability.

Status: Fixed in the neighboring `../iroha` toolchain.

Change:
- `koto_test` now ignores stale return-arity registers for `expect_reject_as` calls because rejected calls never consume return values.

### T-002: Local deploy/smoke gates did not cleanly support foundation-only release evidence

Impact: The local foundation deployability check could be blocked by later-module contracts, missing explicit unit permissions, or stale temporary scoped manifests even when the N3X/DLMM foundation was deployable.

Status: Fixed.

Changes:
- Added `SORASWAP_DEPLOY_SCOPE=foundation` handling for the local deploy wrapper.
- Foundation deploys compile only the selected contract sources directly, so the tier remains independent of full-only product compilation without introducing a second manifest.
- Scoped local foundation smoke trigger expectations to `soraswap_epoch_auction_close`, `soraswap_range_governor_tick`, and `soraswap_escrow_settle`.
- Granted explicit unit `Admin`/`AssetOps` permissions to the local authority and `AssetOps` to deployed contract subject accounts during bootstrap.
- Switched epoch native-close proof to verify the active-trigger index after close.
- Made the normal per-contract deploy selector compute an explicit six-contract foundation dependency closure: `n3x.n3x_hub`, DLMM pool/router, epoch auction, liquidity executor, and conditional escrow. No temporary alternate manifest is used.

### T-003: `make dev-test` fell through to runtime CLI config loading

Impact: The manifest-declared Kotodama regression suite could be blocked by unrelated Iroha CLI client-config loading before `koto_test` ran, weakening the local production gate.

Status: Fixed.

Changes:
- Added explicit `test` handling in `scripts/dev_iroha.sh` that reads manifest `[[tests]]` entries and runs each file through `koto_test run`.
- Added public helper smoke coverage with a fake `koto_test` binary to ensure the wrapper test path does not require runtime CLI config.

### T-004: Manifest tooling allowed stale generated contract outputs

Impact: A removed or renamed contract could leave ignored `.to` or manifest outputs under `artifacts/compiled/`, and a manifest typo could reach Kotodama tooling with a less actionable missing-file failure. That weakened local release evidence because generated artifacts and generated interface docs could drift from `iroha.contracts.toml`.

Status: Fixed.

Changes:
- `scripts/dev_iroha.sh check` and `build` now reject missing contract sources before invoking Kotodama tooling.
- `scripts/dev_iroha.sh build` now emits CLI dev-smoke-compatible `.to`, `.manifest.json`, `.interface.json`, `.source-map.json`, and `.budget.json` outputs under `artifacts/compiled/`, verifies that set exactly matches manifest-declared contracts, and fails on missing or stale generated outputs.
- `scripts/dev_iroha.sh test` now rejects missing manifest test paths before invoking `koto_test`.
- `tests/public_env_helper_smoke.sh` now compares `docs/interface_specs/generated.md` headings and interface paths against the manifest and covers missing-source, missing-test-path, and stale compiled-artifact fixtures.

## Verification

Current verification:
- `iroha.contracts.toml` is the sole contract manifest and exactly covers 20 current contract sources and 13 Kotodama test files in universal dataspace.
- The six-contract foundation closure includes `launchpad.liquidity_executor`, which the DLMM pool pins immutably; foundation compile does not create an alternate manifest.
- Focused Kotodama regressions pass for the DLMM pool (17), router (8), liquidity executor (6), and epoch auction (11).
- Shell syntax and focused first-release release-phase guards pass for typed options oracle separation, current cover trigger evidence, and the perps-owned collateral pool.
- Current primitive telemetry is retained at `artifacts/telemetry/defi_2026_primitives_latest.json` with `generated_at: "2026-08-23T15:41:53.820Z"`.
- No completed local chain/deploy/contracts/smoke set is retained, so this source verification is not a deployment-readiness claim.
- The current Taira preflight diagnostic has `status: "blocked"`; no current-chain signed release evidence exists.

## Production Readiness Notes

- Local source is hardened for the audited findings, but public production readiness depends on the deployment evidence for the exact target chain and contract addresses.
- Keep the oracle freshness setting explicit in bootstrap evidence. The default is `4`; override with `SORASWAP_OPTIONS_ORACLE_STALE_SLOTS` only when the oracle cadence and chain finality assumptions justify it.
- Treat any future ABI v1 limitation in `call_contract(...)` or test-host behavior as a tooling blocker and patch the narrowest `../iroha` layer, as done for `expect_reject_as`.
