# Batch AMM Interface

Contract: `contracts/batch_amm/epoch_auction.ko`

Entrypoints:
- `init_auction(base_asset, quote_asset)`
- `bind_contract(contract_id)`
- `configure_epoch(epoch_id, start_slot, end_slot, lower_tick, upper_tick, tick_step, max_orders)`
- `submit_order(order_id, side, amount, limit_tick) -> escrowed order`
- `cancel_order(order_id) -> refunded amount`
- `close_epoch()`
- `native_epoch_auction_close()`
- `settle_order(order_id) -> output amount`
- `epoch_state() -> (int, int, int, int, int, int, int, int, int, int, int)`
- `order_state(order_id) -> (int, int, int, int, int, int, int, int, int)`

Trigger:
- `soraswap_epoch_auction_close`
- Kind: `on time pre_commit; repeats indefinitely;`
- Callback: `native_epoch_auction_close`
- Metadata defaults include `__enabled=false`; `configure_epoch` enables it and the native close path disables it after the epoch closes or if no active epoch remains.

Notes:
- Default deployment config uses `xor#universal` as base and `n3x#soraswap.universal` as quote.
- Side `1` is a quote-escrowed bid; side `2` is a base-escrowed ask.
- Closing scans bounded price ticks, stores one uniform clearing tick, and leaves settlement user-driven.
- Pro-rata allocation is applied at the clearing tick; non-crossing and unfilled balances are refunded through `settle_order`.
- Closed epoch clearing data is retained by epoch id, so unsettled prior-epoch orders settle against their own epoch even after a later epoch is configured.
- `cancel_order` is scoped to the order's epoch and only succeeds while that epoch is active.
