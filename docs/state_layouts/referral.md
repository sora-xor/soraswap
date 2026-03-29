# Referral State Layout

Registry-slot maps:
- `RewardAsset`
- `Treasury`
- `ClaimThreshold`
- `DirectShareBps`
- `ParentShareBps`

Per-member maps:
- `Referrer`
- `ParentMember`
- `Accrued`
- `TotalAccrued`
- `TotalClaimed`
- `ClaimCount`

View tuple fields returned by `mirror_member()`:
- `soraswap_referral_bound`
- `soraswap_referral_claim_threshold`
- `soraswap_referral_direct_share_bps`
- `soraswap_referral_parent_share_bps`
- `soraswap_referral_accrued`
- `soraswap_referral_total_accrued`
- `soraswap_referral_total_claimed`
- `soraswap_referral_claim_count`
- `soraswap_referral_parent_bound`
- `soraswap_referral_parent_accrued`
- `soraswap_referral_parent_total_accrued`
- `soraswap_referral_parent_total_claimed`
- `soraswap_referral_parent_claim_count`

View tuple fields returned by `registry_config()`:
- `soraswap_referral_reward_asset`
- `soraswap_referral_treasury`
- `soraswap_referral_claim_threshold_config`
- `soraswap_referral_direct_share_bps_config`
- `soraswap_referral_parent_share_bps_config`

Notes:
- `DirectShareBps` and `ParentShareBps` are singleton routing parameters keyed under the `registry` slot and must sum to `10000`.
- `ParentMember` links a child member to an upstream member whose bound referrer account receives the routed parent-share accrual.
- `mirror_member()` reports the selected member plus its linked parent member, if present, through `/v1/contracts/view`.
