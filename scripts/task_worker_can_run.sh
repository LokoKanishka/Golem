#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
POLICY_PATH="$REPO_ROOT/config/worker_run_policy.json"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_worker_can_run.sh <task_id>
  ./scripts/task_worker_can_run.sh type <task_type>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [ ! -f "$POLICY_PATH" ]; then
  fatal "falta worker_run_policy.json"
fi

mode="${1:-}"
task_type=""
task_status=""

case "$mode" in
  type)
    task_type="${2:-}"
    if [ -z "$task_type" ]; then
      usage
      fatal "falta task_type"
    fi
    ;;
  "")
    usage
    fatal "falta task_id o type"
    ;;
  *)
    task_id="$mode"
    task_path="$TASKS_DIR/${task_id}.json"
    if [ ! -f "$task_path" ]; then
      fatal "no existe la tarea: $task_id"
    fi
    readarray -t task_meta < <(
      python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

print(task.get("type", ""))
print(task.get("status", ""))
PY
    )
    task_type="${task_meta[0]:-}"
    task_status="${task_meta[1]:-}"
    ;;
esac

set +e
decision_output="$(
  python3 - "$POLICY_PATH" "$task_type" "$task_status" <<'PY'
import json
import pathlib
import sys

policy_path = pathlib.Path(sys.argv[1])
task_type = sys.argv[2]
task_status = sys.argv[3]

with policy_path.open(encoding="utf-8") as fh:
    policy = json.load(fh)

allowed = set(policy.get("allow_real_codex_run_for", []))
denied = set(policy.get("deny_real_codex_run_for", []))
sandbox_modes = policy.get("allowed_sandbox_modes", [])
sandbox_mode = sandbox_modes[0] if sandbox_modes else "(none)"
default_mode = policy.get("default_mode", "deny")

if task_type in denied:
    decision = False
    rationale = "task_type denied explicitly by worker_run_policy"
elif task_type in allowed:
    decision = True
    rationale = "task_type allowed explicitly by worker_run_policy"
elif default_mode == "allow":
    decision = True
    rationale = "task_type allowed by default_mode"
else:
    decision = False
    rationale = "task_type denied by default_mode"

print(f"allowed: {'yes' if decision else 'no'}")
print(f"task_type: {task_type or '(none)'}")
print(f"task_status: {task_status or '(n/a)'}")
print(f"rationale: {rationale}")
print(f"sandbox_mode: {sandbox_mode}")
print("decision_source: worker_run_policy")
print(f"policy_version: {policy.get('version', '(none)')}")
sys.exit(0 if decision else 1)
PY
)"
decision_exit="$?"
set -e

printf '%s\n' "$decision_output"
exit "$decision_exit"
