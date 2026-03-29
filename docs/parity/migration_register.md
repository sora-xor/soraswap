# SoraSwap Migration Register

This register tracks behavior-level migration from the legacy reference implementation into this Kotodama repo.

Status values:
- `stub` - repo placeholder only
- `adapted` - initial Kotodama shape exists, but feature parity is incomplete
- `ported` - intended behavior is mostly present in this repo
- `blocked` - waiting on an `../iroha` capability or design decision
- `reference-only` - kept for comparison, not part of the deployable surface

| Reference area | SoraSwap area | Status | Notes |
| --- | --- | --- | --- |
| T3 hub | `contracts/n3x/n3x_hub.ko` | adapted | Renamed to `n3x`; the singleton basket hub now exposes configurable basket targets, mint/redeem fee accounting, mint/redeem quotes, and typed reserve snapshots, but it is still not the final production parity surface. |
| DLMM | `contracts/dlmm/dlmm_pool.ko` | ported | Single-pool Kotodama DLMM now includes deterministic multi-bin walk, guard rails, seeded multi-bin liquidity, explicit `position_id` LP accounting, and per-bin fee claims; factory/registry parity and planned helper/NFT wrappers remain outside this repo slice. |
| DLMM router | `contracts/dlmm/dlmm_router.ko` | adapted | Stateless quote helpers now include bin-aware pricing, but cross-contract route execution is still not modeled in this repo. |
| Launchpad | `contracts/launchpad/sale_factory.ko` | adapted | Fixed-price sale scaffold now includes configurable soft/hard caps, recorded allocations, vesting windows, claim inventory, refund accounting, explicit seed inventory accounting, registered DLMM seed plans, and typed sale/allocation snapshots; separate vesting-vault contracts and executor-driven cross-contract pool activation remain outside this repo slice. |
| Referral | `contracts/referral/registry.ko` | adapted | Registry config, routed child/parent accrual splits, member-bound claim accounting, thresholds, and typed child-plus-parent snapshots are now present; broader affiliate settlement and richer campaign logic remain outside this repo slice. |
| Automation | `contracts/automation/job_queue.ko` | adapted | Jobs now model queued/running/paused/done scheduling with retry limits, retry delays, executor binding, recurring cron-style reschedule, run counts, and typed snapshots; a fuller external executor network still remains out of scope. |
| Farms | `contracts/farms/farm.ko` | adapted | Reward funding, owned stake positions, claim, unstake, and typed farm accounting snapshots are now present; emissions math is still a simplified rate-per-stake scaffold rather than final production parity. |
| Perps | `contracts/perps/perps_engine.ko` | adapted | Risk config, collateral add/remove, funding accrual, close, liquidation, and typed position snapshots are now present; mark/oracle, matching, and cross-position risk netting remain outside this repo slice. |
| Options | `contracts/options/series_manager.ko` | adapted | Configurable series lifecycle, ticket ownership, expiry/void handling, and typed series/ticket snapshots are now present; vault collateralization and settlement engines remain external. |
| Cover | `contracts/cover/policy_manager.ko` | adapted | Sized policy activation, breach recording, claim/cancel/expire handling, and typed policy snapshots are now present; underwriting pools and external adjudication remain outside this repo slice. |
| CLMM | N/A | reference-only | Not deployable in SoraSwap v1. |
| XYK | N/A | reference-only | Useful as a math comparator only. |
| SigmAMM | N/A | reference-only | Not deployable in SoraSwap v1. |

## Open TODOs
- Replace the current `position_id`-keyed DLMM LP scaffold with the final helper/NFT-oriented position surface if helper/NFT wrappers become necessary on Sora Nexus.
- Add real conflict-aware state layout docs and deploy-time contract ids beyond the current bootstrap defaults.
- Identify any `../iroha` blockers that require compiler, host, Torii, or CLI changes.
- Decide whether launchpad seeding should stay externally orchestrated or move to a dedicated Kotodama-side DLMM executor once multi-pool wiring is modeled in this repo.
- Extend shared testnet smoke beyond initialized-state assertions and typed view snapshots into managed swap and settlement verification once shared state ownership is defined.
