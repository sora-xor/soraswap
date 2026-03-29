# Launchpad Interface

Contract: `contracts/launchpad/sale_factory.ko`

Public entrypoints:
- `main() -> int`
- `init_sale(sale, sale_asset, payment_asset, treasury, unit_price, hard_cap)`
- `configure_sale(sale, unit_price, soft_cap, hard_cap)`
- `configure_vesting(sale, claim_start_slot, claim_end_slot)`
- `contribute(buyer, sale, payment_amount) -> int`
- `contribute_with_assets(buyer, sale, treasury, payment_asset, sale_asset, payment_amount) -> int`
- `contribute_recorded(buyer, sale, allocation, payment_amount) -> int`
- `contribute_recorded_with_assets(buyer, sale, allocation, treasury, payment_asset, payment_amount) -> int`
- `close_sale(sale)`
- `deposit_claim_inventory(owner, sale, amount) -> int`
- `deposit_claim_inventory_with_assets(owner, sale, treasury, sale_asset, amount) -> int`
- `deposit_seed_inventory(owner, sale, amount) -> int`
- `deposit_seed_inventory_with_assets(owner, sale, treasury, sale_asset, amount) -> int`
- `claim_allocation(buyer, allocation, current_slot) -> int`
- `claim_allocation_with_assets(buyer, allocation, treasury, sale_asset, current_slot) -> int`
- `refund_allocation(buyer, allocation) -> int`
- `refund_allocation_with_assets(buyer, allocation, treasury, payment_asset) -> int`
- `register_seed_liquidity(sale, position_id, vault_account, bin_id, payment_amount, sale_amount)`
- `seed_liquidity(sale) -> int`
- `seed_liquidity_with_assets(sale, treasury, vault_account, payment_asset, sale_asset) -> int`
- `mark_seeded(sale)`
- `sale_config(sale) -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- `mirror_sale(sale) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`
- `mirror_sale_accounting(sale) -> (int, int, int, int)`
- `mirror_allocation(allocation) -> (int, int, int, int, int)`

Notes:
- `init_sale` keeps the repo’s minimal fixed-price flow but now defaults the soft cap to `1` so successful close is tied to actual contributions instead of a placeholder flag.
- `contribute*` remains the compatibility path that mints sale output immediately, while `contribute_recorded*` records a named allocation for later claim or refund settlement.
- `configure_vesting` stores a per-sale linear vesting window. When `claim_end_slot == claim_start_slot`, the allocation becomes fully claimable at `claim_start_slot`.
- `deposit_claim_inventory*` stages sale-token inventory for contributor claims. `claim_allocation*` transfers only the currently vested delta, updates `ClaimInventory` and `ClaimedSupply`, and refuses claims on failed or refunded allocations.
- `refund_allocation*` returns the recorded payment amount for failed sales, marks the allocation refunded, and increases `RefundedPayment` so already-returned proceeds cannot also be reused for DLMM seeding.
- `deposit_seed_inventory*` records sale-token inventory that can be paired with raised payment proceeds for DLMM seeding after the sale closes.
- `register_seed_liquidity` stores an explicit DLMM seed plan keyed by `sale`, including a `position_id`, destination `vault_account`, target `bin_id`, and the planned payment/sale token amounts.
- `seed_liquidity*` consumes the registered plan, debits available sale proceeds plus deposited seed inventory, and records the committed amounts. The actual downstream DLMM pool mutation is still orchestrated by scripts or external callers.
- `mark_seeded` remains as a compatibility alias for the stored-plan path and now executes the same accounting checks as `seed_liquidity`.
- The `*_with_assets` entrypoints remain the compatibility path for live nodes where host decoding of state-loaded asset or account pointers can still be brittle.
- `sale_config`, `mirror_sale`, `mirror_sale_accounting`, and `mirror_allocation` are `view fn` entrypoints consumed through `/v1/contracts/view`.
