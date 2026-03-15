#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_status.sh <root_task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta root_task_id"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

python3 - "$TASKS_DIR" "$task_path" <<'PY'
import json
import pathlib
import sys

tasks_dir = pathlib.Path(sys.argv[1])
task_path = pathlib.Path(sys.argv[2])

with task_path.open(encoding="utf-8") as fh:
    root = json.load(fh)

children = {}
for path in tasks_dir.glob("*.json"):
    with path.open(encoding="utf-8") as fh:
        task = json.load(fh)
    if (task.get("parent_task_id") or "") == root.get("task_id", task_path.stem):
        children[task.get("task_id", "")] = task

chain_plan = root.get("chain_plan") if isinstance(root.get("chain_plan"), dict) else {}
steps = chain_plan.get("steps") if isinstance(chain_plan.get("steps"), list) else []
chain_summary = root.get("chain_summary") or {}

print(f"task_id: {root.get('task_id', task_path.stem)}")
print(f"status: {root.get('status', '?')}")
print(f"chain_status: {root.get('chain_status', '(none)')}")
print(f"chain_type: {root.get('chain_type', '(none)')}")
print(f"step_count: {chain_summary.get('step_count', len(steps))}")
print(f"steps_completed: {chain_summary.get('steps_completed', sum(1 for step in steps if step.get('status') == 'done'))}")
print(f"steps_failed: {chain_summary.get('steps_failed', sum(1 for step in steps if step.get('status') == 'failed'))}")
print(f"steps_pending: {chain_summary.get('steps_pending', sum(1 for step in steps if step.get('status') not in {'done', 'failed'}))}")
print(f"local_steps: {chain_summary.get('local_step_count', chain_plan.get('local_step_count', 0))}")
print(f"worker_steps: {chain_summary.get('worker_step_count', chain_plan.get('worker_step_count', 0))}")
if chain_summary.get("final_artifact_path"):
    print(f"final_artifact_path: {chain_summary.get('final_artifact_path')}")

print("steps:")
if not steps:
    print("- (none)")
else:
    ordered_steps = sorted(steps, key=lambda step: (step.get("step_order", 10**9), step.get("step_name", "")))
    for step in ordered_steps:
        child_task_id = step.get("child_task_id", "")
        child = children.get(child_task_id) if child_task_id else None
        child_status = step.get("child_status") or (child.get("status", "") if child else "(none)")
        summary = step.get("summary", "")
        print(
            "- [{order}] {name} | mode={mode} | critical={critical} | status={status} | child_task_id={child_task_id} | child_status={child_status}".format(
                order=step.get("step_order", "?"),
                name=step.get("step_name", "(none)"),
                mode=step.get("execution_mode", "(none)"),
                critical="yes" if step.get("critical") else "no",
                status=step.get("status", "(none)"),
                child_task_id=child_task_id or "(none)",
                child_status=child_status or "(none)",
            )
        )
        if summary:
            print(f"  summary: {summary}")
        worker_state = step.get("worker_state") or ((child.get("worker_run") or {}).get("state", "") if child else "")
        worker_result_status = step.get("worker_result_status") or ((child.get("worker_run") or {}).get("result_status", "") if child else "")
        if worker_state or worker_result_status:
            print(
                f"  worker_state: {worker_state or '(none)'} | worker_result_status: {worker_result_status or '(none)'}"
            )
PY
