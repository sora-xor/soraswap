# DLMM State Layout

Pool-wide scalar state:
- `PoolInitialized`
- `PoolOwner`
- `AdminRenounced`
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
- `RouterOwner`
- `BaseAsset`
- `QuoteAsset`
- `DefaultFeePips`
- `RouterContractId`
- `RouterContractBound`
- `BoundPoolContract`
- `PoolBound`
- `SwapHistoryHead`

Router swap-history maps:
- `SwapHistoryTrader`
- `SwapHistoryInputIsBase`
- `SwapHistoryAmountIn`
- `SwapHistoryAmountOut`
- `SwapHistoryMinOut`

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

View fields returned by `contract_binding()`:
- `soraswap_dlmm_router_contract_bound`

View fields returned by `execution_binding()`:
- `soraswap_dlmm_router_pool_bound`

View tuple fields returned by `router_assets()`:
- `soraswap_dlmm_router_base_asset`
- `soraswap_dlmm_router_quote_asset`

View field returned by `swap_history_head()`:
- `soraswap_dlmm_router_swap_history_head`

View tuple fields returned by `mirror_swap_history(record_id)`:
- `soraswap_dlmm_router_swap_trader`
- `soraswap_dlmm_router_swap_input_is_base`
- `soraswap_dlmm_router_swap_amount_in`
- `soraswap_dlmm_router_swap_amount_out`
- `soraswap_dlmm_router_swap_min_out`

View tuple fields returned by `pool_config()`:
- `soraswap_dlmm_pool_base_asset`
- `soraswap_dlmm_pool_quote_asset`
- `soraswap_dlmm_pool_vault_account`
- `soraswap_dlmm_pool_config_fee_pips`
- `soraswap_dlmm_pool_config_bin_step`
- `soraswap_dlmm_pool_config_active_bin`

View field returned by `custody_account()`:
- `soraswap_dlmm_pool_custody_account`

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

View tuple fields returned by `quote_position_fees(position_id)`:
- `soraswap_dlmm_position_pending_fee_base`
- `soraswap_dlmm_position_pending_fee_quote`

Notes:
- The pool layout models one deployed DLMM instance per contract address with fixed-price bin traversal and guard rails stored directly on the contract.
- `hajimari(...)` is asset-agnostic for generic pool instantiation, but the SoraSwap production deployment anchors its deployable AMM instance on `xor#universal` as the canonical DEX base asset.
- The active `VaultAccount` can now be rotated only by the current vault authority through `bind_custody_account(...)`; bootstrap uses that once to migrate legacy treasury-backed pools onto pool-subject custody.
- The signed testnet bootstrap now materializes the pool contract subject as the custody account so router c2c swaps settle under the pool runtime subject instead of an external treasury signer.
- The router layout now stores both its own contract subject account and the bound pool contract address because production execution uses same-transaction router-to-pool `call_contract(...)` dispatch, not quote-only inspection.
- The generic, asset-agnostic router now also stores a monotonic swap-history journal keyed by `record_id`. Each successful self-custodial `route_swap(...)` appends the effective trader, trade direction, exact `amount_in`, exact executed `amount_out`, and the submitted `min_out`.
- `make smoke-local` and the signed `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet` lane both record the router contract binding, router execution binding, and the post-swap decoded state snapshots.
- `quote_position_fees(...)` reports pending claimable fees after applying the current bin fee-growth deltas to the position's stored debt. `mirror_position(...)` remains a raw stored-state snapshot.
- Range governor state is stored in `RangeGovernorEnabled`, `RangeGovernorCadenceSlots`, `RangeGovernorNextSlot`, `RangeGovernorMaxFeePips`, `RangeGovernorTargetActiveBin`, `RangeGovernorMaxActiveBinDrift`, `RangeGovernorLastSlot`, and `RangeGovernorLastAction`. `PoolOwner` is captured at pool init for governor administration and does not replace `VaultAccount` custody semantics.
- `AdminRenounced` changes once from `0` to `1`. Renunciation permanently gates the range-governor callback to an inert return and makes custody binding and governor configuration permanently reject.
