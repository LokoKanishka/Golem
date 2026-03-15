#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_summary.sh <task_id>
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
chain_type = task.get("chain_type", "(none)")
chain_status = task.get("chain_status", "(none)")
chain_summary = task.get("chain_summary") or {}
chain_plan = task.get("chain_plan") or {}

print(f"task_id: {task.get('task_id', task_path.stem)}")
print(f"status: {task.get('status', '?')}")
print(f"chain_status: {chain_status}")
print(f"chain_type: {chain_type}")
print(f"child_count: {chain_summary.get('child_count', 0)}")
print(f"children_done: {chain_summary.get('children_done', 0)}")
print(f"children_failed: {chain_summary.get('children_failed', 0)}")
print(f"children_with_warnings: {chain_summary.get('children_with_warnings', 0)}")
print(f"step_count: {chain_summary.get('step_count', len(chain_plan.get('steps') or []))}")
print(f"steps_completed: {chain_summary.get('steps_completed', 0)}")
print(f"steps_failed: {chain_summary.get('steps_failed', 0)}")
print(f"steps_pending: {chain_summary.get('steps_pending', 0)}")
print(f"local_steps: {chain_summary.get('local_steps_count', chain_summary.get('local_step_count', 0))}")
print(f"delegated_steps: {chain_summary.get('delegated_steps_count', chain_summary.get('worker_step_count', 0))}")
print(f"worker_steps_done: {chain_summary.get('worker_steps_done', 0)}")
print(f"worker_steps_failed: {chain_summary.get('worker_steps_failed', 0)}")
if chain_summary.get("final_artifact_path"):
    print(f"final_artifact_path: {chain_summary.get('final_artifact_path')}")
if chain_summary.get("headline"):
    print(f"headline: {chain_summary.get('headline')}")
aggregated_artifact_paths = chain_summary.get("aggregated_artifact_paths") or chain_summary.get("artifact_paths") or []
print(f"aggregated_artifacts: {len(aggregated_artifact_paths)}")
worker_result_summaries = chain_summary.get("worker_result_summaries") or []
print(f"worker_result_summaries: {len(worker_result_summaries)}")
if worker_result_summaries:
    print("worker_result_summary_lines:")
    for summary in worker_result_summaries:
        print(f"- {summary}")
worker_outcomes = chain_summary.get("worker_outcomes") or []
if worker_outcomes:
    print("worker_outcomes:")
    for outcome in worker_outcomes:
        print(
            "- [{order}] {name} | child_task_id={child_task_id} | status={status} | worker_state={worker_state} | worker_result_status={worker_result_status}".format(
                order=outcome.get("step_order", "?"),
                name=outcome.get("step_name", "(none)"),
                child_task_id=outcome.get("child_task_id") or "(none)",
                status=outcome.get("status") or "(none)",
                worker_state=outcome.get("worker_state") or "(none)",
                worker_result_status=outcome.get("worker_result_status") or "(none)",
            )
        )
        if outcome.get("summary"):
            print(f"  summary: {outcome.get('summary')}")
        if outcome.get("result_artifact_path"):
            print(f"  result_artifact_path: {outcome.get('result_artifact_path')}")
print(f"artifacts: {len(task.get('artifacts', []))}")
print(f"last_note: {last_note}")
PY
