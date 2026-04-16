# SoraSwap Roadmap

Last updated: 2026-04-16

## Current status

The trader roadmap slice is now implemented locally across `soraswap` plus `../iroha`.

Shipped:
- Canonical trader-event metadata is attached in `../iroha` for the current SoraSwap trader entrypoints, with public module names normalized to `swaps`, `n3x`, `perps`, `farms`, `launchpad`, `options`, and `cover`.
- Torii now exposes the trader read plane needed by the cockpit:
  - `POST /v1/contracts/view/batch`
  - `GET /v1/contracts/rollups/swaps/fills`
  - `GET /v1/contracts/rollups/swaps/candles`
  - `GET /v1/contracts/rollups/trader/activity`
  - `GET /v1/contracts/rollups/trader/account`
- The trader UI now consumes rollups/account endpoints as its primary source for candles, fills, wallet metrics, module cards, and unified activity instead of rebuilding the page from ad hoc view stitching.
- The public `options` surface is unified in the cockpit instead of split `manager` and `factory` tiles.
- Real user-facing action rails now exist in the cockpit for swaps, `n3x`, perps, farms, launchpad, options, and cover.
- The Python proxy and local fixture server both speak the new trader rollup and batch-view surfaces.
- Browser smoke coverage in `tests/trader_ui.spec.js` now exercises the rollup-backed cockpit plus a signed trader action through the real Python server.
- `../iroha` compiles with the new trader metadata and route registrations (`cargo check -p iroha_torii`).
- Torii has a CID-routed app API gateway for pinned SoraFS route manifests:
  - `GET /v1/app-api/bindings`
  - `GET /v1/app-api/cid/{cid}`
  - `GET|POST /v1/app-api/cid/{cid}/{*path}`
  - `GET|POST /v1/app-api/active/{*path}`
- `make publish-trader-api` now builds the SoraSwap trader route manifest, pins it to SoraFS, writes deployment evidence, and can optionally bind the CID to a public SoraCloud service config.

## What is done

### Trader UI
- Swap candles, fills, wallet metrics, module cards, and unified activity now hydrate from dedicated Torii trader rollups.
- The cockpit follows contract-event SSE and falls back to polling when needed.
- Product rails are real for the currently supported trader surfaces instead of summary-only placeholders.

### `../iroha` support
- Canonical trader metadata now lands on supported successful contract calls.
- Trader rollups and batch-view reads are routable over Torii.
- Contract-event indexing remains available for direct event views and SSE.

## What is not done yet

The remaining gap for this slice is live environment validation and evidence, not the local implementation itself.

Still missing:
- Public Taira validator rollout from the patched `../iroha` runtime so every validator accepts permissionless SoraFS capacity declarations and can rehydrate the trader CID through the shared edge.
- At least one visible public SoraFS capacity declaration on Taira so repeated `GET /v1/app-api/cid/{cid}` probes stop mixing `200` and `404` across validators that did not receive the original storage pin.
- Production hardening for longer history ranges and real user load.

## Next steps

1. Keep public Taira on the patched `../iroha` build, then add or restore public SoraFS provider capacity so repeated `GET /v1/app-api/cid/{cid}` probes stop mixing `200` and `404` across validators.
2. Re-run `bash ../iroha/configs/soranexus/taira/check_sorafs_rollout.sh --public-root https://taira.sora.org` and let it auto-bootstrap `/run/secrets/taira-canary-client.toml` from a fresh signer if the runtime canary file is missing.
3. Re-run `make publish-trader-api` until `deployments/testnet/trader_api_bundle.latest.json` records `cid_probe.status = "completed"` across repeated attempts, not merely a single successful cache hit.
4. Re-run `make smoke-testnet-trader-readonly` until `deployments/testnet/trader_readonly.latest.json` is green.
5. Re-run `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make smoke-testnet-trader` with a fresh signer until `deployments/testnet/trader.latest.json` records a committed signed trader mutation instead of faucet expiry.
6. Push the same rollup-backed trader flow through longer history windows and real load.

## Current Taira evidence

On April 15, 2026:
- `deployments/testnet/trader_readonly.latest.json` was written and shows legacy `/v1/contracts/activity` plus `/v1/contracts/events` are live, but all new trader rollup routes are still missing on public Taira.
- `deployments/testnet/trader.latest.json` was written from a fresh generated signer and shows the same route blocker plus three terminal `Expired` faucet claims under the saturated public queue.
- `deployments/testnet/trader_api_bundle.latest.json` was written after pinning the route bundle to Taira SoraFS:
  - content CID: `bafyr6ify3wnhgitoefdihi5mkdqvt2zbelpnvuk7wuyardy6wshizz3chm`
  - manifest digest: `2be3538b71b80b060f88b0e32410d5224ad82d195e7c09504811677801b60acc`
  - pin status: `200`
  - CID probe: `404`, because public Taira has not yet been rolled forward to the Torii app API gateway.
- `scripts/release_checklist.sh` now requires trader readonly, signed trader, and trader API bundle evidence; it will fail until those reports turn `completed`.

## Near-term acceptance bar

This roadmap slice can be called fully complete when:
- the current SoraSwap trader surfaces emit canonical trader-facing metadata,
- the trader cockpit uses Torii rollups as its primary data source,
- the module rails are real for the supported products,
- local and Taira validation are both green,
- the pinned trader route bundle resolves through public Taira's CID app API gateway,
- the release evidence is written and checked in.
