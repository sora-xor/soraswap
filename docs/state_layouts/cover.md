# Cover State Layout

Singleton scalar state:
- `CoverInitialized`
- `CoverOwner`
- `CoverSettlementAsset`
- `CoverRiskVaultContract`
- `CoverContractBound`
- `CoverContractId`
- `CoverWithdrawalOnly`
- `CoverOraclePublicKey`
- `CoverOracleScheme`
- `CoverDefaultRequiredObservations`
- `CoverOracleStaleSlots`
- `CoverAutomationExecutor`
- `CoverObservationJobId`
- `CoverAutomationCadence`
- `CoverAutomationBacklogCap`
- `CoverAutomationBacklog`
- `CoverAutomationSafeMode`
- `CoverNextPolicyId`

Per-policy maps:
- `CoverPolicyOwner`
- `CoverPolicyLowerBound`
- `CoverPolicyUpperBound`
- `CoverPolicyPayoutAmount`
- `CoverPolicyMonitoringWindowSlots`
- `CoverPolicyRequiredObservations`
- `CoverPolicyCoveredNotional`
- `CoverPolicyPremiumPaid`
- `CoverPolicyStatus`
- `CoverPolicyRegistrationSlot`
- `CoverPolicyBreachStartSlot`
- `CoverPolicyBreachElapsedSlots`
- `CoverPolicyObservationCount`
- `CoverPolicyLastObservationSlot`
- `CoverPolicyLastOracleSlot`
- `CoverPolicyLastObservedPrice`
- `CoverPolicyClaimPayout`
- `CoverPolicyClaimCount`

View tuple fields returned by `manager_config()`, `policy_state()`, and `automation_state()` cover:
- settlement asset, risk-vault contract, withdrawal-only flag, default observation threshold, stale-oracle threshold, and automation config
- per-policy status, bounds, payout amount, monitoring window, observation counts, latest observed price, and claim payout
- automation executor/job binding, backlog, cadence, and safe-mode state
- bucket `3` liability routing through `risk_vault`, keyed by `policy_id`
- `CoverRiskVaultContract` stores the deployed `risk_vault` contract address literal as UTF-8 `bytes` for the ABI v1 `call_contract(...)` target; `bind_risk_vault(...)` rewrites that target without disturbing live policy state. `manager_config()` exposes the stored bytes as a hex string.
- `CoverOraclePublicKey` and `CoverOracleScheme` are init-only for v1. Observation payloads must use domain `4` and include `policy_id`, `observed_price`, `oracle_slot`, `status_flags`, and `attestation_hash`. `CoverPolicyLastOracleSlot` enforces monotonic signed observations per policy.

Automation state is split intentionally: `sync_automation(...)` binds the observation job and cap settings, while `heartbeat(...)` updates the live backlog/safe-mode fields and reports bucket `3` telemetry into `risk_vault`.
