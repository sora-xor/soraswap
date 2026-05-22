# Portfolio Margin Interface

Contract: `contracts/margin/portfolio_margin.ko`

Entrypoints:
- `register_market(market_id, risk_weight_bps, liquidation_threshold_bps)`
- `deposit_collateral(account_key, amount)`
- `withdraw_collateral(account_key, amount)`
- `lock_exposure(market_id, account_key, exposure_delta)`
- `liquidate_account(account_key) -> int`
- `market_state(market_id) -> (int, int, int)`
- `account_health(account_key) -> (int, int, int, int)`

Notes:
- Health is `collateral * 10000 / exposure`; zero exposure is reported as `10000`.
- This is the first v2 shared-margin adapter for perps/options/cover/RWA integration.
