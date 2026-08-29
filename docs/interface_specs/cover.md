# Cover Interface

Contract: `contracts/cover/policy_manager.ko`

Initialization:

- `hajimari(settlement_asset, cover_account, guardian, oracle_authority, default_required_observations, oracle_stale_slots)`

Control and treasury entrypoints:

- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `configure_oracle_authority(oracle_authority)`
- `configure_oracle_stale_slots(stale_slots)`
- `sync_automation(executor, job_id, cadence_slots, backlog_cap, safe_mode)`
- `heartbeat(current_backlog, safe_mode)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `fund_reserve(amount)`
- `withdraw_surplus(recipient, amount)`
- `native_lifecycle_tick()`

Policy entrypoints:

- `register_policy(lower_bound, upper_bound, payout_amount, monitoring_window_slots, required_observations, covered_notional, premium_paid) -> int`
- `record_observation(policy_id, observed_price, oracle_slot, status_flags, attestation_hash)`
- `route_claim(policy_id) -> quantity`
- `expire_policy(policy_id)`

Views:

- `main() -> int`
- `manager_config() -> (AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- `reserve_state() -> (quantity, quantity, quantity, quantity, quantity)`
- `policy_state(policy_id) -> (int, decimal, decimal, quantity, int, int, quantity, quantity, int, int, int, quantity)`
- `policy_observation(policy_id) -> (decimal, int, int, int)`
- `next_policy_id() -> int`
- `automation_state() -> (int, int, int, int, int, int, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

The first release is self-contained. Kotodama's current `contract::invoke` profile is specific to quantity-in/quantity-out swaps, so the cover manager does not store a contract address or route arbitrary calls into `risk_vault`.

`cover_account` is the dedicated settlement-asset treasury. New policies are accepted only when its current balance plus the incoming premium can fully back all existing reserved payouts plus the new payout. Claims transfer the exact reserved payout directly from that account. Expiry releases the reservation without moving funds. `withdraw_surplus` checks the live account balance and cannot consume reserved payout capital.

Oracle observations are typed calls made by `oracle_authority`. The submitting account's transaction signature binds the entrypoint and every typed argument, avoiding unverifiable relayed JSON. Observations must be fresh, monotonic, non-degraded (`status_flags == 0`), and carry a positive attestation hash. The oracle, guardian, treasury, and owner accounts must be distinct.

Policy IDs are contract-assigned and capped at 64 for bounded lifecycle scans. Status values are `1` active, `2` claimable, `3` claimed, and `4` expired. The time trigger scans at most the configured number of policies and releases reserves for expired active policies.
