# Farms Interface

Contract: `contracts/farms/farm.ko`

Public entrypoints:
- `main() -> int`
- `init_farm(stake_asset, reward_asset, treasury, reward_rate)`
- `configure_farm(reward_rate)`
- `fund_rewards(funder, amount) -> int`
- `fund_rewards_with_assets(funder, treasury, reward_asset, amount) -> int`
- `stake(staker, position, amount)`
- `stake_with_assets(staker, position, treasury, stake_asset, amount)`
- `unstake(staker, position, amount)`
- `unstake_with_assets(staker, position, treasury, stake_asset, amount)`
- `claim(staker, position)`
- `claim_with_assets(staker, position, treasury, reward_asset)`
- `farm_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, int)`
- `mirror_position(position) -> (int, int, int, int, int, int, int, int)`

Notes:
- Reward claims now depend on an explicit reward budget funded into the farm treasury instead of assuming infinite treasury-side inventory.
- LP/farm ownership is tracked by `position`, and stake/claim/unstake all enforce the recorded `PositionOwner`.
- `farm_config` and `mirror_position` are `view fn` entrypoints consumed through `/v1/contracts/view`.
