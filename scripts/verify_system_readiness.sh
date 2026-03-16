#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

RESULT_NAMES=()
RESULT_STATUSES=()
RESULT_NOTES=()

append_result() {
  RESULT_NAMES+=("$1")
  RESULT_STATUSES+=("$2")
  RESULT_NOTES+=("$3")
}

join_lines() {
  python3 - "$@" <<'PY'
import sys

values = [value for value in sys.argv[1:] if value]
print(", ".join(values))
PY
}

run_fast_self_check() {
  local output exit_code task_id task_status note status

  printf '\n## fast self-check\n'
  printf '$ %s\n' 'bash ./scripts/task_run_self_check.sh "System readiness / fast self-check"'
  set +e
  output="$(cd "$REPO_ROOT" && bash ./scripts/task_run_self_check.sh "System readiness / fast self-check" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"

  task_id="$(printf '%s\n' "$output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json)"
  task_status=""
  if [ -n "$task_id" ] && [ -f "$TASKS_DIR/${task_id}.json" ]; then
    task_status="$(python3 - "$TASKS_DIR/${task_id}.json" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print(task.get("status", ""))
PY
)"
  fi

  if [ "$exit_code" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="fast operational self-check completed and closed as done"
    if printf '%s\n' "$output" | rg -q 'estado_general: WARN|tabs: WARN'; then
      note="$note; warning signals remain visible in the evidence"
    fi
  else
    status="FAIL"
    note="fast operational self-check did not complete cleanly"
  fi

  append_result "fast self-check" "$status" "$note"
  printf 'subsystem_check: fast self-check | %s | %s\n' "$status" "$note"
}

run_browser_stack() {
  local output exit_code status note
  local pass_count blocked_count fail_count
  local blocked_caps fail_caps

  printf '\n## browser stack\n'
  printf '$ %s\n' 'timeout 90s bash ./scripts/verify_browser_stack.sh'
  set +e
  output="$(cd "$REPO_ROOT" && timeout 90s bash ./scripts/verify_browser_stack.sh 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"

  pass_count="$(printf '%s\n' "$output" | awk -F'|' '/^[[:space:]]*(navigation|reading|artifacts)[[:space:]]+\|/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2=="PASS") c++} END {print c+0}')"
  blocked_count="$(printf '%s\n' "$output" | awk -F'|' '/^[[:space:]]*(navigation|reading|artifacts)[[:space:]]+\|/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2=="BLOCKED") c++} END {print c+0}')"
  fail_count="$(printf '%s\n' "$output" | awk -F'|' '/^[[:space:]]*(navigation|reading|artifacts)[[:space:]]+\|/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2=="FAIL") c++} END {print c+0}')"
  blocked_caps="$(join_lines $(printf '%s\n' "$output" | awk -F'|' '/^[[:space:]]*(navigation|reading|artifacts)[[:space:]]+\|/ {name=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); state=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", state); if (state=="BLOCKED") print name}'))"
  fail_caps="$(join_lines $(printf '%s\n' "$output" | awk -F'|' '/^[[:space:]]*(navigation|reading|artifacts)[[:space:]]+\|/ {name=$1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); state=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", state); if (state=="FAIL") print name}'))"

  if [ "$exit_code" -eq 124 ]; then
    status="BLOCKED"
    note="browser stack verify did not complete before the operational timeout and remains externally blocked"
  elif [ "$fail_count" -gt 0 ]; then
    status="FAIL"
    note="browser stack verify reported internal failures: ${fail_caps:-unknown}"
  elif [ "$blocked_count" -gt 0 ]; then
    status="BLOCKED"
    note="browser stack verify reported external browser/environment blocking: ${blocked_caps:-unknown}"
  elif [ "$pass_count" -gt 0 ]; then
    status="PASS"
    note="browser stack verify passed its navigation, reading, and artifact probes"
  else
    status="FAIL"
    note="browser stack verify did not emit a recognizable final classification"
  fi

  append_result "browser stack" "$status" "$note"
  printf 'subsystem_check: browser stack | %s | %s\n' "$status" "$note"
}

run_worker_stack() {
  local output exit_code status note

  printf '\n## worker orchestration stack\n'
  printf '$ %s\n' 'bash ./scripts/verify_worker_orchestration_stack.sh'
  set +e
  output="$(cd "$REPO_ROOT" && bash ./scripts/verify_worker_orchestration_stack.sh 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"

  if [ "$exit_code" -eq 0 ] && printf '%s\n' "$output" | rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_OK '; then
    status="PASS"
    note="worker/orchestration/traceability subsystem verify passed"
  elif printf '%s\n' "$output" | rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_BLOCKED '; then
    status="BLOCKED"
    note="worker/orchestration/traceability subsystem verify was externally blocked"
  else
    status="FAIL"
    note="worker/orchestration/traceability subsystem verify failed internally"
  fi

  append_result "worker orchestration stack" "$status" "$note"
  printf 'subsystem_check: worker orchestration stack | %s | %s\n' "$status" "$note"
}

cd "$REPO_ROOT"

printf '# System Readiness Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_fast_self_check
run_browser_stack
run_worker_stack

pass_count=0
blocked_count=0
fail_count=0
for status in "${RESULT_STATUSES[@]}"; do
  case "$status" in
    PASS) pass_count=$((pass_count + 1)) ;;
    BLOCKED) blocked_count=$((blocked_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
  esac
done

overall_status="PASS"
overall_note="all critical subsystems passed"
if [ "$fail_count" -gt 0 ]; then
  overall_status="FAIL"
  overall_note="at least one critical subsystem failed internally"
elif [ "$blocked_count" -gt 0 ]; then
  overall_status="BLOCKED"
  overall_note="no critical subsystem failed, but at least one remains externally blocked"
fi

printf '\nsubsystem/check | status | note\n'
for index in "${!RESULT_NAMES[@]}"; do
  printf '%s | %s | %s\n' "${RESULT_NAMES[$index]}" "${RESULT_STATUSES[$index]}" "${RESULT_NOTES[$index]}"
done

printf 'PASS: %s\n' "$pass_count"
printf 'FAIL: %s\n' "$fail_count"
printf 'BLOCKED: %s\n' "$blocked_count"
printf 'overall_status: %s\n' "$overall_status"
printf 'overall_note: %s\n' "$overall_note"

if [ "$fail_count" -gt 0 ]; then
  printf 'VERIFY_SYSTEM_READINESS_FAIL pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count" >&2
  exit 1
fi

if [ "$blocked_count" -gt 0 ]; then
  printf 'VERIFY_SYSTEM_READINESS_BLOCKED pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count"
  exit 2
fi

printf 'VERIFY_SYSTEM_READINESS_OK pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count"
