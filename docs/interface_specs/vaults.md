# Vaults Interface

Contract: `contracts/vaults/manager.ko`

Entrypoints:
- `hajimari()`
- `main() -> int`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `register_vault(vault_id, underlying_asset, share_asset, custody_account, strategy_code, async_redeem)`
- `deposit(vault_id, position_id, amount)`
- `request_redeem(vault_id, request_id, position_id, shares, claim_slot)`
- `claim_redeem(request_id)`
- `native_lifecycle_tick()`
- `vault_state(vault_id) -> (int, int, int, quantity, quantity)`
- `position_state(position_id) -> quantity`
- `request_state(request_id) -> (int, quantity, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

Notes:
- The first launch vault is expected to use the `n3x` basket as underlying strategy input.
- Every vault fixes its own custody account at registration.
- Position ids are bound to the depositing caller and vault on first use.
- Async redemption requests are explicit and claim-gated by contract `block_height()`.
- `soraswap_vault_lifecycle_tick` is a bounded time trigger registered on a `schedule(100000, 120000)` native schedule. It still enforces the configured slot cadence inside the contract and marks async redemption requests ready once their claim slot has elapsed; the owner still calls `claim_redeem`.
