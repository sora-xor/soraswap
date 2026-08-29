# DLMM Hooks Interface

Contract: `contracts/dlmm_hooks/hook_manager.ko`

Entrypoints:
- `hajimari(base_asset, quote_asset, custody_account, router_contract, guardian)`
- `main() -> int`
- `configure_hook_policy(hook_id, phase, max_fee_pips, enabled)`
- `configure_trigger_twamm(cadence_slots, max_orders_per_tick, enabled)`
- `enter_withdrawal_only()`
- `exit_withdrawal_only()`
- `place_limit_order(order_id, hook_id, amount_in, min_out)`
- `record_execution(order_id, amount_in, amount_out)`
- `schedule_twamm(order_id, total_in, slice_in, input_is_base, min_total_out, start_slot, interval_slots)`
- `cancel_twamm(order_id) -> quantity`
- `claim_twamm(order_id) -> quantity`
- `native_twamm_tick()`
- `hook_policy(hook_id) -> (int, int, int, int)`
- `quote_hooked_swap(order_id) -> (quantity, quantity, quantity, quantity, int)`
- `twamm_order_state(order_id) -> (int, quantity, quantity, quantity, quantity, quantity, int, int, int)`
- `twamm_trigger_state() -> (int, int, int, int, int, int, int)`

Notes:
- Hook phases are numeric launch labels: `1=dynamic_fee`, `2=limit_order`, `3=twamm`, `4=lp_fee`.
- The hook manager is intentionally separate from `dlmm_pool` so pool math remains stable while hook policies evolve.
- Assets, custody, router, and guardian are immutable after `hajimari(...)`.
- `schedule_twamm(...)` is the canonical TWAMM scheduling entrypoint. It escrows the full input amount into the hook-manager contract subject before trigger execution can route slices.
- `soraswap_twamm_tick` is a bounded pre-commit trigger. It scans at most `max_orders_per_tick` TWAMM records and routes due slices through the bound DLMM router with the hook-manager contract subject as custody/trader.
- TWAMM enforces `min_total_out` across the full order: intermediate slices use proportional floors, the final slice carries any rounded remainder, and completed-order claims reject if executed output is below the aggregate minimum. Cancelled orders may still claim already executed output.
