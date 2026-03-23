#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_NEW="$REPO_ROOT/scripts/task_new.sh"
TASK_CREATE="$REPO_ROOT/scripts/task_create.sh"
TMPDIR="$(mktemp -d)"
task_path=""

cleanup() {
  rm -rf "$TMPDIR"
  if [[ -n "$task_path" && -f "$task_path" ]]; then
    rm -f "$task_path"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -x "$TASK_CREATE" ]] || fail "scripts/task_create.sh must exist and be executable"
[[ -x "$TASK_NEW" ]] || fail "scripts/task_new.sh must exist and be executable"

grep -Fq 'Wrapper legacy sobre ./scripts/task_create.sh.' "$TASK_NEW" || fail "task_new.sh must declare wrapper-only compatibility"
grep -Fq '"$SCRIPT_DIR/task_create.sh"' "$TASK_NEW" || fail "task_new.sh must delegate to task_create.sh"

for forbidden in 'python3 -' 'secrets.token_hex' 'json.dump(task' 'TASKS_DIR=' 'mkdir -p "$TASKS_DIR"'; do
  if grep -Fq "$forbidden" "$TASK_NEW"; then
    fail "task_new.sh contains forbidden inline creation logic: $forbidden"
  fi
done

create_calls="$(grep -Fc '"$SCRIPT_DIR/task_create.sh"' "$TASK_NEW")"
[[ "$create_calls" -eq 1 ]] || fail "task_new.sh must call task_create.sh exactly once"

create_output="$(
  TASK_OBJECTIVE="Wrapper compatibility objective" \
  TASK_PARENT_TASK_ID="task-parent-wrapper-check" \
  TASK_DEPENDS_ON='["task-dependency-wrapper-check"]' \
  TASK_STEP_NAME="compat-wrapper-check" \
  TASK_STEP_ORDER="7" \
  TASK_CRITICAL="true" \
  TASK_EXECUTION_MODE="worker" \
  TASK_CANONICAL_SESSION="verify-task-entrypoint-policy" \
  TASK_ORIGIN="compat-wrapper-check" \
  "$TASK_NEW" compat-wrapper-check "Wrapper compatibility title"
)"

task_id="$(printf '%s\n' "$create_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json)"
task_path="$REPO_ROOT/$(printf '%s\n' "$create_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"

[[ -n "$task_id" ]] || fail "task_new.sh did not emit TASK_CREATED"
[[ -f "$task_path" ]] || fail "task_new.sh did not produce a task file"

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))

assert task["task_id"] == task["id"], "task_id alias mismatch"
assert task["type"] == "compat-wrapper-check", task["type"]
assert task["title"] == "Wrapper compatibility title", task["title"]
assert task["objective"] == "Wrapper compatibility objective", task["objective"]
assert task["status"] == "todo", task["status"]
assert task["parent_task_id"] == "task-parent-wrapper-check", task["parent_task_id"]
assert task["depends_on"] == ["task-dependency-wrapper-check"], task["depends_on"]
assert task["step_name"] == "compat-wrapper-check", task.get("step_name")
assert task["step_order"] == 7, task.get("step_order")
assert task["critical"] is True, task.get("critical")
assert task["execution_mode"] == "worker", task.get("execution_mode")
assert task["canonical_session"] == "verify-task-entrypoint-policy", task.get("canonical_session")
assert task["origin"] == "compat-wrapper-check", task.get("origin")
assert isinstance(task["delivery"], dict), "missing delivery block"
assert isinstance(task["media"], dict), "missing media block"
assert isinstance(task["screenshot"], dict), "missing screenshot block"
print("TASK_NEW_WRAPPER_RUNTIME_OK")
PY

printf 'TASK_ENTRYPOINT_POLICY_OK\n'
