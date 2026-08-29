# Conditional Escrow Interface

Contract: `contracts/escrow/conditional_escrow.ko`

Entrypoints:
- `hajimari(escrow_account)`
- `main() -> int`
- `open_escrow(escrow_id, taker, asset, amount, expiry_slot, condition_code)`
- `accept_escrow(escrow_id, condition_code) -> quantity`
- `native_by_call_settle() -> quantity`
- `cancel_escrow(escrow_id) -> quantity`
- `refund_expired(escrow_id) -> quantity`
- `escrow_state(escrow_id) -> (int, quantity, int, int, int, int)`
- `escrow_config() -> AccountId`

Trigger:
- `soraswap_escrow_settle`
- Kind: `on execute trigger soraswap_escrow_settle; repeats indefinitely;`
- Callback: `native_by_call_settle`

Notes:
- `accept_escrow` is the ordinary public path.
- The escrow custody account is fixed by `hajimari(...)`; there is no post-deployment bind operation.
- `native_by_call_settle` is the by-call trigger path. It reads `escrow_id` and `condition_code` from `trigger_event()` arguments.
- The smoke wrappers require every expected trigger to be registered, separately record active trigger IDs, grant `CanExecuteTrigger` to the signer, and execute `soraswap_escrow_settle` with `escrow_id` and `condition_code` arguments.
- Trigger completion evidence is accepted only from native `block_result` trigger completions persisted by the current runtime. Reconstructed completion history and reconstructed by-call argument payloads are not supported.
