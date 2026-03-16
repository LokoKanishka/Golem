#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

nav_task_id=""
read_task_id=""
artifact_task_id=""

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

diagnosis_only="0"
if [ "${1:-}" = "--diagnosis-only" ]; then
  diagnosis_only="1"
fi

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

readiness_value() {
  local json_path="$1"
  local field="$2"
  python3 - "$json_path" "$field" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value = payload
for part in sys.argv[2].split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
        break
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

classify_browser_capability() {
  local capability="$1"
  local exit_code="$2"
  local output="$3"
  local task_id="$4"
  local readiness_json_path="$5"
  local status=""
  local note=""
  local task_final_status=""
  local attempted_recovery="false"
  local reason=""
  local chosen_profile=""

  if [ -n "$task_id" ] && [ -f "$TASKS_DIR/${task_id}.json" ]; then
    task_final_status="$(task_status "$task_id")"
  fi

  if [ -f "$readiness_json_path" ]; then
    attempted_recovery="$(readiness_value "$readiness_json_path" attempted_recovery)"
    reason="$(readiness_value "$readiness_json_path" reason)"
    chosen_profile="$(readiness_value "$readiness_json_path" chosen_profile)"
  fi

  if [ "$exit_code" -eq 0 ] && [ "$task_final_status" = "done" ]; then
    status="PASS"
    if [ "$chosen_profile" = "openclaw" ] && [ "$attempted_recovery" = "true" ]; then
      note="success-path real verificado tras remediacion controlada usando fallback openclaw"
    elif [ "$chosen_profile" = "openclaw" ]; then
      note="success-path real verificado con fallback openclaw ya utilizable"
    else
      note="success-path real verificado con browser utilizable sin bloqueo residual"
    fi
  elif [ "$task_final_status" = "blocked" ] || printf '%s\n' "$output" | grep -Eq '^TASK_RUN_BLOCKED '; then
    status="BLOCKED"
    if [ "$attempted_recovery" = "true" ]; then
      note="la tarea cerro como blocked despues de intentar remediacion controlada; reason=${reason:-unknown}"
    else
      note="la tarea cerro como blocked sin remediacion activa adicional; reason=${reason:-unknown}"
    fi
  elif printf '%s\n' "$output" | grep -Eqi 'BROWSER_BLOCKED|No tabs|no tab is connected|browser closed or no targets|Failed to start Chrome CDP|gateway timeout'; then
    status="BLOCKED"
    note="el verify encontro bloqueo operacional persistente con evidencia de remediation ladder; reason=${reason:-unknown}"
  else
    status="FAIL"
    note="el entorno permitia probar pero el flujo fallo por una causa no clasificada como bloqueo; reason=${reason:-unknown}"
  fi

  printf '%s|%s|%s\n' "$capability" "$status" "$note"
}

run_readiness_probe() {
  local label="$1"
  local capability="$2"
  local mode="$3"
  local cache_path="$4"
  local cmd="./scripts/browser_ready_check.sh ${capability} ${mode}"
  local output=""
  local render_exit="0"
  local -a check_args=("$capability" "$mode")
  local -a json_args=("$capability" "$mode" "--json")

  if [ "$diagnosis_only" = "1" ]; then
    cmd="${cmd} --diagnosis-only"
    check_args+=("--diagnosis-only")
    json_args+=("--diagnosis-only")
  fi

  printf '\n## %s\n' "$label"
  printf '$ %s\n' "$cmd"

  set +e
  LAST_OUTPUT="$(cd "$REPO_ROOT" && ./scripts/browser_ready_check.sh "${json_args[@]}" 2>&1)"
  LAST_EXIT_CODE="$?"
  set -e
  printf '%s\n' "$LAST_OUTPUT" >"$cache_path"

  set +e
  output="$(cd "$REPO_ROOT" && GOLEM_BROWSER_READYNESS_JSON_FILE="$cache_path" ./scripts/browser_ready_check.sh "${check_args[@]}" 2>&1)"
  render_exit="$?"
  set -e
  printf 'exit_code: %s\n' "$render_exit"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
}

LAST_OUTPUT=""
LAST_EXIT_CODE="0"

nav_readiness_json="$tmp_dir/navigation-readiness.json"
read_readiness_json="$tmp_dir/reading-readiness.json"
artifact_readiness_json="$tmp_dir/artifacts-readiness.json"

printf '# Browser Stack Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"
if [ "$diagnosis_only" = "1" ]; then
  printf 'verify_mode: diagnosis-only\n'
  readiness_label_suffix="Readiness + Diagnosis"
else
  printf 'verify_mode: diagnosis-plus-remediation\n'
  readiness_label_suffix="Readiness + Remediation"
fi

run_readiness_probe "Navigation ${readiness_label_suffix}" "navigation" "tabs" "$nav_readiness_json"
run_cmd "Navigation Task Probe" "GOLEM_BROWSER_READYNESS_JSON_FILE=$nav_readiness_json ./scripts/task_run_nav.sh tabs \"Browser stack verification / navigation\""
nav_task_id="$(extract_task_id "$LAST_OUTPUT")"
nav_probe_output="$LAST_OUTPUT"
nav_probe_exit="$LAST_EXIT_CODE"
if [ -n "$nav_task_id" ]; then
  run_cmd "Navigation Task Summary" "./scripts/task_summary.sh $nav_task_id"
  run_cmd "Navigation Task Show" "./scripts/task_show.sh $nav_task_id"
fi

run_readiness_probe "Reading ${readiness_label_suffix}" "reading" "snapshot" "$read_readiness_json"
run_cmd "Reading Task Probe" "GOLEM_BROWSER_READYNESS_JSON_FILE=$read_readiness_json ./scripts/task_run_read.sh snapshot \"Browser stack verification / reading\""
read_task_id="$(extract_task_id "$LAST_OUTPUT")"
read_probe_output="$LAST_OUTPUT"
read_probe_exit="$LAST_EXIT_CODE"
if [ -n "$read_task_id" ]; then
  run_cmd "Reading Task Summary" "./scripts/task_summary.sh $read_task_id"
  run_cmd "Reading Task Show" "./scripts/task_show.sh $read_task_id"
fi

run_readiness_probe "Artifact ${readiness_label_suffix}" "artifacts" "snapshot" "$artifact_readiness_json"
run_cmd "Artifact Task Probe" "GOLEM_BROWSER_READYNESS_JSON_FILE=$artifact_readiness_json ./scripts/task_run_artifact.sh snapshot \"Browser stack verification / artifacts\" browser-stack-verification"
artifact_task_id="$(extract_task_id "$LAST_OUTPUT")"
artifact_probe_output="$LAST_OUTPUT"
artifact_probe_exit="$LAST_EXIT_CODE"
if [ -n "$artifact_task_id" ]; then
  run_cmd "Artifact Task Summary" "./scripts/task_summary.sh $artifact_task_id"
  run_cmd "Artifact Task Show" "./scripts/task_show.sh $artifact_task_id"
fi

nav_classification="$(classify_browser_capability "navigation" "$nav_probe_exit" "$nav_probe_output" "$nav_task_id" "$nav_readiness_json")"
read_classification="$(classify_browser_capability "reading" "$read_probe_exit" "$read_probe_output" "$read_task_id" "$read_readiness_json")"
artifact_classification="$(classify_browser_capability "artifacts" "$artifact_probe_exit" "$artifact_probe_output" "$artifact_task_id" "$artifact_readiness_json")"

printf '\n## Final Classification\n'
printf 'capability | status | note\n'
printf '%s\n' "${nav_classification//|/ | }"
printf '%s\n' "${read_classification//|/ | }"
printf '%s\n' "${artifact_classification//|/ | }"
