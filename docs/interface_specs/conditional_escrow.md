# Conditional Escrow Interface

Contract: `contracts/escrow/conditional_escrow.ko`

Entrypoints:
- `init_escrow()`
- `bind_contract(contract_id)`
- `open_escrow(escrow_id, taker, asset, amount, expiry_slot, condition_code)`
- `accept_escrow(escrow_id, condition_code) -> amount`
- `native_by_call_settle() -> amount`
- `cancel_escrow(escrow_id) -> amount`
- `refund_expired(escrow_id) -> amount`
- `escrow_state(escrow_id) -> (int, int, int, int, int, int)`

Trigger:
- `soraswap_escrow_settle`
- Kind: `on execute trigger soraswap_escrow_settle; repeats indefinitely;`
- Callback: `native_by_call_settle`

Notes:
- `accept_escrow` is the ordinary public path.
- `native_by_call_settle` is the by-call trigger path. It reads `escrow_id` and `condition_code` from `trigger_event()` arguments.
- The smoke wrappers require every expected trigger to be registered, separately record active trigger IDs, grant `CanExecuteTrigger` to the signer, and execute `soraswap_escrow_settle` with `escrow_id` and `condition_code` arguments.
- Trigger completion evidence is query-visible for blocks that persist native `block_result` trigger completions. Older local chains may still expose reconstructed completion history for ordinary trigger outcomes, but by-call argument payloads are not reconstructed from legacy blocks.
