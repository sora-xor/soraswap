#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-taira-write-canary-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

config="$TMP_DIR/taira.client.toml"
token_file="$TMP_DIR/taira-onboarding.token"
fake_iroha="$TMP_DIR/iroha"
args_file="$TMP_DIR/args.bin"
expected_account_id="fixture-taira-account"
fee_asset_id="$SORASWAP_TESTNET_FEE_ASSET_DEFINITION_ID"
token_value="fixture-taira-onboarding-token-123456"
private_key_value="8026201111111111111111111111111111111111111111111111111111111111111111"

cat >"$config" <<EOF
chain = "$SORASWAP_TESTNET_CHAIN_ID_DEFAULT"
network_id = "$SORASWAP_TESTNET_NETWORK_ID_DEFAULT"
torii_url = "https://taira.sora.org/"

[account]
domain = "universal"
profile = "taira"
chain_discriminant = $SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT
public_key = "ed0120d04ab232742bb4ab3a1368bd4615e4e6d0224ab71a016baf8520a332c9778737"
private_key = "$private_key_value"
EOF
chmod 600 "$config"
printf '%s' "$token_value" >"$token_file"
chmod 600 "$token_file"

cat >"$fake_iroha" <<'EOF'
#!/bin/zsh
set -euo pipefail

printf '%s\0' "$@" >"$TAIRA_WRITE_CANARY_ARGS_FILE"
account_id="$TAIRA_WRITE_CANARY_EXPECTED_ACCOUNT_ID"
mode="${FAKE_TAIRA_WRITE_CANARY_MODE:-ok}"
case "$mode" in
  wrong-account)
    account_id="wrong-taira-account"
    ;;
  echo-token)
    token_path=""
    args=("$@")
    index=1
    while (( index <= ${#args[@]} )); do
      if [[ "${args[$index]}" == "--onboarding-token-file" ]]; then
        token_path="${args[$(( index + 1 ))]}"
        break
      fi
      index=$(( index + 1 ))
    done
    print -r -- "$(<"$token_path")"
    ;;
  echo-config-secret)
    print -r -- "$TAIRA_WRITE_CANARY_PRIVATE_KEY"
    ;;
esac

receipt="$(jq -cn \
  --arg account_id "$account_id" \
  --arg faucet_asset_id "$TAIRA_WRITE_CANARY_FEE_ASSET_ID" \
  --arg public_root "$TAIRA_WRITE_CANARY_PUBLIC_ROOT" \
  --arg chain "$TAIRA_WRITE_CANARY_CHAIN_ID" \
  --argjson chain_discriminant "$TAIRA_WRITE_CANARY_CHAIN_DISCRIMINANT" \
  '
    [{
      kind: {kind: "nexus", value: null},
      asset_definition_id: $faucet_asset_id,
      max_amount: "1"
    }] as $charge_limits
    | {
        payer: "authority",
        value: {
          charge_limits: $charge_limits,
          gas_limit: null
        }
      } as $fee_payment
    | {
        command: "taira_write_canary",
        status: "ok",
        public_root: $public_root,
        checks: [
          {name: "accounts_onboard_plan", http_status: 200, ok: true, detail: "{}"},
          {name: "accounts_onboard", http_status: 202, ok: true, detail: "{}"},
          {name: "accounts_onboard_finality", http_status: 200, ok: true, detail: "{}"},
          {name: "accounts_faucet", http_status: 202, ok: true, detail: "{}"},
          {name: "accounts_faucet_finality", http_status: 200, ok: true, detail: "{}"}
        ],
        warnings: [],
        failures: [],
        chain: $chain,
        chain_discriminant: $chain_discriminant,
        account_id: $account_id,
        alias: "tairarolloutcanary0123456789abcdef@universal",
        generated_signer: false,
        faucet_asset_id: $faucet_asset_id,
        fee_payment: $fee_payment,
        fee_quote: {
          intent: $fee_payment,
          observation: {
            ledger_time_ms: 1,
            next_block_height: 42,
            route_dataspace_id: 0
          },
          components: $charge_limits,
          capacities: [],
          decision: {
            status: "accepted",
            value: {
              debit_source: {kind: "account", value: $account_id}
            }
          }
        },
        message: "taira-write-canary-1770000000000",
        faucet_tx_hash: "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd",
        ping_tx_hash: "abababababababababababababababababababababababababababababababab",
        applied_block_height: 42,
        terminal_kind: "Applied",
        tx_query_verified: true
      }
  ')"

case "$mode" in
  wrong-chain)
    receipt="$(jq -c '.chain = "wrong-taira-chain"' <<<"$receipt")"
    ;;
  wrong-discriminant)
    receipt="$(jq -c '.chain_discriminant = 370' <<<"$receipt")"
    ;;
  wrong-public-root)
    receipt="$(jq -c '.public_root = "https://wrong.invalid"' <<<"$receipt")"
    ;;
  failed-check)
    receipt="$(jq -c '.checks[3].ok = false' <<<"$receipt")"
    ;;
  missing-check)
    receipt="$(jq -c 'del(.checks[2])' <<<"$receipt")"
    ;;
  sponsor-fee)
    receipt="$(jq -c '
      .fee_payment = {
        payer: "sponsor",
        value: {
          program_id: "fixture-sponsor",
          program_revision: 1,
          charge_limits: .fee_payment.value.charge_limits,
          gas_limit: null
        }
      }
      | .fee_quote.intent = .fee_payment
    ' <<<"$receipt")"
    ;;
  mismatched-fee-quote)
    receipt="$(jq -c '.fee_quote.intent.value.charge_limits = []' <<<"$receipt")"
    ;;
  short-hash)
    receipt="$(jq -c '.ping_tx_hash = "abc123"' <<<"$receipt")"
    ;;
  zero-height)
    receipt="$(jq -c '.applied_block_height = 0' <<<"$receipt")"
    ;;
  rejected-terminal)
    receipt="$(jq -c '.terminal_kind = "Rejected"' <<<"$receipt")"
    ;;
  nonboolean-query)
    receipt="$(jq -c '.tx_query_verified = "true"' <<<"$receipt")"
    ;;
  query-unverified-without-warning)
    receipt="$(jq -c '.tx_query_verified = false' <<<"$receipt")"
    ;;
  extra-key)
    receipt="$(jq -c '.legacy_receipt = true' <<<"$receipt")"
    ;;
  missing-field)
    receipt="$(jq -c 'del(.message)' <<<"$receipt")"
    ;;
  query-unverified)
    receipt="$(jq -c '
      .tx_query_verified = false
      | .warnings = ["write canary reached pipeline terminal status but transaction query did not return the entry yet"]
    ' <<<"$receipt")"
    ;;
  null-height)
    receipt="$(jq -c '.applied_block_height = null' <<<"$receipt")"
    ;;
  multiple-receipts)
    print -r -- "$receipt"
    print -r -- "$receipt"
    exit 0
    ;;
esac

print -r -- "$receipt"
EOF
chmod 700 "$fake_iroha"

ensure_iroha_cli_bin() {
  export SORASWAP_ACTIVE_IROHA_CLI_BIN="$fake_iroha"
}

export SORASWAP_PUBLIC_ENV=testnet
export SORASWAP_ALLOW_TESTNET_MUTATIONS=1
export SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE="$token_file"
export TAIRA_WRITE_CANARY_ARGS_FILE="$args_file"
export TAIRA_WRITE_CANARY_EXPECTED_ACCOUNT_ID="$expected_account_id"
export TAIRA_WRITE_CANARY_FEE_ASSET_ID="$fee_asset_id"
export TAIRA_WRITE_CANARY_PRIVATE_KEY="$private_key_value"
export TAIRA_WRITE_CANARY_PUBLIC_ROOT="https://taira.sora.org"
export TAIRA_WRITE_CANARY_CHAIN_ID="$SORASWAP_TESTNET_CHAIN_ID_DEFAULT"
export TAIRA_WRITE_CANARY_CHAIN_DISCRIMINANT="$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT"

receipt="$(iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id")"
jq -e \
  --arg account_id "$expected_account_id" \
  --arg fee_asset_id "$fee_asset_id" \
  '.status == "ok" and .account_id == $account_id and .faucet_asset_id == $fee_asset_id' \
  >/dev/null <<<"$receipt"

python3 - "$args_file" "$token_file" "$fee_asset_id" <<'PY'
from pathlib import Path
import sys

args_path, token_path, fee_asset_id = sys.argv[1:]
raw = Path(args_path).read_bytes().split(b"\0")
assert raw[-1] == b""
args = [item.decode("utf-8") for item in raw[:-1]]

def require_pair(flag: str, value: str) -> None:
    index = args.index(flag)
    assert args[index + 1] == value, (flag, args[index + 1])

subsequence = ["--fee-payer", "authority", "taira", "write-canary"]
assert any(args[index:index + len(subsequence)] == subsequence for index in range(len(args)))
require_pair("--public-root", "https://taira.sora.org")
require_pair("--onboarding-token-file", token_path)
require_pair("--faucet-asset-id", fee_asset_id)
assert "--use-config-signer" in args
assert "--json" in args
config_path = Path(args[args.index("--config") + 1])
assert not config_path.exists(), f"materialized config was not removed: {config_path}"
PY

rm -f "$args_file"
unset SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE
missing_token_output="$TMP_DIR/missing-token.out"
if iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id" \
  >"$missing_token_output" 2>&1; then
  echo "write canary unexpectedly accepted a missing onboarding token file" >&2
  exit 1
fi
rg -Fq "SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE is required" "$missing_token_output"
[[ ! -e "$args_file" ]]

export SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE="$token_file"
expect_schema_rejection() {
  local mode="$1"
  local description="$2"
  local output_file="$TMP_DIR/${mode}.out"

  export FAKE_TAIRA_WRITE_CANARY_MODE="$mode"
  if iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id" \
    >"$output_file" 2>&1; then
    echo "write canary unexpectedly accepted $description" >&2
    exit 1
  fi
  rg -Fq "receipt did not match the exact current success schema" "$output_file"
}

expect_schema_rejection wrong-account "a receipt for another account"
expect_schema_rejection wrong-chain "a receipt for another chain"
expect_schema_rejection wrong-discriminant "a receipt for another chain discriminant"
expect_schema_rejection wrong-public-root "a receipt for another public root"
expect_schema_rejection failed-check "a receipt with a failed required check"
expect_schema_rejection missing-check "a receipt with a missing required check"
expect_schema_rejection sponsor-fee "a sponsor-paid receipt"
expect_schema_rejection mismatched-fee-quote "a mismatched fee quote"
expect_schema_rejection short-hash "a non-64-hex transaction hash"
expect_schema_rejection zero-height "a zero applied block height"
expect_schema_rejection rejected-terminal "a non-Applied terminal status"
expect_schema_rejection nonboolean-query "a non-boolean transaction-query result"
expect_schema_rejection query-unverified-without-warning "an unverified query without the current warning"
expect_schema_rejection extra-key "a receipt with a retired extra field"
expect_schema_rejection missing-field "a receipt missing a current top-level field"

export FAKE_TAIRA_WRITE_CANARY_MODE=multiple-receipts
multiple_receipts_output="$TMP_DIR/multiple-receipts.out"
if iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id" \
  >"$multiple_receipts_output" 2>&1; then
  echo "write canary unexpectedly accepted multiple JSON receipts" >&2
  exit 1
fi
rg -Fq "did not return exactly one JSON receipt" "$multiple_receipts_output"

export FAKE_TAIRA_WRITE_CANARY_MODE=query-unverified
unverified_receipt="$(iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id")"
jq -e \
  '.status == "ok" and .tx_query_verified == false and (.warnings | length > 0)' \
  >/dev/null <<<"$unverified_receipt"

export FAKE_TAIRA_WRITE_CANARY_MODE=null-height
null_height_receipt="$(iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id")"
jq -e '.status == "ok" and .applied_block_height == null' >/dev/null <<<"$null_height_receipt"

export FAKE_TAIRA_WRITE_CANARY_MODE=echo-token
secret_output="$TMP_DIR/secret-output.out"
if iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id" \
  >"$secret_output" 2>&1; then
  echo "write canary unexpectedly accepted credential-bearing output" >&2
  exit 1
fi
rg -Fq "output contained credential material and was suppressed" "$secret_output"
if rg -Fq "$token_value" "$secret_output"; then
  echo "write-canary failure output exposed the onboarding token" >&2
  exit 1
fi

export FAKE_TAIRA_WRITE_CANARY_MODE=echo-config-secret
config_secret_output="$TMP_DIR/config-secret-output.out"
if iroha_taira_write_canary_with_config_signer "$config" "$expected_account_id" \
  >"$config_secret_output" 2>&1; then
  echo "write canary unexpectedly accepted client-key-bearing output" >&2
  exit 1
fi
rg -Fq "output contained credential material and was suppressed" "$config_secret_output"
if rg -Fq "$private_key_value" "$config_secret_output"; then
  echo "write-canary failure output exposed the client private key" >&2
  exit 1
fi

unset FAKE_TAIRA_WRITE_CANARY_MODE
unset SORASWAP_TAIRA_ONBOARDING_TOKEN_FILE
rm -f "$args_file"
account_exists() {
  return 0
}
account_assets_json() {
  jq -cn --arg asset "$fee_asset_id" '{items: [{asset: $asset, quantity: "1"}]}'
}
ready_output="$(ensure_public_signer_ready "$config" "$expected_account_id" autofund)"
rg -Fq "public signer ready" <<<"$ready_output"
[[ ! -e "$args_file" ]]

echo "taira write-canary helper smoke: ok"
