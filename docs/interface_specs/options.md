# Options Interface

Contract: `contracts/options/series_manager.ko`

Public entrypoints:
- `main() -> int`
- `init_series(series, underlying_asset, settlement_asset, treasury, strike_price, premium)`
- `configure_series(series, strike_price, premium, expiry_slot, active)`
- `buy_option(buyer, series, ticket)`
- `buy_option_with_assets(buyer, series, ticket, treasury, settlement_asset, premium)`
- `exercise(buyer, ticket, payout)`
- `exercise_with_assets(buyer, ticket, treasury, settlement_asset, payout)`
- `expire_series(series, current_slot)`
- `void_expired_ticket(ticket)`
- `series_config(series) -> (AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int)`
- `mirror_series(series) -> (int, int, int, int, int, int, int, int, int, int)`
- `mirror_ticket(ticket) -> (int, int, int, int, int, int)`

Notes:
- Series now track an explicit active flag and expiry slot, and tickets record owner plus premium paid.
- The simplified lifecycle is buy -> exercise before expiry, or buy -> series expiry -> `void_expired_ticket`.
- `series_config`, `mirror_series`, and `mirror_ticket` are `view fn` entrypoints consumed through `/v1/contracts/view`.
