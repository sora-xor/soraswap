#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import signal
import socketserver
import sys
import tempfile
import threading
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = REPO_ROOT / "scripts" / "serve_trader_ui.py"
MODULE_NAME = "soraswap_trader_fixture_server"

if str(MODULE_PATH.parent) not in sys.path:
    sys.path.insert(0, str(MODULE_PATH.parent))

spec = importlib.util.spec_from_file_location(MODULE_NAME, MODULE_PATH)
trader_ui = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[MODULE_NAME] = trader_ui
spec.loader.exec_module(trader_ui)


FIXTURE_ROUTER_ADDRESS = "tairac1fixturerouter00000000000000000000000000000000000"
FIXTURE_N3X_ADDRESS = "tairac1fixturen3x000000000000000000000000000000000000"
FIXTURE_PERPS_ADDRESS = "tairac1fixtureperps000000000000000000000000000000000"
FIXTURE_FARMS_ADDRESS = "tairac1fixturefarms000000000000000000000000000000000"
FIXTURE_LAUNCHPAD_ADDRESS = "tairac1fixturelaunchpad00000000000000000000000000000"
FIXTURE_OPTIONS_MANAGER_ADDRESS = "tairac1fixtureoptmgr000000000000000000000000000000"
FIXTURE_OPTIONS_FACTORY_ADDRESS = "tairac1fixtureoptfactory000000000000000000000000000"
FIXTURE_COVER_ADDRESS = "tairac1fixturecover000000000000000000000000000000000"
FIXTURE_INTENTS_ADDRESS = "tairac1fixtureintents000000000000000000000000000000"
FIXTURE_VAULTS_ADDRESS = "tairac1fixturevaults0000000000000000000000000000000"
FIXTURE_OPERATORS_ADDRESS = "tairac1fixtureoperators0000000000000000000000000000"
FIXTURE_MARGIN_ADDRESS = "tairac1fixturemargin00000000000000000000000000000"
FIXTURE_RWA_ADDRESS = "tairac1fixturerwa0000000000000000000000000000000"
FIXTURE_DLMM_HOOKS_ADDRESS = "tairac1fixturehooks000000000000000000000000000000"

FIXTURE_AUTHORITY = "i105fixturetrader@universal"
OTHER_AUTHORITY = "i105othertrader@universal"

BASE_ASSET_ID = "xor#universal"
QUOTE_ASSET_ID = "usdt#soraswap.universal"
USDC_ASSET_ID = "usdc#soraswap.universal"
KUSD_ASSET_ID = "kusd#soraswap.universal"
N3X_ASSET_ID = "n3x#soraswap.universal"

CONTRACTS = [
    {
        "contract_key": "dlmm.dlmm_router",
        "contract_source": "contracts/dlmm/dlmm_router.ko",
        "contract_address": FIXTURE_ROUTER_ADDRESS,
        "deploy_nonce": 4,
    },
    {
        "contract_key": "n3x.n3x_hub",
        "contract_source": "contracts/n3x/n3x_hub.ko",
        "contract_address": FIXTURE_N3X_ADDRESS,
        "deploy_nonce": 5,
    },
    {
        "contract_key": "perps.perps_engine",
        "contract_source": "contracts/perps/perps_engine.ko",
        "contract_address": FIXTURE_PERPS_ADDRESS,
        "deploy_nonce": 6,
    },
    {
        "contract_key": "farms.farm",
        "contract_source": "contracts/farms/farm.ko",
        "contract_address": FIXTURE_FARMS_ADDRESS,
        "deploy_nonce": 7,
    },
    {
        "contract_key": "launchpad.sale_factory",
        "contract_source": "contracts/launchpad/sale_factory.ko",
        "contract_address": FIXTURE_LAUNCHPAD_ADDRESS,
        "deploy_nonce": 8,
    },
    {
        "contract_key": "options.manager",
        "contract_source": "contracts/options/manager.ko",
        "contract_address": FIXTURE_OPTIONS_MANAGER_ADDRESS,
        "deploy_nonce": 9,
    },
    {
        "contract_key": "options.factory",
        "contract_source": "contracts/options/factory.ko",
        "contract_address": FIXTURE_OPTIONS_FACTORY_ADDRESS,
        "deploy_nonce": 10,
    },
    {
        "contract_key": "cover.policy_manager",
        "contract_source": "contracts/cover/policy_manager.ko",
        "contract_address": FIXTURE_COVER_ADDRESS,
        "deploy_nonce": 11,
    },
    {
        "contract_key": "intents.settlement_router",
        "contract_source": "contracts/intents/settlement_router.ko",
        "contract_address": FIXTURE_INTENTS_ADDRESS,
        "deploy_nonce": 12,
    },
    {
        "contract_key": "vaults.manager",
        "contract_source": "contracts/vaults/manager.ko",
        "contract_address": FIXTURE_VAULTS_ADDRESS,
        "deploy_nonce": 13,
    },
    {
        "contract_key": "operators.registry",
        "contract_source": "contracts/operators/registry.ko",
        "contract_address": FIXTURE_OPERATORS_ADDRESS,
        "deploy_nonce": 14,
    },
    {
        "contract_key": "margin.portfolio_margin",
        "contract_source": "contracts/margin/portfolio_margin.ko",
        "contract_address": FIXTURE_MARGIN_ADDRESS,
        "deploy_nonce": 15,
    },
    {
        "contract_key": "rwa.market",
        "contract_source": "contracts/rwa/market.ko",
        "contract_address": FIXTURE_RWA_ADDRESS,
        "deploy_nonce": 16,
    },
    {
        "contract_key": "dlmm_hooks.hook_manager",
        "contract_source": "contracts/dlmm_hooks/hook_manager.ko",
        "contract_address": FIXTURE_DLMM_HOOKS_ADDRESS,
        "deploy_nonce": 17,
    },
]

ALIAS_TO_ADDRESS = {contract["contract_key"]: contract["contract_address"] for contract in CONTRACTS}
ADDRESS_TO_ALIAS = {contract["contract_address"]: contract["contract_key"] for contract in CONTRACTS}
MODULE_TO_CONTRACT_KEY = {
    "swaps": "dlmm.dlmm_router",
    "n3x": "n3x.n3x_hub",
    "perps": "perps.perps_engine",
    "farms": "farms.farm",
    "launchpad": "launchpad.sale_factory",
    "options": "options.factory",
    "cover": "cover.policy_manager",
    "intents": "intents.settlement_router",
    "vaults": "vaults.manager",
    "operators": "operators.registry",
    "margin": "margin.portfolio_margin",
    "rwa": "rwa.market",
    "dlmmHooks": "dlmm_hooks.hook_manager",
}
MODULE_LABELS = {
    "swaps": "Swaps",
    "n3x": "n3x",
    "perps": "Perps",
    "farms": "Farms",
    "launchpad": "Launchpad",
    "options": "Options",
    "cover": "Cover",
    "intents": "Intents",
    "vaults": "Vaults",
    "operators": "Operators",
    "margin": "Margin",
    "rwa": "RWA",
    "dlmmHooks": "DLMM Hooks",
}
MODULE_ORDER = [
    "swaps",
    "n3x",
    "perps",
    "farms",
    "launchpad",
    "options",
    "cover",
    "intents",
    "vaults",
    "operators",
    "margin",
    "rwa",
    "dlmmHooks",
]
ALIAS_TO_MODULE = {
    "dlmm.dlmm_router": "swaps",
    "n3x.n3x_hub": "n3x",
    "perps.perps_engine": "perps",
    "farms.farm": "farms",
    "launchpad.sale_factory": "launchpad",
    "options.manager": "options",
    "options.factory": "options",
    "cover.policy_manager": "cover",
    "intents.settlement_router": "intents",
    "vaults.manager": "vaults",
    "operators.registry": "operators",
    "margin.portfolio_margin": "margin",
    "rwa.market": "rwa",
    "dlmm_hooks.hook_manager": "dlmmHooks",
}
ENTRYPOINT_TO_EVENT_KIND = {
    "route_swap": "swap_executed",
    "deposit_and_mint": "n3x_minted",
    "burn_and_redeem": "n3x_redeemed",
    "open_position": "perps_position_opened",
    "modify_position": "perps_position_modified",
    "add_margin": "perps_margin_added",
    "remove_margin": "perps_margin_removed",
    "close_position": "perps_position_closed",
    "sync_funding": "perps_funding_synced",
    "run_liquidation_pass": "perps_liquidation_pass",
    "stake": "farm_staked",
    "unstake": "farm_unstaked",
    "claim": "farm_rewards_claimed",
    "contribute": "launchpad_contributed",
    "claim_allocation": "launchpad_claimed",
    "refund_allocation": "launchpad_refunded",
    "finalize_sale_activation": "launchpad_activation_finalized",
    "create_series": "options_series_created",
    "buy_shout": "options_position_bought",
    "buy_outperformance": "options_position_bought",
    "record_shout": "options_shout_recorded",
    "exercise_shout_position": "options_position_exercised",
    "exercise_outperformance_position": "options_position_exercised",
    "settle_series": "options_series_settled",
    "register_policy": "cover_policy_opened",
    "record_observation": "cover_observation_recorded",
    "route_claim": "cover_claim_routed",
    "expire_policy": "cover_policy_expired",
    "open_intent": "intent_opened",
    "cancel_intent": "intent_cancelled",
    "fill_intent": "intent_filled",
    "register_vault": "vault_registered",
    "deposit": "vault_deposited",
    "request_redeem": "vault_redeem_requested",
    "claim_redeem": "vault_redeem_claimed",
    "register_operator": "operator_registered",
    "bond": "operator_bonded",
    "heartbeat": "operator_heartbeat",
    "claim_fees": "operator_fees_claimed",
    "register_market": "margin_market_registered",
    "deposit_collateral": "margin_collateral_deposited",
    "withdraw_collateral": "margin_collateral_withdrawn",
    "lock_exposure": "margin_exposure_locked",
    "liquidate_account": "margin_account_liquidated",
    "issue_lot": "rwa_lot_issued",
    "bind_share_asset": "rwa_share_asset_bound",
    "report_nav": "rwa_nav_reported",
    "request_redemption": "rwa_redemption_requested",
    "settle_redemption": "rwa_redemption_settled",
    "configure_hook_policy": "dlmm_hook_configured",
    "place_limit_order": "dlmm_hook_limit_order_placed",
    "schedule_twamm": "dlmm_hook_twamm_scheduled",
    "record_execution": "dlmm_hook_execution_recorded",
}
SUPPORTED_ENTRYPOINTS = set(ENTRYPOINT_TO_EVENT_KIND)
DEFAULT_BUCKET_MS = 900_000


class FastThreadingHTTPServer(ThreadingHTTPServer):
    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = port


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any] | list[Any] | Any) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def build_fixture_repo(root: Path, torii_url: str) -> None:
    (root / "ui").mkdir(parents=True, exist_ok=True)
    os.symlink(REPO_ROOT / "ui" / "trader", root / "ui" / "trader", target_is_directory=True)

    (root / "config").mkdir(parents=True, exist_ok=True)
    (root / "config" / "fixture.client.toml").write_text(
        "\n".join(
            [
                '[chain]',
                'id = "fixture-chain"',
                "",
                "[torii]",
                f'url = "{torii_url}"',
                "",
                "[account]",
                f'authority = "{FIXTURE_AUTHORITY}"',
                "",
            ]
        ),
        encoding="utf-8",
    )

    environment_root = root / "deployments" / "fixture"
    write_json(
        environment_root / "chain.latest.json",
        {
            "torii_url": torii_url,
            "chain": "fixture-chain",
            "block_1_hash": "fixture-block-1",
        },
    )
    write_json(
        environment_root / "contracts.latest.json",
        {
            "generated_at": "20260415T000000Z",
            "chain_fingerprint": {
                "torii_url": torii_url,
                "chain": "fixture-chain",
                "block_1_hash": "fixture-block-1",
            },
            "contracts": [
                {
                    **contract,
                    "dataspace": "universal",
                    "instance": {
                        "verification": "transaction_and_manifest",
                        "tx_hash_hex": f"{contract['deploy_nonce']:064x}",
                    },
                }
                for contract in CONTRACTS
            ],
        },
    )


def parse_int(query: dict[str, list[str]], key: str, default: int) -> int:
    raw = str((query.get(key) or [str(default)])[0] or str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def parse_str(query: dict[str, list[str]], key: str) -> str:
    return str((query.get(key) or [""])[0] or "").strip()


def format_amount(value: float, digits: int = 4) -> str:
    if abs(value) >= 1000:
        return f"{value:,.{digits}f}".rstrip("0").rstrip(".")
    return f"{value:.{digits}f}".rstrip("0").rstrip(".")


def format_signed_amount(value: float, symbol: str) -> str:
    sign = "+" if value > 0 else "-" if value < 0 else ""
    return f"{sign}{format_amount(abs(value), 4)} {symbol}"


def format_timestamp_label(timestamp_ms: int | None) -> str:
    if not timestamp_ms:
        return "-"
    return f"T+{timestamp_ms // 60000}m"


def asset_ticker(asset_id: str) -> str:
    return str(asset_id or "?").split("#")[0].upper()


def humanize_event_kind(event_kind: str) -> str:
    return " ".join(segment.capitalize() for segment in event_kind.split("_") if segment)


class MockToriiState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.sse_condition = threading.Condition()
        self.sse_sequence = 0
        self.sse_payload: dict[str, Any] = {"kind": "bootstrap"}
        self.next_record_id = 0
        self.next_timestamp_ms = 1_713_850_000_000
        self.next_hash_counter = 0
        self.swap_records: list[dict[str, Any]] = []
        self.contract_events: list[dict[str, Any]] = []
        self.activities: list[dict[str, Any]] = []
        self.status_by_hash: dict[str, dict[str, Any]] = {}

        self.seed()

    def seed(self) -> None:
        self.append_swap_fill(FIXTURE_AUTHORITY, 1, 100, 98, 95)
        self.append_swap_fill(FIXTURE_AUTHORITY, 1, 120, 111, 108)
        self.append_swap_fill(OTHER_AUTHORITY, 1, 90, 83, 80)
        self.append_swap_fill(FIXTURE_AUTHORITY, 0, 60, 68, 64)

        self.append_event("n3x.n3x_hub", "deposit_and_mint", FIXTURE_AUTHORITY, {
            "usdt_in": 160,
            "usdc_in": 40,
            "kusd_in": 20,
            "amount": 220,
        })
        self.append_event("perps.perps_engine", "open_position", FIXTURE_AUTHORITY, {
            "market_id": 1,
            "position_id": 7,
            "size": 480,
            "margin": 110,
        })
        self.append_event("farms.farm", "stake", FIXTURE_AUTHORITY, {
            "position": "yield-alpha",
            "amount": 550,
        })
        self.append_event("launchpad.sale_factory", "contribute", FIXTURE_AUTHORITY, {
            "sale": "seed-alpha",
            "allocation": "alloc-alpha",
            "payment_amount": 420,
            "amount": 420,
        })
        self.append_event("options.factory", "buy_shout", FIXTURE_AUTHORITY, {
            "series_id": 12,
            "position_id": 77,
            "notional": 260,
            "premium_paid": 18,
            "collateral_locked": 104,
        })
        self.append_event("cover.policy_manager", "register_policy", FIXTURE_AUTHORITY, {
            "policy_id": 5,
            "covered_notional": 900,
            "notional": 900,
            "payout_amount": 240,
            "premium_paid": 30,
        })

    def next_hash_hex(self) -> str:
        self.next_hash_counter += 1
        return f"{self.next_hash_counter:064x}"

    def next_timestamp(self) -> int:
        timestamp = self.next_timestamp_ms
        self.next_timestamp_ms += 30_000
        return timestamp

    def notify_sse(self, payload: dict[str, Any]) -> None:
        with self.sse_condition:
            self.sse_sequence += 1
            self.sse_payload = payload
            self.sse_condition.notify_all()

    def next_sse_frame(self, last_sequence: int, timeout: float = 1.0) -> tuple[int, dict[str, Any] | None]:
        with self.sse_condition:
            if self.sse_sequence <= last_sequence:
                self.sse_condition.wait(timeout=timeout)
            if self.sse_sequence > last_sequence:
                return self.sse_sequence, dict(self.sse_payload)
            return last_sequence, None

    def append_swap_fill(
        self,
        authority: str,
        input_is_base: int,
        amount_in: int,
        amount_out: int,
        min_out: int,
    ) -> dict[str, Any]:
        self.next_record_id += 1
        timestamp_ms = self.next_timestamp()
        tx_hash_hex = self.next_hash_hex()
        record = {
            "record_id": self.next_record_id,
            "authority": authority,
            "input_is_base": input_is_base,
            "amount_in": amount_in,
            "amount_out": amount_out,
            "min_out": min_out,
            "timestamp_ms": timestamp_ms,
            "tx_hash_hex": tx_hash_hex,
        }
        self.swap_records.append(record)
        self.append_event(
            "dlmm.dlmm_router",
            "route_swap",
            authority,
            {
                "amount_in": amount_in,
                "amount_out": amount_out,
                "input_is_base": input_is_base,
                "min_out": min_out,
            },
            timestamp_ms=timestamp_ms,
            tx_hash_hex=tx_hash_hex,
        )
        return record

    def append_event(
        self,
        contract_alias: str,
        entrypoint: str,
        authority: str,
        payload: dict[str, Any],
        *,
        timestamp_ms: int | None = None,
        tx_hash_hex: str | None = None,
    ) -> dict[str, Any]:
        module = ALIAS_TO_MODULE[contract_alias]
        contract_address = ALIAS_TO_ADDRESS[contract_alias]
        event_kind = ENTRYPOINT_TO_EVENT_KIND[entrypoint]
        timestamp_ms = timestamp_ms or self.next_timestamp()
        tx_hash_hex = tx_hash_hex or self.next_hash_hex()
        numeric_fields = {
            key: value
            for key, value in payload.items()
            if isinstance(value, (int, float))
        }
        asset_ids = sorted({
            BASE_ASSET_ID,
            *[
                str(value)
                for value in payload.values()
                if isinstance(value, str) and "#" in value
            ],
        })
        event = {
            "event_id": f"{tx_hash_hex}:0",
            "schema_version": 1,
            "provenance": "emitted",
            "authority": authority,
            "timestamp_ms": timestamp_ms,
            "tx_hash_hex": tx_hash_hex,
            "block_height": max(1, len(self.contract_events) + 1),
            "block_hash_hex": f"block-{tx_hash_hex}",
            "result_ok": True,
            "contract_address": contract_address,
            "contract_alias": contract_alias,
            "module": module,
            "event_kind": event_kind,
            "participants": [authority],
            "asset_ids": asset_ids,
            "numeric_fields": numeric_fields,
            "payload": payload,
            "gas_asset_id": BASE_ASSET_ID,
            "fee_sponsor": authority,
            "gas_limit": 100000,
        }
        self.contract_events.append(event)
        self.activities.append(
            {
                "authority": authority,
                "timestamp_ms": timestamp_ms,
                "entrypoint_hash": tx_hash_hex,
                "result_ok": True,
                "contract_address": contract_address,
                "contract_alias": contract_alias,
                "contract_entrypoint": entrypoint,
                "contract_payload": payload,
                "gas_asset_id": BASE_ASSET_ID,
                "fee_sponsor": authority,
                "gas_limit": 100000,
            }
        )
        self.status_by_hash[tx_hash_hex] = {"status": {"kind": "Committed"}}
        self.notify_sse(
            {
                "event_id": event["event_id"],
                "module": module,
                "event_kind": event_kind,
                "tx_hash_hex": tx_hash_hex,
            }
        )
        return event

    def mirror_swap_history(self, record_id: int) -> list[Any] | None:
        record = next((item for item in self.swap_records if item["record_id"] == record_id), None)
        if not record:
            return None
        return [
            record["authority"],
            record["input_is_base"],
            record["amount_in"],
            record["amount_out"],
            record["min_out"],
        ]

    def view(self, contract_address: str, entrypoint: str, payload: dict[str, Any]) -> Any:
        if contract_address == FIXTURE_ROUTER_ADDRESS:
            if entrypoint == "router_assets":
                return [BASE_ASSET_ID, QUOTE_ASSET_ID]
            if entrypoint == "swap_history_head":
                return self.next_record_id
            if entrypoint == "mirror_swap_history":
                return self.mirror_swap_history(int(payload.get("record_id") or 0))
        return None

    def view_batch(self, request: dict[str, Any]) -> dict[str, Any]:
        authority = str(request.get("authority") or FIXTURE_AUTHORITY)
        items = []
        for item in request.get("items") or []:
            contract_address = str(item.get("contract_address") or "")
            contract_alias = str(item.get("contract_alias") or "")
            if not contract_address and contract_alias:
                contract_address = ALIAS_TO_ADDRESS.get(contract_alias, "")
            entrypoint = str(item.get("entrypoint") or "")
            payload = item.get("payload") if isinstance(item.get("payload"), dict) else {}
            result = self.view(contract_address, entrypoint, payload)
            items.append(
                {
                    "request_id": item.get("request_id"),
                    "ok": result is not None,
                    "dataspace": "universal",
                    "contract_address": contract_address,
                    "entrypoint": entrypoint,
                    "result": result,
                    "error": None if result is not None else "unsupported_entrypoint",
                    "authority": authority,
                }
            )
        return {"ok": True, "items": items}

    def list_activity(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority")
        contract_address = parse_str(query, "contract_address")
        contract_entrypoint = parse_str(query, "contract_entrypoint")
        result_ok = parse_str(query, "result_ok").lower() or "true"
        limit = max(1, parse_int(query, "limit", 200))
        offset = max(0, parse_int(query, "offset", 0))

        items = list(reversed(self.activities))
        if authority:
            items = [item for item in items if item["authority"] == authority]
        if contract_address:
            items = [item for item in items if item["contract_address"] == contract_address]
        if contract_entrypoint:
            items = [item for item in items if item["contract_entrypoint"] == contract_entrypoint]
        if result_ok in {"true", "false"}:
            expected = result_ok == "true"
            items = [item for item in items if bool(item["result_ok"]) == expected]
        return {"items": items[offset:offset + limit], "total": len(items)}

    def list_contract_events(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority")
        contract_address = parse_str(query, "contract_address")
        contract_alias = parse_str(query, "contract_alias")
        module = parse_str(query, "module")
        event_kind = parse_str(query, "event_kind")
        participant = parse_str(query, "participant")
        asset_id = parse_str(query, "asset_id")
        provenance = parse_str(query, "provenance")
        result_ok = parse_str(query, "result_ok").lower() or "true"
        limit = max(1, parse_int(query, "limit", 200))
        offset = max(0, parse_int(query, "offset", 0))

        items = list(reversed(self.contract_events))
        if authority:
            items = [item for item in items if item["authority"] == authority]
        if contract_address:
            items = [item for item in items if item["contract_address"] == contract_address]
        if contract_alias:
            items = [item for item in items if item["contract_alias"] == contract_alias]
        if module:
            items = [item for item in items if item["module"] == module]
        if event_kind:
            items = [item for item in items if item["event_kind"] == event_kind]
        if participant:
            items = [item for item in items if participant in item["participants"]]
        if asset_id:
            items = [item for item in items if asset_id in item["asset_ids"]]
        if provenance:
            items = [item for item in items if item["provenance"] == provenance]
        if result_ok in {"true", "false"}:
            expected = result_ok == "true"
            items = [item for item in items if bool(item["result_ok"]) == expected]
        return {"items": items[offset:offset + limit], "total": len(items)}

    def swap_fill_items(
        self,
        authority: str,
        *,
        limit: int,
        offset: int,
    ) -> list[dict[str, Any]]:
        fills = [record for record in reversed(self.swap_records) if record["authority"] == authority]
        items = []
        for record in fills[offset:offset + limit]:
            input_is_base = int(record["input_is_base"])
            amount_in = int(record["amount_in"])
            amount_out = int(record["amount_out"])
            min_out = int(record["min_out"])
            side = "buy" if input_is_base == 1 else "sell"
            price = amount_in / max(amount_out, 1) if input_is_base == 1 else amount_out / max(amount_in, 1)
            protection_ratio = ((amount_out - min_out) / min_out) if min_out > 0 else None
            items.append(
                {
                    "recordId": record["record_id"],
                    "trader": record["authority"],
                    "inputIsBase": input_is_base,
                    "amountIn": amount_in,
                    "amountOut": amount_out,
                    "minOut": min_out,
                    "side": side,
                    "price": price,
                    "protectionRatio": protection_ratio,
                    "timestampMs": record["timestamp_ms"],
                    "executionHash": record["tx_hash_hex"],
                }
            )
        return items

    def swaps_fills_rollup(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority") or FIXTURE_AUTHORITY
        limit = max(1, parse_int(query, "limit", 120))
        offset = max(0, parse_int(query, "offset", 0))
        items = self.swap_fill_items(authority, limit=limit, offset=offset)
        total = len([record for record in self.swap_records if record["authority"] == authority])
        return {
            "ok": True,
            "authority": authority,
            "contract_address": FIXTURE_ROUTER_ADDRESS,
            "contract_alias": "dlmm.dlmm_router",
            "base_asset_id": BASE_ASSET_ID,
            "quote_asset_id": QUOTE_ASSET_ID,
            "history_head": self.next_record_id,
            "scanned": total,
            "total": total,
            "items": items,
        }

    def swaps_candles_rollup(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority") or FIXTURE_AUTHORITY
        bucket_ms = max(60_000, parse_int(query, "bucket_ms", DEFAULT_BUCKET_MS))
        limit = max(1, parse_int(query, "limit", 120))
        offset = max(0, parse_int(query, "offset", 0))
        buckets: dict[int, dict[str, Any]] = {}

        for record in [item for item in self.swap_records if item["authority"] == authority]:
            timestamp_ms = int(record["timestamp_ms"])
            bucket_start_ms = timestamp_ms - (timestamp_ms % bucket_ms)
            input_is_base = int(record["input_is_base"])
            amount_in = int(record["amount_in"])
            amount_out = int(record["amount_out"])
            price = amount_in / max(amount_out, 1) if input_is_base == 1 else amount_out / max(amount_in, 1)
            entry = buckets.setdefault(
                bucket_start_ms,
                {
                    "bucketStartMs": bucket_start_ms,
                    "open": price,
                    "high": price,
                    "low": price,
                    "close": price,
                    "buyCount": 0,
                    "sellCount": 0,
                    "baseVolume": 0.0,
                    "quoteVolume": 0.0,
                },
            )
            entry["high"] = max(entry["high"], price)
            entry["low"] = min(entry["low"], price)
            entry["close"] = price
            if input_is_base == 1:
                entry["buyCount"] += 1
                entry["baseVolume"] += float(amount_in)
                entry["quoteVolume"] += float(amount_out)
            else:
                entry["sellCount"] += 1
                entry["baseVolume"] += float(amount_out)
                entry["quoteVolume"] += float(amount_in)

        items = [buckets[key] for key in sorted(buckets.keys(), reverse=True)][offset:offset + limit]
        return {
            "ok": True,
            "authority": authority,
            "bucketMs": bucket_ms,
            "items": items,
        }

    def trader_activity_items(self, authority: str, limit: int, offset: int, module: str = "") -> tuple[list[dict[str, Any]], int]:
        events = [
            event
            for event in reversed(self.contract_events)
            if event["authority"] == authority and event["module"] in MODULE_ORDER and event["result_ok"]
        ]
        if module:
            events = [event for event in events if event["module"] == module]

        items = [self.activity_item_from_event(event) for event in events]
        total = len(items)
        return items[offset:offset + limit], total

    def activity_item_from_event(self, event: dict[str, Any]) -> dict[str, Any]:
        payload = event.get("payload") or {}
        module = event["module"]
        event_kind = event["event_kind"]
        action = humanize_event_kind(event_kind)
        exposure = "-"
        context = MODULE_LABELS[module]

        if event_kind == "swap_executed":
            input_is_base = int(payload.get("input_is_base", 1))
            amount_in = int(payload.get("amount_in", 0))
            amount_out = int(payload.get("amount_out", 0))
            min_out = int(payload.get("min_out", 0))
            action = "Bought quote" if input_is_base == 1 else "Sold quote"
            exposure = f"{format_amount(amount_in, 0)} -> {format_amount(amount_out, 0)}"
            context = f"Min out {format_amount(min_out, 0)}"
        elif event_kind in {"n3x_minted", "n3x_redeemed"}:
            amount = int(payload.get("amount", payload.get("n3x_amount", 0)) or 0)
            action = "Minted n3x" if event_kind == "n3x_minted" else "Redeemed n3x"
            exposure = f"{format_amount(amount, 0)} {'basket in' if event_kind == 'n3x_minted' else 'N3X'}"
            context = "Basket rebalance"
        elif module == "perps":
            market_id = payload.get("market_id")
            position_id = payload.get("position_id")
            size = payload.get("size", payload.get("size_delta", payload.get("notional")))
            margin = payload.get("margin", payload.get("margin_delta", payload.get("amount")))
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(size), 0)} size" if isinstance(size, (int, float)) else "",
                    f"{format_amount(float(margin), 0)} margin" if isinstance(margin, (int, float)) else "",
                ]
                if part
            ) or "Perp action"
            context = " · ".join(
                part
                for part in [
                    f"Market {market_id}" if isinstance(market_id, int) else "",
                    f"Position #{position_id}" if isinstance(position_id, int) else "",
                ]
                if part
            ) or "Perps"
            action = {
                "perps_position_opened": "Opened perp",
                "perps_position_modified": "Modified perp",
                "perps_margin_added": "Added margin",
                "perps_margin_removed": "Removed margin",
                "perps_position_closed": "Closed perp",
                "perps_funding_synced": "Synced funding",
                "perps_liquidation_pass": "Liquidation pass",
            }.get(event_kind, action)
        elif module == "farms":
            amount = payload.get("amount")
            position = payload.get("position")
            exposure = format_amount(float(amount), 0) if isinstance(amount, (int, float)) else "Farm action"
            context = f"Position {position}" if isinstance(position, str) and position else "Farm position"
        elif module == "launchpad":
            sale = payload.get("sale")
            allocation = payload.get("allocation")
            amount = payload.get("amount", payload.get("payment_amount"))
            exposure = format_amount(float(amount), 0) if isinstance(amount, (int, float)) else "Launchpad action"
            context = " · ".join(part for part in [sale, allocation] if isinstance(part, str) and part) or "Launchpad"
        elif module == "options":
            series_id = payload.get("series_id")
            position_id = payload.get("position_id")
            notional = payload.get("notional")
            premium = payload.get("premium_paid")
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(notional), 0)} notional" if isinstance(notional, (int, float)) else "",
                    f"{format_amount(float(premium), 0)} premium" if isinstance(premium, (int, float)) else "",
                ]
                if part
            ) or "Option action"
            context = " · ".join(
                part
                for part in [
                    f"Series #{series_id}" if isinstance(series_id, int) else "",
                    f"Position #{position_id}" if isinstance(position_id, int) else "",
                ]
                if part
            ) or "Options"
        elif module == "cover":
            policy_id = payload.get("policy_id")
            notional = payload.get("notional", payload.get("covered_notional"))
            payout = payload.get("payout_amount")
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(notional), 0)} covered" if isinstance(notional, (int, float)) else "",
                    f"{format_amount(float(payout), 0)} payout" if isinstance(payout, (int, float)) else "",
                ]
                if part
            ) or "Policy action"
            context = f"Policy #{policy_id}" if isinstance(policy_id, int) else "Cover"
        elif module == "intents":
            intent_id = payload.get("intent_id")
            amount_in = payload.get("amount_in")
            amount_out = payload.get("amount_out")
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(amount_in), 0)} in" if isinstance(amount_in, (int, float)) else "",
                    f"{format_amount(float(amount_out), 0)} out" if isinstance(amount_out, (int, float)) else "",
                ]
                if part
            ) or "Intent action"
            context = f"Intent {intent_id}" if isinstance(intent_id, str) and intent_id else "Solver intent"
        elif module == "vaults":
            vault_id = payload.get("vault_id")
            position_id = payload.get("position_id")
            amount = payload.get("amount", payload.get("shares"))
            exposure = format_amount(float(amount), 0) if isinstance(amount, (int, float)) else "Vault action"
            context = " · ".join(part for part in [vault_id, position_id] if isinstance(part, str) and part) or "Vault position"
        elif module == "operators":
            service = payload.get("service")
            amount = payload.get("amount", payload.get("min_bond", payload.get("fees_accrued")))
            health = payload.get("health_bps")
            exposure = " · ".join(
                part
                for part in [
                    format_amount(float(amount), 0) if isinstance(amount, (int, float)) else "",
                    f"{format_amount(float(health) / 100, 2)}% health" if isinstance(health, (int, float)) else "",
                ]
                if part
            ) or "Operator action"
            context = f"Service {service}" if isinstance(service, str) and service else "Bonded operator"
        elif module == "margin":
            market_id = payload.get("market_id")
            account_key = payload.get("account_key")
            amount = payload.get("amount", payload.get("exposure_delta"))
            exposure = format_amount(float(amount), 0) if isinstance(amount, (int, float)) else "Margin action"
            context = " · ".join(part for part in [market_id, account_key] if isinstance(part, str) and part) or "Portfolio margin"
        elif module == "rwa":
            market_id = payload.get("market_id")
            redemption_id = payload.get("redemption_id")
            shares = payload.get("shares", payload.get("total_shares"))
            nav = payload.get("nav_per_share", payload.get("initial_nav_per_share"))
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(shares), 0)} shares" if isinstance(shares, (int, float)) else "",
                    f"{format_amount(float(nav), 0)} NAV" if isinstance(nav, (int, float)) else "",
                ]
                if part
            ) or "RWA action"
            context = " · ".join(part for part in [market_id, redemption_id] if isinstance(part, str) and part) or "RWA market"
        elif module == "dlmmHooks":
            hook_id = payload.get("hook_id")
            order_id = payload.get("order_id")
            amount_in = payload.get("amount_in")
            amount_out = payload.get("amount_out", payload.get("min_out"))
            exposure = " · ".join(
                part
                for part in [
                    f"{format_amount(float(amount_in), 0)} in" if isinstance(amount_in, (int, float)) else "",
                    f"{format_amount(float(amount_out), 0)} out" if isinstance(amount_out, (int, float)) else "",
                ]
                if part
            ) or "Hook action"
            context = " · ".join(part for part in [hook_id, order_id] if isinstance(part, str) and part) or "DLMM hook"

        return {
            "moduleKey": module,
            "moduleLabel": MODULE_LABELS[module],
            "timestampMs": event["timestamp_ms"],
            "action": action,
            "exposure": exposure,
            "context": context,
            "executionHash": event["tx_hash_hex"],
        }

    def trader_activity_rollup(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority") or FIXTURE_AUTHORITY
        limit = max(1, parse_int(query, "limit", 64))
        offset = max(0, parse_int(query, "offset", 0))
        module = parse_str(query, "module")
        items, total = self.trader_activity_items(authority, limit, offset, module)
        return {"ok": True, "items": items, "total": total}

    def module_rollup(self, query: dict[str, list[str]], module: str, rollup_kind: str) -> dict[str, Any]:
        authority = parse_str(query, "authority") or FIXTURE_AUTHORITY
        limit = max(1, parse_int(query, "limit", 64))
        offset = max(0, parse_int(query, "offset", 0))
        items, total = self.trader_activity_items(authority, limit, offset, module)
        return {
            "ok": True,
            "module": module,
            "moduleLabel": MODULE_LABELS[module],
            "rollupKind": rollup_kind,
            "contractKey": MODULE_TO_CONTRACT_KEY[module],
            "items": items,
            "total": total,
        }

    def compute_swap_metrics(self, authority: str) -> dict[str, Any]:
        fills = [record for record in reversed(self.swap_records) if record["authority"] == authority]
        quote_inventory = 0.0
        cost_basis_base = 0.0
        realized_pnl_base = 0.0
        total_base_spent = 0.0
        total_base_realized = 0.0
        total_quote_bought = 0.0
        total_quote_sold = 0.0
        win_count = 0.0
        sell_count = 0.0
        cushion_ratio_sum = 0.0
        cushion_count = 0.0

        normalized_fills = self.swap_fill_items(authority, limit=max(1, len(fills)), offset=0)
        for fill in reversed(normalized_fills):
            if fill["side"] == "buy":
                total_base_spent += fill["amountIn"]
                total_quote_bought += fill["amountOut"]
                quote_inventory += fill["amountOut"]
                cost_basis_base += fill["amountIn"]
            else:
                total_base_realized += fill["amountOut"]
                total_quote_sold += fill["amountIn"]
                sell_count += 1.0
                inventory_before = quote_inventory
                basis_before = cost_basis_base
                sold_quote = min(fill["amountIn"], inventory_before)
                cost_portion = (basis_before * sold_quote) / inventory_before if inventory_before > 0 else 0.0
                trade_realized = fill["amountOut"] - cost_portion
                realized_pnl_base += trade_realized
                if trade_realized > 0:
                    win_count += 1.0
                quote_inventory = max(0.0, inventory_before - fill["amountIn"])
                cost_basis_base = max(0.0, basis_before - cost_portion)
            if isinstance(fill.get("protectionRatio"), (int, float)):
                cushion_ratio_sum += float(fill["protectionRatio"])
                cushion_count += 1.0

        avg_entry = (total_base_spent / total_quote_bought) if total_quote_bought > 0 else None
        avg_exit = (total_base_realized / total_quote_sold) if total_quote_sold > 0 else None
        last_price = normalized_fills[0]["price"] if normalized_fills else None
        unrealized_pnl_base = (
            (quote_inventory * last_price) - cost_basis_base
            if isinstance(last_price, (int, float))
            else None
        )
        total_pnl_base = realized_pnl_base + unrealized_pnl_base if unrealized_pnl_base is not None else realized_pnl_base

        return {
            "avgEntry": avg_entry,
            "avgExit": avg_exit,
            "openQuoteAmount": quote_inventory,
            "realizedPnlBase": realized_pnl_base,
            "unrealizedPnlBase": unrealized_pnl_base,
            "totalPnlBase": total_pnl_base,
            "totalBaseSpent": total_base_spent,
            "totalBaseRealized": total_base_realized,
            "lastPrice": last_price,
            "winRate": (win_count / sell_count) if sell_count > 0 else None,
            "avgCushionRatio": (cushion_ratio_sum / cushion_count) if cushion_count > 0 else None,
        }

    def build_module_cards(self, authority: str) -> list[dict[str, Any]]:
        base_symbol = asset_ticker(BASE_ASSET_ID)
        quote_symbol = asset_ticker(QUOTE_ASSET_ID)
        metrics = self.compute_swap_metrics(authority)
        fills = self.swap_fill_items(authority, limit=120, offset=0)
        activities, _ = self.trader_activity_items(authority, 64, 0)
        latest_by_module = {module: next((item for item in activities if item["moduleKey"] == module), None) for module in MODULE_ORDER}

        cards = []
        for module in MODULE_ORDER:
            contract_key = MODULE_TO_CONTRACT_KEY[module]
            contract_address = ALIAS_TO_ADDRESS.get(contract_key)
            if module == "swaps":
                cards.append(
                    {
                        "key": "swaps",
                        "label": "Swaps",
                        "contractKey": contract_key,
                        "contractAddress": contract_address,
                        "statusTone": "live" if fills else "watch",
                        "statusLabel": "Trading" if fills else "Awaiting flow",
                        "hero": format_signed_amount(metrics["totalPnlBase"], base_symbol)
                        if isinstance(metrics.get("totalPnlBase"), (int, float))
                        else "No personal PnL yet",
                        "blurb": (
                            f"Avg entry {format_amount(metrics['avgEntry'], 4)} {base_symbol} · "
                            f"Open {format_amount(metrics['openQuoteAmount'], 4)} {quote_symbol} · "
                            f"{len(fills)} executed fills"
                            if fills and isinstance(metrics.get("avgEntry"), (int, float))
                            else "The router is deployed, but this wallet has no successful fills in the visible journal window yet."
                        ),
                        "radarValue": f"{len(fills)} fills" if fills else "No fills",
                        "metrics": [
                            {
                                "label": "Avg Entry",
                                "value": f"{format_amount(metrics['avgEntry'], 4)} {base_symbol}"
                                if isinstance(metrics.get("avgEntry"), (int, float))
                                else "-",
                            },
                            {
                                "label": "Realized",
                                "value": format_signed_amount(metrics["realizedPnlBase"], base_symbol),
                            },
                            {
                                "label": "Open Quote",
                                "value": f"{format_amount(metrics['openQuoteAmount'], 4)} {quote_symbol}",
                            },
                        ],
                    }
                )
                continue

            latest = latest_by_module[module]
            if latest is None:
                cards.append(
                    {
                        "key": module,
                        "label": MODULE_LABELS[module],
                        "contractKey": contract_key,
                        "contractAddress": contract_address,
                        "statusTone": "watch",
                        "statusLabel": "Watching",
                        "hero": "No recent wallet activity",
                        "blurb": "This product is deployed, but no recent canonical trader events were found for the selected authority.",
                        "radarValue": "Watching",
                        "metrics": [
                            {"label": "Contract", "value": contract_key},
                            {"label": "Last Action", "value": "None yet"},
                            {"label": "Last Seen", "value": "-"},
                        ],
                    }
                )
                continue

            cards.append(
                {
                    "key": module,
                    "label": MODULE_LABELS[module],
                    "contractKey": contract_key,
                    "contractAddress": contract_address,
                    "statusTone": "live",
                    "statusLabel": "Live",
                    "hero": latest["exposure"],
                    "blurb": f"{latest['action']} · {latest['context']}",
                    "radarValue": latest["action"],
                    "metrics": [
                        {"label": "Latest", "value": latest["action"]},
                        {"label": "Context", "value": latest["context"]},
                        {"label": "Last Seen", "value": format_timestamp_label(latest["timestampMs"])},
                    ],
                }
            )
        return cards

    def trader_account_rollup(self, query: dict[str, list[str]]) -> dict[str, Any]:
        authority = parse_str(query, "authority") or FIXTURE_AUTHORITY
        fills = self.swap_fill_items(authority, limit=120, offset=0)
        return {
            "ok": True,
            "authority": authority,
            "assets": {
                "baseAssetId": BASE_ASSET_ID,
                "quoteAssetId": QUOTE_ASSET_ID,
            },
            "historyHead": self.next_record_id,
            "fillCount": len(fills),
            "metrics": self.compute_swap_metrics(authority),
            "modules": self.build_module_cards(authority),
        }

    def normalize_call_payload(self, entrypoint: str, payload: dict[str, Any]) -> dict[str, Any]:
        normalized = dict(payload)
        if entrypoint == "route_swap":
            normalized.setdefault("amount_in", 100)
            normalized.setdefault("input_is_base", 1)
            normalized.setdefault("min_out", 95)
        elif entrypoint == "deposit_and_mint":
            normalized.setdefault("usdt_in", 150)
            normalized.setdefault("usdc_in", 35)
            normalized.setdefault("kusd_in", 20)
            normalized.setdefault("amount", normalized["usdt_in"] + normalized["usdc_in"] + normalized["kusd_in"])
        elif entrypoint == "burn_and_redeem":
            normalized.setdefault("n3x_amount", 180)
            normalized.setdefault("amount", normalized["n3x_amount"])
        elif entrypoint == "open_position":
            normalized.setdefault("market_id", 1)
            normalized.setdefault("position_id", 8)
            normalized.setdefault("size", 520)
            normalized.setdefault("margin", 120)
        elif entrypoint == "modify_position":
            normalized.setdefault("market_id", 1)
            normalized.setdefault("position_id", 7)
            normalized.setdefault("size_delta", 40)
            normalized.setdefault("margin_delta", 10)
        elif entrypoint in {"add_margin", "remove_margin"}:
            normalized.setdefault("position_id", 7)
            normalized.setdefault("amount", 24)
        elif entrypoint == "close_position":
            normalized.setdefault("position_id", 7)
        elif entrypoint in {"stake", "unstake"}:
            normalized.setdefault("position", "yield-alpha")
            normalized.setdefault("amount", 120)
        elif entrypoint == "claim":
            normalized.setdefault("position", "yield-alpha")
            normalized.setdefault("amount", 42)
        elif entrypoint == "contribute":
            normalized.setdefault("sale", "seed-alpha")
            normalized.setdefault("allocation", "alloc-alpha")
            normalized.setdefault("payment_amount", 260)
            normalized.setdefault("amount", normalized["payment_amount"])
        elif entrypoint in {"claim_allocation", "refund_allocation"}:
            normalized.setdefault("sale", "seed-alpha")
            normalized.setdefault("allocation", "alloc-alpha")
        elif entrypoint == "buy_shout":
            normalized.setdefault("series_id", 12)
            normalized.setdefault("position_id", 79)
            normalized.setdefault("notional", 220)
            normalized.setdefault("premium_paid", 16)
            normalized.setdefault("collateral_locked", 94)
        elif entrypoint == "buy_outperformance":
            normalized.setdefault("series_id", 12)
            normalized.setdefault("position_id", 80)
            normalized.setdefault("notional", 240)
            normalized.setdefault("premium_paid", 19)
            normalized.setdefault("collateral_locked", 102)
        elif entrypoint == "record_shout":
            normalized.setdefault("position_id", 77)
            normalized.setdefault("series_id", 12)
            normalized.setdefault("shout_price", 11350)
        elif entrypoint in {"exercise_shout_position", "exercise_outperformance_position"}:
            normalized.setdefault("position_id", 77)
            normalized.setdefault("series_id", 12)
            normalized.setdefault("payout_amount", 31)
        elif entrypoint == "register_policy":
            normalized.setdefault("policy_id", 6)
            normalized.setdefault("covered_notional", 1100)
            normalized.setdefault("notional", normalized["covered_notional"])
            normalized.setdefault("payout_amount", 260)
            normalized.setdefault("premium_paid", 32)
        elif entrypoint == "route_claim":
            normalized.setdefault("policy_id", 5)
            normalized.setdefault("payout_amount", 180)
        elif entrypoint == "open_intent":
            normalized.setdefault("intent_id", "intent-1")
            normalized.setdefault("amount_in", 100)
            normalized.setdefault("min_out", 97)
            normalized.setdefault("solver_fee_bps", 25)
        elif entrypoint == "fill_intent":
            normalized.setdefault("intent_id", "intent-1")
            normalized.setdefault("amount_out", 99)
        elif entrypoint == "cancel_intent":
            normalized.setdefault("intent_id", "intent-1")
        elif entrypoint == "register_vault":
            normalized.setdefault("vault_id", "n3x-savings")
            normalized.setdefault("strategy_code", 1)
        elif entrypoint == "deposit":
            normalized.setdefault("vault_id", "n3x-savings")
            normalized.setdefault("position_id", "pos-1")
            normalized.setdefault("amount", 250)
        elif entrypoint == "request_redeem":
            normalized.setdefault("vault_id", "n3x-savings")
            normalized.setdefault("request_id", "redeem-1")
            normalized.setdefault("position_id", "pos-1")
            normalized.setdefault("shares", 40)
        elif entrypoint == "claim_redeem":
            normalized.setdefault("request_id", "redeem-1")
        elif entrypoint == "register_operator":
            normalized.setdefault("service", "solver")
            normalized.setdefault("min_bond", 1000)
        elif entrypoint == "bond":
            normalized.setdefault("service", "solver")
            normalized.setdefault("amount", 1000)
        elif entrypoint == "heartbeat":
            normalized.setdefault("service", "solver")
            normalized.setdefault("health_bps", 9700)
            normalized.setdefault("fees_accrued", 0)
        elif entrypoint == "claim_fees":
            normalized.setdefault("service", "solver")
            normalized.setdefault("fees_accrued", 12)
        elif entrypoint == "deposit_collateral":
            normalized.setdefault("account_key", "alice")
            normalized.setdefault("amount", 500)
        elif entrypoint == "withdraw_collateral":
            normalized.setdefault("account_key", "alice")
            normalized.setdefault("amount", 100)
        elif entrypoint == "lock_exposure":
            normalized.setdefault("market_id", "perps-btc")
            normalized.setdefault("account_key", "alice")
            normalized.setdefault("exposure_delta", 300)
        elif entrypoint == "liquidate_account":
            normalized.setdefault("account_key", "alice")
        elif entrypoint == "issue_lot":
            normalized.setdefault("market_id", "tbill-1")
            normalized.setdefault("initial_nav_per_share", 101)
            normalized.setdefault("total_shares", 10000)
        elif entrypoint == "report_nav":
            normalized.setdefault("market_id", "tbill-1")
            normalized.setdefault("nav_per_share", 101)
            normalized.setdefault("total_shares", 10000)
        elif entrypoint == "request_redemption":
            normalized.setdefault("market_id", "tbill-1")
            normalized.setdefault("redemption_id", "r-1")
            normalized.setdefault("shares", 250)
        elif entrypoint == "settle_redemption":
            normalized.setdefault("redemption_id", "r-1")
        elif entrypoint == "configure_hook_policy":
            normalized.setdefault("hook_id", "limit")
            normalized.setdefault("phase", 3)
            normalized.setdefault("max_fee_pips", 25)
            normalized.setdefault("enabled", 1)
        elif entrypoint == "place_limit_order":
            normalized.setdefault("order_id", "order-1")
            normalized.setdefault("hook_id", "limit")
            normalized.setdefault("amount_in", 100)
            normalized.setdefault("min_out", 99)
        elif entrypoint == "schedule_twamm":
            normalized.setdefault("order_id", "twamm-1")
            normalized.setdefault("hook_id", "twamm")
            normalized.setdefault("amount_in", 1000)
            normalized.setdefault("min_out", 990)
        elif entrypoint == "record_execution":
            normalized.setdefault("order_id", "order-1")
            normalized.setdefault("amount_in", 100)
            normalized.setdefault("amount_out", 101)
        return normalized

    def submit_call(self, request: dict[str, Any]) -> dict[str, Any]:
        authority = str(request.get("authority") or FIXTURE_AUTHORITY)
        entrypoint = str(request.get("entrypoint") or "")
        contract_address = str(request.get("contract_address") or "")
        contract_alias = ADDRESS_TO_ALIAS.get(contract_address)
        if entrypoint not in SUPPORTED_ENTRYPOINTS or not contract_alias:
            return {"error": "unsupported_entrypoint"}

        payload = request.get("payload") if isinstance(request.get("payload"), dict) else {}
        normalized_payload = self.normalize_call_payload(entrypoint, payload)
        tx_hash_hex = self.next_hash_hex()
        if entrypoint == "route_swap":
            amount_in = int(normalized_payload.get("amount_in", 0))
            input_is_base = int(normalized_payload.get("input_is_base", 1))
            min_out = int(normalized_payload.get("min_out", 0))
            amount_out = max(min_out, amount_in - 7) if input_is_base == 1 else max(min_out, amount_in + 11)
            self.append_swap_fill(authority, input_is_base, amount_in, amount_out, min_out)
            tx_hash_hex = self.swap_records[-1]["tx_hash_hex"]
        else:
            self.append_event(contract_alias, entrypoint, authority, normalized_payload, tx_hash_hex=tx_hash_hex)

        return {
            "submitted": True,
            "tx_hash_hex": tx_hash_hex,
            "status": {"kind": "Pending"},
        }


class MockToriiHandler(BaseHTTPRequestHandler):
    server_version = "MockTorii/0.2"

    @property
    def state(self) -> MockToriiState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return

    def parse_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=False)

        if parsed.path in {"/v1/events/sse", "/v1/contracts/events/sse"}:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            last_sequence = 0
            try:
                self.wfile.write(b"event: ready\ndata: {\"kind\":\"ready\"}\n\n")
                self.wfile.flush()
                while True:
                    last_sequence, payload = self.state.next_sse_frame(last_sequence, timeout=1.0)
                    if payload is None:
                        self.wfile.write(b": keepalive\n\n")
                    else:
                        self.wfile.write(
                            b"event: contract_event\n" if parsed.path == "/v1/contracts/events/sse" else b"event: pipeline\n"
                        )
                        self.wfile.write(b"data: ")
                        self.wfile.write(json.dumps(payload).encode("utf-8"))
                        self.wfile.write(b"\n\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                return
            return

        with self.state.lock:
            if parsed.path == "/v1/contracts/activity":
                json_response(self, HTTPStatus.OK, self.state.list_activity(query))
                return
            if parsed.path == "/v1/contracts/events":
                json_response(self, HTTPStatus.OK, self.state.list_contract_events(query))
                return
            if parsed.path == "/v1/contracts/rollups/swaps/fills":
                json_response(self, HTTPStatus.OK, self.state.swaps_fills_rollup(query))
                return
            if parsed.path == "/v1/contracts/rollups/swaps/candles":
                json_response(self, HTTPStatus.OK, self.state.swaps_candles_rollup(query))
                return
            if parsed.path == "/v1/contracts/rollups/trader/activity":
                json_response(self, HTTPStatus.OK, self.state.trader_activity_rollup(query))
                return
            if parsed.path == "/v1/contracts/rollups/trader/account":
                json_response(self, HTTPStatus.OK, self.state.trader_account_rollup(query))
                return
            if parsed.path == "/v1/contracts/rollups/intents":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "intents", "intent_lifecycle"))
                return
            if parsed.path == "/v1/contracts/rollups/vaults/positions":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "vaults", "vault_positions"))
                return
            if parsed.path == "/v1/contracts/rollups/operators/status":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "operators", "operator_status"))
                return
            if parsed.path == "/v1/contracts/rollups/margin/health":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "margin", "margin_health"))
                return
            if parsed.path == "/v1/contracts/rollups/rwa/lots":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "rwa", "rwa_lots"))
                return
            if parsed.path == "/v1/contracts/rollups/dlmm/hooks":
                json_response(self, HTTPStatus.OK, self.state.module_rollup(query, "dlmmHooks", "dlmm_hooks"))
                return
            if parsed.path == "/v1/pipeline/transactions/status":
                tx_hash_hex = parse_str(query, "hash")
                json_response(
                    self,
                    HTTPStatus.OK,
                    self.state.status_by_hash.get(tx_hash_hex, {"status": {"kind": "Committed"}}),
                )
                return

        json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        request = self.parse_json_body()

        with self.state.lock:
            if parsed.path == "/v1/contracts/view":
                contract_address = str(request.get("contract_address") or "")
                entrypoint = str(request.get("entrypoint") or "")
                payload = request.get("payload") if isinstance(request.get("payload"), dict) else {}
                response = self.state.view(contract_address, entrypoint, payload)
                if response is None:
                    json_response(self, HTTPStatus.BAD_REQUEST, {"code": "unsupported_entrypoint"})
                    return
                json_response(self, HTTPStatus.OK, response)
                return

            if parsed.path == "/v1/contracts/view/batch":
                json_response(self, HTTPStatus.OK, self.state.view_batch(request))
                return

            if parsed.path == "/v1/contracts/call":
                response = self.state.submit_call(request)
                if "error" in response:
                    json_response(self, HTTPStatus.BAD_REQUEST, {"code": response["error"]})
                    return
                json_response(self, HTTPStatus.OK, response)
                return

        json_response(self, HTTPStatus.NOT_FOUND, {"code": "not_found"})


def start_server(server: ThreadingHTTPServer) -> threading.Thread:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


def main() -> int:
    tempdir = tempfile.TemporaryDirectory(prefix="soraswap-trader-fixture-")
    fixture_root = Path(tempdir.name)

    upstream_state = MockToriiState()
    upstream_server = FastThreadingHTTPServer(("127.0.0.1", 0), MockToriiHandler)
    upstream_server.state = upstream_state  # type: ignore[attr-defined]
    upstream_thread = start_server(upstream_server)
    upstream_host, upstream_port = upstream_server.server_address
    upstream_url = f"http://{upstream_host}:{upstream_port}"

    build_fixture_repo(fixture_root, upstream_url)

    signer = trader_ui.contract_console.SignerBinding(
        environment="fixture",
        config_path=fixture_root / "config" / "fixture.client.toml",
        authority=FIXTURE_AUTHORITY,
        torii_url="http://ignored-by-deployment.invalid",
        private_key="802620fixture",
        public_key="ed0120fixture",
        basic_auth=None,
        warnings=[],
        source="explicit",
    )
    state = trader_ui.TraderUiState(fixture_root, {"fixture": signer})
    app_server = FastThreadingHTTPServer(("127.0.0.1", 0), trader_ui.TraderUiHandler)
    app_server.state = state  # type: ignore[attr-defined]
    app_thread = start_server(app_server)
    app_host, app_port = app_server.server_address
    app_url = f"http://{app_host}:{app_port}"

    stop_event = threading.Event()

    def handle_signal(signum, frame) -> None:  # noqa: ARG001
        stop_event.set()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    print(json.dumps({"url": app_url, "upstream_url": upstream_url}), flush=True)

    try:
        while not stop_event.wait(0.25):
            pass
    finally:
        app_server.shutdown()
        upstream_server.shutdown()
        app_server.server_close()
        upstream_server.server_close()
        app_thread.join(timeout=5)
        upstream_thread.join(timeout=5)
        tempdir.cleanup()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
