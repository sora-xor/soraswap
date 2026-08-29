# Launchpad Interface

Contracts:
- `contracts/launchpad/sale_factory.ko`
- `contracts/launchpad/liquidity_executor.ko`

`sale_factory.ko` lifecycle and entrypoints:
- `hajimari(executor_contract, guardian)`
- `main() -> int`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `native_lifecycle_tick()`
- `init_sale(sale, sale_asset, payment_asset, treasury, unit_price, soft_cap, hard_cap, claim_start_slot, claim_end_slot)`
- `contribute_recorded(sale, allocation, payment_amount) -> quantity`
- `close_sale(sale)`
- `deposit_seed_inventory(sale, amount) -> quantity`
- `deposit_claim_inventory(sale, amount) -> quantity`
- `configure_seed_liquidity(sale, payment_amount, sale_amount)`
- `seed_liquidity(sale) -> quantity`
- `finalize_sale_activation(sale, claim_inventory_amount) -> quantity`
- `claim_allocation(allocation) -> quantity`
- `refund_allocation(allocation) -> quantity`
- `sale_config(sale) -> (AssetDefinitionId, AssetDefinitionId, AccountId, decimal, quantity, quantity, int, int)`
- `mirror_sale(sale) -> (int, quantity, quantity, int, int, int, quantity, quantity, quantity, quantity, quantity, quantity, quantity)`
- `mirror_sale_accounting(sale) -> (quantity, quantity, quantity, quantity)`
- `mirror_allocation(allocation) -> (int, quantity, quantity, quantity, int)`
- `factory_config() -> (AccountId, AccountId, AccountId, bytes, int)`
- `activation_state(sale) -> (int, quantity)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

`liquidity_executor.ko` lifecycle and entrypoints:
- `hajimari(pool_contract, base_asset, quote_asset, sale_factory_account, guardian)`
- `main() -> int`
- `set_paused(paused)`
- `executor_config() -> (bytes, AssetDefinitionId, AssetDefinitionId, AccountId, AccountId, AccountId, AccountId, int)`
- `seed_count() -> int`
- `liquidity_state() -> (int, quantity, quantity, quantity, int)`
- `seed_liquidity(amount_in, min_out) -> quantity`

Notes:
- Both contracts derive custody from `context::seiyaku_subject()` during `hajimari(...)`. The deployer cannot inject or later rebind either custody account.
- Owner, guardian, factory subject, and executor subject are separate authorities. Both contracts start fail-closed: the factory starts withdrawal-only and the executor starts paused. Only the owner can open their forward paths; the guardian can close them.
- Factory-to-executor and executor-to-pool calls use Iroha's exact current Quantity2 ABI `(amount_in: quantity, min_out: quantity) -> quantity`. On this custody-only path, `amount_in` is the base/payment deposit and `min_out` is the quote/sale deposit; `min_out` is not a slippage threshold.
- `configure_seed_liquidity(...)` records only the per-sale asset amounts. Position identity and bin selection are not caller-controlled: the pool owns one executor position at its immutable initialization bin.
- `finalize_sale_activation(...)` is the canonical production activation path. It closes the sale if needed, optionally stages claim inventory, invokes the pinned executor, records the returned shares per sale, and releases only the payment proceeds left after seeding.
- Failed nested calls roll back the factory-to-executor transfers, executor-to-pool transfers, and all activation accounting in the same transaction.
- Recorded allocations through `contribute_recorded(...)` are the only purchase path. Allocation ownership is caller-bound, and claim-window checks use `block_height()` internally.
- `soraswap_launchpad_lifecycle_tick` is a bounded time trigger registered on `schedule(20000, 120000)`. It closes due sales; liquidity activation remains an explicit sale-owner path so an automation callback cannot choose custody, position, or bin parameters.
- This is a first-release interface. Removed init/bind methods, arbitrary funding accounts, arbitrary position/bin seed parameters, and compatibility aliases are intentionally unsupported.
