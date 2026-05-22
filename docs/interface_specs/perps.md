# Perps Interface

Contract: `contracts/perps/perps_engine.ko`

Lifecycle and control entrypoints:
- `main() -> int`
- `init_engine(collateral_asset, risk_vault_contract, oracle_public_key, oracle_scheme)`
- `sync_automation(executor, funding_job_id, liquidation_job_id, cadence_slots, backlog_cap, safe_mode)`
- `bind_risk_vault(risk_vault_contract)`
- `bind_contract(contract_id)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`

Market admin entrypoints:
- `register_market(asset, max_leverage_bps, maintenance_margin_bps, liquidation_fee_bps, open_interest_cap, funding_bps, funding_interval_slots, oracle_stale_slots, backlog_limit, utilisation_clamp_bps, liquidation_stress_limit) -> int`
- `update_market(market_id, max_leverage_bps, maintenance_margin_bps, liquidation_fee_bps, open_interest_cap, funding_bps, funding_interval_slots, oracle_stale_slots, backlog_limit, utilisation_clamp_bps, liquidation_stress_limit, guard_flags, active)`
- `admin_repair_orphan_position(position_id, mark_price_bps, index_price_bps)`
- `heartbeat(market_id, current_backlog, safe_mode)`

Trading and liquidation entrypoints:
- Verified oracle tuple used below:
  `(oracle_payload: bytes, oracle_signature: bytes)`
- `open_position(market_id, size, margin, requested_leverage_bps, oracle_payload, oracle_signature) -> int`
- `modify_position(position_id, size_delta, margin_delta, requested_leverage_bps, oracle_payload, oracle_signature) -> int`
- `add_margin(position_id, amount) -> int`
- `remove_margin(position_id, amount, oracle_payload, oracle_signature) -> int`
- `sync_funding(market_id, oracle_payload, oracle_signature) -> int`
- `run_liquidation_pass(market_id, max_positions, oracle_payload, oracle_signature) -> int`
- `close_position(position_id, oracle_payload, oracle_signature) -> int`

Views:
- `engine_config() -> (AssetDefinitionId, bytes, int, int, int, int, int, int)`
- `market_state(market_id) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`
- `market_oracle_state(market_id) -> (int, int, int, int)`
- `position_state(position_id) -> (int, int, int, int, int, int, int, int, int, int, int)`
- `position_liquidation_state(position_id) -> (int, int, int)`
- `liquidation_state(market_id) -> (int, int, int, int, int, int, int)`
- `risk_state(market_id) -> (int, int, int, int, int, int, int, int)`
- `automation_state() -> (int, int, int, int, int, int, int)`

Notes:
- Position ids are contract-assigned integers; caller-chosen position names were removed.
- Bucket `1` in `risk_vault` is the canonical perps liability ledger, and `exposure_id = position_id`.
- `open_position`, size-increasing `modify_position`, and margin updates route collateral through `risk_vault` instead of direct perps-owned custody transfers.
- `run_liquidation_pass(...)` is the canonical liquidation path. The first unhealthy pass queues the position, a later healthy pass auto-recovers it, and a later unhealthy pass liquidates it once the queued slot is older than the current oracle slot.
- `close_position` and liquidation payouts settle through bucket `1`, then release the liability in the same flow.
- Automatic liquidations pay the keeper fee to `authority()` and return any remaining positive residual equity to the original position owner.
- `admin_repair_orphan_position(...)` is owner-only recovery tooling for long-lived environments such as Taira where a historical position can remain open after the bound `risk_vault` liability is gone; it closes the stale position without attempting payout settlement.
- Signed oracle payloads are raw UTF-8 JSON bytes passed as hex blobs, and signatures cover the exact bytes supplied. Scheme `1` is Ed25519. Required fields are `domain=1`, `market_id`, `mark_price_bps`, `index_price_bps`, `confidence_bps`, `oracle_slot`, `status_flags`, and `attestation_hash`.
- All risk-bearing perps mutations except `add_margin` verify the configured oracle key, decode the signed JSON privately, reject degraded/stale/replayed oracle slots, and use `block_height()` as the current slot. The raw `settle_funding(position, mark_price, index_price)` and naked payout helpers were removed.
- Engine-side risk guards clamp openings and modifications on market pause, backlog, utilisation, liquidation stress, withdrawal-only mode, and automation safe mode.
- The stored `risk_vault_contract` is the deployed `risk_vault` contract address literal carried as a UTF-8 `bytes` field for ABI v1 `call_contract(...)` routing. View surfaces expose that field as hex-encoded bytes.
- `main()` is a write entrypoint, not a `view fn`; bootstrap and smoke should use the typed views above.
