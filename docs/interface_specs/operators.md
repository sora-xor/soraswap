# Operators Interface

Contract: `contracts/operators/registry.ko`

Entrypoints:
- `main() -> int`
- `register_operator(service, operator_owner, bond_asset, bond_vault, fee_asset, fee_vault, min_bond)`
- `bond(service, amount)`
- `heartbeat(service, slot, health_bps)`
- `accrue_fees(service, amount)`
- `claim_fees(service) -> quantity`
- `operator_state(service) -> (int, quantity, quantity, decimal, int, quantity, int)`

Notes:
- Services are labels such as `solver`, `keeper`, `oracle`, `relayer`, or `executor`.
- Bond and fee custody accounts are registered explicitly; heartbeat telemetry does not mutate fee accrual.
- Health below `5000` bps marks the service as jailed in the contract state.
