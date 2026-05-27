# DLMM Hooks Interface

Contract: `contracts/dlmm_hooks/hook_manager.ko`

Entrypoints:
- `configure_hook_policy(hook_id, phase, max_fee_pips, enabled)`
- `place_limit_order(order_id, hook_id, amount_in, min_out)`
- `schedule_twamm(order_id, hook_id, amount_in, min_out, interval_slots)`
- `init_trigger_twamm(base_asset, quote_asset, cadence_slots, max_orders_per_tick, enabled)`
- `bind_contract(contract_id)`
- `bind_router(router_contract)`
- `schedule_twamm_v2(order_id, input_is_base, total_in, slice_in, min_total_out, interval_slots, start_slot)`
- `cancel_twamm(order_id) -> remaining input`
- `claim_twamm(order_id) -> claimable output`
- `record_execution(order_id, amount_in, amount_out)`
- `hook_policy(hook_id) -> (int, int, int, int)`
- `quote_hooked_swap(order_id) -> (int, int, int, int, int)`
- `twamm_order_state(order_id) -> (int, int, int, int, int, int, int, int, int)`
- `twamm_trigger_state() -> (int, int, int, int, int, int, int)`

Notes:
- Hook phases are numeric launch labels: `1=dynamic_fee`, `2=limit_order`, `3=twamm`, `4=lp_fee`.
- The hook manager is intentionally separate from `dlmm_pool` so pool math remains stable while hook policies evolve.
- `soraswap_twamm_tick` is a bounded pre-commit trigger. It scans at most `max_orders_per_tick` TWAMM records and routes due slices through the bound DLMM router with the hook-manager contract subject as custody/trader.
- TWAMM v2 enforces `min_total_out` across the full order: intermediate slices use proportional floors, the final slice carries any rounded remainder, and completed-order claims reject if executed output is below the aggregate minimum. Cancelled orders may still claim already executed output.
