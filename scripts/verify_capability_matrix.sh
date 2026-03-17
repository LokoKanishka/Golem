#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="$OUTBOX_DIR/${TIMESTAMP}-capability-verification-logs"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-capability-verification-matrix.md"
RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/golem-capability-matrix-results.XXXXXX.jsonl")"
SELECTED_CAPABILITIES=()

mkdir -p "$TASKS_DIR" "$OUTBOX_DIR" "$LOG_DIR"

cleanup() {
  rm -f "$RESULTS_FILE"
}

trap cleanup EXIT

normalize_capability_id() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -s '-'
}

should_run_capability() {
  local capability_id
  local selected

  capability_id="$(normalize_capability_id "$1")"
  if [ "${#SELECTED_CAPABILITIES[@]}" -eq 0 ]; then
    return 0
  fi

  for selected in "${SELECTED_CAPABILITIES[@]}"; do
    if [ "$selected" = "$capability_id" ]; then
      return 0
    fi
  done

  return 1
}

run_selected_verification() {
  local capability_id="$1"
  local function_name="$2"

  if should_run_capability "$capability_id"; then
    "$function_name"
  fi
}

log_command() {
  local log_path="$1"
  shift
  printf '$ %s\n' "$*" >>"$log_path"
}

append_task_evidence() {
  local log_path="$1"
  local task_id="$2"

  if [ -z "$task_id" ] || [ ! -f "$TASKS_DIR/${task_id}.json" ]; then
    return 0
  fi

  {
    printf '\n## task_summary.sh %s\n' "$task_id"
    ./scripts/task_summary.sh "$task_id" 2>&1 || true
    printf '\n## task_show.sh %s\n' "$task_id"
    ./scripts/task_show.sh "$task_id" 2>&1 || true
  } >>"$log_path"
}

append_worker_evidence() {
  local log_path="$1"
  local task_id="$2"

  if [ -z "$task_id" ] || [ ! -f "$TASKS_DIR/${task_id}.json" ]; then
    return 0
  fi

  {
    printf '\n## task_worker_summary.sh %s\n' "$task_id"
    ./scripts/task_worker_summary.sh "$task_id" 2>&1 || true
    printf '\n## task_show.sh %s\n' "$task_id"
    ./scripts/task_show.sh "$task_id" 2>&1 || true
  } >>"$log_path"
}

append_chain_evidence() {
  local log_path="$1"
  local task_id="$2"

  if [ -z "$task_id" ] || [ ! -f "$TASKS_DIR/${task_id}.json" ]; then
    return 0
  fi

  {
    printf '\n## task_summary.sh %s\n' "$task_id"
    ./scripts/task_summary.sh "$task_id" 2>&1 || true
    printf '\n## task_chain_summary.sh %s\n' "$task_id"
    ./scripts/task_chain_summary.sh "$task_id" 2>&1 || true
    printf '\n## task_chain_status.sh %s\n' "$task_id"
    ./scripts/task_chain_status.sh "$task_id" 2>&1 || true
    printf '\n## task_show.sh %s\n' "$task_id"
    ./scripts/task_show.sh "$task_id" 2>&1 || true
  } >>"$log_path"
}

extract_first_task_id() {
  local log_path="$1"
  awk '/^TASK_CREATED / {print $2; exit}' "$log_path" | xargs -r basename -s .json
}

extract_last_task_id() {
  local log_path="$1"
  awk '/^(TASK_CREATED|TASK_CHILD_CREATED) / {print $2}' "$log_path" | tail -n 1 | xargs -r basename -s .json
}

extract_chain_root_id() {
  local log_path="$1"
  local value
  value="$(awk '/^TASK_CHAIN_(OK|FAIL|PLANNED) / {print $2}' "$log_path" | tail -n 1)"
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  extract_first_task_id "$log_path"
}

task_field() {
  local task_id="$1"
  local path_expr="$2"
  python3 - "$TASKS_DIR/${task_id}.json" "$path_expr" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
path_expr = sys.argv[2]

with task_path.open(encoding="utf-8") as fh:
    value = json.load(fh)

for part in path_expr.split("."):
    if part == "":
        continue
    if isinstance(value, list):
        try:
            value = value[int(part)]
        except Exception:
            value = ""
            break
    elif isinstance(value, dict):
        value = value.get(part, "")
    else:
        value = ""
        break

if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=True))
else:
    print(value)
PY
}

record_result() {
  local capability="$1"
  local status="$2"
  local note="$3"
  local exit_code="$4"
  local log_path="$5"
  local artifact_path="$6"
  local task_id="$7"
  local final_task_status="$8"
  shift 8
  python3 - "$RESULTS_FILE" "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_path" "$task_id" "$final_task_status" "$@" <<'PY'
import json
import pathlib
import sys

results_path = pathlib.Path(sys.argv[1])
capability, status, note, exit_code, log_path, artifact_path, task_id, final_task_status = sys.argv[2:10]
commands = sys.argv[10:]

payload = {
    "capability": capability,
    "status": status,
    "note": note,
    "exit_code": int(exit_code),
    "log_path": log_path,
    "artifact_path": artifact_path,
    "task_id": task_id,
    "final_task_status": final_task_status,
    "commands": commands,
}

with results_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, ensure_ascii=True) + "\n")
PY
}

browser_blocked_status() {
  local log_path="$1"
  if rg -qi 'BROWSER_BLOCKED|No tabs|no hay tabs adjuntas|Adjunta una pestana|Adjunt[aá] una pestaña|relay activo pero 0 tabs|0 tabs adjuntas|gateway closed|abnormal closure|chrome_without_tab_and_openclaw|managed openclaw start failed during the controlled recovery attempt' "$log_path"; then
    printf 'BLOCKED\n'
  else
    printf 'FAIL\n'
  fi
}

extract_roundtrip_root_id() {
  local log_path="$1"
  local key="$2"
  python3 - "$log_path" "$key" <<'PY'
import pathlib
import re
import sys

log_path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
pattern = re.compile(rf"{re.escape(key)}=([A-Za-z0-9._-]+)")

for line in reversed(log_path.read_text(encoding="utf-8", errors="replace").splitlines()):
    match = pattern.search(line)
    if match:
        print(match.group(1))
        raise SystemExit(0)
print("")
PY
}

extract_roundtrip_child_id() {
  local log_path="$1"
  local which="$2"
  python3 - "$log_path" "$which" <<'PY'
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
which = sys.argv[2]
children = []

for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
    if line.startswith("worker_child_id: "):
        children.append(line.split(": ", 1)[1].strip())

if not children:
    print("")
elif which == "first":
    print(children[0])
else:
    print(children[-1])
PY
}

extract_logged_worker_child_ids() {
  local log_path="$1"
  python3 - "$log_path" <<'PY'
import pathlib
import sys

seen = set()
for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines():
    if not line.startswith("worker_child_id: "):
        continue
    child_id = line.split(": ", 1)[1].strip()
    if not child_id or child_id in seen:
        continue
    seen.add(child_id)
    print(child_id)
PY
}

append_roundtrip_evidence() {
  local log_path="$1"
  local success_root_id blocked_root_id success_child_id blocked_child_id

  success_root_id="$(extract_roundtrip_root_id "$log_path" "success_root")"
  blocked_root_id="$(extract_roundtrip_root_id "$log_path" "blocked_root")"
  success_child_id="$(extract_roundtrip_child_id "$log_path" "first")"
  blocked_child_id="$(extract_roundtrip_child_id "$log_path" "last")"

  append_chain_evidence "$log_path" "$success_root_id"
  append_chain_evidence "$log_path" "$blocked_root_id"
  append_worker_evidence "$log_path" "$success_child_id"
  append_worker_evidence "$log_path" "$blocked_child_id"
}

append_multi_worker_barrier_evidence() {
  local log_path="$1"
  local partial_root_id blocked_root_id child_id

  partial_root_id="$(extract_roundtrip_root_id "$log_path" "partial_root")"
  blocked_root_id="$(extract_roundtrip_root_id "$log_path" "blocked_root")"

  append_chain_evidence "$log_path" "$partial_root_id"
  append_chain_evidence "$log_path" "$blocked_root_id"
  while IFS= read -r child_id; do
    [ -n "$child_id" ] || continue
    append_worker_evidence "$log_path" "$child_id"
  done < <(extract_logged_worker_child_ids "$log_path")
}

append_chain_execution_audit_evidence() {
  local log_path="$1"
  local root_id

  root_id="$(extract_roundtrip_root_id "$log_path" "root")"
  append_chain_evidence "$log_path" "$root_id"
}

worker_roundtrip_status() {
  local log_path="$1"
  if rg -qi 'Permission denied|Read-only file system|No space left on device|Operation not permitted' "$log_path"; then
    printf 'BLOCKED\n'
  else
    printf 'FAIL\n'
  fi
}

append_artifact_validation() {
  local log_path="$1"
  local artifact_path="$2"

  if [ -n "$artifact_path" ] && [ -f "$REPO_ROOT/$artifact_path" ]; then
    {
      printf '\n## validate_markdown_artifact.sh %s\n' "$artifact_path"
      ./scripts/validate_markdown_artifact.sh "$REPO_ROOT/$artifact_path" 2>&1 || true
    } >>"$log_path"
  fi
}

verify_self_check() {
  local capability="self-check"
  local log_path="$LOG_DIR/self-check.log"
  local cmd="./scripts/task_run_self_check.sh \"Capability verification / self-check\""
  local output exit_code task_id task_status note status

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_run_self_check.sh "Capability verification / self-check" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output" >>"$log_path"

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="fast self-check executed and closed the task as done"
    if rg -q 'estado_general: WARN|tabs: WARN' "$log_path"; then
      note="$note; warning signals were present and are visible in the evidence"
    fi
  else
    status="FAIL"
    note="fast self-check did not complete cleanly"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "$task_id" "$task_status" "$cmd"
}

verify_navigation() {
  local capability="navigation"
  local log_path="$LOG_DIR/navigation.log"
  local cmd="./scripts/task_run_nav.sh tabs \"Capability verification / navigation tabs\""
  local output exit_code task_id task_status status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_run_nav.sh tabs "Capability verification / navigation tabs" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output" >>"$log_path"

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="navigation tabs command completed successfully"
  else
    status="$(browser_blocked_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="navigation is blocked by browser-tab attachment or relay state in the current environment"
    else
      note="navigation command failed for reasons other than the expected environment block"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "$task_id" "$task_status" "$cmd"
}

verify_reading() {
  local capability="reading"
  local log_path="$LOG_DIR/reading.log"
  local cmd="./scripts/task_run_read.sh snapshot \"Capability verification / reading snapshot\""
  local output exit_code task_id task_status status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_run_read.sh snapshot "Capability verification / reading snapshot" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output" >>"$log_path"

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="reading snapshot completed successfully"
  else
    status="$(browser_blocked_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="reading is blocked because no usable browser tab was attached in the current environment"
    else
      note="reading command failed for reasons other than the expected environment block"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "$task_id" "$task_status" "$cmd"
}

verify_artifacts() {
  local capability="artifacts"
  local log_path="$LOG_DIR/artifacts.log"
  local slug="capability-matrix-artifact-snapshot"
  local cmd="./scripts/task_run_artifact.sh snapshot \"Capability verification / artifact snapshot\" ${slug}"
  local output exit_code task_id task_status status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_run_artifact.sh snapshot "Capability verification / artifact snapshot" "$slug" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output" >>"$log_path"

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"
  artifact_rel="$([ -n "$task_id" ] && task_field "$task_id" artifacts.0.path || printf '')"
  append_artifact_validation "$log_path" "$artifact_rel"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ] && [ -n "$artifact_rel" ]; then
    status="PASS"
    note="artifact snapshot capability produced and validated a markdown artifact"
  else
    status="$(browser_blocked_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="artifact capability is blocked because browser content could not be captured from the current environment"
    else
      note="artifact capability failed without producing a valid artifact"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "$task_id" "$task_status" "$cmd"
}

verify_comparison() {
  local capability="comparison"
  local log_path="$LOG_DIR/comparison.log"
  local cmd="./scripts/task_run_compare.sh files \"Capability verification / compare files\" capability-matrix-compare docs/TASK_MODEL.md docs/TASK_CHAIN_RESULTS.md"
  local output exit_code task_id task_status status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_run_compare.sh files "Capability verification / compare files" "capability-matrix-compare" docs/TASK_MODEL.md docs/TASK_CHAIN_RESULTS.md 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output" >>"$log_path"

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"
  artifact_rel="$([ -n "$task_id" ] && task_field "$task_id" artifacts.0.path || printf '')"
  append_artifact_validation "$log_path" "$artifact_rel"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ] && [ -n "$artifact_rel" ]; then
    status="PASS"
    note="comparison generated a markdown artifact and task closure evidence"
  else
    status="FAIL"
    note="comparison capability did not produce the expected artifact or task closure"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "$task_id" "$task_status" "$cmd"
}

verify_task_core() {
  local capability="task core"
  local log_path="$LOG_DIR/task-core.log"
  local cmd="./tests/smoke_task_core.sh"
  local exit_code task_id task_status status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./tests/smoke_task_core.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  task_id="$(extract_first_task_id "$log_path")"
  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"
  artifact_rel="$([ -n "$task_id" ] && task_field "$task_id" artifacts.0.path || printf '')"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="smoke task core flow passed and produced evidence"
  else
    status="FAIL"
    note="smoke task core flow failed"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "$task_id" "$task_status" "$cmd"
}

verify_task_lifecycle() {
  local capability="task lifecycle"
  local log_path="$LOG_DIR/task-lifecycle.log"
  local cmd_new="./scripts/task_new.sh verification-lifecycle \"Capability verification / task lifecycle\""
  local cmd_update=""
  local cmd_output=""
  local cmd_close=""
  local created_output update_output close_output exit_code=0 task_id="" task_status="" status note

  : >"$log_path"
  log_command "$log_path" "$cmd_new"
  set +e
  created_output="$(cd "$REPO_ROOT" && ./scripts/task_new.sh verification-lifecycle "Capability verification / task lifecycle" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$created_output" >>"$log_path"
  task_id="$(extract_first_task_id "$log_path")"

  if [ "$exit_code" -eq 0 ] && [ -n "$task_id" ]; then
    cmd_update="./scripts/task_update.sh ${task_id} running"
    log_command "$log_path" "$cmd_update"
    set +e
    update_output="$(cd "$REPO_ROOT" && ./scripts/task_update.sh "$task_id" running 2>&1)"
    exit_code="$?"
    set -e
    printf '%s\n' "$update_output" >>"$log_path"
  fi

  if [ "$exit_code" -eq 0 ] && [ -n "$task_id" ]; then
    cmd_output="./scripts/task_add_output.sh ${task_id} lifecycle-check 0 \"lifecycle output recorded\""
    log_command "$log_path" "$cmd_output"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_add_output.sh "$task_id" lifecycle-check 0 "lifecycle output recorded") >>"$log_path" 2>&1
    exit_code="$?"
    set -e
  fi

  if [ "$exit_code" -eq 0 ] && [ -n "$task_id" ]; then
    cmd_close="./scripts/task_close.sh ${task_id} done \"task lifecycle verification completed\""
    log_command "$log_path" "$cmd_close"
    set +e
    close_output="$(cd "$REPO_ROOT" && ./scripts/task_close.sh "$task_id" done "task lifecycle verification completed" 2>&1)"
    exit_code="$?"
    set -e
    printf '%s\n' "$close_output" >>"$log_path"
  fi

  append_task_evidence "$log_path" "$task_id"
  task_status="$([ -n "$task_id" ] && task_field "$task_id" status || printf '')"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="task lifecycle transitions new -> running -> done were exercised successfully"
  else
    status="FAIL"
    note="task lifecycle verification did not complete cleanly"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "$task_id" "$task_status" "$cmd_new" "$cmd_update" "$cmd_output" "$cmd_close"
}

verify_delegation_decision() {
  local capability="delegation decision"
  local log_path="$LOG_DIR/delegation-decision.log"
  local cmd="./scripts/delegation_decide.sh type repo-analysis"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/delegation_decide.sh type repo-analysis) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  if [ "$exit_code" -eq 0 ] && rg -q '^owner: ' "$log_path"; then
    status="PASS"
    note="delegation policy returned an explicit decision for repo-analysis"
  else
    status="FAIL"
    note="delegation decision command did not return the expected policy output"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

DIRECT_WORKER_LOG="$LOG_DIR/direct-worker-flow.log"
DIRECT_WORKER_TASK_ID=""
DIRECT_WORKER_STATUS=""
DIRECT_WORKER_HANDOFF=""
DIRECT_WORKER_TICKET=""
DIRECT_WORKER_RESULT_ARTIFACT=""
DIRECT_WORKER_START_EXIT="1"
DIRECT_WORKER_EXTRACT_EXIT="1"
DIRECT_WORKER_FINALIZE_EXIT="1"

run_direct_worker_flow() {
  local cmd_new="./scripts/task_new.sh repo-analysis \"Capability verification / direct worker flow\""
  local cmd_delegate=""
  local cmd_handoff=""
  local cmd_ticket=""
  local cmd_start=""
  local cmd_extract=""
  local cmd_finalize=""
  local output finalize_status="done"

  : >"$DIRECT_WORKER_LOG"

  log_command "$DIRECT_WORKER_LOG" "$cmd_new"
  set +e
  output="$(cd "$REPO_ROOT" && ./scripts/task_new.sh repo-analysis "Capability verification / direct worker flow" 2>&1)"
  DIRECT_WORKER_START_EXIT="$?"
  set -e
  printf '%s\n' "$output" >>"$DIRECT_WORKER_LOG"
  DIRECT_WORKER_TASK_ID="$(extract_first_task_id "$DIRECT_WORKER_LOG")"

  if [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_delegate="./scripts/task_delegate.sh ${DIRECT_WORKER_TASK_ID}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_delegate"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_delegate.sh "$DIRECT_WORKER_TASK_ID") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_START_EXIT="$?"
    set -e
  fi

  if [ "$DIRECT_WORKER_START_EXIT" -eq 0 ] && [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_handoff="./scripts/task_prepare_codex_handoff.sh ${DIRECT_WORKER_TASK_ID}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_handoff"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_prepare_codex_handoff.sh "$DIRECT_WORKER_TASK_ID") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_START_EXIT="$?"
    set -e
    DIRECT_WORKER_HANDOFF="handoffs/${DIRECT_WORKER_TASK_ID}.md"
    append_artifact_validation "$DIRECT_WORKER_LOG" "$DIRECT_WORKER_HANDOFF"
  fi

  if [ "$DIRECT_WORKER_START_EXIT" -eq 0 ] && [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_ticket="./scripts/task_prepare_codex_ticket.sh ${DIRECT_WORKER_TASK_ID}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_ticket"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_prepare_codex_ticket.sh "$DIRECT_WORKER_TASK_ID") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_START_EXIT="$?"
    set -e
    DIRECT_WORKER_TICKET="handoffs/${DIRECT_WORKER_TASK_ID}.codex.md"
    append_artifact_validation "$DIRECT_WORKER_LOG" "$DIRECT_WORKER_TICKET"
  fi

  if [ "$DIRECT_WORKER_START_EXIT" -eq 0 ] && [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_start="./scripts/task_start_codex_run.sh ${DIRECT_WORKER_TASK_ID}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_start"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_start_codex_run.sh "$DIRECT_WORKER_TASK_ID") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_START_EXIT="$?"
    set -e
    if [ "$DIRECT_WORKER_START_EXIT" -ne 0 ]; then
      finalize_status="failed"
    fi
  fi

  if [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_extract="./scripts/task_extract_worker_result.sh ${DIRECT_WORKER_TASK_ID}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_extract"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_extract_worker_result.sh "$DIRECT_WORKER_TASK_ID") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_EXTRACT_EXIT="$?"
    set -e
  fi

  if [ -n "$DIRECT_WORKER_TASK_ID" ]; then
    cmd_finalize="./scripts/task_finalize_codex_run.sh ${DIRECT_WORKER_TASK_ID} ${finalize_status}"
    log_command "$DIRECT_WORKER_LOG" "$cmd_finalize"
    set +e
    (cd "$REPO_ROOT" && ./scripts/task_finalize_codex_run.sh "$DIRECT_WORKER_TASK_ID" "$finalize_status") >>"$DIRECT_WORKER_LOG" 2>&1
    DIRECT_WORKER_FINALIZE_EXIT="$?"
    set -e
  fi

  if [ -n "$DIRECT_WORKER_TASK_ID" ] && [ -f "$TASKS_DIR/${DIRECT_WORKER_TASK_ID}.json" ]; then
    DIRECT_WORKER_STATUS="$(task_field "$DIRECT_WORKER_TASK_ID" status)"
    DIRECT_WORKER_RESULT_ARTIFACT="$(task_field "$DIRECT_WORKER_TASK_ID" worker_run.result_artifact_path)"
    append_artifact_validation "$DIRECT_WORKER_LOG" "$DIRECT_WORKER_RESULT_ARTIFACT"
    {
      printf '\n## tail run log %s\n' "$DIRECT_WORKER_TASK_ID"
      tail -n 40 "handoffs/${DIRECT_WORKER_TASK_ID}.run.log" 2>&1 || true
    } >>"$DIRECT_WORKER_LOG"
    append_worker_evidence "$DIRECT_WORKER_LOG" "$DIRECT_WORKER_TASK_ID"
  fi

  record_result \
    "worker handoff packet" \
    "$([ -n "$DIRECT_WORKER_HANDOFF" ] && [ -f "$REPO_ROOT/$DIRECT_WORKER_HANDOFF" ] && printf PASS || printf FAIL)" \
    "$([ -n "$DIRECT_WORKER_HANDOFF" ] && [ -f "$REPO_ROOT/$DIRECT_WORKER_HANDOFF" ] && printf 'handoff packet generated and validated' || printf 'handoff packet was not generated correctly')" \
    "$DIRECT_WORKER_START_EXIT" \
    "$DIRECT_WORKER_LOG" \
    "$DIRECT_WORKER_HANDOFF" \
    "$DIRECT_WORKER_TASK_ID" \
    "$DIRECT_WORKER_STATUS" \
    "$cmd_new" "$cmd_delegate" "$cmd_handoff"

  record_result \
    "codex-ready ticket" \
    "$([ -n "$DIRECT_WORKER_TICKET" ] && [ -f "$REPO_ROOT/$DIRECT_WORKER_TICKET" ] && printf PASS || printf FAIL)" \
    "$([ -n "$DIRECT_WORKER_TICKET" ] && [ -f "$REPO_ROOT/$DIRECT_WORKER_TICKET" ] && printf 'codex ticket generated and validated' || printf 'codex ticket was not generated correctly')" \
    "$DIRECT_WORKER_START_EXIT" \
    "$DIRECT_WORKER_LOG" \
    "$DIRECT_WORKER_TICKET" \
    "$DIRECT_WORKER_TASK_ID" \
    "$DIRECT_WORKER_STATUS" \
    "$cmd_ticket"

  local controlled_status="FAIL"
  local controlled_note="controlled codex run did not complete successfully"
  if [ "$DIRECT_WORKER_START_EXIT" -eq 0 ] && [ "$(task_field "$DIRECT_WORKER_TASK_ID" worker_run.state)" = "finished" ]; then
    controlled_status="PASS"
    controlled_note="controlled codex run executed with real worker evidence"
  elif rg -qi 'codex_cli: ok|allowed: no|WORKER_PREFLIGHT_OK' "$DIRECT_WORKER_LOG"; then
    controlled_status="BLOCKED"
    controlled_note="controlled codex run was blocked by preflight or runtime environment conditions"
  fi
  record_result \
    "controlled codex run" \
    "$controlled_status" \
    "$controlled_note" \
    "$DIRECT_WORKER_START_EXIT" \
    "$DIRECT_WORKER_LOG" \
    "$DIRECT_WORKER_RESULT_ARTIFACT" \
    "$DIRECT_WORKER_TASK_ID" \
    "$DIRECT_WORKER_STATUS" \
    "$cmd_start"

  local extraction_status="FAIL"
  local extraction_note="worker result extraction/finalization did not complete successfully"
  if [ "$DIRECT_WORKER_EXTRACT_EXIT" -eq 0 ] && [ "$DIRECT_WORKER_FINALIZE_EXIT" -eq 0 ] && [ "$DIRECT_WORKER_STATUS" = "done" ] && [ -n "$DIRECT_WORKER_RESULT_ARTIFACT" ]; then
    extraction_status="PASS"
    extraction_note="worker result was extracted, validated and finalized into the task"
  elif [ "$DIRECT_WORKER_START_EXIT" -ne 0 ]; then
    extraction_status="BLOCKED"
    extraction_note="worker result extraction/finalization could not complete because the controlled run did not reach a finalizable state"
  fi
  record_result \
    "worker result extraction/finalization" \
    "$extraction_status" \
    "$extraction_note" \
    "$DIRECT_WORKER_FINALIZE_EXIT" \
    "$DIRECT_WORKER_LOG" \
    "$DIRECT_WORKER_RESULT_ARTIFACT" \
    "$DIRECT_WORKER_TASK_ID" \
    "$DIRECT_WORKER_STATUS" \
    "$cmd_extract" "$cmd_finalize"
}

verify_worker_packet_roundtrip() {
  local capability="worker packet roundtrip"
  local log_path="$LOG_DIR/worker-packet-roundtrip.log"
  local cmd="./scripts/verify_worker_packet_roundtrip.sh"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/verify_worker_packet_roundtrip.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  append_roundtrip_evidence "$log_path"

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_WORKER_PACKET_ROUNDTRIP_OK ' "$log_path"; then
    status="PASS"
    note="deep verify reused the canonical roundtrip script and proved both success and blocked packet-settlement paths"
  else
    status="$(worker_roundtrip_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="deep verify could not complete because repo-local execution prerequisites were externally blocked"
    else
      note="deep verify exposed an internal failure in the packetized worker roundtrip flow"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

verify_multi_worker_barrier_orchestration() {
  local capability="multi-worker barrier orchestration"
  local log_path="$LOG_DIR/multi-worker-barrier-orchestration.log"
  local cmd="./scripts/verify_multi_worker_await_roundtrip.sh"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/verify_multi_worker_await_roundtrip.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  append_multi_worker_barrier_evidence "$log_path"

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_MULTI_WORKER_AWAIT_OK ' "$log_path" && \
     rg -q 'analysis-workers=waiting,architecture-ready=satisfied' "$log_path" && \
     rg -q 'analysis_barrier_status: satisfied' "$log_path" && \
     rg -q 'analysis_barrier_status: blocked' "$log_path" && \
     rg -q 'full_continuation_status: skipped' "$log_path"; then
    status="PASS"
    note="deep verify reused the canonical multi-worker barrier script and proved partial continuation, full join satisfaction, and blocked-barrier skip semantics"
  else
    status="$(worker_roundtrip_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="deep verify could not complete because repo-local execution prerequisites were externally blocked"
    else
      note="deep verify exposed an internal failure in the multi-worker dependency barrier orchestration flow"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

verify_chain_execution_audit() {
  local capability="chain execution audit"
  local log_path="$LOG_DIR/chain-execution-audit.log"
  local cmd="bash ./scripts/verify_chain_execution_audit.sh"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_chain_execution_audit.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  append_chain_execution_audit_evidence "$log_path"

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_CHAIN_EXECUTION_AUDIT_OK ' "$log_path" && \
     rg -q '^audit_status: WARN$' "$log_path" && \
     rg -q '^audit_reason: execution_incomplete$' "$log_path" && \
     rg -q '^audit_status: OK$' "$log_path" && \
     rg -q '^audit_reason: execution_coherent$' "$log_path" && \
     rg -q '^audit_status: FAIL$' "$log_path" && \
     rg -q '^audit_reason: execution_drift$' "$log_path" && \
     rg -q 'effective_plan_sha256 no coincide' "$log_path"; then
    status="PASS"
    note="deep verify proved incomplete, coherent, and drift-detection paths for execution audit against the frozen effective plan"
  else
    status="$(worker_roundtrip_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="deep verify could not complete because repo-local execution prerequisites were externally blocked"
    else
      note="deep verify exposed an internal failure in the chain execution audit flow"
    fi
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

verify_worker_orchestration_stack() {
  local capability="worker orchestration stack"
  local log_path="$LOG_DIR/worker-orchestration-stack.log"
  local cmd="bash ./scripts/verify_worker_orchestration_stack.sh"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_worker_orchestration_stack.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_OK ' "$log_path" && \
     rg -q '^worker packet roundtrip \| PASS \|' "$log_path" && \
     rg -q '^multi-worker barrier orchestration \| PASS \|' "$log_path" && \
     rg -q '^chain execution audit \| PASS \|' "$log_path"; then
    status="PASS"
    note="deep subsystem verify aggregated roundtrip, barrier orchestration, and execution audit as one worker-orchestration-traceability stack health check"
  elif rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_BLOCKED ' "$log_path"; then
    status="BLOCKED"
    note="deep subsystem verify was externally blocked because at least one canonical stack verify could not run"
  else
    status="FAIL"
    note="deep subsystem verify exposed an internal failure in the worker-orchestration-traceability stack"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

verify_system_readiness() {
  local capability="system readiness"
  local log_path="$LOG_DIR/system-readiness.log"
  local cmd="bash ./scripts/verify_system_readiness.sh"
  local exit_code status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_system_readiness.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_SYSTEM_READINESS_OK ' "$log_path"; then
    status="PASS"
    note="system readiness verify reported the fast lane, browser stack, and worker stack all healthy"
  elif [ "$exit_code" -eq 2 ] && rg -q '^VERIFY_SYSTEM_READINESS_BLOCKED ' "$log_path"; then
    status="BLOCKED"
    note="system readiness verify reported a coherent global block without collapsing blocked subsystems into a generic internal failure"
  else
    status="FAIL"
    note="system readiness verify exposed an internal system-level failure"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "" "" "" "$cmd"
}

verify_live_smoke_profile() {
  local capability="live smoke profile"
  local log_path="$LOG_DIR/live-smoke-profile.log"
  local cmd="bash ./scripts/verify_live_smoke_profile.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_live_smoke_profile.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^REPORT_PATH / {print $2}' "$log_path" | tail -n 1)"

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_LIVE_SMOKE_PROFILE_OK ' "$log_path"; then
    status="PASS"
    note="live smoke profile proved the current launcher-facing stack, fast self-check, worker stack, and live browser action as fully usable"
  elif [ "$exit_code" -eq 2 ] && rg -q '^VERIFY_LIVE_SMOKE_PROFILE_BLOCKED ' "$log_path"; then
    status="BLOCKED"
    note="live smoke profile ran end-to-end, generated real evidence, and reported an honest partial system block without pretending the browser lane passed"
  else
    status="FAIL"
    note="live smoke profile failed internally before producing a coherent demo-state report"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_user_facing_delivery_truth() {
  local capability="user-facing delivery truth"
  local log_path="$LOG_DIR/user-facing-delivery-truth.log"
  local cmd="bash ./scripts/verify_user_facing_delivery_truth.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_user_facing_delivery_truth.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_USER_FACING_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_USER_FACING_DELIVERY_TRUTH_OK ' "$log_path"; then
    status="PASS"
    note="delivery truth verify proved that accepted is not enough, visible authorizes user-facing success, verified_by_user persists explicit confirmation, and invalid drift is rejected"
  else
    status="FAIL"
    note="delivery truth verify exposed a gap in the user-facing delivery guardrails or audit model"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_visible_artifact_delivery_truth() {
  local capability="visible artifact delivery truth"
  local log_path="$LOG_DIR/visible-artifact-delivery-truth.log"
  local cmd="bash ./scripts/verify_visible_artifact_delivery_truth.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_visible_artifact_delivery_truth.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_(OK|FAIL|BLOCKED) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_OK ' "$log_path"; then
    status="PASS"
    note="visible artifact delivery truth verify proved canonical desktop/downloads resolution, post-delivery verification, and claim gating against unverified visibility"
  elif [ "$exit_code" -eq 2 ] && rg -q '^VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_BLOCKED ' "$log_path"; then
    status="BLOCKED"
    note="visible artifact delivery truth verify stayed honest when the current environment could not prove a canonical desktop or downloads destination"
  else
    status="FAIL"
    note="visible artifact delivery truth verify exposed a gap in visible path resolution, verification, or drift detection"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_whatsapp_delivery_claim_truth() {
  local capability="whatsapp delivery claim truth"
  local log_path="$LOG_DIR/whatsapp-delivery-claim-truth.log"
  local cmd="bash ./scripts/verify_whatsapp_delivery_claim_truth.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_whatsapp_delivery_claim_truth.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_OK ' "$log_path"; then
    status="PASS"
    note="whatsapp delivery claim truth verify proved that gateway acceptance, provider ambiguity, delivered evidence, and user confirmation all map to honest claim levels"
  else
    status="FAIL"
    note="whatsapp delivery claim truth verify exposed a gap in channel-specific claim degradation or drift detection"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_media_ingestion_truth() {
  local capability="media ingestion truth"
  local log_path="$LOG_DIR/media-ingestion-truth.log"
  local cmd="bash ./scripts/verify_media_ingestion_truth.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_media_ingestion_truth.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_MEDIA_INGESTION_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_MEDIA_INGESTION_TRUTH_OK ' "$log_path"; then
    status="PASS"
    note="media ingestion truth verify proved canonical identity capture for internal, visible, and local media paths plus explicit blocking and drift detection"
  else
    status="FAIL"
    note="media ingestion truth verify exposed a gap in canonical media identity capture, readiness gating, or drift detection"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_host_screenshot_truth() {
  local capability="host screenshot truth"
  local log_path="$LOG_DIR/host-screenshot-truth.log"
  local cmd="bash ./scripts/verify_host_screenshot_truth.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_host_screenshot_truth.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_HOST_SCREENSHOT_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_HOST_SCREENSHOT_TRUTH_OK ' "$log_path"; then
    status="PASS"
    note="host screenshot truth verify proved captured-versus-verified semantics, honest blocking, and screenshot drift detection"
  else
    status="FAIL"
    note="host screenshot truth verify exposed a gap in canonical host-side visual evidence handling"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_user_facing_readiness() {
  local capability="user-facing readiness"
  local log_path="$LOG_DIR/user-facing-readiness.log"
  local cmd="bash ./scripts/verify_user_facing_readiness.sh"
  local exit_code status note artifact_rel

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && bash ./scripts/verify_user_facing_readiness.sh) >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  artifact_rel="$(awk '/^report_path: / {print $2}' "$log_path" | tail -n 1)"
  if [ -z "$artifact_rel" ]; then
    artifact_rel="$(awk '/^VERIFY_USER_FACING_READINESS_(OK|BLOCKED|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' "$log_path" | tail -n 1)"
  fi

  if [ "$exit_code" -eq 0 ] && rg -q '^VERIFY_USER_FACING_READINESS_OK ' "$log_path"; then
    status="PASS"
    note="user-facing readiness verify aggregated the five canonical user-facing truths and proved they all passed coherently"
  elif [ "$exit_code" -eq 2 ] && rg -q '^VERIFY_USER_FACING_READINESS_BLOCKED ' "$log_path"; then
    status="BLOCKED"
    note="user-facing readiness verify stayed honest: no internal failure, but at least one canonical user-facing lane remains blocked"
  else
    status="FAIL"
    note="user-facing readiness verify exposed an internal failure or inconsistency in one of the canonical user-facing lanes"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "" "" "$cmd"
}

verify_orchestration_basic() {
  local capability="orchestration basic"
  local log_path="$LOG_DIR/orchestration-basic.log"
  local cmd="./scripts/task_chain_run.sh self-check-compare \"Capability verification / basic orchestration\""
  local exit_code root_task_id task_status artifact_rel status note

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/task_chain_run.sh self-check-compare "Capability verification / basic orchestration") >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  root_task_id="$(extract_chain_root_id "$log_path")"
  append_chain_evidence "$log_path" "$root_task_id"
  task_status="$([ -n "$root_task_id" ] && task_field "$root_task_id" status || printf '')"
  artifact_rel="$([ -n "$root_task_id" ] && task_field "$root_task_id" chain_summary.final_artifact_path || printf '')"
  append_artifact_validation "$log_path" "$artifact_rel"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ] && [ -n "$artifact_rel" ]; then
    status="PASS"
    note="basic orchestration chain completed and produced a validated final artifact"
  else
    status="FAIL"
    note="basic orchestration chain did not complete as expected"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "$root_task_id" "$task_status" "$cmd"
}

verify_orchestration_v2() {
  local capability="orchestration v2 mixta local+worker"
  local log_path="$LOG_DIR/orchestration-v2.log"
  local cmd="./scripts/task_chain_run_v2.sh repo-analysis-worker \"Capability verification / orchestration v2\""
  local exit_code root_task_id task_status artifact_rel status note worker_child_id

  : >"$log_path"
  log_command "$log_path" "$cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/task_chain_run_v2.sh repo-analysis-worker "Capability verification / orchestration v2") >>"$log_path" 2>&1
  exit_code="$?"
  set -e

  root_task_id="$(extract_chain_root_id "$log_path")"
  append_chain_evidence "$log_path" "$root_task_id"
  task_status="$([ -n "$root_task_id" ] && task_field "$root_task_id" status || printf '')"
  artifact_rel="$([ -n "$root_task_id" ] && task_field "$root_task_id" chain_summary.final_artifact_path || printf '')"
  worker_child_id="$([ -n "$root_task_id" ] && task_field "$root_task_id" chain_summary.worker_child_ids.0 || printf '')"
  append_artifact_validation "$log_path" "$artifact_rel"
  append_worker_evidence "$log_path" "$worker_child_id"

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ] && [ -n "$artifact_rel" ] && [ -n "$worker_child_id" ]; then
    status="PASS"
    note="mixed v2 orchestration completed with real worker evidence and final artifact"
  else
    status="FAIL"
    note="mixed v2 orchestration did not complete as expected"
  fi

  record_result "$capability" "$status" "$note" "$exit_code" "$log_path" "$artifact_rel" "$root_task_id" "$task_status" "$cmd"
}

verify_orchestration_v3() {
  local capability="orchestration v3 condicional"
  local log_path="$LOG_DIR/orchestration-v3.log"
  local success_cmd="./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional \"Capability verification / orchestration v3 success\""
  local fail_cmd="./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional \"Capability verification / orchestration v3 failover\" --force-worker-result failed"
  local success_exit fail_exit success_root_id fail_root_id success_status fail_status success_artifact fail_artifact success_next fail_next fail_skipped status note success_worker_child

  : >"$log_path"
  log_command "$log_path" "$success_cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "Capability verification / orchestration v3 success") >>"$log_path" 2>&1
  success_exit="$?"
  set -e

  success_root_id="$(extract_chain_root_id "$log_path")"
  append_chain_evidence "$log_path" "$success_root_id"
  success_status="$([ -n "$success_root_id" ] && task_field "$success_root_id" status || printf '')"
  success_artifact="$([ -n "$success_root_id" ] && task_field "$success_root_id" chain_summary.final_artifact_path || printf '')"
  success_next="$([ -n "$success_root_id" ] && task_field "$success_root_id" chain_summary.next_step_selected || printf '')"
  success_worker_child="$([ -n "$success_root_id" ] && task_field "$success_root_id" chain_summary.worker_child_ids.0 || printf '')"
  append_artifact_validation "$log_path" "$success_artifact"
  append_worker_evidence "$log_path" "$success_worker_child"

  log_command "$log_path" "$fail_cmd"
  set +e
  (cd "$REPO_ROOT" && ./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "Capability verification / orchestration v3 failover" --force-worker-result failed) >>"$log_path" 2>&1
  fail_exit="$?"
  set -e

  fail_root_id="$(awk '/^TASK_CHAIN_FAIL / {print $2}' "$log_path" | tail -n 1)"
  append_chain_evidence "$log_path" "$fail_root_id"
  fail_status="$([ -n "$fail_root_id" ] && task_field "$fail_root_id" status || printf '')"
  fail_artifact="$([ -n "$fail_root_id" ] && task_field "$fail_root_id" chain_summary.final_artifact_path || printf '')"
  fail_next="$([ -n "$fail_root_id" ] && task_field "$fail_root_id" chain_summary.next_step_selected || printf '')"
  fail_skipped="$([ -n "$fail_root_id" ] && task_field "$fail_root_id" chain_summary.skipped_steps.0 || printf '')"

  if [ "$success_exit" -eq 0 ] && [ "$success_status" = "done" ] && [ "$success_next" = "local-review-worker-outcome" ] && \
     [ "$fail_exit" -ne 0 ] && [ "$fail_status" = "failed" ] && [ "$fail_next" = "close-root" ] && [ "$fail_skipped" = "local-review-worker-outcome" ]; then
    status="PASS"
    note="v3 conditional orchestration exercised both success and controlled failover paths with honest decisions"
  else
    status="FAIL"
    note="v3 conditional orchestration did not preserve the expected decision evidence across success and failover paths"
  fi

  record_result "$capability" "$status" "$note" "$success_exit" "$log_path" "$success_artifact" "$success_root_id" "$success_status" "$success_cmd" "$fail_cmd"
}

generate_report() {
  python3 - "$RESULTS_FILE" "$REPORT_PATH" "$REPO_ROOT" <<'PY'
import datetime
import json
import pathlib
import sys

results_path = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
repo_root = sys.argv[3]
results = [json.loads(line) for line in results_path.read_text(encoding="utf-8").splitlines() if line.strip()]

status_order = {"PASS": 0, "FAIL": 1, "BLOCKED": 2}
results.sort(key=lambda item: (status_order.get(item["status"], 99), item["capability"].lower()))

counts = {"PASS": [], "FAIL": [], "BLOCKED": []}
for result in results:
    counts.setdefault(result["status"], []).append(result["capability"])

lines = []
lines.append("# Capability Verification Matrix Report")
lines.append("")
lines.append("generated_at: " + datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat())
lines.append(f"repo: {repo_root}")
lines.append("task_type: capability-verification")
lines.append("")
lines.append("## Summary")
lines.append(f"- total_capabilities: {len(results)}")
for key in ("PASS", "FAIL", "BLOCKED"):
    lines.append(f"- {key.lower()}_count: {len(counts.get(key, []))}")
lines.append("- BLOCKED does not mean PASS; it means the capability could not be proven in the current environment.")
lines.append("")
lines.append("## Capability Table")
lines.append("| capability | status | note |")
lines.append("| --- | --- | --- |")
for result in results:
    note = result["note"].replace("|", "\\|")
    lines.append(f"| {result['capability']} | {result['status']} | {note} |")

for result in results:
    lines.append("")
    lines.append(f"## {result['capability']}")
    lines.append(f"- status: {result['status']}")
    lines.append(f"- note: {result['note']}")
    lines.append(f"- primary_exit_code: {result['exit_code']}")
    if result.get("task_id"):
        lines.append(f"- task_id: {result['task_id']}")
    if result.get("final_task_status"):
        lines.append(f"- final_task_status: {result['final_task_status']}")
    if result.get("artifact_path"):
        lines.append(f"- artifact_path: {result['artifact_path']}")
    lines.append(f"- log_path: {result['log_path']}")
    lines.append("- commands:")
    for command in result.get("commands", []):
        if command:
            lines.append(f"  - `{command}`")
    lines.append("- stdout/stderr excerpt:")
    lines.append("```text")
    log_text = pathlib.Path(result["log_path"]).read_text(encoding="utf-8", errors="replace")
    excerpt_lines = log_text.splitlines()[:120]
    lines.extend(excerpt_lines if excerpt_lines else ["(empty)"])
    lines.append("```")

lines.append("")
lines.append("## Final Lists")
for key in ("PASS", "FAIL", "BLOCKED"):
    values = counts.get(key, [])
    lines.append(f"- {key}: {', '.join(values) if values else '(none)'}")

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

print_summary() {
  python3 - "$RESULTS_FILE" "$REPORT_PATH" <<'PY'
import json
import pathlib
import sys

results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
report_path = sys.argv[2]

print(f"REPORT_PATH {report_path}")
print("capability | status | note")
for result in results:
    print(f"{result['capability']} | {result['status']} | {result['note']}")
print("PASS:", ", ".join([r["capability"] for r in results if r["status"] == "PASS"]) or "(none)")
print("FAIL:", ", ".join([r["capability"] for r in results if r["status"] == "FAIL"]) or "(none)")
print("BLOCKED:", ", ".join([r["capability"] for r in results if r["status"] == "BLOCKED"]) or "(none)")
PY
}

if [ "$#" -gt 0 ]; then
  while [ "$#" -gt 0 ]; do
    SELECTED_CAPABILITIES+=("$(normalize_capability_id "$1")")
    shift
  done
fi

cd "$REPO_ROOT"

printf 'VERIFY_START %s\n' "$TIMESTAMP"
run_selected_verification "self-check" verify_self_check
run_selected_verification "navigation" verify_navigation
run_selected_verification "reading" verify_reading
run_selected_verification "artifacts" verify_artifacts
run_selected_verification "comparison" verify_comparison
run_selected_verification "task-core" verify_task_core
run_selected_verification "task-lifecycle" verify_task_lifecycle
run_selected_verification "delegation-decision" verify_delegation_decision
run_selected_verification "direct-worker-flow" run_direct_worker_flow
run_selected_verification "worker-packet-roundtrip" verify_worker_packet_roundtrip
run_selected_verification "multi-worker-barrier-orchestration" verify_multi_worker_barrier_orchestration
run_selected_verification "chain-execution-audit" verify_chain_execution_audit
run_selected_verification "worker-orchestration-stack" verify_worker_orchestration_stack
run_selected_verification "system-readiness" verify_system_readiness
run_selected_verification "live-smoke-profile" verify_live_smoke_profile
run_selected_verification "user-facing-delivery-truth" verify_user_facing_delivery_truth
run_selected_verification "visible-artifact-delivery-truth" verify_visible_artifact_delivery_truth
run_selected_verification "whatsapp-delivery-claim-truth" verify_whatsapp_delivery_claim_truth
run_selected_verification "media-ingestion-truth" verify_media_ingestion_truth
run_selected_verification "host-screenshot-truth" verify_host_screenshot_truth
run_selected_verification "user-facing-readiness" verify_user_facing_readiness
run_selected_verification "orchestration-basic" verify_orchestration_basic
run_selected_verification "orchestration-v2" verify_orchestration_v2
run_selected_verification "orchestration-v3" verify_orchestration_v3
if [ ! -s "$RESULTS_FILE" ]; then
  printf 'VERIFY_FAIL no capabilities matched the requested selection\n' >&2
  exit 2
fi
generate_report
print_summary
printf 'VERIFY_DONE %s\n' "$REPORT_PATH"
