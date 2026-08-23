# SoraSwap

SoraSwap is an Apache-2.0 Kotodama smart-contract repository for Sora Nexus. It uses the sibling [`../iroha`](../iroha) checkout as the canonical compiler, IVM runtime, CLI, and Torii toolchain.

The repo now also carries an SCCP bridge contract at `contracts/bridge/sccp_bridge.ko`. The deploy flow compiles and deploys it automatically with the rest of the contract set, and the signed Taira gate now verifies proof submit plus bridge-message relay through the real contract console backend.

Current status:
- Repo scaffold is in place.
- Initial Kotodama contracts are present for `n3x`, DLMM, launchpad, referral, automation, farms, perps, options, cover, solver intents, vaults, bonded operators, portfolio margin, tokenized RWA markets, and DLMM hooks.
- Trigger-native contracts are now present for `batch_amm.epoch_auction` and `escrow.conditional_escrow`, and existing DLMM/perps/options/cover/launchpad/vault/DLMM-hook modules expose bounded pre-commit or by-call trigger callbacks.
- The derivatives stack is being rebuilt as a launch-gated multi-contract graph: `contracts/risk/risk_vault.ko`, `contracts/perps/perps_engine.ko`, `contracts/options/{manager,factory,vault,shout_option,outperformance_option}.ko`, and `contracts/cover/policy_manager.ko`.
- The derivatives graph now depends on sibling `../iroha` support for same-transaction ABI v1 contract-to-contract `call_contract(...)` execution. Product contracts store deployed contract address literals as UTF-8 `bytes` routing fields for nested calls, while nested `authority()` inside the callee still resolves to the caller contract subject account.
- DLMM is treated as the deployable AMM surface. The pool lifecycle initializer is asset-agnostic at `hajimari(...)`, while the reviewed Taira validation-fee instance fixes canonical XOR as base and canonical SBD as quote.
- The pool's `configured_base_asset()`, `configured_quote_asset()`, and `configured_vault_account()` views expose only its generic stored configuration, allowing nested callers to bind an exact instance without adding an official or pair-specific pool path.
- Core module config is now init-only, caller-bound, and canonical-asset based: the public `*_with_assets` and post-init `configure_*` compatibility surfaces were removed from the SoraSwap contracts.
- The `n3x` basket hub now supports init-time basket targets, mint/redeem fees, redeem quoting, and mirrored fee accounting.
- The DLMM pool scaffold now executes guarded multi-bin swaps, seeds multiple bins deterministically, and supports explicit `position_id` LP records with per-bin fee claims.
- The launchpad scaffold now tracks recorded allocations, init-time claim windows, claim inventory, refunds, explicit seed inventory, registered DLMM seed plans, and executor-backed activation results on chain.
- The risky product modules now keep executor/job ids, cadence, backlog caps, safe-mode state, and native lifecycle trigger state on the product contracts. `contracts/automation/job_queue.ko` remains a first-release scheduler surface for standalone automation jobs, while launch/expiry/readiness/TWAMM/auction paths use native Iroha triggers.
- Derivatives now route user collateral, liability, and payout state through `risk_vault` instead of direct product-owned custody transfers. The shared risk-vault custody account is the deployed contract subject itself, so nested product calls settle against contract-owned collateral on chain. Local acceptance and the signed Taira smoke lane both exercise active write paths for perps/options/cover.
- Perps/options/cover plus `risk_vault` remain one shared rollout surface behind the combined `lint + compile + simulate + isolated local smoke` gate rather than independent per-module acceptance.
- The current DLMM LP surface is the pool contract's `position_id` accounting, not a helper/NFT wrapper layout.
- New trigger-native success paths do not require an off-chain keeper/solver/relayer. Public/testnet deploy grants `CanRegisterTrigger`, smoke grants `CanExecuteTrigger` for by-call escrow evidence, and `iroha trigger execute <id> --args-json ...` is available through the sibling CLI.
- The 2026 DeFi primitive launch uses generic metadata-backed native `DeFiInstructionBox` records in `../iroha` for intents, vaults, operators, AMM hooks, margin, and RWA markets, with SoraSwap product adapters in `contracts/{intents,vaults,operators,margin,rwa,dlmm_hooks}`.
- `xor#universal` is the canonical base asset for routing and pool pricing.
- [`docs/parity/migration_register.md`](./docs/parity/migration_register.md) is the canonical release ledger. Modules must be `ported`, `blocked`, `stub`, or `reference-only`; `adapted` is treated as an intermediate non-release state only.

## Layout
- `contracts/` - Kotodama contracts grouped by module.
- `scripts/` - compile, lint, deploy, and smoke wrappers around `../iroha`.
- `ui/` - static browser assets for the local contract console.
- `tests/` - end-to-end local verification wrappers that keep the localnet alive for the duration of the run.
- `config/` - local, testnet, and production client templates.
- `docs/` - parity, interface, state-layout, and release notes.
- `artifacts/` - generated bytecode and manifests.
- `deployments/` - deployment evidence, canonical address records, and manifests by environment.

## Asset and Naming Policy
- Base asset: `xor#universal`
- Stable basket brand: `n3x`
- Helper aliases under this repo: `usdt#soraswap.universal`, `usdc#soraswap.universal`, `kusd#soraswap.universal`, `n3x#soraswap.universal`

## Requirements
- A sibling `../iroha` checkout with ABI v1 synchronous contract-to-contract `call_contract` support wired through Kotodama codegen, IVM host/runtime dispatch, executor, Torii payload normalization, and CLI helpers.
- Rust toolchain able to build `iroha`, `ivm`, and `irohad`.
- `curl` and `jq` for Torii smoke calls and response checks.
- A client config for either local Nexus or a public environment such as Taira testnet.

## Commands
```bash
make dev-doctor
make dev-build
make dev-check
make dev-test
make dev-schema
make dev-smoke
make lint
make compile
SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG=config/validation_fee/autonomous-payout.local.json make render-validation-fee-payout
SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG=config/validation_fee/autonomous-payout.local.json make check-validation-fee-payout
SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG=config/validation_fee/autonomous-payout.local.json make compile-validation-fee-payout
SORASWAP_VALIDATION_FEE_PAYOUT_CONFIG=config/validation_fee/autonomous-payout.local.json make test-validation-fee-payout
make check-shell-syntax
make redact-generated-evidence
make simulate-build
make simulate-smoke
make simulate-full
make local-up
make local-down
make deploy-local
make smoke-local
make refresh-testnet-chain
make refresh-production-chain
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight
make test-local
make test-local-isolated
make test-local-foundation-isolated
make contract-console
make trader-ui
make test-contract-console
make test-contract-console-ui
make test-contract-console-integration
make test-trader-ui
make test-contract-console-live
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet
make soak-contract-console
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make deploy-production
make maintain-public-deploy-latest
make maintain-testnet-deploy-latest
make maintain-production-deploy-latest
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make publish-trader-api
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make publish-production-trader-api
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet
make smoke-testnet-readonly
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet-trader
make smoke-testnet-trader-readonly
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production
make smoke-production-readonly
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production-trader
make smoke-production-trader-readonly
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make test-contract-console-production
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make public-nested-call-probe
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe
make record-rwa-compliance
make record-testnet-rwa-compliance
make record-production-rwa-compliance
make taira-state-repair-plan
make test-public-env-helpers
make test-production-auth-config
make test-release-closeout
make test-production-cutover
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make release-production
make release-checklist
make release-production-checklist
```

### External validation-fee payout

The CBSI validation-fee payout wrapper is intentionally excluded from
`iroha.contracts.toml` and every default SoraSwap deploy/release bundle. Copy
`config/validation_fee/autonomous-payout.example.json` to the ignored
`config/validation_fee/autonomous-payout.local.json`, replace every placeholder
with reviewed public Taira identifiers, and run the dedicated targets above.
The renderer accepts no key material, rejects unknown fields and any deviation
from canonical SBD/XOR, 10 SBD, 4..100 XOR, and four unique recipients, then
writes:

- `artifacts/rendered/validation_fee/autonomous_payout.ko`
- `artifacts/rendered/validation_fee/autonomous_payout.render.json`
- `artifacts/compiled/validation_fee/autonomous_payout.to` after compile

The dedicated check/build/test commands pin Kotodama's offline
`--chain-discriminant 369` policy. Every account literal must retain the
canonical fresh-Taira `test` prefix; the renderer and compiler reject Sora or
other-network forms rather than rewriting an account identifier.

For the fresh `fc569` Taira reset,
`config/validation_fee/autonomous-payout.taira.pending.json` already pins the
four validator payout accounts tagged
`metadata.purpose = taira_validator_payout_recipient` in rendered genesis SHA-256
`766910cc2cd4916701c17f00d8f0cad23da0d19774bfad82e3d42442b26178cc`.
Its adjacent `.provenance.json` records the derivation and exact fixed policy.
The pool contract, pool vault, and payout contract subject remain explicit
`LIVE_TAIRA_*_REQUIRED` values; the strict renderer rejects the pending file
until an operator replaces all three from the reviewed live deployment. Copy
the pending file to the ignored `autonomous-payout.local.json` and change only
those three fields; do not edit the pinned recipients or policy constants.
Recheck any retained copy of the rendered genesis with:

```bash
python3 scripts/verify_validation_fee_taira_binding.py /path/to/rendered/genesis.json
```

The rendered contract pins its pool address, pool vault, payout subject/vault,
and four validator recipients directly in Kotodama source. It exposes only
`autonomous_validation_fee_tick`; its pinned contract-subject authority and
exact selector permission topology bind it to the declared indefinite
pre-commit time trigger. It no-ops below the 10 SBD batch or minimum
pool-vault XOR credit,
performs a full-fill caller-funded SBD-to-XOR nested swap, enforces the exact
4..100 XOR bounds and balance deltas, and distributes one exact quarter to
each recipient in a single transfer batch. It has no lifecycle configuration,
owner, admin, manual tick, recipient setter, router setter, upgrade, or
sponsorship entrypoint. Rendering, compiling, and testing do not deploy it.
Admission additionally requires a reviewed XOR/SBD pool with the pinned vault
and irreversible `AdminRenounced == 1`; the payout render/check/build/test
tooling does not perform that live verification or any deployment.

The fresh-chain P1 deployment is driven by
`scripts/apply_validation_fee_deployment.sh`, not the generic SoraSwap
deployment bundle. `make plan-validation-fee-deployment` first revalidates the
reviewed source/artifact/manifest hashes, signed Iroha source commit, exact
reviewed tracked-diff and untracked path/mode/blob closure, separately bound
`Cargo.lock`, release binary hashes, deterministic nonce `0` pool and nonce
`1` payout addresses, aliases, subjects, code/ABI hashes, and the exact three
protected permission selectors without contacting Taira. Before apply, update
only the reviewed source-closure and binary hashes in
`config/validation_fee/deployment.taira.p1.json`, then update the script's
reviewed canonical spec digest.

The release source root must be a standalone clone packaged and mounted from
an immutable read-only filesystem after the tracked diff, untracked
path/mode/blob manifest, signed base, and separately copied `Cargo.lock` have
been reviewed. The collaborative writable Iroha checkout and shared Git
worktrees are rejected. Cargo writes only to a new external target directory;
the read-only source mount makes transient source mutation during compilation
impossible instead of relying only on matching pre/post snapshots.

Apply requires the explicit mutation consent gates, exact client config, a new
or resumable absolute evidence directory, and strict one-write mode. The work
root must be an absolute non-overlapping sibling of the canonical evidence
directory. `SORASWAP_VALIDATION_FEE_STATE_ROOT` must name one canonical,
mode-`0700`, operator-writable directory outside the source, evidence, and
work trees; every runner on every host must share that same durable directory.
No-clobber `root.binding.json` files give the evidence and work roots distinct
random identities. The external `state.binding.json` binds their raw hashes,
canonical paths, its own random state identity, chain/P1 identity, and producer
digest; `00.plan.json` binds the raw SHA-256 of that state binding. Deleting
and recreating an empty directory at the same path therefore cannot reset
gate ancestry or discard a partial mutation journal unnoticed. The
write-gate command must be a reviewed, executable, non-symlinked producer that
reads one `soraswap.validation-fee-write-gate-request.v1` JSON object from
stdin and emits one `soraswap.validation-fee-write-gate.v1` JSON object on
stdout. Both objects must be strict, duplicate-free, finite-number-only,
sorted, two-space-indented canonical UTF-8 JSON with one trailing newline.
The producer must be a reviewed native Mach-O/ELF executable rather than an
interpreter script. Its file must have no write bits, must not be writable by
the operator, and every ancestor must be on its reviewed operator-read-only
mount. It runs under an empty environment with only fixed locale, timezone,
and system `PATH`, so proxy, Python import, custom-CA, and TLS key-log
environment variables cannot alter or observe it.
This repository validates that contract but does not ship the network-reading
producer: apply remains intentionally blocked until an independently reviewed
producer is installed and pinned by its exact SHA-256:

```bash
SORASWAP_PUBLIC_ENV=testnet \
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 \
SORASWAP_VALIDATION_FEE_DEPLOY_APPLY=1 \
SORASWAP_VALIDATION_FEE_DEPLOY_CLIENT_CONFIG='/run/secrets/taira-client.toml' \
SORASWAP_VALIDATION_FEE_EVIDENCE_DIR='/absolute/operator/evidence/validation-fee-p1' \
SORASWAP_VALIDATION_FEE_WORK_ROOT='/absolute/operator/evidence/validation-fee-p1.work' \
SORASWAP_VALIDATION_FEE_STATE_ROOT='/absolute/operator/state/validation-fee-p1' \
SORASWAP_VALIDATION_FEE_ONE_WRITE_PER_INVOCATION=1 \
SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND='/opt/reviewed/bin/taira-validation-fee-write-gate' \
SORASWAP_VALIDATION_FEE_WRITE_GATE_COMMAND_SHA256='<reviewed-command-sha256>' \
SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_BIN='/opt/reviewed/bin/validation_fee_ledger_adapter' \
SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_SHA256='<reviewed-adapter-sha256>' \
SORASWAP_VALIDATION_FEE_LEDGER_ADAPTER_SOURCE_SHA256='<reviewed-adapter-source-sha256>' \
SORASWAP_VALIDATION_FEE_IROHA_SOURCE_ROOT='/Volumes/reviewed-iroha-closure' \
SORASWAP_VALIDATION_FEE_EXPECTED_BLOCK_1_HASH='<reviewed-fresh-chain-block-1-hash>' \
make apply-validation-fee-deployment
```

Each invocation takes an exclusive lock, performs at most one newly submitted
mutation, waits for exact `Applied` evidence, and fsyncs immutable
intent/submission/Applied journals plus their containing directories before
exiting successfully with JSON status
`paused_after_applied_write`. Stop at that status, obtain the next explicit
mutation authorization, and invoke the same command again. Leave
`SORASWAP_VALIDATION_FEE_INVOCATION_ID` unset for a fresh generated ID on each
invocation, or provide a new unique ID yourself. Only the final invocation,
which performs no write, emits the canonical `07.final.json` path.
The lock and the only accepted gate-history directory are fixed under the
bound external state root; caller-selected invocation-history paths and
alternate evidence/work roots are rejected after state binding. Back up that
complete state root with the canonical evidence. If `apply.lock` remains
after a host or shell crash, first
inspect its immutable `owner.json` and prove no apply/bootstrap process or
in-flight submission remains, then move the whole lock directory to a
timestamped quarantine name under the same state directory before resuming.
Never remove or move a lock held by a live invocation.

Immediately before every prepared account registration, typed permission
grant/revoke, split-deploy transaction, and contract-call POST, the pinned
producer must
prove the four validator-local endpoints at ports `39080..39083`, public
`https://taira.sora.org`, and MCP `https://taira.sora.org/v1/mcp` agree on the
exact fresh Taira chain, discriminant, reviewed block-1 hash, committed block
height/hash, health, status, Sumeragi status, canonical block lookup, and node
capabilities. MCP
must expose the exact four read tools in the request. Every later observation
must prove the previous checkpoint is its canonical ancestor; rollback,
same-height equivocation, stale/expired output, endpoint mismatch, unhealthy
capability, mutable producer, producer-digest mismatch, or non-contiguous gate
history fails closed.
After the gate and every required pre-submit journal are fsynced, the hook
revalidates the published marker against the current clock as its final action;
an expiry during local journal publication therefore prevents the POST.

The current Iroha CLI quotes and signs, then performs a capabilities request
after any process-level hook and before its transaction POST. It has no
reviewed generic emit-only mode for account registration or permission
grant/revoke, so that hook is not an immediate-submit boundary. This release
retains that generic CLI hook as an unconditional fail-closed path.
Account registration and the five temporary permission selectors instead use
the separately reviewed native prepare-only adapter. The adapter has no submit
or generic-instruction command: it accepts only the two exact plan subject
mappings and exact typed grants/revokes, quotes fees, signs, re-decodes and
verifies the envelope, then freezes one mode-`0444` Norito payload. Its
compile-time plan digest must equal the canonical digest in immutable
`00.plan.json`; the runner additionally pins the adapter binary SHA-256 and
rejects unknown or duplicate JSON fields. The full imminent operation binds
the plan digest, semantic intent, payload SHA-256, positive payload size, and
exact transaction hash before the gate runs. Only the runner performs the
direct Torii POST after the gate and durable intent/submission journals.
Missing, mutable, differently pinned, or non-native adapter artifacts fail
before submission.

The runner rejects an authority nonce other than exactly `0`, pre-existing
subjects or aliases without its own immutable phase journal, any code/ABI,
address, subject, alias, or nonce mismatch, non-applied transaction evidence,
and any direct or role-carried protected lifecycle permission. The sealed
ledger adapter registers both contract subjects with transaction evidence and
performs only the temporary bootstrap permission changes. Contract deployment
uses the reviewed
`split_contract_deploy` binary in `--emit-only` mode and freezes each exact signed
Norito payload at mode `0444`, and submits upload/manifest/commit transactions
one at a time. Evidence files are mode `0444`; a rerun may resume only
contiguous phases whose transaction, chain, alias, manifest, and account state
still match exactly. The sibling work root retains immutable prepared payloads,
per-mutation intent/submission/Applied journals, and the hash-chained
pool-bootstrap event journal before canonical `06.pool-bootstrap.json` is
finalized. The bound external state directory retains the single
hash/height/producer-digest-linked gate ancestry. Losing it after the immutable
plan exists fails closed instead of starting a new sequence. A known submitted
hash, including a contract-call hash journaled immediately after Torii accepts
it, can be reconciled without resubmission only after exact Applied proof; an
intent-only or otherwise ambiguous outcome is never retried automatically. The
runner never grants the three protected runtime permissions or activates
Parliament policy. Run
`make test-validation-fee-deployment` for the offline schema, receipt,
permission-topology, write-gate, one-write budget, and immutable-journal checks.

The separate pool bootstrap is plan-first and is not part of normal SoraSwap
deployment. It pins fresh Taira chain
`fc56984b-2be7-431d-840e-21514d1883f0` with discriminant `369`, canonical
XOR/SBD, `hajimari(...)`, three uniquely owned `seed_bin(...)` positions at
bins `0`, `1`, and `2` with exactly `1000` of each asset, then
`renounce_admin()`. Generate the public, undeployed plan with:

```bash
SORASWAP_VALIDATION_FEE_POOL_CONTRACT_ADDRESS='<reviewed-tairac-address>' \
SORASWAP_VALIDATION_FEE_POOL_SUBJECT_ACCOUNT_ID='<reviewed-test-account>' \
SORASWAP_VALIDATION_FEE_PAYOUT_CONTRACT_ADDRESS='<reviewed-tairac-address>' \
SORASWAP_VALIDATION_FEE_PAYOUT_SUBJECT_ACCOUNT_ID='<reviewed-test-account>' \
make plan-validation-fee-pool
```

Applying additionally requires an explicit client config for that exact chain,
`SORASWAP_PUBLIC_ENV=testnet`, `SORASWAP_ALLOW_TESTNET_MUTATIONS=1`, and
`SORASWAP_VALIDATION_FEE_POOL_APPLY=1`. It is normally invoked by the dedicated
deployment runner after both subjects and both exact contract aliases are
journaled. A standalone invocation must use the same bound
`SORASWAP_VALIDATION_FEE_STATE_ROOT`, canonical evidence root, and canonical
work root through `SORASWAP_VALIDATION_FEE_BOUND_EVIDENCE_ROOT` and
`SORASWAP_VALIDATION_FEE_BOUND_WORK_ROOT`, and must supply the runner's immutable
`00.plan.json`, `01.preflight.json`, `04.pool-deployment.json`, and
`05.payout-deployment.json` paths plus an absolute emergency-recovery evidence
path, an absolute append-only event-journal directory, an absolute mutation
journal directory, the reviewed write-gate command and digest, strict one-write
mode, and an absolute canonical bootstrap evidence path; it cannot bootstrap
caller-selected contracts. Standalone bootstrap acquires the same state-root
Taira-P1 lock and gate-history state as the deployment runner. It rejects a
caller-supplied alternate `SORASWAP_VALIDATION_FEE_INVOCATION_JOURNAL_DIR`. The
script refuses to create or silently adopt subject accounts, verifies the live chain,
deterministic subjects, exact aliases, code/ABI hashes, deployment
transactions, and checked-in P1 spec before its first write, uses only exact
typed `CanInvokeContractEntrypoint` and `CanTransferAsset` bootstrap grants,
records applied evidence for all five calls and all five grant/revoke pairs,
verifies pool/position/admin/governor views, and proves every temporary grant
is absent afterward. Temporary grants intentionally remain active across
successful one-write pauses only when their Applied mutation and event are
durably journaled; the next invocation rechecks exact live topology and passes
a new direct/public/MCP gate before its one write. On an interrupted or failed
run emergency cleanup is itself limited to at most one newly submitted revoke
and the preflight guard is installed as soon as the lock is acquired. While
the ledger adapter blocker remains, an observed live temporary permission
cannot be revoked safely by this runner, so it writes or reports critical
recovery failure and never claims cleanup. With a reviewed adapter, cleanup
writes sequential immutable `<recovery-prefix>.recovery-NNNN.json` evidence
and exits with a loud critical failure unless that invocation's cleanup is
proven. It never loops through several revokes under one authorization. Its
append-only journal retains every exact grant/revoke cycle needed by a resumed
run; it never replaces the canonical phase with an evidence-free
`already_completed` result. The plan records, but external bootstrap never
attempts, the final pool-held permission over wrapper-owned SBD; the protected
Core validation-fee lifecycle must derive that permission atomically and the
post-activation gate must verify its sole-direct-holder topology.

Use `SORASWAP_TAIRA_REPAIR_REASON`, `SORASWAP_TAIRA_REPAIR_SNAPSHOT_POLICY`, and `SORASWAP_TAIRA_REPAIR_OPERATOR` instead of CLI flags when `make taira-state-repair-plan` includes sensitive incident notes or operator tokens; command-line arguments can appear in local process listings while the helper runs. For the one-block-ahead Taira volatile-consensus stall, add `SORASWAP_TAIRA_REPAIR_VOLATILE_DIST`, `SORASWAP_TAIRA_REPAIR_VOLATILE_RUNTIME_BIN`, and `SORASWAP_TAIRA_REPAIR_VOLATILE_EXPECTED_RUNTIME_SHA` so the plan records the clear-volatile-state dry-run/apply command shape and verifies the runtime digest before evidence is written. When no persistent state copy is intended, omit donor/target storage and the report is written as `repair_mode: "volatile_consensus_quarantine"` with `donor: null`, empty `targets`, and no rsync/copy action templates. `SORASWAP_TAIRA_REPAIR_PLATFORM` defaults to `darwin` for the current Taira host; set it to `linux` only for a systemd-operated validator bundle or `manual` when service control is fully operator-managed. Override the default `29080,29081,29082,29083` Torii restart-probe ports with `SORASWAP_TAIRA_REPAIR_VOLATILE_TORII_PORTS` only when the operator-approved listener set differs; the value must be a unique numeric comma-separated port list. The helper still redacts secret-like and local-path text before writing repair-plan evidence.

`make maintain-testnet-deploy-latest` and `make maintain-production-deploy-latest` are dry-run evidence-maintenance commands for interrupted public deploys. They report whether a failed `deploy.latest.json` would be preserved as `deploy.failed.latest.json` plus a timestamped sidecar and restore `deploy.latest.json` only when an existing completed deploy report matches the current saved chain fingerprint and the retained `contracts.latest.json` snapshot. Pass `--apply` to `scripts/maintain_public_deploy_latest.sh` only after reviewing the dry-run output. If no completed deploy report matches the current contracts snapshot, the command leaves `deploy.latest.json` failed and requires a fresh deploy after public write health recovers.

For operator-side Taira finality diagnosis when SSH is unavailable, `make taira-preflight` can sample explicit direct Torii listeners with `SORASWAP_TAIRA_DIRECT_TORII_HOST` and comma-separated `SORASWAP_TAIRA_DIRECT_TORII_PORTS`. The retained evidence redacts the host and stores only `port-<port>` labels plus sanitized endpoint URLs; use it only for diagnostics, not as a substitute for green public write-health gates.

`iroha.contracts.toml` is the source of truth for contract sources, aliases, profile client configs, signer/default gas/fee asset settings, test files, and smoke declarations. `make lint` enters through `scripts/lint_contracts.sh` and `make compile` enters through `scripts/compile_contracts.sh`; those wrappers and the underlying `dev-check` / `dev-build` / `dev-test` / `dev-schema` path reject non-Kotodama files under `contracts/` before invoking tooling, then run the manifest sources through `koto_lint` and `koto_compile`, resolve the default manifest from the repo root for direct script invocation, and match `make dev-check` and `make dev-build` while preserving the canonical repo entrypoints. Compile uses the debug/source-map/budget output shape consumed by top-level `iroha contract dev` freshness checks; generated `.to`, manifest JSON, interface JSON, source-map JSON, and budget JSON files are emitted under `artifacts/compiled/`. The wrapper rejects missing manifest sources and stale or missing generated outputs, so ignored bytecode or sidecar files for removed contracts do not silently survive a compile. `make dev-test` similarly fails before invoking `koto_test` when a manifest test path is missing. `make dev-schema` regenerates the profile/interface summary from the same manifest into `docs/interface_specs/generated.md` and fails if a manifest contract is missing its compiled interface JSON, so run `make compile` first after source or manifest changes; `make test-public-env-helpers` also checks that the generated headings and interface paths still match the manifest. `make check-shell-syntax` parses every top-level `scripts/*.sh` and `tests/*.sh` zsh wrapper instead of relying on an ineffective globbed `zsh -n` invocation, parse-checks top-level Python scripts/tests through Python AST parsing without writing bytecode, parse-checks JavaScript tests, browser UI files, and root JS/CJS/MJS config files with `node --check`, rejects stale root deploy temp manifests left by interrupted foundation or chunked app deploys, rejects non-Kotodama files under `contracts/` except the shared helper README, validates the migration register has at least one `ported` production row and no non-ported production rows, verifies `#!/bin/zsh` shebangs plus `set -euo pipefail` on executable entrypoints and limits non-executable shell files to sourced helper libraries, verifies every Makefile shell-script command references an existing executable file, requires every Makefile recipe target to be listed in `.PHONY` and every `.PHONY` entry to have a recipe, enforces the canonical `lint`/`compile` wrapper entrypoints, validates literal release-script Make target references such as `run_target ...`, `make -C ...`, and `local_acceptance_targets`, checks production script-to-script shell references for missing or non-executable command targets while allowing sourced helper libraries to remain non-executable, checks Makefile and production shell references to repo-owned Python/JS entrypoints, validates Makefile unittest discovery patterns, validates Makefile and package-script `npm run` references against `package.json` scripts, validates dependency-backed package-script commands, validates package-script JS/TS file references, validates `package-lock.json` root metadata against `package.json` when the lockfile exists, validates `tsconfig.json`, Jest, and Playwright root config patterns against real files, validates actual `.gitignore` behavior for generated deployment evidence, tracked `.gitkeep` placeholders, ignored public signer configs, and visible `*.toml.example` templates, validates local UI HTML/CSS asset references under `ui/`, validates local UI JavaScript literal DOM selectors such as `#id` and data-attribute selectors against each app's `index.html`, validates concrete documented timestamped deployment evidence and telemetry artifact paths against real files, checks release-status docs mention the current retained local chain/deploy/contracts/smoke `generated_at` values plus the current `defi_2026_primitives_latest.json` telemetry timestamp and canonical path, scans all generated deployment and telemetry JSON under `deployments/` and `artifacts/telemetry/` for raw local path diagnostics and fails if the shared sensitive-data/runtime-path redactor would change any retained JSON artifact, validates repo-contained Markdown links against real files or directories, validates fenced and inline repo-markdown `make` examples against the Makefile target set, validates repo-markdown `npm run` examples against `package.json` scripts, rejects repo-markdown `zsh -n` examples that name multiple shell-script operands, and rejects stale repo-markdown `scripts/` or `tests/` path references for shell, Python, and JS files. `make redact-generated-evidence` applies the shared sensitive-data and runtime-path redactor to generated deployment/telemetry JSON and rewrites only artifacts whose redacted JSON value changes; `./scripts/redact_generated_evidence.sh --check` runs the same scan without rewriting. `make dev-smoke` runs the native manifest smoke declarations against the selected profile client config through the top-level `iroha contract dev smoke` path. The SoraSwap wrapper forwards that profile config to the top-level `iroha` CLI automatically for runtime dev commands, and those commands fail before invoking the CLI when the selected profile declares a missing config, the default local profile config lacks `torii_url`, or the default local profile points at an unreachable Torii endpoint, so local doctor/smoke/deploy calls use the same signer and Torii endpoint as deploy/smoke flows.

Product lifecycle callbacks are deployed and enabled by default for the first release: `SORASWAP_TRIGGER_LIFECYCLE_ENABLED` defaults to `1`, so scheduled expiry/readiness/liquidation passes run as native trigger paths unless an operator explicitly sets it to `0` for controlled diagnostics. Disabled time-trigger declarations are still registered on activation; smoke reports therefore record both registered trigger IDs and active trigger IDs. Range governor, TWAMM, epoch-auction close, and conditional-escrow by-call surfaces are included in the normal smoke evidence, and mutating smoke proves the epoch-auction pre-commit trigger closes and self-disables after its due slot. Product lifecycle triggers are registered on staggered `120000` ms native schedules while `SORASWAP_TRIGGER_LIFECYCLE_CADENCE_SLOTS=4` remains the product-level slot gate inside each contract, so regular blocks do not dispatch empty lifecycle IVM calls between due wall-clock ticks and due product jobs do not all cluster in one block; the smoke wrappers still expose explicit trigger execute/completion timeouts for trigger-heavy diagnostics.

The neighboring `../iroha` CLI has first-class lifecycle controls for these gates: `iroha trigger list all` lists registered triggers, `iroha trigger list all --active` lists active triggers, and `iroha trigger enable <id>` / `iroha trigger disable <id>` toggle the `__enabled` metadata key. SoraSwap scripts should use `soraswap_enable_trigger "$config" <id>` / `soraswap_disable_trigger "$config" <id>` from `scripts/common.sh` so local and Taira transactions include the required gas metadata.

## Simulations
The repo now includes a root Node/TypeScript/Jest workspace for derivatives simulation and cross-product stress runs.

Useful entrypoints:
```bash
make simulate-build
make simulate-smoke
make simulate-full
```

Simulation suites live under `simulations/`, and generated telemetry is written to `artifacts/telemetry/`.

## Contract Console
For bridge operations, contract browsing, and ad hoc operator calls, start the local browser console:

```bash
make contract-console
```

By default it serves `http://127.0.0.1:4173`, reads the live `deployments/<env>/*.deploy.json` records, refresh-compatible `deployments/<env>/contracts.latest.json` metadata, plus the adjacent `*.manifest.json` files, and exposes a local proxy for:
- `POST /v1/contracts/view`
- `POST /v1/contracts/call`
- `GET /v1/sccp/capabilities`
- `GET /v1/sccp/registry`
- `GET /v1/sccp/messages/recent`
- `GET /v1/sccp/proofs/message/<message_id>`
- `GET /v1/sccp/proof-requests/<message_id>`
- `POST /v1/bridge/proofs/submit`
- `POST /v1/bridge/messages`
- `GET /v1/pipeline/transactions/status`

The backend resolves Torii targets from the checked-in deployment record for the selected environment. Signer configs can contribute authority and signing material, but they do not override the deployment Torii URL. The catalog response now also surfaces signer source metadata and any mismatch warnings that were detected during signer discovery, but only exposes the signer config basename plus boolean Basic Auth presence, with source labels and warning text path-redacted to the basename, instead of full config paths or auth values. Catalog repo labels are basename-only, and contract source plus deployment/manifest evidence paths are repo-relative. Read-only catalog entries are exposed only when they come from a current selected-environment deploy record with a stamped matching manifest, or from the current selected-environment `contracts.latest.json` snapshot with the same manifest proof; the manifest code and ABI hashes must match the exposed evidence, so stale same-key deploy files do not shadow a current snapshot.

The contract-console proxy caps history-like read windows before forwarding them to Torii. Raw GET proxy query strings are capped at `4096` characters and `32` parsed fields before route-specific allowlists run. SCCP recent-message and remote transaction-history queries are capped at `100` rows per request, with `from` and `offset` normalized to a maximum of `10000`; browser-supplied unknown query keys are dropped. SCCP bundle and proof-request lookups require an exact nonzero lowercase 32-byte message id. Browser transaction-status polling likewise requires an exact nonzero lowercase 32-byte transaction hash and forwards only `hash` plus the closed `local|auto|global` scope.

The shared local JSON proxy parser used by the contract console and trader UI requires non-empty POST bodies to use `application/json` or `application/*+json`; it rejects malformed `Content-Length` headers, invalid UTF-8 bodies, JSON bodies nested deeper than `64` levels, and request bodies larger than `1 MiB` before reading them. Browser/API `gas_limit` values must be integers from `1` through `50000000`; blank values default to `100000`. Local Torii proxy responses are capped at `10 MiB` before decoding, and response JSON nested deeper than `64` levels is left as bounded text instead of being embedded as structured JSON.

Contract-console browser POST APIs reject caller-supplied private-key, secret, mnemonic, token/API-key, access-token, refresh-token, authorization, client-secret, password, or passphrase fields at any nesting level, including read-only view and bridge-inspection requests; signing material must come from the bound signer config.

Public preflight, deploy, bootstrap/SNS and asset-alias fallback, manifest-build, contract-app deploy, nested-probe, smoke, contract-console smoke, and trader API publication shell wrappers redact normalized sensitive fields such as `private_key`, `privateKey`, `private-key`, `private key`, `secret`, `mnemonic`, `api-token`, `access_token`, `refresh-token`, `apiKey`, `authorization`, `bearer_token`, `clientSecret`, `token`, `password`, and `passphrase`, plus CLI-style captures like `--private-key`, `--secret`, `--mnemonic`, `--api-token`, `--access-token`, `--refresh-token`, `--authorization`, `--bearer-token`, `--client-secret`, `--password`, and `--passphrase`, from upstream error text before printing it or copying it into failure evidence. URL diagnostics also redact embedded `scheme://user:password@host` credentials and sensitive URL query or fragment params such as `access_token`, `refresh_token`, `client_secret`, `api_key`, `authorization`, `token`, and `password` while preserving non-sensitive params. JSON diagnostics preserve JSON shape while applying the same redaction to string values and object keys, so command-line fragments embedded inside maps do not persist secrets. The same redaction pass normalizes local filesystem paths from `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, and `/private/var/folders/...`, including `file://` URIs pointing at those locations, into basename-scoped `[local-path]/...` or `[runtime-path]/...` labels before diagnostic text is persisted. Public preflight blockers, warnings, health issues, and diagnostic endpoint fields are redacted before they are printed or retained. Public stale snapshot-check diagnostics, local/public negative-test rejection evidence, trader route response bodies, and contract-console bridge submit/replay rejection diagnostics are redacted and capped before being printed or copied into public smoke evidence. Trader API SoraFS pin/registry summary and response files are redacted before reuse, and CID probe bodies plus retained probe body/error files are redacted and capped before they are written to evidence. The local console and trader access logs also redact those sensitive query-parameter values, including JSON-like query payloads or nested URL credentials containing sensitive keys, and truncate long non-sensitive query values before writing request lines to stderr. Immediate release phase guards reject metadata-bearing phase artifacts with unredacted sensitive diagnostics. `make release-checklist` rejects `chain.latest.json`, `preflight.latest.json`, and any retained `nested_call_probe.latest.json` that would change under the shared redactor before printing blocked-preflight or status-doc diagnostics; after normal release validation succeeds, it also rejects target-chain summaries, per-contract deploy records and manifests, aggregate bundle receipts, and local evidence JSON that would change under that redactor, so stale hand-edited artifacts cannot carry hidden secret-like diagnostics into a release claim. Request signing material still comes from the runtime client config and is never intended to be part of release artifacts.

The local operator servers add defensive browser headers to static UI, JSON API, and trader SSE responses: `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, same-origin cross-origin isolation/resource policy, a camera/geolocation/microphone/payment/USB-denying permissions policy, and a strict self-hosted CSP that blocks framing and plugins.

Mutation policy is environment-aware:
- `local` permits signed mutations by default.
- `testnet` public environments, including Taira, permit signed mutations only when the console was started with `SORASWAP_ALLOW_TESTNET_MUTATIONS=1`.
- `production` permits signed mutations only when the console was started with `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1`.
- bridge proof/message submissions accept only the current closed Torii DTO: `destination_proof_b64` for `/v1/bridge/proofs/submit` or `native_proof_b64` for `/v1/bridge/messages`, plus authority and the server-managed detached-signing fields. The proxy prepares the exact transaction, signs its 32-byte prehash locally, reuses the returned payload byte-for-byte, and rejects any metadata switch between preparation and submission.

It now also auto-discovers the standard signer configs when they exist and are not placeholder templates:
- `tmp/iroha-localnet/client.toml` for `local` (or `$SORASWAP_LOCALNET_DIR/client.toml` when that env var is set)
- `config/testnet/taira.client.toml` for `testnet`
- `config/production/production.client.toml` for `production`

Signer configs with local/wildcard/example endpoints, including `127.0.0.1`, `0.0.0.0`, IPv6 `[::1]` / `[::]`, reserved `.example`, `.test`, `.invalid`, `.localhost`, `example.com`, `example.org`, and `example.net` hosts, or embedded placeholder fragments such as `CHANGE_ME`, `TODO`, `TBD`, `changeme`, `replace_me`, `replaceme`, or `placeholder` are treated as templates and are not auto-discovered for signing. Default auto-discovery also requires usable public and private signer key material; explicit `--signer ENV=/path/to/client.toml` configs still load with warnings so operators can see and fix incomplete key or endpoint fields.

Copied testnet and production `.toml` client configs are ignored by git; only checked-in `*.toml.example` templates should be tracked.

The browser UI is deployment-driven: it shows the canonical contract address, dataspace, deploy metadata, and manifest entrypoints already recorded in this repo. No frontend build step is required.

The console now also includes a bridge workspace for the deployed `bridge.sccp_bridge` contract. It can:
- aggregate the common bridge `view` calls (`listing_config`, `mirror_asset`, `asset_vault_account`, `route_config`, `route_provenance`, `mirror_outbound`, `inbound_consumed`) into one local snapshot request
- jump directly to the deployed bridge contract in the generic invocation form
- prefill the common bridge mutation payloads (`register_asset`, `bind_asset_vault`, `activate_route`, `activate_route_governed`, `pause_route`, `resume_route`, `lock_to_remote`, `finalize_inbound`)
- validate bridge action fields before loading them into the generic invocation panel
- validate `lock_to_remote` recipients against the live SCCP codec metadata for the selected counterparty lane
- store browser-local bridge bookmarks for asset keys, routes, transfer ids, and inbound message ids

The operator console now also adds:
- a transaction tracker that stores recent signed actions in browser `localStorage`, tracks `tx_hash_hex`, and polls `/v1/pipeline/transactions/status` until terminal status
- best-effort remote transaction history rendering through `/v1/transactions/history`; public Taira may report this as unavailable, and the UI degrades to a warning state instead of failing
- an SCCP proof/status workspace that renders live capabilities, the authoritative typed registry, newest-first recent outbound messages, raw finalized bundles, and state-derived Groth16 proof requests
- guided destination-proof and native-message builders for the closed `destination_proof_b64` and `native_proof_b64` DTOs
- a **Clear Operator State** action that clears browser-local recent signed actions, tracked transaction statuses, bridge bookmarks, and SCCP proof lookup history after sensitive sessions

## Trader Cockpit
For swap history, charting, wallet-level PnL, and direct DLMM router trading, start the chart-first trader cockpit:

```bash
make trader-ui
```

By default it serves `http://127.0.0.1:4274`; `TRADER_UI_ARGS="--port <n>"` accepts TCP ports from `1` through `65535`. The cockpit reads the same checked-in deployment metadata as the contract console and proxies a narrow trading surface for:
- `GET /v1/contracts/events`
- `GET /v1/contracts/events/sse`
- `GET /v1/contracts/rollups/swaps/fills`
- `GET /v1/contracts/rollups/swaps/candles`
- `GET /v1/contracts/rollups/trader/activity`
- `GET /v1/contracts/rollups/trader/account`
- `POST /v1/contracts/view`
- `POST /v1/contracts/view/batch`
- `POST /v1/contracts/call`
- `GET /v1/pipeline/transactions/status`

The cockpit prefers the deployed `dlmm.dlmm_router` contract in the selected environment. It loads:
- trader account rollups for module cards, wallet metrics, and live product posture
- swap fill and candle rollups for the chart and journal
- trader activity rollups plus contract-event SSE for the unified action feed and live refresh path
- batch contract views only for narrow fallback/config reads

The browser surface keeps the chart, journal, avg entry, realized and unrealized PnL, and trader action rails in one frame so users can see position context and submit without bouncing between raw history and a separate form. It also now:
- keeps a cross-product radar and selectable overview for swaps, `n3x`, perps, farms, launchpad, options, and cover
- adds a focused product stage so traders can pin one surface while keeping the rest visible
- unifies public `options` into one trader surface instead of split factory/manager tiles
- exposes real action rails for swaps, `n3x`, perps, farms, launchpad, options, and cover
- follows Torii contract-event SSE in live mode and refreshes the cockpit when the chain moves, with automatic polling fallback if the stream drops

It accepts the same signer and authority flags as the contract console:

```bash
make trader-ui \
  TRADER_UI_ARGS="--signer local=$SORASWAP_LOCALNET_DIR/client.toml --authority local=$SORASWAP_AUTHORITY"
```

Custom environments allow signed swaps when a signer with a private key is bound. Public environments inherit the same mutate gates as the contract console: export `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` for `testnet`, or `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1` for `production`, before starting the trader if you want the submit button enabled against those deployments.

Trader signed-call requests reject browser-supplied private-key, secret, mnemonic, token/API-key, access-token, refresh-token, authorization, client-secret, password, or passphrase fields at any nesting level; signing material must come from the bound signer config. Trader confirmation JSON uses the same normalized sensitive-key filtering as the contract console before displaying payloads.

The trader cockpit only stores the selected environment, the last authority per environment, and the live-follow preference in browser `localStorage`. Use **Clear State** after sensitive operator sessions to remove those browser-local preferences and blank the authority before the next session.

With public mutations enabled, the trader cockpit uses the same startup evidence guard as the contract console. It refuses to bind when `docs/parity/migration_register.md` is missing, empty, lacks a `ported` production row, or has non-reference release rows outside `ported`. It also refuses to bind when local `deployments/<env>/chain.latest.json`, `preflight.latest.json`, `nested_call_probe.latest.json`, `deploy.latest.json`, `contracts.latest.json`, or per-contract `*.deploy.json` plus `*.manifest.json` evidence is missing, lacks `generated_at` provenance, has a preflight report that is not ready for the current saved chain, signer/oracle environment, and current supported nested-call probe, has an unsupported or stale nested-call probe, has a `contracts.latest.json` snapshot without `status: "completed"`, has a `deploy.latest.json` report without completed preflight, compile, nested-call-probe, deploy, bootstrap, and deployment-snapshot phases plus non-bypassed signer readiness, has a chain snapshot without `torii_url`, `chain`, or `block_1_hash`, points at a different Torii URL, chain id, or block-1 hash, does not cover the current Kotodama contract set exactly once with matching per-contract deploy/manifest evidence, contains stale extra per-contract records, or does not identify the selected environment. If the aggregate `soraswap.bundle.deploy.json` receipt is present, startup also requires it to be successful, timestamped, selected-environment-scoped, path-clean, free of unredacted sensitive diagnostics, matched to `chain.latest.json`, and matched to the current contracts snapshot.

The trader proxy caps rollup and activity `limit` query values before forwarding them to Torii, so accidental large history windows do not become unbounded public-node reads. Trader GET and SSE proxy query strings use the same `4096` character and `32` parsed-field cap as the contract console. Swap fills, candles, trader activity, and raw contract activity are capped at `500` rows per request; module rollups are capped at `250`, with `offset` normalized to a maximum of `10000`. Read routes forward only bounded `authority`, `contract_address`, `cursor`, `module`, `limit`, `from`, and `offset` values where the upstream route supports them; the trader-account rollup is authority-only, and candle `bucket_secs` is forwarded only for swap candles with a cap of `86400`. Trader transaction-status polling uses the same hash-only guard as the contract console. Contract-event SSE only forwards bounded `limit`, `from`, `offset`, `authority`, `contract_address`, `cursor`, and `module` query parameters; unknown browser-supplied query keys are dropped before the upstream stream is opened, individual SSE lines are capped at `1 MiB`, and upstream SSE error bodies use the same `10 MiB` response cap as the local JSON proxy.

The browser smoke suite starts the real Python trader server against a local mock Torii node and verifies history load, chart/journal rendering, and a live `route_swap` submission:

```bash
make test-trader-ui
```

Public Taira trader evidence now has dedicated lanes:

```bash
make smoke-testnet-trader-readonly
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet-trader
```

Those commands write `deployments/testnet/trader_readonly.latest.json` and `deployments/testnet/trader.latest.json` with `status: "completed"` only after their current `contracts.latest.json`/`deploy.latest.json` snapshot check and route evidence are complete. The readonly lane probes `view/batch` plus the full trader rollup route set directly. The signed lane runs live signer funding and `route_swap` probes only after snapshot and route prerequisites pass, records the router contract and entrypoint, reprobes the full route set after the mutation, and records the resulting 64-hex transaction hash plus XOR/USDT balance deltas. If the signed lane fails after a contract transaction is submitted, the same `trader.latest.json` report includes `mutation.submitted_calls`, `mutation.latest_submitted_call`, and a `public_write_health` snapshot so operators can distinguish a bad swap payload from public finality or ingress degradation without treating the artifact as release-passing evidence. Non-JSON or oversized route diagnostic bodies are redacted and capped at `8192` characters by default before they are copied into the report.

The trader API route bundle can also be published to SoraFS and addressed through Torii's CID app API gateway:

```bash
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make publish-trader-api
```

That writes `deployments/testnet/trader_api_bundle.latest.json` by default, including the generated content CID, manifest digest, route manifest, selected environment, the local SoraFS storage-pin receipt, the public pin-registry submission receipt, current contract/deploy snapshot metadata, a read-only deployment-record and manifest freshness summary, a producer-side `snapshot_check` summary, and a repeated `/v1/app-api/cid/{cid}` probe summary. The publish path no longer tries to recover stale deployment records by recompiling contracts mid-rollout; it reports deploy-record or manifest drift as `deployment_record_check.status = "degraded"` and stale, missing, or incomplete current snapshot evidence as `snapshot_check.status = "degraded"`, writes the evidence for diagnosis, and exits nonzero unless top-level `status = "completed"`.
`snapshot_check.status = "completed"` requires `contracts.latest.json` to cover the current Kotodama contract set exactly once and `deploy.latest.json` to have completed preflight, compile, nested-call-probe, deploy, bootstrap, and deployment-record snapshot phases plus signer-readiness proof without debug bypass. `make release-checklist` requires that completed status, the exact expected trader route method/path/adapter set both in the report and in the parsed CID probe response, matching SoraFS pin and registry receipts, a `content_cid` derived from the pinned manifest id, exact current `contracts.latest.json` plus `deploy.latest.json` snapshot references by `generated_at`, status, selected environment, and chain fingerprint, `deployment_record_check.status = "completed"`, `snapshot_check.status = "completed"`, selected-environment agreement, and a `generated_at` no older than those snapshots before a release can pass.
By default the probe uses the same `torii_url` as the selected client config; when public rollout is being validated against an explicit direct node, set `SORASWAP_TRADER_API_PROBE_ROOT=https://<direct-public-node>` before running the target. `SORASWAP_TRADER_API_PROBE_ATTEMPTS` must be a positive integer and defaults to `6`; `SORASWAP_TRADER_API_PROBE_INTERVAL_SECS` must be a nonnegative number and defaults to `1`; `SORASWAP_TRADER_API_PROBE_BODY_MAX_CHARS` must be a positive integer and defaults to `8192` for redacted CID probe body/error evidence. Paid registry visibility is polled with `SORASWAP_TRADER_API_REGISTRY_VISIBILITY_ATTEMPTS` and `SORASWAP_TRADER_API_REGISTRY_VISIBILITY_RETRY_DELAY_SECS`, defaulting to `30` attempts and `2` seconds, before the storage pin step runs. CID gateway propagation is repaired and re-probed with `SORASWAP_TRADER_API_STORAGE_PIN_PROPAGATION_ATTEMPTS` and `SORASWAP_TRADER_API_STORAGE_PIN_PROPAGATION_RETRY_DELAY_SECS`, defaulting to `8` rounds and `2` seconds. `cid_probe.status = "completed"` now means every sampled probe hit `2xx` and served the exact expected trader API manifest; mixed `200/404` results or manifest mismatches are reported as `status = "inconsistent"` so a single lucky cache hit does not look like a healthy public rollout. To activate the CID through an existing public SoraCloud service, set `SORASWAP_PUBLISH_TRADER_API_BINDING=1` and `SORASWAP_TRADER_API_SERVICE_NAME=<service>` before running the target; the binding flag must be `0` or `1`. The script upserts the `torii/app_api_binding` config with the pinned CID and trader route adapters when binding publication is enabled.

View-only sessions can be started with a default authority override:

```bash
make contract-console \
  CONTRACT_CONSOLE_ARGS="--authority testnet=i105..."
```

Local signed entrypoints stay server-side. Bind an untracked client config to an environment when you want the UI to enable `call` requests:

```bash
make contract-console \
  CONTRACT_CONSOLE_ARGS="--signer local=$SORASWAP_LOCALNET_DIR/client.toml"
```

For a mutation-enabled Taira session, bind the signer explicitly and enable the mutate gate before starting the console:

```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
make contract-console \
  CONTRACT_CONSOLE_ARGS="--signer testnet=$SORASWAP_CLIENT_CONFIG --authority testnet=$SORASWAP_AUTHORITY"
```

With public mutations enabled, the console refuses to start when local `deployments/testnet` evidence is stale or incomplete. It also requires `docs/parity/migration_register.md` to be present, nonempty, and backed by at least one `ported` production row with no non-reference release rows outside `ported`. Refresh `chain.latest.json`, `preflight.latest.json`, `nested_call_probe.latest.json`, `deploy.latest.json`, `contracts.latest.json`, and per-contract `*.deploy.json` plus `*.manifest.json` evidence through the public deploy/readiness flow before using the console for signed Taira calls. Those artifacts must record `generated_at` provenance, `preflight.latest.json` must be ready for the current saved chain, signer/oracle environment, and current supported nested-call probe, `nested_call_probe.latest.json` must be supported and no newer than preflight, `contracts.latest.json` must record `status: "completed"`, `deploy.latest.json` must record completed preflight, compile, nested-call-probe, deploy, bootstrap, and deployment-snapshot phases plus non-bypassed signer readiness, and `chain.latest.json` must include non-empty `torii_url`, `chain`, and `block_1_hash` fields. The `contracts.latest.json` snapshot must cover the Kotodama contract set under `contracts/` exactly once, every snapshot entry must record the selected environment and have a matching deploy record plus manifest with selected-environment, contract-key, address, deploy nonce, and hash evidence, and extra stale per-contract deploy records or manifests are rejected. The aggregate bundle receipt `soraswap.bundle.deploy.json` remains allowed as provenance only when it is timestamped, selected-environment-scoped, path-clean, free of unredacted sensitive diagnostics, successful, matches `chain.latest.json`, and matches the current contracts snapshot. If public console smoke fails after a setup, proof, or bridge-message transaction is submitted, it writes diagnostic-only `contract_console_smoke.failed.latest.json` plus a timestamped sidecar with `submissions.submitted_calls`, API proof/message submission state, and a `public_write_health` sample; only `contract_console_smoke.latest.json` with `status: "completed"` can satisfy release gates.

If the console port is already occupied, override it with a TCP port from `1` through `65535`:

```bash
make contract-console CONTRACT_CONSOLE_ARGS="--port 4273"
```

When a signer config includes a public key and the sibling `../iroha/target/debug/iroha` binary is present, the console will attempt to derive the canonical I105 authority automatically. Otherwise pass `--authority ENV=I105...` explicitly.

If you want a strictly manual session, disable default signer discovery with:

```bash
make contract-console CONTRACT_CONSOLE_ARGS="--no-auto-signers"
```

The console backend has a small regression suite:

```bash
make test-contract-console
```

The browser smoke suite serves the static UI, mocks the local proxy surfaces, and verifies catalog load, bridge validation, SCCP discovery, proof lookup rendering, and browser-local persistence:

```bash
make test-contract-console-ui
```

There is also a real browser-to-backend integration smoke. It starts the actual Python console server against a local mock Torii node, then drives the UI through catalog load, bridge snapshot, contract call, SCCP lookup, and proof/message submission flows:

```bash
make test-contract-console-integration
```

The Playwright package scripts start the static contract-console server only for `make test-contract-console-ui`. Fixture-backed browser suites set `SORASWAP_PLAYWRIGHT_STATIC_SERVER=0` and use distinct `SORASWAP_PLAYWRIGHT_PORT` values, so `make test-contract-console-ui`, `make test-contract-console-integration`, and `make test-trader-ui` can run concurrently without contending for one fixed static-server port. `SORASWAP_PLAYWRIGHT_STATIC_SERVER` must be `0` or `1`, and `SORASWAP_PLAYWRIGHT_PORT` must be a TCP port from `1` through `65535`.

If Playwright browser binaries are not installed yet on your machine, run:

```bash
npx playwright install chromium
```

The repo also carries an optional live non-mutating SCCP discovery smoke against the public contract-console surface. It defaults to Taira and stays opt-in so routine local runs do not depend on network reachability. `SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE` must be `0` or `1`, and the live Torii probes use `SORASWAP_TORII_READ_MAX_TIME_SECS`:

```bash
SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE=1 make test-contract-console-live
```

To point the same smoke at the parallel production environment, set `SORASWAP_PUBLIC_ENV=production` and either provide an explicit Torii URL or a production client config:

```bash
SORASWAP_PUBLIC_ENV=production \
SORASWAP_CONTRACT_CONSOLE_LIVE_TORII_URL=https://production.example.invalid \
SORASWAP_RUN_CONTRACT_CONSOLE_LIVE_SMOKE=1 \
make test-contract-console-live
```

Signed Taira verification uses the same contract console:

```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
export SORASWAP_TESTNET_SCCP_DESTINATION_PROOF_FILE=/runtime/path/to/destination-proof.norito
export SORASWAP_TESTNET_SCCP_NATIVE_PROOF_FILE=/runtime/path/to/native-proof.norito
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet
make soak-contract-console
```

`SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet` discovers a finalized Taira-to-external SCCP message, retrieves its canonical bundle and state-derived proof request, and requires runtime files containing a matching destination Groth16 artifact plus an independent governed external-to-Taira native proof. Both submissions must reach `Applied` or `Committed`; replayed or skipped evidence is not release-grade. The runtime proof bytes are never written to evidence, and prepare/submit response metadata must remain identical. `SORASWAP_TESTNET_BRIDGE_MESSAGE_ID` can pin the outbound message whose destination artifact is supplied.

## Environment Variables
The default contract workflow is profile based. Prefer editing or selecting profiles in `iroha.contracts.toml`, then run `make dev-schema` to refresh the generated profile/interface summary. Environment variables are kept for local paths, signer secrets, public rollout gates, and scenario-specific smoke fixtures that should not live in the manifest.

- `SORASWAP_IROHA_ROOT` - defaults to `../iroha`
- `SORASWAP_PROFILE` - selects the `iroha.contracts.toml` profile used by `make dev-*`, `make lint`, and `make compile`; defaults to `local`
- `SORASWAP_CONTRACTS_MANIFEST` - optional manifest override for wrappers; defaults to `iroha.contracts.toml`
- `SORASWAP_IROHA_CLI_BIN` - optional explicit `iroha` binary used by `scripts/dev_iroha.sh`
- `SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD` - set to `1` to reuse existing `iroha`, `koto_compile`, `koto_lint`, and `koto_test` binaries; must be `0` or `1`
- `SORASWAP_CLIENT_CONFIG` - CLI config path; defaults per script
- `SORASWAP_AUTHORITY` - optional canonical I105 override; otherwise derived from the client config public key
- `SORASWAP_BASE_ASSET_ALIAS` - defaults to `xor#universal`
- `SORASWAP_XOR_ASSET_DEFINITION_ID` - defaults to Taira's canonical `xor#universal` asset definition id; used when the public alias is not query-visible
- `SORASWAP_USDT_ASSET_DEFINITION_ID`, `SORASWAP_USDC_ASSET_DEFINITION_ID`, `SORASWAP_KUSD_ASSET_DEFINITION_ID`, `SORASWAP_N3X_ASSET_DEFINITION_ID` - optional public helper-asset definition overrides used by `bootstrap_assets.sh`; set these before `make deploy-production` when the parallel public chain uses different helper asset ids than Taira
- `SORASWAP_SMOKE_GAS_LIMIT` - defaults to `500000`; must be a positive integer
- `SORASWAP_SKIP_IROHA_CLI_BUILD` - set to `1` to reuse existing `../iroha/target/debug` or `../iroha/target/release` CLI/helper binaries even when the sibling tree is newer; fails instead of building when the required binary is absent; must be `0` or `1`. Public preflight commands default this to `1` when unset so health checks do not start a sibling `cargo build`; set it to `0` explicitly when you want preflight to build a missing or stale CLI.
- `SORASWAP_SORAFS_CLI_BIN` - optional explicit `sorafs_cli` path used by `make publish-trader-api`; otherwise the script reuses or builds `../iroha/target/debug/sorafs_cli`
- `SORASWAP_SKIP_KOTO_TOOL_BUILD` - set to `1` to reuse existing `../iroha/target/debug/{koto_compile,koto_lint}` binaries instead of rebuilding them; must be `0` or `1`
- `SORASWAP_FORCE_COMPILE` - set to `1` to rebuild generated contract outputs even when they look current; must be `0` or `1`
- `SORASWAP_SKIP_LOCALNET_TOOL_BUILD` - set to `1` to reuse existing `../iroha/target/debug/{iroha,irohad,kagami}` binaries instead of rebuilding them; must be `0` or `1`
- `SORASWAP_LOCALNET_DIR`, `SORASWAP_LOCALNET_BASE_API_PORT`, `SORASWAP_LOCALNET_BASE_P2P_PORT`, `SORASWAP_ISOLATED_PORT_SELECTION_MAX_ATTEMPTS` - optional isolated-acceptance placement controls. The run directory must not already exist and must be a direct child of this checkout's `tmp/`; the wrapper retains it after success or failure. Port selection starts at `49180` / `49337`, advances both values by `100` while either address is not bindable, and fails after at most `162` range-checked attempts.
- `SORASWAP_TORII_URL` - optional explicit Torii URL override
- `SORASWAP_TESTNET_CHAIN_ID` - optional override for the public Taira chain id; when unset, scripts use the copied client config's `chain` value and fall back to `fc56984b-2be7-431d-840e-21514d1883f0`; public wrappers do not use generic `CHAIN` as a substitute
- `SORASWAP_TESTNET_CHAIN_DISCRIMINANT` - optional override for the public Taira account-address network prefix; when unset, scripts use `[account].chain_discriminant`, then `[account].profile`, then the canonical Taira fallback `369`
- `SORASWAP_ALLOW_TESTNET_MUTATIONS` - required for any signed Taira signer funding, deploy, bootstrap, nested-call probe, smoke, console, trader, or trader API publication path
- `SORASWAP_ALLOW_PRODUCTION_MUTATIONS` - required for `make production-preflight`, `make release-production`, and standalone signed production deploy, bootstrap, nested-call probe, smoke, console, trader, or trader API publication paths
- `SORASWAP_TRADER_PUBLIC_RESPONSE_BODY_MAX_CHARS`, `SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_ATTEMPTS`, `SORASWAP_TRADER_PUBLIC_ROUTE_PROBE_RETRY_DELAY_SECS` - optional public trader route-probe controls; retained redacted non-JSON or oversized route response bodies are capped at `8192` characters by default, route probes retry public transport/502/503/504 failures up to `3` attempts by default, and retry delay defaults to `2` seconds. Body cap and attempts must be positive integers, and retry delay must be nonnegative.
- `SORASWAP_PUBLISH_TRADER_API_BINDING`, `SORASWAP_TRADER_API_SERVICE_NAME`, `SORASWAP_TRADER_API_APP_ID`, `SORASWAP_TORII_API_TOKEN`, `SORASWAP_TRADER_API_PROBE_ROOT`, `SORASWAP_TRADER_API_PROBE_ATTEMPTS`, `SORASWAP_TRADER_API_PROBE_INTERVAL_SECS`, `SORASWAP_TRADER_API_PROBE_BODY_MAX_CHARS`, `SORASWAP_TRADER_API_REGISTRY_VISIBILITY_ATTEMPTS`, `SORASWAP_TRADER_API_REGISTRY_VISIBILITY_RETRY_DELAY_SECS`, `SORASWAP_TRADER_API_STORAGE_PIN_PROPAGATION_ATTEMPTS`, `SORASWAP_TRADER_API_STORAGE_PIN_PROPAGATION_RETRY_DELAY_SECS` - optional trader API publication controls for `make publish-trader-api`; binding publication is off by default, must be `0` or `1`, and requires a live public SoraCloud service name when enabled. SoraFS manifest/storage calls use canonical `--client-config` paths, manifest signing uses only `--private-key-file`, and an optional binding token is materialized at mode `0600` for the top-level `soracloud service config-set --api-token-file` interface; inline secret fallbacks are refused. `SORASWAP_TRADER_API_PROBE_ROOT` lets the CID probe hit an explicit direct public validator instead of the client config's default Torii URL, probe attempts and registry/storage propagation attempts must be positive integers, retry delays must be nonnegative numbers, retained redacted probe body/error evidence is capped at `8192` characters by default, paid registry visibility defaults to `30` attempts with `2` second spacing, and CID storage propagation defaults to `8` repair rounds with `2` second spacing
- `SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK` - optional `0`/`1` debug bypass for standalone public deploy/smoke signer balance checks; use only when the configured chain cannot expose the fee asset or faucet state yet and you explicitly want to skip readiness validation. Release runners reject this bypass, and deploy evidence created with it records `signer_ready_check.status: "skipped"` so release phase guards and checklists cannot treat it as releasable.
- `SORASWAP_TAIRA_PREFLIGHT_TIMEOUT_SECS` - defaults to `10`; public preflight HTTP timeout for endpoint, MCP, faucet, and chain-fingerprint probes, and must be a nonnegative number
- `SORASWAP_PUBLIC_PREFLIGHT_QUEUED_STALL_MAX_MS` - defaults to `180000`; with public mutations enabled, preflight records `endpoint.health_issues` from `/status` and `/v1/sumeragi/status`, blocks on non-JSON health endpoints, stale committed blocks, queue saturation, excessive QC lag, and other shared public write-health issues, and also reports the queued-stall hint when queued or age-saturated writes show no committed block within this many milliseconds. Set to `0` only for diagnosis, not release evidence.
- `SORASWAP_BLOCK_HEIGHT_SAMPLE_ATTEMPTS` - optional positive integer for block-height reads; defaults to `1` for localhost Torii roots and `3` for public roots, using the maximum committed/QC height across sampled `/status/blocks`, `/status`, and `/v1/sumeragi/status` responses to tolerate load-balanced stale public status views.
- `SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK` - optional `0`/`1` preflight-only nested-probe evidence bypass; leave unset for normal operator use. Release runners reject a globally exported `1` and apply their own scoped skip only for the first refresh-safe preflight.
- `SORASWAP_PUBLIC_BOOTSTRAP` - optional shared bootstrap toggle for `make deploy-testnet` and `make deploy-production`; defaults to `auto`, set to `1` to force the one-time public domain and helper-asset bootstrap before contract deploy, or `0` to skip it. Values must be `auto`, `0`, or `1`.
- `SORASWAP_TESTNET_BOOTSTRAP`, `SORASWAP_PRODUCTION_BOOTSTRAP` - optional environment-specific bootstrap toggles that override `SORASWAP_PUBLIC_BOOTSTRAP` for `make deploy-testnet` and `make deploy-production`; values must be `auto`, `0`, or `1`
- `SORASWAP_PRODUCTION_CLIENT_CONFIG` - optional default config path used by the production wrapper family when `SORASWAP_CLIENT_CONFIG` is not set, including preflight, nested-call probe, deploy, smoke, contract-console, trader, trader API publication, and release commands
- `SORASWAP_PRODUCTION_CHAIN_ID` - optional production chain-id override used when the production client config is copied from another environment or otherwise carries the wrong `chain` value; production wrappers use this or the config `chain` value and do not use generic `CHAIN` as a substitute
- `SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT` - optional explicit network-prefix override for the parallel production environment; when omitted, production requires `[account].chain_discriminant` in the secure client config and never falls back to generic `SORASWAP_CHAIN_DISCRIMINANT` or Taira's discriminant
- `SORASWAP_LOCAL_FEE_ASSET_LABEL`, `SORASWAP_LOCAL_FEE_ASSET_SCALE`, `SORASWAP_LOCAL_FEE_ASSET_DEFINITION_ID`, `SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID` - fee-asset label, scale, and definition ids inserted into ledger transaction metadata for local/testnet bootstrap commands and public contract-call gas metadata; local scale defaults to `9` and must be a nonnegative integer, and testnet gas metadata defaults to the canonical definition id because `xor#universal` is not guaranteed to be an active public gas alias
- `SORASWAP_TESTNET_FEE_ASSET_LABEL` - optional testnet gas metadata override; defaults to `SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID`
- `SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID`, `SORASWAP_PRODUCTION_FEE_ASSET_LABEL` - the production fee-asset definition id is mandatory for deploy/bootstrap/smoke/preflight; the label is optional and defaults to that exact id
- `SORASWAP_DEPLOY_SCOPE` - defaults to `full`; set to `foundation` for local isolated checks that should deploy only `n3x`, DLMM pool/router, epoch auction, and conditional escrow
- `SORASWAP_LEDGER_GAS_LIMIT` - optional gas limit for metadata-backed ledger/SNS bootstrap transactions; defaults to `2000000` and must be a positive integer
- `SORASWAP_PUBLIC_RUN_SUFFIX`, `SORASWAP_PUBLIC_BRIDGE_ROUTE`, `SORASWAP_PUBLIC_BRIDGE_RECENT_LIMIT`, `SORASWAP_PUBLIC_BRIDGE_MESSAGE_ID` - optional shared public-env overrides used by the generic public smoke and contract-console wrappers before their built-in defaults; bridge recent limit must be a positive integer
- `SORASWAP_PUBLIC_SCCP_DESTINATION_PROOF_FILE`, `SORASWAP_PUBLIC_SCCP_NATIVE_PROOF_FILE` - runtime-only canonical Norito proof files required by public contract-console smoke; environment-specific `SORASWAP_TESTNET_*` and `SORASWAP_PRODUCTION_*` variants take precedence. Files must be nonempty and their contents are submitted but omitted from retained request evidence.
- `SORASWAP_CONTRACT_CONSOLE_HOST`, `SORASWAP_CONTRACT_CONSOLE_PORT`, `SORASWAP_CONTRACT_CONSOLE_HTTP_TIMEOUT_SECS`, `SORASWAP_CONTRACT_CONSOLE_TX_STATUS_ATTEMPTS`, `SORASWAP_CONTRACT_CONSOLE_TX_STATUS_RETRY_DELAY_SECS` - optional local bind, HTTP, and transaction-status polling controls for public contract-console smoke; host defaults to `127.0.0.1`, port defaults to `4273`, port must be a positive integer no greater than `65535`, the local HTTP timeout defaults to `60` seconds and must be a nonnegative number, transaction-status attempts default to `60` and must be positive, and status retry delay defaults to `2` seconds and must be nonnegative
- `SORASWAP_TESTNET_BRIDGE_MESSAGE_ID`, `SORASWAP_TESTNET_BRIDGE_RECENT_LIMIT` - optional debug overrides for `make test-contract-console-testnet` when you want to force a specific live SCCP message id or recent-message query window instead of using the defaults; bridge recent limit must be a positive integer
- `SORASWAP_TESTNET_BRIDGE_ROUTE` - optional bridge route override for testnet console smoke when the looked-up message bundle cannot derive the route
- `SORASWAP_TESTNET_RUN_SUFFIX` - optional suffix reused by the signed Taira smoke for mutable launchpad, referral, farm, perps, options, cover, and automation identifiers
- `SORASWAP_PRODUCTION_BRIDGE_MESSAGE_ID`, `SORASWAP_PRODUCTION_BRIDGE_ROUTE`, `SORASWAP_PRODUCTION_BRIDGE_RECENT_LIMIT`, `SORASWAP_PRODUCTION_RUN_SUFFIX` - optional production-wrapper equivalents used by the parallel `deployments/production` evidence family; bridge recent limit must be a positive integer
- `SORASWAP_TRADER_SMOKE_SWAP_IN` - optional signed public trader `route_swap` input amount; must be a positive JSON number and defaults to `10`
- `SORASWAP_PUBLIC_XOR_TOPUP_MAX_ATTEMPTS`, `SORASWAP_PUBLIC_XOR_TOPUP_MAX_USDT_IN`, `SORASWAP_PUBLIC_XOR_TOPUP_BUFFER` - optional shared public-env signer autofund controls used by the mutating public smoke before its built-in defaults; max attempts must be a positive integer, max USDT input must be a positive JSON number, and the buffer must be a nonnegative JSON number
- `SORASWAP_TESTNET_XOR_TOPUP_MAX_ATTEMPTS`, `SORASWAP_TESTNET_XOR_TOPUP_MAX_USDT_IN`, `SORASWAP_TESTNET_XOR_TOPUP_BUFFER` - optional testnet signer autofund controls for the mutating public smoke; they use the same validation rules as the shared controls and override them for Taira
- `SORASWAP_PRODUCTION_XOR_TOPUP_MAX_ATTEMPTS`, `SORASWAP_PRODUCTION_XOR_TOPUP_MAX_USDT_IN`, `SORASWAP_PRODUCTION_XOR_TOPUP_BUFFER` - optional production-wrapper equivalents used by `make smoke-production`; they use the same validation rules as the shared controls and override them for production
- `SORASWAP_PUBLIC_FAUCET_CLAIM_ATTEMPTS` - defaults to `3`; public Taira faucet claim retry budget for stale PoW puzzles and must be a positive integer
- `SORASWAP_LAUNCHPAD_SALE_ASSET_ID` - optional launchpad sale-asset override; local and signed Taira launchpad smoke default to `usdt#soraswap.universal` so the executor seeds the canonical `xor/usdt` DLMM pool
- `SORASWAP_LAUNCHPAD_POOL_QUOTE_ASSET_ID` - optional launchpad executor / DLMM quote-asset override; defaults to `usdt#soraswap.universal`
- `SORASWAP_RECOMMENDED_TX_GOSSIP_FRAME_CAP` - defaults to `1048576`; deploy scripts warn when live Taira is below this frame-cap budget, and it must be a positive integer
- `SORASWAP_CONTRACT_DEPLOY_MAX_TIME_SECS` - defaults to `45`; max request time for the public `/v1/contracts/deploy` wrapper before deploy recovery/fallback logic takes over, and must be a nonnegative number
- `SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_ATTEMPTS`, `SORASWAP_CONTRACT_DEPLOY_HTTP_RETRY_DELAY_SECS` - defaults to `5` and `3`; retry budget for transient public `/v1/contracts/deploy` transport failures and `queue_unresolved_route` / `PRTRY:ROUTE_UNRESOLVED` admission responses before the deploy wrapper records a hard failure. Attempts must be a positive integer, and delay seconds must be a nonnegative number.
- `SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS` - defaults to `SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS` (`900000`); optional `/v1/contracts/deploy` transaction TTL sent to patched public Torii runtimes so queued public deployments do not expire under congestion. Set to `0` to omit the field for legacy runtimes. It must be a nonnegative integer.
- `SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS` - defaults to `3600`; max request time for the multi-contract `contract app deploy` bundle path before the local/public deploy wrapper gives up. It must be a nonnegative integer; `0` skips writing a bundle-specific Torii request timeout.
- `SORASWAP_CONTRACT_APP_DEPLOY_ATTEMPTS` - defaults to `3`; retry budget for resuming a timed-out multi-contract app deploy. It must be a positive integer.
- `SORASWAP_CONTRACT_APP_DEPLOY_PROCESS_TIMEOUT_SECS` - defaults to `SORASWAP_CONTRACT_APP_DEPLOY_MAX_TIME_SECS + 120` when the bundle request timeout is enabled; bounds the local `iroha contract app deploy/resume` process so a stuck client can fall back to direct per-contract deploy. Set to `0` to disable the process guard. It must be a nonnegative integer.
- `SORASWAP_CONTRACT_APP_ACTIVATION_MAX_TIME_SECS` - defaults to `180`; max wait for each bundle alias to resolve to its planned contract address before materializing deployment evidence. It must be a nonnegative integer. The isolated local smoke wrapper raises this to `600` by default because the full 25-contract bundle can spend several minutes inside one cold local commit.
- `SORASWAP_CONTRACT_APP_ACTIVATION_TICK_BLOCKS`, `SORASWAP_CONTRACT_APP_ACTIVATION_TICK_INTERVAL_SECS` - local activation waits can submit no-wait ping ticks to advance block-height-gated activation; ticks are disabled on public configs and throttled to every `10` seconds by default to avoid flooding a stalled local queue. Tick blocks must be a boolean flag (`0`, `1`, `true`, `false`, `yes`, `no`, `on`, or `off`), and the interval must be a nonnegative integer.
- `SORASWAP_DEPLOY_PIPELINE_WAIT_SECS`, `SORASWAP_DEPLOY_COMMITTED_WAIT_SECS`, `SORASWAP_DEPLOY_MANIFEST_WAIT_SECS`, `SORASWAP_DEPLOY_NONCE_WAIT_SECS` - default to `300`, `120`, `180`, and `120`; control live deploy revalidation windows for pipeline status, committed transaction lookup, manifest visibility, and deploy-nonce visibility during deploy recovery plus post-deploy bootstrap. `SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS` defaults to `2` and bounds each CLI transaction/deploy-nonce lookup inside those longer waits so a stalled public read cannot consume the full revalidation window. Wait windows and lookup command timeouts must be nonnegative integers; setting `SORASWAP_DEPLOY_NONCE_WAIT_SECS=0` skips only the deploy-nonce projection wait after contract code/manifest evidence is visible, while setting `SORASWAP_TX_LOOKUP_COMMAND_TIMEOUT_SECS=0` disables the per-command timeout.
- `SORASWAP_DEPLOY_PROGRESS_LOG` - defaults to `1`; emits deploy recovery stage notes even when output is captured, which keeps public deploy evidence diagnosable. Set to `0` to silence these notes.
- `SORASWAP_CONTRACT_CALL_MAX_TIME_SECS` - defaults to `120`; max request time for signed `/v1/contracts/call` mutations before the wrapper fails the request, and must be a nonnegative number
- `SORASWAP_CONTRACT_CALL_RETRY_COUNT`, `SORASWAP_CONTRACT_CALL_RETRY_DELAY_SECS` - default to `4` and `2`; signed `/v1/contracts/call` mutations pin one `creation_time_ms` per logical call and retry transient transport or wrapped submit failures such as `502/503/504` with the same request body, so the retry preserves transaction identity instead of creating a second non-idempotent operation. The retry count must be a positive integer and the delay must be a nonnegative number.
- `SORASWAP_CONTRACT_CALL_TRANSACTION_TTL_MS` - defaults to `900000`; optional `/v1/contracts/call` transaction TTL sent to patched public Torii runtimes so queued mutations do not expire under congestion. Local calls use this value directly. Bundle deploy init calls inherit this TTL through `SORASWAP_CONTRACT_DEPLOY_TRANSACTION_TTL_MS` unless overridden. Set to `0` to omit the field for legacy runtimes. It must be a nonnegative integer.
- `SORASWAP_PUBLIC_CONTRACT_CALL_TRANSACTION_TTL_MS` - defaults to `1800000`; public `/v1/contracts/call` transaction TTL used for signed Taira/production mutations so transactions that enter a saturated public queue do not expire before finality catches up. Set to `0` only when diagnosing a legacy public runtime that rejects the TTL field. It must be a nonnegative integer.
- `SORASWAP_ACCEPT_PIPELINE_APPLIED_WITHOUT_COMMITTED_TX` - defaults to `auto`; public environments accept terminal pipeline `Applied|Committed` when committed transaction lookup cannot decode the public response, while local environments remain strict unless overridden. Values must be `auto`, `0`, `1`, `true`, `false`, `yes`, `no`, `on`, or `off`.
- `SORASWAP_PUBLIC_TX_COMMITTED_WAIT_SECS` - defaults to unset; public contract-call visibility waits use `max(SORASWAP_TX_COMMITTED_WAIT_SECS, 300)` while local waits keep `SORASWAP_TX_COMMITTED_WAIT_SECS`. Set it to a nonnegative integer only when public pipeline/committed transaction projection is consistently faster or slower than that default.
- `SORASWAP_PUBLIC_TX_WAIT_QUEUED_STALL_MAX_MS` - defaults to `180000`; public contract-call visibility waits fail with a public finality blocker when `/status` or `/v1/sumeragi/status` shows queued or age-saturated writes and no committed block has appeared within this many milliseconds. Set to `0` only for diagnosis, not release evidence.
- `SORASWAP_PIPELINE_APPLIED_COMMITTED_VERIFY_SECS` - defaults to `5`; short committed-transaction decode attempt before the public pipeline-only fallback is used, and must be a nonnegative integer
- `SORASWAP_CONTRACT_VIEW_MAX_TIME_SECS`, `SORASWAP_TORII_READ_MAX_TIME_SECS` - optional public-node timeout controls for `/v1/contracts/view` and read-only Torii queries; useful when `taira.sora.org` is intermittently resetting or stalling connections. Both values must be nonnegative numbers.
- `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_COUNT`, `SORASWAP_CONTRACT_VIEW_EXPECT_RETRY_DELAY_SECS` - default to `60` and `2`; bounded read-after-write visibility retry controls for public smoke views that must observe a just-applied mutation before later assertions reuse that view result. The retry count must be a positive integer and the delay must be a nonnegative number.
- `SORASWAP_TORII_READ_RETRY_COUNT`, `SORASWAP_TORII_READ_RETRY_DELAY_SECS` - defaults to `6` and `2`; bounded retry budget for transient public read failures from shared Torii read helpers, including contract views and code-byte probes. The retry count must be a positive integer and the delay must be a nonnegative number.
- `SORASWAP_PUBLIC_WRITE_HEALTH_QUEUE_MAX`, `SORASWAP_PUBLIC_WRITE_HEALTH_QC_LAG_MAX`, `SORASWAP_PUBLIC_WRITE_HEALTH_AGE_MAX_MS`, `SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_COUNT`, `SORASWAP_PUBLIC_WRITE_HEALTH_RETRY_DELAY_SECS`, `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_COUNT`, `SORASWAP_PUBLIC_SUBMIT_HEALTH_RETRY_DELAY_SECS` - default to `10`, `8`, `30000`, `3`, `5`, `24`, and `5`; preflight and signed public mutation wrappers sample `/status` and `/v1/sumeragi/status`, use the longer submit retry window before long write flows and before each public contract-call submission, and continue transaction visibility waits until terminal/committed status, the elapsed public visibility timeout, or the queued-write finality-stall threshold above. Release-ready preflight must record `endpoint.health_issues: []`, so non-JSON health endpoints or persistent write-health degradation block before any signed phase. When a public visibility timeout expires, the wait rechecks write health and exits as a public finality/write-health blocker when Taira is still degraded instead of reporting a contract assertion failure. They refuse to start or submit when public Torii persistently reports no committed blocks, no recent committed block within the age threshold, capacity/byte-saturated or oversized transaction queues, age-only queue pressure whose oldest queued transaction is at or above the age threshold, missing/timeout view-change causes, or excessive highest-QC versus committed-QC lag after the relevant retry window. Integer thresholds and retry counts must be nonnegative integers, and retry delays must be nonnegative numbers; set the age threshold to `0` only when diagnosing immediate runtime age-pressure signals.
- `SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_COUNT`, `SORASWAP_CONTRACT_ALIAS_RESOLVE_RETRY_DELAY_SECS` - defaults to `5` and `1`; bounded retry budget for transient public `/v1/contracts/aliases/resolve` read failures such as edge `502/503/504` responses. The retry count must be a positive integer and the delay must be a nonnegative number.
- `SORASWAP_CHAIN_FINGERPRINT_ATTEMPTS`, `SORASWAP_CHAIN_FINGERPRINT_SLEEP_SECS` - optional retry controls for live block-1 chain fingerprint reads; defaults are `15` attempts and `1` second between attempts. Attempts must be a nonnegative integer, and sleep seconds must be a nonnegative number.
- `SORASWAP_TRIGGER_EXECUTE_TIMEOUT_MS`, `SORASWAP_TRIGGER_EXECUTE_POLL_INTERVAL_MS` - optional by-call trigger execution wait controls for `iroha trigger execute`; defaults are `SORASWAP_TX_COMMITTED_WAIT_SECS * 1000` and `1000`. Execute timeout must be a nonnegative integer, and poll interval must be a positive integer.
- `SORASWAP_TRIGGER_COMPLETION_TIMEOUT_MS`, `SORASWAP_TRIGGER_COMPLETION_CAPTURE_WARMUP_SECONDS`, `SORASWAP_TRIGGER_COMPLETION_PROBE_MS`, `SORASWAP_TRIGGER_COMPLETION_PROBE_LIMIT` - optional trigger completion evidence controls used by local/public smoke and readonly public probes. Completion timeout/probe windows must be nonnegative integers, capture warmup must be a nonnegative number, and probe limits must be positive integers.
- `SORASWAP_EPOCH_AUCTION_CLOSE_WAIT_ATTEMPTS` - optional mutating-smoke wait budget for proving the epoch-auction pre-commit trigger closes the current epoch and self-disables after `epoch_end_slot`
- `SORASWAP_LOCALNET_DIR` - optional override for the generated localnet directory
- `SORASWAP_LOCALNET_BASE_API_PORT` - optional localnet API port root override; useful when another local Nexus already occupies `8080-8082`. It must be a positive integer no greater than `65535`.
- `SORASWAP_LOCALNET_BASE_P2P_PORT` - optional localnet P2P port root override; useful when another local Nexus already occupies `1337+`. It must be a positive integer no greater than `65535`.
- `SORASWAP_LOCALNET_CONSENSUS_MODE` - optional localnet consensus override; defaults to `npos` for `local_up.sh` and `permissioned` for `tests/isolated_e2e.sh`
- `SORASWAP_LOCALNET_BLOCK_TIME_MS`, `SORASWAP_LOCALNET_COMMIT_TIME_MS` - optional Kagami timing overrides passed through by `local_up.sh`; the isolated local smoke defaults both to `5000` to avoid fast-profile quorum churn during cold contract deployment. When set, each must be a positive integer.
- `SORASWAP_RUN_TESTNET_SMOKE` - optional `0`/`1` flag for `tests/isolated_e2e.sh`; set to `1` only when the isolated local client should also run the testnet smoke wrapper after local smoke
- `SORASWAP_LOCALNET_COMMIT_INFLIGHT_TIMEOUT_MS` - optional override for `[sumeragi.persistence].commit_inflight_timeout_ms` in generated local peer configs; SoraSwap defaults it to `120000` so cold DLMM deploy and trigger-heavy pre-commit blocks do not stall behind Kagami's tighter localnet cap. It must be a positive integer.
- `SORASWAP_BOOTSTRAP_VIEW_RETRY_ATTEMPTS`, `SORASWAP_BOOTSTRAP_VIEW_RETRY_SLEEP_SECS` - optional bootstrap typed-view retry budget; defaults to `15` attempts locally and `60` attempts on public testnet/production, with `1` second between attempts. Attempts must be a nonnegative integer, and sleep seconds must be a nonnegative number.
- `SORASWAP_BOOTSTRAP_APPLY_RETRY_ATTEMPTS`, `SORASWAP_BOOTSTRAP_APPLY_RETRY_SLEEP_SECS` - optional retry budget for idempotent bootstrap init/setter/bind/sync/lifecycle operations whose postcondition is not visible yet; defaults to `1` attempt locally and `3` attempts on public testnet/production, with `3` seconds between attempts.
- `SORASWAP_WARM_VIEW_TIMEOUT_SECS` - optional per-view timeout used only by bootstrap prewarm calls; defaults to `5` so a cold diagnostic view cannot stall the whole isolated bootstrap, and must be a nonnegative number
- `SORASWAP_LOCALNET_GUEST_STACK_BYTES` - optional localnet guest stack override; defaults to `8388608` so DLMM swap smoke has an `8 MiB` guest stack budget. It must be a positive integer.
- `SORASWAP_LOCALNET_GAS_TO_STACK_MULTIPLIER` - optional localnet gas-to-stack multiplier override; defaults to `8` so the DLMM pool can use the raised guest stack budget at its current `max_cycles`. It must be a positive integer.
- `SORASWAP_LOCALNET_MEMORY_BUDGET_PROFILE` - optional localnet IVM memory-budget profile name; defaults to `soraswap-dlmm`
- `SORASWAP_LOCALNET_MAX_STACK_BYTES` - optional localnet compute-profile stack cap override; defaults to the same value as `SORASWAP_LOCALNET_GUEST_STACK_BYTES`. It must be a positive integer.
- `KAGAMI_BIN`, `IROHAD_BIN`, `IROHA_BIN` - optional explicit localnet tool paths. When any is set, `scripts/local_up.sh` verifies all three paths and forwards them to `../iroha/scripts/deploy_localnet.sh` instead of rebuilding or reusing binaries under `../iroha/target/debug`.
- `SORASWAP_LOCAL_ACCEPTANCE_IROHA_ROOT`, `SORASWAP_LOCAL_ACCEPTANCE_BUNDLE_DIR`, `SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA` - optional all-or-none `make release-checklist` pin for an exact Iroha release candidate and mandatory input to a full public release. The candidate must be a clean Git worktree at the exact signed commit. The bundle manifest must attest `git_signature_verified: true`, exactly `embedded-soracloud-runtime` plus `sccp-test-fixtures`, and both required SoraSwap regressions; both `bin/irohad` and `bin/iroha` must independently embed the full SHA. `sha256sums.txt` must be canonical, sorted, duplicate-free, newline-terminated, and cover every regular bundle file exactly. The sibling `<bundle>.tar.gz` and canonical `.tar.gz.sha256` sidecar are mandatory, and every archive member, byte, type, and file mode must match the directory. `target/release/kagami` must be current. Candidate-aware isolated checks retain zero wrapper/process timeouts so their internally scoped cleanup is not replaced by a name-wide timeout signal path. The checklist freezes and repeatedly revalidates all candidate and archive identities before and after candidate-using gates.
- Phase 12 inside `make release-taira` and `make release-production` is a fail-closed, two-step status-doc closeout. Full prepare and resume require the three exact-candidate pins plus `SORASWAP_RELEASE_EXPECTED_GIT_SHA`, which must equal a verifiably signed SoraSwap RC commit. A pending checkpoint or journal for either environment is a global release lock. Before phase 1, the runner validates both signed commits and source trees, then atomically creates a mode-`0600` ignored phase journal. Every phase snapshots its exact artifact paths before dispatch and must atomically regenerate file identity, bytes, hash, and fresh `generated_at`; the nested-call phase is forced instead of reusing a current probe. Phases 1–11 append exact numbered receipt files, and journal verification requires the fixed target/artifact mapping, one chain fingerprint, and one phase-5 deploy/contracts snapshot. Phase 12 rejects incomplete, reordered, duplicate, escaping, symlinked, hard-linked, wrong-mode, stale, or mixed-snapshot state, read-back verifies the new mode-`0600` checkpoint, then consumes the receipts and exits pending. The checkpoint binds the signed RC/tree, HEAD-tree source, staged/worktree status-doc equality, absence of staged non-status changes and non-ignored untracked source, evidence/timestamps, RWA mode, receipts, and candidate/archive hashes. Stage only validated status-doc content, then resume with the same pins. Resume performs no signed mutation or local E2E; it runs redaction/static gates plus `git diff --cached --check`, `git diff --check`, and `git diff HEAD --check`, and production also revalidates Taira. Only successful resume removes the exact reverified checkpoint. `make test-release-closeout` covers these adversarial paths.
- `SORASWAP_INIT_CONTRACT_STATE` - defaults to `1` on public deploys and must be `0` or `1`; set to `0` only for an explicit standalone debug bypass of post-deploy init. Release runners reject `SORASWAP_INIT_CONTRACT_STATE=0`, and release evidence requires the deploy report's `bootstrap_contract_state` phase to be completed.
- `SORASWAP_BOOTSTRAP_SCOPE` - defaults to `full`; must be `foundation` or `full`. Use `foundation` to stop post-deploy initialization after `n3x` plus DLMM setup.
- `SORASWAP_POOL_FEE_PIPS`, `SORASWAP_POOL_ACTIVE_BIN`, `SORASWAP_DLMM_RANGE_GOVERNOR_CADENCE_SLOTS`, `SORASWAP_DLMM_RANGE_GOVERNOR_MAX_FEE_PIPS`, `SORASWAP_DLMM_RANGE_GOVERNOR_TARGET_ACTIVE_BIN`, `SORASWAP_DLMM_RANGE_GOVERNOR_MAX_ACTIVE_BIN_DRIFT`, `SORASWAP_DLMM_RANGE_GOVERNOR_ENABLED` - optional DLMM bootstrap/range-governor controls. Fee pips must be nonnegative integers below `1000000`, drift values must be nonnegative integers, cadence must be positive, enabled must be `0` or `1`, and active-bin values may be signed integers.
- `SORASWAP_TRIGGER_LIFECYCLE_CADENCE_SLOTS`, `SORASWAP_TRIGGER_LIFECYCLE_MAX_ITEMS`, `SORASWAP_TRIGGER_LIFECYCLE_ENABLED`, `SORASWAP_PERPS_TRIGGER_LIFECYCLE_MAX_ITEMS`, `SORASWAP_TWAMM_TRIGGER_CADENCE_SLOTS`, `SORASWAP_TWAMM_TRIGGER_MAX_ORDERS_PER_TICK`, `SORASWAP_TWAMM_TRIGGER_ENABLED` - optional bootstrap trigger controls. Cadences and batch sizes must be positive integers, enabled values must be `0` or `1`, product lifecycle triggers default to enabled, shared lifecycle/TWAMM batches cap at `16`, and perps lifecycle batches cap at `4`.
- `SORASWAP_EPOCH_AUCTION_EPOCH_ID`, `SORASWAP_EPOCH_AUCTION_DURATION_SLOTS`, `SORASWAP_EPOCH_AUCTION_LOWER_TICK`, `SORASWAP_EPOCH_AUCTION_UPPER_TICK`, `SORASWAP_EPOCH_AUCTION_TICK_STEP`, `SORASWAP_EPOCH_AUCTION_MAX_ORDERS` - optional epoch-auction bootstrap controls. Epoch IDs must be nonnegative, duration/ticks/step/max orders must be positive, upper tick must be greater than or equal to lower tick, and max orders caps at `256`.
- `SORASWAP_SMOKE_SCOPE` - defaults to `full`; must be `foundation` or `full`. Set to `foundation` to skip launchpad, referral, farms, perps, options, cover, and automation smoke mutations.
- `SORASWAP_SMOKE_BLOCK_WAIT_ATTEMPTS`, `SORASWAP_SMOKE_BLOCK_WAIT_TICK` - local smoke block-height wait controls; defaults are `900` attempts and `1` ping tick per unchanged observed height so trigger-heavy pre-commit flows can advance gated slots without an external transaction source. Attempts must be a positive integer, and the tick flag must be one of `0`, `1`, `true`, `false`, `yes`, `no`, `on`, or `off`.
- `SORASWAP_LOCAL_SMOKE_PAUSE_PERIODIC_TRIGGERS` - optional local smoke `0`/`1` flag; defaults to `1`. Local smoke pauses the DLMM range-governor and TWAMM periodic time triggers during mutation-heavy checks, then restores them before collecting trigger evidence so retained local reports still prove the required active trigger set.
- `SORASWAP_TREASURY_ACCOUNT`, `SORASWAP_TREASURY_SEED_BALANCE` - optional overrides for the treasury/vault account and helper-asset seed balance used during post-deploy init; the seed balance defaults to `1000000` and must be a positive integer
- `SORASWAP_BRIDGE_PROOF_AUTHORITY` - optional bridge proof authority; bootstrap defaults it to the deployment authority and enforces it through `bridge_authorities()`
- `SORASWAP_ORACLE_PUBLIC_KEY_HEX` - optional override for the bootstrap and smoke oracle public key; raw 32-byte Ed25519 public keys and Iroha `ed0120...` public keys are accepted and normalized before contract init, and public configs default to the client config signer when this is unset
- `SORASWAP_ORACLE_PRIVATE_KEY_HEX` - optional runtime override consumed by the shell wrapper; it is copied over stdin into a mode-`0600` identity-owned file and never placed in argv. Direct `scripts/oracle_payload.py` signing requires `--private-key-file`; public configs default to a file-backed extraction of the client config signer when the override is unset
- `SORASWAP_ORACLE_PYTHON_BIN` - optional Python interpreter override for oracle payload signing; it must be able to import `nacl.signing`
- `SORASWAP_ORACLE_SCHEME` - defaults to `1` for Ed25519 signatures over the exact raw UTF-8 JSON oracle payload bytes and must be a positive integer
- `SORASWAP_POOL_SEED_BASE`, `SORASWAP_POOL_SEED_QUOTE`, `SORASWAP_POOL_SEED_NEXT_BASE`, `SORASWAP_POOL_SEED_NEXT_QUOTE`, `SORASWAP_POOL_SEED_FAR_BASE`, `SORASWAP_POOL_SEED_FAR_QUOTE` - optional bootstrap liquidity overrides; values must be nonnegative integers
- `SORASWAP_POOL_POSITION_ID`, `SORASWAP_POOL_POSITION_BASE`, `SORASWAP_POOL_POSITION_QUOTE`, `SORASWAP_POOL_POSITION_MIN_SHARES_OUT`, `SORASWAP_POOL_POSITION_REMOVE_SHARES` - optional DLMM smoke position controls. Local smoke defaults position base/quote to `500`; public mutating smoke defaults them to `200000` so the run-scoped active-bin position can accrue and then collect fees after the live route swap. Position amounts and minimum shares must be nonnegative integers
- `SORASWAP_POOL_BIN_STEP`, `SORASWAP_POOL_IMPACT_CAP_BPS`, `SORASWAP_POOL_MIN_RESERVE_BASE`, `SORASWAP_POOL_MIN_RESERVE_QUOTE`, `SORASWAP_POOL_MAX_BINS_PER_SWAP`, `SORASWAP_POOL_BIN_LIQUIDITY_CAP` - optional DLMM risk guard overrides. Bin step and max bins per swap must be positive integers, other values must be nonnegative integers, and a nonzero bin liquidity cap must be greater than or equal to both reserve floors.
- `SORASWAP_POOL_SMOKE_SWAP_IN` - DLMM quote/swap input used by local and public smoke flows; public smoke validates it as a positive JSON number and defaults to `1500`
- `SORASWAP_ASSERT_BOOTSTRAP_STATE` - optional `0`/`1` readonly public smoke assertion that compares live pool state with bootstrap defaults; leave unset for normal release evidence
- `SORASWAP_ROUTER_BIN_QUOTE_IN` - router `quote_bin` sample amount used by smoke flows
- `SORASWAP_N3X_VAULT_ACCOUNT`, `SORASWAP_DLMM_POOL_VAULT_ACCOUNT` - optional custody-account overrides for bootstrap repair and custom environments; bootstrap now targets the current deployed contract subjects by default and, on public `testnet|production`, migrates seeded balances forward from previous contract-subject custody when contracts are upgraded
- `SORASWAP_N3X_SMOKE_USDT_IN`, `SORASWAP_N3X_SMOKE_USDC_IN`, `SORASWAP_N3X_SMOKE_KUSD_IN`, `SORASWAP_N3X_TARGET_USDT_BPS`, `SORASWAP_N3X_TARGET_USDC_BPS`, `SORASWAP_N3X_TARGET_KUSD_BPS`, `SORASWAP_N3X_MINT_FEE_BPS`, `SORASWAP_N3X_REDEEM_FEE_BPS` - optional `n3x` smoke controls for basket inputs, target weights, and fee configuration; bootstrap target weights must be nonnegative bps values that sum to `10000`, and mint/redeem fees must be `0..9999`
- `SORASWAP_SALE_NAME`, `SORASWAP_LAUNCHPAD_SMOKE_PAYMENT_AMOUNT`, `SORASWAP_LAUNCHPAD_SMOKE_ALLOCATION_ID`, `SORASWAP_LAUNCHPAD_CLAIM_INVENTORY_AMOUNT`, `SORASWAP_LAUNCHPAD_CLAIM_SLOT`, `SORASWAP_LAUNCHPAD_CLAIM_DELAY_SLOTS`, `SORASWAP_LAUNCHPAD_SEED_PAYMENT_AMOUNT`, `SORASWAP_LAUNCHPAD_SEED_SALE_AMOUNT`, `SORASWAP_LAUNCHPAD_SEED_BIN_ID`, `SORASWAP_LAUNCHPAD_SEED_POSITION_ID`, `SORASWAP_REFUND_SALE_NAME`, `SORASWAP_REFUND_ALLOCATION_ID`, `SORASWAP_REFUND_PAYMENT_AMOUNT`, `SORASWAP_REFUND_SOFT_CAP`, `SORASWAP_REFUND_SALE_CLAIM_DELAY_SLOTS` - optional launchpad smoke controls for recorded allocations, claim inventory, refunds, and the explicit DLMM seed plan. If `SORASWAP_LAUNCHPAD_CLAIM_SLOT` is unset, smoke derives it from current block height plus `SORASWAP_LAUNCHPAD_CLAIM_DELAY_SLOTS`, which defaults to `12`; the refund-sale fixture derives its own future claim slot from the current block height plus `SORASWAP_REFUND_SALE_CLAIM_DELAY_SLOTS`, which defaults to `120`, so lifecycle automation cannot preempt the explicit refund-sale close transaction. If the absolute launchpad slot is set, it must be greater than the current block height when lifecycle triggers are active.
- `SORASWAP_REFERRAL_SMOKE_MEMBER`, `SORASWAP_REFERRAL_SMOKE_PARENT_MEMBER`, `SORASWAP_REFERRAL_SMOKE_CLAIM_THRESHOLD`, `SORASWAP_REFERRAL_SMOKE_ACCRUAL`, `SORASWAP_REFERRAL_SMOKE_DIRECT_SHARE_BPS`, `SORASWAP_REFERRAL_SMOKE_PARENT_SHARE_BPS` - optional referral smoke controls for the routed child and parent member settlement path; bootstrap claim threshold must be positive and direct/parent shares must be nonnegative bps values that sum to `10000`
- `SORASWAP_FARM_SMOKE_REWARD_FUND`, `SORASWAP_FARM_SMOKE_STAKE_AMOUNT`, `SORASWAP_FARM_SMOKE_UNSTAKE_AMOUNT`, `SORASWAP_FARM_SMOKE_CLAIM_SLOT`, `SORASWAP_FARM_SMOKE_UNSTAKE_SLOT` - optional farms smoke controls for the slot-synced accrual path
- `SORASWAP_INTENT_SMOKE_DEADLINE_SLOT`, `SORASWAP_INTENT_SMOKE_DEADLINE_OFFSET_SLOTS`, `SORASWAP_VAULT_SMOKE_STRATEGY_CODE`, `SORASWAP_VAULT_SMOKE_ASYNC_REDEEM`, `SORASWAP_VAULT_SMOKE_CLAIM_SLOT`, `SORASWAP_VAULT_SMOKE_CLAIM_DELAY_SLOTS` - optional intent and vault smoke controls; defaults are derived from current chain height because fills and redemption claims use contract `block_height()`. Vault strategy code must be nonnegative, and async redeem must be `0` or `1`.
- `SORASWAP_PERPS_SMOKE_FUNDING_BPS`, `SORASWAP_PERPS_SMOKE_MAX_LEVERAGE_BPS`, `SORASWAP_PERPS_SMOKE_MAINTENANCE_MARGIN_BPS`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_FEE_BPS` - optional perps bootstrap defaults for market funding and guard configuration; funding may be signed, max leverage must be greater than `10000`, maintenance margin must be `1..10000`, and liquidation fee must be `0..10000`
- `SORASWAP_PERPS_MARKET_OPEN_INTEREST_CAP`, `SORASWAP_PERPS_MARKET_FUNDING_INTERVAL_SLOTS`, `SORASWAP_PERPS_MARKET_ORACLE_STALE_SLOTS`, `SORASWAP_PERPS_MARKET_BACKLOG_LIMIT`, `SORASWAP_PERPS_MARKET_UTILISATION_CLAMP_BPS`, `SORASWAP_PERPS_MARKET_LIQUIDATION_STRESS_LIMIT` - optional perps market registration overrides for the shared derivatives stack; open-interest cap must be positive, cadence/stale/backlog/stress values must be nonnegative integers, and utilisation clamp must be `0..10000`
- `SORASWAP_PERPS_SMOKE_POSITION`, `SORASWAP_PERPS_SMOKE_SIZE`, `SORASWAP_PERPS_SMOKE_COLLATERAL`, `SORASWAP_PERPS_SMOKE_ADD_COLLATERAL`, `SORASWAP_PERPS_SMOKE_REMOVE_COLLATERAL`, `SORASWAP_PERPS_SMOKE_REQUESTED_LEVERAGE_BPS`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_REQUESTED_LEVERAGE_BPS`, `SORASWAP_PERPS_SMOKE_ENTRY_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_FUNDING_MARK_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_FUNDING_INDEX_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_EXIT_MARK_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_COLLATERAL`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_STRESS_MARK_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_HEALTHY_MARK_PRICE_BPS`, `SORASWAP_PERPS_SMOKE_LIQUIDATION_SCAN_LIMIT` - optional perps smoke controls for the normal open/funding/margin/close path plus the automatic queue/recover/liquidate rehearsal; the liquidation path uses its own requested leverage so lower-margin liquidation fixtures can stay valid against the market max leverage check
- `SORASWAP_OPTIONS_SHOUT_TENOR_SLOTS`, `SORASWAP_OPTIONS_OUTPERFORMANCE_TENOR_SLOTS`, `SORASWAP_OPTIONS_SHOUT_STRIKE_BPS`, `SORASWAP_OPTIONS_OUTPERFORMANCE_STRIKE_BPS`, `SORASWAP_OPTIONS_COLLATERAL_MULTIPLIER_BPS`, `SORASWAP_OPTIONS_SHOUT_BASE_PREMIUM_BPS`, `SORASWAP_OPTIONS_OUTPERFORMANCE_BASE_PREMIUM_BPS`, `SORASWAP_OPTIONS_SHOUT_EXPIRY_SLOT`, `SORASWAP_OPTIONS_OUTPERFORMANCE_EXPIRY_SLOT`, `SORASWAP_OPTIONS_SHOUT_MAX_NOTIONAL`, `SORASWAP_OPTIONS_OUTPERFORMANCE_MAX_NOTIONAL`, `SORASWAP_OPTIONS_ORACLE_STALE_SLOTS` - optional options template, series, and oracle freshness bootstrap overrides; tenor/strike/collateral/premium/max-notional values must be positive integers, and expiry/stale slots must be nonnegative integers
- `SORASWAP_OPTIONS_GUARD_BUMP_ACTIVATE_BPS`, `SORASWAP_OPTIONS_GUARD_BUMP_DEACTIVATE_BPS`, `SORASWAP_OPTIONS_GUARD_PAUSE_THRESHOLD_BPS`, `SORASWAP_OPTIONS_GUARD_BUMP_PERCENT_BPS` - optional options factory utilisation-guard overrides; activate/deactivate/pause thresholds must be `0..10000`, and bump percent must be nonnegative
- `SORASWAP_OPTIONS_SHOUT_SMOKE_NOTIONAL`, `SORASWAP_OPTIONS_SHOUT_SMOKE_PREMIUM_PAID`, `SORASWAP_OPTIONS_SHOUT_SMOKE_COLLATERAL_LOCKED`, `SORASWAP_OPTIONS_SHOUT_SMOKE_RECORD_MARK_BPS`, `SORASWAP_OPTIONS_SHOUT_SMOKE_EXERCISE_MARK_BPS`, `SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_NOTIONAL`, `SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_PREMIUM_PAID`, `SORASWAP_OPTIONS_OUTPERFORMANCE_SMOKE_COLLATERAL_LOCKED`, `SORASWAP_OPTIONS_OUTPERFORMANCE_FINAL_MARK_BPS`, `SORASWAP_OPTIONS_OUTPERFORMANCE_FINAL_QUOTE_MARK_BPS` - optional local active options smoke controls for shout and outperformance buy/settle/exercise flows
- `SORASWAP_COVER_REQUIRED_OBSERVATIONS`, `SORASWAP_COVER_ORACLE_STALE_SLOTS`, `SORASWAP_COVER_POLICY_ID_SCAN_LIMIT`, `SORASWAP_COVER_SMOKE_NOTIONAL`, `SORASWAP_COVER_SMOKE_PAYOUT_AMOUNT`, `SORASWAP_COVER_SMOKE_PREMIUM_PAID`, `SORASWAP_COVER_SMOKE_LOWER_BOUND`, `SORASWAP_COVER_SMOKE_UPPER_BOUND`, `SORASWAP_COVER_SMOKE_TRIGGER_PRICE`, `SORASWAP_COVER_SMOKE_WINDOW_SLOTS`, `SORASWAP_COVER_SMOKE_POLICY_REQUIRED_OBSERVATIONS`, `SORASWAP_COVER_CLAIMABLE_OBSERVATION_MAX_ATTEMPTS` - optional cover bootstrap and active smoke controls, including the degraded-oracle reset drill; bootstrap required observations, policy-id scan limit, cover smoke window, and claimable-observation attempts must be positive, oracle stale slots must be nonnegative, bootstrap plus local/public mutating smoke default the cover oracle stale window to `120` slots, local cover smoke defaults the monitoring window to `10` slots with `8` claimable-observation attempts, public mutating smoke defaults the monitoring window to `60` slots with `12` claimable-observation attempts so live trigger expiry does not race the degraded-reset drill, and the policy-id scan defaults to `16` locally but `256` on public `testnet|production` so release bootstraps still advance the cover policy cursor past used risk-vault bucket-3 liability ids
- `SORASWAP_RISK_BUCKET_1_BOOTSTRAP_DEPOSIT`, `SORASWAP_RISK_BUCKET_2_BOOTSTRAP_DEPOSIT`, `SORASWAP_RISK_BUCKET_3_BOOTSTRAP_DEPOSIT` - optional shared risk-vault bootstrap funding overrides for buckets `1=perps`, `2=options`, `3=cover`; the signed Taira flow now seeds bucket `1` with `200` by default so the live perps smoke uses the same funded baseline as the local rehearsal, and bootstrap deposit overrides must be nonnegative integers
- `SORASWAP_BRIDGE_LISTING_FEE_AMOUNT`, `SORASWAP_BRIDGE_REMOTE_DOMAIN`, `SORASWAP_BRIDGE_ASSET_HOME_DOMAIN`, `SORASWAP_BRIDGE_ASSET_DECIMALS`, `SORASWAP_BOOTSTRAP_SIGNER_FEE_MINIMUM`, `SORASWAP_BOOTSTRAP_MAINTENANCE_GAS_LIMIT`, `SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_PIPELINE_WAIT_SECS`, `SORASWAP_BOOTSTRAP_CONTROLLER_SYNC_COMMITTED_WAIT_SECS` - optional bridge/bootstrap maintenance controls; bridge fee/domain/decimal values must be nonnegative integers, bootstrap fee reserve/gas values must be positive integers, and bounded controller-sync wait overrides must be nonnegative integers
- `SORASWAP_ENABLE_RWA_RELEASE` - optional `0`/`1` public release switch. Public `testnet|production` defaults to `0`, records RWA compliance evidence as `not_applicable`, skips RWA lot/redemption smoke mutations, and does not launch a real-world asset market. Set it to `1` only for an explicit RWA market launch with issuer approval, legal review, compliance policy, NAV source, and redemption terms references. Local flows default to `1` so RWA regressions stay covered.
- `SORASWAP_LAUNCH_VAULT_STRATEGY_CODE`, `SORASWAP_LAUNCH_VAULT_ASYNC_REDEEM`, `SORASWAP_LAUNCH_OPERATOR_MIN_BOND`, `SORASWAP_LAUNCH_OPERATOR_BOND`, `SORASWAP_LAUNCH_OPERATOR_HEARTBEAT_SLOT`, `SORASWAP_LAUNCH_OPERATOR_HEALTH_BPS`, `SORASWAP_LAUNCH_MARGIN_RISK_WEIGHT_BPS`, `SORASWAP_LAUNCH_MARGIN_LIQUIDATION_THRESHOLD_BPS`, `SORASWAP_LAUNCH_RWA_NAV`, `SORASWAP_LAUNCH_RWA_SHARES`, `SORASWAP_LAUNCH_DLMM_HOOK_PHASE`, `SORASWAP_LAUNCH_DLMM_HOOK_MAX_FEE_PIPS` - optional launch-surface bootstrap controls; async redeem is `0` or `1`, bond/RWA values must be positive, health and margin bps values must be `0..10000`, hook phase must be an integer, and hook max fee must be nonnegative
- `SORASWAP_AUTOMATION_SMOKE_JOB`, `SORASWAP_AUTOMATION_SMOKE_EXECUTOR`, `SORASWAP_AUTOMATION_SMOKE_NEXT_SLOT`, `SORASWAP_AUTOMATION_SMOKE_RESUME_SLOT`, `SORASWAP_AUTOMATION_SMOKE_RETRY_DELAY_SLOTS`, `SORASWAP_AUTOMATION_SMOKE_MAX_RETRIES`, `SORASWAP_AUTOMATION_SMOKE_CRON_INTERVAL_SLOTS` - optional automation smoke scheduler overrides

The public mutating smoke validates numeric scenario overrides before submitting signed calls: amount-style values must be positive or nonnegative JSON numbers as documented above, slot/count/scan/bps values must be integers in their documented domains, optional deadline/claim slots must be nonnegative when supplied, and `SORASWAP_POOL_FEE_PIPS` must stay below `1000000` so DLMM fee math cannot divide by zero.

## Local Nexus
`scripts/local_up.sh` generates and starts a fresh one-peer Kagami localnet in `tmp/iroha-localnet` using the sibling `../iroha` checkout and the Nexus/NPoS profile. It now also injects a SoraSwap-specific IVM stack profile into the generated peer config so DLMM swap smoke runs with an `8 MiB` guest stack budget by default, and raises the generated `sumeragi.persistence.commit_inflight_timeout_ms` to `120000` so cold large-contract deploy and trigger-heavy pre-commit blocks do not flap at the default localnet cap. When another local Nexus is already running, set `SORASWAP_LOCALNET_DIR`, `SORASWAP_LOCALNET_BASE_API_PORT`, and `SORASWAP_LOCALNET_BASE_P2P_PORT` to spin up an isolated verification localnet instead of reusing the default one. To validate a patched sibling checkout without waiting on the shared `../iroha/target` lock, build Iroha tools into a separate target directory and pass explicit `KAGAMI_BIN`, `IROHAD_BIN`, and `IROHA_BIN` paths.

Default local client config:
```bash
tmp/iroha-localnet/client.toml
```

Local bootstrap also acquires the `soraswap` SNS domain-name lease before registering the on-ledger `soraswap` domain, which is now required by current Nexus core. It then binds and tops up `xor#universal` as the base asset alongside the repo helper assets.

`iroha.contracts.toml` is the repo's canonical SoraSwap bundle manifest. `make deploy-local` compiles the listed contracts through the same manifest compiler wrapper as `make compile`, then hands the bundle to `../iroha` via `iroha contract app deploy --manifest iroha.contracts.toml` so address planning, alias binding, deploy receipts, and recovery semantics live in the platform instead of repo shell logic. Public `testnet|production` deploys default `SORASWAP_CONTRACT_APP_CHUNK_SIZE=1` so Taira never has to accept the full SoraSwap app in one consensus block; local deploys default to `0` unless explicitly overridden. Set `SORASWAP_CONTRACT_APP_CHUNK_SIZE=<n>` to choose a deterministic chunk size, or `0` to force a full-bundle submission in an environment known to handle it. Chunked deploys wait one block between chunks by default, tunable with `SORASWAP_CONTRACT_APP_CHUNK_WAIT_BLOCKS`, `SORASWAP_CONTRACT_APP_CHUNK_BLOCK_WAIT_ATTEMPTS`, `SORASWAP_CONTRACT_APP_CHUNK_TICK_BLOCKS`, and `SORASWAP_CONTRACT_APP_CHUNK_QUEUED_STALL_MAX_MS`; block-wait attempts default to `120` locally and `300` on public testnet/production, while queued-write stall detection defaults to disabled locally and `180000` ms on public testnet/production. Chunk size, wait blocks, and queued-stall milliseconds must be nonnegative integers, block-wait attempts must be a positive integer, and chunk ticks must be one of `0`, `1`, `true`, `false`, `yes`, `no`, `on`, or `off`. The wrapper still materializes the same per-contract evidence and writes an aggregate `soraswap.bundle.deploy.json` receipt stamped with `generated_at`, selected `environment`, and the current chain fingerprint when available, and deployment receipts, per-contract deploy records, and adjacent deployment manifests are published through the shared atomic JSON writer so interrupted runs do not leave malformed evidence files. The wrapper still runs `scripts/bootstrap_contract_state.sh` after activation so the foundational contracts have usable local state before smoke calls. Full bootstrap requires an oracle public key, initializes derivatives with the configured signer, binds the bridge proof authority, and verifies those singleton settings through typed views. The bootstrap is skip-and-verify: singleton init/config writes are skipped when their typed config views already match, and the DLMM seed block is only replayed when the current bin and position snapshots are still pristine. Each deploy now writes both the platform bundle receipt to `deployments/local/soraswap.bundle.deploy.json` and the materialized per-contract `deployments/local/<contract>.deploy.json` evidence used by the smoke/bootstrap flows, cleans stale per-contract records for sources no longer under `contracts/`, plus writes a timestamped `deployments/local/contracts.<utc>.json` snapshot of the whole local deployment set.

`make dev-doctor` and `make dev-smoke` use the selected profile client config for runtime checks, so run `make local-up` before using the default local profile. `make dev-smoke` first checks that generated artifacts are not stale, then runs the declarative `[[smoke]]` views/calls from `iroha.contracts.toml` through `iroha contract dev smoke`. If the local profile config is missing, lacks `torii_url`, or points at an unreachable Torii endpoint, `scripts/dev_iroha.sh` stops with the setup hint instead of surfacing a generic CLI config or connection failure. `make smoke-local` remains the domain-heavy integration rehearsal and writes a machine-readable report to `deployments/local/smoke.latest.json` plus a timestamped copy. Before writing retained smoke evidence, `make smoke-local` derives the current chain fingerprint from the selected local client config and stops with the `make local-up` setup hint if the fingerprint cannot be read. Successful reports carry top-level `status: "completed"`, `environment: "local"`, and non-null `chain_fingerprint` metadata. Local smoke pauses the DLMM range-governor and TWAMM periodic time triggers while it performs mutation-heavy checks, then restores them before trigger evidence is collected. That report separates committed mutation transaction hashes from typed `/v1/contracts/view` results, records registered/active trigger evidence plus by-call completion evidence, and records decoded integer snapshots for the `n3x`, deployable DLMM, launchpad, referral, farms, risk vault, perps, options, cover, and automation surfaces. The `n3x` section includes basket backing plus per-asset fee reserves, the launchpad section includes both sale-level claim/seed aggregates plus allocation refund state, and the referral section includes routed child-plus-parent settlement state. The derivatives section now signs raw UTF-8 JSON oracle payloads with `SORASWAP_ORACLE_PRIVATE_KEY_HEX`, uses contract `block_height()` for price-sensitive current-slot checks, and includes committed local write-path coverage for perps open/funding/margin/close plus queue/recover/requeue/liquidate, shout buy/record/exercise, outperformance buy/series settlement/exercise, and cover register/degraded-reset/claim, all routed through `risk_vault`.

## Public Testnet
The public testnet template lives at:
```bash
config/testnet/taira.client.toml.example
```

Copy it to an untracked `.toml`, set the correct credentials, then point `SORASWAP_CLIENT_CONFIG` at that file before running `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet`.
Use a fully qualified account domain in the copied config, for example `wonderland.universal`.

Use the non-mutating release preflight before the signed release gate when setting up a workstation or diagnosing public Taira:

```bash
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight
```

It writes `deployments/testnet/preflight.latest.json`, records `target_environment: "testnet"`, checks client-config shape, mutation consent, oracle key availability, public endpoint reachability, current block height, compact public-chain health, live block-1 chain fingerprint, saved `chain.latest.json` selected-environment provenance, native Torii MCP status, faucet puzzle availability, signer derivation/funding plus account asset-listing availability when a real config is present, existing release evidence, and any current-chain nested-call probe blocker. Failed nested-call probes carry a compact Sumeragi health summary in the report and stdout only when `nested_call_probe.latest.json` is timestamped, records the selected environment, and matches the live chain fingerprint; wrong-environment or stale-chain probe files are recorded as blockers without copying their summary or health into preflight status. Public release evidence path labels are repo-relative for files under this checkout and basename-only for outside runtime paths, while the scripts still operate on the real configured paths. When `SORASWAP_ORACLE_PUBLIC_KEY_HEX` and `SORASWAP_ORACLE_PRIVATE_KEY_HEX` are unset, the Taira client config signer is used as the native oracle provider. It blocks the full release when native Torii MCP is missing or unhealthy, when mutation-enabled public write health records any `endpoint.health_issues` such as non-JSON `/status` or `/v1/sumeragi/status`, stale committed blocks, saturated queues, or excessive QC lag, when the public finality path has queued or age-saturated writes with no recent committed block, when saved chain evidence is missing entirely, lacks selected-environment provenance, lacks non-empty `torii_url`, `chain`, or `block_1_hash`, or belongs to another public environment, and also when `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` is absent, because release-ready preflight evidence must prove the later signed phases are operator-authorized. The CLI/HTTP scripts remain useful for diagnostics, but not for claiming release readiness. It does not deploy contracts or print signing secrets.

When preflight reports that saved `chain.latest.json` no longer matches the live Taira block-1 fingerprint, run `make refresh-testnet-chain` after intentionally accepting the public reset. That target is read-only against Taira: it fetches the live block-1 fingerprint through the selected client config and `SORASWAP_TORII_URL` override if present, archives stale local `deployments/testnet` evidence under `deployments/testnet/archive/<utc>-<block1-hash>/`, and writes a fresh `chain.latest.json` plus timestamped `chain.<generated_at>.json`. It does not require `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` and does not refresh `nested_call_probe.latest.json`; run `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe` separately after the chain snapshot is current. `make refresh-testnet-chain` and `make refresh-production-chain` validate the selected client config before network work, rejecting wrong-environment configs, placeholder/local/wildcard/example endpoints or key material, Taira configs whose chain does not match the expected Taira chain unless `SORASWAP_TESTNET_CHAIN_ID` pins an intentional public reset, and production configs that still carry Taira's canonical chain id without `SORASWAP_PRODUCTION_CHAIN_ID`; they also fail with a `next setup:` block when the required untracked client config is missing, including the example `cp`, `SORASWAP_CLIENT_CONFIG`, and rerun command.

As verified on May 27, 2026, the operator host behind `taira.sora.org` may be running an existing Sora-prefix localnet state with chain id `00000000-0000-0000-0000-000000000000` and account prefix `753`, while the current fresh Taira staging chain is `fc56984b-2be7-431d-840e-21514d1883f0` with prefix `369`. Keep the copied, untracked client config aligned with the live host before running deploy or smoke flows; use `chain = "00000000-0000-0000-0000-000000000000"` plus `[account].chain_discriminant = 753` for that localnet state, or restore the current Taira template values after a fresh Taira redeploy.

`SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet` now treats public deployment as a permissionless `universal` dataspace bundle flow. Before deploying it fingerprints the live chain using `chain id + block 1 hash`, writes `deployments/testnet/chain.latest.json` with `generated_at`, `environment: "testnet"`, `torii_url`, `chain`, and `block_1_hash`, and archives stale `deployments/testnet` evidence under `deployments/testnet/archive/<utc>-<block1-hash>/` whenever Taira has been redeployed without changing the chain id. Release gates also compare the observed `torii_url` as required provenance metadata, so evidence captured through another public endpoint is rejected even when the chain id and block-1 hash match. Deploy reports include the writer PID, and a later deploy marks any previous `deploy.latest.json` that is still `status: "running"` as failed/interrupted before starting fresh evidence, so an interrupted bundle run is retained for diagnosis but cannot be mistaken for current release evidence. The wrapper auto-runs the helper domain/asset bootstrap when `soraswap.universal` or the helper aliases are missing, compiles `iroha.contracts.toml`, submits it through `iroha contract app deploy` in one-contract chunks by default, atomically persists the platform receipt to `deployments/testnet/soraswap.bundle.deploy.json` with `generated_at`, selected `environment`, chunk metadata, and chain fingerprint, materializes the per-contract `*.deploy.json` records with selected-environment provenance, successful response/instance proof, and code/ABI hash evidence that the readonly and mutable smoke flows already consume, and atomically writes adjacent deployment manifests whose compiler payload is stamped with `contract_key`, `generated_at`, and selected `environment`. Stale per-contract records or orphan manifests for sources no longer under `contracts/` are cleaned before deployment snapshots are written. Operators can set `SORASWAP_CONTRACT_APP_CHUNK_SIZE=<n>` for deterministic chunked public deploys; release evidence still relies on the materialized per-contract records plus `contracts.latest.json` and matching `<contract_key>.manifest.json` files, and bundle-based records must carry a deployed bundle receipt for the same contract key/address/nonce/code hash/ABI hash. If the aggregate `soraswap.bundle.deploy.json` receipt is present, public release gates also require it to be successful, timestamped, path-clean, free of unredacted sensitive diagnostics, selected-environment-scoped, match `chain.latest.json`, and be contract-for-contract identical to `contracts.latest.json`. `deployments/testnet/nested_call_probe.latest.json` records persisted `bytes` state round-trip, minimal no-arg live `call_contract(...)`, and multi-hop nested AssetOps relay checks that must pass before bootstrap proceeds.

`scripts/fund_testnet_signer.sh` is the operator helper for public Taira funding and requires `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` because it may self-register, onboard, and faucet-fund the signer. `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet` will auto-claim faucet funds when the signer is missing or unfunded, solve the faucet PoW puzzle, and wait for a positive `xor#universal` balance before deploying. Post-deploy init now runs by default there, and `SORASWAP_BOOTSTRAP_SCOPE=foundation|full` still narrows the init surface when needed.

Public bootstrap now targets the current `n3x_hub` and DLMM pool contract subjects on `testnet|production` and migrates seeded balances forward from previous contract-subject custody after upgrades. `local` still defaults `n3x` custody to the `n3x_hub` contract subject, and `SORASWAP_N3X_VAULT_ACCOUNT` remains the explicit override when an operator wants to force a different custody account during repair or migration drills.

`SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet` is now the canonical signed Taira rehearsal for the mutable DeFi surface. It reuses the readonly compatibility lane for deployment-record and manifest revalidation, rechecks the saved `nested_call_probe.latest.json` evidence against the current chain, requires current `contracts.latest.json` and `deploy.latest.json` snapshot evidence with a completed `deployment_records_snapshot` phase before signed write paths, signs oracle payloads when derivative write paths are enabled, then executes the same active router, launchpad, farms, automation, and derivatives write paths that the local smoke uses, including the perps queue/recover/requeue/liquidate path, before writing `deployments/testnet/smoke.latest.json` with `status: "completed"`. The report embeds the readonly verification run with current chain, contracts, deploy snapshot metadata, and `snapshot_check`, and the release gate verifies the embedded snapshot `generated_at`, status, selected environment, and chain fingerprint against the current evidence files. The release gate requires those critical public smoke write paths to carry 64-hex transaction hashes, not placeholders.

The mutating smoke stores its prerequisite readonly pass in `deployments/testnet/smoke.readonly.latest.json` plus a timestamped `smoke.readonly.<timestamp>.json` sidecar by setting the internal `SORASWAP_SMOKE_LATEST_REPORT` and `SORASWAP_SMOKE_TIMESTAMPED_REPORT` overrides for that subprocess only. Operators should leave those overrides unset for release runs; `deployments/testnet/smoke.latest.json` is reserved for completed signed mutating evidence. If a signed mutating smoke exits before completion after the readonly prerequisite, the wrapper also writes diagnostic-only `deployments/testnet/smoke.failed.latest.json` plus a timestamped `smoke.failed.<timestamp>.json` sidecar with the submitted contract-call transaction trace and the latest public write-health sample. Failed sidecars do not satisfy `make release-checklist`; they preserve the root-cause evidence for public finality/write-health incidents without overwriting completed signed smoke evidence.

The bridge proof lane stays in the same release gate, but it runs as its own target: `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet` records `deployments/testnet/contract_console_smoke.latest.json` separately so the bridge message is not consumed twice by a single rehearsal. It also requires current deploy snapshot evidence before signed bridge proof/message submissions. A green release gate therefore requires both the signed `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet` evidence and the signed `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet` evidence, with both reports marked `status: "completed"` and the console report proving a proof-driven `finalize_inbound` submission, no caller-supplied `settlement.payload`, exact `Applied` or `Committed` proof/message statuses on the normal apply path, and 64-hex proof/message transaction hashes. Replay fallback evidence must decode to replay/duplicate/consumed/proof-overlap or current bridge assertion semantics rather than a generic `Rejected` status.

`make smoke-testnet-readonly` preserves the older non-destructive compatibility lane. It revalidates each saved `*.deploy.json` record on the current selected-environment chain, including timestamp, environment, and chain-fingerprint provenance before live alias/code checks, rebuilds missing records from live aliases plus local manifests when possible, compares live code manifests against any saved deployment manifests, and records typed readonly view evidence under the same `deployments/testnet/` directory.

`SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira` is the full public Taira release runner. It requires a real untracked `config/testnet/taira.client.toml` or `SORASWAP_CLIENT_CONFIG`, rejects the checked-in example, local/wildcard/example endpoints such as `127.0.0.1`, `0.0.0.0`, IPv6 `[::1]` / `[::]`, reserved `.example`, `.test`, `.invalid`, `.localhost`, `example.com`, `example.org`, and `example.net` hosts, and embedded placeholder fragments such as `CHANGE_ME`, `TODO`, `TBD`, `changeme`, `replace_me`, `replaceme`, or `placeholder` in the config or oracle override env vars, and checks mutation consent before any public mutation. It also rejects non-Kotodama files under `contracts/` except `contracts/shared/README.md` before config setup can advance into any signed phase. It also rejects release-unsafe debug knobs such as `SORASWAP_SKIP_PUBLIC_SIGNER_READY_CHECK=1`, `SORASWAP_INIT_CONTRACT_STATE=0`, or a globally exported `SORASWAP_PREFLIGHT_SKIP_EXISTING_NESTED_PROBE_CHECK=1`; these binary knobs must be `0` or `1`, and the runner applies the nested-probe skip only to its first refresh-safe preflight. By default, the same client config signer submits native oracle attestations; set `SORASWAP_ORACLE_PUBLIC_KEY_HEX` plus `SORASWAP_ORACLE_PRIVATE_KEY_HEX` only when overriding that provider. Public RWA market launch is opt-in: with the default `SORASWAP_ENABLE_RWA_RELEASE=0`, the runner records current-chain RWA compliance evidence as `not_applicable` and the signed smoke skips RWA lot/redemption mutations; when `SORASWAP_ENABLE_RWA_RELEASE=1`, the runner validates `SORASWAP_RWA_ISSUER_APPROVAL_REF`, `SORASWAP_RWA_LEGAL_REVIEW_REF`, `SORASWAP_RWA_COMPLIANCE_POLICY_REF`, `SORASWAP_RWA_NAV_SOURCE_REF`, and `SORASWAP_RWA_REDEMPTION_TERMS_REF` with the same missing, placeholder, local/wildcard endpoint, reserved-domain, and control-character checks used by the RWA recorder before it exports the mutation environment or starts `[1/12]`. When setup stops early on missing config, mutation consent, oracle material, or required RWA references for an enabled RWA launch, it also prints the retained `deployments/testnet/preflight.latest.json` status, timestamp, blockers, warnings, and health issues if available. It runs the release sequence in order: refresh-safe preflight, nested-call probe, normal preflight against the refreshed probe and saved chain snapshot, RWA compliance evidence recording, deploy, readonly smoke, mutating smoke, contract-console smoke, trader readonly, trader mutating, trader API publish, and `release-checklist`. The runner prints numbered `[n/12]` phase banners and lists each expected evidence path before a target starts, then prints the ready evidence paths only after that phase materializes artifacts and the immediate evidence guard confirms selected-environment metadata, current chain fingerprint provenance, final preflight agreement with `chain.latest.json` and the current supported `nested_call_probe.latest.json` with a preflight timestamp no older than the probe timestamp, RWA evidence no older than the final ready preflight, deploy evidence no older than the final ready preflight, `contracts.latest.json` no older than the deploy report with the deploy snapshot detail naming that current contracts timestamp, current completed contracts/deploy snapshot references for post-deploy phases, current supported nested-call evidence plus current readonly-smoke verification for mutating smoke, mutating smoke first-release module transaction and state evidence plus risk-vault views, perps-liquidation transaction hashes with numeric positive liquidation counters, and 2026 primitive transaction/rejection evidence, and the phase's release status, such as warning-free `preflight.status = "ready"` with signer/account/fee readiness, `nested_call_probe.supported = true`, a deploy report whose preflight, compile, nested-call probe, deploy, contract-state bootstrap, and deployment-record snapshot phases all completed, completed RWA or not-applicable RWA evidence plus completed smoke reports, trader reports with full account-scoped required-route probes including `authority`, list `limit`, and swap-candle `bucket_secs` evidence plus signed numeric `route_swap` delta evidence for the XOR-to-USDT base-input path, completed proof-driven contract-console bridge settlement with governed-route provenance and valid submission status using exact status-kind matching, and a completed trader API report with deployment-record, snapshot-check, CID probe success, manifest-match count checks, exact route-manifest, and SoraFS receipt evidence.

Setup summaries for retained preflight evidence include health issues alongside blockers and warnings when `endpoint.health_issues` or non-JSON health snapshots are present; those lines remain diagnostic and never turn blocked preflight into release evidence.

The same immediate phase guard checks `docs/parity/migration_register.md` before accepting each live release phase artifact, so a missing, empty, reference-only-only, or non-ported production ledger stops the phase runner before later signed phases can advance. It also rechecks the current release-ready preflight baseline before deploy, RWA, smoke, contract-console, trader, and trader API phases can advance, including mutation consent, native MCP HTTP `200`, empty `endpoint.health_issues`, signer/account/fee readiness, usable oracle key sources, `oracle_keypair_verified: true`, matching saved chain evidence, current supported nested-call probe evidence, and preflight metadata with `nested_call_probe.latest_exists`, `matches_current_chain`, and `supported` all true.

`make release-checklist` requires `docs/parity/migration_register.md` to be present, nonempty, and backed by at least one `ported` production row with no non-reference release rows outside `ported`; blank status cells are treated as non-ported rows. Before public preflight or production-prerequisite evidence checks, it also rejects non-Kotodama files under `contracts/` except `contracts/shared/README.md`, so source-side notes cannot bypass the final release gate. It also requires `deployments/testnet/chain.latest.json` to carry `generated_at`, selected `environment`, and non-empty `torii_url`, `chain`, and `block_1_hash` fields before it accepts `deployments/testnet/preflight.latest.json` as `ready` for the current Taira fingerprint with matching `chain.fingerprint.torii_url`, `chain`, and `block_1_hash`, `target_environment: "testnet"`, `chain.saved_snapshot_environment: "testnet"`, mutation consent, native Torii MCP HTTP `200`, empty `endpoint.health_issues`, signer account visibility, account asset-listing availability, a positive fee balance, usable oracle key sources, `oracle_keypair_verified: true` proving the private key signs to the configured public key, and `nested_call_probe.latest_exists`, `nested_call_probe.matches_current_chain`, and `nested_call_probe.supported` all true. When preflight is blocked by missing current nested-call evidence, it prints the signed nested-probe refresh command before listing artifacts still required after preflight clears; when a current probe exists but is unsupported or carries a failure summary, it prints the compact health summary plus the sibling `../iroha` rollout verifier command with `--allow-testnet-mutations`. Checklist artifact diagnostics use repo-relative labels under the checkout and basename-only labels for outside paths, and required public evidence, including per-contract deploy records and manifests, plus required local chain/deploy/contracts/smoke reports and primitive telemetry are rejected if diagnostic string values or object keys still contain raw local `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, or `/private/var/folders/...` paths, including `file://` URI forms. It also rejects required release artifacts whose `chain_fingerprint` is missing or does not match the current `torii_url`, `chain`, and `block_1_hash`, artifacts that do not record the selected environment and `generated_at`, smoke, contract-console, trader, or trader API reports without `status: "completed"`, post-deploy reports missing `snapshot_check.status: "completed"`, deploy reports whose deployment-record snapshot detail does not point at the current contracts timestamp, `contracts.latest.json` snapshots without `status: "completed"` or that do not exactly cover the Kotodama contracts under `contracts/` once per contract or include wrong-environment contract entries, plus missing, stale, wrong-environment, untimestamped, extra, response/instance-incomplete, or code/ABI-hash-inconsistent per-contract `deployments/testnet/<contract_key>.deploy.json` and `<contract_key>.manifest.json` records. Current per-contract manifests must embed the filename-matching `contract_key` plus selected `environment` and `generated_at` metadata alongside matching code/ABI hashes, and an optional aggregate `soraswap.bundle.deploy.json` receipt must be successful, timestamped, selected-environment-scoped, path-clean, free of unredacted sensitive diagnostics, match `chain.latest.json`, and match the current contract set by key, address, nonce, code hash, and ABI hash. After local acceptance runs with every inherited `SORASWAP_*` variable plus generic chain/account-discriminator variables `CHAIN`, `ACCOUNT_CHAIN_DISCRIMINANT`, and `IROHA_ACCOUNT_CHAIN_DISCRIMINANT` cleared, including public client/config, public endpoint, mutation consent, profile/manifest, release-selector, preflight, local-coverage, bridge, oracle, RWA, top-up/faucet, trader, and publication controls, and with make-control variables `MAKEFLAGS`, `MFLAGS`, `GNUMAKEFLAGS`, `MAKEFILES`, and `MAKEOVERRIDES` cleared before nested `make`, it requires `deployments/local/chain.latest.json`, `deployments/local/deploy.latest.json`, `deployments/local/contracts.latest.json`, `deployments/local/smoke.latest.json`, and `artifacts/telemetry/defi_2026_primitives_latest.json` to remain present and path-clean; the retained local chain/deploy/contracts/smoke evidence must come from the full isolated run, with local contracts covering the current Kotodama contract set exactly once, local contracts no older than local deploy, local smoke no older than both local deploy and contracts, the deploy snapshot detail pointing at the current contracts timestamp, local smoke marked `status: "completed"` and `environment: "local"`, plus telemetry proving launch-ready intent, n3x vault, solver-operator, hook-order, margin, and RWA evidence instead of accepting a sparse telemetry placeholder. The production audit and readiness checklist must mention the current retained local chain, deploy, contracts, smoke, and primitive telemetry `generated_at` values, so stale local rehearsal writeups fail the same gate as stale Taira blocker writeups. If retained `deployments/local/soraswap.bundle.deploy.json` exists, it must also be successful, timestamped, selected-environment-scoped, path-clean, free of unredacted sensitive diagnostics, and match local `contracts.latest.json` by key, address, nonce, code hash, and ABI hash; the optional local aggregate bundle may omit `chain_fingerprint`, but any bundle fingerprint it records must match local contracts. It validates required public docs and evidence before running the expensive local acceptance bundle, including the contract-console and trader UI suites. For Taira, the production audit, readiness checklist, and devex critique must mention the current block-1 hash and, while preflight is blocked, the current blocked preflight plus either the current nested-call probe timestamp when a latest probe is timestamped, selected-environment-scoped, and matched to `chain.latest.json`, or the fact that current probe evidence is absent via `nested_call_probe.latest_exists`. For production, the production audit and readiness checklist must mention the current production block-1 hash and, while production preflight is blocked, the current blocked production preflight plus either the current production nested-call probe timestamp when a latest probe is timestamped, selected-environment-scoped, and matched to `chain.latest.json`, or the fact that current probe evidence is absent via `nested_call_probe.latest_exists`, so stale blocker writeups fail fast with the evidence for the selected public environment.

Retained local smoke evidence is treated as full-scope only when it includes transaction hashes for the critical perps liquidation, intent/vault/operator/margin, RWA, DLMM hook, and conditional-escrow trigger mutations; nonempty rejection evidence for the negative-path checks; stable state snapshots for perps liquidation counters, intent/vault/operator/margin, RWA market, and DLMM hook quote state; and trigger evidence proving every expected SoraSwap trigger is registered, the required active triggers remain active, and epoch-auction close evidence completed. Sparse local smoke reports are rejected even when they carry `status: "completed"`.

Retained local contract snapshots must cover the current Kotodama contract set exactly once with selected-environment provenance and complete address, deploy nonce, code-hash, and ABI-hash evidence for every contract entry. Retained local chain, deploy, contract, and smoke snapshots must also carry matching non-empty local chain fingerprints.

The local acceptance scrub also clears `SORASWAP_PROFILE` and `SORASWAP_CONTRACTS_MANIFEST`, so the release checklist cannot satisfy `dev-schema`, `dev-check`, or `dev-build` through a non-local profile or alternate manifest.

The scrub also removes every inherited generic `IROHA*` and `KAGAMI*` variable. When the optional local-acceptance candidate trio is present, only its validated target-specific values are restored after the scrub; both isolated targets force `SORASWAP_ISOLATED_LOCAL_UP_TIMEOUT_SECS`, `SORASWAP_ISOLATED_DEPLOY_TIMEOUT_SECS`, `SORASWAP_ISOLATED_SMOKE_TIMEOUT_SECS`, `SORASWAP_ISOLATED_TESTNET_SMOKE_TIMEOUT_SECS`, and `SORASWAP_CONTRACT_APP_DEPLOY_PROCESS_TIMEOUT_SECS` to `0`. Their harness still selects and cleans up its own isolated localnet directory and ports.

Internal production-prerequisite narrowing is not an operator env surface: exported release-checklist internal prerequisite flags or the private `RELEASE_CHECKLIST_INTERNAL_TOKEN` make `make release-checklist`, `make release-taira`, and `make release-production` fail before evidence validation or release phases. The standalone production checklist reaches that mode only through the scrubbed recursive script path with a one-time private token. Full release phase dispatches also clear inherited generic chain/account-discriminator variables before calling nested `make`, and phase dispatches plus recursive checklist calls clear inherited make-control variables, so stale account derivation, dry-run, injected-makefile, or command-line override state from wrapper automation cannot make a release phase appear to pass without executing.

`deployments/testnet/rwa_compliance.latest.json` is a required release artifact. Create or refresh it with `make record-testnet-rwa-compliance` after `make refresh-testnet-chain` has captured the saved chain fingerprint, the signed nested-call probe has proven current-chain support, and preflight has captured the target chain fingerprint and `target_environment: "testnet"` with ready, warning-free status. The recorder refuses a ready-looking preflight unless it proves mutation consent, native MCP HTTP `200`, empty `endpoint.health_issues`, signer/account/fee readiness, usable oracle key sources, `oracle_keypair_verified: true`, a matching saved `chain.latest.json`, and a latest nested-call probe that matches the current chain and is supported. If chain evidence is missing or preflight is not release-ready, the recorder prints the same refresh, signed nested-probe, then final preflight order before asking for RWA-mode-specific evidence, and it relays the recorded blocker such as the signed nested-call probe refresh command; when the selected `preflight.latest.json` exists but is blocked, warning-bearing, or records public write-health issues, it also prints a compact preflight setup summary with status, target environment, generated timestamp, blockers, warnings, and health issues. With default public `SORASWAP_ENABLE_RWA_RELEASE=0`, the recorder writes a current-chain artifact with `status: "not_applicable"`, `rwa_release_enabled: false`, and a reason saying no RWA market is being launched for the DEX release. With `SORASWAP_ENABLE_RWA_RELEASE=1`, it requires `SORASWAP_RWA_ISSUER_APPROVAL_REF`, `SORASWAP_RWA_LEGAL_REVIEW_REF`, `SORASWAP_RWA_COMPLIANCE_POLICY_REF`, `SORASWAP_RWA_NAV_SOURCE_REF`, and `SORASWAP_RWA_REDEMPTION_TERMS_REF` unless an existing completed artifact already matches the current `torii_url`, `chain`, and `block_1_hash` fingerprint plus selected environment with timestamp metadata, control-character-free, non-placeholder, non-local/wildcard, non-reserved-domain references, redacted optional notes, and a `generated_at` timestamp no older than the current ready preflight. The release gate applies the same no-older-than-preflight rule, accepts `not_applicable` only when public RWA release is disabled and no RWA launch activity is observed in smoke evidence, rejects optional notes that would change under the shared redactor, and the recorder's stdout labels evidence paths repo-relative under this checkout or basename-only for outside runtime paths. Manual `SORASWAP_RWA_COMPLIANCE_CHAIN_JSON` overrides must include non-empty `torii_url`, `chain`, and `block_1_hash` fields and match the ready `preflight.latest.json` plus saved `chain.latest.json`; they are an assertion against current evidence, not a substitute for the refresh, signed nested-probe, and final preflight sequence. Placeholder fragments such as `TODO`, `TBD`, `CHANGE_ME`, `changeme`, `replace me`, `replaceme`, or `placeholder` are rejected even when embedded in a longer-looking reference, control characters are rejected, local/wildcard endpoints such as `127.0.0.1`, `0.0.0.0`, IPv6 `[::1]` / `[::]` are rejected, and reserved `.example`, `.test`, `.invalid`, `.localhost`, `example.com`, `example.org`, and `example.net` domains are rejected as evidence URLs. Optional `SORASWAP_RWA_COMPLIANCE_NOTES` is redacted before evidence writing, and an existing otherwise-current artifact is refreshed if its notes would change under the redactor. The repo validates the evidence hook only; issuer approval, legal review, compliance policy, NAV source, and redemption terms remain external artifacts referenced by concrete ids or URLs in that JSON when an RWA market is explicitly launched.

The release flow no longer depends on a separate staging environment. The repo now also carries a parallel production wrapper family:

Prepare production input as a mode-`0600`, single-link regular file at the ignored, untracked path `config/production/production.client.toml`. Set the real non-Taira `chain`, Torii root, signer keypair, and explicit `[account].chain_discriminant`; production has no `753` discriminant fallback. If Torii requires HTTP Basic authentication, populate both `[basic_auth].web_login` and `[basic_auth].password`. Partial or malformed auth is rejected. The shell request path supplies the derived authorization header through an anonymous curl config descriptor. CLI-compatible configs are parsed and materialized in one fd-bound generation, preserve auth at mode `0600`, and use inode-bound cleanup that refuses replaced or multiply-linked paths after success or failure; credentials and the encoded header are never added to request argv or evidence. Authenticated response bodies, stderr, and explicit output files are mediated through mode-`0600` temporary files and suppressed before publication if an upstream echoes the Basic credential or signer material.

Before preflight, set `SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID` to the exact production fee asset and `SORASWAP_PRODUCTION_MIN_FEE_BALANCE` to its independently approved minimum balance. Production preflight and signer readiness require the live balance to meet that value; they do not invent either default. The production operator must already hold unit `Admin`, unit `AssetOps`, `CanRegisterTrigger` scoped to its own authority, and `CanExecuteTrigger` scoped to `soraswap_escrow_settle`. Production scripts verify the exact account readback and permission payloads and refuse to self-grant them. Deterministic contract-subject and nested-probe `AssetOps` grants remain covered by the explicit production mutation gate and are recorded with exact account and permission read-after-write verification in the permission-provisioning evidence.

Production cutover also requires a real `config/production/cutover-trust-policy.json` in the signed SoraSwap RC. Start from the tracked `.example`, replace every placeholder, and commit the real policy before freezing the RC. Its trusted approvers must use distinct, comment-free SSH Ed25519 public keys; the policy requires at least two independent signatures and both the `security` and `operations` roles. The policy also pins the allowed HTTPS monitoring origins and the non-weakenable 1,800-second/30-second/61-sample observation controls. It is intentionally not ignored: changing a trust anchor creates a new RC.

After `make refresh-production-chain` and before any production mutation, create the ignored runtime file `config/production/cutover-approval.json` at mode `0600` from its `.example`. The approval binds the exact production chain fingerprint, signed SoraSwap commit/tree/source state, signed Iroha candidate and every bundle/binary/archive digest, five distinct signer/oracle/admin/treasury/bridge authorities, the canonical positive fee minimum, external custody/rotation/admin/pause/rollback/monitoring/incident-response references, zero unresolved Critical/High findings, the expected validator and monitoring watch sets, and the deterministic trader API app/CID/routes identity. Sign the canonical UTF-8 JSON object with the `signatures` member removed—sorted keys, compact separators, and no trailing newline—using `ssh-keygen -Y sign -n soraswap-production-cutover-v1`; embed the complete OpenSSH signature files as canonical base64 under their policy approver ids. The runner verifies the signatures and approval expiry before phase 1, before and after every phase, around observation, and again during status-document closeout. It rejects inherited internal approval state and will not accept a policy outside the signed RC or an approval outside the canonical ignored path.

The external monitoring endpoint must return the exact shape in `config/production/monitoring-snapshot.schema.json`. Validator ids are normalized lowercase Iroha Ed25519 peer keys and are sorted before hashing. `validator_set_sha256` is SHA-256 of compact, sorted-key JSON for the sorted id array; oracle watch identity hashes use a sorted array of `{ "id": ... }`; balance watch identity hashes use a sorted array of `{ "id": ..., "kind": ... }`. Every snapshot is fresh and monotonically sequenced, binds the exact chain/RC/Iroha/deploy/contracts/approval state, and reports direct validator committed/canonical/commit-QC/highest-QC state, queues, lane backlog, finality age, API failures, oracle ages, the signer fee and other watched balances, readonly routes, and shared-derivatives regression state. The observer authenticates Torii status and CID reads only to the production Torii origin from the mode-`0600` client config, refuses redirects and non-JSON responses, and never forwards Torii Basic credentials to the separate monitoring origin.

```bash
cp config/production/production.client.toml.example config/production/production.client.toml
chmod 600 config/production/production.client.toml
# edit the copy; do not commit it
export SORASWAP_PRODUCTION_MIN_FEE_BALANCE=<approved-minimum>
export SORASWAP_PRODUCTION_ADMIN_AUTHORITY=<independent-admin-authority>
export SORASWAP_PRODUCTION_TREASURY_AUTHORITY=<independent-treasury-authority>
export SORASWAP_PRODUCTION_BRIDGE_AUTHORITY=<independent-bridge-authority>
```

```bash
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make deploy-production
make smoke-production-readonly
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production
make smoke-production-trader-readonly
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production-trader
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-nested-call-probe
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make publish-production-trader-api
make record-production-rwa-compliance
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make test-contract-console-production
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make release-production
```

Those commands write the same artifact shape under `deployments/production/` and reuse the same signed public-env code path as Taira; production evidence JSON is generated operator evidence and stays untracked except for `deployments/production/.gitkeep`. Signed production wrappers require explicit `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1` consent, while read-only wrappers remain available without it. `make release-production` checks that consent before any phase starts, validates the five `SORASWAP_RWA_*_REF` values only when `SORASWAP_ENABLE_RWA_RELEASE=1`, forces an isolated `SORASWAP_PUBLIC_ENV=testnet SORASWAP_RELEASE_ENV=testnet make release-checklist` as a no-production-mutation prerequisite, establishes the signed cutover approval, then mirrors the Taira sequence with the same numbered phase, evidence freshness guards, and exact receipt mapping. Phase 12 runs the fixed 30-minute readonly production observation before the production checklist; `observation.latest.json` must contain exactly 61 non-test samples over at least 1,800 seconds, with 25–45 seconds between samples, advancing committed finality, one immutable cryptographic validator set, aligned cross-validator commit-QC/highest-QC state, committed `/status/blocks`, zero queues/lane backlog/API failures, fresh approved oracle feeds, preserved minimum fee, stable watched balances and readonly routes, and the exact Torii trader API CID. A shared perps/options/cover regression aborts immediately at the external fail-closed pause boundary: the observer says that a coordinated pause is required but never claims it executed an external control. Operators must confirm the real all-derivatives pause outside this repo before starting a new approved cutover. Only after green observation/checklist evidence does the runner prepare `tmp/release-closeout/production.pending.json` and exit pending. Missing, placeholder, local/wildcard endpoint, reserved-domain, or control-character RWA references stop the runner before the Taira prerequisite for an enabled RWA launch. Update and stage only the two production status docs, without committing them, then run `SORASWAP_RELEASE_RESUME_CLOSEOUT=1 make release-production` with the same signed RC, Iroha pins, production config, authority inputs, and still-valid signed approval; that nonmutating resume revalidates approval, observation, checkpoint, and Taira prerequisite and is the only path that removes the checkpoint and emits completion. Other missing or invalid setup also stops before production mutation. The standalone production checklist cannot accept caller-injected approval state and directs operators back to the controlled runner.

Production setup summaries use the same preflight diagnostic printer as Taira and RWA compliance, so retained production preflight health issues are shown with blockers and warnings while remaining non-release diagnostic evidence.

The full production runner and standalone production checklist both clear every inherited `SORASWAP_*` variable plus generic chain/account-discriminator variables before the Taira prerequisite check, then pass only the explicit testnet release selector needed by the inner checklist, so production credentials, public endpoint overrides, alternate tools, local-coverage knobs, RWA/trader publication settings, or mutation-consent env vars cannot make the prerequisite look green.

`SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make production-preflight` records the faucet endpoint status for diagnostics but does not require a faucet on production. Unlike Taira preflight, production preflight blocks when the signer account is not query-visible or its live fee-asset balance is below `SORASWAP_PRODUCTION_MIN_FEE_BALANCE`. It also records config-file security, the explicit account discriminant, and exact operator-permission readiness. Public preflight and release runners sign an oracle probe payload and block unless the configured oracle private key derives the configured oracle public key.

The release runners, public preflight, and standalone public wrappers reject cross-environment configs before any public action, including configs discovered from the default ignored paths `config/testnet/taira.client.toml` and `config/production/production.client.toml`: Taira paths refuse configs under `config/production/`, and production paths refuse configs under `config/testnet/`. They also reject local/wildcard/example endpoints, including `127.0.0.1`, `0.0.0.0`, IPv6 `[::1]` / `[::]`, reserved `.example`, `.test`, `.invalid`, `.localhost`, `example.com`, `example.org`, and `example.net` hosts, and embedded placeholder fragments in public client configs and oracle override env vars. Taira paths also refuse configs whose chain does not match the expected Taira chain unless `SORASWAP_TESTNET_CHAIN_ID` pins an intentional public reset. Production paths also refuse configs or stale generic `CHAIN` overrides that still carry Taira's canonical chain id unless `SORASWAP_PRODUCTION_CHAIN_ID` pins the intended chain.

Set the production account prefix in `[account].chain_discriminant` (or explicitly in `SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT`). When the production client config is copied from another chain or the production fee asset is not query-visible by alias, also set `SORASWAP_PRODUCTION_CHAIN_ID` and `SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID` before running the production wrappers so contract-subject derivation and fee-balance preflight stay pinned to the real production chain. Run `make test-production-auth-config` to exercise authenticated GET/POST handling, secret-free argv and retained outputs, config file constraints, discriminant/minimum/permission rejection, fd-bound read races, identity-bound cleanup, oracle-key file hardening, and the raw-curl bypass guard. `make test-public-env-helpers` includes this target. Run `make test-production-cutover` for distinct-key/role/signature, expiry, schema, path/link/mode, exact binding, same-origin authentication, live status-shape, validator/finality, queue/API/oracle/balance/readonly/CID, cadence, fail-closed pause, test-only-evidence, and release-runner bypass regressions.

Release guidance and operator procedures live under:
- [`docs/release/smart_contract_production_audit.md`](./docs/release/smart_contract_production_audit.md)
- [`docs/release/production_readiness_checklist.md`](./docs/release/production_readiness_checklist.md)
- [`docs/release/taira_devex_critique.md`](./docs/release/taira_devex_critique.md)
- [`docs/release/taira_operator_runbook.md`](./docs/release/taira_operator_runbook.md)
- [`docs/release/contract_console_security_review.md`](./docs/release/contract_console_security_review.md)
- [`docs/release/contract_console_runbook.md`](./docs/release/contract_console_runbook.md)

On March 28, 2026, probing the live Taira node showed:
- chain id `fc56984b-2be7-431d-840e-21514d1883f0`
- `/v1/accounts/onboard` responding `403` with `UAID onboarding disabled`
- `/v1/accounts/faucet/puzzle` responding `200` once faucet is enabled on the public node
- `status.tx_gossip.caps.frame_cap_bytes` is expected to be at least `1048576` for routine SoraSwap deploys without split fallback
- public contract lifecycle writes were being rejected when Taira omitted an explicit `[nexus.fees]` block and fell back to the canonical default fee selector instead of `xor#universal`

On April 15, 2026, probing the live Taira node additionally showed:
- `/v1/contracts/rollups/swaps/fills`, `/v1/contracts/rollups/swaps/candles`, `/v1/contracts/rollups/trader/activity`, and `/v1/contracts/rollups/trader/account` still responding `404 Not Found`
- `/v1/contracts/view/batch` still responding `404 Not Found`
- fresh public faucet claims for new testnet signers reaching terminal `Expired` under the saturated public queue, so the trader signed evidence lane now retries the faucet claim and records the exact blocker in `deployments/testnet/trader.latest.json` when the public node still cannot fund a brand-new signer in time

Public SoraSwap docs and scripts now target canonical contract addresses in the `universal` dataspace. A Taira rollout must therefore include both the explicit `nexus.fees.fee_asset_id = "xor#universal"` override and the raised `network.max_frame_bytes_tx_gossip = 1048576` setting from `../iroha/configs/soranexus/taira/config.toml`, then a fresh `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet` run after the node comes back.

On May 23, 2026, the live Taira probe initially showed native Torii MCP returning `404`; `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` treats that as a release blocker before any signed live action. The public peers were then restarted with `[torii.mcp]` enabled, non-universal dataspace `manifest_hash` values, and a fresh `../iroha` `irohad` build. A later probe reported `mcp_http_status = "200"` and `nested_call_probe.supported = true`. The release gate now defaults the native oracle provider to the Taira client config signer, so separate oracle env vars are only required when an operator wants a different provider keypair.

When `deployments/testnet/preflight.latest.json` reports `endpoint.mcp_http_status = "404"` or any non-`200` MCP status, stop before signed live actions. Treat `502` / `503` from `https://taira.sora.org`, `/v1/mcp`, faucet, chain-fingerprint, MCP rollout, or SoraFS rollout reads as public ingress/upstream health, not a signer or contract bug. When `deployments/testnet/nested_call_probe.latest.json` reports `state_bytes_roundtrip_supported = true` but either `nested_call_supported = false` or `nested_asset_ops_supported = false`, first check the probe's `probe_asset.asset_definition_id`; if that id is wrong for the live chain, fix the asset wiring. If the asset id is correct, treat it as the public Taira runtime rejecting a required nested contract/AssetOps capability. When the probe reaches a `confirm_deploy_*` stage but the submitted transaction does not expose pipeline status or committed-transaction visibility within the configured windows, keep the release blocked as public transaction-visibility/finality health and record the stage plus hash before rerunning the MCP/SoraFS rollout checks on a healthy public root. When the probe fails earlier during `deploy_bytes_probe` with `queue_unresolved_route` / `PRTRY:ROUTE_UNRESOLVED`, keep the release blocked and record the attached Sumeragi health summary, including queue count/depth saturation, age saturation, and view-change cause such as `quorum_timeout`. The runtime fix path is to roll public Taira forward from `../iroha`, not to add a non-nested fallback here:
- build and stage an exact runtime bundle with `bash ../iroha/configs/soranexus/taira/build_taira_rollout_bundle.sh`
- install/restart the public validator(s) from that bundle
- verify the sibling runtime canaries with `cargo test -p iroha_core queue::router::tests::smart_contract_deploy_rule --lib` and `cargo test -p iroha_core contract_call_transaction_preserves_three_hop_transfer_authorities --lib`
- rerun the public canary plus the SoraSwap gate with `bash ../iroha/configs/soranexus/taira/verify_soraswap_rollout.sh --public-root "<direct-public-node>" --write-config /run/secrets/taira-canary-client.toml --soraswap-client-config /absolute/path/to/taira.client.toml --run-release-checklist --allow-testnet-mutations`

For a collision-free local full-stack check, use `make test-local-isolated`. It reserves a new direct child of `tmp/` named `iroha-localnet-verify-<expected-sha-or-dev>-<UTC timestamp>-<pid>`, defaults to API/P2P ports `49180` / `49337`, and advances both ports by `100` until the pair is bindable. It deploys the full contract set, runs the full `smoke_local.sh` mutation flow against the generated client config, asserts the exact post-smoke `n3x` and DLMM view snapshots, and drives the shared derivatives write path through `risk_vault`. The same DLMM-oriented stack overrides are applied there by default, and the isolated permissioned wrapper raises both Kagami timing knobs to `5000 ms` so the cold first-write `dlmm_pool` path stays clear of the 6 s quorum-timeout band seen on the debug localnet profile. When a fresh sibling `../iroha/target/release/irohad` exists, the isolated wrapper uses it for the peer while continuing to reuse the debug CLI/kagami helpers; otherwise it falls back to the normal debug peer. It also defaults `SORASWAP_CONTRACT_APP_CHUNK_SIZE=1` so full deploy acceptance avoids queueing multiple heavy contract deploy entries into one local consensus block.

The isolated wrapper never uses `local_down.sh` or signals a process itself. On exit it requires `ps`, audits every live `peerN.pid` as an `irohad` command with the exact absolute run-local `peerN.toml`, invokes only that run's generated `stop.sh`, and then requires all audited PIDs to be gone with no peer PID file left. A mismatch prevents `stop.sh` from running; a stop failure or still-live postcondition makes an otherwise successful acceptance fail. When the acceptance body already failed, its original status is preserved while cleanup failure is reported. The new run directory is always retained for evidence and diagnostics. The legacy `SORASWAP_ISOLATED_*_TIMEOUT_SECS` controls are accepted only as `0`; bounded timeout implementations signal child processes and are intentionally disabled for this strict cleanup lane.

For a foundation-only deployability check, use `make test-local-foundation-isolated`. It exports deploy, bootstrap, and smoke scope variables as `foundation`, proves the `n3x` plus DLMM bootstrap and smoke path on a dedicated permissioned localnet, and skips later-module initialization so unrelated launchpad/farms/perps/options scaffolds do not block DLMM verification. The wrapper preserves the retained full `chain.latest.json`, `deploy.latest.json`, `contracts.latest.json`, `smoke.latest.json`, and `soraswap.bundle.deploy.json` release evidence, while publishing the foundation rehearsal under `chain.foundation.latest.json`, `deploy.foundation.latest.json`, `contracts.foundation.latest.json`, `smoke.foundation.latest.json`, and `soraswap.foundation.bundle.deploy.json`.

## Notes
- The scripts are idempotent where practical and explicitly verify alias bindings before skipping asset registration.
- Bootstrap now applies the init-only `n3x`, DLMM, launchpad, referral, farms, risk-vault, perps, options, and cover config surfaces before smoke begins. The derivatives bootstrap also binds the product contracts into the shared `risk_vault` controller map so all later perps/options/cover write paths route through bucket accounting instead of raw product custody transfers.
- The local smoke also queries `n3x` and DLMM state through `view fn` snapshots after the mutation flow and asserts the expected post-smoke multi-bin DLMM reserves, share supply, and guard config after a position add, fee collect, and partial LP withdrawal before writing `deployments/local/smoke.latest.json`.
- In full scope, the local smoke also drives launchpad, referral, farms, automation, perps, options, and cover through their current lifecycle surfaces. Derivatives are no longer shell-view-only: perps covers open/funding/add-remove margin/close plus automatic queue/recover/requeue/liquidate, options covers shout buy-record-exercise plus outperformance buy-series settlement-exercise, and cover covers register-policy, stale/degraded reset handling, and claim routing, with typed `view fn` snapshots still recorded after the mutations.
- `make test-local-isolated` is the safest end-to-end verifier when another local Nexus is already running, because it avoids the default `tmp/iroha-localnet` path and the default local ports while still proving the post-swap local contract state.
- `make test-local-foundation-isolated` is the fastest isolated verifier for the current production target because it narrows the run to `n3x` plus DLMM and avoids unrelated downstream module bootstrap failures.
- The canonical testnet smoke is signed and mutation-gated behind `SORASWAP_ALLOW_TESTNET_MUTATIONS=1`, while `make smoke-testnet-readonly` preserves the older readonly compatibility lane.
- Mutating smoke steps require both a successful Torii submission and a committed transaction hash; read-only steps execute through `/v1/contracts/view`.
- The current contract set is a real Kotodama foundation, not full product parity. Use the parity register before treating a module as production-complete.
