# Contract Console Security Review

## Scope
- `scripts/serve_contract_console.py`
- `ui/contract_console/`
- operator workflows for contract calls, SCCP discovery, proof lookup, and bridge submission

## Current Controls
- Deployment records are the canonical Torii source. Signer configs may add authority, signing material, and auth headers, but they do not override deployment Torii URLs.
- Browser requests cannot supply a `private_key`; the backend rejects that field and requires a bound signer config instead.
- `testnet` mutations require `SORASWAP_ALLOW_TESTNET_MUTATIONS=1` at console startup.
- Taira bridge message submission rejects caller-supplied `settlement.payload`; the operator path must stay proof-driven.
- Request previews redact top-level `private_key` before rendering responses.

## Reviewed Risks

### Signer Precedence
- Risk: operator binds the right signer config but accidentally targets the wrong Torii URL.
- Current posture: deployment record wins over signer-config Torii URL; mismatches are surfaced as warnings in the catalog and UI.
- Residual risk: stale or incorrect deployment records can still point operators at the wrong chain.
- Required practice: regenerate Taira evidence after chain resets and inspect `chain.latest.json` before release.

### Private-Key Exposure
- Risk: operators paste signing material into the browser JSON editors, browser history, logs, screenshots, or clipboard.
- Current posture: browser JSON may not include `private_key`; the backend rejects it.
- Residual risk: signer configs on disk remain sensitive and browser screenshots may still expose authorities, tx hashes, and payloads.
- Required practice: keep signer configs untracked, stored outside the repo when possible, and never shared through the browser editors.

### localStorage Contents
- Risk: route ids, message ids, recent requests, and transaction tracking state persist in browser `localStorage`.
- Stored today: bridge bookmarks, recent request metadata, and tracked transaction state.
- Not stored today: signer private keys.
- Residual risk: workstation compromise or shared browser profiles expose operator context and bridge identifiers.
- Required practice: use a dedicated browser profile for the console and clear local state after sensitive sessions.

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

## Follow-Up Items
- Add automated checks for stale deployment evidence before serving a mutation-enabled Taira session.
- Consider a dedicated “clear all operator state” UI action that wipes bookmarks, history, and tracked transactions together.
- Keep the bridge release claim tied to the proof-driven Taira path and do not accept raw settlement payload fallback as production evidence.
