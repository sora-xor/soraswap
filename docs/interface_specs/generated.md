# Contract Interface Schema

Manifest: `iroha.contracts.toml`

## n3x.n3x_hub

- Interface: `artifacts/compiled/n3x/n3x_hub.interface.json`
- Entrypoints: `13`
- State keys: `21`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_hub

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "kusd_asset": "xor#universal",
  "mint_fee_bps": 0,
  "n3x_asset": "xor#universal",
  "redeem_fee_bps": 0,
  "target_kusd_bps": 0,
  "target_usdc_bps": 0,
  "target_usdt_bps": 0,
  "usdc_asset": "xor#universal",
  "usdt_asset": "xor#universal",
  "vault_account": "ed0120..."
}
```

### quote_mint

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "kusd_in": 0,
  "usdc_in": 0,
  "usdt_in": 0
}
```

### quote_redeem

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "n3x_amount": 0
}
```

### assert_initialized

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{}
```

### hub_config

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### bind_vault_account

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "vault_account": "ed0120..."
}
```

### repair_zero_supply_state

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "vault_account": "ed0120..."
}
```

### mirror_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### fee_reserve_state

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{}
```

### deposit_and_mint

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "kusd_in": 0,
  "usdc_in": 0,
  "usdt_in": 0
}
```

### burn_and_redeem

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "n3x_amount": 0
}
```

### claim_fees

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "recipient": "ed0120..."
}
```

## dlmm.dlmm_pool

- Interface: `artifacts/compiled/dlmm/dlmm_pool.interface.json`
- Entrypoints: `22`
- State keys: `24`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### warm_write

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### init_pool

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "active_bin": 0,
  "base_asset": "xor#universal",
  "bin_liquidity_cap": 0,
  "bin_step": 0,
  "fee_pips": 0,
  "impact_cap_bps": 0,
  "max_bins_per_swap": 0,
  "min_reserve_base": 0,
  "min_reserve_quote": 0,
  "quote_asset": "xor#universal",
  "vault_account": "ed0120..."
}
```

### seed_bin

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "base_amount": 0,
  "bin_id": 0,
  "quote_amount": 0
}
```

### seed_bin_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "base_amount": 0,
  "bin_id": 0,
  "quote_amount": 0
}
```

### add_position_liquidity

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "base_amount": 0,
  "bin_id": 0,
  "min_shares_out": 0,
  "position_id": "name",
  "quote_amount": 0
}
```

### remove_position_liquidity

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "position_id": "name",
  "shares": 0
}
```

### collect_position_fees

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "position_id": "name"
}
```

### mirror_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### pool_config

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int)`
- Sample payload:

```json
{}
```

### bind_custody_account

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "vault_account": "ed0120..."
}
```

### repair_active_bin

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "active_bin": 0
}
```

### custody_account

- Kind: `View`
- Return: `AccountId`
- Sample payload:

```json
{}
```

### risk_config

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{}
```

### mirror_bin

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "bin_id": 0
}
```

### mirror_position

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": "name"
}
```

### quote_position_fees

- Kind: `View`
- Return: `(int, int)`
- Sample payload:

```json
{
  "position_id": "name"
}
```

### swap_exact_in

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "input_asset": "xor#universal",
  "min_out": 0
}
```

### swap_exact_in_base

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "min_out": 0
}
```

### swap_exact_in_quote

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "min_out": 0
}
```

### swap_exact_in_base_for

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "min_out": 0,
  "recipient": "ed0120..."
}
```

### swap_exact_in_quote_for

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "min_out": 0,
  "recipient": "ed0120..."
}
```

## dlmm.dlmm_router

- Interface: `artifacts/compiled/dlmm/dlmm_router.interface.json`
- Entrypoints: `16`
- State keys: `15`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_router

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "default_fee_pips": 0
}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### bind_pool

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "pool_contract": null,
  "quote_asset": "xor#universal"
}
```

### assert_router_config

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "default_fee_pips": 0
}
```

### router_config

- Kind: `View`
- Return: `(AssetDefinitionId, int)`
- Sample payload:

```json
{}
```

### router_assets

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId)`
- Sample payload:

```json
{}
```

### mirror_state

- Kind: `View`
- Return: `(int, int)`
- Sample payload:

```json
{}
```

### swap_history_head

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{}
```

### mirror_swap_history

- Kind: `View`
- Return: `(AccountId, int, int, int, int)`
- Sample payload:

```json
{
  "record_id": 0
}
```

### execution_binding

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{}
```

### contract_binding

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{}
```

### quote_direct

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "fee_pips": 0,
  "reserve_in": 0,
  "reserve_out": 0
}
```

### quote_bin

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "bin_id": 0,
  "bin_step": 0,
  "fee_pips": 0,
  "input_is_base": 0,
  "min_reserve_base": 0,
  "min_reserve_quote": 0,
  "reserve_base": 0,
  "reserve_quote": 0
}
```

### select_best_quote

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "direct_out": 0,
  "via_base_out": 0
}
```

### route_swap

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount_in": 0,
  "input_is_base": 0,
  "min_out": 0
}
```

## launchpad.liquidity_executor

- Interface: `artifacts/compiled/launchpad/liquidity_executor.interface.json`
- Entrypoints: `8`
- State keys: `9`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_executor

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "base_asset": "xor#universal",
  "pool_contract": null,
  "quote_asset": "xor#universal"
}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### bind_sale_factory

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "factory_contract": "ed0120..."
}
```

### bind_pool_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "pool_contract": null
}
```

### executor_config

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId, int, int)`
- Sample payload:

```json
{}
```

### executor_binding_details

- Kind: `View`
- Return: `(bytes, AccountId, AccountId, int, int)`
- Sample payload:

```json
{}
```

### seed_liquidity

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "base_amount": 0,
  "bin_id": 0,
  "funding_account": "ed0120...",
  "quote_amount": 0
}
```

## launchpad.sale_factory

- Interface: `artifacts/compiled/launchpad/sale_factory.interface.json`
- Entrypoints: `24`
- State keys: `38`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_factory

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### mirror_sale

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "sale": "name"
}
```

### sale_config

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, int, int, int, int, int)`
- Sample payload:

```json
{
  "sale": "name"
}
```

### mirror_sale_accounting

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "sale": "name"
}
```

### factory_binding_state

- Kind: `View`
- Return: `(int, int)`
- Sample payload:

```json
{}
```

### factory_owner_state

- Kind: `View`
- Return: `(int, AccountId)`
- Sample payload:

```json
{}
```

### factory_binding_details

- Kind: `View`
- Return: `(AccountId, bytes, int, int)`
- Sample payload:

```json
{}
```

### activation_state

- Kind: `View`
- Return: `(int, int)`
- Sample payload:

```json
{
  "sale": "name"
}
```

### mirror_allocation

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "allocation": "name"
}
```

### init_sale

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "claim_end_slot": 0,
  "claim_start_slot": 0,
  "hard_cap": 0,
  "payment_asset": "xor#universal",
  "sale": "name",
  "sale_asset": "xor#universal",
  "soft_cap": 0,
  "treasury": "ed0120...",
  "unit_price": 0
}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### bind_executor

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "executor_contract": null
}
```

### contribute

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "payment_amount": 0,
  "sale": "name"
}
```

### contribute_recorded

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "allocation": "name",
  "payment_amount": 0,
  "sale": "name"
}
```

### close_sale

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "sale": "name"
}
```

### deposit_seed_inventory

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "sale": "name"
}
```

### deposit_claim_inventory

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "sale": "name"
}
```

### register_seed_liquidity

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "bin_id": 0,
  "payment_amount": 0,
  "position_id": "name",
  "sale": "name",
  "sale_amount": 0,
  "vault_account": "ed0120..."
}
```

### seed_liquidity

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "sale": "name"
}
```

### finalize_sale_activation

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "claim_inventory_amount": 0,
  "sale": "name"
}
```

### claim_allocation

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "allocation": "name"
}
```

### refund_allocation

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "allocation": "name"
}
```

### mark_seeded

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "sale": "name"
}
```

## referral.registry

- Interface: `artifacts/compiled/referral/registry.interface.json`
- Entrypoints: `8`
- State keys: `13`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_registry

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "claim_threshold": 0,
  "direct_share_bps": 0,
  "parent_share_bps": 0,
  "reward_asset": "xor#universal",
  "treasury": "ed0120..."
}
```

### bind_member

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "member": "name"
}
```

### bind_member_with_parent

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "member": "name",
  "parent_member": "name"
}
```

### accrue

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "member": "name"
}
```

### claim

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "member": "name"
}
```

### registry_config

- Kind: `View`
- Return: `(AssetDefinitionId, AccountId, int, int, int)`
- Sample payload:

```json
{}
```

### mirror_member

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "member": "name"
}
```

## automation.job_queue

- Interface: `artifacts/compiled/automation/job_queue.interface.json`
- Entrypoints: `15`
- State keys: `11`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### enqueue

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name",
  "payload_hash": 0
}
```

### assign_executor

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "executor": "ed0120...",
  "job": "name"
}
```

### configure_job

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name",
  "max_retries": 0,
  "next_slot": 0,
  "retry_delay_slots": 0
}
```

### configure_cron

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "interval_slots": 0,
  "job": "name"
}
```

### mark_running

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### dispatch_job

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### mark_done

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### complete_run

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### retry

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### pause_job

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### resume_job

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### cancel_job

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "job": "name"
}
```

### mirror_job

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "job": "name"
}
```

## farms.farm

- Interface: `artifacts/compiled/farms/farm.interface.json`
- Entrypoints: `10`
- State keys: `18`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_farm

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "reward_asset": "xor#universal",
  "reward_rate": 0,
  "stake_asset": "xor#universal",
  "treasury": "ed0120..."
}
```

### sync_slot

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "current_slot": 0
}
```

### fund_rewards

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0
}
```

### stake

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "position": "name"
}
```

### unstake

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "position": "name"
}
```

### claim

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "position": "name"
}
```

### farm_config

- Kind: `View`
- Return: `(AssetDefinitionId, AssetDefinitionId, AccountId, int)`
- Sample payload:

```json
{}
```

### farm_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{}
```

### mirror_position

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position": "name"
}
```

## risk.risk_vault

- Interface: `artifacts/compiled/risk/risk_vault.interface.json`
- Entrypoints: `17`
- State keys: `23`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_asset": "xor#universal",
  "vault_account": "ed0120..."
}
```

### configure_bucket

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "bucket_id": 0,
  "collateral_multiplier_bps": 0,
  "controller": "ed0120...",
  "payout_cap_bps": 0,
  "utilisation_cap_bps": 0
}
```

### sync_automation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": 0,
  "bucket_id": 0,
  "cadence_slots": 0,
  "executor": "ed0120...",
  "job_id": 0,
  "safe_mode": 0
}
```

### report_bucket

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog": 0,
  "bucket_id": 0,
  "safe_mode": 0
}
```

### report_bucket_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "backlog": 0,
  "bucket_id": 0,
  "safe_mode": 0
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### deposit

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "bucket_id": 0
}
```

### withdraw_surplus

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "bucket_id": 0
}
```

### lock_liability

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "backlog": 0,
  "bucket_id": 0,
  "collateral_locked": 0,
  "exposure_id": 0,
  "notional": 0
}
```

### release_liability

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "backlog": 0,
  "bucket_id": 0,
  "exposure_id": 0
}
```

### settle_payout

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "bucket_id": 0,
  "exposure_id": 0,
  "recipient": "ed0120..."
}
```

### bucket_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "bucket_id": 0
}
```

### risk_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### automation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "bucket_id": 0
}
```

### liability_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "bucket_id": 0,
  "exposure_id": 0
}
```

## perps.perps_engine

- Interface: `artifacts/compiled/perps/perps_engine.interface.json`
- Entrypoints: `26`
- State keys: `58`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_engine

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_asset": "xor#universal",
  "oracle_public_key": null,
  "oracle_scheme": 0,
  "risk_vault_contract": null
}
```

### sync_automation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": 0,
  "cadence_slots": 0,
  "executor": "ed0120...",
  "funding_job_id": 0,
  "liquidation_job_id": 0,
  "safe_mode": 0
}
```

### engine_config

- Kind: `View`
- Return: `(AssetDefinitionId, bytes, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### market_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": 0
}
```

### market_oracle_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "market_id": 0
}
```

### position_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

### liquidation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": 0
}
```

### position_liquidation_state

- Kind: `View`
- Return: `(int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

### risk_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "market_id": 0
}
```

### automation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### bind_risk_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "risk_vault_contract": null
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### open_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "margin": 0,
  "market_id": 0,
  "oracle_payload": null,
  "oracle_signature": null,
  "requested_leverage_bps": 0,
  "size": 0
}
```

### add_margin

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "position_id": 0
}
```

### remove_margin

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### sync_funding

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "market_id": 0,
  "oracle_payload": null,
  "oracle_signature": null
}
```

### run_liquidation_pass

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "market_id": 0,
  "max_positions": 0,
  "oracle_payload": null,
  "oracle_signature": null
}
```

### close_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### register_market

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "asset": "xor#universal",
  "backlog_limit": 0,
  "funding_bps": 0,
  "funding_interval_slots": 0,
  "liquidation_fee_bps": 0,
  "liquidation_stress_limit": 0,
  "maintenance_margin_bps": 0,
  "max_leverage_bps": 0,
  "open_interest_cap": 0,
  "oracle_stale_slots": 0,
  "utilisation_clamp_bps": 0
}
```

### update_market

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "active": 0,
  "backlog_limit": 0,
  "funding_bps": 0,
  "funding_interval_slots": 0,
  "guard_flags": 0,
  "liquidation_fee_bps": 0,
  "liquidation_stress_limit": 0,
  "maintenance_margin_bps": 0,
  "market_id": 0,
  "max_leverage_bps": 0,
  "open_interest_cap": 0,
  "oracle_stale_slots": 0,
  "utilisation_clamp_bps": 0
}
```

### admin_repair_orphan_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "index_price_bps": 0,
  "mark_price_bps": 0,
  "position_id": 0
}
```

### heartbeat

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": 0,
  "market_id": 0,
  "safe_mode": 0
}
```

### modify_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "margin_delta": 0,
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0,
  "requested_leverage_bps": 0,
  "size_delta": 0
}
```

## options.manager

- Interface: `artifacts/compiled/options/manager.interface.json`
- Entrypoints: `16`
- State keys: `40`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_manager

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "guardian": "ed0120...",
  "oracle_public_key": null,
  "oracle_scheme": 0,
  "settlement_asset": "xor#universal"
}
```

### sync_automation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": 0,
  "cadence_slots": 0,
  "executor": "ed0120...",
  "expiry_job_id": 0,
  "safe_mode": 0,
  "settlement_job_id": 0
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### bind_controller

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "controller": "ed0120..."
}
```

### register_template

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "base_premium_bps": 0,
  "collateral_multiplier_bps": 0,
  "option_kind": 0,
  "quote_asset": "xor#universal",
  "strike_bps": 0,
  "tenor_slots": 0,
  "underlying_asset": "xor#universal"
}
```

### update_template

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "active": 0,
  "base_premium_bps": 0,
  "collateral_multiplier_bps": 0,
  "strike_bps": 0,
  "template_id": 0
}
```

### create_series

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "expiry_slot": 0,
  "max_notional": 0,
  "premium_bps": 0,
  "template_id": 0
}
```

### close_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "series_id": 0,
  "settlement_slot": 0
}
```

### settle_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "series_id": 0
}
```

### settle_series_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "attestation_hash": 0,
  "final_mark": 0,
  "final_quote_mark": 0,
  "oracle_slot": 0,
  "series_id": 0,
  "settlement_slot": 0
}
```

### manager_config

- Kind: `View`
- Return: `(AssetDefinitionId, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### template_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "template_id": 0
}
```

### series_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "series_id": 0
}
```

### automation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## options.factory

- Interface: `artifacts/compiled/options/factory.interface.json`
- Entrypoints: `21`
- State keys: `52`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_factory

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "guardian": "ed0120...",
  "oracle_public_key": null,
  "oracle_scheme": 0,
  "settlement_asset": "xor#universal"
}
```

### bind_modules

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "outperf_contract": null,
  "risk_vault_contract": null,
  "shout_contract": null,
  "vault_contract": null
}
```

### bind_manager

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "manager_contract": null
}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### sync_automation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": 0,
  "cadence_slots": 0,
  "executor": "ed0120...",
  "job_id": 0,
  "safe_mode": 0
}
```

### heartbeat

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": 0,
  "safe_mode": 0
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### sync_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_multiplier_bps": 0,
  "expiry_slot": 0,
  "max_notional": 0,
  "option_kind": 0,
  "premium_bps": 0,
  "series_id": 0,
  "strike_bps": 0
}
```

### configure_utilisation_guard

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "bump_activate_bps": 0,
  "bump_deactivate_bps": 0,
  "bump_percent_bps": 0,
  "pause_threshold_bps": 0,
  "series_id": 0
}
```

### buy_shout

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "collateral_locked": 0,
  "notional": 0,
  "premium_paid": 0,
  "series_id": 0
}
```

### buy_outperformance

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "collateral_locked": 0,
  "notional": 0,
  "premium_paid": 0,
  "series_id": 0
}
```

### settle_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "series_id": 0
}
```

### record_shout

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### exercise_shout_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### exercise_outperformance_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "position_id": 0
}
```

### factory_config

- Kind: `View`
- Return: `(AssetDefinitionId, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### series_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "series_id": 0
}
```

### position_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

### automation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## options.vault

- Interface: `artifacts/compiled/options/vault.interface.json`
- Entrypoints: `14`
- State keys: `15`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "risk_vault_contract": null,
  "settlement_asset": "xor#universal"
}
```

### bind_controller

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "controller": "ed0120..."
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### sync_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "series_id": 0
}
```

### sync_series_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "series_id": 0
}
```

### record_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_locked": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "premium_paid": 0,
  "series_id": 0
}
```

### record_position_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "collateral_locked": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "premium_paid": 0,
  "series_id": 0
}
```

### release_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_release": 0,
  "position_id": 0
}
```

### settle_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "payout": 0,
  "position_id": 0,
  "premium_burn": 0
}
```

### settle_position_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "payout": 0,
  "position_id": 0,
  "premium_burn": 0
}
```

### vault_state

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "series_id": 0
}
```

### position_accounting

- Kind: `View`
- Return: `(int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

## options.shout_option

- Interface: `artifacts/compiled/options/shout_option.interface.json`
- Entrypoints: `16`
- State keys: `20`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_product

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "guardian": "ed0120...",
  "oracle_public_key": null,
  "oracle_scheme": 0
}
```

### bind_controller

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "controller": "ed0120..."
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### sync_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "expiry_slot": 0,
  "series_id": 0,
  "strike_bps": 0
}
```

### sync_series_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "expiry_slot": 0,
  "series_id": 0,
  "strike_bps": 0
}
```

### register_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "notional": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "series_id": 0,
  "strike_bps": 0
}
```

### register_position_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "notional": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "series_id": 0,
  "strike_bps": 0
}
```

### record_shout

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### record_shout_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "attestation_hash": 0,
  "mark_price_bps": 0,
  "oracle_slot": 0,
  "position_id": 0
}
```

### exercise_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "position_id": 0
}
```

### exercise_position_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "attestation_hash": 0,
  "mark_price_bps": 0,
  "oracle_slot": 0,
  "position_id": 0
}
```

### expire_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "series_id": 0
}
```

### series_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "series_id": 0
}
```

### position_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

## options.outperformance_option

- Interface: `artifacts/compiled/options/outperformance_option.interface.json`
- Entrypoints: `15`
- State keys: `20`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_product

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "guardian": "ed0120..."
}
```

### bind_controller

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "controller": "ed0120..."
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### sync_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_multiplier_bps": 0,
  "expiry_slot": 0,
  "series_id": 0
}
```

### sync_series_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "collateral_multiplier_bps": 0,
  "expiry_slot": 0,
  "series_id": 0
}
```

### register_position

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "collateral_multiplier_bps": 0,
  "notional": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "series_id": 0
}
```

### register_position_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "collateral_multiplier_bps": 0,
  "notional": 0,
  "owner": "ed0120...",
  "position_id": 0,
  "series_id": 0
}
```

### settle_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "base_return_bps": 0,
  "quote_return_bps": 0,
  "series_id": 0,
  "settlement_slot": 0
}
```

### settle_series_c2c

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "base_return_bps": 0,
  "quote_return_bps": 0,
  "series_id": 0,
  "settlement_slot": 0
}
```

### exercise_position

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "position_id": 0
}
```

### expire_series

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "series_id": 0
}
```

### series_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "series_id": 0
}
```

### position_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "position_id": 0
}
```

## cover.policy_manager

- Interface: `artifacts/compiled/cover/policy_manager.interface.json`
- Entrypoints: `15`
- State keys: `36`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_manager

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_public_key": null,
  "oracle_scheme": 0,
  "oracle_stale_slots": 0,
  "required_observations": 0,
  "risk_vault_contract": null,
  "settlement_asset": "xor#universal"
}
```

### sync_automation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "backlog_cap": 0,
  "cadence_slots": 0,
  "executor": "ed0120...",
  "job_id": 0,
  "safe_mode": 0
}
```

### heartbeat

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "current_backlog": 0,
  "safe_mode": 0
}
```

### bind_contract

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "contract_id": "ed0120..."
}
```

### bind_risk_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "risk_vault_contract": null
}
```

### enter_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### exit_withdrawal_only

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{}
```

### register_policy

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "covered_notional": 0,
  "lower_bound": 0,
  "monitoring_window_slots": 0,
  "payout_amount": 0,
  "premium_paid": 0,
  "required_observations": 0,
  "upper_bound": 0
}
```

### record_observation

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "oracle_payload": null,
  "oracle_signature": null,
  "policy_id": 0
}
```

### route_claim

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "policy_id": 0
}
```

### expire_policy

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "policy_id": 0
}
```

### manager_config

- Kind: `View`
- Return: `(AssetDefinitionId, bytes, int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

### policy_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "policy_id": 0
}
```

### automation_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{}
```

## bridge.sccp_bridge

- Interface: `artifacts/compiled/bridge/sccp_bridge.interface.json`
- Entrypoints: `23`
- State keys: `28`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### init_bridge

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "listing_fee_amount": 0,
  "listing_fee_asset": "xor#universal",
  "proof_authority": "ed0120...",
  "treasury": "ed0120..."
}
```

### set_proof_authority

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "proof_authority": "ed0120..."
}
```

### register_asset

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "asset": "xor#universal",
  "asset_key": "name",
  "decimals": 0,
  "home_domain": 0
}
```

### bind_asset_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "name",
  "vault_account": "ed0120..."
}
```

### activate_route

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "name",
  "local_asset": "xor#universal",
  "remote_domain": 0,
  "route": "name",
  "vault_account": "ed0120..."
}
```

### activate_route_governed

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "asset_key": "name",
  "message_id": "name",
  "remote_domain": 0,
  "route": "name"
}
```

### pause_route

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "route": "name"
}
```

### resume_route

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "route": "name"
}
```

### lock_to_remote

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "amount": 0,
  "recipient": "name",
  "route": "name",
  "transfer": "name"
}
```

### finalize_inbound

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "message_id": "name",
  "recipient": "ed0120...",
  "route": "name"
}
```

### listing_config

- Kind: `View`
- Return: `(AssetDefinitionId, AccountId, int, int)`
- Sample payload:

```json
{}
```

### bridge_authorities

- Kind: `View`
- Return: `(AccountId, AccountId)`
- Sample payload:

```json
{}
```

### mirror_asset

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "asset_key": "name"
}
```

### asset_config

- Kind: `View`
- Return: `(AssetDefinitionId, int, int)`
- Sample payload:

```json
{
  "asset_key": "name"
}
```

### asset_vault_bound

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "asset_key": "name"
}
```

### asset_vault_account

- Kind: `View`
- Return: `AccountId`
- Sample payload:

```json
{
  "asset_key": "name"
}
```

### mirror_route

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "route": "name"
}
```

### route_config

- Kind: `View`
- Return: `(Name, int, AssetDefinitionId, AccountId)`
- Sample payload:

```json
{
  "route": "name"
}
```

### route_provenance

- Kind: `View`
- Return: `(int, Name)`
- Sample payload:

```json
{
  "route": "name"
}
```

### mirror_outbound

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "transfer": "name"
}
```

### outbound_config

- Kind: `View`
- Return: `(Name, AccountId, Name, int)`
- Sample payload:

```json
{
  "transfer": "name"
}
```

### inbound_consumed

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "message_id": "name"
}
```

## intents.settlement_router

- Interface: `artifacts/compiled/intents/settlement_router.interface.json`
- Entrypoints: `5`
- State keys: `12`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### open_intent

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": 0,
  "deadline_slot": 0,
  "input_asset": "xor#universal",
  "intent_id": "name",
  "min_out": 0,
  "nonce": 0,
  "output_asset": "xor#universal",
  "solver_fee_bps": 0
}
```

### cancel_intent

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "intent_id": "name"
}
```

### fill_intent

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount_out": 0,
  "fill_slot": 0,
  "intent_id": "name"
}
```

### intent_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "intent_id": "name"
}
```

## vaults.manager

- Interface: `artifacts/compiled/vaults/manager.interface.json`
- Entrypoints: `7`
- State keys: `13`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### register_vault

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "async_redeem": 0,
  "share_asset": "xor#universal",
  "strategy_code": 0,
  "underlying_asset": "xor#universal",
  "vault_id": "name"
}
```

### deposit

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "position_id": "name",
  "vault_id": "name"
}
```

### request_redeem

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "claim_slot": 0,
  "position_id": "name",
  "request_id": "name",
  "shares": 0,
  "vault_id": "name"
}
```

### claim_redeem

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "current_slot": 0,
  "request_id": "name"
}
```

### vault_state

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "vault_id": "name"
}
```

### position_state

- Kind: `View`
- Return: `int`
- Sample payload:

```json
{
  "position_id": "name"
}
```

## operators.registry

- Interface: `artifacts/compiled/operators/registry.interface.json`
- Entrypoints: `6`
- State keys: `8`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### register_operator

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "bond_asset": "xor#universal",
  "min_bond": 0,
  "service": "name"
}
```

### bond

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount": 0,
  "service": "name"
}
```

### heartbeat

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "fees_accrued": 0,
  "health_bps": 0,
  "service": "name",
  "slot": 0
}
```

### claim_fees

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "service": "name"
}
```

### operator_state

- Kind: `View`
- Return: `(int, int, int, int, int, int, int)`
- Sample payload:

```json
{
  "service": "name"
}
```

## margin.portfolio_margin

- Interface: `artifacts/compiled/margin/portfolio_margin.interface.json`
- Entrypoints: `8`
- State keys: `7`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### register_market

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "liquidation_threshold_bps": 0,
  "market_id": "name",
  "risk_weight_bps": 0
}
```

### deposit_collateral

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "name",
  "amount": 0
}
```

### withdraw_collateral

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "name",
  "amount": 0
}
```

### lock_exposure

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "account_key": "name",
  "exposure_delta": 0,
  "market_id": "name"
}
```

### liquidate_account

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{
  "account_key": "name"
}
```

### market_state

- Kind: `View`
- Return: `(int, int, int)`
- Sample payload:

```json
{
  "market_id": "name"
}
```

### account_health

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "account_key": "name"
}
```

## rwa.market

- Interface: `artifacts/compiled/rwa/market.interface.json`
- Entrypoints: `7`
- State keys: `10`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### issue_lot

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "initial_nav_per_share": 0,
  "market_id": "name",
  "nav_asset": "xor#universal",
  "share_asset": "xor#universal",
  "total_shares": 0
}
```

### bind_share_asset

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "market_id": "name",
  "share_asset": "xor#universal"
}
```

### report_nav

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "market_id": "name",
  "nav_per_share": 0,
  "status": 0,
  "total_shares": 0
}
```

### request_redemption

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "market_id": "name",
  "redemption_id": "name",
  "shares": 0
}
```

### settle_redemption

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "redemption_id": "name"
}
```

### rwa_market_state

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "market_id": "name"
}
```

## dlmm_hooks.hook_manager

- Interface: `artifacts/compiled/dlmm_hooks/hook_manager.interface.json`
- Entrypoints: `7`
- State keys: `11`

### main

- Kind: `Public`
- Return: `int`
- Sample payload:

```json
{}
```

### configure_hook_policy

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "enabled": 0,
  "hook_id": "name",
  "max_fee_pips": 0,
  "phase": 0
}
```

### place_limit_order

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": 0,
  "hook_id": "name",
  "min_out": 0,
  "order_id": "name"
}
```

### schedule_twamm

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": 0,
  "hook_id": "name",
  "interval_slots": 0,
  "min_out": 0,
  "order_id": "name"
}
```

### record_execution

- Kind: `Public`
- Return: `null`
- Sample payload:

```json
{
  "amount_in": 0,
  "amount_out": 0,
  "order_id": "name"
}
```

### hook_policy

- Kind: `View`
- Return: `(int, int, int, int)`
- Sample payload:

```json
{
  "hook_id": "name"
}
```

### quote_hooked_swap

- Kind: `View`
- Return: `(int, int, int, int, int)`
- Sample payload:

```json
{
  "order_id": "name"
}
```
