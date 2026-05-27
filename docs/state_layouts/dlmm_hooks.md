# DLMM Hooks State Layout

Hook state is keyed by `hook_id`; hook-owned orders are keyed by `order_id`.

Tracked values:
- hook owner, phase, max fee, enabled flag
- order owner, hook id, amount in, minimum output, TWAMM interval
- cumulative executed input and output
- trigger-native TWAMM config: owner, base/quote assets, contract subject, router contract, cadence, per-tick order cap, enabled flag, scan cursor, and last tick counters
- TWAMM v2 orders: owner, input side, total/remaining/executed input, executed/claimed output, slice size, minimum total output, interval, next slot, and status
