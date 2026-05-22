# Operators Interface

Contract: `contracts/operators/registry.ko`

Entrypoints:
- `register_operator(service, bond_asset, min_bond)`
- `bond(service, amount)`
- `heartbeat(service, slot, health_bps, fees_accrued)`
- `claim_fees(service) -> int`
- `operator_state(service) -> (int, int, int, int, int, int, int)`

Notes:
- Services are labels such as `solver`, `keeper`, `oracle`, `relayer`, or `executor`.
- Health below `5000` bps marks the service as jailed in the contract state.
