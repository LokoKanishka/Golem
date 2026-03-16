#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_remediate.sh <navigation|reading|artifacts> <mode> [--json] [--diagnosis-only]
USAGE
}

capability="${1:-}"
mode="${2:-}"
shift 2 || true

output_json="0"
remediation_enabled="1"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    --diagnosis-only)
      remediation_enabled="0"
      ;;
    *)
      usage
      printf 'ERROR: argumento no soportado: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$capability" ] || [ -z "$mode" ]; then
  usage
  exit 1
fi

tmp_dir="$(mktemp -d)"
STEP_FILES=()

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

LAST_OUTPUT_FILE=""
LAST_EXIT_CODE="0"
readiness_state="BLOCKED"
chosen_profile=""
reason=""
attempted_recovery="false"
final_decision="block"
remediation_mode="diagnosis-plus-remediation"

if [ "$remediation_enabled" != "1" ]; then
  remediation_mode="diagnosis-only"
fi

run_cmd() {
  local key="$1"
  local cmd="$2"
  local output_file="$tmp_dir/${key}.out"

  set +e
  (cd "$REPO_ROOT" && bash -lc "$cmd") >"$output_file" 2>&1
  LAST_EXIT_CODE="$?"
  set -e
  LAST_OUTPUT_FILE="$output_file"
}

record_step() {
  local remediation_step="$1"
  local attempted="$2"
  local result="$3"
  local note="$4"
  local command="$5"
  local exit_code="$6"
  local output_file="${7:-}"
  local step_file="$tmp_dir/step-${#STEP_FILES[@]}.json"

  python3 - "$remediation_step" "$attempted" "$result" "$note" "$command" "$exit_code" "$output_file" >"$step_file" <<'PY'
import json
import pathlib
import sys

remediation_step, attempted, result, note, command, exit_code, output_file = sys.argv[1:8]
output = ""
if output_file:
    path = pathlib.Path(output_file)
    if path.exists():
        output = path.read_text(encoding="utf-8", errors="replace")

payload = {
    "remediation_step": remediation_step,
    "attempted": attempted == "true",
    "result": result,
    "note": note,
    "command": command,
    "exit_code": int(exit_code),
    "output": output,
}

print(json.dumps(payload, ensure_ascii=True))
PY

  STEP_FILES+=("$step_file")
}

text_has_tabs() {
  local file="$1"
  grep -Eq '^[0-9]+\.' "$file"
}

text_has_runtime_failure() {
  local file="$1"
  grep -Eqi 'Failed to start Chrome CDP|gateway timeout|gateway closed|abnormal closure|Error:' "$file"
}

requires_active_target="1"
if [ "$capability" = "navigation" ] && [ "$mode" = "open" ]; then
  requires_active_target="0"
fi

run_cmd gateway_status "openclaw gateway status"
gateway_exit="$LAST_EXIT_CODE"
gateway_file="$LAST_OUTPUT_FILE"
gateway_ready="false"
if [ "$gateway_exit" -eq 0 ] && grep -q 'RPC probe: ok' "$gateway_file"; then
  gateway_ready="true"
  record_step "probe_gateway" "true" "ok" "gateway reachable and RPC probe responded" "openclaw gateway status" "$gateway_exit" "$gateway_file"
else
  record_step "probe_gateway" "true" "blocked" "gateway is not ready enough for browser operations" "openclaw gateway status" "$gateway_exit" "$gateway_file"
fi

run_cmd browser_profiles "openclaw browser profiles"
profiles_exit="$LAST_EXIT_CODE"
profiles_file="$LAST_OUTPUT_FILE"
if [ "$profiles_exit" -eq 0 ]; then
  record_step "probe_profiles" "true" "ok" "browser profile inventory collected" "openclaw browser profiles" "$profiles_exit" "$profiles_file"
else
  record_step "probe_profiles" "true" "blocked" "browser profiles could not be listed cleanly" "openclaw browser profiles" "$profiles_exit" "$profiles_file"
fi

run_cmd chrome_status "openclaw browser --browser-profile chrome status"
chrome_status_exit="$LAST_EXIT_CODE"
chrome_status_file="$LAST_OUTPUT_FILE"
if [ "$chrome_status_exit" -eq 0 ]; then
  record_step "probe_chrome_status" "true" "ok" "chrome profile status collected" "openclaw browser --browser-profile chrome status" "$chrome_status_exit" "$chrome_status_file"
else
  record_step "probe_chrome_status" "true" "blocked" "chrome profile status probe failed" "openclaw browser --browser-profile chrome status" "$chrome_status_exit" "$chrome_status_file"
fi

run_cmd chrome_tabs "openclaw browser --browser-profile chrome tabs"
chrome_tabs_exit="$LAST_EXIT_CODE"
chrome_tabs_file="$LAST_OUTPUT_FILE"
chrome_tab_usable="false"
if [ "$chrome_tabs_exit" -eq 0 ] && text_has_tabs "$chrome_tabs_file"; then
  chrome_tab_usable="true"
  record_step "detect_chrome_usable_tab" "true" "ok" "chrome has at least one usable attached tab" "openclaw browser --browser-profile chrome tabs" "$chrome_tabs_exit" "$chrome_tabs_file"
else
  record_step "detect_chrome_usable_tab" "true" "blocked" "chrome does not currently expose a usable attached tab" "openclaw browser --browser-profile chrome tabs" "$chrome_tabs_exit" "$chrome_tabs_file"
fi

record_step "attempt_chrome_attach_refresh" "false" "skipped" "the repo has no non-destructive CLI attach path for chrome relay tabs; fallback moves to managed openclaw only" "" "0"

run_cmd openclaw_status "openclaw browser --browser-profile openclaw status"
openclaw_status_exit="$LAST_EXIT_CODE"
openclaw_status_file="$LAST_OUTPUT_FILE"
if [ "$openclaw_status_exit" -eq 0 ]; then
  record_step "probe_openclaw_status" "true" "ok" "managed openclaw profile status collected" "openclaw browser --browser-profile openclaw status" "$openclaw_status_exit" "$openclaw_status_file"
else
  record_step "probe_openclaw_status" "true" "blocked" "managed openclaw profile status probe failed" "openclaw browser --browser-profile openclaw status" "$openclaw_status_exit" "$openclaw_status_file"
fi

run_cmd openclaw_tabs "openclaw browser --browser-profile openclaw tabs"
openclaw_tabs_exit="$LAST_EXIT_CODE"
openclaw_tabs_file="$LAST_OUTPUT_FILE"
if [ "$openclaw_tabs_exit" -eq 0 ] && text_has_tabs "$openclaw_tabs_file"; then
  record_step "probe_openclaw_tabs" "true" "ok" "managed openclaw already has a usable attached tab" "openclaw browser --browser-profile openclaw tabs" "$openclaw_tabs_exit" "$openclaw_tabs_file"
else
  record_step "probe_openclaw_tabs" "true" "not_usable" "managed openclaw does not currently expose a usable attached tab" "openclaw browser --browser-profile openclaw tabs" "$openclaw_tabs_exit" "$openclaw_tabs_file"
fi

openclaw_running="false"
if [ "$profiles_exit" -eq 0 ] && grep -q '^openclaw: running' "$profiles_file"; then
  openclaw_running="true"
fi

openclaw_snapshot_file=""
openclaw_snapshot_exit="1"
openclaw_usable="false"
if [ "$requires_active_target" = "1" ]; then
  run_cmd openclaw_snapshot "openclaw browser --browser-profile openclaw snapshot"
  openclaw_snapshot_exit="$LAST_EXIT_CODE"
  openclaw_snapshot_file="$LAST_OUTPUT_FILE"
  if [ "$openclaw_snapshot_exit" -eq 0 ] && ! text_has_runtime_failure "$openclaw_snapshot_file"; then
    openclaw_usable="true"
    record_step "probe_openclaw_snapshot" "true" "ok" "managed openclaw snapshot path is already usable" "openclaw browser --browser-profile openclaw snapshot" "$openclaw_snapshot_exit" "$openclaw_snapshot_file"
  else
    record_step "probe_openclaw_snapshot" "true" "not_usable" "managed openclaw snapshot path is not currently usable" "openclaw browser --browser-profile openclaw snapshot" "$openclaw_snapshot_exit" "$openclaw_snapshot_file"
  fi
else
  if [ "$openclaw_running" = "true" ]; then
    openclaw_usable="true"
    record_step "probe_openclaw_open_path" "true" "ok" "managed openclaw is already running for navigation open mode" "openclaw browser --browser-profile openclaw status" "$openclaw_status_exit" "$openclaw_status_file"
  else
    record_step "probe_openclaw_open_path" "true" "not_usable" "managed openclaw is not already running for navigation open mode" "openclaw browser --browser-profile openclaw status" "$openclaw_status_exit" "$openclaw_status_file"
  fi
fi

openclaw_start_file=""
openclaw_start_exit="1"
openclaw_status_after_start_file=""
openclaw_status_after_start_exit="1"
openclaw_tabs_after_start_file=""
openclaw_tabs_after_start_exit="1"
openclaw_snapshot_after_start_file=""
openclaw_snapshot_after_start_exit="1"

if [ "$gateway_ready" != "true" ]; then
  record_step "attempt_openclaw_start" "false" "skipped" "managed openclaw start was not attempted because the gateway itself is not ready" "" "0"
  if [ "$requires_active_target" = "1" ]; then
    record_step "retry_openclaw_snapshot_after_start" "false" "skipped" "no retry snapshot was attempted because start was skipped" "" "0"
  else
    record_step "retry_openclaw_open_after_start" "false" "skipped" "no retry open-path probe was attempted because start was skipped" "" "0"
  fi
  readiness_state="BLOCKED"
  reason="gateway_not_ready"
  final_decision="block"
elif [ "$chrome_tab_usable" = "true" ]; then
  record_step "attempt_openclaw_start" "false" "skipped" "managed openclaw start was unnecessary because chrome already had a usable tab" "" "0"
  if [ "$requires_active_target" = "1" ]; then
    record_step "retry_openclaw_snapshot_after_start" "false" "skipped" "no retry snapshot was needed because chrome already satisfied readiness" "" "0"
  else
    record_step "retry_openclaw_open_after_start" "false" "skipped" "no retry open-path probe was needed because chrome already satisfied readiness" "" "0"
  fi
  readiness_state="READY"
  chosen_profile="chrome"
  reason="chrome_has_usable_tab"
  final_decision="proceed"
elif [ "$openclaw_usable" = "true" ]; then
  record_step "attempt_openclaw_start" "false" "skipped" "managed openclaw start was unnecessary because the fallback path was already usable" "" "0"
  if [ "$requires_active_target" = "1" ]; then
    record_step "retry_openclaw_snapshot_after_start" "false" "skipped" "no retry snapshot was needed because openclaw was already usable" "" "0"
  else
    record_step "retry_openclaw_open_after_start" "false" "skipped" "no retry open-path probe was needed because openclaw was already usable" "" "0"
  fi
  readiness_state="DEGRADED"
  chosen_profile="openclaw"
  reason="managed_openclaw_fallback_usable"
  final_decision="proceed"
elif [ "$remediation_enabled" != "1" ]; then
  record_step "attempt_openclaw_start" "false" "skipped" "diagnosis-only mode does not attempt managed openclaw recovery" "" "0"
  if [ "$requires_active_target" = "1" ]; then
    record_step "retry_openclaw_snapshot_after_start" "false" "skipped" "diagnosis-only mode does not retry snapshot after start" "" "0"
  else
    record_step "retry_openclaw_open_after_start" "false" "skipped" "diagnosis-only mode does not retry open-path probes after start" "" "0"
  fi
  readiness_state="BLOCKED"
  reason="chrome_without_tab_and_openclaw_not_attempted"
  final_decision="block"
else
  attempted_recovery="true"
  run_cmd openclaw_start "openclaw browser --browser-profile openclaw start"
  openclaw_start_exit="$LAST_EXIT_CODE"
  openclaw_start_file="$LAST_OUTPUT_FILE"

  if [ "$openclaw_start_exit" -eq 0 ]; then
    record_step "attempt_openclaw_start" "true" "ok" "managed openclaw start completed and the fallback will be re-probed" "openclaw browser --browser-profile openclaw start" "$openclaw_start_exit" "$openclaw_start_file"

    run_cmd openclaw_status_after_start "openclaw browser --browser-profile openclaw status"
    openclaw_status_after_start_exit="$LAST_EXIT_CODE"
    openclaw_status_after_start_file="$LAST_OUTPUT_FILE"
    if [ "$openclaw_status_after_start_exit" -eq 0 ]; then
      record_step "probe_openclaw_status_after_start" "true" "ok" "managed openclaw status was collected after start" "openclaw browser --browser-profile openclaw status" "$openclaw_status_after_start_exit" "$openclaw_status_after_start_file"
    else
      record_step "probe_openclaw_status_after_start" "true" "not_usable" "managed openclaw status still looks unhealthy after start" "openclaw browser --browser-profile openclaw status" "$openclaw_status_after_start_exit" "$openclaw_status_after_start_file"
    fi

    run_cmd openclaw_tabs_after_start "openclaw browser --browser-profile openclaw tabs"
    openclaw_tabs_after_start_exit="$LAST_EXIT_CODE"
    openclaw_tabs_after_start_file="$LAST_OUTPUT_FILE"
    if [ "$openclaw_tabs_after_start_exit" -eq 0 ] && text_has_tabs "$openclaw_tabs_after_start_file"; then
      record_step "probe_openclaw_tabs_after_start" "true" "ok" "managed openclaw exposes a usable tab after start" "openclaw browser --browser-profile openclaw tabs" "$openclaw_tabs_after_start_exit" "$openclaw_tabs_after_start_file"
    else
      record_step "probe_openclaw_tabs_after_start" "true" "not_usable" "managed openclaw still does not expose a usable tab after start" "openclaw browser --browser-profile openclaw tabs" "$openclaw_tabs_after_start_exit" "$openclaw_tabs_after_start_file"
    fi

    if [ "$requires_active_target" = "1" ]; then
      run_cmd openclaw_snapshot_after_start "openclaw browser --browser-profile openclaw snapshot"
      openclaw_snapshot_after_start_exit="$LAST_EXIT_CODE"
      openclaw_snapshot_after_start_file="$LAST_OUTPUT_FILE"
      if [ "$openclaw_snapshot_after_start_exit" -eq 0 ] && ! text_has_runtime_failure "$openclaw_snapshot_after_start_file"; then
        record_step "retry_openclaw_snapshot_after_start" "true" "ok" "managed openclaw snapshot succeeded after the controlled recovery attempt" "openclaw browser --browser-profile openclaw snapshot" "$openclaw_snapshot_after_start_exit" "$openclaw_snapshot_after_start_file"
        readiness_state="DEGRADED"
        chosen_profile="openclaw"
        reason="managed_openclaw_recovered"
        final_decision="proceed"
      else
        record_step "retry_openclaw_snapshot_after_start" "true" "blocked" "managed openclaw still could not produce a usable snapshot after start" "openclaw browser --browser-profile openclaw snapshot" "$openclaw_snapshot_after_start_exit" "$openclaw_snapshot_after_start_file"
        readiness_state="BLOCKED"
        reason="chrome_without_tab_and_openclaw_not_usable"
        final_decision="block"
      fi
    else
      record_step "retry_openclaw_open_after_start" "true" "ok" "managed openclaw was started successfully for navigation open mode" "openclaw browser --browser-profile openclaw start" "$openclaw_start_exit" "$openclaw_start_file"
      readiness_state="DEGRADED"
      chosen_profile="openclaw"
      reason="managed_openclaw_started_for_navigation_open"
      final_decision="proceed"
    fi
  else
    record_step "attempt_openclaw_start" "true" "blocked" "managed openclaw start failed during the controlled recovery attempt" "openclaw browser --browser-profile openclaw start" "$openclaw_start_exit" "$openclaw_start_file"
    if [ "$requires_active_target" = "1" ]; then
      record_step "retry_openclaw_snapshot_after_start" "false" "skipped" "snapshot retry was skipped because managed openclaw never started cleanly" "" "0"
    else
      record_step "retry_openclaw_open_after_start" "false" "skipped" "open-path retry was skipped because managed openclaw never started cleanly" "" "0"
    fi
    readiness_state="BLOCKED"
    reason="chrome_without_tab_and_openclaw_recovery_failed"
    final_decision="block"
  fi
fi

human_summary="readiness_state=${readiness_state}; chosen_profile=${chosen_profile:-none}; reason=${reason}; attempted_recovery=${attempted_recovery}; final_decision=${final_decision}; remediation_mode=${remediation_mode}"

json_output_payload="$(python3 - \
  "$capability" "$mode" "$readiness_state" "$chosen_profile" "$reason" "$attempted_recovery" "$final_decision" "$human_summary" "$remediation_mode" "$remediation_enabled" \
  "$gateway_exit" "$gateway_file" \
  "$profiles_exit" "$profiles_file" \
  "$chrome_status_exit" "$chrome_status_file" \
  "$chrome_tabs_exit" "$chrome_tabs_file" \
  "$openclaw_status_exit" "$openclaw_status_file" \
  "$openclaw_tabs_exit" "$openclaw_tabs_file" \
  "$openclaw_snapshot_exit" "$openclaw_snapshot_file" \
  "$openclaw_start_exit" "$openclaw_start_file" \
  "$openclaw_status_after_start_exit" "$openclaw_status_after_start_file" \
  "$openclaw_tabs_after_start_exit" "$openclaw_tabs_after_start_file" \
  "$openclaw_snapshot_after_start_exit" "$openclaw_snapshot_after_start_file" \
  "${STEP_FILES[@]}" <<'PY'
import json
import pathlib
import sys

(
    capability,
    mode,
    readiness_state,
    chosen_profile,
    reason,
    attempted_recovery,
    final_decision,
    human_summary,
    remediation_mode,
    remediation_enabled,
    gateway_exit,
    gateway_file,
    profiles_exit,
    profiles_file,
    chrome_status_exit,
    chrome_status_file,
    chrome_tabs_exit,
    chrome_tabs_file,
    openclaw_status_exit,
    openclaw_status_file,
    openclaw_tabs_exit,
    openclaw_tabs_file,
    openclaw_snapshot_exit,
    openclaw_snapshot_file,
    openclaw_start_exit,
    openclaw_start_file,
    openclaw_status_after_start_exit,
    openclaw_status_after_start_file,
    openclaw_tabs_after_start_exit,
    openclaw_tabs_after_start_file,
    openclaw_snapshot_after_start_exit,
    openclaw_snapshot_after_start_file,
    *step_paths,
) = sys.argv[1:]

def read_text(path_str):
    if not path_str:
        return ""
    path = pathlib.Path(path_str)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")

payload = {
    "capability": capability,
    "mode": mode,
    "readiness_state": readiness_state,
    "chosen_profile": chosen_profile,
    "reason": reason,
    "final_reason": reason,
    "attempted_recovery": attempted_recovery == "true",
    "final_decision": final_decision,
    "human_summary": human_summary,
    "remediation_mode": remediation_mode,
    "remediation_enabled": remediation_enabled == "1",
    "checks": {
        "gateway_status": {
            "command": "openclaw gateway status",
            "exit_code": int(gateway_exit),
            "output": read_text(gateway_file),
        },
        "browser_profiles": {
            "command": "openclaw browser profiles",
            "exit_code": int(profiles_exit),
            "output": read_text(profiles_file),
        },
        "chrome_status": {
            "command": "openclaw browser --browser-profile chrome status",
            "exit_code": int(chrome_status_exit),
            "output": read_text(chrome_status_file),
        },
        "chrome_tabs": {
            "command": "openclaw browser --browser-profile chrome tabs",
            "exit_code": int(chrome_tabs_exit),
            "output": read_text(chrome_tabs_file),
        },
        "openclaw_status": {
            "command": "openclaw browser --browser-profile openclaw status",
            "exit_code": int(openclaw_status_exit),
            "output": read_text(openclaw_status_file),
        },
        "openclaw_tabs": {
            "command": "openclaw browser --browser-profile openclaw tabs",
            "exit_code": int(openclaw_tabs_exit),
            "output": read_text(openclaw_tabs_file),
        },
        "openclaw_snapshot": {
            "command": "openclaw browser --browser-profile openclaw snapshot",
            "exit_code": int(openclaw_snapshot_exit),
            "output": read_text(openclaw_snapshot_file),
        },
        "openclaw_start": {
            "command": "openclaw browser --browser-profile openclaw start",
            "exit_code": int(openclaw_start_exit),
            "output": read_text(openclaw_start_file),
        },
        "openclaw_status_after_start": {
            "command": "openclaw browser --browser-profile openclaw status",
            "exit_code": int(openclaw_status_after_start_exit),
            "output": read_text(openclaw_status_after_start_file),
        },
        "openclaw_tabs_after_start": {
            "command": "openclaw browser --browser-profile openclaw tabs",
            "exit_code": int(openclaw_tabs_after_start_exit),
            "output": read_text(openclaw_tabs_after_start_file),
        },
        "openclaw_snapshot_after_start": {
            "command": "openclaw browser --browser-profile openclaw snapshot",
            "exit_code": int(openclaw_snapshot_after_start_exit),
            "output": read_text(openclaw_snapshot_after_start_file),
        },
    },
    "remediation_steps": [],
}

for step_path in step_paths:
    path = pathlib.Path(step_path)
    if not path.exists():
        continue
    payload["remediation_steps"].append(json.loads(path.read_text(encoding="utf-8")))

print(json.dumps(payload, ensure_ascii=True))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$json_output_payload"
else
  python3 - "$json_output_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])

print("# Browser Remediation Flow")
print(f"capability: {payload.get('capability', '')}")
print(f"mode: {payload.get('mode', '')}")
print(f"remediation_mode: {payload.get('remediation_mode', '')}")
print(f"readiness_state: {payload.get('readiness_state', '')}")
chosen_profile = payload.get("chosen_profile") or "none"
print(f"chosen_profile: {chosen_profile}")
print(f"reason: {payload.get('reason', '')}")
print("attempted_recovery: " + ("true" if payload.get("attempted_recovery") else "false"))
print(f"final_decision: {payload.get('final_decision', '')}")
print(f"summary: {payload.get('human_summary', '')}")
print("")
print("## Remediation Steps")
print("remediation_step | attempted | result | note")
for step in payload.get("remediation_steps", []):
    attempted = "true" if step.get("attempted") else "false"
    print(f"{step.get('remediation_step', '')} | {attempted} | {step.get('result', '')} | {step.get('note', '')}")

section_order = [
    ("gateway_status", "Gateway Status"),
    ("browser_profiles", "Browser Profiles"),
    ("chrome_status", "Chrome Status"),
    ("chrome_tabs", "Chrome Tabs"),
    ("openclaw_status", "OpenClaw Status"),
    ("openclaw_tabs", "OpenClaw Tabs"),
    ("openclaw_snapshot", "OpenClaw Snapshot"),
    ("openclaw_start", "OpenClaw Start"),
    ("openclaw_status_after_start", "OpenClaw Status After Start"),
    ("openclaw_tabs_after_start", "OpenClaw Tabs After Start"),
    ("openclaw_snapshot_after_start", "OpenClaw Snapshot After Start"),
]

for key, title in section_order:
    data = payload.get("checks", {}).get(key, {})
    command = data.get("command", "")
    output = data.get("output", "")
    if not command and not output:
      continue
    if not output and data.get("exit_code", 0) == 0:
      continue
    print("")
    print(f"## {title}")
    print(f"$ {command}")
    print(f"exit_code: {data.get('exit_code', 0)}")
    if output:
      print(output, end="" if output.endswith("\n") else "\n")
PY
fi

case "$final_decision" in
  proceed) exit 0 ;;
  block) exit 2 ;;
  *) exit 0 ;;
esac
