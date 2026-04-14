# Farms Interface

Contract: `contracts/farms/farm.ko`

Public entrypoints:
- `main() -> int`
- `init_farm(stake_asset, reward_asset, treasury, reward_rate)`
- `sync_slot(current_slot) -> int`
- `fund_rewards(amount) -> int`
- `stake(position, amount)`
- `unstake(position, amount)`
- `claim(position)`
- `farm_config() -> (AssetDefinitionId, AssetDefinitionId, AccountId, int)`
- `farm_state() -> (int, int, int, int)`
- `mirror_position(position) -> (int, int, int, int, int, int, int, int)`

Notes:
- Farm config is init-only; `configure_farm` and asset override entrypoints were removed.
- Stake positions are caller-owned through `authority()`.
- Emissions now use slot-based accrual with a global reward index, per-position reward debt, and explicit budget exhaustion through `sync_slot(...)`.
