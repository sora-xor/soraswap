#!/usr/bin/env python3
"""Verify final production cutover approval and observation evidence without network I/O."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import stat
from decimal import Decimal, InvalidOperation
from pathlib import Path

import observe_production_cutover as observer


APPROVAL_EVIDENCE_SCHEMA = "soraswap-production-cutover-approval-evidence/v1"
APPROVAL_STATE_SCHEMA = "soraswap-production-cutover-approval-state/v1"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"production cutover evidence failed: {message}")


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def read_json(path: Path, label: str, expected_mode: int | None = None) -> tuple[dict, bytes]:
    raw, metadata = observer.read_regular(Path(os.path.abspath(path)), label)
    if expected_mode is not None and stat.S_IMODE(metadata.st_mode) != expected_mode:
        fail(f"{label} must have mode {expected_mode:04o}")
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        fail(f"{label} is not valid UTF-8 JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value, raw


def parse_state(raw: str, label: str) -> dict:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        fail(f"{label} is not valid JSON")
    if not isinstance(value, dict):
        fail(f"{label} must be a JSON object")
    return value


def compact_time(value: object, label: str) -> dt.datetime:
    if not isinstance(value, str):
        fail(f"{label} is missing")
    try:
        return dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(
            tzinfo=dt.timezone.utc
        )
    except ValueError:
        fail(f"{label} is not a compact UTC timestamp")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--approval-state-json", required=True)
    parser.add_argument("--soraswap-rc-state-json", required=True)
    parser.add_argument("--soraswap-source-state-json", required=True)
    parser.add_argument("--iroha-state-json", required=True)
    parser.add_argument("--chain-file", required=True)
    parser.add_argument("--deploy-file", required=True)
    parser.add_argument("--contracts-file", required=True)
    parser.add_argument("--trader-api-file", required=True)
    parser.add_argument("--approval-evidence", required=True)
    parser.add_argument("--observation-evidence", required=True)
    args = parser.parse_args()

    root_input = Path(os.path.abspath(args.root))
    try:
        root_metadata = root_input.lstat()
    except OSError:
        fail("release root is missing")
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        fail("release root must be a real directory")
    root = root_input.resolve(strict=True)
    if root != root_input:
        fail("release root path must not traverse links")
    expected_approval = root / "deployments/production/cutover_approval.latest.json"
    expected_observation = root / "deployments/production/observation.latest.json"
    if Path(os.path.abspath(args.approval_evidence)) != expected_approval \
            or Path(os.path.abspath(args.observation_evidence)) != expected_observation:
        fail("approval and observation evidence must use the canonical production latest paths")

    approval = parse_state(args.approval_state_json, "approval state")
    rc_state = parse_state(args.soraswap_rc_state_json, "SoraSwap RC state")
    source_state = parse_state(args.soraswap_source_state_json, "SoraSwap source state")
    iroha_state = parse_state(args.iroha_state_json, "Iroha state")
    if approval.get("schema") != APPROVAL_STATE_SCHEMA:
        fail("approval state schema is invalid")
    if observer.parse_time(approval.get("expires_at"), "approval expiry") <= dt.datetime.now(dt.timezone.utc):
        fail("signed cutover approval expired before final evidence verification")

    approval_evidence, _ = read_json(
        expected_approval, "cutover approval evidence", 0o600
    )
    if approval_evidence.get("schema") != APPROVAL_EVIDENCE_SCHEMA \
            or approval_evidence.get("status") != "verified" \
            or approval_evidence.get("test_only") is not False:
        fail("cutover approval evidence is not a verified production artifact")
    approval_generated_at = compact_time(
        approval_evidence.get("generated_at"), "approval evidence generated_at"
    )
    approval_from_evidence = dict(approval_evidence)
    approval_from_evidence.pop("status", None)
    approval_from_evidence.pop("generated_at", None)
    approval_from_evidence.pop("test_only", None)
    approval_from_evidence["schema"] = APPROVAL_STATE_SCHEMA
    if approval_from_evidence != approval:
        fail("approval evidence differs from the current signed approval state")

    chain, chain_bytes = read_json(Path(args.chain_file), "production chain evidence")
    deploy, deploy_bytes = read_json(Path(args.deploy_file), "production deploy evidence")
    contracts, contracts_bytes = read_json(
        Path(args.contracts_file), "production contracts evidence"
    )
    trader, trader_bytes = read_json(
        Path(args.trader_api_file), "production trader API evidence"
    )
    observation, _ = read_json(expected_observation, "production observation evidence", 0o600)
    fingerprint = observer.chain_fingerprint(chain)
    source_hash = hashlib.sha256(canonical_bytes(source_state)).hexdigest()
    expected_routes_hash = observer.routes_sha256(trader.get("routes"))
    expected_bindings = {
        "chain_fingerprint": fingerprint,
        "soraswap_git_sha": rc_state.get("git_sha"),
        "soraswap_tree_sha": rc_state.get("tree_sha"),
        "soraswap_source_sha256": source_hash,
        "iroha_git_sha": iroha_state.get("iroha_git_sha"),
        "iroha_state_sha256": hashlib.sha256(canonical_bytes(iroha_state)).hexdigest(),
        "approval_id": approval.get("approval_id"),
        "approval_sha256": approval.get("approval_sha256"),
        "policy_sha256": approval.get("policy_sha256"),
        "deploy_generated_at": deploy.get("generated_at"),
        "deploy_sha256": hashlib.sha256(deploy_bytes).hexdigest(),
        "contracts_generated_at": contracts.get("generated_at"),
        "contracts_sha256": hashlib.sha256(contracts_bytes).hexdigest(),
        "trader_api_generated_at": trader.get("generated_at"),
        "trader_api_sha256": hashlib.sha256(trader_bytes).hexdigest(),
        "trader_api_content_cid": trader.get("content_cid"),
        "trader_api_app_id": trader.get("app_id"),
        "trader_api_routes_sha256": expected_routes_hash,
    }
    if fingerprint is None or observation.get("bindings") != expected_bindings:
        fail("observation does not bind the exact current chain/RC/Iroha/deploy/contracts/trader state")
    if approval.get("bindings", {}).get("chain_fingerprint") != fingerprint:
        fail("observation chain differs from the signed approval")

    if observation.get("schema") != observer.SCHEMA \
            or observation.get("status") != "completed" \
            or observation.get("environment") != "production" \
            or observation.get("test_only") is not False:
        fail("observation is not completed non-test production evidence")
    generated_at = compact_time(observation.get("generated_at"), "observation generated_at")
    if generated_at < approval_generated_at:
        fail("observation predates the cutover approval evidence")
    exact_controls = {
        "required_duration_seconds": observer.DURATION_SECONDS,
        "required_interval_seconds": observer.INTERVAL_SECONDS,
        "required_minimum_samples": observer.MINIMUM_SAMPLES,
        "sample_count": observer.MINIMUM_SAMPLES,
    }
    for key, expected in exact_controls.items():
        if observation.get(key) != expected:
            fail(f"observation {key} differs from the fixed production control")
    if not isinstance(observation.get("observed_duration_seconds"), int) \
            or observation["observed_duration_seconds"] < observer.DURATION_SECONDS:
        fail("observation duration is shorter than thirty minutes")
    expected_summary = {
        "validator_qc_finality_agreement": True,
        "queues_drained": True,
        "api_failures": 0,
        "oracle_fresh": True,
        "minimum_fee_preserved": True,
        "readonly_routes_stable": True,
        "trader_api_cid_stable": True,
        "shared_derivatives_pause_outcome": "not_required",
        "shared_derivatives_pause_boundary": "external_fail_closed",
    }
    if observation.get("summary") != expected_summary:
        fail("observation summary is incomplete or claims an unsupported pause outcome")

    samples = observation.get("samples")
    if not isinstance(samples, list) or len(samples) != observer.MINIMUM_SAMPLES:
        fail("observation must contain exactly 61 production samples")
    try:
        minimum_fee = Decimal(approval["minimum_fee_balance"])
    except (KeyError, InvalidOperation):
        fail("approved minimum fee is invalid")
    maximum_oracle_age = approval.get("observation", {}).get(
        "maximum_oracle_age_seconds"
    )
    if not isinstance(maximum_oracle_age, int):
        fail("approved oracle freshness bound is invalid")
    expected_manifest = {
        "schema_version": 1,
        "app_id": trader.get("app_id"),
        "content_cid": trader.get("content_cid"),
        "manifest_digest_hex": trader.get("manifest_digest_hex"),
        "routes": trader.get("routes"),
    }
    expected_manifest_hash = hashlib.sha256(canonical_bytes(expected_manifest)).hexdigest()
    previous_time = None
    previous_sequence = None
    sample_times = []
    validator_ids = None
    baseline_watched_balances = None
    for index, sample in enumerate(samples, 1):
        if not isinstance(sample, dict):
            fail(f"sample {index} is not a JSON object")
        balances = observer.validate_sample(
            sample,
            index,
            maximum_oracle_age,
            minimum_fee,
            approval,
            previous_time,
            previous_sequence,
        )
        watched_balances = {
            key: amount for key, (kind, amount) in balances.items() if kind == "watched"
        }
        if baseline_watched_balances is None:
            baseline_watched_balances = watched_balances
        elif watched_balances != baseline_watched_balances:
            fail(f"sample {index} watched production balances changed")
        if sample.get("trader_api", {}).get("manifest_sha256") != expected_manifest_hash:
            fail(f"sample {index} trader API manifest hash differs from current evidence")
        current_ids = [item.get("id") for item in sample.get("validators", [])]
        if validator_ids is None:
            validator_ids = current_ids
        elif current_ids != validator_ids:
            fail(f"sample {index} validator set or ordering changed")
        sampled_at = observer.parse_time(sample.get("sampled_at"), f"sample {index} sampled_at")
        sample_times.append(sampled_at)
        previous_time = observer.parse_time(
            sample.get("monitoring_sampled_at"), f"sample {index} monitoring_sampled_at"
        )
        previous_sequence = sample.get("monitoring_sequence")
    if any(
        later <= earlier or not 25 <= (later - earlier).total_seconds() <= 45
        for earlier, later in zip(sample_times, sample_times[1:])
    ):
        fail("observation sample cadence is invalid")
    if (sample_times[-1] - sample_times[0]).total_seconds() < observer.DURATION_SECONDS:
        fail("observation sample timestamps span less than thirty minutes")
    if samples[-1]["commit_qc_height"] <= samples[0]["commit_qc_height"]:
        fail("production finality did not advance during observation")
    if observation.get("started_at") != samples[0].get("sampled_at") \
            or observation.get("completed_at") != samples[-1].get("sampled_at"):
        fail("observation start/completion timestamps do not match its samples")
    if generated_at < sample_times[-1]:
        fail("observation evidence was generated before its final sample")

    sensitive = re.compile(
        r"(?i)(authorization\s*[:=]\s*(?:basic|bearer)\s+|"
        r"\b(?:basic_auth|web_login|password|private_key|privatekey|secret|token)\b)"
    )

    def strings(value):
        if isinstance(value, str):
            yield value
        elif isinstance(value, list):
            for item in value:
                yield from strings(item)
        elif isinstance(value, dict):
            for key, item in value.items():
                yield str(key)
                yield from strings(item)

    if any(sensitive.search(value) for value in strings(approval_evidence)) \
            or any(sensitive.search(value) for value in strings(observation)):
        fail("cutover evidence contains Basic-auth or secret-bearing diagnostics")

    print(json.dumps({
        "status": "verified",
        "approval_id": approval.get("approval_id"),
        "observation_generated_at": observation.get("generated_at"),
        "sample_count": len(samples),
    }, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
