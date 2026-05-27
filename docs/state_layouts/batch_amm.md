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
