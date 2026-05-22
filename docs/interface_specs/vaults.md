# Vaults Interface

Contract: `contracts/vaults/manager.ko`

Entrypoints:
- `register_vault(vault_id, underlying_asset, share_asset, strategy_code, async_redeem)`
- `deposit(vault_id, position_id, amount)`
- `request_redeem(vault_id, request_id, position_id, shares, claim_slot)`
- `claim_redeem(request_id, current_slot)`
- `vault_state(vault_id) -> (int, int, int, int, int)`
- `position_state(position_id) -> int`

Notes:
- The first launch vault is expected to use the `n3x` basket as underlying strategy input.
- Async redemption requests are explicit and claim-gated by slot.
