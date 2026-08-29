# Perps State Layout

## Singleton state

- `PerpsInitialized`
- `PerpsOwner`
- `PerpsCollateralAsset`
- `PerpsCustodyAccount`
- `PerpsCollateralPoolBalance`
- `PerpsReservedMargin`
- `PerpsWithdrawalOnly`
- `PerpsOracleAccount`
- `PerpsAutomationExecutor`
- `PerpsFundingJobId`
- `PerpsLiquidationJobId`
- `PerpsAutomationCadence`
- `PerpsAutomationBacklogCap`
- `PerpsAutomationBacklog`
- `PerpsAutomationSafeMode`
- `PerpsLifecycleCadenceSlots`
- `PerpsLifecycleMaxItems`
- `PerpsLifecycleEnabled`
- `PerpsLifecycleNextSlot`
- `PerpsLifecycleMarketCursor`
- `PerpsLifecycleLastSlot`
- `PerpsLifecycleLastProcessed`
- `PerpsNextMarketId`
- `PerpsNextPositionId`

`PerpsCollateralPoolBalance` is the engine's accounted collateral in `PerpsCustodyAccount`; `PerpsReservedMargin` is the portion reserved for live positions. The invariant is `PerpsCollateralPoolBalance >= PerpsReservedMargin`. All ledger transfers use universal dataspace `0`.

## Per-market maps

- `PerpsMarketAsset`
- `PerpsMarketActive`
- `PerpsMarketOpenInterest`
- `PerpsMarketOpenInterestCap`
- `PerpsMarketMaxLeverageBps`
- `PerpsMarketMaintenanceMarginBps`
- `PerpsMarketLiquidationFeeBps`
- `PerpsMarketFundingBps`
- `PerpsMarketFundingIntervalSlots`
- `PerpsMarketOracleStaleSlots`
- `PerpsMarketBacklogLimit`
- `PerpsMarketUtilisationClampBps`
- `PerpsMarketLiquidationStressLimit`
- `PerpsMarketLastMarkPrice`
- `PerpsMarketLastIndexPrice`
- `PerpsMarketLastConfidenceBps`
- `PerpsMarketLastOracleSlot`
- `PerpsMarketLastOracleAttestationHash`
- `PerpsMarketGuardFlags`
- `PerpsMarketQueuedLiquidations`
- `PerpsMarketActivePositionCount`
- `PerpsMarketScanCursor`
- `PerpsMarketLastPassScanned`
- `PerpsMarketLastPassQueued`
- `PerpsMarketLastPassRecovered`
- `PerpsMarketLastPassLiquidated`
- `PerpsMarketLastNativeFundingDelta`
- `PerpsMarketLastNativePassSlot`

The configured oracle account publishes the typed mark, index, confidence, slot, and attestation fields. `PerpsMarketLastOracleSlot` enforces monotonic publication per market. Consumers additionally compare the cached slot with `block_height()` and `PerpsMarketOracleStaleSlots`.

## Per-position maps

- `PerpsPositionOwner`
- `PerpsPositionMarketId`
- `PerpsPositionSize`
- `PerpsPositionMargin`
- `PerpsPositionEntryPrice`
- `PerpsPositionMarkPrice`
- `PerpsPositionIndexPrice`
- `PerpsPositionFundingAccrued`
- `PerpsPositionRealizedPnl`
- `PerpsPositionStatus`
- `PerpsPositionActiveSlot`
- `PerpsPositionQueuedSlot`
- `PerpsPositionLastKeeperReward`
- `PerpsPositionLastOwnerResidual`
- `PerpsActivePositionBySlot`

Position status values are `0 = missing`, `1 = open`, `2 = closed`, `3 = queued for liquidation`, and `4 = liquidated`. `PerpsActivePositionBySlot` is a dense, market-qualified scan table maintained with swap removal; `PerpsPositionActiveSlot` is its reverse index.

## View tuple ordering

`main()` returns `PerpsInitialized`.

`engine_config()` returns:

1. collateral asset
2. custody account
3. oracle account
4. withdrawal-only flag
5. next market ID
6. next position ID
7. funding job ID
8. liquidation job ID
9. automation backlog cap

`collateral_pool_state()` returns:

1. custody account
2. pool balance
3. reserved margin
4. unreserved surplus

`market_state(market_id)` returns:

1. registered flag
2. active flag
3. open interest
4. open-interest cap
5. maximum leverage bps
6. maintenance-margin bps
7. liquidation-fee bps
8. funding bps
9. funding interval slots
10. oracle stale slots
11. queued liquidations
12. guard flags
13. backlog limit

`market_oracle_state(market_id)` returns:

1. mark price bps
2. index price bps
3. confidence bps
4. oracle slot
5. attestation identifier

`position_state(position_id)` returns:

1. registered flag
2. status
3. market ID
4. size
5. margin
6. funding accrued
7. realized PnL
8. entry price bps
9. last mark price bps
10. last index price bps
11. queued slot

`position_liquidation_state(position_id)` returns queued slot, last keeper reward, and last owner residual.

`liquidation_state(market_id)` returns active-position count, scan cursor, queued count, and the most recent scanned, queued, recovered, and liquidated counters.

`risk_state(market_id)` returns open interest, open-interest cap, queued count, utilisation bps, guard flags, automation backlog, automation safe-mode flag, and withdrawal-only flag.

`automation_state()` returns executor-bound flag, funding job ID, liquidation job ID, cadence, backlog cap, backlog, and safe-mode flag.

`trigger_lifecycle_state()` returns enabled flag, cadence slots, maximum items, next slot, market cursor, last slot, and last processed count.

## Operational invariants

- The deployer, custody account, and oracle account are distinct.
- The custody account cannot self-credit a collection or receive a positive settlement through a no-op self-transfer.
- The engine begins in withdrawal-only mode.
- Oracle authority can rotate only while withdrawal-only.
- Every open or queued position's margin contributes to `PerpsReservedMargin`.
- Closing, margin removal, and liquidation cannot reduce the pool below the remaining reserved margin.
- Owner surplus withdrawal is limited to `pool balance - reserved margin` and is available only while withdrawal-only.
- Cached oracle data is accepted only from the configured account, is strictly monotonic by market, and must remain fresh at use time.
