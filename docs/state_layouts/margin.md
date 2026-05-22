# Portfolio Margin State Layout

Market state is keyed by `market_id`; account margin state is keyed by caller-provided `account_key`.

Tracked values:
- market owner, risk weight, liquidation threshold
- account owner, collateral, exposure, computed health, liquidation count

Account keys are caller-bound on first collateral deposit. Exposure changes are accepted from the account owner or the registered owner of the market that is locking exposure.
