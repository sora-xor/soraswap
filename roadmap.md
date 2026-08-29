# SoraSwap Roadmap

Last updated: 2026-08-24

## Current status

The trader roadmap slice is implemented locally across `soraswap` plus `../iroha`. Current source-level checks are green, but no completed local or Taira release evidence set is retained; the full acceptance sequence must be regenerated against the current API.
The local release hygiene gate also scans generated deployment/telemetry JSON for raw local path diagnostics, requires retained evidence to stay stable under the shared sensitive-data/runtime-path redactor, keeps public/local deploy and smoke path labels basename/repo-relative, and validates `.gitignore` behavior for generated evidence, `.gitkeep` placeholders, ignored public signer configs, and visible `*.toml.example` templates.

Shipped:
- Canonical trader-event metadata is attached in `../iroha` for the current SoraSwap trader entrypoints, with public module names normalized to `swaps`, `n3x`, `perps`, `farms`, `launchpad`, `options`, and `cover`.
- Torii now exposes the trader read plane needed by the cockpit:
  - `POST /v1/contracts/view/batch`
  - `GET /v1/contracts/rollups/swaps/fills`
  - `GET /v1/contracts/rollups/swaps/candles`
  - `GET /v1/contracts/rollups/trader/activity`
  - `GET /v1/contracts/rollups/trader/account`
- The trader UI now consumes rollups/account endpoints as its primary source for candles, fills, wallet metrics, module cards, and unified activity instead of rebuilding the page from ad hoc view stitching.
- The public `options` surface is a single factory-backed cockpit tile.
- Real user-facing action rails now exist in the cockpit for swaps, `n3x`, perps, farms, launchpad, options, and cover.
- The Python proxy and local fixture server both speak the new trader rollup and batch-view surfaces.
- Browser smoke coverage in `tests/trader_ui.spec.js` now exercises the rollup-backed cockpit, explicit public candle `bucket_secs` queries, a capped 120-fill history render, and a signed trader action through the real Python server.
- `../iroha` compiles with the new trader metadata and route registrations (`cargo check -p iroha_torii`).
- Torii has a CID-routed app API gateway for pinned SoraFS route manifests:
  - `GET /v1/app-api/bindings`
  - `GET /v1/app-api/cid/{cid}`
  - `GET|POST /v1/app-api/cid/{cid}/{*path}`
  - `GET|POST /v1/app-api/active/{*path}`
- `make publish-trader-api` now builds the SoraSwap trader route manifest, pins it to SoraFS, writes deployment evidence, fails nonzero unless the report is fully completed, and can optionally bind the CID to a public SoraCloud service config.
- The local trader proxy caps rollup/activity history windows before forwarding requests to Torii, forwards candle bucket sizing only on the candle route, and keeps trader-account rollups authority-only, so browser/API callers cannot accidentally turn the cockpit into an unbounded public-node history scan during longer sessions.

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
- Current-chain Taira preflight readiness. `deployments/testnet/preflight.latest.json` has `status: "blocked"`: native MCP is reachable at HTTP `200` and the canonical live chain fingerprint is visible, but MCP capability metadata is incomplete and no saved chain snapshot, secure oracle config, mutation consent, or current nested-call probe exists.
- Completed external RWA compliance references only for an explicit `SORASWAP_ENABLE_RWA_RELEASE=1` market launch; the default DEX-only release now records current-chain RWA evidence as `not_applicable`.
- Production chain setup and signed production evidence after the Taira artifact gate is green. No production preflight or chain evidence is retained in this checkout.
- Public/production validation for longer history ranges and real user load after the Taira artifact gate is green.

## Next steps

1. Restore Taira public MCP/write health, then rerun `SORASWAP_ALLOW_TESTNET_MUTATIONS=1 make taira-preflight` until it is ready before any signed release phase.
2. If launching an RWA market, set `SORASWAP_ENABLE_RWA_RELEASE=1` and record concrete issuer approval, legal review, compliance policy, NAV source, and redemption terms references before the signed release.
3. After Taira is green, run `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1 make release-production` and push the rollup-backed trader flow through public/production longer-history windows and real load.

## Current Taira evidence

- The canonical first-release identity is chain `fc56984b-2be7-431d-840e-21514d1883f0`, NetworkId `hash:82531CE8EAE8BFF6BEECA4698BFD13A3BC8BEC5F0EE0D23D428C97FC17AB0F3B#3E94`, and account-chain discriminant `369`.
- `deployments/testnet/preflight.latest.json` is the current blocked diagnostic. It observes the canonical live fingerprint but does not include a saved chain snapshot or current nested-call capability evidence.
- Current-chain `chain.latest.json`, signed nested-call probe, deploy/contracts, RWA-mode, smoke, console, trader, and trader API release evidence are absent.
- The next release work is a read-only chain refresh, fresh signed probe, ready preflight, and then the ordered release evidence sequence. Historical success is not reusable.

## Near-term acceptance bar

This roadmap slice can be called fully complete when:
- the current SoraSwap trader surfaces emit canonical trader-facing metadata,
- the trader cockpit uses Torii rollups as its primary data source,
- the module rails are real for the supported products,
- local and Taira validation are both green,
- the pinned trader route bundle resolves through public Taira's CID app API gateway,
- the release evidence is generated, retained under the appropriate `deployments/<env>/` evidence directory, and accepted by the release checklist.
