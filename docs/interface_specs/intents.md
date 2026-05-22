# Intents Interface

Contract: `contracts/intents/settlement_router.ko`

Entrypoints:
- `open_intent(intent_id, input_asset, output_asset, amount_in, min_out, solver_fee_bps, deadline_slot, nonce)`
- `cancel_intent(intent_id)`
- `fill_intent(intent_id, amount_out)`
- `intent_state(intent_id) -> (int, int, int, int, int, int, int, int, int)`

Notes:
- Status values: `1=open`, `2=filled`, `3=cancelled`.
- Fill expiry and recorded fill slot use contract `block_height()`; solvers do not provide a slot.
- The contract records the SoraSwap product state; the matching native Iroha `SubmitDefiIntent` / `SettleDefiIntent` ISIs provide canonical ledger records.
