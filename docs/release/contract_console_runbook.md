# Contract Console Runbook

## Read-Only Session
```bash
make contract-console \
  CONTRACT_CONSOLE_ARGS="--authority testnet=i105..."
```

Expected signals:
- the environment banner shows the deployment Torii URL
- `testnet` shows `Mutations: disabled (testnet)`
- the catalog lists only contracts backed by a current per-contract deploy record plus a stamped manifest whose code and ABI hashes match that evidence; it displays the record's separate universal dataspace alias and numeric ID as `universal (0)`
- SCCP capabilities and the authoritative typed registry load without a signer
- SCCP recent-message and remote transaction-history reads are capped at `100` rows per request, with `from` and `offset` capped at `10000`; raw GET proxy query strings are capped at `4096` characters and `32` parsed fields before forwarding
- browser POST APIs reject caller-supplied private-key, secret, mnemonic, token/API-key, authorization, password, or passphrase fields at any nesting level, including read-only view and bridge-inspection requests
- local console and trader access logs redact those same sensitive query-parameter values, including JSON-like query payloads containing sensitive keys, and truncate long non-sensitive query values before writing request lines to stderr
- local JSON proxy requests require non-empty POST bodies to use `application/json` or `application/*+json`; they reject malformed `Content-Length` headers, invalid UTF-8 bodies, bodies larger than `1 MiB`, and browser/API gas limits outside `1..50000000`; local Torii proxy responses are capped at `10 MiB`
- static UI, JSON API, and trader SSE responses include the expected no-store, no-sniff, frame-deny, no-referrer, restrictive permissions, same-origin, and self-hosted CSP headers

## Mutation-Enabled Taira Session
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make contract-console \
  CONTRACT_CONSOLE_ARGS="--signer testnet=$SORASWAP_CLIENT_CONFIG --authority testnet=$SORASWAP_AUTHORITY"
```

Expected signals:
- the environment banner shows `testnet`
- the signer is configured
- `Mutations: enabled (testnet)`
- the Torii URL source is `deployment`

After a sensitive signed session, click **Clear Operator State** before closing the tab. This clears browser-local recent signed actions, tracked transaction statuses, bridge bookmarks, and SCCP proof lookup history without touching signer config files.

Startup gate:
- with `SORASWAP_ALLOW_TESTNET_MUTATIONS=1`, the console refuses to bind if `docs/parity/migration_register.md` is missing, empty, has no `ported` production row, or still contains non-reference production rows outside `ported`
- with `SORASWAP_ALLOW_TESTNET_MUTATIONS=1`, the console refuses to bind if `deployments/testnet/chain.latest.json`, `preflight.latest.json`, `nested_call_probe.latest.json`, `deploy.latest.json`, an exact current-source `contracts.latest.json`, or per-contract `*.deploy.json` plus `*.manifest.json` evidence is missing, lacks `generated_at`, has a preflight report that is not ready for the current saved chain, signer/oracle environment, and current supported nested-call probe, has an unsupported or stale nested-call probe, has a `contracts.latest.json` snapshot without `status: "completed"`, has a `deploy.latest.json` report without completed preflight, compile, nested-call-probe, deploy, bootstrap, and deployment-snapshot phases plus non-bypassed signer readiness, has a chain snapshot without `torii_url`, `chain`, or `block_1_hash`, has mismatched selected-environment/contract-key metadata, points at a different chain id plus block-1 hash, or carries anything other than the exact current native `ivm_contract_deploy` record and five-field contracts-snapshot DTOs
- deployment bundles, ambiguous predecessor top-level record `dataspace`, synthetic instance evidence, recovered alias records, and predecessor response fields are not startup inputs; their presence never repairs missing current deployment evidence, and operators must perform a fresh native deployment instead
- remove `SORASWAP_ALLOW_TESTNET_MUTATIONS` for a read-only troubleshooting session when public evidence is intentionally incomplete

## Signed Taira Verification
Signed DeFi rehearsal:
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet
```

Console-only bridge proof lane:
```bash
export SORASWAP_CLIENT_CONFIG=/absolute/path/to/taira.client.toml
SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet
```

Readonly validation lane:
```bash
make smoke-testnet-readonly
```

Parallel production wrappers reuse the same evidence shape with a production-specific mutation gate:
```bash
export SORASWAP_PRODUCTION_CLIENT_CONFIG=/absolute/path/to/production.client.toml
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make smoke-production
SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make test-contract-console-production
make smoke-production-readonly
```

The production signer file must be inside the checkout, Git-ignored and untracked, owned by the effective user, mode `0600`, and single-link with no symlink traversal. Authenticated/signed upstream responses are suppressed if they echo the bound Basic credential or signer material; curl trace, remote-name, external header-dump, and external stderr-file options are not permitted on protected public requests.

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
- `contract_console_smoke.latest.json.status == "completed"`
- `contract_console_smoke.latest.json.bridge.route_provenance[0] == 1`
- `contract_console_smoke.latest.json.bridge.message_submit_entrypoint == "finalize_inbound"`, `proof_driven_settlement == true`, and `settlement_payload_supplied == false`
- `contract_console_smoke.latest.json.bridge.submission_expectation == "apply"`, `message_selection` identifies a previously unconsumed finalized transfer, and both proof and message submit reach exact `status_kind` values of `Committed` or `Applied`; rejected, skipped, replayed, or substring statuses such as `NotApplied` do not satisfy the release gate

Operator notes:
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet` no longer calls `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet` internally. Run both targets for the full signed Taira release gate.
- `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet` requires a live unconsumed message. Saved evidence may identify a candidate only while the current `inbound_consumed` view is still exactly zero; otherwise the run stops and requires a fresh finalized transfer.
- `test-contract-console-testnet` fails if the app API skips standalone bridge proof submission or either signed transaction does not reach exact `Applied` or `Committed` status.

Expected failure signals:
- missing `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` for Taira, or `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1` for production, in the UI banner or shell
- `browser JSON must not include private keys, secrets, mnemonics, tokens, authorization, passwords, or passphrases`
- `unsupported bridge submit fields: ...` when advanced proof/message JSON includes a top-level field outside the bridge submit allowlist
- signer-config Torii mismatch warnings
- bridge message submission rejection because `settlement.payload` was supplied manually

## Timeout Handling
- A pending transaction tracker in the UI eventually marks the request `TimedOut` when no terminal pipeline status arrives.
- Treat timeout as operationally unresolved, not as success.
- Re-check `/api/pipeline/transactions/status`, remote history, and the target contract view before retrying.

## Rollback And Disable
- Remove `SORASWAP_ALLOW_TESTNET_MUTATIONS` and restart the console to force Taira back behind the mutation gate.
- Remove `SORASWAP_ALLOW_PRODUCTION_MUTATIONS` and restart the console to force production back behind the mutation gate.
- Close the console server after the operator session.
- If bridge proof relay fails or reverts to raw-input-only handling, the Taira gate has failed.
- If the shared derivatives acceptance bar regresses, roll back the whole derivatives claim together.
