# Intents Interface

Contract: `contracts/intents/settlement_router.ko`

Entrypoints:
- `hajimari(custody_account, fee_account)`
- `main() -> int`
- `open_intent(intent_id, input_asset, output_asset, amount_in, min_out, solver_fee_bps, deadline_slot, nonce)`
- `cancel_intent(intent_id)`
- `fill_intent(intent_id, amount_out)`
- `intent_state(intent_id) -> (int, int, quantity, quantity, int, int, int, int, quantity, quantity)`

Notes:
- Status values: `1=open`, `2=filled`, `3=cancelled`.
- Custody and fee accounts are immutable after `hajimari(...)`.
- Fill expiry and recorded fill slot use contract `block_height()`; solvers do not provide a slot.
- The contract records the SoraSwap product state; the matching native Iroha `SubmitDefiIntent` / `SettleDefiIntent` ISIs provide canonical ledger records.
