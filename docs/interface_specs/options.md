# Options Interface

Contract: `contracts/options/factory.ko`

Entrypoints:

- `hajimari(settlement_asset, factory_account, guardian, oracle_authority, stale_slots)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `configure_oracle_authority(oracle_authority)`
- `configure_oracle_stale_slots(stale_slots)`
- `sync_automation(executor, job_id, cadence_slots, backlog_cap, safe_mode)`
- `heartbeat(current_backlog, safe_mode)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `withdraw_surplus(recipient, amount)`
- `sync_series(series_id, option_kind, max_notional, premium_bps, collateral_multiplier_bps, expiry_slot, strike_bps)`
- `configure_utilisation_guard(series_id, bump_activate_bps, bump_deactivate_bps, pause_threshold_bps, bump_percent_bps)`
- `buy_shout(series_id, notional) -> int`
- `buy_outperformance(series_id, notional) -> int`
- `settle_outperformance_series(series_id, final_mark, final_quote_mark, base_return_bps, quote_return_bps, oracle_slot, attestation_hash)`
- `publish_shout_mark(position_id, mark_price_bps, oracle_slot, attestation_hash)`
- `exercise_shout_position(position_id) -> quantity`
- `exercise_outperformance_position(position_id) -> quantity`
- `native_lifecycle_tick()`
- `main() -> int`
- `factory_config() -> (AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- `oracle_stale_slots() -> int`
- `treasury_state() -> (quantity, quantity, quantity, quantity, quantity)`
- `series_state(series_id)`
- `series_terms(series_id) -> (int, int)`
- `series_settlement(series_id)`
- `series_returns(series_id) -> (int, int)`
- `position_state(position_id)`
- `automation_state() -> (int, int, int, int, int, int, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

Notes:

- The factory is the canonical first-release position, accounting, custody, and payout surface. It has no manager, vault, product, or `risk_vault` contract-address bindings.
- Kotodama's available `contract::invoke` profile is swap-specific and cannot represent the former arbitrary factory/shout C2C calls. Those relay entrypoints were removed instead of emulated.
- `buy_shout` and `buy_outperformance` derive premium and collateral from the configured series, transfer both into `factory_account`, and reserve the collateral locally. Purchases fail if the live account balance does not back all existing reserves.
- The configured `oracle_authority` submits typed series returns and shout marks and must be distinct from the owner, guardian, and custody accounts. The account transaction signature binds the entrypoint and typed arguments; no contract attempts to decode relayed JSON bytes.
- The typed oracle account publishes a fresh shout mark before exercise. Only the recorded position owner can exercise, and exercise consumes the latest fresh stored mark; users never provide oracle data in their exercise transaction.
- Outperformance and shout payout formulas are computed inside the factory. A payout is capped at that position's collateral, transferred to the recorded owner, and atomically releases the full position reserve. `withdraw_surplus` cannot consume reserved collateral.
- `series_terms` exposes the immutable expiry slot and strike in a stable, purpose-specific view; callers do not need a second control-plane contract to discover settlement timing.
