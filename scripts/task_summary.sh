#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_summary.sh <task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

notes = task.get("notes", [])
last_note = notes[-1] if notes else "(none)"
parent_task_id = task.get("parent_task_id") or "(none)"
depends_on = task.get("depends_on") or []
chain_type = task.get("chain_type") or ""
chain_status = task.get("chain_status") or ""
chain_summary = task.get("chain_summary") or {}
chain_plan = task.get("chain_plan") or {}
worker_run = task.get("worker_run") or {}
step_name = task.get("step_name") or ""
step_order = task.get("step_order")
critical = task.get("critical")
execution_mode = task.get("execution_mode") or ""

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"type: {task.get('type', '?')}")
print(f"status: {task.get('status', '?')}")
print(f"title: {task.get('title', '')}")
print(f"parent_task_id: {parent_task_id}")
print(f"depends_on: {len(depends_on)}")
if step_name:
    print(f"step_name: {step_name}")
if step_order is not None:
    print(f"step_order: {step_order}")
if critical is not None:
    print(f"critical: {'yes' if critical else 'no'}")
if execution_mode:
    print(f"execution_mode: {execution_mode}")
if chain_type:
    print(f"chain_type: {chain_type}")
if chain_status:
    print(f"chain_status: {chain_status}")
if task.get("validated_plan_version"):
    print(f"validated_plan_version: {task.get('validated_plan_version')}")
if task.get("effective_plan_path"):
    print(f"effective_plan_path: {task.get('effective_plan_path')}")
if task.get("preflight_artifact_path"):
    print(f"preflight_artifact_path: {task.get('preflight_artifact_path')}")
if chain_summary:
    print(f"child_count: {chain_summary.get('child_count', 0)}")
    if "step_count" in chain_summary:
        print(f"step_count: {chain_summary.get('step_count', 0)}")
    if "steps_completed" in chain_summary:
        print(f"steps_completed: {chain_summary.get('steps_completed', 0)}")
    if "steps_failed" in chain_summary:
        print(f"steps_failed: {chain_summary.get('steps_failed', 0)}")
    if chain_summary.get("final_artifact_path"):
        print(f"final_artifact_path: {chain_summary.get('final_artifact_path')}")
elif chain_plan:
    print(f"planned_steps: {len(chain_plan.get('steps') or [])}")
if worker_run:
    print(f"worker_state: {worker_run.get('state', '(none)')}")
    print(f"worker_result_status: {worker_run.get('result_status', '(none)')}")
    extracted_summary = worker_run.get("extracted_summary", "")
    if extracted_summary:
        print(f"worker_extracted_summary: {extracted_summary}")
print(f"outputs: {len(task.get('outputs', []))}")
print(f"artifacts: {len(task.get('artifacts', []))}")
print(f"last_note: {last_note}")
PY
