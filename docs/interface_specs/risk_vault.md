# Risk Vault Interface

Contract: `contracts/risk/risk_vault.ko`

Lifecycle and bucket control entrypoints:
- `main() -> int`
- `init_vault(collateral_asset, vault_account)`
- `configure_bucket(bucket_id, controller, payout_cap_bps, utilisation_cap_bps, collateral_multiplier_bps)`
- `sync_automation(bucket_id, executor, job_id, cadence_slots, backlog_cap, safe_mode)`
- `report_bucket(bucket_id, backlog, safe_mode)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`

Accounting entrypoints:
- `deposit(bucket_id, amount) -> int`
- `withdraw_surplus(bucket_id, amount)`
- `lock_liability(bucket_id, exposure_id, notional, collateral_locked, backlog) -> int`
- `release_liability(bucket_id, exposure_id, backlog) -> int`
- `settle_payout(bucket_id, exposure_id, recipient, amount) -> int`

Views:
- `bucket_state(bucket_id) -> (int, int, int, int, int, int, int, int, int, int, int, int)`
- `risk_state() -> (int, int, int, int, int, int, int, int)`
- `automation_state(bucket_id) -> (int, int, int, int, int, int, int)`
- `liability_state(bucket_id, exposure_id) -> (int, int, int, int)`

Notes:
- Bucket ids are fixed to `1=perps`, `2=options`, `3=cover`.
- Bucket controllers are the product contract ids that call into `risk_vault`; bootstrap treasury flows may still be owner-driven, but derivative user flows should reach `deposit`, `lock_liability`, `settle_payout`, and `release_liability` through the product contracts rather than directly.
- In deployment/bootstrap flows, `vault_account` should be the deterministic subject account of the deployed `risk_vault` contract so the shared bucket remains contract-owned custody on chain.
- Liability ids are derived from `(bucket_id, exposure_id)` and are intended to be idempotent across repeated lock/release attempts.
- ABI v1 cross-contract routing uses same-transaction `call_contract(...)` execution against deployed contract address literals carried in UTF-8 `bytes` fields. `authority()` inside `risk_vault` still resolves to the caller contract subject, so `configure_bucket(..., controller, ...)` must store the controller subject account rather than the contract address literal.
- `main()` is a write entrypoint, not a `view fn`.
