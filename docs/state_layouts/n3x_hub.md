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

Notes:
- The layout is intentionally singleton and deterministic for the first Kotodama port.
- Basket balances retain accrued redeem fees because only the net redeem output is transferred out.
- `MintFeesAccrued` tracks aggregate mint-side fees in basket units, and `RedeemFeesAccrued` tracks the sum of per-asset redeem-side fees.
- Target weights are configuration-only in this repo slice; they are returned for operator readback and smoke assertions, not yet enforced by a rebalancer.
- Repo bootstrap targets the current `n3x_hub` contract subject for public `testnet|production` `VaultAccount` and migrates seeded balances forward from previous contract-subject custody after upgrades; `local` still defaults to the isolated `n3x_hub` contract subject unless `SORASWAP_N3X_VAULT_ACCOUNT` overrides it.
- `VaultAccount` can now be repaired in-place through `bind_vault_account(...)` when live custody drifts but basket state remains valid.
- `repair_zero_supply_state(...)` is a stricter owner-gated repair path that rebinds custody and zeroes basket/fee counters when `TotalN3x == 0`.
- `scripts/smoke_testnet.sh` reads those fields through `/v1/contracts/view` and records both raw view tuples and decoded integer values in the smoke report.
