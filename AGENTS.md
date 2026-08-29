# SoraSwap Agents Guide

## Purpose
- `soraswap` is an Apache-2.0 Kotodama smart-contract repository for deploying a DEX and adjacent DeFi modules on Sora Nexus.
- The canonical Iroha workspace is discovered from the repository's ancestors, or selected explicitly with `SORASWAP_IROHA_ROOT`. This repo wraps that checkout for compile, deploy, and smoke workflows.

## Project Rules
- Keep all repository content Apache-2.0 compatible.
- Contract sources are Kotodama `.ko` files only. Do not introduce TOLK, Func, or Solidity into this repo.
- `xor#universal` is the canonical DEX base asset.
- `n3x` is the renamed stable basket contract and asset surface derived from the earlier T3 design.
- Self-issued helper assets live under the `soraswap` alias space where possible, but the DEX base asset remains `xor#universal`.
- DLMM is the production AMM target. CLMM/XYK/SigmAMM are reference and comparison material only.
- Preserve the intended product behavior while designing directly for the current first-release contracts and Iroha interfaces.

## Working Model
- Implement foundation first: shared helpers, `n3x`, DLMM pool/router, deploy scripts, and parity docs.
- Then extend into launchpad, referral, automation, farms, perps, options, and cover.
- If `../iroha` lacks a required Kotodama, IVM, Torii, or CLI capability, patch `../iroha` in the narrowest layer that solves the blocker.
- This is a first-release codebase. Target only the current Iroha API and ABI; remove superseded routes, DTOs, binaries, and compatibility fallbacks instead of preserving them.

## Tooling Expectations
- Use `scripts/lint_contracts.sh` and `scripts/compile_contracts.sh` as the repo entry points.
- Use `scripts/deploy_local.sh` and `scripts/smoke_local.sh` for local Nexus.
- Isolated acceptance must reserve a new run directory under `tmp/`; never signal or use broad localnet cleanup from that lane. Audit every live peer PID against its exact run-local config and stop it only through the generated `stop.sh`, retaining the run directory afterward.
- Use Make targets for public release workflows: `make deploy-testnet`, `make smoke-testnet-readonly`, `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet`, and `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira` for `taira.sora.org`; use the matching production targets only after the Taira release gate is green.
- Treat `scripts/deploy_testnet.sh` and `scripts/smoke_testnet.sh` as the Taira entrypoints over the shared public deploy/read-only smoke implementation, not as the whole release surface.
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
- Local compile, lint, schema, regression, browser, simulation, isolated deploy/smoke, generated-evidence hygiene, and release-checklist metadata gates are hardened. Public release readiness is blocked before current Taira preflight because retained public evidence targets a retired chain identity. External RWA references are still required before any explicit RWA market launch.
- Current Taira is exactly chain `fc56984b-2be7-431d-840e-21514d1883f0`, NetworkId `hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94`, and account-chain discriminant `369`. Those values are not configurable. Retained artifacts for chain `809574f5-fee7-5e69-bfcf-52451e42d50f` are historical diagnostics only; a full chain refresh, signed capability probe, deploy/contracts snapshot, smoke, console, trader, and publication evidence sequence must be generated after the runtime upgrade. No compatibility parser, replay-success fallback, or historical-evidence promotion is allowed.
