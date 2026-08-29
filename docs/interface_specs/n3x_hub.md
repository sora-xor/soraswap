# n3x Hub Interface

Contract: `contracts/n3x/n3x_hub.ko`

Public entrypoints:
- `main() -> quantity`
- `hajimari(usdt_asset, usdc_asset, kusd_asset, n3x_asset, vault_account, target_usdt_bps, target_usdc_bps, target_kusd_bps, mint_fee_bps, redeem_fee_bps)`
- `quote_mint(usdt_in, usdc_in, kusd_in) -> quantity`
- `quote_redeem(n3x_amount) -> quantity`
- `assert_initialized() -> quantity`
- `hub_config() -> (AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- `mirror_state() -> (int, quantity, quantity, quantity, quantity, int, int, quantity, quantity, int, int, int)`
- `fee_reserve_state() -> (quantity, quantity, quantity, quantity, quantity)`
- `deposit_and_mint(usdt_in, usdc_in, kusd_in) -> quantity`
- `burn_and_redeem(n3x_amount) -> quantity`
- `claim_fees(recipient) -> quantity`

Notes:
- Runtime configuration and custody are immutable after `hajimari(...)`.
- User flows derive the caller from `authority()` and use canonical stored assets plus the stored vault only.
- Asset-moving entrypoints carry a neutral `permission(AssetOps)` compiler hint, not an admin-only business rule.
- Bootstrap targets the deployed `n3x_hub` contract subject as `VaultAccount` unless an explicit environment-specific custody account is selected before the first deployment.
