# Cover Interface

Contract: `contracts/cover/policy_manager.ko`

Public entrypoints:
- `main() -> int`
- `init_policy(policy, settlement_asset, vault_account, duration_slots, payout_bps, premium)`
- `configure_policy(policy, duration_slots, payout_bps, premium)`
- `buy_policy(buyer, policy)`
- `buy_policy_with_assets(buyer, policy, vault_account, settlement_asset, premium)`
- `buy_policy_sized(buyer, policy, covered_notional)`
- `buy_policy_sized_with_assets(buyer, policy, vault_account, settlement_asset, premium, covered_notional)`
- `record_breach(policy, elapsed_slots)`
- `settle_claim(claimant, policy, covered_notional)`
- `settle_claim_with_assets(claimant, policy, vault_account, settlement_asset, covered_notional)`
- `cancel_policy(buyer, policy, refund_bps)`
- `cancel_policy_with_assets(buyer, policy, vault_account, settlement_asset, refund_bps)`
- `expire_policy(policy, elapsed_slots)`
- `policy_config(policy) -> (AssetDefinitionId, AccountId, int, int, int)`
- `mirror_policy(policy) -> (int, int, int, int, int, int, int, int, int)`

Notes:
- Policies now record owner, covered notional, premium paid, claim payout, and an explicit expired flag.
- `buy_policy*` remains for compatibility and falls back to premium-sized notional, while `buy_policy_sized*` is the explicit smoke/deploy path.
- `policy_config` and `mirror_policy` are `view fn` entrypoints consumed through `/v1/contracts/view`.
