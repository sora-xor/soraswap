#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/scripts/common.sh"

typeset -gi adversarial_rejection_count=0

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/soraswap-production-auth-smoke.XXXXXX")"
work_dir="${work_dir:A}"
original_tmpdir="${TMPDIR:-}"
cleanup() {
  rm -rf -- "$work_dir"
  if [[ -n "$original_tmpdir" ]]; then
    export TMPDIR="$original_tmpdir"
  else
    unset TMPDIR
  fi
}
trap cleanup EXIT

fail() {
  echo "production auth/config smoke failed: $*" >&2
  exit 1
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  (( adversarial_rejection_count += 1 ))
}

fixture_root="$work_dir/repo"
mkdir -p "$fixture_root/config/production" "$work_dir/tmp"
git -C "$fixture_root" init -q
printf '%s\n' 'config/production/*.toml' >"$fixture_root/.gitignore"

login="auth-smoke-user-$RANDOM"
password="auth-smoke-pass-$RANDOM"
basic_token="$(printf '%s:%s' "$login" "$password" | base64 | tr -d '\r\n')"
config="$fixture_root/config/production/production.client.toml"
cat >"$config" <<EOF
chain = "production-auth-smoke"
network_id = "hash:32C903E5B3497E34C2B844EBFE8A39C19E6CF8F95D44C1FFB8BA9DCB42F91149#A2F0"
torii_url = "https://torii.invalid"

[account]
domain = "wonderland"
public_key = "ed0120aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private_key = "802620bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
chain_discriminant = 991

[basic_auth]
web_login = "$login"
password = "$password"
EOF
chmod 600 "$config"
soraswap_require_secure_production_client_config "$config" "$fixture_root" \
  || fail "secure ignored production config was rejected"

fake_curl="$work_dir/fake-curl.zsh"
cat >"$fake_curl" <<'EOF'
#!/bin/zsh
set -euo pipefail

for arg in "$@"; do
  case "$arg" in
    *"$EXPECTED_LOGIN"*|*"$EXPECTED_PASSWORD"*|*"$EXPECTED_BASIC_TOKEN"*|*"Authorization: Basic"*)
      echo "credential material appeared in curl argv" >&2
      exit 90
      ;;
  esac
done

config_path=""
method="GET"
output_path=""
write_out=""
for ((idx = 1; idx <= $#; idx++)); do
  if [[ "${@[idx]}" == "--config" && $((idx + 1)) -le $# ]]; then
    config_path="${@[$((idx + 1))]}"
  elif [[ "${@[idx]}" == "-X" && $((idx + 1)) -le $# ]]; then
    method="${@[$((idx + 1))]}"
  elif [[ "${@[idx]}" == "-o" && $((idx + 1)) -le $# ]]; then
    output_path="${@[$((idx + 1))]}"
  elif [[ "${@[idx]}" == "-w" && $((idx + 1)) -le $# ]]; then
    write_out="${@[$((idx + 1))]}"
  fi
done
if [[ "${EXPECT_ANONYMOUS:-0}" == "1" ]]; then
  [[ -z "$config_path" ]] || {
    echo "anonymous request unexpectedly received a curl auth config" >&2
    exit 96
  }
  printf '%s\n' '{"anonymous":true}'
  exit 0
fi
[[ -n "$config_path" && -r "$config_path" ]] || {
  echo "anonymous curl config was not readable" >&2
  exit 91
}
[[ "$config_path" == /dev/fd/* ]] || {
  echo "curl auth config was not supplied through a macOS file descriptor" >&2
  exit 95
}
auth_line="$(sed -n 's/^header = "\(Authorization: Basic [A-Za-z0-9+\/=]*\)"$/\1/p' "$config_path")"
[[ "$auth_line" == "Authorization: Basic $EXPECTED_BASIC_TOKEN" ]] || {
  echo "curl config did not carry expected basic auth" >&2
  exit 92
}
case "$method" in
  GET) response='{"method":"GET","authenticated":true}' ;;
  POST) response='{"method":"POST","authenticated":true}' ;;
  *) exit 93 ;;
esac
if [[ "${ECHO_CREDENTIAL_RESPONSE:-0}" == "1" ]]; then
  response="Authorization: Basic $EXPECTED_BASIC_TOKEN"
fi
if [[ -n "$output_path" ]]; then
  printf '%s\n' "$response" >"$output_path"
  [[ -z "$write_out" ]] || printf '%s' 200
else
  printf '%s\n' "$response"
fi
EOF
chmod 700 "$fake_curl"

auth_stdout="$work_dir/auth.stdout"
auth_stderr="$work_dir/auth.stderr"
(
  export SORASWAP_CURL_BIN="$fake_curl"
  export EXPECTED_LOGIN="$login"
  export EXPECTED_PASSWORD="$password"
  export EXPECTED_BASIC_TOKEN="$basic_token"
  soraswap_curl_for_config "$config" -sS -X GET https://torii.invalid/status
  printf '%s' '{"probe":true}' \
    | soraswap_curl_for_config "$config" -sS -X POST --data-binary @- https://torii.invalid/v1/probe
) >"$auth_stdout" 2>"$auth_stderr" || fail "authenticated GET/POST did not reach the argv-inspecting curl shim"
jq -e -s 'length == 2 and .[0].method == "GET" and .[1].method == "POST" and all(.[]; .authenticated == true)' \
  "$auth_stdout" >/dev/null || fail "authenticated GET/POST responses were not preserved"
if rg -F -q -e "$login" -e "$password" -e "$basic_token" -e 'Authorization: Basic' "$auth_stdout" "$auth_stderr"; then
  fail "credential material appeared in captured stdout/stderr"
fi

echo_stdout="$work_dir/credential-echo.stdout"
echo_stderr="$work_dir/credential-echo.stderr"
echo_status=0
(
  export SORASWAP_CURL_BIN="$fake_curl"
  export EXPECTED_LOGIN="$login" EXPECTED_PASSWORD="$password" EXPECTED_BASIC_TOKEN="$basic_token"
  export ECHO_CREDENTIAL_RESPONSE=1
  soraswap_curl_for_config "$config" -sS https://torii.invalid/status
) >"$echo_stdout" 2>"$echo_stderr" || echo_status=$?
[[ "$echo_status" != "0" ]] || fail "credential-echoing authenticated response unexpectedly succeeded"
(( adversarial_rejection_count += 1 ))
if rg -F -q -e "$login" -e "$password" -e "$basic_token" -e 'Authorization: Basic' "$echo_stdout" "$echo_stderr"; then
  fail "suppressed authenticated response still emitted credential material"
fi

echo_body="$work_dir/credential-echo.body"
printf '%s' preserved-sentinel >"$echo_body"
echo_status=0
(
  export SORASWAP_CURL_BIN="$fake_curl"
  export EXPECTED_LOGIN="$login" EXPECTED_PASSWORD="$password" EXPECTED_BASIC_TOKEN="$basic_token"
  export ECHO_CREDENTIAL_RESPONSE=1
  soraswap_curl_for_config "$config" -sS -o "$echo_body" -w '%{http_code}' https://torii.invalid/status
) >"$echo_stdout" 2>"$echo_stderr" || echo_status=$?
[[ "$echo_status" != "0" ]] || fail "file-backed credential-echoing response unexpectedly succeeded"
(( adversarial_rejection_count += 1 ))
[[ "$(cat "$echo_body")" == preserved-sentinel ]] \
  || fail "credential-echoing response was copied into the caller output path"
if rg -F -q -e "$login" -e "$password" -e "$basic_token" -e 'Authorization: Basic' "$echo_stdout" "$echo_stderr" "$echo_body"; then
  fail "file-backed response suppression retained credential material"
fi

(
  export SORASWAP_CURL_BIN="$fake_curl"
  export EXPECTED_LOGIN="$login" EXPECTED_PASSWORD="$password" EXPECTED_BASIC_TOKEN="$basic_token"
  expect_failure "cross-origin authenticated request" soraswap_curl_for_config "$config" -sS https://evil.invalid/status
  expect_failure "authenticated redirect" soraswap_curl_for_config "$config" -sS -L https://torii.invalid/status
  expect_failure "combined authenticated redirect" soraswap_curl_for_config "$config" -sSL https://torii.invalid/status
  expect_failure "combined authenticated insecure TLS" soraswap_curl_for_config "$config" -sk https://torii.invalid/status
  expect_failure "authenticated endpoint remap" soraswap_curl_for_config "$config" -sS --connect-to torii.invalid:443:evil.invalid:443 https://torii.invalid/status
  expect_failure "caller auth override" soraswap_curl_for_config "$config" -sS --user attacker:secret https://torii.invalid/status
  expect_failure "authenticated insecure TLS" soraswap_curl_for_config "$config" -sS --insecure https://torii.invalid/status
  expect_failure "caller curl config" soraswap_curl_for_config "$config" -sS --config /dev/null https://torii.invalid/status
  expect_failure "file-backed caller header" soraswap_curl_for_config "$config" -sS -H @/dev/null https://torii.invalid/status
  expect_failure "external curl trace" soraswap_curl_for_config "$config" -sS --trace "$work_dir/trace" https://torii.invalid/status
  expect_failure "remote-name output" soraswap_curl_for_config "$config" -sS --remote-name https://torii.invalid/status
  expect_failure "expanded authenticated URL" soraswap_curl_for_config "$config" -sS --variable target=https://evil.invalid --expand-url '{{target}}/status'
  expect_failure "request URL parser differential" soraswap_curl_for_config "$config" -sS 'https://torii.invalid\\@evil.invalid/status'
  expect_failure "missing authenticated request URL" soraswap_curl_for_config "$config" -sS
  expect_failure "missing client config" soraswap_curl_for_config "$fixture_root/config/production/missing.toml" -sS https://torii.invalid/status
)

anonymous_production_config="$fixture_root/config/production/anonymous.toml"
sed '/^\[basic_auth\]/,$d' "$config" >"$anonymous_production_config"
chmod 600 "$anonymous_production_config"
soraswap_require_secure_production_client_config "$anonymous_production_config" "$fixture_root" \
  || fail "secure production config without Basic auth was rejected"
anonymous_inspected="$(SORASWAP_ROOT="$fixture_root" SORASWAP_PUBLIC_ENV=production \
  soraswap_inspect_client_config "$anonymous_production_config" curl)" \
  || fail "anonymous production config inspection failed"
[[ "${anonymous_inspected#*$'\n'}" == "-" ]] \
  || fail "anonymous curl config did not retain the explicit no-auth sentinel"
anonymous_response="$(
  export SORASWAP_PUBLIC_ENV=production
  export SORASWAP_ROOT="$fixture_root"
  export SORASWAP_CURL_BIN="$fake_curl" EXPECT_ANONYMOUS=1
  export EXPECTED_LOGIN="$login" EXPECTED_PASSWORD="$password" EXPECTED_BASIC_TOKEN="$basic_token"
  soraswap_curl_for_config "$anonymous_production_config" -sS https://torii.invalid/status
)" || fail "anonymous protected production request failed"
jq -e '.anonymous == true' >/dev/null <<<"$anonymous_response" \
  || fail "anonymous protected production response was not preserved"
(
  export SORASWAP_PUBLIC_ENV=production
  export SORASWAP_ROOT="$fixture_root"
  expect_failure "anonymous production cross-origin request" \
    soraswap_curl_for_config "$anonymous_production_config" -sS https://evil.invalid/status
  expect_failure "anonymous production redirect" \
    soraswap_curl_for_config "$anonymous_production_config" -sSL https://torii.invalid/status
)

partial_auth="$fixture_root/config/production/partial.toml"
sed '/^password = /d' "$config" >"$partial_auth"
chmod 600 "$partial_auth"
expect_failure "partial basic_auth" soraswap_validate_client_basic_auth "$partial_auth"

malformed_auth="$fixture_root/config/production/malformed.toml"
printf '%s\n' 'chain = "broken' >"$malformed_auth"
chmod 600 "$malformed_auth"
expect_failure "malformed TOML" soraswap_validate_client_basic_auth "$malformed_auth"

for hostile_kind in taira-chain taira-origin taira-profile taira-discriminant http-auth string-discriminant negative-discriminant oversized-discriminant missing-private-key; do
  hostile_config="$fixture_root/config/production/${hostile_kind}.toml"
  cp "$config" "$hostile_config"
  case "$hostile_kind" in
    taira-chain)
      perl -0pi -e "s/production-auth-smoke/$SORASWAP_TESTNET_CHAIN_ID_DEFAULT/" "$hostile_config"
      ;;
    taira-origin)
      perl -0pi -e 's#https://torii.invalid#https://taira.sora.org#' "$hostile_config"
      ;;
    taira-profile)
      perl -0pi -e 's/(chain_discriminant = 991)/$1\nprofile = "taira"/' "$hostile_config"
      ;;
    taira-discriminant)
      perl -0pi -e "s/chain_discriminant = 991/chain_discriminant = $SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT/" "$hostile_config"
      ;;
    http-auth)
      perl -0pi -e 's#https://torii.invalid#http://torii.invalid#' "$hostile_config"
      ;;
    string-discriminant)
      perl -0pi -e 's/chain_discriminant = 991/chain_discriminant = "991"/' "$hostile_config"
      ;;
    negative-discriminant)
      perl -0pi -e 's/chain_discriminant = 991/chain_discriminant = -1/' "$hostile_config"
      ;;
    oversized-discriminant)
      perl -0pi -e 's/chain_discriminant = 991/chain_discriminant = 65536/' "$hostile_config"
      ;;
    missing-private-key)
      perl -ni -e 'print unless /^private_key = /' "$hostile_config"
      ;;
  esac
  chmod 600 "$hostile_config"
  expect_failure "$hostile_kind production config" soraswap_require_secure_production_client_config "$hostile_config" "$fixture_root"
done

mode_config="$fixture_root/config/production/mode.toml"
cp "$config" "$mode_config"
chmod 644 "$mode_config"
expect_failure "mode 0644 config" soraswap_require_secure_production_client_config "$mode_config" "$fixture_root"

symlink_config="$fixture_root/config/production/symlink.toml"
ln -s "$config" "$symlink_config"
expect_failure "symlink config" soraswap_require_secure_production_client_config "$symlink_config" "$fixture_root"

hardlink_config="$fixture_root/config/production/hardlink.toml"
ln "$config" "$hardlink_config"
expect_failure "multiply-linked config" soraswap_require_secure_production_client_config "$config" "$fixture_root"
rm -f "$hardlink_config"

tracked_config="$fixture_root/config/production/tracked.toml"
cp "$config" "$tracked_config"
chmod 600 "$tracked_config"
git -C "$fixture_root" add -f config/production/tracked.toml
expect_failure "tracked production config" soraswap_require_secure_production_client_config "$tracked_config" "$fixture_root"

no_discriminant="$fixture_root/config/production/no-discriminant.toml"
awk '!/chain_discriminant/' "$config" >"$no_discriminant"
chmod 600 "$no_discriminant"
(
  unset SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT SORASWAP_CHAIN_DISCRIMINANT
  expect_failure "implicit production discriminant" chain_discriminant_for_env_config production "$no_discriminant"
)
(
  unset SORASWAP_PRODUCTION_CHAIN_DISCRIMINANT
  export SORASWAP_CHAIN_DISCRIMINANT=753
  expect_failure "generic production discriminant" chain_discriminant_for_env_config production "$no_discriminant"
)
[[ "$(chain_discriminant_for_env_config testnet "$no_discriminant")" == "$SORASWAP_TESTNET_CHAIN_DISCRIMINANT_DEFAULT" ]] \
  || fail "testnet discriminant default changed"

export TMPDIR="$work_dir/tmp"
export SORASWAP_PUBLIC_ENV=production
export SORASWAP_ROOT="$fixture_root"
(
  export SORASWAP_TORII_URL=https://evil.invalid/
  expect_failure "cross-origin production Torii override" materialize_cli_compatible_config "$config"
)
materialized="$(materialize_cli_compatible_config "$config")" || fail "CLI config materialization failed"
[[ "$(stat -f '%Lp' "$materialized")" == "600" ]] || fail "materialized CLI config mode is not 0600"
[[ "$materialized" == /* && "${materialized:A}" == "$materialized" ]] \
  || fail "materialized CLI config path is not absolute and canonical"
python3 - "$materialized" "$login" "$password" <<'PY' || fail "materialized CLI config dropped basic_auth"
import pathlib
import sys
import tomllib

with pathlib.Path(sys.argv[1]).open("rb") as handle:
    config = tomllib.load(handle)
assert config["basic_auth"] == {"web_login": sys.argv[2], "password": sys.argv[3]}
PY
soraswap_secure_unlink_owned_file "$materialized" || fail "materialized CLI config cleanup failed"

file_backed_signer_key="$(soraswap_config_private_key_temp_file "$config" canonical-key)" \
  || fail "file-backed signer key extraction failed"
[[ "$file_backed_signer_key" == /* && "${file_backed_signer_key:A}" == "$file_backed_signer_key" ]] \
  || fail "file-backed signer key path is not absolute and canonical"
soraswap_secure_unlink_owned_file "$file_backed_signer_key" \
  || fail "file-backed signer key cleanup failed"

printf '%s' '{"status":"completed"}' \
  | soraswap_assert_client_output_clean "$config" \
  || fail "clean authenticated command output was rejected"
if printf '%s' "$password" | soraswap_assert_client_output_clean "$config" >/dev/null 2>&1; then
  fail "Basic password response echo unexpectedly succeeded"
fi
(( adversarial_rejection_count += 1 ))
output_token_file="$(printf '%s\n' output-token-secret \
  | soraswap_secret_temp_from_stdin output-token)" \
  || fail "could not materialize output-echo token"
if printf '%s' output-token-secret \
  | soraswap_assert_client_output_clean "$config" "$output_token_file" >/dev/null 2>&1; then
  fail "file-backed token response echo unexpectedly succeeded"
fi
(( adversarial_rejection_count += 1 ))
soraswap_secure_unlink_owned_file "$output_token_file" \
  || fail "output-echo token cleanup failed"

owned_secret="$(printf '%s' fixture-secret | soraswap_secret_temp_from_stdin cleanup-race)" \
  || fail "could not create owned secret fixture"
[[ "$owned_secret" == /* && "${owned_secret:A}" == "$owned_secret" ]] \
  || fail "file-backed secret path is not absolute and canonical"
owned_secret_original="$work_dir/owned-secret-original"
mv "$owned_secret" "$owned_secret_original"
printf '%s' replacement >"$owned_secret"
chmod 600 "$owned_secret"
expect_failure "replacement-race owned file cleanup" soraswap_secure_unlink_owned_file "$owned_secret"
[[ -f "$owned_secret" && "$(cat "$owned_secret")" == replacement ]] \
  || fail "replacement file was deleted by identity-bound cleanup"
rm -f -- "$owned_secret" "$owned_secret_original"

linked_secret="$(printf '%s' fixture-secret | soraswap_secret_temp_from_stdin cleanup-link)" \
  || fail "could not create hardlink cleanup fixture"
ln "$linked_secret" "$work_dir/linked-secret-copy"
expect_failure "multiply-linked owned file cleanup" soraswap_secure_unlink_owned_file "$linked_secret"
rm -f "$work_dir/linked-secret-copy"
soraswap_secure_unlink_owned_file "$linked_secret" || fail "single-link owned cleanup failed after hardlink removal"

owned_secret_dir="$(soraswap_secure_temp_directory cleanup-directory)" \
  || fail "could not create identity-owned secret directory"
owned_child="$(printf '%s' directory-secret \
  | TMPDIR="$owned_secret_dir" soraswap_secret_temp_from_stdin directory-child)" \
  || fail "could not create an owned child secret"
[[ -f "$owned_child" ]] || fail "owned child secret was not created inside its private directory"
soraswap_secure_cleanup_owned_directory "$owned_secret_dir" \
  || fail "identity-owned secret directory cleanup failed"
[[ ! -e "$owned_secret_dir" ]] || fail "identity-owned secret directory was retained after cleanup"

replaced_secret_dir="$(soraswap_secure_temp_directory cleanup-directory-race)" \
  || fail "could not create replacement-race directory fixture"
replaced_secret_dir_original="$work_dir/replaced-secret-dir-original"
mv "$replaced_secret_dir" "$replaced_secret_dir_original"
mkdir -m 700 "$replaced_secret_dir"
printf '%s' replacement >"$replaced_secret_dir/replacement"
expect_failure "replacement-race owned directory cleanup" \
  soraswap_secure_cleanup_owned_directory "$replaced_secret_dir"
[[ -f "$replaced_secret_dir/replacement" ]] \
  || fail "owned directory cleanup deleted a replacement directory entry"
rm -rf -- "$replaced_secret_dir" "$replaced_secret_dir_original"

fake_iroha="$work_dir/fake-iroha.zsh"
cat >"$fake_iroha" <<'EOF'
#!/bin/zsh
set -euo pipefail
config_path=""
for arg in "$@"; do
  case "$arg" in
    *"$EXPECTED_LOGIN"*|*"$EXPECTED_PASSWORD"*|*"$EXPECTED_BASIC_TOKEN"*|*"Authorization: Basic"*)
      exit 94
      ;;
  esac
done
for ((idx = 1; idx <= $#; idx++)); do
  if [[ "${@[idx]}" == "--config" && $((idx + 1)) -le $# ]]; then
    config_path="${@[$((idx + 1))]}"
  fi
done
if [[ "${REPLACE_CONFIG_PATH:-0}" == "1" ]]; then
  [[ -n "$config_path" ]]
  mv "$config_path" "$CAPTURED_ORIGINAL_CONFIG"
  printf '%s' replacement >"$config_path"
  chmod 600 "$config_path"
  printf '%s\n' "$config_path" >"$CAPTURED_REPLACEMENT_PATH"
fi
exit 42
EOF
chmod 700 "$fake_iroha"
ensure_iroha_cli_bin() {
  SORASWAP_ACTIVE_IROHA_CLI_BIN="$fake_iroha"
}
(
  export EXPECTED_LOGIN="$login"
  export EXPECTED_PASSWORD="$password"
  export EXPECTED_BASIC_TOKEN="$basic_token"
  iroha_cli --config "$config" ledger account get --id example >/dev/null 2>&1
) && fail "failing fake Iroha command unexpectedly succeeded"
if find "$TMPDIR" -type f -name 'soraswap-cli-config.*' -print -quit | grep -q .; then
  fail "materialized credential config was retained after CLI failure"
fi
captured_original_config="$work_dir/captured-original-config"
captured_replacement_path="$work_dir/captured-replacement-path"
(
  export EXPECTED_LOGIN="$login" EXPECTED_PASSWORD="$password" EXPECTED_BASIC_TOKEN="$basic_token"
  export REPLACE_CONFIG_PATH=1
  export CAPTURED_ORIGINAL_CONFIG="$captured_original_config"
  export CAPTURED_REPLACEMENT_PATH="$captured_replacement_path"
  iroha_cli --config "$config" ledger account get --id example >/dev/null 2>&1
) && fail "replacement-race fake Iroha command unexpectedly succeeded"
replacement_config_path="$(cat "$captured_replacement_path")"
[[ -f "$replacement_config_path" && "$(cat "$replacement_config_path")" == replacement ]] \
  || fail "CLI cleanup deleted a replacement config path"
rm -f -- "$replacement_config_path" "$captured_original_config" "$captured_replacement_path"

operator="i105operator"
permission_state="$work_dir/permission-state"
export SORASWAP_AUTHORITY="$operator"
iroha_cli_json() {
  if [[ "$*" == *" ledger account get "* ]]; then
    jq -cn --arg id "${EXACT_ACCOUNT_READBACK_ID:-${@[-1]}}" '{account_id: $id}'
    return 0
  fi
  if [[ -f "$permission_state" ]]; then
    cat "$permission_state"
  else
    printf '%s\n' '[]'
  fi
}
cat >"$permission_state" <<EOF
[
  {"name":"Admin","payload":null},
  {"name":"AssetOps","payload":null},
  {"name":"CanRegisterTrigger","payload":{"authority":"$operator"}},
  {"name":"CanExecuteTrigger","payload":{"trigger":"soraswap_escrow_settle"}}
]
EOF
require_production_operator_permissions "$config" "$operator" \
  || fail "complete production operator permission set was rejected"
operator_readiness="$(production_operator_permission_readiness_json "$config" "$operator")" \
  || fail "production operator readiness could not be rendered"
jq -e --arg operator "$operator" '
  .ready == true
  and .account_present == true
  and .account_readback.matched == true
  and .account_readback.observed_ids == [$operator]
' >/dev/null <<<"$operator_readiness" || fail "operator readiness omitted exact account readback"
(
  export EXACT_ACCOUNT_READBACK_ID=i105different
  expect_failure "mismatched production operator account readback" \
    require_production_operator_permissions "$config" "$operator"
)
printf '%s\n' '[{"name":"Admin","payload":null}]' >"$permission_state"
expect_failure "missing production operator permissions" require_production_operator_permissions "$config" "$operator"

grant_marker="$work_dir/grant-called"
iroha_cli_with_authority_fee() {
  : >"$grant_marker"
}
expect_failure "production operator self-grant" ensure_unit_account_permission "$config" "$operator" AssetOps
[[ ! -e "$grant_marker" ]] || fail "production operator self-grant reached the mutation command"

export SORASWAP_PUBLIC_ENV=testnet
testnet_subject="i105testnetsubject"
iroha_cli_with_authority_fee() {
  cat >"$permission_state" <<'EOF'
[{"name":"AssetOps","payload":null}]
EOF
  : >"$grant_marker"
}
ensure_unit_account_permission "$config" "$testnet_subject" AssetOps \
  || fail "testnet permission provisioning behavior regressed"
[[ -e "$grant_marker" ]] || fail "testnet permission provisioning did not invoke the grant path"

numeric_gte 10 10 || fail "minimum fee equality was rejected"
expect_failure "fee balance below minimum" numeric_gte 9.99 10
(
  unset SORASWAP_PRODUCTION_MIN_FEE_BALANCE
  expect_failure "missing approved production fee minimum" soraswap_production_min_fee_balance
)
SORASWAP_PRODUCTION_MIN_FEE_BALANCE=10 \
  soraswap_production_min_fee_balance >/dev/null \
  || fail "approved production fee minimum was rejected"

expect_failure "missing production fee asset id" env \
  SORASWAP_PUBLIC_ENV=production \
  SORASWAP_PRODUCTION_FEE_ASSET_DEFINITION_ID= \
  zsh -c 'source "$1"; fee_asset_definition_id_for_config "$2"' zsh "$repo_root/scripts/common.sh" "$config"

zsh "$repo_root/tests/sorafs_publish_summary_validation_smoke.sh" >/dev/null \
  || fail "current SoraFS publish summary validators rejected their focused fixtures"

rg -Fq -- 'refusing a non-canonical file-backed secret/config path' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not reject non-canonical candidate secret/config paths"
rg -Fq -- '--private-key-file="$publisher_private_key_file"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not require file-backed private key"
rg -Fq -- '--network-id="$manifest_network_id"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not submit the exact configured genesis NetworkId"
rg -Fq -- '--network-prefix="$manifest_network_prefix"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not submit the configured account chain discriminant"
rg -Fq -- 'storage prepare' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not prepare current provider-ingest artifacts"
rg -Fq -- 'state: "awaiting_finalized_provider_assignment"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not report the current provider-assignment state"
rg -Fq -- 'direct_http_ingest: false' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher claims retired direct HTTP ingest"
rg -Fq -- 'SORASWAP_TRADER_API_GATEWAY_PROPAGATION_ATTEMPTS' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not expose current gateway propagation controls"
if rg -n -- 'storage pin|--resolve-submitted-epoch|--client-config|pin_summary|SORASWAP_TRADER_API_STORAGE_PIN_PROPAGATION' \
  "$repo_root/scripts/publish_trader_api_bundle.sh" >/dev/null; then
  fail "publisher retains a retired SoraFS publish interface"
fi
rg -Fq -- 'current SoraFS manifest submit summary is missing, invalid, or mismatched' \
  "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not fail closed on invalid current manifest-submit summaries"
rg -Fq -- 'and .status == 202' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not require the current accepted manifest-registration status"
rg -Fq -- 'and .submission_mode == "pin_register_http"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not validate the current manifest submission mode"
rg -Fq -- 'and .torii_response == $response' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not bind the current CLI summary to its exact Torii response"
if rg -n -- 'json_file_or_null|extract_last_json_object|status: 200,[[:space:]]*$|summary_path: \$summary_path' \
  "$repo_root/scripts/publish_trader_api_bundle.sh" >/dev/null; then
  fail "publisher retains a legacy CLI response-shape fallback"
fi
rg -Fq -- 'api_token_args=(--api-token "$api_token_value")' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not use the current SoraCloud inline API-token option"
rg -Fq -- 'soraswap_assert_client_output_clean "$config" "$api_token_file"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not suppress inline API-token echoes"
if rg -Fq -- '--api-token-file' "$repo_root/scripts/publish_trader_api_bundle.sh"; then
  fail "publisher retains the unsupported SoraCloud API-token-file option"
fi
rg -Fq -- 'soracloud service config-set' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not use the top-level SoraCloud service config-set command"
if rg -Fq -- 'app soracloud config-set' "$repo_root/scripts/publish_trader_api_bundle.sh"; then
  fail "publisher retains the rejected nested app SoraCloud command"
fi
if rg -n -- '--private-key="\$\(|--api-token "\$SORASWAP_TORII_API_TOKEN"' "$repo_root/scripts/publish_trader_api_bundle.sh" >/dev/null; then
  fail "publisher bypasses its protected secret handling"
fi
rg -Fq -- 'seed_hex="$(printf '\''%s'\'' "$seed" | json_sha256)"' "$repo_root/scripts/bootstrap_contract_state.sh" \
  || fail "contract-subject signer seed is not deterministically SHA-256 derived"
rg -Fq -- '--seed-hex "$seed_hex"' "$repo_root/scripts/bootstrap_contract_state.sh" \
  || fail "contract-subject signer does not use the current Kagami seed-hex option"
if rg -Fq -- '--seed "$seed"' "$repo_root/scripts/bootstrap_contract_state.sh"; then
  fail "contract-subject signer retains the retired Kagami seed option"
fi
semantic_contract_seed='iroha:contract-subject:v1:fixture-contract'
expected_contract_seed_hex='771ba8231d7cbaf7c7c5634ef275ac9a28e4926de04b1aeaeac9b8d1d68b3757'
[[ "$(printf '%s' "$semantic_contract_seed" | json_sha256)" == "$expected_contract_seed_hex" ]] \
  || fail "contract-subject semantic seed SHA-256 derivation is not stable"
rg -Fq 'ensure_public_signer_ready "$config" "$SORASWAP_AUTHORITY" verify-only' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not verify signer fee readiness"
rg -Fq 'require_production_operator_permissions "$config" "$SORASWAP_AUTHORITY"' "$repo_root/scripts/publish_trader_api_bundle.sh" \
  || fail "publisher does not verify production operator permissions"
[[ "$(rg -F -c 'soraswap_assert_client_output_clean "$config"' "$repo_root/scripts/publish_trader_api_bundle.sh")" -ge 2 ]] \
  || fail "publisher does not suppress credential echoes from both SoraFS and SoraCloud candidate interfaces"
rg -Fq 'authenticated Torii response credential echo was suppressed' "$repo_root/scripts/common.sh" \
  || fail "authenticated curl wrapper does not fail closed on upstream credential echoes"

if rg -n '\b(pkill|killall)\b' \
  "$repo_root/scripts/common.sh" \
  "$repo_root/scripts/bootstrap_contract_state.sh" \
  "$repo_root/scripts/publish_trader_api_bundle.sh" \
  "$repo_root/scripts/serve_contract_console.py" >/dev/null; then
  fail "Phase-A scripts contain name-wide process cleanup"
fi

rg -q '^test-production-auth-config:' "$repo_root/Makefile" \
  || fail "Makefile does not expose test-production-auth-config"
python3 - "$repo_root/Makefile" <<'PY' \
  || fail "test-public-env-helpers does not enforce test-production-auth-config"
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
target = lines.index("test-public-env-helpers:")
recipe = []
for line in lines[target + 1 :]:
    if line and not line.startswith("\t"):
        break
    recipe.append(line)
assert any("$(MAKE) test-production-auth-config" in line for line in recipe)
PY

python3 - "$repo_root" <<'PY' || fail "a production-reachable script bypasses soraswap_curl_for_config"
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
paths = [
    "scripts/common.sh",
    "scripts/taira_preflight.sh",
    "scripts/refresh_public_chain_snapshot.sh",
    "scripts/deploy_public.sh",
    "scripts/bootstrap_contract_state.sh",
    "scripts/public_nested_call_probe.sh",
    "scripts/trader_public.sh",
    "scripts/contract_console_public_smoke.sh",
    "scripts/publish_trader_api_bundle.sh",
]
raw_curl = re.compile(r"(?<![A-Za-z0-9_])curl\s+(?=[\-$\"'])")
violations = []
for relative in paths:
    for line_number, line in enumerate((root / relative).read_text().splitlines(), 1):
        if raw_curl.search(line):
            violations.append(f"{relative}:{line_number}")
if violations:
    print("raw curl bypasses: " + ", ".join(violations), file=sys.stderr)
    raise SystemExit(1)
PY

(( adversarial_rejection_count >= 26 )) \
  || fail "adversarial rejection coverage unexpectedly fell to $adversarial_rejection_count cases"
echo "production auth/config smoke passed ($adversarial_rejection_count adversarial rejection checks)"
