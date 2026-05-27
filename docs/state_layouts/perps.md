# Perps State Layout

Singleton scalar state:
- `PerpsInitialized`
- `PerpsOwner`
- `PerpsCollateralAsset`
- `PerpsRiskVaultContract`
- `PerpsContractBound`
- `PerpsContractId`
- `PerpsWithdrawalOnly`
- `PerpsOraclePublicKey`
- `PerpsOracleScheme`
- `PerpsAutomationExecutor`
- `PerpsFundingJobId`
- `PerpsLiquidationJobId`
- `PerpsAutomationCadence`
- `PerpsAutomationBacklogCap`
- `PerpsAutomationBacklog`
- `PerpsAutomationSafeMode`
- `PerpsNextMarketId`
- `PerpsNextPositionId`
- `PerpsLifecycleCadenceSlots`
- `PerpsLifecycleMaxItems`
- `PerpsLifecycleEnabled`
- `PerpsLifecycleNextSlot`
- `PerpsLifecycleMarketCursor`
- `PerpsLifecycleLastSlot`
- `PerpsLifecycleLastProcessed`

Per-market maps:
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

Per-position maps:
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

View tuple fields returned by `engine_config()`:
- `soraswap_perps_collateral_asset`
- `soraswap_perps_risk_vault_contract`
- `soraswap_perps_withdrawal_only`
- `soraswap_perps_next_market_id`
- `soraswap_perps_next_position_id`
- `soraswap_perps_funding_job_id`
- `soraswap_perps_liquidation_job_id`
- `soraswap_perps_automation_backlog_cap`

View tuple fields returned by `market_state()`, `market_oracle_state()`, `position_state()`, `position_liquidation_state()`, `liquidation_state()`, `risk_state()`, and `automation_state()` cover:
- market registration, activity, caps, guard flags, queued liquidations, last oracle marks, last oracle slot, last attestation hash, and the most recent bounded liquidation-pass counters
- position registration, status, market id, size, margin, funding accrued, realized PnL, queued slot, and the last keeper/residual settlement amounts
- market risk snapshots for utilisation, backlog, safe mode, and withdrawal-only state
- automation executor/job binding and cadence metadata
- bucket `1` liability routing through `risk_vault`, keyed by `position_id`
- `PerpsRiskVaultContract` stores the deployed `risk_vault` contract address literal as UTF-8 `bytes` for the ABI v1 `call_contract(...)` target; `bind_risk_vault(...)` rewrites that target without disturbing live market state. `engine_config()` exposes the stored bytes as a hex string.
- `PerpsOraclePublicKey` and `PerpsOracleScheme` are init-only for v1. Signed payloads must use domain `1`, include market price fields plus `oracle_slot`, `status_flags`, and `attestation_hash`, and pass strict monotonic slot checks against `PerpsMarketLastOracleSlot`.

Operational note:
- `admin_repair_orphan_position(...)` does not add new storage, but it can move a stale live `PerpsPositionStatus` from `1=open` or `3=queued liquidation` to `2=closed` while zeroing size/margin, clearing queued/active index slots, and decrementing market open interest when bootstrap detects a position whose `risk_vault` bucket-1 liability record has already disappeared.
