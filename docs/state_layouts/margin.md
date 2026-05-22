# Portfolio Margin State Layout

Market state is keyed by `market_id`; account margin state is keyed by caller-provided `account_key`.

Tracked values:
- market owner, risk weight, liquidation threshold
- account collateral, account exposure, computed health, liquidation count
