# External Validation-Fee Payout State Layout

The payout wrapper has no mutable contract state and no lifecycle initializer
or upgrade hook. All policy values are source literals in the rendered
Kotodama artifact.

Its only durable runtime object is the compiler-declared
`validation_fee_autonomous_payout` trigger:

- Filter: time, pre-commit.
- Repetitions: indefinite.
- Authority: the source-pinned payout contract subject/vault.
- Callback: `autonomous_validation_fee_tick`.

The DLMM pool retains reserves and fee growth. The wrapper retains no balances,
recipient registry, router choice, owner, administrator, counters, or cached
quote. Ledger asset balances and the atomic transaction overlay are the
authoritative payout state.

The protected lifecycle atomically derives the two exact
`CanInvokeContractEntrypoint` tokens and the pool-held exact
`CanTransferAsset(SBD#payout_subject#dataspace:0)` token. Those permissions are
ledger topology, not wrapper state or runtime configuration. External pool
bootstrap never provisions any of the three; activation must fail unless they
are all absent before enactment and Core can atomically install and then
verify each exact sole direct holder with no role delegation.
