# DLMM Interface

Contracts:
- `contracts/dlmm/dlmm_pool.ko`
- `contracts/dlmm/dlmm_router.ko`

`dlmm_pool.ko` public entrypoints:
- `main() -> int`
- `hajimari(base_asset, quote_asset, vault_account, fee_pips, bin_step, active_bin, impact_cap_bps, min_reserve_base, min_reserve_quote, max_bins_per_swap, bin_liquidity_cap)`
- `seed_bin(position_id, bin_id, base_amount, quote_amount) -> quantity`
- `add_position_liquidity(position_id, bin_id, base_amount, quote_amount, min_shares_out) -> quantity`
- `remove_position_liquidity(position_id, shares) -> quantity`
- `collect_position_fees(position_id) -> quantity`
- `mirror_state() -> (int, int, int, int, quantity, quantity, quantity, quantity, int, quantity, quantity, int, quantity)`
- `pool_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int)`
- `configured_base_asset() -> AssetDefinitionId`
- `configured_quote_asset() -> AssetDefinitionId`
- `configured_vault_account() -> AccountId`
- `bind_custody_account(vault_account)`
- `custody_account() -> AccountId`
- `risk_config() -> (int, quantity, quantity, int, quantity)`
- `mirror_bin(bin_id) -> (quantity, quantity, quantity, decimal, decimal)`
- `mirror_position(position_id) -> (int, int, quantity, decimal, decimal, quantity, quantity)`
- `quote_position_fees(position_id) -> (quantity, quantity)`
- `swap_exact_in(input_asset, amount_in, min_out) -> quantity`
- `swap_exact_in_base(amount_in, min_out) -> quantity`
- `swap_exact_in_quote(amount_in, min_out) -> quantity`
- `swap_exact_in_quote_public(amount_in, min_out) -> quantity`
- `swap_exact_in_base_for(recipient, amount_in, min_out) -> quantity`
- `swap_exact_in_quote_for(recipient, amount_in, min_out) -> quantity`
- `renounce_admin()`
- `admin_state() -> (AccountId, int)`
- `configure_range_governor(cadence_slots, max_fee_pips, target_active_bin, max_active_bin_drift, enabled)`
- `native_range_governor_tick()`
- `range_governor_state() -> (int, int, int, int, int, int, int, int)`

`dlmm_router.ko` public entrypoints:
- `main() -> int`
- `init_router(base_asset, default_fee_pips)`
- `bind_contract(contract_id)`
- `bind_pool(pool_contract, quote_asset)`
- `assert_router_config(default_fee_pips)`
- `router_config() -> (AssetDefinitionId, int)`
- `router_assets() -> (AssetDefinitionId, AssetDefinitionId)`
- `mirror_state() -> (int, int)`
- `swap_history_head() -> int`
- `mirror_swap_history(record_id) -> (AccountId, int, int, int, int)`
- `contract_binding() -> int`
- `execution_binding() -> int`
- `quote_direct(reserve_in, reserve_out, amount_in, fee_pips) -> int`
- `quote_bin(reserve_base, reserve_quote, amount_in, fee_pips, bin_id, bin_step, input_is_base, min_reserve_base, min_reserve_quote) -> int`
- `select_best_quote(direct_out, via_base_out) -> int`
- `route_swap(amount_in, input_is_base, min_out) -> int`

Notes:
- Pool risk config is immutable after `hajimari`; `set_risk_params` was removed.
- The typed `configured_*` views expose the generic stored base, quote, and vault values so nested callers can fail closed on an exact pool binding without adding pair-specific policy to SoraSwap.
- Liquidity and swap entrypoints bind the trader/provider to `authority()` and use stored pool assets plus vault only.
- `swap_exact_in_quote_public(...)` is the minimum generic public route required by autonomous CBSI payout. It requires the exact direct typed `CanInvokeContractEntrypoint(pool, swap_exact_in_quote_public)` token. It accepts no trader or recipient, always debits and pays `context::authority()`, and requires a complete exact-input fill.
- `renounce_admin()` permanently gates the range governor off and freezes every owner-controlled setting. The declared governor trigger remains inert because its callback returns while the gate is zero. The contract has no `kaizen`, owner rotation, or recovery path, and every remaining admin entrypoint checks the irreversible `AdminRenounced` flag.
- `bind_custody_account(...)` is a vault-authorized migration hook for rotating an already-initialized pool from legacy treasury custody into subject-backed custody.
- The production bootstrap now binds the DLMM pool vault to the pool contract subject so direct pool flows and router-to-pool nested swaps share the same custody authority model on public Taira.
- The release path is no longer quote-only. `dlmm_router.ko` binds both its own contract subject account and a deployed pool, then executes same-transaction contract-to-contract swaps through `route_swap(...)`.
- `route_swap(...)` now escrows the caller input into the router contract subject before the c2c pool call, and the pool pays the output directly to the signer through the recipient-aware `swap_exact_in_*_for(...)` entrypoints.
- Successful router swaps now append a router-local fill journal. Use `swap_history_head()` plus `mirror_swap_history(record_id)` to reconstruct exact executed fills and user-facing entry/exit analytics without inferring amounts from the submitted call payload alone.
- `router_assets()` exposes both the canonical base asset and the currently bound quote asset so charting and journal surfaces can label the traded pair directly from the router state.
- `mirror_position(...)` exposes stored fee debt and stored credits only. Use `quote_position_fees(...)` to read the fees that would become claimable after an accrual pass, especially before `remove_position_liquidity(...)`.
- `soraswap_range_governor_tick` is a pre-commit trigger on `dlmm_pool`. It reads internal pool state only, bounds fee/risk drift, and can realign active-bin drift to a populated configured target bin without moving assets.
