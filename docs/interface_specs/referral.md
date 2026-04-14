# Referral Interface

Contract: `contracts/referral/registry.ko`

Public entrypoints:
- `main() -> int`
- `init_registry(reward_asset, treasury, claim_threshold, direct_share_bps, parent_share_bps)`
- `bind_member(member)`
- `bind_member_with_parent(member, parent_member)`
- `accrue(member, amount)`
- `claim(member)`
- `registry_config() -> (AssetDefinitionId, AccountId, int, int, int)`
- `mirror_member(member) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`

Notes:
- Registry config is init-only; `configure_registry` and `configure_tiers` were removed.
- Member ownership is bound to `authority()` when the member is created.
- `accrue` now funds the treasury from the caller before crediting child/parent accounting.
