# Production Readiness Checklist

This checklist is the repo-wide release gate for SoraSwap. Taira is the canonical signed pre-production environment.

## Required Local Acceptance
- `make lint`
- `make compile`
- `make test-public-env-helpers`
- `make simulate-smoke`
- `make simulate-full`
- `make test-local-isolated`

## Required Taira Gate
- `make deploy-testnet`
- `make smoke-testnet-trader-readonly`
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet-trader`
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet`
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet`
- `make release-checklist`

## Module Readiness Rules
- `docs/parity/migration_register.md` is the canonical release ledger.
- Every non-reference-only row must be `ported`.
- `blocked`, `stub`, and `adapted` are not acceptable for a production claim.
- The shared derivatives group (`risk_vault`, `perps`, `options`, `cover`) is one sign-off and one rollback decision.

## Evidence Requirements
- `deployments/testnet/chain.latest.json` matches the current Taira fingerprint.
- `deployments/testnet/deploy.latest.json` exists, is `completed`, and records completed `preflight`, `compile`, `nested_call_probe`, `deploy`, `bootstrap_contract_state`, and `deployment_records_snapshot` phases.
- `deployments/testnet/nested_call_probe.latest.json` exists, matches the current Taira fingerprint, proves that persisted `bytes` state round-trips on live Taira, and proves that the minimal live `call_contract(...)` probe succeeded.
- `deployments/testnet/contracts.latest.json` exists and matches the current Taira fingerprint.
- `deployments/testnet/trader_readonly.latest.json` exists, matches the current Taira fingerprint, references the current `contracts.latest.json` plus `deploy.latest.json` metadata, and proves that `view/batch`, `swaps/fills`, `swaps/candles`, `trader/activity`, and `trader/account` are all live on public Taira.
- `deployments/testnet/trader.latest.json` exists, matches the current Taira fingerprint, references the current `contracts.latest.json` plus `deploy.latest.json` metadata, proves that the same trader routes are live on public Taira, and records a committed signed trader mutation.
- `deployments/testnet/smoke.latest.json` exists and matches the current Taira fingerprint.
- `deployments/testnet/contract_console_smoke.latest.json` exists and matches the current Taira fingerprint.
- `trader_readonly.latest.json.generated_at >= contracts.latest.json.generated_at`.
- `trader.latest.json.generated_at >= contracts.latest.json.generated_at`.
- `smoke.latest.json` references the current `nested_call_probe.latest.json`, `contracts.latest.json`, and `deploy.latest.json` metadata.
- `contract_console_smoke.latest.json` references the current `contracts.latest.json` and `deploy.latest.json` metadata.
- `smoke.latest.json.generated_at >= contracts.latest.json.generated_at`.
- `contract_console_smoke.latest.json.generated_at >= contracts.latest.json.generated_at`.
- Trader evidence must stop the gate when any required trader route still returns `404` on the public node.
- Testnet smoke evidence includes router execution, launchpad executor activation, farms slot accrual, and the active derivatives write-path suite, including perps queue/recover/requeue/liquidate coverage with recorded keeper reward and owner residual.
- Contract-console evidence includes proof submit plus bridge message submit through the deployed `bridge.sccp_bridge` contract.
- `contract_console_smoke.latest.json.bridge.submission_expectation == "apply"` is acceptable when proof/message both reach `Applied|Committed`.
- `contract_console_smoke.latest.json.bridge.submission_expectation == "replay_reject"` is acceptable when cached SCCP evidence proves the governed route and the deployed bridge rejects the replay path with decoded replay/duplicate/consumed/proof-overlap semantics, or with the current generic bridge-contract `assertion failed (constraint violation)` rejection when Taira does not preserve the original contract string.
- Bridge evidence must prove governed route provenance (`route_provenance[0] == 1`) before any production claim.
- If `nested_call_probe.latest.json` reports `state_bytes_roundtrip_supported == true` and `nested_call_supported == false`, the public Taira runtime is specifically failing on nested `call_contract(...)` rather than basic pointer/state codecs, and the gate must stop there.
- If `nested_call_probe.latest.json` reports `supported == false`, the public Taira runtime is not release-capable for SoraSwap’s active router/launchpad/derivatives surfaces and the gate must stop there.
- If `trader_readonly.latest.json` or `trader.latest.json` reports missing rollup routes, the public Taira app API is missing the trader read-plane rollout and the gate must stop there.
- The only acceptable fix for that specific blocker is a public Taira runtime rollout from `../iroha`, followed by `../iroha/configs/soranexus/taira/verify_soraswap_rollout.sh`; do not add a SoraSwap-side non-nested fallback.

## Release And Rollback
- Mainnet cutover happens only after the exact Taira artifact set is green with no exceptions.
- Production must reuse the same deploy, smoke, and evidence layout as Taira.
- If the bridge path falls back to caller-supplied settlement payloads, the release gate has failed.
- If any shared-derivatives regression appears, roll back the whole derivatives claim together.
