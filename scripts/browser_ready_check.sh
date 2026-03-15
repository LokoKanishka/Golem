#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_ready_check.sh <navigation|reading|artifacts> <mode> [--json]
USAGE
}

capability="${1:-}"
mode="${2:-}"
output_json="0"

if [ "${3:-}" = "--json" ]; then
  output_json="1"
fi

if [ -z "$capability" ] || [ -z "$mode" ]; then
  usage
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

LAST_OUTPUT_FILE=""
LAST_EXIT_CODE="0"
attempted_recovery="false"
readiness_state="BLOCKED"
chosen_profile=""
reason=""
final_decision="block"

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

text_has_tabs() {
  local file="$1"
  grep -Eq '^[0-9]+\.' "$file"
}

text_has_no_tabs() {
  local file="$1"
  grep -Eq 'No tabs|no tab is connected|browser closed or no targets' "$file"
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

run_cmd browser_profiles "openclaw browser profiles"
profiles_exit="$LAST_EXIT_CODE"
profiles_file="$LAST_OUTPUT_FILE"

run_cmd chrome_status "openclaw browser --browser-profile chrome status"
chrome_status_exit="$LAST_EXIT_CODE"
chrome_status_file="$LAST_OUTPUT_FILE"

run_cmd chrome_tabs "openclaw browser --browser-profile chrome tabs"
chrome_tabs_exit="$LAST_EXIT_CODE"
chrome_tabs_file="$LAST_OUTPUT_FILE"

gateway_ready="false"
if [ "$gateway_exit" -eq 0 ] && grep -q 'RPC probe: ok' "$gateway_file"; then
  gateway_ready="true"
fi

chrome_tab_usable="false"
if [ "$chrome_tabs_exit" -eq 0 ] && text_has_tabs "$chrome_tabs_file"; then
  chrome_tab_usable="true"
fi

openclaw_running="false"
if [ "$profiles_exit" -eq 0 ] && grep -q '^openclaw: running' "$profiles_file"; then
  openclaw_running="true"
fi

openclaw_status_file=""
openclaw_status_exit="1"
openclaw_tabs_file=""
openclaw_tabs_exit="1"
openclaw_snapshot_file=""
openclaw_snapshot_exit="1"
openclaw_start_file=""
openclaw_start_exit="1"
openclaw_snapshot_after_start_file=""
openclaw_snapshot_after_start_exit="1"
openclaw_usable="false"

run_cmd openclaw_status "openclaw browser --browser-profile openclaw status"
openclaw_status_exit="$LAST_EXIT_CODE"
openclaw_status_file="$LAST_OUTPUT_FILE"

run_cmd openclaw_tabs "openclaw browser --browser-profile openclaw tabs"
openclaw_tabs_exit="$LAST_EXIT_CODE"
openclaw_tabs_file="$LAST_OUTPUT_FILE"

if [ "$requires_active_target" = "1" ]; then
  run_cmd openclaw_snapshot "openclaw browser --browser-profile openclaw snapshot"
  openclaw_snapshot_exit="$LAST_EXIT_CODE"
  openclaw_snapshot_file="$LAST_OUTPUT_FILE"

  if [ "$openclaw_snapshot_exit" -eq 0 ] && ! text_has_runtime_failure "$openclaw_snapshot_file"; then
    openclaw_usable="true"
  fi
else
  if [ "$openclaw_running" = "true" ]; then
    openclaw_usable="true"
  fi
fi

if [ "$gateway_ready" != "true" ]; then
  readiness_state="BLOCKED"
  reason="gateway_not_ready"
  final_decision="block"
elif [ "$chrome_tab_usable" = "true" ]; then
  readiness_state="READY"
  chosen_profile="chrome"
  reason="chrome_has_usable_tab"
  final_decision="proceed"
elif [ "$openclaw_usable" = "true" ]; then
  readiness_state="DEGRADED"
  chosen_profile="openclaw"
  reason="managed_openclaw_fallback_usable"
  final_decision="proceed"
else
  attempted_recovery="true"
  run_cmd openclaw_start "openclaw browser --browser-profile openclaw start"
  openclaw_start_exit="$LAST_EXIT_CODE"
  openclaw_start_file="$LAST_OUTPUT_FILE"

  if [ "$openclaw_start_exit" -eq 0 ]; then
    if [ "$requires_active_target" = "1" ]; then
      run_cmd openclaw_snapshot_after_start "openclaw browser --browser-profile openclaw snapshot"
      openclaw_snapshot_after_start_exit="$LAST_EXIT_CODE"
      openclaw_snapshot_after_start_file="$LAST_OUTPUT_FILE"
      if [ "$openclaw_snapshot_after_start_exit" -eq 0 ] && ! text_has_runtime_failure "$openclaw_snapshot_after_start_file"; then
        readiness_state="DEGRADED"
        chosen_profile="openclaw"
        reason="managed_openclaw_recovered"
        final_decision="proceed"
      else
        readiness_state="BLOCKED"
        reason="chrome_without_tab_and_openclaw_not_usable"
        final_decision="block"
      fi
    else
      readiness_state="DEGRADED"
      chosen_profile="openclaw"
      reason="managed_openclaw_started_for_navigation_open"
      final_decision="proceed"
    fi
  else
    readiness_state="BLOCKED"
    reason="chrome_without_tab_and_openclaw_recovery_failed"
    final_decision="block"
  fi
fi

human_summary="readiness_state=${readiness_state}; chosen_profile=${chosen_profile:-none}; reason=${reason}; attempted_recovery=${attempted_recovery}; final_decision=${final_decision}"

json_output="$(python3 - \
  "$capability" "$mode" "$readiness_state" "$chosen_profile" "$reason" "$attempted_recovery" "$final_decision" "$human_summary" \
  "$gateway_exit" "$gateway_file" \
  "$profiles_exit" "$profiles_file" \
  "$chrome_status_exit" "$chrome_status_file" \
  "$chrome_tabs_exit" "$chrome_tabs_file" \
  "$openclaw_status_exit" "$openclaw_status_file" \
  "$openclaw_tabs_exit" "$openclaw_tabs_file" \
  "$openclaw_snapshot_exit" "$openclaw_snapshot_file" \
  "$openclaw_start_exit" "$openclaw_start_file" \
  "$openclaw_snapshot_after_start_exit" "$openclaw_snapshot_after_start_file" <<'PY'
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
    openclaw_snapshot_after_start_exit,
    openclaw_snapshot_after_start_file,
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
    "attempted_recovery": attempted_recovery == "true",
    "final_decision": final_decision,
    "human_summary": human_summary,
    "checks": {
        "gateway_status": {
            "exit_code": int(gateway_exit),
            "output": read_text(gateway_file),
        },
        "browser_profiles": {
            "exit_code": int(profiles_exit),
            "output": read_text(profiles_file),
        },
        "chrome_status": {
            "exit_code": int(chrome_status_exit),
            "output": read_text(chrome_status_file),
        },
        "chrome_tabs": {
            "exit_code": int(chrome_tabs_exit),
            "output": read_text(chrome_tabs_file),
        },
        "openclaw_status": {
            "exit_code": int(openclaw_status_exit),
            "output": read_text(openclaw_status_file),
        },
        "openclaw_tabs": {
            "exit_code": int(openclaw_tabs_exit),
            "output": read_text(openclaw_tabs_file),
        },
        "openclaw_snapshot": {
            "exit_code": int(openclaw_snapshot_exit),
            "output": read_text(openclaw_snapshot_file),
        },
        "openclaw_start": {
            "exit_code": int(openclaw_start_exit),
            "output": read_text(openclaw_start_file),
        },
        "openclaw_snapshot_after_start": {
            "exit_code": int(openclaw_snapshot_after_start_exit),
            "output": read_text(openclaw_snapshot_after_start_file),
        },
    },
}

print(json.dumps(payload, ensure_ascii=True))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$json_output"
else
  printf '# Browser Readiness Check\n'
  printf 'capability: %s\n' "$capability"
  printf 'mode: %s\n' "$mode"
  printf 'readiness_state: %s\n' "$readiness_state"
  printf 'chosen_profile: %s\n' "${chosen_profile:-none}"
  printf 'reason: %s\n' "$reason"
  printf 'attempted_recovery: %s\n' "$attempted_recovery"
  printf 'final_decision: %s\n' "$final_decision"
  printf 'summary: %s\n' "$human_summary"
  printf '\n## Gateway Status\n'
  printf '$ openclaw gateway status\n'
  printf 'exit_code: %s\n' "$gateway_exit"
  cat "$gateway_file"
  printf '\n## Browser Profiles\n'
  printf '$ openclaw browser profiles\n'
  printf 'exit_code: %s\n' "$profiles_exit"
  cat "$profiles_file"
  printf '\n## Chrome Tabs\n'
  printf '$ openclaw browser --browser-profile chrome tabs\n'
  printf 'exit_code: %s\n' "$chrome_tabs_exit"
  cat "$chrome_tabs_file"
  printf '\n## OpenClaw Status\n'
  printf '$ openclaw browser --browser-profile openclaw status\n'
  printf 'exit_code: %s\n' "$openclaw_status_exit"
  cat "$openclaw_status_file"
  printf '\n## OpenClaw Tabs\n'
  printf '$ openclaw browser --browser-profile openclaw tabs\n'
  printf 'exit_code: %s\n' "$openclaw_tabs_exit"
  cat "$openclaw_tabs_file"
  if [ -s "$openclaw_snapshot_file" ]; then
    printf '\n## OpenClaw Snapshot\n'
    printf '$ openclaw browser --browser-profile openclaw snapshot\n'
    printf 'exit_code: %s\n' "$openclaw_snapshot_exit"
    cat "$openclaw_snapshot_file"
  fi
  if [ -s "$openclaw_start_file" ]; then
    printf '\n## OpenClaw Start\n'
    printf '$ openclaw browser --browser-profile openclaw start\n'
    printf 'exit_code: %s\n' "$openclaw_start_exit"
    cat "$openclaw_start_file"
  fi
  if [ -s "$openclaw_snapshot_after_start_file" ]; then
    printf '\n## OpenClaw Snapshot After Start\n'
    printf '$ openclaw browser --browser-profile openclaw snapshot\n'
    printf 'exit_code: %s\n' "$openclaw_snapshot_after_start_exit"
    cat "$openclaw_snapshot_after_start_file"
  fi
fi

case "$final_decision" in
  proceed) exit 0 ;;
  block) exit 2 ;;
  *) exit 0 ;;
esac
