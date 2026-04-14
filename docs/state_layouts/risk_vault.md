# Risk Vault State Layout

Singleton scalar state:
- `RiskVaultInitialized`
- `RiskVaultOwner`
- `RiskVaultCollateralAsset`
- `RiskVaultAccount`
- `RiskVaultWithdrawalOnly`

Per-bucket maps:
- `RiskVaultBucketController`
- `RiskVaultBucketPayoutCapBps`
- `RiskVaultBucketUtilisationCapBps`
- `RiskVaultBucketCollateralMultiplierBps`
- `RiskVaultBucketDeposits`
- `RiskVaultBucketOutstandingNotional`
- `RiskVaultBucketReservedCollateral`
- `RiskVaultBucketSettledPayouts`
- `RiskVaultBucketAutomationExecutor`
- `RiskVaultBucketAutomationJobId`
- `RiskVaultBucketAutomationCadence`
- `RiskVaultBucketAutomationBacklogCap`
- `RiskVaultBucketAutomationBacklog`
- `RiskVaultBucketAutomationSafeMode`

Per-liability maps:
- `RiskVaultLiabilityStatus`
- `RiskVaultLiabilityNotional`
- `RiskVaultLiabilityCollateral`
- `RiskVaultLiabilitySettledPayout`

All vault state is prefixed with `RiskVault` to keep the shared collateral bucket isolated from other derivatives contracts in the same dataspace.
`RiskVaultBucketController` stores the controlling product contract subject account for each bucket because nested `authority()` inside `risk_vault` resolves to the caller contract subject, not the caller contract address literal.
`RiskVaultAccount` is expected to hold the risk-vault contract subject account in deployed environments so shared derivative custody and payouts originate from the on-chain `risk_vault` authority rather than an external treasury account.

View tuple fields returned by `bucket_state()`, `risk_state()`, `automation_state()`, and `liability_state()` cover:
- bucket configuration, deposits, outstanding notional, reserved collateral, settled payouts, utilisation, surplus, backlog, and safe mode
- aggregate cross-bucket deposits, liabilities, payouts, maximum utilisation, unsafe bucket count, and global withdrawal-only mode
- per-bucket executor/job/cadence telemetry
- liability lifecycle status, notional, remaining collateral, and settled payout totals, keyed by `(bucket_id, exposure_id)` where the exposure id is the product position/policy id
