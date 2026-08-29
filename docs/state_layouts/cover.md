# Cover State Layout

Singleton state:

- initialization and authority: `CoverInitialized`, `CoverOwner`, `CoverGuardian`, `CoverOracleAuthority`
- custody and safety: `CoverAccount`, `CoverSettlementAsset`, `CoverWithdrawalOnly`
- reserve accounting: `CoverReservedPayout`, `CoverPremiumCollected`, `CoverSettledPayouts`
- oracle policy: `CoverDefaultRequiredObservations`, `CoverOracleStaleSlots`
- automation: `CoverAutomationExecutor`, `CoverObservationJobId`, `CoverAutomationCadence`, `CoverAutomationBacklogCap`, `CoverAutomationBacklog`, `CoverAutomationSafeMode`
- lifecycle: `CoverLifecycleCadenceSlots`, `CoverLifecycleMaxItems`, `CoverLifecycleEnabled`, `CoverLifecycleNextSlot`, `CoverLifecycleCursor`, `CoverLifecycleLastSlot`, `CoverLifecycleLastProcessed`
- append-only cursor: `CoverNextPolicyId`

Per-policy maps:

- identity and terms: `CoverPolicyOwner`, `CoverPolicyLowerBound`, `CoverPolicyUpperBound`, `CoverPolicyPayoutAmount`, `CoverPolicyCoveredNotional`, `CoverPolicyPremiumPaid`
- timing and status: `CoverPolicyMonitoringWindowSlots`, `CoverPolicyRequiredObservations`, `CoverPolicyStatus`, `CoverPolicyRegistrationSlot`
- breach state: `CoverPolicyBreachStartSlot`, `CoverPolicyBreachElapsedSlots`, `CoverPolicyObservationCount`
- oracle audit state: `CoverPolicyLastOracleSlot`, `CoverPolicyLastObservedPrice`, `CoverPolicyLastAttestationHash`
- settlement: `CoverPolicyClaimPayout`

Reserve invariant:

`ledger::asset::balance(CoverAccount, CoverSettlementAsset) >= CoverReservedPayout`

Registration checks the invariant against the projected post-premium balance before reserving a new payout. Claim and expiry atomically remove exactly one policy's payout from `CoverReservedPayout`; only a claim also transfers that amount and increments `CoverSettledPayouts`.

There is no risk-vault contract binding or cross-contract liability key in the first-release layout. `reserve_state()` exposes live balance, reserved payout, surplus, cumulative premiums, and cumulative paid claims.
