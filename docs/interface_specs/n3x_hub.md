# n3x Hub Interface

Contract: `contracts/n3x/n3x_hub.ko`

Public entrypoints:
- `main() -> int`
- `init_hub(usdt_asset, usdc_asset, kusd_asset, n3x_asset, vault_account, target_usdt_bps, target_usdc_bps, target_kusd_bps, mint_fee_bps, redeem_fee_bps)`
- `bind_vault_account(vault_account)`
- `quote_mint(usdt_in, usdc_in, kusd_in) -> int`
- `quote_redeem(n3x_amount) -> int`
- `assert_initialized() -> int`
- `hub_config() -> (AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- `mirror_state() -> (int, int, int, int, int, int, int, int, int, int, int, int)`
- `fee_reserve_state() -> (int, int, int, int, int)`
- `deposit_and_mint(usdt_in, usdc_in, kusd_in) -> int`
- `burn_and_redeem(n3x_amount) -> int`

Notes:
- Runtime config is singleton after init; `configure_hub` remains removed. `bind_vault_account(...)` is owner-only custody rebinding and does not mutate basket or fee accounting.
- User flows derive the caller from `authority()` and use canonical stored assets plus the stored vault only.
- Asset-moving entrypoints carry a neutral `permission(AssetOps)` compiler hint, not an admin-only business rule.
- Repo bootstrap targets the current `n3x_hub` contract subject for public `testnet|production` `VaultAccount` and migrates seeded balances forward from previous contract-subject custody after upgrades; `local` still defaults to the isolated `n3x_hub` contract subject unless `SORASWAP_N3X_VAULT_ACCOUNT` overrides it.
