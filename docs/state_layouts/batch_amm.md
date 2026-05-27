# Batch AMM State Layout

Epoch auction singleton state:
- `AuctionInitialized`
- `AuctionOwner`
- `AuctionContractId`
- `AuctionContractBound`
- `AuctionBaseAsset`
- `AuctionQuoteAsset`
- `EpochId`
- `EpochStartSlot`
- `EpochEndSlot`
- `EpochLowerTick`
- `EpochUpperTick`
- `EpochTickStep`
- `EpochMaxOrders`
- `EpochStatus`
- `EpochOrderCount`
- `EpochClearingTick`
- `EpochClearingBase`
- `EpochBidBaseAtClearing`
- `EpochAskBaseAtClearing`
- `EpochLastCloseSlot`
- `EpochStatusById`
- `EpochClearingTickById`
- `EpochClearingBaseById`
- `EpochBidBaseAtClearingById`
- `EpochAskBaseAtClearingById`
- `NextOrderIndex`

Order maps:
- `OrderByIndex`
- `OrderOwner`
- `OrderEpoch`
- `OrderSide`
- `OrderAmount`
- `OrderLimitTick`
- `OrderStatus`
- `OrderBaseOut`
- `OrderQuoteOut`
- `OrderBaseRefund`
- `OrderQuoteRefund`

Status values:
- Epoch `0=unset`, `1=active`, `2=closed`
- Order `1=active`, `2=cancelled`, `3=settled`

Closed epoch snapshots are keyed by epoch id so user-driven settlement and cancellation decisions use the epoch recorded on each order, not only the current singleton epoch.
