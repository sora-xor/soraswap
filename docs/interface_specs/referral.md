# Referral Interface

Contract: `contracts/referral/registry.ko`

Public entrypoints:
- `hajimari(reward_asset, treasury, claim_threshold, direct_share_bps, parent_share_bps)`
- `main() -> int`
- `bind_member(member)`
- `bind_member_with_parent(member, parent_member)`
- `accrue(member, amount)`
- `claim(member)`
- `registry_config() -> (AssetDefinitionId, AccountId, quantity, int, int)`
- `mirror_member(member) -> (int, quantity, int, int, quantity, quantity, quantity, int, int, quantity, quantity, quantity, int)`

Notes:
- Registry config is immutable after `hajimari(...)`.
- Member ownership is bound to `authority()` when the member is created.
- `accrue` now funds the treasury from the caller before crediting child/parent accounting.
