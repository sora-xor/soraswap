# Launchpad State Layout

Per-sale maps:
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

View tuple fields returned by `mirror_allocation()`:
- `soraswap_launchpad_allocation_registered`
- `soraswap_launchpad_allocation_payment_amount`
- `soraswap_launchpad_allocation_sale_amount`
- `soraswap_launchpad_allocation_claimed`
- `soraswap_launchpad_allocation_refunded`

Notes:
- `Raised` tracks total payment-side sale proceeds; `RefundedPayment` and `SeedPaymentUsed` partition the payment-side proceeds between refunds and committed DLMM seeding.
- `ClaimInventory` tracks remaining sale-token inventory available for contributor claims, while `ClaimedSupply` records the amount already settled out to buyers.
- `SeedInventory` tracks remaining sale-token inventory available for DLMM seeding, while `SeedSaleUsed` records the committed amount.
- `SeedPositionId`, `SeedVault`, `SeedBinId`, `SeedPaymentAmount`, and `SeedSaleAmount` together form the registered DLMM seed plan for a sale.
- The current layout is still single-seed per sale. Executor-driven cross-contract DLMM activation and separate vesting-vault contracts remain outside this repo slice.
