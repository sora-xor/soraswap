# Farms Interface

Contract: `contracts/farms/farm.ko`

Public entrypoints:
- `hajimari(stake_asset, reward_asset, treasury, reward_rate)`
- `main() -> int`
- `sync_slot() -> quantity`
- `fund_rewards(amount) -> quantity`
- `stake(position, amount)`
- `unstake(position, amount)`
- `claim(position)`
- `farm_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, quantity)`
- `farm_state() -> (int, int, int, decimal)`
- `mirror_position(position) -> (int, quantity, quantity, quantity, quantity, quantity, quantity, quantity)`

Notes:
- Farm config is immutable after `hajimari(...)`.
- Stake positions are caller-owned through `authority()`.
- Emissions now use slot-based accrual with a global reward index, per-position reward debt, and explicit budget exhaustion through `sync_slot(...)`.
