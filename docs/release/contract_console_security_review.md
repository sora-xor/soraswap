# Contract Console Security Review

## Scope
- `scripts/serve_contract_console.py`
- `ui/contract_console/`
- operator workflows for contract calls, SCCP discovery, proof lookup, and bridge submission

## Current Controls
- Deployment records are the canonical Torii source. Signer configs may add authority, signing material, and auth headers, but they do not override deployment Torii URLs.
- When public mutations are enabled, the console refuses to start unless `docs/parity/migration_register.md` is present, nonempty, has at least one `ported` production row, and has no non-reference production rows outside `ported`.
- Mutation-enabled public sessions also require current `chain.latest.json`, `preflight.latest.json`, `nested_call_probe.latest.json`, `deploy.latest.json`, an exact current-source `contracts.latest.json`, and per-contract `*.deploy.json` plus `*.manifest.json` evidence. Those artifacts must record `generated_at` provenance, selected-environment metadata, and the same `torii_url`, chain id, and block-1 hash. If `soraswap.bundle.deploy.json` is present, the startup guard also requires that aggregate receipt to be successful, timestamped, selected-environment-scoped, path-clean, free of unredacted sensitive diagnostics, matched to `chain.latest.json`, and matching the current contracts snapshot.
- `preflight.latest.json` must be ready for the saved chain, signer/oracle environment, and the current supported nested-call probe; `nested_call_probe.latest.json` must be supported; `deploy.latest.json` must show completed preflight, compile, nested-call-probe, deploy, bootstrap, and deployment-snapshot phases without a skipped signer-ready check; `contracts.latest.json` must have top-level `status: "completed"`.
- Browser requests cannot supply private-key, secret, mnemonic, token/API-key, authorization, password, or passphrase fields anywhere in browser JSON; the backend rejects those fields before adding signer-config material server-side.
- Browser-facing catalog data uses a basename-only repo label and repo-relative contract source plus deployment/manifest evidence paths. Signer snapshots expose only whether a signer and Basic Auth are configured, the authority, basename-scoped source and warning labels, and the signer config basename; they do not expose private keys, Basic Auth values, or parent signer-config directories.
- Public release evidence and release-checklist report path labels are repo-relative for files under the checkout and basename-only for outside runtime paths; the underlying commands still use the real paths. Phase guards and the final checklist reject required public evidence, including per-contract deploy records and manifests, when diagnostic string values or object keys still contain raw local `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, or `/private/var/folders/...` paths; the final checklist applies the same rule to the required local primitive telemetry artifact.
- Public shell wrappers redact normalized sensitive fields and CLI-style private-key, token, authorization, password/passphrase, secret, and mnemonic captures from upstream call/deploy/view, bootstrap/SNS and asset-alias fallback, manifest-build, contract-app deploy, and trader API publication error text before writing stderr or failure evidence, so echoed request bodies or command lines do not persist signer keys, passwords, or API tokens into nested-probe, deploy, smoke, or API publication artifacts. JSON diagnostics preserve JSON shape while applying the same redaction to string values and object keys, so command-line fragments embedded inside maps do not persist secrets. The same pass normalizes local `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, and `/private/var/folders/...` paths into basename-scoped `[local-path]/...` or `[runtime-path]/...` labels before diagnostic text is persisted. Public trader route response bodies are redacted and capped before being copied into trader smoke evidence. Trader API SoraFS pin/registry summary and response files are redacted before reuse, and CID probe bodies plus retained probe body/error files are redacted and capped before they are written to evidence. Local console and trader access logs redact the same sensitive query-parameter values, including JSON-like query payloads containing sensitive keys, and truncate long non-sensitive query values before writing request lines to stderr.
- Public mutations require environment-specific consent at console startup: `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` for `testnet`, or `SORASWAP_ALLOW_PRODUCTION_MUTATIONS=1` for `production`.
- Taira bridge proof/message submissions accept only the expected top-level bundle, settlement, authority, and gas fields; bridge message submission rejects caller-supplied `settlement.payload` for proof-managed entrypoints, so the operator path must stay proof-driven.
- The public release checklist requires `contract_console_smoke.latest.json` to prove a proof-driven `finalize_inbound` submission with `proof_driven_settlement == true` and `settlement_payload_supplied == false`.
- Bridge submission status evidence is exact: apply-path proof and message statuses must be `Applied` or `Committed`, replay fallback must include replay/duplicate/consumed/proof-overlap detail or the current bridge-contract assertion text, and substring values such as `NotApplied` or generic `Rejected` records do not satisfy the release gate.
- Browser POST APIs reject caller-supplied private-key, secret, mnemonic, token/API-key, authorization, password, and passphrase fields at any nesting level, including read-only view and bridge-inspection requests. Confirmation previews and backend proxy response echoes recursively redact the same fields before rendering operator-visible JSON.
- History-like read proxies cap raw GET query strings at `4096` characters and `32` parsed fields, then cap SCCP recent-message and remote transaction-history reads at `100` rows per request, with `from` and `offset` capped at `10000`.
- The shared local JSON proxy parser requires non-empty POST bodies to use `application/json` or `application/*+json`; it rejects malformed `Content-Length` values, invalid UTF-8 bodies, and bodies larger than `1 MiB` before reading request content. Browser/API gas limits must be integers from `1` through `50000000`, and local Torii proxy responses are capped at `10 MiB` before decoding.
- Static UI, JSON API, and trader SSE responses carry `no-store`, `nosniff`, `DENY` frame, `no-referrer`, same-origin cross-origin, restrictive permissions, and self-hosted CSP headers.
- Authenticated upstream responses are rejected with a generic local error if they echo the bound Basic password/header token or any signer material inserted by the backend; echoed credentials are never returned to browser JSON.
- Production shell HTTP calls apply the same exact-secret echo check to captured stdout, stderr, and explicit curl output files before copying or replaying them; curl trace, remote-name, external header-dump, and stderr-file escapes are rejected for authenticated requests.
- Production signer configuration is accepted only from a canonical, non-symlink, single-link, mode-`0600` file owned by the effective user inside the checkout; the file must also be Git-ignored and untracked.
- The browser UI includes a clear-all operator-state action for recent signed actions, tracked transaction statuses, bridge bookmarks, and SCCP proof lookup history stored in `localStorage`.

## Reviewed Risks

### Signer Precedence
- Risk: operator binds the right signer config but accidentally targets the wrong Torii URL.
- Current posture: deployment record wins over signer-config Torii URL; mismatches are surfaced as warnings in the catalog and UI. Mutation-enabled public sessions also fail startup on stale local evidence, wrong Torii provenance, unsupported nested-call probes, incomplete deploy phases, degraded contract snapshots, stale, path-leaking, or sensitive-diagnostic-bearing aggregate bundle receipts, or a non-release migration ledger before binding the local server.
- Residual risk: a freshly generated but operationally wrong deployment record can still point operators at the wrong chain.
- Required practice: regenerate Taira evidence after chain resets and inspect `chain.latest.json`, `preflight.latest.json`, `nested_call_probe.latest.json`, `deploy.latest.json`, `contracts.latest.json`, and `docs/parity/migration_register.md` before enabling public mutations.

### Private-Key Exposure
- Risk: operators paste signing material into the browser JSON editors, browser history, logs, screenshots, or clipboard.
- Current posture: browser JSON may not include private-key, secret, mnemonic, token/API-key, authorization, password, or passphrase fields at any nesting level; the backend rejects those fields and requires signing material from a bound signer config. The catalog snapshot reports only basename/repo-relative path labels, a signer config basename, basename-scoped source/warning labels, and boolean Basic Auth presence, not secret values or parent directories. Signer derivation warnings normalize local `/Users/...`, `/tmp/...`, `/private/tmp/...`, `/var/folders/...`, and `/private/var/folders/...` paths before catalog exposure. Shell release helpers and local access logs redact the same normalized sensitive keys before recording upstream error text or request lines.
- Residual risk: signer configs on disk remain sensitive and browser screenshots may still expose authorities, tx hashes, and payloads.
- Required practice: keep signer configs untracked, stored outside the repo when possible, and never shared through the browser editors.

### localStorage Contents
- Risk: route ids, message ids, recent requests, and transaction tracking state persist in browser `localStorage`.
- Stored today: bridge bookmarks, recent request metadata, tracked transaction state, and SCCP proof lookup history.
- Not stored today: signer private keys.
- Residual risk: workstation compromise, browser sync, or shared browser profiles can expose operator context before local state is cleared.
- Required practice: use a dedicated browser profile for the console and run **Clear Operator State** after sensitive sessions.

### JSON Submission Risks
- Risk: operators edit raw JSON into inconsistent or unsafe mutation bodies.
- Current posture: the UI validates the common bridge payload shapes, and the backend validates bundle and settlement structure.
- Residual risk: semantically incorrect but syntactically valid payloads still rely on operator review and upstream validation.
- Required practice: prefer guided builders plus live SCCP lookup, then inspect the final JSON before submission.

### Browser Session Risk
- Risk: stale tabs, autofill, session restore, or shared workstations replay operator context.
- Current posture: the console is a local server with no external auth boundary of its own.
- Residual risk: anyone with local browser access can inspect cached operator state.
- Required practice: run the console on trusted operator machines only, close the server after use, and avoid leaving mutation-enabled Taira sessions open.
