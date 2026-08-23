# Cover Interface

Contract: `contracts/cover/policy_manager.ko`

Lifecycle and control entrypoints:
- `main() -> int`
- `init_manager(settlement_asset, risk_vault_contract, required_observations, oracle_stale_slots, oracle_public_key, oracle_scheme)`
- `sync_automation(executor, job_id, cadence_slots, backlog_cap, safe_mode)`
- `heartbeat(current_backlog, safe_mode)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `native_lifecycle_tick()`
- `bind_risk_vault(risk_vault_contract)`
- `bind_contract(contract_id)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `configure_oracle_stale_slots(oracle_stale_slots)`
- `configure_next_policy_id(next_policy_id)`

Policy entrypoints:
- `register_policy(lower_bound, upper_bound, payout_amount, monitoring_window_slots, required_observations, covered_notional, premium_paid) -> int`
- `record_observation(policy_id, oracle_payload, oracle_signature)`
- `route_claim(policy_id) -> int`
- `expire_policy(policy_id)`

Views:
- `manager_config() -> (AssetDefinitionId, bytes, int, int, int, int, int, int, int)`
- `policy_state(policy_id) -> (int, int, int, int, int, int, int, int, int, int, int, int)`
- `next_policy_id() -> int`
- `automation_state() -> (int, int, int, int, int, int, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

Notes:
- Policy ids are contract-assigned integers with on-chain ownership records; raw caller-chosen policy names were removed.
- Bucket `3` in `risk_vault` is the canonical cover liability ledger, with `exposure_id = policy_id`, `notional = covered_notional`, and `collateral_locked = payout_amount`.
- `register_policy` routes premium into shared risk funding, locks the liability in bucket `3`, and records policy ownership/state in the manager.
- `sync_automation(...)` binds the observation job; live backlog/safe-mode reporting flows through `heartbeat(...)`, which forwards bucket `3` telemetry into `risk_vault.report_bucket(...)`.
- Signed oracle payloads are raw UTF-8 JSON bytes passed as hex blobs, and signatures cover the exact bytes supplied. Scheme `1` is Ed25519. Required fields are `domain=4`, `policy_id`, `observed_price`, `oracle_slot`, `status_flags`, and `attestation_hash`.
- Breach tracking is observation-driven and Parisian-style: payloads are signature verified, decoded privately, and checked against monotonic oracle slots. Degraded payloads, automation safe mode, or `block_height() - oracle_slot > oracle_stale_slots` reset breach progress instead of advancing claims.
- `configure_oracle_stale_slots(...)` is owner-only and updates the stale-oracle threshold without disturbing live policy counters or automation state.
- `configure_next_policy_id(...)` is owner-only, can only advance the append-only policy cursor, and lets public bootstrap skip policy ids that already exist in the shared risk-vault bucket-3 liability ledger after a contract code refresh.
- `register_policy(...)` and `expire_policy(...)` use `block_height()` internally. `route_claim(policy_id)` settles through bucket `3` and then releases the liability; `expire_policy(policy_id)` releases the liability without payout.
- The stored `risk_vault_contract` is the deployed `risk_vault` contract address literal carried as a UTF-8 `bytes` field for ABI v1 `call_contract(...)` routing. View surfaces expose that field as hex-encoded bytes.
- Raw `record_breach(policy, elapsed_slots)` and `settle_claim(policy, covered_notional)` helpers were removed in favor of `record_observation(...)` plus `route_claim(policy_id)`.
- `main()` is a write entrypoint, not a `view fn`.
- `soraswap_cover_lifecycle_tick` is a bounded time trigger registered on a `schedule(0, 120000)` native schedule. It still enforces the configured slot cadence inside the contract, auto-expires active policies after their monitoring window has elapsed, and releases the bucket-3 liability without paying a keeper reward.
