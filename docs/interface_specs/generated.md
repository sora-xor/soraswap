# Contract Interface Schema

Manifest: `./iroha.contracts.toml`

## n3x.n3x_hub

- Interface: `./artifacts/compiled/n3x/n3x_hub.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `11`
- State keys: `21`

### main

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{}
```
### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "kusd_asset": "xor#universal",
  "mint_fee_bps": "0",
  "n3x_asset": "xor#universal",
  "redeem_fee_bps": "0",
  "target_kusd_bps": "0",
  "target_usdc_bps": "0",
  "target_usdt_bps": "0",
  "usdc_asset": "xor#universal",
  "usdt_asset": "xor#universal",
  "vault_account": "ed0120..."
}
```

### quote_mint

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "kusd_in": "0",
  "usdc_in": "0",
  "usdt_in": "0"
}
```

### quote_redeem

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "n3x_amount": "0"
}
```

### assert_initialized

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{}
```

### hub_config

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### mirror_state

- Kind: `view`
- Return: `(int, quantity, quantity, quantity, quantity, int, int, quantity, quantity, int, int, int)`
- Sample payload:

```json
{}
```

### fee_reserve_state

- Kind: `view`
- Return: `(quantity, quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{}
```

### deposit_and_mint

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "kusd_in": "0",
  "usdc_in": "0",
  "usdt_in": "0"
}
```

### burn_and_redeem

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "n3x_amount": "0"
}
```

### claim_fees

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "recipient": "ed0120..."
}
```

## dlmm.dlmm_pool

- Interface: `./artifacts/compiled/dlmm/dlmm_pool.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `27`
- State keys: `42`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "active_bin": "0",
  "base_asset": "xor#universal",
  "bin_liquidity_cap": "0",
  "bin_step": "0",
  "fee_pips": "0",
  "impact_cap_bps": "0",
  "launchpad_executor": "ed0120...",
  "max_bins_per_swap": "0",
  "min_reserve_base": "0",
  "min_reserve_quote": "0",
  "quote_asset": "xor#universal",
  "vault_account": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### add_position_liquidity

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "base_amount": "0",
  "bin_id": "0",
  "min_shares_out": "0",
  "position_id": "sample",
  "quote_amount": "0"
}
```

### seed_bin

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "base_amount": "0",
  "bin_id": "0",
  "position_id": "sample",
  "quote_amount": "0"
}
```

### seed_launchpad_liquidity

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

### remove_position_liquidity

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "position_id": "sample",
  "shares": "0"
}
```

### collect_position_fees

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "position_id": "sample"
}
```

### swap_exact_in

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "input_asset": "xor#universal",
  "min_out": "0"
}
```

### swap_exact_in_base

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

### swap_exact_in_quote

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

### renounce_admin

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### configure_range_governor

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_active_bin_drift": "0",
  "max_fee_pips": "0",
  "target_active_bin": "0"
}
```

### native_range_governor_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### mirror_state

- Kind: `view`
- Return: `(int, int, int, int, quantity, quantity, quantity, quantity, int, quantity, quantity, int, quantity)`
- Sample payload:

```json
{}
```

### pool_config

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int)`
- Sample payload:

```json
{}
```

### configured_base_asset

- Kind: `view`
- Return: `AssetDefinitionId`
- Sample payload:

```json
{}
```

### configured_quote_asset

- Kind: `view`
- Return: `AssetDefinitionId`
- Sample payload:

```json
{}
```

### configured_vault_account

- Kind: `view`
- Return: `AccountId`
- Sample payload:

```json
{}
```

### launchpad_binding

- Kind: `view`
- Return: `(AccountId, int)`
- Sample payload:

```json
{}
```

### custody_account

- Kind: `view`
- Return: `AccountId`
- Sample payload:

```json
{}
```

### risk_config

- Kind: `view`
- Return: `(int, quantity, quantity, int, quantity)`
- Sample payload:

```json
{}
```

### mirror_bin

- Kind: `view`
- Return: `(quantity, quantity, quantity, decimal, decimal)`
- Sample payload:

```json
{
  "bin_id": "0"
}
```

### mirror_bin_index

- Kind: `view`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "bin_id": "0"
}
```

### mirror_position

- Kind: `view`
- Return: `(int, int, quantity, decimal, decimal, quantity, quantity)`
- Sample payload:

```json
{
  "position_id": "sample"
}
```

### quote_position_fees

- Kind: `view`
- Return: `(quantity, quantity)`
- Sample payload:

```json
{
  "position_id": "sample"
}
```

### range_governor_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### admin_state

- Kind: `view`
- Return: `(AccountId, int)`
- Sample payload:

```json
{}
```

## dlmm.dlmm_router

- Interface: `./artifacts/compiled/dlmm/dlmm_router.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `17`
- State keys: `16`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "default_fee_pips": "0",
  "guardian": "ed0120...",
  "pool_contract": "0x",
  "quote_asset": "xor#universal"
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### set_paused

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "paused": "0"
}
```

### assert_router_config

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{
  "default_fee_pips": "0"
}
```

### router_config

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId, int, AccountId, bytes, int)`
- Sample payload:

```json
{}
```

### router_assets

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId)`
- Sample payload:

```json
{}
```

### mirror_state

- Kind: `view`
- Return: `(int, int, int)`
- Sample payload:

```json
{}
```

### execution_binding

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### contract_binding

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### swap_history_head

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### mirror_swap_history

- Kind: `view`
- Return: `(AccountId, int, quantity, quantity, quantity, int)`
- Sample payload:

```json
{
  "record_id": "0"
}
```

### quote_direct

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "fee_pips": "0",
  "reserve_in": "0",
  "reserve_out": "0"
}
```

### quote_bin

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "bin_id": "0",
  "bin_step": "0",
  "fee_pips": "0",
  "input_is_base": "0",
  "min_reserve_base": "0",
  "min_reserve_quote": "0",
  "reserve_base": "0",
  "reserve_quote": "0"
}
```

### select_best_quote

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "direct_out": "0",
  "via_base_out": "0"
}
```

### route_swap

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "input_is_base": "0",
  "min_out": "0"
}
```

### route_exact_in_base

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

### route_exact_in_quote

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

## batch_amm.epoch_auction

- Interface: `./artifacts/compiled/batch_amm/epoch_auction.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `13`
- State keys: `39`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "custody_account": "ed0120...",
  "guardian": "ed0120...",
  "quote_asset": "xor#universal"
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### enter_paused

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_paused

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### configure_epoch

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "end_slot": "0",
  "epoch_id": "0",
  "lower_tick": "0",
  "max_orders": "0",
  "start_slot": "0",
  "tick_step": "0",
  "upper_tick": "0"
}
```

### submit_order

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "limit_tick": "0",
  "order_id": "sample",
  "side": "0"
}
```

### cancel_order

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### close_epoch

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### native_epoch_auction_close

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### settle_order

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### epoch_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int, int, quantity, int)`
- Sample payload:

```json
{}
```

### auction_config

- Kind: `view`
- Return: `(int, int, int)`
- Sample payload:

```json
{}
```

### order_state

- Kind: `view`
- Return: `(int, int, int, quantity, int, int, quantity, quantity, quantity)`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

## launchpad.liquidity_executor

- Interface: `./artifacts/compiled/launchpad/liquidity_executor.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `7`
- State keys: `14`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "guardian": "ed0120...",
  "pool_contract": "0x",
  "quote_asset": "xor#universal",
  "sale_factory_account": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### set_paused

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "paused": "0"
}
```

### executor_config

- Kind: `view`
- Return: `(bytes, AssetDefinitionId, AssetDefinitionId, AccountId, AccountId, AccountId, AccountId, int)`
- Sample payload:

```json
{}
```

### seed_count

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### liquidity_state

- Kind: `view`
- Return: `(int, quantity, quantity, quantity, int)`
- Sample payload:

```json
{}
```

### seed_liquidity

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount_in": "0",
  "min_out": "0"
}
```

## launchpad.sale_factory

- Interface: `./artifacts/compiled/launchpad/sale_factory.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `23`
- State keys: `45`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "executor_contract": "0x",
  "guardian": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### enter_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### configure_trigger_lifecycle

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_items_per_tick": "0"
}
```

### init_sale

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "claim_end_slot": "0",
  "claim_start_slot": "0",
  "hard_cap": "0",
  "payment_asset": "xor#universal",
  "sale": "sample",
  "sale_asset": "xor#universal",
  "soft_cap": "0",
  "treasury": "ed0120...",
  "unit_price": "0"
}
```

### contribute_recorded

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "allocation": "sample",
  "payment_amount": "0",
  "sale": "sample"
}
```

### close_sale

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### deposit_seed_inventory

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount": "0",
  "sale": "sample"
}
```

### deposit_claim_inventory

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount": "0",
  "sale": "sample"
}
```

### configure_seed_liquidity

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "payment_amount": "0",
  "sale": "sample",
  "sale_amount": "0"
}
```

### seed_liquidity

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### finalize_sale_activation

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "claim_inventory_amount": "0",
  "sale": "sample"
}
```

### claim_allocation

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "allocation": "sample"
}
```

### refund_allocation

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "allocation": "sample"
}
```

### native_lifecycle_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### sale_config

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, decimal, quantity, quantity, int, int)`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### mirror_sale

- Kind: `view`
- Return: `(int, quantity, quantity, int, int, int, quantity, quantity, quantity, quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### mirror_sale_accounting

- Kind: `view`
- Return: `(quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### mirror_allocation

- Kind: `view`
- Return: `(int, quantity, quantity, quantity, int)`
- Sample payload:

```json
{
  "allocation": "sample"
}
```

### factory_config

- Kind: `view`
- Return: `(AccountId, AccountId, AccountId, bytes, int)`
- Sample payload:

```json
{}
```

### activation_state

- Kind: `view`
- Return: `(int, quantity)`
- Sample payload:

```json
{
  "sale": "sample"
}
```

### trigger_lifecycle_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## referral.registry

- Interface: `./artifacts/compiled/referral/registry.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `8`
- State keys: `11`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "claim_threshold": "0",
  "direct_share_bps": "0",
  "parent_share_bps": "0",
  "reward_asset": "xor#universal",
  "treasury": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### bind_member

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "member": "sample"
}
```

### bind_member_with_parent

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "member": "sample",
  "parent_member": "sample"
}
```

### accrue

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "member": "sample"
}
```

### claim

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "member": "sample"
}
```

### registry_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, quantity, int, int)`
- Sample payload:

```json
{}
```

### mirror_member

- Kind: `view`
- Return: `(int, quantity, int, int, quantity, quantity, quantity, int, int, quantity, quantity, quantity, int)`
- Sample payload:

```json
{
  "member": "sample"
}
```

## automation.job_queue

- Interface: `./artifacts/compiled/automation/job_queue.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `14`
- State keys: `11`

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### enqueue

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample",
  "payload_hash": "0"
}
```

### assign_executor

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "executor": "ed0120...",
  "job": "sample"
}
```

### configure_job

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample",
  "max_retries": "0",
  "next_slot": "0",
  "retry_delay_slots": "0"
}
```

### configure_cron

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "interval_slots": "0",
  "job": "sample"
}
```

### mark_running

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### dispatch_job

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### mark_done

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### complete_run

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### retry

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### pause_job

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### resume_job

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### cancel_job

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "job": "sample"
}
```

### mirror_job

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "job": "sample"
}
```

## farms.farm

- Interface: `./artifacts/compiled/farms/farm.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `10`
- State keys: `16`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "reward_asset": "xor#universal",
  "reward_rate": "0",
  "stake_asset": "xor#universal",
  "treasury": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### sync_slot

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{}
```

### fund_rewards

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "amount": "0"
}
```

### stake

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "position": "sample"
}
```

### unstake

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "position": "sample"
}
```

### claim

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "position": "sample"
}
```

### farm_config

- Kind: `view`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, quantity)`
- Sample payload:

```json
{}
```

### farm_state

- Kind: `view`
- Return: `(int, int, int, decimal)`
- Sample payload:

```json
{}
```

### mirror_position

- Kind: `view`
- Return: `(int, quantity, quantity, quantity, quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{
  "position": "sample"
}
```

## perps.perps_engine

- Interface: `./artifacts/compiled/perps/perps_engine.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `31`
- State keys: `67`

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "collateral_asset": "xor#universal",
  "custody_account": "ed0120...",
  "oracle_account": "ed0120..."
}
```

### sync_automation

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": "0",
  "cadence_slots": "0",
  "executor": "ed0120...",
  "funding_job_id": "0",
  "liquidation_job_id": "0",
  "safe_mode": "0"
}
```

### configure_trigger_lifecycle

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_items_per_tick": "0"
}
```

### native_lifecycle_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### engine_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### collateral_pool_state

- Kind: `view`
- Return: `(AccountId, int, int, int)`
- Sample payload:

```json
{}
```

### market_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": "0"
}
```

### market_oracle_state

- Kind: `view`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": "0"
}
```

### position_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### liquidation_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": "0"
}
```

### trigger_lifecycle_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### position_liquidation_state

- Kind: `view`
- Return: `(int, int, int)`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### risk_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": "0"
}
```

### automation_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### fund_collateral_pool

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "amount": "0"
}
```

### publish_market_oracle

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "attestation_hash": "0",
  "confidence_bps": "0",
  "index_price_bps": "0",
  "mark_price_bps": "0",
  "market_id": "0",
  "oracle_slot": "0",
  "status_flags": "0"
}
```

### withdraw_collateral_surplus

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "amount": "0",
  "recipient": "ed0120..."
}
```

### configure_oracle_account

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "oracle_account": "ed0120..."
}
```

### enter_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### open_position

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "margin": "0",
  "market_id": "0",
  "requested_leverage_bps": "0",
  "size": "0"
}
```

### add_margin

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "amount": "0",
  "position_id": "0"
}
```

### remove_margin

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "amount": "0",
  "position_id": "0"
}
```

### sync_funding

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "market_id": "0"
}
```

### run_liquidation_pass

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "market_id": "0",
  "max_positions": "0"
}
```

### close_position

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### register_market

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "asset": "xor#universal",
  "backlog_limit": "0",
  "funding_bps": "0",
  "funding_interval_slots": "0",
  "liquidation_fee_bps": "0",
  "liquidation_stress_limit": "0",
  "maintenance_margin_bps": "0",
  "max_leverage_bps": "0",
  "open_interest_cap": "0",
  "oracle_stale_slots": "0",
  "utilisation_clamp_bps": "0"
}
```

### update_market

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "active": "0",
  "backlog_limit": "0",
  "funding_bps": "0",
  "funding_interval_slots": "0",
  "guard_flags": "0",
  "liquidation_fee_bps": "0",
  "liquidation_stress_limit": "0",
  "maintenance_margin_bps": "0",
  "market_id": "0",
  "max_leverage_bps": "0",
  "open_interest_cap": "0",
  "oracle_stale_slots": "0",
  "utilisation_clamp_bps": "0"
}
```

### heartbeat

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": "0",
  "market_id": "0",
  "safe_mode": "0"
}
```

### modify_position

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "margin_delta": "0",
  "position_id": "0",
  "requested_leverage_bps": "0",
  "size_delta": "0"
}
```

## options.factory

- Interface: `./artifacts/compiled/options/factory.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `29`
- State keys: `60`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "factory_account": "ed0120...",
  "guardian": "ed0120...",
  "oracle_authority": "ed0120...",
  "settlement_asset": "xor#universal",
  "stale_slots": "0"
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### enter_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### configure_oracle_authority

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "oracle_authority": "ed0120..."
}
```

### configure_oracle_stale_slots

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "stale_slots": "0"
}
```

### withdraw_surplus

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "recipient": "ed0120..."
}
```

### sync_automation

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": "0",
  "cadence_slots": "0",
  "executor": "ed0120...",
  "job_id": "0",
  "safe_mode": "0"
}
```

### heartbeat

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": "0",
  "safe_mode": "0"
}
```

### configure_trigger_lifecycle

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_items_per_tick": "0"
}
```

### sync_series

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "collateral_multiplier_bps": "0",
  "expiry_slot": "0",
  "max_notional": "0",
  "option_kind": "0",
  "premium_bps": "0",
  "series_id": "0",
  "strike_bps": "0"
}
```

### configure_utilisation_guard

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "bump_activate_bps": "0",
  "bump_deactivate_bps": "0",
  "bump_percent_bps": "0",
  "pause_threshold_bps": "0",
  "series_id": "0"
}
```

### buy_shout

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "notional": "0",
  "series_id": "0"
}
```

### buy_outperformance

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "notional": "0",
  "series_id": "0"
}
```

### settle_outperformance_series

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "attestation_hash": "0",
  "base_return_bps": "0",
  "final_mark": "0",
  "final_quote_mark": "0",
  "oracle_slot": "0",
  "quote_return_bps": "0",
  "series_id": "0"
}
```

### publish_shout_mark

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "attestation_hash": "0",
  "mark_price_bps": "0",
  "oracle_slot": "0",
  "position_id": "0"
}
```

### exercise_shout_position

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### exercise_outperformance_position

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### native_lifecycle_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### factory_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### oracle_stale_slots

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### treasury_state

- Kind: `view`
- Return: `(quantity, quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{}
```

### series_state

- Kind: `view`
- Return: `(int, int, quantity, int, int, quantity, int, int, int, int)`
- Sample payload:

```json
{
  "series_id": "0"
}
```

### series_terms

- Kind: `view`
- Return: `(int, int)`
- Sample payload:

```json
{
  "series_id": "0"
}
```

### position_state

- Kind: `view`
- Return: `(int, int, int, quantity, quantity, quantity, int, quantity, int)`
- Sample payload:

```json
{
  "position_id": "0"
}
```

### series_settlement

- Kind: `view`
- Return: `(decimal, decimal, int, int, int)`
- Sample payload:

```json
{
  "series_id": "0"
}
```

### series_returns

- Kind: `view`
- Return: `(int, int)`
- Sample payload:

```json
{
  "series_id": "0"
}
```

### automation_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### trigger_lifecycle_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## cover.policy_manager

- Interface: `./artifacts/compiled/cover/policy_manager.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `23`
- State keys: `43`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "cover_account": "ed0120...",
  "default_required_observations": "0",
  "guardian": "ed0120...",
  "oracle_authority": "ed0120...",
  "oracle_stale_slots": "0",
  "settlement_asset": "xor#universal"
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### enter_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### configure_oracle_authority

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "oracle_authority": "ed0120..."
}
```

### configure_oracle_stale_slots

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "stale_slots": "0"
}
```

### sync_automation

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": "0",
  "cadence_slots": "0",
  "executor": "ed0120...",
  "job_id": "0",
  "safe_mode": "0"
}
```

### heartbeat

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": "0",
  "safe_mode": "0"
}
```

### configure_trigger_lifecycle

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_items_per_tick": "0"
}
```

### fund_reserve

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0"
}
```

### withdraw_surplus

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "recipient": "ed0120..."
}
```

### register_policy

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "covered_notional": "0",
  "lower_bound": "0",
  "monitoring_window_slots": "0",
  "payout_amount": "0",
  "premium_paid": "0",
  "required_observations": "0",
  "upper_bound": "0"
}
```

### record_observation

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "attestation_hash": "0",
  "observed_price": "0",
  "oracle_slot": "0",
  "policy_id": "0",
  "status_flags": "0"
}
```

### route_claim

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "policy_id": "0"
}
```

### expire_policy

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "policy_id": "0"
}
```

### native_lifecycle_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### manager_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, AccountId, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### reserve_state

- Kind: `view`
- Return: `(quantity, quantity, quantity, quantity, quantity)`
- Sample payload:

```json
{}
```

### policy_state

- Kind: `view`
- Return: `(int, decimal, decimal, quantity, int, int, quantity, quantity, int, int, int, quantity)`
- Sample payload:

```json
{
  "policy_id": "0"
}
```

### policy_observation

- Kind: `view`
- Return: `(decimal, int, int, int)`
- Sample payload:

```json
{
  "policy_id": "0"
}
```

### next_policy_id

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### automation_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### trigger_lifecycle_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## bridge.sccp_bridge

- Interface: `./artifacts/compiled/bridge/sccp_bridge.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `25`
- State keys: `30`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "guardian": "ed0120...",
  "listing_fee_amount": "0",
  "listing_fee_asset": "xor#universal",
  "proof_authority": "ed0120...",
  "treasury": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### set_proof_authority

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "proof_authority": "ed0120..."
}
```

### set_registry_enabled

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "enabled": "0"
}
```

### register_bridge_asset

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "asset": "xor#universal",
  "asset_key": "sample",
  "decimals": "0",
  "home_domain": "0"
}
```

### bind_asset_vault

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "sample",
  "vault_account": "ed0120..."
}
```

### activate_route

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "sample",
  "remote_domain": "0",
  "route": "sample"
}
```

### activate_route_governed

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "sample",
  "message_id": "sample",
  "remote_domain": "0",
  "route": "sample"
}
```

### pause_route

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "route": "sample"
}
```

### emergency_pause_route

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "route": "sample"
}
```

### resume_route

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "route": "sample"
}
```

### lock_to_remote

- Kind: `kotoage`
- Return: `int`
- Sample payload:

```json
{
  "amount": "0",
  "recipient": "sample",
  "route": "sample",
  "transfer": "sample"
}
```

### finalize_inbound

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "message_id": "sample",
  "recipient": "ed0120...",
  "route": "sample"
}
```

### listing_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, quantity, int)`
- Sample payload:

```json
{}
```

### bridge_authorities

- Kind: `view`
- Return: `(AccountId, AccountId, AccountId)`
- Sample payload:

```json
{}
```

### mirror_asset

- Kind: `view`
- Return: `(int, int, int, quantity)`
- Sample payload:

```json
{
  "asset_key": "sample"
}
```

### asset_config

- Kind: `view`
- Return: `(AssetDefinitionId, AccountId, int, int)`
- Sample payload:

```json
{
  "asset_key": "sample"
}
```

### asset_vault_bound

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{
  "asset_key": "sample"
}
```

### asset_vault_account

- Kind: `view`
- Return: `AccountId`
- Sample payload:

```json
{
  "asset_key": "sample"
}
```

### mirror_route

- Kind: `view`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "route": "sample"
}
```

### route_config

- Kind: `view`
- Return: `(Name, int, AssetDefinitionId, AccountId)`
- Sample payload:

```json
{
  "route": "sample"
}
```

### route_provenance

- Kind: `view`
- Return: `(int, Name)`
- Sample payload:

```json
{
  "route": "sample"
}
```

### mirror_outbound

- Kind: `view`
- Return: `(int, quantity, int, int)`
- Sample payload:

```json
{
  "transfer": "sample"
}
```

### outbound_config

- Kind: `view`
- Return: `(Name, AccountId, Name, quantity)`
- Sample payload:

```json
{
  "transfer": "sample"
}
```

### inbound_consumed

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{
  "message_id": "sample"
}
```

## intents.settlement_router

- Interface: `./artifacts/compiled/intents/settlement_router.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `6`
- State keys: `15`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "custody_account": "ed0120...",
  "fee_account": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### open_intent

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": "0",
  "deadline_slot": "0",
  "input_asset": "xor#universal",
  "intent_id": "sample",
  "min_out": "0",
  "nonce": "0",
  "output_asset": "xor#universal",
  "solver_fee_bps": "0"
}
```

### cancel_intent

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "intent_id": "sample"
}
```

### fill_intent

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount_out": "0",
  "intent_id": "sample"
}
```

### intent_state

- Kind: `view`
- Return: `(int, int, quantity, quantity, int, int, int, int, quantity, quantity)`
- Sample payload:

```json
{
  "intent_id": "sample"
}
```

## vaults.manager

- Interface: `./artifacts/compiled/vaults/manager.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `12`
- State keys: `25`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### configure_trigger_lifecycle

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_items_per_tick": "0"
}
```

### register_vault

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "async_redeem": "0",
  "custody_account": "ed0120...",
  "share_asset": "xor#universal",
  "strategy_code": "0",
  "underlying_asset": "xor#universal",
  "vault_id": "sample"
}
```

### deposit

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "position_id": "sample",
  "vault_id": "sample"
}
```

### request_redeem

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "claim_slot": "0",
  "position_id": "sample",
  "request_id": "sample",
  "shares": "0",
  "vault_id": "sample"
}
```

### claim_redeem

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "request_id": "sample"
}
```

### native_lifecycle_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### vault_state

- Kind: `view`
- Return: `(int, int, int, quantity, quantity)`
- Sample payload:

```json
{
  "vault_id": "sample"
}
```

### position_state

- Kind: `view`
- Return: `quantity`
- Sample payload:

```json
{
  "position_id": "sample"
}
```

### request_state

- Kind: `view`
- Return: `(int, quantity, int)`
- Sample payload:

```json
{
  "request_id": "sample"
}
```

### trigger_lifecycle_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## operators.registry

- Interface: `./artifacts/compiled/operators/registry.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `7`
- State keys: `11`

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### register_operator

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "bond_asset": "xor#universal",
  "bond_vault": "ed0120...",
  "fee_asset": "xor#universal",
  "fee_vault": "ed0120...",
  "min_bond": "0",
  "operator_owner": "ed0120...",
  "service": "sample"
}
```

### bond

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "service": "sample"
}
```

### heartbeat

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "health_bps": "0",
  "service": "sample",
  "slot": "0"
}
```

### accrue_fees

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "service": "sample"
}
```

### claim_fees

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "service": "sample"
}
```

### operator_state

- Kind: `view`
- Return: `(int, quantity, quantity, decimal, int, quantity, int)`
- Sample payload:

```json
{
  "service": "sample"
}
```

## margin.portfolio_margin

- Interface: `./artifacts/compiled/margin/portfolio_margin.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `9`
- State keys: `11`

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### register_market

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "collateral_asset": "xor#universal",
  "collateral_vault": "ed0120...",
  "liquidation_threshold_bps": "0",
  "market_id": "sample",
  "risk_weight_bps": "0"
}
```

### deposit_collateral

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "sample",
  "amount": "0",
  "market_id": "sample"
}
```

### withdraw_collateral

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "sample",
  "amount": "0"
}
```

### lock_exposure

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "sample",
  "exposure_delta": "0",
  "market_id": "sample"
}
```

### release_exposure

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "sample",
  "exposure_delta": "0",
  "market_id": "sample"
}
```

### liquidate_account

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "account_key": "sample"
}
```

### market_state

- Kind: `view`
- Return: `(int, decimal, decimal)`
- Sample payload:

```json
{
  "market_id": "sample"
}
```

### account_health

- Kind: `view`
- Return: `(int, quantity, quantity, decimal, int)`
- Sample payload:

```json
{
  "account_key": "sample"
}
```

## rwa.market

- Interface: `./artifacts/compiled/rwa/market.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `8`
- State keys: `12`

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### issue_lot

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "initial_nav_per_share": "0",
  "market_id": "sample",
  "nav_asset": "xor#universal",
  "share_asset": "xor#universal",
  "total_shares": "0"
}
```

### report_nav

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "market_id": "sample",
  "nav_per_share": "0",
  "status": "0",
  "total_shares": "0"
}
```

### request_redemption

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "market_id": "sample",
  "redemption_id": "sample",
  "shares": "0"
}
```

### settle_redemption

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "redemption_id": "sample"
}
```

### cancel_redemption

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "redemption_id": "sample"
}
```

### rwa_market_state

- Kind: `view`
- Return: `(int, decimal, quantity, int)`
- Sample payload:

```json
{
  "market_id": "sample"
}
```

### redemption_state

- Kind: `view`
- Return: `(int, quantity, quantity, int)`
- Sample payload:

```json
{
  "redemption_id": "sample"
}
```

## dlmm_hooks.hook_manager

- Interface: `./artifacts/compiled/dlmm_hooks/hook_manager.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `16`
- State keys: `39`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "custody_account": "ed0120...",
  "guardian": "ed0120...",
  "quote_asset": "xor#universal",
  "router_contract": "0x"
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### configure_hook_policy

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "enabled": "0",
  "hook_id": "sample",
  "max_fee_pips": "0",
  "phase": "0"
}
```

### configure_trigger_twamm

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "cadence_slots": "0",
  "enabled": "0",
  "max_orders_per_tick": "0"
}
```

### enter_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### place_limit_order

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": "0",
  "hook_id": "sample",
  "min_out": "0",
  "order_id": "sample"
}
```

### record_execution

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": "0",
  "amount_out": "0",
  "order_id": "sample"
}
```

### schedule_twamm

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "input_is_base": "0",
  "interval_slots": "0",
  "min_total_out": "0",
  "order_id": "sample",
  "slice_in": "0",
  "start_slot": "0",
  "total_in": "0"
}
```

### cancel_twamm

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### claim_twamm

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### native_twamm_tick

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{}
```

### hook_policy

- Kind: `view`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "hook_id": "sample"
}
```

### quote_hooked_swap

- Kind: `view`
- Return: `(quantity, quantity, quantity, quantity, int)`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### twamm_order_state

- Kind: `view`
- Return: `(int, quantity, quantity, quantity, quantity, quantity, int, int, int)`
- Sample payload:

```json
{
  "order_id": "sample"
}
```

### twamm_trigger_state

- Kind: `view`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## escrow.conditional_escrow

- Interface: `./artifacts/compiled/escrow/conditional_escrow.interface.json`
- `kotoage`/`言挙げ`, `view`, `hajimari`/`始まり`, `kaizen`/`改善`: `9`
- State keys: `10`

### hajimari

- Kind: `hajimari`
- Return: `null`
- Sample payload:

```json
{
  "escrow_account": "ed0120..."
}
```

### main

- Kind: `view`
- Return: `int`
- Sample payload:

```json
{}
```

### open_escrow

- Kind: `kotoage`
- Return: `null`
- Sample payload:

```json
{
  "amount": "0",
  "asset": "xor#universal",
  "condition_code": "0",
  "escrow_id": "sample",
  "expiry_slot": "0",
  "taker": "ed0120..."
}
```

### accept_escrow

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "condition_code": "0",
  "escrow_id": "sample"
}
```

### native_by_call_settle

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{}
```

### cancel_escrow

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "escrow_id": "sample"
}
```

### refund_expired

- Kind: `kotoage`
- Return: `quantity`
- Sample payload:

```json
{
  "escrow_id": "sample"
}
```

### escrow_state

- Kind: `view`
- Return: `(int, quantity, int, int, int, int)`
- Sample payload:

```json
{
  "escrow_id": "sample"
}
```

### escrow_config

- Kind: `view`
- Return: `AccountId`
- Sample payload:

```json
{}
```
