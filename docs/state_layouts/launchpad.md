# Launchpad State Layout

Sale factory singleton state:
- immutable initialization: `FactoryInitialized`, `FactoryOwner`, `FactoryGuardian`, `FactoryAccount`, `SeedExecutorContract`
- fail-closed mode: `FactoryWithdrawalOnly`
- bounded lifecycle: `LaunchLifecycleCadenceSlots`, `LaunchLifecycleMaxItems`, `LaunchLifecycleEnabled`, `LaunchLifecycleNextSlot`, `LaunchLifecycleCursor`, `LaunchLifecycleLastSlot`, `LaunchLifecycleLastProcessed`, `NextSaleIndex`, `SaleByIndex`

Per-sale maps:
- identity and terms: `SaleOwner`, `SaleAsset`, `PaymentAsset`, `Treasury`, `UnitPrice`, `SoftCap`, `HardCap`, `ClaimStartSlot`, `ClaimEndSlot`
- lifecycle totals: `Raised`, `Sold`, `Closed`, `Successful`, `Seeded`
- custody accounting: `SeedInventory`, `ClaimInventory`, `ClaimedSupply`, `RefundedPayment`, `TreasuryPaymentReleased`
- seed plan and result: `SeedPaymentAmount`, `SeedSaleAmount`, `SeedPaymentUsed`, `SeedSaleUsed`, `SeedActivationShares`

Per-allocation maps:
- `AllocationSale`
- `AllocationBuyer`
- `AllocationPaymentAmount`
- `AllocationSaleAmount`
- `AllocationClaimed`
- `AllocationRefunded`

Liquidity executor singleton state:
- immutable initialization: `ExecutorInitialized`, `ExecutorOwner`, `ExecutorGuardian`, `PoolContract`, `BaseAsset`, `QuoteAsset`, `ExecutorContractAccount`, `SaleFactoryContractAccount`
- fail-closed mode: `ExecutorPaused`
- aggregate execution journal: `SeedCount`, `TotalBaseAmount`, `TotalQuoteAmount`, `TotalShares`, `LastSeedSlot`

View tuple fields returned by `mirror_sale()`:
1. sale exists
2. raised payment amount
3. sold sale-asset amount
4. closed
5. successful
6. seeded
7. remaining seed inventory
8. remaining claim inventory
9. claimed supply
10. refunded payment
11. seed payment used
12. seed sale amount used
13. seed activation shares

View tuple fields returned by `sale_config()`:
1. sale asset
2. payment asset
3. treasury
4. unit price
5. soft cap
6. hard cap
7. claim start slot
8. claim end slot

View tuple fields returned by `mirror_sale_accounting()`:
1. raised payment
2. treasury payment released
3. refunded payment
4. seed payment used

View tuple fields returned by `factory_config()`:
1. owner
2. guardian
3. factory contract subject
4. executor contract address bytes
5. withdrawal-only mode

View tuple fields returned by `activation_state(sale)`:
1. seeded
2. activation shares

View tuple fields returned by `mirror_allocation()`:
1. allocation exists
2. payment amount
3. sale amount
4. claimed amount
5. refunded

View tuple fields returned by `executor_config()`:
1. pool contract address bytes
2. base asset
3. quote asset
4. owner
5. guardian
6. executor contract subject
7. sale-factory contract subject
8. paused

View tuple fields returned by `liquidity_state()`:
1. seed count
2. total base amount
3. total quote amount
4. total shares
5. last seed slot

Notes:
- `FactoryAccount` and `ExecutorContractAccount` are captured from `context::seiyaku_subject()` and never accepted as deployer input. `SaleFactoryContractAccount` and both nested contract addresses are immutable.
- The factory owns per-sale plans and returned share attribution. The executor intentionally stores only aggregate execution totals; it cannot select a per-sale position or bin.
- The pool owns the single `launchpad_executor` position at its immutable initialization bin. No launchpad position, vault, or bin maps exist in either launchpad contract.
- `Raised` tracks payment-side proceeds. `RefundedPayment`, `SeedPaymentUsed`, and `TreasuryPaymentReleased` are the mutually constrained disposition totals for those proceeds.
- `ClaimInventory` tracks remaining contributor inventory and `ClaimedSupply` tracks settled inventory. `SeedInventory` tracks the independent sale-asset balance available for DLMM seeding.
- Claim and lifecycle scheduling uses chain `block_height()`, and only `contribute_recorded(...)` creates allocations. `SaleByIndex` and the hard sale limit bound every trigger scan.
- All transfers use `DataSpaceId::parse("0")`, the Taira universal dataspace.
