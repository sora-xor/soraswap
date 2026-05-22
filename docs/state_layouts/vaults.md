# Vaults State Layout

Vault state is keyed by `vault_id`; positions are keyed by caller-provided `position_id`; redemption requests are keyed by `request_id`.

Tracked values:
- vault owner, underlying asset, share asset, strategy code, async flag
- total assets, total shares, per-position owner, vault, and shares
- request owner, vault, shares, claim slot, request status

Position ids are scoped to the depositing caller and vault. Redemption claim readiness is checked against contract `block_height()`.
