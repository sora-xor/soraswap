# DLMM Hooks Interface

Contract: `contracts/dlmm_hooks/hook_manager.ko`

Entrypoints:
- `configure_hook_policy(hook_id, phase, max_fee_pips, enabled)`
- `place_limit_order(order_id, hook_id, amount_in, min_out)`
- `schedule_twamm(order_id, hook_id, amount_in, min_out, interval_slots)`
- `record_execution(order_id, amount_in, amount_out)`
- `hook_policy(hook_id) -> (int, int, int, int)`
- `quote_hooked_swap(order_id) -> (int, int, int, int, int)`

Notes:
- Hook phases are numeric launch labels: `1=dynamic_fee`, `2=limit_order`, `3=twamm`, `4=lp_fee`.
- The hook manager is intentionally separate from `dlmm_pool` so pool math remains stable while hook policies evolve.
