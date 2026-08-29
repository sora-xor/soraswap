# Taira Deploy Devex Critique

Updated on 2026-08-24 for the current first-release Taira workflow.

## Current 2026-08-24 Status
- Upstream now defines Taira as chain `fc56984b-2be7-431d-840e-21514d1883f0`, NetworkId `hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94`, and account-chain discriminant `369`.
- Earlier public release chronicles have been removed. They are not evidence for the current API or identity.
- The current `deployments/testnet/preflight.latest.json` diagnostic (`generated_at: "20260823T162522Z"`) has `status: "blocked"`; it observes native MCP HTTP `200` and the canonical live block-1 fingerprint `d78dd3be4dcd8150ca50b9fa0184a77e16c1042e2e4ce60bdd588c42a49e6c43`, but records incomplete MCP capability metadata, no saved chain snapshot, no secure oracle config, no mutation consent, and no current nested-call probe.
- The Taira release gate is blocked before release-ready preflight. Operators must refresh the chain snapshot and regenerate the full signed capability/deploy/smoke/UI evidence sequence. No compatibility adapter or replay-success shortcut is supported.
- Local `../iroha` includes the universal-deploy router regression and three-hop nested-transfer authority canary, but current public capability still requires a fresh signed Taira probe.
- `make refresh-testnet-chain` now covers the read-only acceptance step for that reset: it updates only local chain evidence and archives stale generated reports, leaving the signed `testnet-nested-call-probe` as the separate runtime capability check.
- `make taira-preflight` and `make production-preflight` now default `SORASWAP_SKIP_IROHA_CLI_BUILD=1` when unset, so a bounded public health check reuses an existing `iroha` CLI instead of starting a sibling `cargo build`; operators can still set `SORASWAP_SKIP_IROHA_CLI_BUILD=0` explicitly when they want preflight to build a stale or missing CLI.
- `make release-checklist` must remain blocked until the current chain snapshot, supported nested-call probe, ready preflight, and downstream signed evidence all exist. `make release-production-checklist` remains blocked by that Taira prerequisite before any production artifact can count.
- `release-taira` and `release-production` now print numbered `[n/12]` phase banners plus expected and ready evidence paths for each public release target.
- Immediate release phase guards and the final release checklist now require the same current release-ready preflight baseline before deploy, RWA, smoke, contract-console, trader, or trader API evidence can advance or be accepted. That includes mutation consent, native MCP HTTP `200`, `endpoint.health_issues: []` from JSON-readable `/status` and `/v1/sumeragi/status`, signer/account/fee readiness, a valid secure typed-oracle client config and a distinct derivable oracle account, `oracle_client_config_valid: true`, `oracle_account_derivable: true`, and `oracle_account_distinct: true`, matching saved chain evidence, current supported nested-call probe evidence, and preflight metadata with `nested_call_probe.latest_exists`, `matches_current_chain`, and `supported` all true.
- `docs/release/taira_operator_runbook.md` now records the SoraSwap-facing Taira rollout inputs: MCP, gas metadata, dataspace manifest hashes, SCCP transparent-proof policy, canary signer handling, direct-node checks, and snapshot repair policy. `make taira-state-repair-plan` writes non-mutating repair-plan evidence before any storage operation.

## Evidence Policy
- The repository does not retain or accept the May/July deployment set as first-release evidence.
- Only artifacts generated against the exact current Taira chain and NetworkId may advance the release gate. Retired-chain success and failure reports are not compatibility inputs.
- The current retained preflight diagnostic is blocked and proves no release capability.

## What Works
- The deploy path defines a useful staged evidence sequence: chain fingerprint, nested runtime capability probe, deploy receipt, contract records, full smoke, console smoke, trader readonly, and trader mutation reports.
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` is the right cheap first release-readiness command. It is non-mutating, but it still catches client-config shape, mutation consent, MCP health, faucet health, current chain fingerprint, signer derivation, signer funding, and nested-call capability before the expensive release path.
- Taira uses a secure typed-oracle client config and requires its derived oracle account to be distinct from the deployment signer; raw oracle key environment variables are not release inputs.
- The nested-call probe separates codec/state storage, minimal `call_contract(...)`, nested AssetOps relay, and asset-id wiring. That distinction is essential because an incorrect SoraSwap asset id is an input error, not a runtime call bug.
- Public contract-call success requires the current closed pipeline-status DTO and a terminal `Applied|Committed` status; retired response shapes are rejected.
- Waiting for contract deploy nonce visibility avoids immediate back-to-back public deploy address reuse.
- The deploy and smoke artifacts are concrete enough to debug without rerunning every expensive phase.

## Friction
- The deployment depended on live sibling `../iroha` fixes and rollout operations, not just SoraSwap scripts. Missing Torii gas metadata, trader alias parsing, contract view selector behavior, IVM pointer handling, IVM chain-discriminant handling, and SCCP transparent-proof testnet behavior all surfaced as deployment blockers.
- Taira node rollout is still operationally manual. The SoraSwap runbook now names the required MCP, dataspace, canary signer, gas, SCCP, and snapshot policy checks, but the actual rollout still depends on live sibling `../iroha` operations.
- State repair was the hardest devex gap. A root split at height `621` was ultimately caused by validators starting height `620` from different state roots. The logs originally reported only group counts; a diagnostic build was needed to print parent/post roots and signer groups.
- Snapshot portability is fragile. Copying a healthy peer snapshot to other validators required aligning snapshot verification/signing config, because snapshot signatures are validated against configured snapshot keys, not simply against trusted validator state. That is reasonable security-wise, but operationally obscure during emergency repair.
- The CLI status helper still has mixed semantics around pipeline scopes. Passing `auto` to a pipeline-status route can produce `400`; scripts compensate in places, but the control-plane contract should be clearer.
- Release output still has many materially different phases, but the runners now expose the current phase and evidence paths directly in the console output.

## Recommendations
- Keep MCP `200` as a hard Taira readiness gate. CLI/HTTP paths are useful diagnostics, but native MCP health should remain part of the release claim.
- Keep `docs/release/taira_operator_runbook.md` in sync with `../iroha/configs/soranexus/taira/config.toml` and rollout scripts when MCP, gas, dataspace, SCCP, canary signer, or snapshot policy changes.
- Promote the commit-root split diagnostic from an ad hoc troubleshooting patch into normal warning output, with parent root, post root, signer indexes, and peer ids.
- Promote the plan-only `make taira-state-repair-plan` helper into an apply-capable runtime tool only after the sibling `../iroha` storage layout and snapshot-sidecar invariants are approved by runtime operators.
- Keep `taira-preflight` and `release-taira` setup hints in lockstep. When a new runtime input is added, both commands should name the same env vars and artifact paths.
- `release-taira` setup failures now print the retained `deployments/testnet/preflight.latest.json` status, timestamp, blockers, warnings, and health issues when available; keep that diagnostic path redacted and clearly separate from release evidence.
- Keep the numbered phase and evidence-path output in `release-taira` and `release-production` in sync when adding or removing release targets.
- Keep `SORASWAP_XOR_ASSET_DEFINITION_ID` defaulted to Taira's canonical `6TEAJqbb8oEPmLncoNiMRbLEK6tw` until the public `xor#universal` alias is query-visible everywhere.
- Treat `nested_asset_ops_supported == false` as ambiguous until the report's `probe_asset.asset_definition_id` is checked. It can be either a runtime blocker or a bad asset-id wiring bug.
- Do not use the deployment evidence alone for production cutover. Require the production readiness checklist artifacts, especially trader API publish evidence and RWA compliance evidence; external RWA references are mandatory only for an explicit RWA market launch.
