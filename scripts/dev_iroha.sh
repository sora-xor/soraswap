#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

IROHA_CLI_BIN="${SORASWAP_IROHA_CLI_BIN:-$SORASWAP_IROHA_ROOT/target/debug/iroha}"
KOTO_COMPILE_BIN="${SORASWAP_KOTO_COMPILE_BIN:-$SORASWAP_IROHA_ROOT/target/debug/koto_compile}"
KOTO_LINT_BIN="${SORASWAP_KOTO_LINT_BIN:-$SORASWAP_IROHA_ROOT/target/debug/koto_lint}"

manifest="iroha.contracts.toml"
profile="local"
schema_out=""
args=("$@")
command="${args[1]:-}"
for ((i = 1; i <= ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --manifest)
      if (( i + 1 <= ${#args[@]} )); then
        manifest="${args[$((i + 1))]}"
      fi
      ;;
    --manifest=*)
      manifest="${args[$i]#--manifest=}"
      ;;
    --profile)
      if (( i + 1 <= ${#args[@]} )); then
        profile="${args[$((i + 1))]}"
      fi
      ;;
    --profile=*)
      profile="${args[$i]#--profile=}"
      ;;
    --out)
      if (( i + 1 <= ${#args[@]} )); then
        schema_out="${args[$((i + 1))]}"
      fi
      ;;
    --out=*)
      schema_out="${args[$i]#--out=}"
      ;;
  esac
done

if [[ "${SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD:-0}" != "1" ]]; then
  echo "iroha dev: building iroha/koto dev tools" >&2
  (
    cd "$SORASWAP_IROHA_ROOT"
    cargo build \
      -p iroha_cli --bin iroha \
      -p ivm --bin koto_compile \
      -p ivm --bin koto_lint \
      -p ivm --bin koto_test
  )
fi

if [[ "$command" == "check" ]]; then
  sources=("${(@f)$(
    python3 - "$manifest" <<'PY'
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:
    raise SystemExit(f"tomllib unavailable: {exc}")

manifest = Path(sys.argv[1]).resolve()
root = manifest.parent
data = tomllib.loads(manifest.read_text())
for contract in data.get("contracts", []):
    source = contract.get("source")
    if source:
        print(root / source)
PY
  )}")
  exec "$KOTO_LINT_BIN" "${sources[@]}"
fi

if [[ "$command" == "build" ]]; then
  exec python3 - "$manifest" "$KOTO_COMPILE_BIN" <<'PY'
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:
    raise SystemExit(f"tomllib unavailable: {exc}")

manifest = Path(sys.argv[1]).resolve()
koto_compile = sys.argv[2]
root = manifest.parent
data = tomllib.loads(manifest.read_text())
for contract in data.get("contracts", []):
    source = contract.get("source")
    artifact = contract.get("artifact")
    if not source or not artifact:
        continue
    source_path = root / source
    artifact_path = root / artifact
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    stem = artifact_path.with_suffix("")
    subprocess.run(
        [
            koto_compile,
            str(source_path),
            "--out",
            str(artifact_path),
            "--manifest-out",
            str(stem) + ".manifest.json",
            "--interface-out",
            str(stem) + ".interface.json",
            "--abi",
            "1",
        ],
        check=True,
    )
PY
fi

if [[ "$command" == "schema" ]]; then
  if [[ -z "$schema_out" ]]; then
    echo "schema requires --out <path>" >&2
    exit 2
  fi
  exec python3 - "$manifest" "$schema_out" <<'PY'
import json
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:
    raise SystemExit(f"tomllib unavailable: {exc}")

def sample_value(type_name):
    if type_name == "int":
        return 0
    if type_name == "AccountId":
        return "ed0120..."
    if type_name == "AssetDefinitionId":
        return "xor#universal"
    if type_name == "Name":
        return "name"
    return None

manifest = Path(sys.argv[1]).resolve()
out = (manifest.parent / sys.argv[2]).resolve()
root = manifest.parent
data = tomllib.loads(manifest.read_text())
lines = ["# Contract Interface Schema", "", f"Manifest: `{manifest.name}`", ""]
for contract in data.get("contracts", []):
    name = contract.get("name", "unknown")
    artifact = contract.get("artifact")
    if not artifact:
        continue
    interface_path = (root / artifact).with_suffix(".interface.json")
    if not interface_path.is_file():
        continue
    interface = json.loads(interface_path.read_text())
    entrypoints = interface.get("entrypoints", [])
    states = interface.get("states", [])
    lines.extend(
        [
            f"## {name}",
            "",
            f"- Interface: `{interface_path.relative_to(root)}`",
            f"- Entrypoints: `{len(entrypoints)}`",
            f"- State keys: `{len(states)}`",
            "",
        ]
    )
    for entrypoint in entrypoints:
        params = entrypoint.get("params", [])
        sample = {
            param.get("name", "value"): sample_value(param.get("type_name", ""))
            for param in params
        }
        kind = entrypoint.get("kind", {})
        if isinstance(kind, dict):
            kind = kind.get("kind", "Unknown")
        lines.extend(
            [
                f"### {entrypoint.get('name', 'unknown')}",
                "",
                f"- Kind: `{kind}`",
                f"- Return: `{entrypoint.get('return_type') or 'null'}`",
                "- Sample payload:",
                "",
                "```json",
                json.dumps(sample, indent=2, sort_keys=True),
                "```",
                "",
            ]
        )

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(lines), encoding="utf-8")
PY
fi

profile_config="$(
  python3 - "$manifest" "$profile" <<'PY' 2>/dev/null || true
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(0)

manifest = Path(sys.argv[1])
profile = sys.argv[2]
try:
    data = tomllib.loads(manifest.read_text())
except Exception:
    sys.exit(0)

client_config = data.get("profiles", {}).get(profile, {}).get("client_config")
if not client_config:
    sys.exit(0)
path = (manifest.parent / client_config).resolve()
if path.is_file():
    print(path)
PY
)"

if [[ -n "$profile_config" ]]; then
  exec "$IROHA_CLI_BIN" -c "$profile_config" contract dev "$@"
fi

exec "$IROHA_CLI_BIN" contract dev "$@"
