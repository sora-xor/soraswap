# Options State Layout

Per-series maps:
- `UnderlyingAsset`
- `SettlementAsset`
- `Treasury`
- `StrikePrice`
- `Premium`
- `SeriesExpirySlot`
- `SeriesActive`
- `TicketsIssued`
- `TicketsExercised`
- `TicketsVoided`
- `SeriesCollateralInventory`
- `SeriesCollateralReserved`
- `SeriesCollateralPaid`

Per-ticket maps:
- `TicketSeries`
- `TicketOwner`
- `TicketActive`
- `TicketPremiumPaid`
- `TicketContracts`
- `TicketCollateralReserved`
- `TicketPayoutPaid`

View tuple fields returned by `mirror_series()` and `mirror_ticket()`:
- `soraswap_options_strike_price`
- `soraswap_options_premium`
- `soraswap_options_expiry_slot`
- `soraswap_options_series_active`
- `soraswap_options_tickets_issued`
- `soraswap_options_tickets_exercised`
- `soraswap_options_tickets_voided`
- `soraswap_options_series_collateral_inventory`
- `soraswap_options_series_collateral_reserved`
- `soraswap_options_series_collateral_paid`
- `soraswap_options_ticket_registered`
- `soraswap_options_ticket_active`
- `soraswap_options_ticket_premium_paid`
- `soraswap_options_ticket_contracts`
- `soraswap_options_ticket_collateral_reserved`
- `soraswap_options_ticket_payout_paid`

View tuple fields returned by `series_config()`:
- `soraswap_options_underlying_asset`
- `soraswap_options_settlement_asset`
- `soraswap_options_treasury`
- `soraswap_options_config_strike_price`
- `soraswap_options_config_premium`
- `soraswap_options_config_expiry_slot`
- `soraswap_options_config_series_active`
