# n3x Hub State Layout

Scalar state:
- `HubInitialized`
- `HubOwner`
- `UsdtAsset`
- `UsdcAsset`
- `KusdAsset`
- `N3xAsset`
- `VaultAccount`
- `BasketUsdt`
- `BasketUsdc`
- `BasketKusd`
- `TotalN3x`
- `MintFeeBps`
- `RedeemFeeBps`
- `MintFeesAccrued`
- `RedeemFeesAccrued`
- `FeeReserveUsdt`
- `FeeReserveUsdc`
- `FeeReserveKusd`
- `TargetUsdtBps`
- `TargetUsdcBps`
- `TargetKusdBps`

View tuple fields returned by `mirror_state()`:
- `soraswap_n3x_hub_initialized`
- `soraswap_n3x_basket_usdt`
- `soraswap_n3x_basket_usdc`
- `soraswap_n3x_basket_kusd`
- `soraswap_n3x_total_n3x`
- `soraswap_n3x_mint_fee_bps`
- `soraswap_n3x_redeem_fee_bps`
- `soraswap_n3x_mint_fees_accrued`
- `soraswap_n3x_redeem_fees_accrued`
- `soraswap_n3x_target_usdt_bps`
- `soraswap_n3x_target_usdc_bps`
- `soraswap_n3x_target_kusd_bps`

View tuple fields returned by `hub_config()`:
- `soraswap_n3x_usdt_asset`
- `soraswap_n3x_usdc_asset`
- `soraswap_n3x_kusd_asset`
- `soraswap_n3x_asset`
- `soraswap_n3x_vault_account`
- `soraswap_n3x_config_mint_fee_bps`
- `soraswap_n3x_config_redeem_fee_bps`
- `soraswap_n3x_config_target_usdt_bps`
- `soraswap_n3x_config_target_usdc_bps`
- `soraswap_n3x_config_target_kusd_bps`

View tuple fields returned by `fee_reserve_state()`:
- `soraswap_n3x_fee_reserve_usdt`
- `soraswap_n3x_fee_reserve_usdc`
- `soraswap_n3x_fee_reserve_kusd`
- `soraswap_n3x_mint_fees_accrued`
- `soraswap_n3x_redeem_fees_accrued`

Notes:
- The layout is intentionally singleton and deterministic for the first Kotodama port.
- Basket balances are redeemable backing only. Mint fees are credited into per-asset fee reserves instead of basket backing; redeem burns the gross basket share, pays the user net output, and moves the redeem fees into reserves.
- `MintFeesAccrued` tracks aggregate mint-side fees in basket units, and `RedeemFeesAccrued` tracks the sum of per-asset redeem-side fees. `claim_fees(recipient)` is owner-only and transfers only `FeeReserve*` balances, then zeroes those reserves without changing basket backing.
- Target weights are configuration-only in the v1 SoraSwap surface; they are returned for operator readback and smoke assertions, and automatic basket rebalancing is outside the release-eligible contract scope.
- Repo bootstrap targets the current `n3x_hub` contract subject for public `testnet|production` `VaultAccount` and migrates seeded balances forward from previous contract-subject custody after upgrades; `local` still defaults to the isolated `n3x_hub` contract subject unless `SORASWAP_N3X_VAULT_ACCOUNT` overrides it.
- `VaultAccount` can now be repaired in-place through `bind_vault_account(...)` when live custody drifts but basket state remains valid.
- Bootstrap treats nonzero basket or fee counters with `TotalN3x == 0` as a hard accounting mismatch instead of zeroing state through a production entrypoint.
- The public smoke targets, `make smoke-testnet-readonly` and `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet`, read those fields through `/v1/contracts/view` and record both raw view tuples and decoded integer values in the smoke reports.
