#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/isolated_e2e.sh"

fail() {
  echo "isolated E2E safety test failed: $*" >&2
  exit 1
}

fixture_root="$(mktemp -d "$ROOT/tmp/isolated-e2e-safety.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

existing_dir="$fixture_root/existing"
mkdir "$existing_dir"
existing_status=0
isolated_reserve_localnet_dir "$existing_dir" >/dev/null 2>&1 || existing_status="$?"
[[ "$existing_status" != "0" ]] || fail "existing run directory was accepted"
[[ -d "$existing_dir" ]] || fail "existing run directory was modified"

outside_dir="$fixture_root/outside"
outside_status=0
isolated_resolve_localnet_dir "$outside_dir" >/dev/null 2>&1 || outside_status="$?"
[[ "$outside_status" != "0" ]] || fail "run directory outside the repository tmp root was accepted"

expected_sha="0123456789abcdef0123456789abcdef01234567"
SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA="$expected_sha"
export SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA
[[ "$(isolated_candidate_tag)" == "01234567" ]] || fail "expected SHA was not shortened for the run name"
expected_default="$ROOT/tmp/iroha-localnet-verify-01234567-20260711T120000Z-4242"
[[ "$(isolated_default_localnet_dir 01234567 20260711T120000Z 4242)" == "$expected_default" ]] \
  || fail "default exact-candidate run directory is not unique and timestamped"
unset SORASWAP_LOCAL_ACCEPTANCE_EXPECTED_GIT_SHA
[[ "$(isolated_candidate_tag)" == "dev" ]] || fail "development run tag is not dev"

matcher_config="$fixture_root/peer0.toml"
isolated_command_matches_peer_config \
  "$fixture_root/bin/iroha3d --config $matcher_config" "$matcher_config" \
  || fail "exact iroha3d config command was rejected"
! isolated_command_matches_peer_config \
  "$fixture_root/bin/not-iroha3d --config $matcher_config" "$matcher_config" \
  || fail "non-iroha3d executable was accepted"
! isolated_command_matches_peer_config \
  "$fixture_root/bin/iroha3d --config $matcher_config.other" "$matcher_config" \
  || fail "config path prefix was accepted as an exact match"
! isolated_command_matches_peer_config \
  "$fixture_root/bin/iroha3d --config $matcher_config --config=$matcher_config" "$matcher_config" \
  || fail "duplicate config arguments were accepted"

(
  isolated_port_pair_bindable() {
    [[ "$1" == "49280" && "$2" == "49437" ]]
  }
  [[ "$(isolated_select_port_pair 49180 49337 3)" == "49280 49437" ]] \
    || fail "occupied default pair did not advance both ports by 100"
)

(
  isolated_port_pair_bindable() {
    return 1
  }
  range_status=0
  isolated_select_port_pair 65500 65510 2 >/dev/null 2>&1 || range_status="$?"
  [[ "$range_status" != "0" ]] || fail "port selection crossed the valid TCP port range"
)

python_bin="$(isolated_python3_bin)"
listener_ready="$fixture_root/listener-port"
"$python_bin" - "$listener_ready" <<'PY' &
import socket
import sys
import time

listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.bind(("127.0.0.1", 0))
listener.listen(1)
with open(sys.argv[1], "w", encoding="utf-8") as destination:
    destination.write(str(listener.getsockname()[1]))
time.sleep(1)
PY
listener_pid="$!"
for _ in {1..100}; do
  [[ -s "$listener_ready" ]] && break
  sleep 0.01
done
[[ -s "$listener_ready" ]] || fail "loopback listener fixture did not start"
occupied_port="$(<"$listener_ready")"
wildcard_probe_status=0
isolated_port_pair_bindable "$occupied_port" "$(( occupied_port == 65535 ? occupied_port - 1 : occupied_port + 1 ))" \
  >/dev/null 2>&1 || wildcard_probe_status="$?"
[[ "$wildcard_probe_status" != "0" ]] || fail "wildcard bind probe missed a loopback-only listener"
wait "$listener_pid"

mock_bin="$fixture_root/mock-bin"
mkdir "$mock_bin"
cat > "$mock_bin/ps" <<'EOF'
#!/bin/sh
state="$(cat "$ISOLATED_TEST_PS_STATE")"
case " $* " in
  *" -p 4242 "*)
    ;;
  *)
    case "$*" in
      *stat=*) printf 'S\n' ;;
      *command=*) printf '/bin/zsh isolated-e2e-safety\n' ;;
      *) exit 2 ;;
    esac
    exit 0
    ;;
esac
case "$*" in
  *stat=*)
    case "$state" in
      live) printf 'S\n' ;;
      zombie) printf 'Z\n' ;;
      error) printf 'permission denied\n' >&2; exit 1 ;;
      *) exit 1 ;;
    esac
    ;;
  *command=*)
    case "$state" in
      live|zombie) printf '%s\n' "$ISOLATED_TEST_PS_COMMAND" ;;
      *) exit 1 ;;
    esac
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$mock_bin/ps"

make_peer_fixture() {
  local name="$1"
  local fixture="$fixture_root/$name"

  mkdir "$fixture"
  : > "$fixture/peer0.toml"
  printf '4242\n' > "$fixture/peer0.pid"
  printf '%s\n' "$fixture"
}

mismatch_dir="$(make_peer_fixture mismatch)"
mismatch_marker="$mismatch_dir/stop-invoked"
cat > "$mismatch_dir/stop.sh" <<'EOF'
#!/bin/sh
: > "$ISOLATED_TEST_STOP_MARKER"
exit 0
EOF
chmod +x "$mismatch_dir/stop.sh"
printf 'live\n' > "$mismatch_dir/ps-state"
mismatch_status=0
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$mismatch_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config $mismatch_dir/peer0.toml.other"
  export ISOLATED_TEST_STOP_MARKER="$mismatch_marker"
  isolated_cleanup_localnet "$mismatch_dir"
) >/dev/null 2>&1 || mismatch_status="$?"
[[ "$mismatch_status" == "70" ]] || fail "mismatched live PID did not fail the pre-audit"
[[ ! -e "$mismatch_marker" ]] || fail "mismatched live PID reached generated stop.sh"
[[ -f "$mismatch_dir/peer0.pid" ]] || fail "mismatched live PID evidence was removed"

inspection_error_dir="$(make_peer_fixture inspection-error)"
inspection_error_marker="$inspection_error_dir/stop-invoked"
cat > "$inspection_error_dir/stop.sh" <<'EOF'
#!/bin/sh
: > "$ISOLATED_TEST_STOP_MARKER"
exit 0
EOF
chmod +x "$inspection_error_dir/stop.sh"
printf 'error\n' > "$inspection_error_dir/ps-state"
inspection_error_status=0
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$inspection_error_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config $inspection_error_dir/peer0.toml"
  export ISOLATED_TEST_STOP_MARKER="$inspection_error_marker"
  isolated_cleanup_localnet "$inspection_error_dir"
) >/dev/null 2>&1 || inspection_error_status="$?"
[[ "$inspection_error_status" == "70" ]] || fail "process inspection error did not fail closed"
[[ ! -e "$inspection_error_marker" ]] || fail "process inspection error reached generated stop.sh"
[[ -f "$inspection_error_dir/peer0.pid" ]] || fail "process inspection error removed PID evidence"

stop_failure_dir="$(make_peer_fixture stop-failure)"
cat > "$stop_failure_dir/stop.sh" <<'EOF'
#!/bin/sh
exit 37
EOF
chmod +x "$stop_failure_dir/stop.sh"
printf 'live\n' > "$stop_failure_dir/ps-state"
stop_failure_status=0
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$stop_failure_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config $stop_failure_dir/peer0.toml"
  isolated_cleanup_localnet "$stop_failure_dir"
) >/dev/null 2>&1 || stop_failure_status="$?"
[[ "$stop_failure_status" == "37" ]] || fail "generated stop.sh failure status was not propagated"
[[ -f "$stop_failure_dir/peer0.pid" ]] || fail "failed stop removed diagnostic PID evidence"

still_live_dir="$(make_peer_fixture still-live)"
cat > "$still_live_dir/stop.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$still_live_dir/stop.sh"
printf 'live\n' > "$still_live_dir/ps-state"
still_live_status=0
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$still_live_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config=$still_live_dir/peer0.toml"
  isolated_cleanup_localnet "$still_live_dir"
) >/dev/null 2>&1 || still_live_status="$?"
[[ "$still_live_status" == "72" ]] || fail "still-live peer postcondition did not fail closed"

zombie_dir="$(make_peer_fixture zombie)"
cat > "$zombie_dir/stop.sh" <<'EOF'
#!/bin/sh
rm -f "$ISOLATED_TEST_PID_FILE"
exit 0
EOF
chmod +x "$zombie_dir/stop.sh"
printf 'zombie\n' > "$zombie_dir/ps-state"
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$zombie_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config $zombie_dir/peer0.toml"
  export ISOLATED_TEST_PID_FILE="$zombie_dir/peer0.pid"
  isolated_cleanup_localnet "$zombie_dir"
) >/dev/null 2>&1 || fail "zombie peer state was treated as live"

success_dir="$(make_peer_fixture success)"
cat > "$success_dir/stop.sh" <<'EOF'
#!/bin/sh
printf 'stopped\n' > "$ISOLATED_TEST_PS_STATE"
rm -f "$ISOLATED_TEST_PID_FILE"
exit 0
EOF
chmod +x "$success_dir/stop.sh"
printf 'live\n' > "$success_dir/ps-state"
(
  export PATH="$mock_bin:$PATH"
  export ISOLATED_TEST_PS_STATE="$success_dir/ps-state"
  export ISOLATED_TEST_PS_COMMAND="$fixture_root/bin/iroha3d --config $success_dir/peer0.toml"
  export ISOLATED_TEST_PID_FILE="$success_dir/peer0.pid"
  isolated_cleanup_localnet "$success_dir"
) >/dev/null 2>&1 || fail "exact generated-stop cleanup failed"
[[ "$(<"$success_dir/ps-state")" == "stopped" ]] || fail "exact generated stop was not invoked"
[[ ! -e "$success_dir/peer0.pid" ]] || fail "successful cleanup left a PID file"

[[ "$(isolated_resolve_final_status 23 72)" == "23" ]] \
  || fail "cleanup failure replaced the original run failure status"
[[ "$(isolated_resolve_final_status 0 72)" == "72" ]] \
  || fail "cleanup failure after a successful run did not become the exit status"

handler_original_status=0
(
  set +e
  export SORASWAP_LOCALNET_DIR="$fixture_root/handler-original"
  isolated_cleanup_localnet() {
    return 72
  }
  false
  isolated_exit_handler
) >/dev/null 2>&1 || handler_original_status="$?"
[[ "$handler_original_status" == "1" ]] \
  || fail "exit handler did not preserve the original run failure"

handler_cleanup_status=0
(
  export SORASWAP_LOCALNET_DIR="$fixture_root/handler-cleanup"
  isolated_cleanup_localnet() {
    return 72
  }
  isolated_exit_handler
) >/dev/null 2>&1 || handler_cleanup_status="$?"
[[ "$handler_cleanup_status" == "72" ]] \
  || fail "exit handler did not surface cleanup failure after a successful run"

empty_path="$fixture_root/empty-path"
mkdir "$empty_path"
missing_ps_status=0
(
  export PATH="$empty_path"
  isolated_require_ps
) >/dev/null 2>&1 || missing_ps_status="$?"
[[ "$missing_ps_status" == "70" ]] || fail "missing ps did not fail closed"

unsupported_ps_path="$fixture_root/unsupported-ps-path"
mkdir "$unsupported_ps_path"
cat > "$unsupported_ps_path/ps" <<'EOF'
#!/bin/sh
echo 'unsupported ps invocation' >&2
exit 2
EOF
chmod +x "$unsupported_ps_path/ps"
unsupported_ps_status=0
(
  export PATH="$unsupported_ps_path:$PATH"
  isolated_require_ps
) >/dev/null 2>&1 || unsupported_ps_status="$?"
[[ "$unsupported_ps_status" == "70" ]] || fail "unsupported ps options did not fail closed"

! rg -n '\b(kill|pkill|killall)\b|local_down\.sh|run_with_timeout|process_tree_pids' \
  "$ROOT/tests/isolated_e2e.sh" >/dev/null \
  || fail "isolated wrapper contains a signal or broad-cleanup path outside generated stop.sh"
rg -Fq 'candidate.bind(("0.0.0.0", int(raw_port)))' "$ROOT/tests/isolated_e2e.sh" \
  || fail "port availability is not probed on the wildcard listener"
! rg -Fq '/usr/bin/python3' "$ROOT/tests/isolated_e2e.sh" \
  || fail "isolated wrapper hardcodes a non-portable python3 path"

echo "isolated E2E safety smoke ok"
