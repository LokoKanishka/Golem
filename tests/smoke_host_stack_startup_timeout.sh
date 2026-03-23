#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
shim_dir="$tmpdir/shims"
state_dir="$tmpdir/state"
diagnostics_root="$tmpdir/diagnostics-host"
auto_state="$tmpdir/auto-state.json"
launch_output="$tmpdir/launch-output.txt"
service_name="openclaw-gateway.service"
api_service_name="golem-task-panel-http-startup-timeout-smoke-$$.service"
bridge_service_name="golem-whatsapp-bridge-startup-timeout-smoke-$$.service"
real_python3="$(command -v python3)"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$shim_dir" "$state_dir"

cat >"$shim_dir/python3" <<EOF
#!/usr/bin/env bash
set -euo pipefail

real_python3="$real_python3"
state_dir="$state_dir"
script="\${1:-}"

json_ok() {
  printf '%s\n' "\$1"
}

json_fail() {
  printf '%s\n' "\$1"
}

next_health_state() {
  local key="\$1"
  local counter_file="\$state_dir/\${key}.count"
  local count=0
  if [ -f "\$counter_file" ]; then
    count="\$(cat "\$counter_file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$counter_file"
  printf '%s\n' "\$count"
}

case "\$script" in
  */task_panel_http_ctl.py)
    shift
    command="\${1:-}"
    case "\$command" in
      start|stop|restart)
        exit 0
        ;;
      status)
        json_ok '{"service_name":"'"$api_service_name"'","service_active_state":"active","service_enabled":"enabled","pid":41001,"base_url":"http://127.0.0.1:8765"}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_health_state task_api_healthcheck)"
        if [ "\$count" -le 1 ]; then
          json_ok '{"ok":true,"reasons":[]}'
          exit 0
        fi
        json_fail '{"ok":false,"reasons":["startup timeout waiting for task_api readiness"]}'
        exit 1
        ;;
    esac
    ;;
  */task_whatsapp_bridge_ctl.py)
    shift
    command="\${1:-}"
    case "\$command" in
      start|stop|restart)
        exit 0
        ;;
      status)
        json_ok '{"service_name":"'"$bridge_service_name"'","service_active_state":"active","service_enabled":"enabled","pid":41002,"runtime":{"status":"starting","last_operation":"booting"}}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_health_state bridge_healthcheck)"
        if [ "\$count" -le 1 ]; then
          json_ok '{"ok":true,"reasons":[]}'
          exit 0
        fi
        json_fail '{"ok":false,"reasons":["startup timeout waiting for whatsapp_bridge readiness"]}'
        exit 1
        ;;
    esac
    ;;
esac

exec "\$real_python3" "\$@"
EOF

cat >"$shim_dir/systemctl" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "is-active" ] && [ "\${3:-}" = "$service_name" ]; then
  printf 'active\n'
  exit 0
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "show" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    cat <<'OUT'
Id=shimmed.service
LoadState=loaded
ActiveState=active
SubState=running
MainPID=41000
UnitFileState=enabled
FragmentPath=/tmp/shimmed.service
Result=success
ExecMainStatus=0
OUT
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "status" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    printf '● %s - shimmed active service\n' "\$unit"
    printf '   Active: active (running)\n'
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "start" ] && [ "\${3:-}" = "$service_name" ]; then
  exit 0
fi

printf 'unexpected systemctl invocation: %s\n' "$*" >&2
exit 2
EOF

cat >"$shim_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "status" ]; then
  printf 'Runtime: running\n'
  printf 'RPC probe: ok\n'
  exit 0
fi

if [ "${1:-}" = "dashboard" ] && [ "${2:-}" = "--no-open" ]; then
  printf 'Dashboard URL: http://127.0.0.1:3333/\n'
  exit 0
fi

printf 'unexpected openclaw invocation\n' >&2
exit 2
EOF

cat >"$shim_dir/google-chrome" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$shim_dir/code" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$shim_dir/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x \
  "$shim_dir/python3" \
  "$shim_dir/systemctl" \
  "$shim_dir/openclaw" \
  "$shim_dir/google-chrome" \
  "$shim_dir/code" \
  "$shim_dir/sleep"

set +e
PATH="$shim_dir:$PATH" \
GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
GOLEM_HOST_AUTO_DIAGNOSE_STATE_FILE="$auto_state" \
GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS=300 \
GOLEM_LAUNCH_WAIT_SECONDS=0 \
GOLEM_STACK_WAIT_SECONDS=0 \
GOLEM_TASK_API_SERVICE_NAME="$api_service_name" \
GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME="$bridge_service_name" \
./scripts/launch_golem.sh >"$launch_output" 2>&1
launch_exit=$?
set -e

[ "$launch_exit" -ne 0 ] || {
  echo "FAIL: launch_golem should fail for stack_startup_timeout smoke" >&2
  exit 1
}

GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
./scripts/golem_host_last_snapshot.sh >"$tmpdir/helper.txt"

python3 - "$launch_output" "$diagnostics_root" "$tmpdir/helper.txt" <<'PY'
import json
import pathlib
import sys

launch_output = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[2])
helper = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]
summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"
summary = summary_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "GOLEM HOST FAILURE SUMMARY" in launch_output, launch_output
assert "reason: stack_startup_timeout" in launch_output, launch_output
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in launch_output, launch_output
assert f"snapshot: {snapshot_dir}" in launch_output, launch_output
assert f"look_first: {summary_path}" in launch_output, launch_output
assert f"look_next: {manifest_path}" in launch_output, launch_output
assert "helper: ./scripts/golem_host_last_snapshot.sh" in launch_output, launch_output
assert "ERROR: el stack local task api + bridge no quedó sano a tiempo." in launch_output, launch_output

failure_block = launch_output[launch_output.index("GOLEM HOST FAILURE SUMMARY"):].splitlines()[:10]
assert len([line for line in failure_block if line.strip()]) <= 10, failure_block

assert "trigger_source: launch_golem" in summary, summary
assert "trigger_reason: stack_startup_timeout" in summary, summary
assert "gateway_context: active, runtime running, rpc ok | gateway_last_signal: RPC probe: ok" in summary, summary
assert "task_api_active: active | whatsapp_bridge_active: active" in summary, summary
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in summary, summary
assert "second_action: mirar pids y puertos relevantes en summary.txt" in summary, summary
assert "stack_healthcheck: FAIL" in summary, summary

assert manifest["trigger"]["source"] == "launch_golem", manifest
assert manifest["trigger"]["reason"] == "stack_startup_timeout", manifest
assert manifest["quick_triage"]["suggested_first_action"] == "confirmar task_api y whatsapp_bridge antes de reintentar start", manifest
assert manifest["quick_triage"]["second_action"] == "mirar pids y puertos relevantes en summary.txt", manifest
assert manifest["task_api"]["active_state"] == "active", manifest
assert manifest["whatsapp_bridge"]["active_state"] == "active", manifest
assert manifest["stack_healthcheck_exit_code"] != 0, manifest

assert "GOLEM HOST LAST SNAPSHOT" in helper, helper
assert "trigger_source: launch_golem" in helper, helper
assert "trigger_reason: stack_startup_timeout" in helper, helper
assert "gateway_context / gateway_last_signal: active, runtime running, rpc ok | RPC probe: ok" in helper, helper
assert "task_api_active / whatsapp_bridge_active: active | active" in helper, helper
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in helper, helper
assert "second_action: mirar pids y puertos relevantes en summary.txt" in helper, helper
assert f"look_first: {summary_path}" in helper, helper
assert f"look_next: {manifest_path}" in helper, helper

print("SMOKE_HOST_STACK_STARTUP_TIMEOUT_OK")
print(f"HOST_STACK_STARTUP_TIMEOUT_SNAPSHOT {snapshot_dir}")
print(f"HOST_STACK_STARTUP_TIMEOUT_LOOK_FIRST {summary_path}")
PY
