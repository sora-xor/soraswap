# Farms State Layout

Singleton scalar state:
- `FarmInitialized`
- `FarmOwner`
- `StakeAsset`
- `RewardAsset`
- `Treasury`
- `RewardRate`
- `TotalStaked`
- `RewardBudget`
- `RewardDistributed`
- `CurrentSlot`
- `LastAccrualSlot`
- `GlobalRewardIndex`
- `RewardIndexRemainder`

Per-position maps:
- `PositionOwner`
- `StakeOf`
- `Accrued`
- `RewardDebt`
- `PositionClaimed`

View tuple fields returned by `mirror_position()`:
- `soraswap_farm_position_registered`
- `soraswap_farm_stake`
- `soraswap_farm_accrued`
- `soraswap_farm_claimed`
- `soraswap_farm_total_staked`
- `soraswap_farm_reward_budget`
- `soraswap_farm_reward_distributed`
- `soraswap_farm_reward_rate`

View tuple fields returned by `farm_config()`:
- `soraswap_farm_stake_asset`
- `soraswap_farm_reward_asset`
- `soraswap_farm_treasury`
- `soraswap_farm_config_reward_rate`

View tuple fields returned by `farm_state()`:
- `soraswap_farm_current_slot`
- `soraswap_farm_last_accrual_slot`
- `soraswap_farm_global_reward_index`
- `soraswap_farm_reward_index_remainder`

Notes:
- Emissions no longer accrue directly as `stake * reward_rate` at stake time.
- The farm now tracks slot-synced global emissions, per-position reward debt, and remainder carry so funding exhaustion is deterministic across multi-step accrual, claim, and unstake flows.
