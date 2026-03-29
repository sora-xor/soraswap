# DLMM Interface

Contracts:
- `contracts/dlmm/dlmm_pool.ko`
- `contracts/dlmm/dlmm_router.ko`

`dlmm_pool.ko` public entrypoints:
- `main() -> int`
- `init_pool(base_asset, quote_asset, vault_account, fee_pips, bin_step, active_bin)`
- `set_risk_params(impact_cap_bps, min_reserve_base, min_reserve_quote, max_bins_per_swap, bin_liquidity_cap)`
- `seed_bin_with_assets(provider, vault_account, base_asset, quote_asset, bin_id, base_amount, quote_amount)`
- `add_position_liquidity_with_assets(position_id, provider, vault_account, base_asset, quote_asset, bin_id, base_amount, quote_amount, min_shares_out) -> int`
- `remove_position_liquidity_with_assets(position_id, recipient, vault_account, base_asset, quote_asset, shares) -> int`
- `collect_position_fees_with_assets(position_id, recipient, vault_account, base_asset, quote_asset) -> int`
- `mirror_state() -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`
- `pool_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int)`
- `risk_config() -> (int, int, int, int, int)`
- `mirror_bin(bin_id) -> (int, int, int, int, int)`
- `mirror_position(position_id) -> (int, int, int, int, int, int, int)`
- `swap_exact_in_with_assets(trader, input_asset, vault_account, base_asset, quote_asset, amount_in, min_out) -> int`

`dlmm_router.ko` public entrypoints:
- `main() -> int`
- `init_router(base_asset, default_fee_pips)`
- `assert_router_config(default_fee_pips)`
- `router_config() -> (AssetDefinitionId, int)`
- `mirror_state() -> (int, int)`
- `quote_direct(reserve_in, reserve_out, amount_in, fee_pips) -> int`
- `quote_bin(reserve_base, reserve_quote, amount_in, fee_pips, bin_id, bin_step, input_is_base, min_reserve_base, min_reserve_quote) -> int`
- `select_best_quote(direct_out, via_base_out) -> int`

Notes:
- The pool now executes a deterministic multi-bin walk: swaps consume the active bin first, then advance by `bin_step` while output-side liquidity remains available and guard limits are not exceeded.
- `swap_exact_in*` only transfers the portion of input that is actually consumed by the walk. If guards or empty bins stop traversal early, unused input remains with the trader.
- `seed_bin_with_assets` seeds anonymous helper liquidity directly into a bin. Owner-facing LP accounting lives in explicit `position_id` records, with fee claims accruing per bin and collected without burning shares.
- `remove_position_liquidity*` currently requires the position’s credited fees to be collected first so share burns do not double-count reserve-embedded fees in this single-contract scaffold.
- The router surface remains quote-oriented because Kotodama cross-contract routing is not yet modeled in this repo.
- `xor#universal` is the intended quote/base anchor for deployable pools.
- `seed_bin_with_assets`, the position entrypoints, and `swap_exact_in_with_assets` exist so live-node flows do not depend on state-loaded pointer comparisons for asset and vault ids.
- The pool keeps its quote walk internal to stay within current IVM payload limits. External quote smoke stays on `dlmm_router.ko`, while `pool_config`, `risk_config`, `mirror_bin`, `mirror_position`, and `mirror_state()` provide bootstrap and post-swap readback.
