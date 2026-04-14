# Options State Layout

Manager singleton state:
- `OptMgrInitialized`
- `OptMgrOwner`
- `OptMgrController`
- `OptMgrGuardian`
- `OptMgrSettlementAsset`
- `OptMgrWithdrawalOnly`
- `OptMgrAutomationExecutor`
- `OptMgrExpiryJobId`
- `OptMgrSettlementJobId`
- `OptMgrAutomationCadence`
- `OptMgrAutomationBacklogCap`
- `OptMgrAutomationBacklog`
- `OptMgrAutomationSafeMode`
- `OptMgrNextTemplateId`
- `OptMgrNextSeriesId`

Manager template maps:
- `OptMgrTemplateKind`
- `OptMgrTemplateUnderlyingAsset`
- `OptMgrTemplateQuoteAsset`
- `OptMgrTemplateTenorSlots`
- `OptMgrTemplateStrikeBps`
- `OptMgrTemplateCollateralMultiplierBps`
- `OptMgrTemplateBasePremiumBps`
- `OptMgrTemplateActive`

Manager series maps:
- `OptMgrSeriesTemplateId`
- `OptMgrSeriesKind`
- `OptMgrSeriesUnderlyingAsset`
- `OptMgrSeriesQuoteAsset`
- `OptMgrSeriesExpirySlot`
- `OptMgrSeriesMaxNotional`
- `OptMgrSeriesPremiumBps`
- `OptMgrSeriesStrikeBps`
- `OptMgrSeriesCollateralMultiplierBps`
- `OptMgrSeriesStatus`
- `OptMgrSeriesSettlementSlot`
- `OptMgrSeriesFinalMark`
- `OptMgrSeriesFinalQuoteMark`

Factory singleton state:
- `OptFactoryInitialized`
- `OptFactoryOwner`
- `OptFactoryGuardian`
- `OptFactorySettlementAsset`
- `OptFactoryManagerContract`
- `OptFactoryRiskVaultContract`
- `OptFactoryVaultContract`
- `OptFactoryShoutContract`
- `OptFactoryOutperfContract`
- `OptFactoryContractBound`
- `OptFactoryContractId`
- `OptFactoryWithdrawalOnly`
- `OptFactoryAutomationExecutor`
- `OptFactoryAutomationJobId`
- `OptFactoryAutomationCadence`
- `OptFactoryAutomationBacklogCap`
- `OptFactoryAutomationBacklog`
- `OptFactoryAutomationSafeMode`
- `OptFactoryNextPositionId`

Factory series and guard maps:
- `OptFactorySeriesKind`
- `OptFactorySeriesMaxNotional`
- `OptFactorySeriesPremiumBps`
- `OptFactorySeriesStrikeBps`
- `OptFactorySeriesCollateralMultiplierBps`
- `OptFactorySeriesExpirySlot`
- `OptFactorySeriesOpenNotional`
- `OptFactorySeriesUtilisationBps`
- `OptFactorySeriesBumpActivateBps`
- `OptFactorySeriesBumpDeactivateBps`
- `OptFactorySeriesPauseThresholdBps`
- `OptFactorySeriesBumpPercentBps`
- `OptFactorySeriesLastSettlementSlot`
- `OptFactorySeriesFinalMark`
- `OptFactorySeriesFinalQuoteMark`
- `OptFactorySeriesSettlementReady`

Factory position maps:
- `OptFactoryPositionOwner`
- `OptFactoryPositionSeriesId`
- `OptFactoryPositionKind`
- `OptFactoryPositionNotional`
- `OptFactoryPositionPremiumPaid`
- `OptFactoryPositionCollateralLocked`
- `OptFactoryPositionStatus`
- `OptFactoryPositionRecordedPayout`
- `OptFactoryPositionSettlementReady`
- `OptFactoryPositionShoutFloor`
- `OptFactoryPositionLastOracleMark`

Vault singleton state:
- `OptVaultInitialized`
- `OptVaultOwner`
- `OptVaultSettlementAsset`
- `OptVaultController`
- `OptVaultRiskVaultContract`
- `OptVaultWithdrawalOnly`

Vault accounting maps:
- `OptVaultSeriesCollateralLocked`
- `OptVaultSeriesPremiumAccrued`
- `OptVaultSeriesPayoutPaid`
- `OptVaultPositionOwner`
- `OptVaultPositionSeriesId`
- `OptVaultPositionCollateralLocked`
- `OptVaultPositionPremiumPaid`
- `OptVaultPositionPayoutPaid`
- `OptVaultPositionStatus`

Shout product maps:
- `ShoutSeriesExpirySlot`
- `ShoutSeriesStatus`
- `ShoutSeriesStrikeBps`
- `ShoutPositionOwner`
- `ShoutPositionSeriesId`
- `ShoutPositionNotional`
- `ShoutPositionStrikeBps`
- `ShoutPositionShoutFloor`
- `ShoutPositionLastOracleMark`
- `ShoutPositionPayout`
- `ShoutPositionStatus`

Outperformance product maps:
- `OutperfSeriesExpirySlot`
- `OutperfSeriesCollateralMultiplierBps`
- `OutperfSeriesStatus`
- `OutperfSeriesFinalBaseReturnBps`
- `OutperfSeriesFinalQuoteReturnBps`
- `OutperfSeriesSettlementReady`
- `OutperfPositionOwner`
- `OutperfPositionSeriesId`
- `OutperfPositionNotional`
- `OutperfPositionCollateralMultiplierBps`
- `OutperfPositionBaseReturnBps`
- `OutperfPositionQuoteReturnBps`
- `OutperfPositionPayout`
- `OutperfPositionSettlementReady`
- `OutperfPositionStatus`

All options contracts use explicit prefixes so manager, factory, vault, and product state cannot collide inside the shared Kotodama dataspace.
The factory is the only user-facing write surface. `risk_vault` bucket `2` tracks the canonical liability and collateral state, while `OptionsVault` mirrors per-series and per-position premium/collateral/payout accounting only.

Typed view snapshots are exposed separately by contract:
- manager: `manager_config()`, `template_state()`, `series_state()`, `automation_state()`
- factory: `factory_config()`, `series_state()`, `position_state()`, `automation_state()`
- vault: `vault_state()`, `position_accounting()`
- shout product: `series_state()`, `position_state()`
- outperformance product: `series_state()`, `position_state()`

Factory automation state is split intentionally: `sync_automation(...)` binds executor/job cadence and cap settings, while `heartbeat(...)` updates the live backlog/safe-mode fields and reports bucket `2` telemetry into `risk_vault`.
