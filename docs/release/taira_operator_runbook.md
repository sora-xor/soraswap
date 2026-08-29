# Taira Operator Runbook

This is the SoraSwap-facing checklist for the current Taira interface. The
canonical runtime procedure is maintained in
[`../../iroha/configs/soranexus/taira/README.md`](../../../../iroha/configs/soranexus/taira/README.md).

## Required identity

The client and runtime must agree on all of the following:

- chain ID `fc56984b-2be7-431d-840e-21514d1883f0`
- NetworkId `hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94`
- account chain discriminant `369`
- XOR definition ID `6TEAJqbb8oEPmLncoNiMRbLEK6tw`, permanent alias
  `xor#universal`, and numeric scale `9`
- current `iroha3d`, `iroha`, and `kagami` binaries built from the same Iroha revision

Keep validator keys, onboarding tokens, faucet authorities, and the primary
populated client config outside both repositories. The separate typed-oracle
client config is the sole exception: keep it owner-only, ignored, and untracked
inside the SoraSwap worktree so the release gate can enforce its provenance.

## Disposable four-validator cohort

For local Taira runtime verification, use the compiled upstream orchestration
surface:

```bash
python3 ../../iroha/scripts/taira_devnet.py up
python3 ../../iroha/scripts/taira_devnet.py check
python3 ../../iroha/scripts/taira_devnet.py down
```

`up` builds `kagami`, `iroha3d`, and `iroha`, generates four
fresh-key NPoS validators for the canonical Taira identity, submits a signed
ping, verifies converged finality, and checks each MCP endpoint. Use
`--no-build --bin-dir ../../iroha/target/local-release` only when those exact
current binaries already exist. The generated directory contains secrets and
must remain owner-only and untracked.

There is no predecessor rollout bundle, daemon alias, host-service installer,
rollback wrapper, or shell compatibility layer in this flow.

## Public read-side doctor

Build the CLI from the revision deployed to Taira and run its typed doctor:

```bash
cargo build --manifest-path ../../iroha/Cargo.toml --locked \
  --profile local-release -p iroha_cli --bin iroha
../../iroha/target/local-release/iroha -c /private/runtime/taira-client.toml \
  taira doctor \
  --public-root https://taira.sora.org \
  --json
```

The command validates the current public routes and MCP posture. Any hard
failure blocks SoraSwap signed work. Diagnose ingress or runtime health; do not
substitute removed rollout scripts or SoraSwap-side endpoint fallbacks.
Treat a 2xx routed read as incomplete when any
`x-iroha-fanout-routes-failed`, `-denied`, `-unavailable`, or `-not-found`
counter is nonzero. Do not replace a same-identity cached balance, position, or
history snapshot with that partial response.

## Authorized write canary

Only an operator explicitly authorized to mutate Taira may run the compiled
write canary. The onboarding token file and output config must be owner-only
runtime files:

```bash
../../iroha/target/local-release/iroha -c /private/runtime/taira-client.toml \
  --fee-payer authority \
  taira write-canary \
  --public-root https://taira.sora.org \
  --onboarding-token-file /private/runtime/onboarding.token \
  --use-config-signer \
  --faucet-asset-id 6TEAJqbb8oEPmLncoNiMRbLEK6tw \
  --write-config /private/runtime/taira-canary-client.toml \
  --json
```

The canary uses the current NetworkId-aware transaction format, explicit fee
payment, signed onboarding/faucet flow, and typed transaction status. A failed
canary is a runtime or operator-input blocker, not permission to try an older
request shape.

## SoraSwap handoff

Copy `config/testnet/taira.client.toml.example` to an untracked owner-only
primary file, populate `[account]`, and keep the checked-in chain and NetworkId
exact. Create `config/testnet/oracle.client.toml` from the same example with a
different account keypair, the same chain, NetworkId, discriminant, and Torii
origin, and mode `0600`; this second file must remain ignored and untracked
inside the SoraSwap worktree.
The valid `[account].domain` value is an account alias-operation scope, not a
contract deployment selector; the universal deployment target is enforced by
the contract aliases and authenticated deployment state.
Then run:

```bash
export SORASWAP_CLIENT_CONFIG=/private/runtime/taira-soraswap-client.toml
export SORASWAP_ORACLE_CLIENT_CONFIG=config/testnet/oracle.client.toml
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make testnet-nested-call-probe
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make deploy-testnet
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make release-taira
```

Preflight must report native MCP HTTP `200`, JSON-readable status/finality,
no health issues, the exact saved chain fingerprint, a query-visible deploy
signer, a valid distinct typed-oracle account, and a positive fee balance. The
nested-call probe must prove persisted bytes, a same-transaction contract call,
and nested AssetOps before deployment.

Deployment uses only per-contract `ivm_contract_deploy` with exact chain and
NetworkId, authority fee payment, and current alias/state confirmation. Every
contract alias targets the universal dataspace, and retained deployment records
must name `dataspace_alias: "universal"` plus `dataspace_id: "0"` separately and
bind both to the exact native response and authenticated deployment state.
SoraSwap does not use `/v1/contracts/deploy`, contract-app bundles, split
deployment, aggregate bundle receipts, ambiguous top-level record `dataspace`,
or older signing DTOs.

The signed mutating-smoke gate requires the self-contained options factory's
buy, oracle-authorized mark publication, settlement, exercise, config, series,
automation, and position evidence. It also requires perps' own collateral-pool
and liquidation evidence. Retired risk-vault state and duplicate options-product
transactions are not accepted as first-release evidence.

## Incident and repair policy

Stop signed release work on non-JSON health, stale committed blocks, queue
saturation, excessive QC lag, listener failure, or divergent validator state.
Capture the current CLI doctor output and runtime logs without secrets.

`make taira-state-repair-plan` is evidence-only. It may record operator
observations and intended actions, but it does not mutate storage or invoke
removed upstream repair scripts. Any validator restart, state repair, or
redeployment must follow the current Iroha operator procedure and be followed
by a green `taira doctor`, an authorized write canary, a refreshed
`chain.latest.json`, and fresh SoraSwap evidence.

Never copy validator storage or clear consensus state from a SoraSwap command.
