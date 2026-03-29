# Cover State Layout

Per-policy maps:
- `SettlementAsset`
- `VaultAccount`
- `DurationSlots`
- `PayoutBps`
- `Premium`
- `PolicyOwner`
- `PolicyNotional`
- `PremiumPaid`
- `BreachElapsed`
- `Active`
- `ClaimPayout`
- `Expired`
- `ClaimCount`

View tuple fields returned by `mirror_policy()`:
- `soraswap_cover_active`
- `soraswap_cover_duration_slots`
- `soraswap_cover_payout_bps`
- `soraswap_cover_premium_paid`
- `soraswap_cover_notional`
- `soraswap_cover_breach_elapsed`
- `soraswap_cover_claim_payout`
- `soraswap_cover_expired`
- `soraswap_cover_claim_count`

View tuple fields returned by `policy_config()`:
- `soraswap_cover_settlement_asset`
- `soraswap_cover_vault_account`
- `soraswap_cover_config_duration_slots`
- `soraswap_cover_config_payout_bps`
- `soraswap_cover_config_premium`
