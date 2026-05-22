# Intents State Layout

State is keyed by `intent_id`.

Fields:
- owner, input/output asset, input amount, minimum output, solver fee, deadline slot, nonce
- status, solver, output amount, fill slot

The fill slot is recorded from contract `block_height()` when a solver fills the intent.

Status values: `1=open`, `2=filled`, `3=cancelled`.
