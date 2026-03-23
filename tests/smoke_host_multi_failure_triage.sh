#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

real_python3="$(command -v python3)"

run_case() {
  local case_name="$1"
  local gateway_mode="$2"
  local task_api_state="$3"
  local bridge_state="$4"
  local expected_first="$5"
  local expected_second="$6"

  local tmpdir shim_dir state_dir diagnostics_root auto_state launch_output helper_txt
  local api_service_name bridge_service_name
  local gateway_reason_state gateway_context gateway_last_signal gateway_runtime_text gateway_runtime_exit gateway_systemd_late_state
  local task_api_reason_state task_api_ready_json task_api_health_json task_api_health_exit
  local bridge_reason_state bridge_ready_json bridge_runtime_state bridge_health_json bridge_health_exit bridge_last_operation

  tmpdir="$(mktemp -d)"
  shim_dir="$tmpdir/shims"
  state_dir="$tmpdir/state"
  diagnostics_root="$tmpdir/diagnostics-host"
  auto_state="$tmpdir/auto-state.json"
  launch_output="$tmpdir/launch-output.txt"
  helper_txt="$tmpdir/helper.txt"
  api_service_name="golem-task-panel-http-${case_name}-smoke-$$.service"
  bridge_service_name="golem-whatsapp-bridge-${case_name}-smoke-$$.service"

  mkdir -p "$shim_dir" "$state_dir"

  case "$gateway_mode" in
    ok)
      gateway_reason_state="OK"
      gateway_context="active, runtime running, rpc ok"
      gateway_last_signal="RPC probe: ok"
      gateway_runtime_text=$'Gateway: running\nRuntime: running\nRPC probe: ok\n'
      gateway_runtime_exit=0
      gateway_systemd_late_state="active"
      ;;
    failed)
      gateway_reason_state="FAIL"
      gateway_context="systemd failed"
      gateway_last_signal="(none)"
      gateway_runtime_text=$'gateway service unavailable\n'
      gateway_runtime_exit=1
      gateway_systemd_late_state="failed"
      ;;
    *)
      echo "unsupported gateway mode: $gateway_mode" >&2
      return 1
      ;;
  esac

  case "$task_api_state" in
    active)
      task_api_reason_state="OK"
      task_api_ready_json="true"
      task_api_health_json='{"ok":true,"reasons":[]}'
      task_api_health_exit=0
      ;;
    inactive)
      task_api_reason_state="FAIL"
      task_api_ready_json="false"
      task_api_health_json='{"ok":false,"reasons":["task_api_unhealthy"]}'
      task_api_health_exit=1
      ;;
    *)
      echo "unsupported task_api state: $task_api_state" >&2
      return 1
      ;;
  esac

  case "$bridge_state" in
    active)
      bridge_reason_state="OK"
      bridge_ready_json="true"
      bridge_runtime_state="running"
      bridge_health_json='{"ok":true,"reasons":[]}'
      bridge_health_exit=0
      bridge_last_operation="healthy"
      ;;
    inactive)
      bridge_reason_state="FAIL"
      bridge_ready_json="false"
      bridge_runtime_state="stopped"
      bridge_health_json='{"ok":false,"reasons":["bridge_unhealthy"]}'
      bridge_health_exit=1
      bridge_last_operation="bridge_unhealthy"
      ;;
    *)
      echo "unsupported bridge state: $bridge_state" >&2
      return 1
      ;;
  esac

  cat >"$shim_dir/python3" <<EOF
#!/usr/bin/env bash
set -euo pipefail

real_python3="$real_python3"
state_dir="$state_dir"
script="\${1:-}"

next_count() {
  local key="\$1"
  local file="\$state_dir/\${key}.count"
  local count=0
  if [ -f "\$file" ]; then
    count="\$(cat "\$file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$file"
  printf '%s\n' "\$count"
}

case "\$script" in
  */task_panel_http_ctl.py)
    shift
    command="\${1:-}"
    case "\$command" in
      start|stop|restart|service-install|service-uninstall)
        exit 0
        ;;
      status)
        printf '%s\n' '{"service_name":"$api_service_name","service_active_state":"$task_api_state","service_enabled":"enabled","pid":42001,"api_ready":$task_api_ready_json,"base_url":"http://127.0.0.1:8765"}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count task_api_health)"
        if [ "\$count" -le 2 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '$task_api_health_json'
        exit $task_api_health_exit
        ;;
    esac
    ;;
  */task_whatsapp_bridge_ctl.py)
    shift
    command="\${1:-}"
    case "\$command" in
      start|stop|restart|service-install|service-uninstall)
        exit 0
        ;;
      status)
        printf '%s\n' '{"service_name":"$bridge_service_name","service_active_state":"$bridge_state","service_enabled":"enabled","pid":42002,"api_ready":$bridge_ready_json,"runtime":{"status":"$bridge_runtime_state","last_operation":"$bridge_last_operation"}}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count bridge_health)"
        if [ "\$count" -le 2 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '$bridge_health_json'
        exit $bridge_health_exit
        ;;
    esac
    ;;
esac

exec "\$real_python3" "\$@"
EOF

  cat >"$shim_dir/systemctl" <<EOF
#!/usr/bin/env bash
set -euo pipefail

state_dir="$state_dir"
gateway_unit="openclaw-gateway.service"

next_gateway_state() {
  local file="\$state_dir/gateway_is_active.count"
  local count=0
  if [ -f "\$file" ]; then
    count="\$(cat "\$file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$file"
  if [ "\$count" -le 2 ]; then
    printf 'active\n'
  else
    printf '%s\n' "$gateway_systemd_late_state"
  fi
}

render_show() {
  local active_state="\$1"
  local sub_state="\$2"
  local pid="\$3"
  cat <<OUT
Id=shimmed.service
LoadState=loaded
ActiveState=\${active_state}
SubState=\${sub_state}
MainPID=\${pid}
UnitFileState=enabled
FragmentPath=/tmp/shimmed.service
Result=success
ExecMainStatus=0
OUT
}

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "is-active" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "\$gateway_unit" ]; then
    next_gateway_state
    exit 0
  fi
  if [ "\$unit" = "$api_service_name" ]; then
    printf '%s\n' "$task_api_state"
    exit 0
  fi
  if [ "\$unit" = "$bridge_service_name" ]; then
    printf '%s\n' "$bridge_state"
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "is-enabled" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    printf 'enabled\n'
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "show" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ]; then
    if [ "$task_api_state" = "active" ]; then
      render_show active running 42001
    else
      render_show inactive dead 0
    fi
    exit 0
  fi
  if [ "\$unit" = "$bridge_service_name" ]; then
    if [ "$bridge_state" = "active" ]; then
      render_show active running 42002
    else
      render_show inactive dead 0
    fi
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "status" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ]; then
    printf '● %s - shimmed task api service\n' "\$unit"
    printf '   Active: %s (%s)\n' "$task_api_state" "\$( [ "$task_api_state" = active ] && printf running || printf dead )"
    exit 0
  fi
  if [ "\$unit" = "$bridge_service_name" ]; then
    printf '● %s - shimmed bridge service\n' "\$unit"
    printf '   Active: %s (%s)\n' "$bridge_state" "\$( [ "$bridge_state" = active ] && printf running || printf dead )"
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "start" ] && [ "\${3:-}" = "\$gateway_unit" ]; then
  exit 0
fi

printf 'unexpected systemctl invocation: %s\n' "\$*" >&2
exit 2
EOF

  cat >"$shim_dir/openclaw" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [ "\${1:-}" = "gateway" ] && [ "\${2:-}" = "status" ]; then
  printf '%s' '$gateway_runtime_text'
  exit $gateway_runtime_exit
fi

if [ "\${1:-}" = "dashboard" ] && [ "\${2:-}" = "--no-open" ]; then
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

  PATH="$shim_dir:$PATH" \
  GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
  GOLEM_HOST_AUTO_DIAGNOSE_STATE_FILE="$auto_state" \
  GOLEM_HOST_AUTO_DIAGNOSE_COOLDOWN_SECONDS=300 \
  GOLEM_LAUNCH_WAIT_SECONDS=0 \
  GOLEM_STACK_WAIT_SECONDS=0 \
  GOLEM_SELF_CHECK_SKIP_WHATSAPP=1 \
  GOLEM_SELF_CHECK_SKIP_BROWSER=1 \
  GOLEM_SELF_CHECK_SKIP_TABS=1 \
  GOLEM_TASK_API_SERVICE_NAME="$api_service_name" \
  GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME="$bridge_service_name" \
  ./scripts/launch_golem.sh >"$launch_output" 2>&1

  GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
  ./scripts/golem_host_last_snapshot.sh >"$helper_txt"

  python3 - "$case_name" "$launch_output" "$diagnostics_root" "$helper_txt" "$gateway_reason_state" "$task_api_reason_state" "$bridge_reason_state" "$gateway_context" "$gateway_last_signal" "$task_api_state" "$bridge_state" "$expected_first" "$expected_second" <<'PY'
import json
import pathlib
import sys

case_name = sys.argv[1]
launch_output = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[3])
helper = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")
gateway_reason_state = sys.argv[5]
task_api_reason_state = sys.argv[6]
bridge_reason_state = sys.argv[7]
gateway_context = sys.argv[8]
gateway_last_signal = sys.argv[9]
task_api_state = sys.argv[10]
bridge_state = sys.argv[11]
expected_first = sys.argv[12]
expected_second = sys.argv[13]

reason = (
    "self_check_status=FAIL;"
    f"gateway={gateway_reason_state};"
    f"task_api={task_api_reason_state};"
    f"whatsapp_bridge_service={bridge_reason_state}"
)

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]
summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"
summary = summary_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "GOLEM HOST FAILURE SUMMARY" in launch_output, launch_output
assert f"reason: {reason}" in launch_output, launch_output
assert f"gateway_context: {gateway_context}" in launch_output, launch_output
assert f"gateway_last_signal: {gateway_last_signal}" in launch_output, launch_output
assert f"suggested_first_action: {expected_first}" in launch_output, launch_output
assert f"snapshot: {snapshot_dir}" in launch_output, launch_output
assert f"look_first: {summary_path}" in launch_output, launch_output
assert f"look_next: {manifest_path}" in launch_output, launch_output
assert "helper: ./scripts/golem_host_last_snapshot.sh" in launch_output, launch_output
failure_block = launch_output[launch_output.index("GOLEM HOST FAILURE SUMMARY"):].splitlines()[:10]
assert len([line for line in failure_block if line.strip()]) <= 10, failure_block

assert f"trigger_reason: {reason}" in summary, summary
assert f"gateway_context: {gateway_context} | gateway_last_signal: {gateway_last_signal}" in summary, summary
assert f"task_api_active: {task_api_state} | whatsapp_bridge_active: {bridge_state}" in summary, summary
assert f"suggested_first_action: {expected_first}" in summary, summary
assert f"second_action: {expected_second}" in summary, summary

assert manifest["trigger"]["reason"] == reason, manifest
assert manifest["gateway"]["context"] == gateway_context, manifest
assert manifest["gateway"]["last_signal"] == gateway_last_signal, manifest
assert manifest["quick_triage"]["suggested_first_action"] == expected_first, manifest
assert manifest["quick_triage"]["second_action"] == expected_second, manifest
assert manifest["task_api"]["active_state"] == task_api_state, manifest
assert manifest["whatsapp_bridge"]["active_state"] == bridge_state, manifest

assert "GOLEM HOST LAST SNAPSHOT" in helper, helper
assert f"trigger_reason: {reason}" in helper, helper
assert f"gateway_context / gateway_last_signal: {gateway_context} | {gateway_last_signal}" in helper, helper
assert f"task_api_active / whatsapp_bridge_active: {task_api_state} | {bridge_state}" in helper, helper
assert f"suggested_first_action: {expected_first}" in helper, helper
assert f"second_action: {expected_second}" in helper, helper
assert f"look_first: {summary_path}" in helper, helper
assert f"look_next: {manifest_path}" in helper, helper

print(f"SMOKE_HOST_MULTI_FAILURE_{case_name.upper()}_OK")
print(f"HOST_MULTI_FAILURE_{case_name.upper()}_SNAPSHOT {snapshot_dir}")
print(f"HOST_MULTI_FAILURE_{case_name.upper()}_LOOK_FIRST {summary_path}")
PY

  rm -rf "$tmpdir"
}

run_case \
  "task_api_bridge" \
  "ok" \
  "inactive" \
  "inactive" \
  "mirar journal de task_api" \
  "mirar journal del servicio whatsapp_bridge"

run_case \
  "gateway_bridge" \
  "failed" \
  "active" \
  "inactive" \
  "confirmar gateway RPC antes de reiniciar stack" \
  "mirar journal del servicio whatsapp_bridge"

run_case \
  "gateway_task_api" \
  "failed" \
  "inactive" \
  "active" \
  "mirar journal de task_api" \
  "mirar estado del gateway en manifest.json"
