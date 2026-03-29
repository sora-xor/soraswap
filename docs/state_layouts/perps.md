# Perps State Layout

Engine-slot maps:
- `CollateralAsset`
- `VaultAccount`
- `FundingBps`
- `MaxLeverageBps`
- `MaintenanceMarginBps`
- `LiquidationFeeBps`

Per-position maps:
- `PositionOwner`
- `PositionSize`
- `PositionCollateral`
- `PositionEntryPrice`
- `PositionMarkPrice`
- `PositionIndexPrice`
- `FundingAccrued`
- `RealizedPnl`
- `Liquidated`

View tuple fields returned by `mirror_position()`:
- `soraswap_perps_position_registered`
- `soraswap_perps_size`
- `soraswap_perps_collateral`
- `soraswap_perps_funding_accrued`
- `soraswap_perps_realized_pnl`
- `soraswap_perps_liquidated`
- `soraswap_perps_funding_bps`
- `soraswap_perps_max_leverage_bps`
- `soraswap_perps_maintenance_margin_bps`
- `soraswap_perps_liquidation_fee_bps`
- `soraswap_perps_entry_price`
- `soraswap_perps_mark_price`
- `soraswap_perps_index_price`

View tuple fields returned by `engine_config()`:
- `soraswap_perps_collateral_asset`
- `soraswap_perps_vault_account`
- `soraswap_perps_config_funding_bps`
- `soraswap_perps_config_max_leverage_bps`
- `soraswap_perps_config_maintenance_margin_bps`
- `soraswap_perps_config_liquidation_fee_bps`
