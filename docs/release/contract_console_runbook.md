# Contract Console Runbook

## Read-Only Session
```bash
make contract-console \
  CONTRACT_CONSOLE_ARGS="--authority testnet=i105..."
```

Expected signals:
- the environment banner shows the deployment Torii URL
- `testnet` shows `Mutations: disabled (testnet)`
- SCCP capabilities and manifests load without a signer

## Mutation-Enabled Taira Session
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
make contract-console \
  CONTRACT_CONSOLE_ARGS="--signer testnet=$SORASWAP_CLIENT_CONFIG --authority testnet=$SORASWAP_AUTHORITY"
```

Expected signals:
- the environment banner shows `testnet`
- the signer is configured
- `Mutations: enabled (testnet)`
- the Torii URL source is `deployment`

## Signed Taira Verification
Signed DeFi rehearsal:
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
make smoke-testnet
```

Console-only bridge proof lane:
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
make test-contract-console-testnet
```

Readonly compatibility lane:
```bash
make smoke-testnet-readonly
```

Parallel production wrappers reuse the same mutation gate and evidence shape:
```bash
export SORASWAP_PRODUCTION_CLIENT_CONFIG=/absolute/path/to/production.client.toml
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
make smoke-production
make test-contract-console-production
make smoke-production-readonly
```

Optional route override when the bundle cannot derive it:
```bash
export SORASWAP_TESTNET_BRIDGE_ROUTE=<route_id>
```

Optional message-id override for targeted debugging:
```bash
export SORASWAP_TESTNET_BRIDGE_MESSAGE_ID=<live_message_id>
```

Production wrapper equivalents:
```bash
export SORASWAP_PRODUCTION_BRIDGE_ROUTE=<route_id>
export SORASWAP_PRODUCTION_BRIDGE_MESSAGE_ID=<live_message_id>
```

Expected success signals:
- `deployments/testnet/smoke.latest.json`
- `deployments/testnet/contract_console_smoke.latest.json`
- `contract_console_smoke.latest.json.bridge.route_provenance[0] == 1`
- `contract_console_smoke.latest.json.bridge.submission_expectation == "apply"` with proof/message submit reaching `Committed` or `Applied`
- or `contract_console_smoke.latest.json.bridge.submission_expectation == "replay_reject"` with replay evidence recorded against the cached bridge message and the rejection decoding to replay/duplicate/consumed/proof-overlap semantics, or to the current generic bridge-contract `assertion failed (constraint violation)` rejection when Taira drops the original contract string

Operator notes:
- `make smoke-testnet` no longer calls `make test-contract-console-testnet` internally. Run both targets for the full signed Taira release gate.
- `make test-contract-console-testnet` prefers a live unconsumed message. When Taira SCCP discovery is unavailable, the newest saved console evidence in `deployments/testnet/` or `deployments/testnet/archive/` already points at a consumed message, or recent live inventory only exposes consumed SORA-targeted transfers, it falls back to replay evidence and verifies the replay path instead of mutating a second time.

Expected failure signals:
- missing `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` in the UI banner or shell
- `private_key must not be supplied in browser JSON`
- signer-config Torii mismatch warnings
- bridge message submission rejection because `settlement.payload` was supplied manually

## Timeout Handling
- A pending transaction tracker in the UI eventually marks the request `TimedOut` when no terminal pipeline status arrives.
- Treat timeout as operationally unresolved, not as success.
- Re-check `/api/pipeline/transactions/status`, remote history, and the target contract view before retrying.

## Rollback And Disable
- Remove `SORASWAP_ALLOW_TESTNET_MUTATIONS` and restart the console to force Taira back behind the mutation gate.
- Close the console server after the operator session.
- If bridge proof relay fails or reverts to raw-input-only handling, the Taira gate has failed.
- If the shared derivatives acceptance bar regresses, roll back the whole derivatives claim together.
