#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

manifest="iroha.contracts.toml"
profile="local"
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
  esac
done

soraswap_require_binary_integer_setting \
  "SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD" \
  "${SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD:-0}" || exit 1

case "$command" in
  check|build|test|schema)
    soraswap_require_contract_source_hygiene "$SORASWAP_ROOT" "iroha dev failed" || exit 1
    ;;
esac

dev_iroha_existing_cli() {
  local debug_bin="$SORASWAP_IROHA_ROOT/target/debug/iroha"
  local release_bin="$SORASWAP_IROHA_ROOT/target/release/iroha"

  if [[ -n "${SORASWAP_IROHA_CLI_BIN:-}" ]]; then
    [[ -x "$SORASWAP_IROHA_CLI_BIN" ]] || return 1
    printf '%s\n' "$SORASWAP_IROHA_CLI_BIN"
  elif [[ -x "$debug_bin" && -x "$release_bin" ]]; then
    if [[ "$debug_bin" -nt "$release_bin" ]]; then
      printf '%s\n' "$debug_bin"
    else
      printf '%s\n' "$release_bin"
    fi
  elif [[ -x "$debug_bin" ]]; then
    printf '%s\n' "$debug_bin"
  elif [[ -x "$release_bin" ]]; then
    printf '%s\n' "$release_bin"
  else
    return 1
  fi
}

if [[ "${SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD:-0}" == "1" ]]; then
  if ! IROHA_CLI_BIN="$(dev_iroha_existing_cli)"; then
    echo "iroha dev: no executable latest-Iroha CLI is available and SORASWAP_SKIP_IROHA_DEV_TOOL_BUILD=1" >&2
    exit 1
  fi
  echo "iroha dev: reusing existing unified iroha contract-dev tool" >&2
else
  ensure_iroha_cli_bin
  IROHA_CLI_BIN="$SORASWAP_ACTIVE_IROHA_CLI_BIN"
fi

dev_iroha_command_requires_profile_config() {
  case "$command" in
    doctor|smoke|deploy|resume|call|view)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

dev_iroha_should_preflight_local_torii() {
  [[ "$profile" == "local" ]] || return 1
  dev_iroha_command_requires_profile_config
}

profile_config="$(
  python3 - "$manifest" "$profile" <<'PY' 2>/dev/null || true
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
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
print((manifest.parent / client_config).resolve())
PY
)"

if [[ -n "$profile_config" && ! -f "$profile_config" ]]; then
  if dev_iroha_command_requires_profile_config; then
    echo "iroha dev: profile '$profile' client config not found at $(soraswap_display_path "$profile_config")" >&2
    if [[ "$profile" == "local" ]]; then
      echo "iroha dev: run make local-up before make dev-$command, or set SORASWAP_LOCALNET_DIR/SORASWAP_PROFILE to a profile with a client config" >&2
    else
      echo "iroha dev: create the selected profile client config or choose a different SORASWAP_PROFILE" >&2
    fi
    exit 2
  fi
  profile_config=""
fi

if [[ -n "$profile_config" ]]; then
  if dev_iroha_should_preflight_local_torii; then
    torii_root="$(torii_url_from_config "$profile_config" 2>/dev/null || true)"
    if [[ -z "$torii_root" ]]; then
      echo "iroha dev: profile '$profile' client config has no torii_url: $(soraswap_display_path "$profile_config")" >&2
      echo "iroha dev: run make local-up before make dev-$command, or set SORASWAP_LOCALNET_DIR/SORASWAP_PROFILE to a profile with a reachable client config" >&2
      exit 2
    fi
    torii_root="${torii_root%/}"
    torii_status="$(curl -fsS -o /dev/null -w "%{http_code}" --max-time 2 "$torii_root/v1/api/version" 2>/dev/null || true)"
    if [[ "$torii_status" != "200" ]]; then
      echo "iroha dev: profile '$profile' Torii is unavailable at $torii_root" >&2
      echo "iroha dev: run make local-up before make dev-$command, or set SORASWAP_LOCALNET_DIR/SORASWAP_PROFILE to a profile with a reachable client config" >&2
      exit 2
    fi
  fi
  exec "$IROHA_CLI_BIN" -c "$profile_config" contract dev "$@"
fi

exec "$IROHA_CLI_BIN" contract dev "$@"
