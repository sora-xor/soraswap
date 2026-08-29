# Portfolio Margin Interface

Contract: `contracts/margin/portfolio_margin.ko`

Entrypoints:
- `main() -> int`
- `register_market(market_id, collateral_asset, collateral_vault, risk_weight_bps, liquidation_threshold_bps)`
- `deposit_collateral(market_id, account_key, amount)`
- `withdraw_collateral(account_key, amount)`
- `lock_exposure(market_id, account_key, exposure_delta)`
- `release_exposure(market_id, account_key, exposure_delta)`
- `liquidate_account(account_key) -> quantity`
- `market_state(market_id) -> (int, decimal, decimal)`
- `account_health(account_key) -> (int, quantity, quantity, decimal, int)`

Notes:
- Health is represented as a decimal ratio; zero exposure is reported as the contract's fully healthy sentinel.
- Margin account keys are bound to the first depositor; exposure changes require that account owner or the registered market owner.
- This is the first-release shared-margin adapter for perps/options/cover/RWA integration.
