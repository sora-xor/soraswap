# Options Interface

Contracts:
- `contracts/options/manager.ko`
- `contracts/options/factory.ko`
- `contracts/options/vault.ko`
- `contracts/options/shout_option.ko`
- `contracts/options/outperformance_option.ko`

Manager entrypoints:
- `main() -> int`
- `init_manager(settlement_asset, guardian, oracle_public_key, oracle_scheme)`
- `sync_automation(executor, expiry_job_id, settlement_job_id, cadence_slots, backlog_cap, safe_mode)`
- `bind_controller(controller)`
- `configure_oracle_stale_slots(oracle_stale_slots)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `register_template(option_kind, underlying_asset, quote_asset, tenor_slots, strike_bps, collateral_multiplier_bps, base_premium_bps) -> int`
- `update_template(template_id, strike_bps, collateral_multiplier_bps, base_premium_bps, active)`
- `create_series(template_id, expiry_slot, max_notional, premium_bps) -> int`
- `close_series(series_id, settlement_slot)`
- `settle_series(series_id, oracle_payload, oracle_signature)`
- `settle_series_c2c(series_id, final_mark, final_quote_mark, settlement_slot, oracle_slot, attestation_hash) -> int`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `native_lifecycle_tick()`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`
- `manager_config() -> (AssetDefinitionId, int, int, int, int, int, int, int, int)`
- `oracle_stale_slots() -> int`
- `template_state(template_id) -> (int, int, int, int, int, int, int, int)`
- `series_state(series_id) -> (int, int, int, int, int, int, int, int, int, int, int)`
- `automation_state() -> (int, int, int, int, int, int, int)`

Factory entrypoints:
- `main() -> int`
- `init_factory(settlement_asset, guardian, oracle_public_key, oracle_scheme)`
- `sync_automation(executor, job_id, cadence_slots, backlog_cap, safe_mode)`
- `heartbeat(current_backlog, safe_mode)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `configure_oracle_stale_slots(oracle_stale_slots)`
- `native_lifecycle_tick()`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`
- `bind_modules(risk_vault_contract, vault_contract, shout_contract, outperformance_contract)`
- `bind_manager(manager_contract)`
- `bind_contract(contract_id)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `sync_series(series_id, option_kind, max_notional, premium_bps, strike_bps, collateral_multiplier_bps, expiry_slot)`
- `configure_utilisation_guard(series_id, bump_activate_bps, bump_deactivate_bps, pause_threshold_bps, bump_percent_bps)`
- `buy_shout(series_id, notional, premium_paid, collateral_locked) -> int`
- `buy_outperformance(series_id, notional, premium_paid, collateral_locked) -> int`
- `settle_series(series_id, oracle_payload, oracle_signature)`
- `record_shout(position_id, oracle_payload, oracle_signature)`
- `exercise_shout_position(position_id, oracle_payload, oracle_signature) -> int`
- `exercise_outperformance_position(position_id) -> int`
- `factory_config() -> (AssetDefinitionId, int, int, int, int, int, int)`
- `oracle_stale_slots() -> int`
- `series_state(series_id) -> (int, int, int, int, int, int, int, int, int, int)`
- `position_state(position_id) -> (int, int, int, int, int, int, int, int, int)`
- `automation_state() -> (int, int, int, int, int, int, int)`

Vault entrypoints:
- `main() -> int`
- `init_vault(settlement_asset, risk_vault_contract)`
- `bind_controller(controller)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `sync_series(series_id)`
- `record_position(position_id, series_id, owner, collateral_locked, premium_paid)`
- `release_position(position_id, collateral_release)`
- `settle_position(position_id, payout, premium_burn)`
- `vault_state(series_id) -> (int, int, int, int, int)`
- `position_accounting(position_id) -> (int, int, int, int, int, int)`

Shout product entrypoints:
- `main() -> int`
- `init_product(guardian, oracle_public_key, oracle_scheme)`
- `bind_controller(controller)`
- `configure_oracle_stale_slots(oracle_stale_slots)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `sync_series(series_id, expiry_slot, strike_bps)`
- `register_position(position_id, series_id, owner, notional, strike_bps)`
- `record_shout(position_id, oracle_payload, oracle_signature)`
- `record_shout_c2c(position_id, mark_price_bps, oracle_slot, attestation_hash) -> int`
- `exercise_position(position_id, oracle_payload, oracle_signature) -> int`
- `exercise_position_c2c(position_id, mark_price_bps, oracle_slot, attestation_hash) -> int`
- `expire_series(series_id)`
- `series_state(series_id) -> (int, int, int, int)`
- `position_state(position_id) -> (int, int, int, int, int, int, int, int)`
- `oracle_stale_slots() -> int`

Outperformance product entrypoints:
- `main() -> int`
- `init_product(guardian)`
- `bind_controller(controller)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `sync_series(series_id, expiry_slot, collateral_multiplier_bps)`
- `register_position(position_id, series_id, owner, notional, collateral_multiplier_bps)`
- `settle_series(series_id, base_return_bps, quote_return_bps, settlement_slot)`
- `settle_series_c2c(series_id, base_return_bps, quote_return_bps, settlement_slot) -> int`
- `exercise_position(position_id) -> int`
- `expire_series(series_id)`
- `series_state(series_id) -> (int, int, int, int)`
- `position_state(position_id) -> (int, int, int, int, int, int, int, int)`

Notes:
- Template ids, series ids, and buyer position ids are contract-assigned integers; the old caller-chosen ticket names were removed.
- The stack is split intentionally: manager owns templates/series, factory is the user-facing buy/record/exercise orchestrator, vault is accounting-only, and the shout/outperformance products compute product-specific exercise state.
- Bucket `2` in `risk_vault` is the canonical options liability ledger, and `exposure_id = position_id`.
- `buy_shout` and `buy_outperformance` move premium plus collateral into the factory-bound contract, deposit that value into bucket `2`, record vault accounting mirrors, and lock the liability in the same flow.
- Signed oracle payloads are raw UTF-8 JSON bytes passed as hex blobs, and signatures cover the exact bytes supplied. Scheme `1` is Ed25519. Series payloads use `domain=2`, `series_id`, `final_mark`, `final_quote_mark`, `oracle_slot`, `status_flags`, and `attestation_hash`; shout payloads use `domain=3`, `position_id`, `mark_price_bps`, `oracle_slot`, `status_flags`, and `attestation_hash`.
- Public factory/product settlement verifies the configured oracle key, decodes the signed JSON privately, rejects degraded/replayed/future slots, and rejects stale slots when `block_height() - oracle_slot > oracle_stale_slots()`. Outperformance product settlement keeps `series_state()[1]` at the greater of the configured expiry and the verified settlement height. Controller-only `*_c2c` entrypoints carry already-verified numeric values because ABI v1 cannot yet construct JSON payloads with raw `bytes` fields for nested calls; manager and shout C2C oracle paths also reject negative, future, stale, and replayed slots.
- Raw payout-driven settlement APIs were removed. Series settlement now comes from verified-oracle `settle_series(...)`, shout exercise uses a fresh oracle payload plus stored shout state, and outperformance exercise consumes stored series settlement instead of caller-supplied payout numbers.
- `sync_automation(...)` binds automation jobs and caps; live backlog/safe-mode reporting flows through `heartbeat(...)`, which forwards bucket `2` telemetry into `risk_vault.report_bucket(...)`.
- Product and vault settlement entrypoints are owner/controller-only; end users go through the factory surface.
- The stored `risk_vault_contract`, vault, and product-module bindings are deployed contract address literals carried through UTF-8 `bytes` fields for ABI v1 `call_contract(...)` routing.
- Each `main()` is a write entrypoint, not a `view fn`; integrations should use the typed views above for bootstrap and smoke checks.
- `soraswap_options_lifecycle_tick` and `soraswap_options_factory_lifecycle_tick` are bounded time triggers registered on staggered `120000` ms native schedules: `schedule(60000, 120000)` for manager lifecycle and `schedule(40000, 120000)` for factory lifecycle. They still enforce the configured slot cadence inside the contracts, auto-close expired manager series, and mark expired factory series settlement-ready; signed oracle settlement and owner/user claim paths remain explicit.
