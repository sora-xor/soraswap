# Taira Deploy Devex Critique

Observed on 2026-05-23 from this worktree while deploying SoraSwap to public Taira.

## Current Evidence
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` reports `status: "ready"` in `deployments/testnet/preflight.latest.json`.
- Public Taira reports native Torii MCP `200`, faucet puzzle `200`, current block height `621`, chain id `809574f5-fee7-5e69-bfcf-52451e42d50f`, and block-1 hash `1a824af79608802b0999db4efeaa5f070a56f0fced274e2a427aea86770fbd99`.
- The runtime client config is untracked, non-placeholder, and kept outside committed source. Taira preflight derives the deployment authority and native oracle provider from that client config signer by default.
- Public Taira is currently running the staged `../iroha` release daemon with SHA-256 `b6f9050d6a901762acf4a137fb9f042ec6a6af1c352ad8e2c581e94c426f173c`.
- `deployments/testnet/deploy.latest.json` is `completed`; its `preflight`, `compile`, `nested_call_probe`, `deploy`, `bootstrap_contract_state`, and `deployment_records_snapshot` phases are all `completed`.
- `deployments/testnet/contracts.latest.json` records 23 deployed `universal` dataspace contracts, including n3x, DLMM pool/router, launchpad, referral, automation, farms, risk, perps, options, cover, bridge, intents, vaults, operators, margin, RWA, and DLMM hooks.
- `deployments/testnet/nested_call_probe.latest.json` records `state_bytes_roundtrip_supported == true`, `nested_call_supported == true`, `nested_asset_ops_supported == true`, and `supported == true` against canonical `xor#universal` asset definition id `6TEAJqbb8oEPmLncoNiMRbLEK6tw`.
- `deployments/testnet/smoke.latest.json` records 91 public mutation hashes and includes evidence for intent, vault, operator, margin, RWA, and DLMM hook flows.
- `deployments/testnet/contract_console_smoke.latest.json` proves the governed bridge route with `route_provenance[0] == 1`; proof and message submissions both reached `Applied`.
- `deployments/testnet/trader_readonly.latest.json` is `completed`, has no missing required trader routes, and covers 11 trader read-plane routes.
- `deployments/testnet/trader.latest.json` is `completed`; the final signed swap tx is `e27e9d998c7e498d8348d2898a508d45d4e782d0cb08ace5ba1a0f55fc1130f9`, committed at block height `621`.
- Remote peer logs show all four validators committed block `84611e87db807fabe74b05dab475b473bfcb852ebe969a1eb3b11e40d11cb8cd` at height `621`.

## What Works
- The deploy path now has useful staged evidence: chain fingerprint, nested runtime capability probe, deploy receipt, contract records, full smoke, console smoke, trader readonly, and trader mutation reports.
- `make taira-preflight` is the right cheap first command. It catches client-config shape, mutation consent, MCP health, faucet health, current chain fingerprint, signer derivation, signer funding, and nested-call capability before the expensive release path.
- Defaulting the Taira oracle provider to the client config signer removes a needless setup fork. Explicit oracle env vars remain available when an operator really needs a different provider key.
- The nested-call probe now separates codec/state storage, minimal `call_contract(...)`, nested AssetOps relay, and asset-id wiring. That distinction was essential: one failure was an incorrect SoraSwap fallback asset id, not a runtime call bug.
- Public contract-call success now tolerates terminal pipeline `Applied|Committed` when committed transaction lookup cannot decode an older public response. That matches how Taira actually behaves under load.
- Waiting for contract deploy nonce visibility avoids immediate back-to-back public deploy address reuse.
- The deploy and smoke artifacts are concrete enough to debug without rerunning every expensive phase.

## Friction
- The deployment depended on live sibling `../iroha` fixes and rollout operations, not just SoraSwap scripts. Missing Torii gas metadata, trader alias parsing, contract view selector behavior, IVM pointer handling, IVM chain-discriminant handling, and SCCP transparent-proof testnet behavior all surfaced as deployment blockers.
- Taira node rollout is still too manual. Enabling `[torii.mcp]`, adding non-universal dataspace `manifest_hash` values, configuring receipt signing, and carrying the SCCP testnet switch are all easy to miss.
- State repair was the hardest devex gap. A root split at height `621` was ultimately caused by validators starting height `620` from different state roots. The logs originally reported only group counts; a diagnostic build was needed to print parent/post roots and signer groups.
- Snapshot portability is fragile. Copying a healthy peer snapshot to other validators required aligning snapshot verification/signing config, because snapshot signatures are validated against configured snapshot keys, not simply against trusted validator state. That is reasonable security-wise, but operationally obscure during emergency repair.
- The CLI status helper still has mixed semantics around pipeline scopes. Passing `auto` to a pipeline-status route can produce `400`; scripts compensate in places, but the control-plane contract should be clearer.
- Release output is still too dense for first-time operators. `release-taira` does many materially different things, and the failure mode is only obvious after reading both the shell output and generated JSON.
- The public deployment evidence is green for deployment and smoke, but not a full production-cutover claim by itself. The stricter release checklist still expects `trader_api_bundle.latest.json` and `rwa_compliance.latest.json`, which are intentionally separate release artifacts.

## Recommendations
- Keep MCP `200` as a hard Taira readiness gate. CLI/HTTP paths are useful diagnostics, but native MCP health should remain part of the release claim.
- Add an operator runbook section for Taira node rollout inputs: `[torii.mcp]`, receipt signer, transparent SCCP testnet setting, dataspace manifest hashes, canonical gas asset id, and snapshot signer policy.
- Promote the commit-root split diagnostic from an ad hoc troubleshooting patch into normal warning output, with parent root, post root, signer indexes, and peer ids.
- Provide a first-class Taira state repair tool that can back up peer storage, choose a donor state, copy only safe state artifacts, clear transient consensus queues, and regenerate or validate snapshot sidecars per peer.
- Keep `taira-preflight` and `release-taira` setup hints in lockstep. When a new runtime input is added, both commands should name the same env vars and artifact paths.
- Split `release-taira` console output into named phases and print the expected evidence path at the end of each phase.
- Keep `SORASWAP_XOR_ASSET_DEFINITION_ID` defaulted to Taira's canonical `6TEAJqbb8oEPmLncoNiMRbLEK6tw` until the public `xor#universal` alias is query-visible everywhere.
- Treat `nested_asset_ops_supported == false` as ambiguous until the report's `probe_asset.asset_definition_id` is checked. It can be either a runtime blocker or a bad asset-id wiring bug.
- Do not use the deployment evidence alone for production cutover. Require the production readiness checklist artifacts, especially trader API publish evidence and external RWA compliance references.
