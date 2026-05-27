# Launchpad Interface

Contracts:
- `contracts/launchpad/sale_factory.ko`
- `contracts/launchpad/liquidity_executor.ko`

`sale_factory.ko` public entrypoints:
- `main() -> int`
- `init_factory()`
- `init_sale(sale, sale_asset, payment_asset, treasury, unit_price, soft_cap, hard_cap, claim_start_slot, claim_end_slot)`
- `bind_contract(contract_id)`
- `bind_executor(executor_contract)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `native_lifecycle_tick()`
- `contribute(sale, payment_amount) -> int`
- `contribute_recorded(sale, allocation, payment_amount) -> int`
- `close_sale(sale)`
- `deposit_seed_inventory(sale, amount) -> int`
- `deposit_claim_inventory(sale, amount) -> int`
- `register_seed_liquidity(sale, position_id, vault_account, bin_id, payment_amount, sale_amount)`
- `seed_liquidity(sale) -> int`
- `finalize_sale_activation(sale, claim_inventory_amount) -> int`
- `claim_allocation(allocation) -> int`
- `refund_allocation(allocation) -> int`
- `mark_seeded(sale)`
- `sale_config(sale) -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- `mirror_sale(sale) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`
- `mirror_sale_accounting(sale) -> (int, int, int, int)`
- `factory_binding_state() -> (int, int)`
- `factory_owner_state() -> (int, AccountId)`
- `factory_binding_details() -> (AccountId, bytes, int, int)`
- `activation_state(sale) -> (int, int)`
- `mirror_allocation(allocation) -> (int, int, int, int, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

`liquidity_executor.ko` public entrypoints:
- `main() -> int`
- `init_executor(pool_contract, base_asset, quote_asset)`
- `bind_contract(contract_id)`
- `bind_sale_factory(factory_contract)`
- `executor_config() -> (AssetDefinitionId, AssetDefinitionId, int, int)`
- `seed_liquidity(funding_account, bin_id, base_amount, quote_amount) -> int`

Notes:
- Sale config is init-only; post-init asset override entrypoints remain removed.
- `init_factory()` must be called before any owner-gated setup. The factory owner is explicit instead of lazily captured on first admin use.
- Direct `contribute(...)` is retained only as a hard-rejecting compatibility trap; recorded allocations through `contribute_recorded(...)` are the only purchase path.
- Recorded-allocation flows are caller-bound through `authority()`.
- Claim window checks use `block_height()` internally; callers no longer provide a current slot.
- `register_seed_liquidity(...)` records the seed plan before activation; it does not require the sale to be closed because `finalize_sale_activation(...)` closes and activates in one signed path.
- `finalize_sale_activation(...)` is the canonical production activation path. It closes the sale if needed, deposits claim inventory when provided, stages both seed assets through the factory contract subject, then invokes the dedicated executor contract to seed DLMM liquidity on chain.
- The release path does not rely on an operator-only off-chain seeding workflow. `liquidity_executor.ko` is the only release-eligible bridge between launchpad sale proceeds and DLMM pool seeding.
- `soraswap_launchpad_lifecycle_tick` is a bounded pre-commit trigger. It closes due sales and auto-seeds only when the seed plan is contract-custodied; otherwise it marks activation pending for explicit completion.
