# Options State Layout

Factory singleton state:
- `OptFactoryInitialized`
- `OptFactoryOwner`
- `OptFactoryGuardian`
- `OptFactoryAccount`
- `OptFactorySettlementAsset`
- `OptFactoryWithdrawalOnly`
- `OptFactoryOracleAuthority`
- `OptFactoryOracleStaleSlots`
- `OptFactoryReservedCollateral`
- `OptFactoryPremiumAccrued`
- `OptFactorySettledPayouts`
- `OptFactoryAutomationExecutor`
- `OptFactoryAutomationJobId`
- `OptFactoryAutomationCadence`
- `OptFactoryAutomationBacklogCap`
- `OptFactoryAutomationBacklog`
- `OptFactoryAutomationSafeMode`
- `OptFactoryNextPositionId`
- `OptFactoryLifecycleCadenceSlots`
- `OptFactoryLifecycleMaxItems`
- `OptFactoryLifecycleEnabled`
- `OptFactoryLifecycleNextSlot`
- `OptFactoryLifecycleCursor`
- `OptFactoryLifecycleLastSlot`
- `OptFactoryLifecycleLastProcessed`

Factory series and guard maps:
- `OptFactorySeriesKind`
- `OptFactorySeriesStatus`
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
- `OptFactorySeriesOracleSlot`
- `OptFactorySeriesAttestationHash`
- `OptFactorySeriesFinalMark`
- `OptFactorySeriesFinalQuoteMark`
- `OptFactorySeriesFinalBaseReturnBps`
- `OptFactorySeriesFinalQuoteReturnBps`
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
- `OptFactoryPositionShoutFloorBps`
- `OptFactoryPositionLastOracleMarkBps`
- `OptFactoryPositionLastOracleSlot`
- `OptFactoryPositionLastAttestationHash`

The sole options contract uses the `OptFactory` prefix for all singleton, series, guard, and position state in the shared Kotodama dataspace.

The factory is the canonical first-release position and collateral ledger. `OptFactoryReservedCollateral` is the sum of collateral on active positions, and the live `OptFactoryAccount` settlement-asset balance must cover it. Closing a position caps payout at its locked collateral, zeroes that position's lock, and removes the full lock from the aggregate reserve. `OptFactoryPremiumAccrued` and `OptFactorySettledPayouts` are cumulative audit counters.

Factory oracle mutations are authorized by a configured account ID that is distinct from the owner, guardian, and custody accounts. Typed calls update outperformance settlement state per series and shout marks per position, including the oracle slot and attestation hash, preserving monotonic replay protection without signed-JSON decoding or C2C relays.

The factory exposes typed view snapshots through `factory_config()`, `oracle_stale_slots()`, `treasury_state()`, `series_state()`, `series_terms()`, `series_settlement()`, `series_returns()`, `position_state()`, `automation_state()`, and `trigger_lifecycle_state()`.

Factory automation state is split intentionally: `sync_automation(...)` binds executor/job cadence and cap settings, while `heartbeat(...)` updates the local backlog/safe-mode fields. It does not forward telemetry to another contract.
