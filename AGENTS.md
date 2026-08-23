# SoraSwap Agents Guide

## Purpose
- `soraswap` is an Apache-2.0 Kotodama smart-contract repository for deploying a DEX and adjacent DeFi modules on Sora Nexus.
- The canonical neighboring toolchain is `../iroha`. This repo wraps that checkout for compile, deploy, and smoke workflows.

## Project Rules
- Keep all repository content Apache-2.0 compatible.
- Contract sources are Kotodama `.ko` files only. Do not introduce TOLK, Func, or Solidity into this repo.
- `xor#universal` is the canonical DEX base asset.
- `n3x` is the renamed stable basket contract and asset surface derived from the earlier T3 design.
- Self-issued helper assets live under the `soraswap` alias space where possible, but the DEX base asset remains `xor#universal`.
- DLMM is the production AMM target. CLMM/XYK/SigmAMM are reference and comparison material only.
- Prefer behavior-level parity with the legacy reference implementation, not literal message layout parity.

## Working Model
- Implement foundation first: shared helpers, `n3x`, DLMM pool/router, deploy scripts, and parity docs.
- Then extend into launchpad, referral, automation, farms, perps, options, and cover.
- If `../iroha` lacks a required Kotodama, IVM, Torii, or CLI capability, patch `../iroha` in the narrowest layer that solves the blocker.
- Preserve ABI v1 unless there is a hard blocker that cannot be solved by compiler lowering, host logic, manifests, or tooling.

## Tooling Expectations
- Use `scripts/lint_contracts.sh` and `scripts/compile_contracts.sh` as the repo entry points.
- Use `scripts/deploy_local.sh` and `scripts/smoke_local.sh` for local Nexus.
- Isolated acceptance must reserve a new run directory under `tmp/`; never signal or use broad localnet cleanup from that lane. Audit every live peer PID against its exact run-local config and stop it only through the generated `stop.sh`, retaining the run directory afterward.
- Use Make targets for public release workflows: `make deploy-testnet`, `make smoke-testnet-readonly`, `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet`, and `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira` for `taira.sora.org`; use the matching production targets only after the Taira release gate is green.
- Treat `scripts/deploy_testnet.sh` and `scripts/smoke_testnet.sh` as compatibility wrappers around the generic public deploy/read-only smoke scripts, not as the whole release surface.
- Full `release-taira` and `release-production` runners validate the required `SORASWAP_RWA_*_REF` external references only when `SORASWAP_ENABLE_RWA_RELEASE=1`; when enabled, validation happens before numbered public release phases, and production validates them before its isolated Taira prerequisite.
- Use `make release-checklist` and `make release-production-checklist` as the final evidence gates; they must fail before any production claim when current-chain Taira evidence is missing, stale, blocked, or unsupported.
- Keep generated `.to` and manifest outputs under `artifacts/` and deployment evidence under `deployments/`.

## Documentation Expectations
- Update `README.md` when command surfaces or environment variables change.
- Update `docs/parity/migration_register.md` whenever a tracked module moves between `stub`, `adapted`, `ported`, or `blocked`.
- Update `docs/interface_specs/` and `docs/state_layouts/` when contract state or public entrypoints change.

## Current Repository Status
- The repo now contains the first-release Kotodama contract surface for the DEX, `n3x`, DLMM, launchpad, referral, automation, farms, derivatives, bridge, intents, vaults, operators, margin, RWA, DLMM hooks, epoch auction, and conditional escrow.
- The migration register is the release ledger for behavior-level parity. Non-reference rows must be `ported` before release evidence can pass; `CLMM`, `XYK`, and `SigmAMM` remain reference-only comparison material.
- Local compile, lint, schema, regression, browser, simulation, isolated deploy/smoke, generated-evidence hygiene, signed current-chain Taira nested-call, DEX-only RWA not-applicable evidence, current-chain deploy/contracts evidence, current-chain readonly smoke sidecar evidence, current-chain readonly trader route evidence, and release-checklist metadata gates are hardened, but public production readiness is blocked again at Taira preflight before any signed mutation evidence can be refreshed. External RWA references are still required before any explicit RWA market launch.
- The current Taira blocker is public finality/write-health degradation, not SoraSwap nested-call support: `deployments/testnet/nested_call_probe.latest.json` remains current-chain supported for state bytes roundtrip, minimal nested `call_contract(...)`, and multi-hop nested AssetOps relay, but `make release-checklist` stops first because `preflight.latest.json` is not ready for the current Taira chain. The retained `deployments/testnet/preflight.20260706T125925Z.json` records stalled finality (`blocks=4468`, `sumeragi_height=4469`, `commit_qc_height=4468`, `highest_qc_height=4468`, `queue=3`, `tx_queue_saturated=true`, `time_since_last_block_ms=133305583`, `phase=pending_finality`, `worker_stage=tick`). Its direct-validator diagnostics also show all four validators at `height=4469` with `commit_qc_height=4468` / `highest_qc_height=4468`; direct hostname queue depths are `3`, `0`, `3`, and `1`, and redacted direct Torii port diagnostics for ports `29080..29083` show the same one-block-ahead stall without retaining the operator host/IP. Current deploy evidence is not release-grade: `deploy.latest.json` is failed at `20260704T225006Z` with `bootstrap_contract_state` still `running`, while `contracts.latest.json` is completed at `20260704T230748Z`; readonly smoke/trader evidence still references older 20260629 snapshots, and contract-console, signed trader, and trader API reports reference older 20260628 snapshots. After public health recovers and `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` is ready, fresh deploy, readonly smoke, signed mutating smoke, contract-console, readonly/signed trader, and trader API evidence still must be regenerated for the current deploy/contracts snapshot before production release can proceed. Failed future mutating smoke runs retain diagnostic-only `smoke.failed.*.json` sidecars, failed future console runs retain diagnostic-only `contract_console_smoke.failed.*.json` sidecars, and failed future signed trader runs retain submitted `route_swap` traces plus public write-health in `trader.latest.json`; those diagnostics do not satisfy release gates.
