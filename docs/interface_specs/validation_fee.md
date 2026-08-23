# External Validation-Fee Payout Interface

The rendered contract is
`artifacts/rendered/validation_fee/autonomous_payout.ko`. Its template,
dedicated manifest, and renderer are outside the default SoraSwap contract
bundle, so no normal deploy or release command can publish it accidentally.

The deterministic fresh-chain input is
`config/validation_fee/autonomous-payout.taira.pending.json`, with derivation
metadata in the adjacent `.provenance.json`. It pins the four accounts tagged
`taira_validator_payout_recipient` in rendered genesis SHA-256
`766910cc2cd4916701c17f00d8f0cad23da0d19774bfad82e3d42442b26178cc`
and intentionally leaves the three live pool/payout binding values unresolved.
The renderer rejects those markers.

The dedicated tooling invokes Kotodama check, build, and test with the exact
Taira chain discriminant `369`. It accepts only canonical `test` account
literals and never translates them to the default Sora discriminant `753`.
Kotodama includes the selected discriminant in its compiler-policy fingerprint,
so a cached artifact admitted for one network cannot satisfy another.

The only mutating entrypoint is:

- `autonomous_validation_fee_tick() -> quantity`, authorized by
  the exact typed `CanInvokeContractEntrypoint` token and callable only as the declared
  `validation_fee_autonomous_payout` indefinite pre-commit time trigger.

The callback requires both `context::authority()` and
`context::seiyaku_subject()` to equal the pinned payout contract subject. A
contract subject has no signing key, and the protected Core lifecycle derives
the exact selector permission only through the reviewed trigger topology. The
zero-argument schema also rejects injected call payload fields. Core currently
supplies an empty event object to zero-argument time callbacks, so the wrapper
does not depend on nonexistent interval fields.

Kotodama does not currently expose a typed trigger-id/origin builtin. The
deployment gate must therefore verify the non-signable derived contract
subject, the post-enactment direct exact `CanInvokeContractEntrypoint` grant for
`autonomous_validation_fee_tick`, the declared trigger, and the derived
lifecycle seal together. Any role holder, additional direct holder, caller,
or trigger grant is a different topology and must fail the binding review.

The source pins:

- The exact DLMM contract address.
- The DLMM pool vault and payout contract subject/vault.
- Canonical SBD `7ZepsJTHCVLKsrFFNZGSRGZgvBhv`.
- Canonical XOR `6TEAJqbb8oEPmLncoNiMRbLEK6tw`.
- Exactly 10 SBD input and 4..100 XOR output.
- Exactly four distinct validator recipient accounts.

The reviewed pool instance must report canonical XOR as base, canonical SBD as
quote, the source-pinned pool vault, and `AdminRenounced == 1` before this
wrapper is admitted. The wrapper cannot repair or rotate a pool binding at
runtime.

The tick returns zero without effects when the payout vault has less than 10
SBD or the pinned pool vault has less than 4 XOR. Otherwise it invokes only
the pool's caller-funded, full-fill `swap_exact_in_quote_public`, verifies
exact SBD/XOR balance deltas, and transfers one exact quarter of output to
each recipient as one batch. A bound, delta, nested-call, or recipient-transfer
failure rejects the complete overlay atomically.

The protected Core lifecycle first requires all three protected runtime
permissions to be absent. It then atomically derives the wrapper subject's
exact `CanInvokeContractEntrypoint(wrapper,
autonomous_validation_fee_tick)` and
`CanInvokeContractEntrypoint(pool, swap_exact_in_quote_public)` selectors.
Because nested pool effects execute as the pool subject, the same lifecycle
atomically installs that pool subject as the sole direct holder of exact
`CanTransferAsset(SBD#payout_subject#dataspace:0)` and then validates the
complete topology. External bootstrap must not attempt any of those three
grants. The wrapper and pool use self-owned balance reads and reserve/output
transfers for the remaining effects. No role, generic `iroha.custom`
sponsorship, or broader selector/effect surface is permitted.

There is no owner, admin, manual trigger, roster, lifecycle-seal setter, router,
upgrade, or sponsorship entrypoint. Iroha derives the lifecycle seal only from
the canonical typed payout binding; it is never accepted as a runtime anchor or
deployment-supplied field. Finalized Parliament evidence remains a separate
activation gate.
