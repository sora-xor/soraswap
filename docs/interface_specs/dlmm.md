# DLMM Interface

Contracts:
- `contracts/dlmm/dlmm_pool.ko`
- `contracts/dlmm/dlmm_router.ko`

`dlmm_pool.ko` lifecycle and entrypoints:
- `hajimari(base_asset, quote_asset, vault_account, launchpad_executor, fee_pips, bin_step, active_bin, impact_cap_bps, min_reserve_base, min_reserve_quote, max_bins_per_swap, bin_liquidity_cap)`
- `main() -> int`
- `seed_bin(position_id, bin_id, base_amount, quote_amount) -> quantity`
- `seed_launchpad_liquidity(amount_in, min_out) -> quantity`
- `add_position_liquidity(position_id, bin_id, base_amount, quote_amount, min_shares_out) -> quantity`
- `remove_position_liquidity(position_id, shares) -> quantity`
- `collect_position_fees(position_id) -> quantity`
- `swap_exact_in(input_asset, amount_in, min_out) -> quantity`
- `swap_exact_in_base(amount_in, min_out) -> quantity`
- `swap_exact_in_quote(amount_in, min_out) -> quantity`
- `renounce_admin()`
- `configure_range_governor(cadence_slots, max_fee_pips, target_active_bin, max_active_bin_drift, enabled)`
- `native_range_governor_tick()`
- `mirror_state() -> (int, int, int, int, quantity, quantity, quantity, quantity, int, quantity, quantity, int, quantity)`
- `pool_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int)`
- `configured_base_asset() -> AssetDefinitionId`
- `configured_quote_asset() -> AssetDefinitionId`
- `configured_vault_account() -> AccountId`
- `launchpad_binding() -> (AccountId, int)`
- `custody_account() -> AccountId`
- `risk_config() -> (int, quantity, quantity, int, quantity)`
- `mirror_bin(bin_id) -> (quantity, quantity, quantity, decimal, decimal)`
- `mirror_bin_index(bin_id) -> (int, int, int, int)`
- `mirror_position(position_id) -> (int, int, quantity, decimal, decimal, quantity, quantity)`
- `quote_position_fees(position_id) -> (quantity, quantity)`
- `range_governor_state() -> (int, int, int, int, int, int, int, int)`
- `admin_state() -> (AccountId, int)`

`dlmm_router.ko` lifecycle and entrypoints:
- `hajimari(base_asset, quote_asset, default_fee_pips, pool_contract, guardian)`
- `main() -> int`
- `set_paused(paused)`
- `assert_router_config(default_fee_pips) -> int`
- `router_config() -> (AssetDefinitionId, AssetDefinitionId, int, AccountId, bytes, int)`
- `router_assets() -> (AssetDefinitionId, AssetDefinitionId)`
- `mirror_state() -> (int, int, int)`
- `swap_history_head() -> int`
- `mirror_swap_history(record_id) -> (AccountId, int, quantity, quantity, quantity, int)`
- `contract_binding() -> int`
- `execution_binding() -> int`
- `quote_direct(reserve_in, reserve_out, amount_in, fee_pips) -> quantity`
- `quote_bin(reserve_base, reserve_quote, amount_in, fee_pips, bin_id, bin_step, input_is_base, min_reserve_base, min_reserve_quote) -> quantity`
- `select_best_quote(direct_out, via_base_out) -> quantity`
- `route_swap(amount_in, input_is_base, min_out) -> quantity`
- `route_exact_in_base(amount_in, min_out) -> quantity`
- `route_exact_in_quote(amount_in, min_out) -> quantity`

Notes:
- Pool assets, custody, launchpad executor, launchpad bin, fees, and risk limits are fixed at `hajimari(...)`. There is no post-init custody or pair rebinding surface.
- The pool reserves one position for its configured launchpad executor. `seed_launchpad_liquidity(...)` is the exact current Iroha Quantity2 nested-call surface: `amount_in` is the base deposit and `min_out` is the quote deposit; caller, position, and bin come from immutable pool state.
- `swap_exact_in(...)` is the flexible direct-user surface. The two directional selectors have the exact `(amount_in, min_out) -> quantity` nested ABI and require a complete fill, preventing caller-contract custody from retaining residual input.
- The router derives its custody account from `context::seiyaku_subject()`, stores the exact pool byte address at initialization, and begins paused. Bootstrap verifies the full binding before the owner unpauses it.
- A routed swap first transfers the caller's input to the router subject. The pool debits and credits that subject during the synchronous nested call; after it returns, the router transfers the exact output to the original caller and appends a local fill record. Any rejection rolls back the whole transaction.
- Contract callers use `route_exact_in_base(...)` or `route_exact_in_quote(...)`; `route_swap(...)` remains the unified direct-user entrypoint. All three converge on one implementation and one history journal.
- `renounce_admin()` is irreversible. It disables the range governor and permanently closes every remaining owner-controlled pool setting.
- `mirror_position(...)` exposes stored fee debt and credits. `quote_position_fees(...)` includes fees implied by current bin growth and is the claim preview.
