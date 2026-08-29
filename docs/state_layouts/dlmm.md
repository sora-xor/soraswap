# DLMM State Layout

Pool scalars:
- initialization and administration: `PoolInitialized`, `PoolOwner`, `AdminRenounced`
- immutable binding: `BaseAsset`, `QuoteAsset`, `VaultAccount`, `LaunchpadExecutorAccount`, `InitializationBin`
- immutable risk configuration: `FeePips`, `BinStep`, `ImpactCapBps`, `MinReserveBase`, `MinReserveQuote`, `MaxBinsPerSwap`, `BinLiquidityCap`
- mutable market cursor: `ActiveBin`
- bounded bin index: `IndexedBinCount`, `FirstIndexedBin`, `LastIndexedBin`
- range governor: `RangeGovernorEnabled`, `RangeGovernorCadenceSlots`, `RangeGovernorNextSlot`, `RangeGovernorMaxFeePips`, `RangeGovernorTargetActiveBin`, `RangeGovernorMaxActiveBinDrift`, `RangeGovernorLastSlot`, `RangeGovernorLastAction`

Pool maps:
- per bin: `BinReserveBase`, `BinReserveQuote`, `BinShareSupply`, `BinFeeGrowthBase`, `BinFeeGrowthQuote`, `PreviousIndexedBin`, `NextIndexedBin`
- per position: `PositionOwner`, `PositionBinId`, `PositionShares`, `PositionFeeDebtBase`, `PositionFeeDebtQuote`, `PositionCreditBase`, `PositionCreditQuote`

The reserved `launchpad_executor` position is created at initialization, owned by `LaunchpadExecutorAccount`, and fixed to `InitializationBin`. Direct liquidity entrypoints cannot claim that name. The Quantity2 launchpad selector can update only that position and accepts calls only from the pinned executor subject.

Router scalars:
- `RouterInitialized`
- `RouterOwner`
- `RouterGuardian`
- `RouterPaused`
- `BaseAsset`
- `QuoteAsset`
- `DefaultFeePips`
- `RouterContractAccount`
- `PoolContract`
- `SwapHistoryHead`

Router history maps:
- `SwapHistoryTrader`
- `SwapHistoryInputIsBase`
- `SwapHistoryAmountIn`
- `SwapHistoryAmountOut`
- `SwapHistoryMinOut`
- `SwapHistorySlot`

`RouterContractAccount` is always `context::seiyaku_subject()` captured by `hajimari(...)`; it is not supplied by the deployer. `PoolContract`, both assets, fee configuration, and guardian are immutable. The pause bit is the only router administration state.

`mirror_state()` returns the pool tuple:
1. initialized
2. active bin
3. fee pips
4. bin step
5. active-bin base reserve
6. active-bin quote reserve
7. active-bin total liquidity
8. active-bin share supply
9. impact cap bps
10. minimum base reserve
11. minimum quote reserve
12. maximum bins per swap
13. per-bin liquidity cap

Router `mirror_state()` returns `(initialized, default_fee_pips, paused)`. `router_config()` returns `(base_asset, quote_asset, default_fee_pips, router_subject, pool_contract, paused)`. Each successful route appends `(trader, direction, amount_in, amount_out, min_out, block_height)` under the next monotonic record ID.

All asset transfers use `DataSpaceId::parse("0")`. Pool and router custody accounts are fixed before the first stateful operation. The first-release deployment rejects mismatched existing state rather than migrating or rebinding it.
