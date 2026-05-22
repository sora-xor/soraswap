# SCCP Bridge Interface

Contract: `contracts/bridge/sccp_bridge.ko`

Public entrypoints:
- `main() -> int`
- `init_bridge(listing_fee_asset, treasury, listing_fee_amount, proof_authority)`
- `set_proof_authority(proof_authority)`
- `register_asset(asset_key, asset, home_domain, decimals)`
- `bind_asset_vault(asset_key, vault_account)`
- `activate_route(route, asset_key, remote_domain, local_asset, vault_account)`
- `activate_route_governed(message_id, route, asset_key, remote_domain)`
- `pause_route(route)`
- `resume_route(route)`
- `lock_to_remote(route, transfer, recipient, amount) -> int`
- `finalize_inbound(route, message_id, recipient, amount)`
- `listing_config() -> (AssetDefinitionId, AccountId, int, int)`
- `bridge_authorities() -> (AccountId, AccountId)`
- `mirror_asset(asset_key) -> (int, int, int, int)`
- `asset_config(asset_key) -> (AssetDefinitionId, int, int)`
- `asset_vault_bound(asset_key) -> int`
- `asset_vault_account(asset_key) -> AccountId`
- `mirror_route(route) -> (int, int, int, int)`
- `route_config(route) -> (Name, int, AssetDefinitionId, AccountId)`
- `route_provenance(route) -> (int, Name)`
- `mirror_outbound(transfer) -> (int, int, int, int)`
- `outbound_config(transfer) -> (Name, AccountId, Name, int)`
- `inbound_consumed(message_id) -> int`

Notes:
- Route ownership is bound to `authority()` when the route is activated.
- `init_bridge(...)` binds both `BridgeOwner = authority()` and the release proof authority. Bootstrap defaults `proof_authority` to the deployment authority unless `SORASWAP_BRIDGE_PROOF_AUTHORITY` is set.
- `set_proof_authority(...)` is owner-only. `activate_route_governed(...)` and `finalize_inbound(...)` require the proof authority so proof-managed settlement cannot be driven by arbitrary callers.
- Listing, outbound locking, and inbound settlement now use canonical stored assets/accounts and caller-bound sender identity only.
- Asset-moving entrypoints retain a neutral `permission(AssetOps)` compiler hint because current Kotodama still requires an effect hint on public syscall emitters.
- The canonical release gate is proof-driven Torii relay submission through `make test-contract-console-testnet`, which exercises the real Python console against deployed `testnet` evidence and submits `/v1/bridge/proofs/submit` plus `/v1/bridge/messages`.
- The Taira console path rejects caller-supplied `settlement.payload` on bridge message submission so release evidence cannot fall back to raw settlement blobs.
