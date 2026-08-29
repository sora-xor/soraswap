# SCCP Bridge Interface

Contract: `contracts/bridge/sccp_bridge.ko`

Public entrypoints:
- `main() -> int`
- `hajimari(listing_fee_asset, treasury, listing_fee_amount, proof_authority, guardian)`
- `set_proof_authority(proof_authority)`
- `set_registry_enabled(enabled)`
- `register_bridge_asset(asset_key, asset, home_domain, decimals)`
- `bind_asset_vault(asset_key, vault_account)`
- `activate_route(route, asset_key, remote_domain)`
- `activate_route_governed(message_id, route, asset_key, remote_domain)`
- `pause_route(route)`
- `emergency_pause_route(route)`
- `resume_route(route)`
- `lock_to_remote(route, transfer, recipient, amount) -> int`
- `finalize_inbound(route, message_id, recipient, amount)`
- `listing_config() -> (AssetDefinitionId, AccountId, quantity, int)`
- `bridge_authorities() -> (AccountId, AccountId, AccountId)`
- `mirror_asset(asset_key) -> (int, int, int, quantity)`
- `asset_config(asset_key) -> (AssetDefinitionId, AccountId, int, int)`
- `asset_vault_bound(asset_key) -> int`
- `asset_vault_account(asset_key) -> AccountId`
- `mirror_route(route) -> (int, int, int, int)`
- `route_config(route) -> (Name, int, AssetDefinitionId, AccountId)`
- `route_provenance(route) -> (int, Name)`
- `mirror_outbound(transfer) -> (int, quantity, int, int)`
- `outbound_config(transfer) -> (Name, AccountId, Name, quantity)`
- `inbound_consumed(message_id) -> int`

Notes:
- Route ownership is bound to `authority()` when the route is activated.
- `hajimari(...)` binds `BridgeOwner = authority()`, the release proof authority, and the guardian. Bootstrap defaults `proof_authority` to the deployment authority unless `SORASWAP_BRIDGE_PROOF_AUTHORITY` is set.
- `register_bridge_asset(...)` binds the registrant to `authority()`. Vault binding is the separate `bind_asset_vault(...)` mutation; route activation accepts only the route, registered asset key, and remote domain.
- `set_proof_authority(...)` is owner-only. `activate_route_governed(...)` and `finalize_inbound(...)` require the proof authority so proof-managed settlement cannot be driven by arbitrary callers.
- Once a route is proof-governed, repeated governed activation is idempotent only for the same `message_id`; a different governance message cannot rewrite route provenance while preserving the same asset/domain fields.
- Listing, outbound locking, and inbound settlement now use canonical stored assets/accounts and caller-bound sender identity only.
- Asset-moving entrypoints retain a neutral `permission(AssetOps)` compiler hint because current Kotodama still requires an effect hint on public syscall emitters.
- The canonical release gate is proof-driven Torii relay submission through `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make test-contract-console-testnet`, which exercises the real Python console against deployed `testnet` evidence and submits `/v1/bridge/proofs/submit` plus `/v1/bridge/messages`.
- The Taira console path rejects caller-supplied `settlement.payload` on bridge message submission so release evidence cannot fall back to raw settlement blobs.
- Release evidence requires a fresh, previously unconsumed message whose proof and message transaction statuses are exact `Applied` or `Committed`. Rejected, replayed, skipped, or substring statuses such as `NotApplied` do not satisfy the first-release gate.
