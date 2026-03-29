# Farms State Layout

Farm-slot maps:
- `StakeAsset`
- `RewardAsset`
- `Treasury`
- `RewardRate`
- `TotalStaked`
- `RewardBudget`
- `RewardDistributed`

Per-position maps:
- `PositionOwner`
- `StakeOf`
- `Accrued`
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
