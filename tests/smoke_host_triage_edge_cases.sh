#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

real_python3="$(command -v python3)"

run_self_check_triple_case() {
  local tmpdir shim_dir state_dir diagnostics_root auto_state launch_output helper_txt
  local api_service_name bridge_service_name

  tmpdir="$(mktemp -d)"
  shim_dir="$tmpdir/shims"
  state_dir="$tmpdir/state"
  diagnostics_root="$tmpdir/diagnostics-host"
  auto_state="$tmpdir/auto-state.json"
  launch_output="$tmpdir/launch-output.txt"
  helper_txt="$tmpdir/helper.txt"
  api_service_name="golem-task-panel-http-triple-edge-smoke-$$.service"
  bridge_service_name="golem-whatsapp-bridge-triple-edge-smoke-$$.service"

  mkdir -p "$shim_dir" "$state_dir"

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
        printf '%s\n' '{"service_name":"$api_service_name","service_active_state":"inactive","service_enabled":"enabled","pid":43001,"api_ready":false,"base_url":"http://127.0.0.1:8765"}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count task_api_health)"
        if [ "\$count" -le 2 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '{"ok":false,"reasons":["task_api_unhealthy"]}'
        exit 1
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
        printf '%s\n' '{"service_name":"$bridge_service_name","service_active_state":"inactive","service_enabled":"enabled","pid":43002,"api_ready":false,"runtime":{"status":"stopped","last_operation":"bridge_unhealthy"}}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count bridge_health)"
        if [ "\$count" -le 2 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '{"ok":false,"reasons":["bridge_unhealthy"]}'
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

state_file="$state_dir/gateway_is_active.count"
gateway_unit="openclaw-gateway.service"

next_gateway_state() {
  local count=0
  if [ -f "\$state_file" ]; then
    count="\$(cat "\$state_file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$state_file"
  if [ "\$count" -le 2 ]; then
    printf 'active\n'
  else
    printf 'failed\n'
  fi
}

render_show() {
  cat <<'OUT'
Id=shimmed.service
LoadState=loaded
ActiveState=inactive
SubState=dead
MainPID=0
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
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    printf 'inactive\n'
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
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    render_show
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "status" ]; then
  unit="\${3:-}"
  if [ "\$unit" = "$api_service_name" ] || [ "\$unit" = "$bridge_service_name" ]; then
    printf '● %s - shimmed inactive service\n' "\$unit"
    printf '   Active: inactive (dead)\n'
    exit 0
  fi
fi

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "start" ] && [ "\${3:-}" = "\$gateway_unit" ]; then
  exit 0
fi

printf 'unexpected systemctl invocation: %s\n' "\$*" >&2
exit 2
EOF

  cat >"$shim_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "gateway" ] && [ "${2:-}" = "status" ]; then
  printf 'gateway service unavailable\n'
  exit 1
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

  python3 - "$launch_output" "$diagnostics_root" "$helper_txt" <<'PY'
import json
import pathlib
import sys

launch_output = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[2])
helper = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
reason = "self_check_status=FAIL;gateway=FAIL;task_api=FAIL;whatsapp_bridge_service=FAIL"

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]
summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"
summary = summary_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "GOLEM HOST FAILURE SUMMARY" in launch_output, launch_output
assert f"reason: {reason}" in launch_output, launch_output
assert "gateway_context: systemd failed" in launch_output, launch_output
assert "gateway_last_signal: (none)" in launch_output, launch_output
assert "suggested_first_action: mirar journal de task_api" in launch_output, launch_output
assert f"snapshot: {snapshot_dir}" in launch_output, launch_output
assert f"look_first: {summary_path}" in launch_output, launch_output
assert f"look_next: {manifest_path}" in launch_output, launch_output
failure_block = launch_output[launch_output.index("GOLEM HOST FAILURE SUMMARY"):].splitlines()[:10]
assert len([line for line in failure_block if line.strip()]) <= 10, failure_block

assert f"trigger_reason: {reason}" in summary, summary
assert "gateway_context: systemd failed | gateway_last_signal: (none)" in summary, summary
assert "task_api_active: inactive | whatsapp_bridge_active: inactive" in summary, summary
assert "suggested_first_action: mirar journal de task_api" in summary, summary
assert "second_action: mirar estado del gateway en manifest.json" in summary, summary

assert manifest["trigger"]["reason"] == reason, manifest
assert manifest["gateway"]["context"] == "systemd failed", manifest
assert manifest["gateway"]["last_signal"] == "(none)", manifest
assert manifest["task_api"]["active_state"] == "inactive", manifest
assert manifest["whatsapp_bridge"]["active_state"] == "inactive", manifest
assert manifest["quick_triage"]["suggested_first_action"] == "mirar journal de task_api", manifest
assert manifest["quick_triage"]["second_action"] == "mirar estado del gateway en manifest.json", manifest

assert f"trigger_reason: {reason}" in helper, helper
assert "gateway_context / gateway_last_signal: systemd failed | (none)" in helper, helper
assert "task_api_active / whatsapp_bridge_active: inactive | inactive" in helper, helper
assert "suggested_first_action: mirar journal de task_api" in helper, helper
assert "second_action: mirar estado del gateway en manifest.json" in helper, helper

print("SMOKE_HOST_TRIAGE_EDGE_TRIPLE_OK")
print(f"HOST_TRIAGE_EDGE_TRIPLE_SNAPSHOT {snapshot_dir}")
print(f"HOST_TRIAGE_EDGE_TRIPLE_LOOK_FIRST {summary_path}")
PY

  rm -rf "$tmpdir"
}

run_timeout_gateway_case() {
  local tmpdir shim_dir state_dir diagnostics_root auto_state launch_output helper_txt
  local api_service_name bridge_service_name service_name

  tmpdir="$(mktemp -d)"
  shim_dir="$tmpdir/shims"
  state_dir="$tmpdir/state"
  diagnostics_root="$tmpdir/diagnostics-host"
  auto_state="$tmpdir/auto-state.json"
  launch_output="$tmpdir/launch-output.txt"
  helper_txt="$tmpdir/helper.txt"
  service_name="openclaw-gateway.service"
  api_service_name="golem-task-panel-http-timeout-gateway-edge-smoke-$$.service"
  bridge_service_name="golem-whatsapp-bridge-timeout-gateway-edge-smoke-$$.service"

  mkdir -p "$shim_dir" "$state_dir"

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
      start|stop|restart)
        exit 0
        ;;
      status)
        printf '%s\n' '{"service_name":"$api_service_name","service_active_state":"active","service_enabled":"enabled","pid":44001,"base_url":"http://127.0.0.1:8765"}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count task_api_health)"
        if [ "\$count" -le 1 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '{"ok":false,"reasons":["startup timeout waiting for task_api readiness"]}'
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
        printf '%s\n' '{"service_name":"$bridge_service_name","service_active_state":"active","service_enabled":"enabled","pid":44002,"runtime":{"status":"starting","last_operation":"booting"}}'
        exit 0
        ;;
      healthcheck)
        count="\$(next_count bridge_health)"
        if [ "\$count" -le 1 ]; then
          printf '%s\n' '{"ok":true,"reasons":[]}'
          exit 0
        fi
        printf '%s\n' '{"ok":false,"reasons":["startup timeout waiting for whatsapp_bridge readiness"]}'
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

state_file="$state_dir/gateway_is_active.count"

next_gateway_state() {
  local count=0
  if [ -f "\$state_file" ]; then
    count="\$(cat "\$state_file")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\$count" >"\$state_file"
  if [ "\$count" -le 2 ]; then
    printf 'active\n'
  else
    printf 'failed\n'
  fi
}

if [ "\${1:-}" = "--user" ] && [ "\${2:-}" = "is-active" ] && [ "\${3:-}" = "$service_name" ]; then
  next_gateway_state
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
MainPID=44000
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
  printf 'gateway service unavailable\n'
  exit 1
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
    echo "FAIL: launch_golem should fail for timeout+gateway edge smoke" >&2
    exit 1
  }

  GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
  ./scripts/golem_host_last_snapshot.sh >"$helper_txt"

  python3 - "$launch_output" "$diagnostics_root" "$helper_txt" <<'PY'
import json
import pathlib
import sys

launch_output = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
diagnostics_root = pathlib.Path(sys.argv[2])
helper = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
reason = "stack_startup_timeout;gateway=FAIL"

snapshot_dirs = sorted(path for path in diagnostics_root.iterdir() if path.is_dir())
assert len(snapshot_dirs) == 1, snapshot_dirs
snapshot_dir = snapshot_dirs[0]
summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"
summary = summary_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "GOLEM HOST FAILURE SUMMARY" in launch_output, launch_output
assert f"reason: {reason}" in launch_output, launch_output
assert "gateway_context: systemd failed" in launch_output, launch_output
assert "gateway_last_signal: (none)" in launch_output, launch_output
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in launch_output, launch_output
assert f"snapshot: {snapshot_dir}" in launch_output, launch_output
assert f"look_first: {summary_path}" in launch_output, launch_output
assert f"look_next: {manifest_path}" in launch_output, launch_output
assert "ERROR: el stack local task api + bridge no quedó sano a tiempo." in launch_output, launch_output
failure_block = launch_output[launch_output.index("GOLEM HOST FAILURE SUMMARY"):].splitlines()[:10]
assert len([line for line in failure_block if line.strip()]) <= 10, failure_block

assert f"trigger_reason: {reason}" in summary, summary
assert "gateway_context: systemd failed | gateway_last_signal: (none)" in summary, summary
assert "task_api_active: active | whatsapp_bridge_active: active" in summary, summary
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in summary, summary
assert "second_action: mirar estado del gateway en manifest.json" in summary, summary

assert manifest["trigger"]["reason"] == reason, manifest
assert manifest["gateway"]["context"] == "systemd failed", manifest
assert manifest["gateway"]["last_signal"] == "(none)", manifest
assert manifest["task_api"]["active_state"] == "active", manifest
assert manifest["whatsapp_bridge"]["active_state"] == "active", manifest
assert manifest["quick_triage"]["suggested_first_action"] == "confirmar task_api y whatsapp_bridge antes de reintentar start", manifest
assert manifest["quick_triage"]["second_action"] == "mirar estado del gateway en manifest.json", manifest

assert f"trigger_reason: {reason}" in helper, helper
assert "gateway_context / gateway_last_signal: systemd failed | (none)" in helper, helper
assert "task_api_active / whatsapp_bridge_active: active | active" in helper, helper
assert "suggested_first_action: confirmar task_api y whatsapp_bridge antes de reintentar start" in helper, helper
assert "second_action: mirar estado del gateway en manifest.json" in helper, helper

print("SMOKE_HOST_TRIAGE_EDGE_TIMEOUT_GATEWAY_OK")
print(f"HOST_TRIAGE_EDGE_TIMEOUT_GATEWAY_SNAPSHOT {snapshot_dir}")
print(f"HOST_TRIAGE_EDGE_TIMEOUT_GATEWAY_LOOK_FIRST {summary_path}")
PY

  rm -rf "$tmpdir"
}

run_self_check_triple_case
run_timeout_gateway_case
