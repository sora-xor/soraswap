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
- Use `scripts/deploy_testnet.sh` and `scripts/smoke_testnet.sh` for `taira.sora.org`.
- Keep generated `.to` and manifest outputs under `artifacts/` and deployment evidence under `deployments/`.

## Documentation Expectations
- Update `README.md` when command surfaces or environment variables change.
- Update `docs/parity/migration_register.md` whenever a tracked module moves between `stub`, `adapted`, `ported`, or `blocked`.
- Update `docs/interface_specs/` and `docs/state_layouts/` when contract state or public entrypoints change.

## Current Repository Status
- This repo currently contains the initial scaffold and first Kotodama contract slice.
- Full parity is not complete yet. Remaining behavior is tracked as TODOs in code and in the parity register.
