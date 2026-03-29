# Referral Interface

Contract: `contracts/referral/registry.ko`

Public entrypoints:
- `main() -> int`
- `init_registry(reward_asset, treasury)`
- `configure_registry(reward_asset, treasury, claim_threshold)`
- `configure_tiers(direct_share_bps, parent_share_bps)`
- `bind_referrer(member, referrer)`
- `bind_referrer_with_parent(member, referrer, parent_member)`
- `accrue(member, amount)`
- `claim(claimant, member)`
- `claim_with_assets(claimant, member, treasury, reward_asset)`
- `registry_config() -> (AssetDefinitionId, AccountId, int, int, int)`
- `mirror_member(member) -> (int, int, int, int, int, int, int, int, int, int, int, int, int)`

Notes:
- The registry is keyed under a single `registry` slot for shared config, while per-member accounting lives under the `member` name.
- `configure_tiers` stores the routed split between a member and its linked parent member. The split is configured in basis points and must sum to `10000`.
- `bind_referrer_with_parent` links a member to an already-bound parent member so routed accrual can flow to the parent member’s bound referrer account.
- `accrue` now routes to two tiers when a parent member is linked: the child member receives the configured direct share and the parent member receives the remainder.
- `claim_with_assets` now requires the `claimant` to match the bound `referrer` for the `member`.
- `configure_registry` exposes a claim threshold so smoke and deploy flows can prove nontrivial accrual and payout handling.
- `registry_config` and `mirror_member` are `view fn` entrypoints consumed through `/v1/contracts/view`.
