# Perps Interface

Contract: `contracts/perps/perps_engine.ko`

Public entrypoints:
- `main() -> int`
- `init_engine(collateral_asset, vault_account, funding_bps)`
- `configure_risk(funding_bps, max_leverage_bps, maintenance_margin_bps, liquidation_fee_bps)`
- `open_position(trader, position, size, collateral)`
- `open_position_with_assets(trader, position, vault_account, collateral_asset, size, collateral)`
- `add_collateral(trader, position, amount)`
- `add_collateral_with_assets(trader, position, vault_account, collateral_asset, amount)`
- `remove_collateral(trader, position, amount)`
- `remove_collateral_with_assets(trader, position, vault_account, collateral_asset, amount)`
- `settle_funding(trader, position, mark_price, index_price)`
- `settle_funding_with_assets(trader, position, vault_account, collateral_asset, funding_bps, mark_price, index_price)`
- `close_position(trader, position, payout)`
- `close_position_with_assets(trader, position, vault_account, collateral_asset, payout)`
- `liquidate_position(liquidator, position) -> int`
- `liquidate_position_with_assets(liquidator, position, vault_account, collateral_asset, maintenance_margin_bps, liquidation_fee_bps) -> int`
- `engine_config() -> (AssetDefinitionId, AccountId, int, int, int, int)`
- `mirror_position(position) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`

Notes:
- The engine now enforces a configurable max-leverage check at open and a maintenance-margin check on collateral withdrawals.
- Funding settlement is modeled as internal collateral adjustment plus accumulated funding readback rather than an external transfer on every funding tick.
- `engine_config` and `mirror_position` are `view fn` entrypoints consumed through `/v1/contracts/view`.
