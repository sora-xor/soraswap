# DLMM Hooks State Layout

Hook state is keyed by `hook_id`; hook-owned orders are keyed by `order_id`.

Tracked values:
- hook owner, phase, max fee, enabled flag
- order owner, hook id, amount in, minimum output, TWAMM interval
- cumulative executed input and output
