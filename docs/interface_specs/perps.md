# Perps Interface

Contract: `contracts/perps/perps_engine.ko`

## Construction

- `hajimari(collateral_asset: AssetDefinitionId, custody_account: AccountId, oracle_account: AccountId)`
- `main() -> int` (view)

Construction records the deployer as owner, starts the engine in withdrawal-only mode, and requires the owner, custody account, and oracle account to be three distinct accounts.

## Lifecycle and control entrypoints

- `sync_automation(executor, funding_job_id, liquidation_job_id, cadence_slots, backlog_cap, safe_mode)`
- `configure_trigger_lifecycle(cadence_slots, max_items_per_tick, enabled)`
- `native_lifecycle_tick()`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `configure_oracle_account(oracle_account)`
- `fund_collateral_pool(amount) -> int`
- `withdraw_collateral_surplus(recipient, amount) -> int`

`configure_oracle_account` and surplus withdrawals are owner-only and require withdrawal-only mode. Oracle rotation must preserve account separation. Funding transfers collateral from the caller to the configured custody account. A surplus withdrawal cannot consume margin reserved for open or queued positions.

## Market and oracle entrypoints

- `register_market(asset, max_leverage_bps, maintenance_margin_bps, liquidation_fee_bps, open_interest_cap, funding_bps, funding_interval_slots, oracle_stale_slots, backlog_limit, utilisation_clamp_bps, liquidation_stress_limit) -> int`
- `update_market(market_id, max_leverage_bps, maintenance_margin_bps, liquidation_fee_bps, open_interest_cap, funding_bps, funding_interval_slots, oracle_stale_slots, backlog_limit, utilisation_clamp_bps, liquidation_stress_limit, guard_flags, active)`
- `publish_market_oracle(market_id, mark_price_bps, index_price_bps, confidence_bps, oracle_slot, status_flags, attestation_hash) -> int`
- `heartbeat(market_id, current_backlog, safe_mode)`

Oracle publication uses typed arguments and is accepted only from the configured oracle account with the `Oracle` permission. Publications require positive mark and index prices, confidence in `0..2_500` bps, `status_flags = 0`, a positive attestation identifier, a strictly increasing slot, and a slot fresh relative to `block_height()` and the market threshold. The account-authenticated transaction is the attestation boundary; there is no secondary JSON payload or contract-local signature decoder.

Market registration and updates share the same risk-parameter validation. Leverage must exceed `10_000`; maintenance and liquidation fees are bounded by `10_000`; open-interest caps must be positive; stale, backlog, stress, and guard values must be non-negative; utilisation clamps are bounded to `0..10_000`; and `active` is binary.

## Trading and liquidation entrypoints

- `open_position(market_id, size, margin, requested_leverage_bps) -> int`
- `modify_position(position_id, size_delta, margin_delta, requested_leverage_bps) -> int`
- `add_margin(position_id, amount) -> int`
- `remove_margin(position_id, amount) -> int`
- `sync_funding(market_id) -> int`
- `run_liquidation_pass(market_id, max_positions) -> int`
- `close_position(position_id) -> int`

Risk-bearing operations consume the latest typed oracle state and reject missing, stale, or degraded data. Requested leverage `0` selects the market maximum; negative values and values above the market maximum are rejected.

Position IDs are contract-assigned integers. `run_liquidation_pass` is the canonical keeper liquidation path: the first unhealthy pass queues a position, a later healthy pass recovers it, and a later unhealthy pass liquidates it once the queued slot is older than the current slot. Keeper-driven liquidation pays its fee to `authority()` and returns any positive residual equity to the position owner. The native lifecycle path performs the same bounded scan without a keeper reward.

## Views

- `engine_config() -> (AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- `collateral_pool_state() -> (AccountId, int, int, int)`
- `market_state(market_id) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`
- `market_oracle_state(market_id) -> (int, int, int, int, int)`
- `position_state(position_id) -> (int, int, int, int, int, int, int, int, int, int, int)`
- `position_liquidation_state(position_id) -> (int, int, int)`
- `liquidation_state(market_id) -> (int, int, int, int, int, int, int)`
- `risk_state(market_id) -> (int, int, int, int, int, int, int, int)`
- `automation_state() -> (int, int, int, int, int, int, int)`
- `trigger_lifecycle_state() -> (int, int, int, int, int, int, int)`

Exact tuple ordering is documented in `docs/state_layouts/perps.md`.

## Collateral and dataspace model

The engine owns its collateral accounting and transfers the configured asset directly through the custody account in universal dataspace `0`. `PerpsCollateralPoolBalance` tracks collateral controlled by that account for this engine, while `PerpsReservedMargin` tracks the portion owed to live positions. Every mutation preserves `pool balance >= reserved margin`. The custody account cannot call a collateral-collection path or receive a positive settlement, preventing a skipped self-transfer from changing internal accounting without moving assets.

Closing and liquidation payouts are capped to the position's margin plus current pool surplus. This permits funded profit payouts without consuming another position's reserved margin. Any uncovered profit is intentionally not minted or borrowed. Margin settlement and reserve release occur atomically in the same transaction.

The public surface consists only of the typed initialization, administration, funding, trading, lifecycle, and view entrypoints listed above.

## Native lifecycle

`soraswap_perps_lifecycle_tick` is registered on `schedule(80000, 120000)` and is disabled at construction. When enabled, the contract also enforces its configured slot cadence, processes at most four positions per tick, consumes only a fresh cached oracle publication, applies funding calculations and liquidation passes, and never invents a price.
