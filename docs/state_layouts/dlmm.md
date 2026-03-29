# DLMM State Layout

Pool-wide scalar state:
- `PoolInitialized`
- `BaseAsset`
- `QuoteAsset`
- `VaultAccount`
- `FeePips`
- `BinStep`
- `ActiveBin`
- `ImpactCapBps`
- `MinReserveBase`
- `MinReserveQuote`
- `MaxBinsPerSwap`
- `BinLiquidityCap`

Bin-indexed maps:
- `BinReserveBase`
- `BinReserveQuote`
- `BinShareSupply`
- `BinFeeGrowthBase`
- `BinFeeGrowthQuote`

Position-indexed maps:
- `PositionOwner`
- `PositionBinId`
- `PositionShares`
- `PositionFeeDebtBase`
- `PositionFeeDebtQuote`
- `PositionCreditBase`
- `PositionCreditQuote`

Router scalar state:
- `RouterInitialized`
- `BaseAsset`
- `DefaultFeePips`

View tuple fields returned by `mirror_state()`:
- `soraswap_dlmm_pool_initialized`
- `soraswap_dlmm_pool_active_bin`
- `soraswap_dlmm_pool_fee_pips`
- `soraswap_dlmm_pool_bin_step`
- `soraswap_dlmm_pool_reserve_base`
- `soraswap_dlmm_pool_reserve_quote`
- `soraswap_dlmm_pool_active_liquidity`
- `soraswap_dlmm_pool_active_share_supply`
- `soraswap_dlmm_pool_impact_cap_bps`
- `soraswap_dlmm_pool_min_reserve_base`
- `soraswap_dlmm_pool_min_reserve_quote`
- `soraswap_dlmm_pool_max_bins_per_swap`
- `soraswap_dlmm_pool_bin_liquidity_cap`
- `soraswap_dlmm_router_initialized`
- `soraswap_dlmm_router_default_fee_pips`

View tuple fields returned by `pool_config()`:
- `soraswap_dlmm_pool_base_asset`
- `soraswap_dlmm_pool_quote_asset`
- `soraswap_dlmm_pool_vault_account`
- `soraswap_dlmm_pool_config_fee_pips`
- `soraswap_dlmm_pool_config_bin_step`
- `soraswap_dlmm_pool_config_active_bin`

View tuple fields returned by `risk_config()`:
- `soraswap_dlmm_pool_risk_impact_cap_bps`
- `soraswap_dlmm_pool_risk_min_reserve_base`
- `soraswap_dlmm_pool_risk_min_reserve_quote`
- `soraswap_dlmm_pool_risk_max_bins_per_swap`
- `soraswap_dlmm_pool_risk_bin_liquidity_cap`

View tuple fields returned by `mirror_bin(bin_id)`:
- `soraswap_dlmm_bin_reserve_base`
- `soraswap_dlmm_bin_reserve_quote`
- `soraswap_dlmm_bin_share_supply`
- `soraswap_dlmm_bin_fee_growth_base`
- `soraswap_dlmm_bin_fee_growth_quote`

View tuple fields returned by `mirror_position(position_id)`:
- `soraswap_dlmm_position_registered`
- `soraswap_dlmm_position_bin_id`
- `soraswap_dlmm_position_shares`
- `soraswap_dlmm_position_fee_debt_base`
- `soraswap_dlmm_position_fee_debt_quote`
- `soraswap_dlmm_position_credit_base`
- `soraswap_dlmm_position_credit_quote`

Notes:
- The pool layout models a single deployed DLMM instance with fixed-price bin traversal and guard rails stored directly on the contract.
- Seeded helper liquidity contributes directly to per-bin reserves and share supply, while owner-facing LP records live under explicit `position_id` names that checkpoint per-bin fee growth and accumulate withdrawable credits.
- Multi-pool registry/factory parity is still pending, and the current owner-facing position surface is a single-contract scaffold rather than the final helper/NFT layout.
- `scripts/smoke_testnet.sh` reads those fields through `/v1/contracts/view` and records both raw view tuples and decoded integer values in the smoke report.
