#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

nav_task_id=""
read_task_id=""
artifact_task_id=""

run_cmd() {
  local label="$1"
  local cmd="$2"
  local output
  local exit_code

  printf '\n## %s\n' "$label"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf 'exit_code: %s\n' "$exit_code"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

extract_task_id() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json
}

task_status() {
  local task_id="$1"
  python3 - "$TASKS_DIR/${task_id}.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(task.get("status", ""))
PY
}

classify_browser_capability() {
  local capability="$1"
  local exit_code="$2"
  local output="$3"
  local task_id="$4"
  local status=""
  local note=""
  local task_final_status=""

  if [ -n "$task_id" ] && [ -f "$TASKS_DIR/${task_id}.json" ]; then
    task_final_status="$(task_status "$task_id")"
  fi

  if [ "$exit_code" -eq 0 ] && [ "$task_final_status" = "done" ]; then
    status="PASS"
    note="success-path real verificado con salida util"
  elif [ "$task_final_status" = "blocked" ] || printf '%s\n' "$output" | grep -Eq '^TASK_RUN_BLOCKED '; then
    status="BLOCKED"
    note="la tarea cerro como blocked con evidencia de readiness y bloqueo operacional"
  elif printf '%s\n' "$output" | grep -Eqi 'no hay tabs adjuntas|No tabs|no tab is connected|browser closed or no targets|Failed to start Chrome CDP|gateway timeout'; then
    status="BLOCKED"
    note="sin tab utilizable en chrome y sin fallback openclaw realmente usable"
  else
    status="FAIL"
    note="el entorno permitia probar pero el flujo fallo por una causa no clasificada como bloqueo"
  fi

  printf '%s|%s|%s\n' "$capability" "$status" "$note"
}

LAST_OUTPUT=""
LAST_EXIT_CODE="0"

printf '# Browser Stack Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Gateway Status" "openclaw gateway status"
run_cmd "Browser Profiles" "openclaw browser profiles"
run_cmd "Chrome Status" "openclaw browser --browser-profile chrome status"
run_cmd "Chrome Tabs" "openclaw browser --browser-profile chrome tabs"
run_cmd "Chrome Snapshot" "openclaw browser --browser-profile chrome snapshot"
run_cmd "OpenClaw Status" "openclaw browser --browser-profile openclaw status"
run_cmd "OpenClaw Start" "openclaw browser --browser-profile openclaw start"
run_cmd "OpenClaw Tabs" "openclaw browser --browser-profile openclaw tabs"
run_cmd "OpenClaw Snapshot" "openclaw browser --browser-profile openclaw snapshot"

run_cmd "Navigation Task Probe" "./scripts/task_run_nav.sh tabs \"Browser stack verification / navigation\""
nav_task_id="$(extract_task_id "$LAST_OUTPUT")"
nav_probe_output="$LAST_OUTPUT"
nav_probe_exit="$LAST_EXIT_CODE"
if [ -n "$nav_task_id" ]; then
  run_cmd "Navigation Task Summary" "./scripts/task_summary.sh $nav_task_id"
  run_cmd "Navigation Task Show" "./scripts/task_show.sh $nav_task_id"
fi

run_cmd "Reading Task Probe" "./scripts/task_run_read.sh snapshot \"Browser stack verification / reading\""
read_task_id="$(extract_task_id "$LAST_OUTPUT")"
read_probe_output="$LAST_OUTPUT"
read_probe_exit="$LAST_EXIT_CODE"
if [ -n "$read_task_id" ]; then
  run_cmd "Reading Task Summary" "./scripts/task_summary.sh $read_task_id"
  run_cmd "Reading Task Show" "./scripts/task_show.sh $read_task_id"
fi

run_cmd "Artifact Task Probe" "./scripts/task_run_artifact.sh snapshot \"Browser stack verification / artifacts\" browser-stack-verification"
artifact_task_id="$(extract_task_id "$LAST_OUTPUT")"
artifact_probe_output="$LAST_OUTPUT"
artifact_probe_exit="$LAST_EXIT_CODE"
if [ -n "$artifact_task_id" ]; then
  run_cmd "Artifact Task Summary" "./scripts/task_summary.sh $artifact_task_id"
  run_cmd "Artifact Task Show" "./scripts/task_show.sh $artifact_task_id"
fi

nav_classification="$(classify_browser_capability "navigation" "$nav_probe_exit" "$nav_probe_output" "$nav_task_id")"
read_classification="$(classify_browser_capability "reading" "$read_probe_exit" "$read_probe_output" "$read_task_id")"
artifact_classification="$(classify_browser_capability "artifacts" "$artifact_probe_exit" "$artifact_probe_output" "$artifact_task_id")"

printf '\n## Final Classification\n'
printf 'capability | status | note\n'
printf '%s\n' "${nav_classification//|/ | }"
printf '%s\n' "${read_classification//|/ | }"
printf '%s\n' "${artifact_classification//|/ | }"
