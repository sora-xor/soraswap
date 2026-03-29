# n3x Hub Interface

Contract: `contracts/n3x/n3x_hub.ko`

Public entrypoints:
- `main() -> int`
- `init_hub(usdt_asset, usdc_asset, kusd_asset, n3x_asset, vault_account)`
- `configure_hub(target_usdt_bps, target_usdc_bps, target_kusd_bps, mint_fee_bps, redeem_fee_bps)`
- `quote_mint(usdt_in, usdc_in, kusd_in) -> int`
- `quote_redeem(n3x_amount) -> int`
- `assert_initialized() -> int`
- `hub_config() -> (AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- `mirror_state() -> (int, int, int, int, int, int, int, int, int, int, int, int)`
- `deposit_and_mint(user, usdt_in, usdc_in, kusd_in) -> int`
- `deposit_and_mint_with_assets(user, vault_account, usdt_asset, usdc_asset, kusd_asset, n3x_asset, usdt_in, usdc_in, kusd_in) -> int`
- `burn_and_redeem(user, n3x_amount) -> int`
- `burn_and_redeem_with_assets(user, vault_account, usdt_asset, usdc_asset, kusd_asset, n3x_asset, n3x_amount) -> int`

Notes:
- This is the renamed `n3x` basket surface.
- The DEX base asset is still `xor#universal`; this hub is not the routing base.
- `configure_hub` sets target basket weights plus independent mint and redeem fees in basis points.
- `quote_mint` returns the net mint amount after the configured mint fee, while `quote_redeem` returns the aggregate redeem output after per-asset redeem fees.
- `deposit_and_mint*` accrues the mint fee into `MintFeesAccrued` while leaving the full deposited basket in reserves, and `burn_and_redeem*` accrues per-asset redeem fees into `RedeemFeesAccrued` while leaving those fees inside the basket balances.
- The `*_with_assets` entrypoints are compatibility paths for live nodes where state-loaded asset and vault pointers can still fail inside host syscall argument decoding.
- `assert_initialized`, `hub_config`, and `mirror_state` are `view fn` entrypoints consumed through `/v1/contracts/view`.
