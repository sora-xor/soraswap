# RWA Market Interface

Contract: `contracts/rwa/market.ko`

Entrypoints:
- `issue_lot(market_id, share_asset, nav_asset, initial_nav_per_share, total_shares)`
- `bind_share_asset(market_id, share_asset)`
- `report_nav(market_id, nav_per_share, total_shares, status)`
- `request_redemption(market_id, redemption_id, shares)`
- `settle_redemption(redemption_id)`
- `rwa_market_state(market_id) -> (int, int, int, int)`

Notes:
- Status values are controller-defined; `1` is the active launch default.
- Native Iroha RWA lot ISIs remain the source of provenance and compliance control.
