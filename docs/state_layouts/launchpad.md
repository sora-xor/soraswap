# Launchpad State Layout

Sale factory singleton state:
- `FactoryOwnerSet`
- `FactoryOwner`
- `FactoryContractBound`
- `FactoryContractId`
- `SeedExecutorBound`
- `SeedExecutorContract`

Per-sale maps:
- `SaleOwner`
- `SaleAsset`
- `PaymentAsset`
- `Treasury`
- `UnitPrice`
- `SoftCap`
- `HardCap`
- `Raised`
- `Sold`
- `Closed`
- `Successful`
- `Seeded`
- `SeedInventory`
- `SeedVault`
- `SeedPositionId`
- `SeedBinId`
- `SeedPaymentAmount`
- `SeedSaleAmount`
- `SeedPaymentUsed`
- `SeedSaleUsed`
- `SeedActivationValue`
- `ClaimInventory`
- `ClaimedSupply`
- `RefundedPayment`
- `ClaimStartSlot`
- `ClaimEndSlot`

Per-allocation maps:
- `AllocationSale`
- `AllocationBuyer`
- `AllocationPaymentAmount`
- `AllocationSaleAmount`
- `AllocationClaimed`
- `AllocationRefunded`

Liquidity executor singleton state:
- `ExecutorInitialized`
- `ExecutorOwner`
- `PoolContract`
- `BaseAsset`
- `QuoteAsset`
- `ExecutorContractBound`
- `ExecutorContractId`
- `SaleFactoryBound`
- `SaleFactoryContractId`

View tuple fields returned by `mirror_sale()`:
- `soraswap_launchpad_seed_registered`
- `soraswap_launchpad_raised`
- `soraswap_launchpad_sold`
- `soraswap_launchpad_closed`
- `soraswap_launchpad_successful`
- `soraswap_launchpad_seeded`
- `soraswap_launchpad_seed_inventory`
- `soraswap_launchpad_seed_bin_id`
- `soraswap_launchpad_seed_payment_amount`
- `soraswap_launchpad_seed_sale_amount`
- `soraswap_launchpad_claim_inventory`
- `soraswap_launchpad_claim_start_slot`
- `soraswap_launchpad_claim_end_slot`

View tuple fields returned by `sale_config()`:
- `soraswap_launchpad_sale_asset`
- `soraswap_launchpad_payment_asset`
- `soraswap_launchpad_treasury`
- `soraswap_launchpad_unit_price`
- `soraswap_launchpad_soft_cap`
- `soraswap_launchpad_hard_cap`
- `soraswap_launchpad_claim_start_slot_config`
- `soraswap_launchpad_claim_end_slot_config`

View tuple fields returned by `mirror_sale_accounting()`:
- `soraswap_launchpad_seed_payment_used`
- `soraswap_launchpad_seed_sale_used`
- `soraswap_launchpad_claimed_supply`
- `soraswap_launchpad_refunded_payment`

View tuple fields returned by `factory_binding_state()`:
- `soraswap_launchpad_factory_contract_bound`
- `soraswap_launchpad_seed_executor_bound`

View tuple fields returned by `factory_owner_state()`:
- `soraswap_launchpad_factory_owner_set`
- `soraswap_launchpad_factory_owner`

View tuple fields returned by `factory_binding_details()`:
- `soraswap_launchpad_factory_owner`
- `soraswap_launchpad_factory_contract_id`
- `soraswap_launchpad_factory_contract_bound`
- `soraswap_launchpad_seed_executor_bound`

View tuple fields returned by `activation_state(sale)`:
- `soraswap_launchpad_seed_executor_bound`
- `soraswap_launchpad_seed_activation_value`

View tuple fields returned by `mirror_allocation()`:
- `soraswap_launchpad_allocation_registered`
- `soraswap_launchpad_allocation_payment_amount`
- `soraswap_launchpad_allocation_sale_amount`
- `soraswap_launchpad_allocation_claimed`
- `soraswap_launchpad_allocation_refunded`

View tuple fields returned by `executor_config()`:
- `soraswap_launchpad_executor_base_asset`
- `soraswap_launchpad_executor_quote_asset`
- `soraswap_launchpad_executor_contract_bound`
- `soraswap_launchpad_executor_sale_factory_bound`

Notes:
- `Raised` tracks total payment-side sale proceeds; `RefundedPayment` and `SeedPaymentUsed` partition the payment-side proceeds between refunds and committed DLMM seeding.
- `ClaimInventory` tracks remaining sale-token inventory available for contributor claims, while `ClaimedSupply` records the amount already settled out to buyers.
- `SeedInventory` tracks remaining sale-token inventory available for DLMM seeding, while `SeedSaleUsed` records the committed amount.
- `SeedPositionId`, `SeedVault`, `SeedBinId`, `SeedPaymentAmount`, and `SeedSaleAmount` form the registered DLMM seed plan for a sale, while `SeedActivationValue` records the on-chain executor result for the canonical activation path.
- `FactoryOwnerSet` is explicit and is written only by `init_factory()`. Admin flows no longer lazily capture the first caller as owner.
- `claim_allocation(...)` uses `block_height()` internally for claim-window enforcement, and direct `contribute(...)` is a hard-rejecting trap; only `contribute_recorded(...)` creates allocations.
- Trigger lifecycle state is stored in `LaunchLifecycleCadenceSlots`, `LaunchLifecycleMaxItems`, `LaunchLifecycleEnabled`, `LaunchLifecycleNextSlot`, `LaunchLifecycleCursor`, `LaunchLifecycleLastSlot`, and `LaunchLifecycleLastProcessed`. `SaleByIndex` and `NextSaleIndex` bound trigger scans.
