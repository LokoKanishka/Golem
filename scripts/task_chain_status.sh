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
print(f"steps_blocked: {chain_summary.get('steps_blocked', sum(1 for step in steps if step.get('status') == 'blocked'))}")
print(f"steps_skipped: {chain_summary.get('steps_skipped', sum(1 for step in steps if step.get('status') == 'skipped'))}")
print(f"steps_pending: {chain_summary.get('steps_pending', sum(1 for step in steps if step.get('status') not in {'done', 'failed', 'blocked', 'skipped'}))}")
print(f"local_steps: {chain_summary.get('local_steps_count', chain_summary.get('local_step_count', chain_plan.get('local_step_count', 0)))}")
print(f"delegated_steps: {chain_summary.get('delegated_steps_count', chain_summary.get('worker_step_count', chain_plan.get('worker_step_count', 0)))}")
print(f"worker_steps_done: {chain_summary.get('worker_steps_done', 0)}")
print(f"worker_steps_blocked: {chain_summary.get('worker_steps_blocked', 0)}")
print(f"worker_steps_failed: {chain_summary.get('worker_steps_failed', 0)}")
print(f"children_blocked: {chain_summary.get('children_blocked', 0)}")
if chain_summary.get("decision_source_step"):
    print(f"decision_source_step: {chain_summary.get('decision_source_step')}")
if chain_summary.get("decision_source_worker_result_status"):
    print(f"decision_source_worker_result_status: {chain_summary.get('decision_source_worker_result_status')}")
if chain_summary.get("next_step_selected"):
    print(f"next_step_selected: {chain_summary.get('next_step_selected')}")
skipped_steps = chain_summary.get("skipped_steps") or []
print(f"skipped_steps: {len(skipped_steps)}")
if skipped_steps:
    print(f"skipped_step_names: {', '.join(skipped_steps)}")
if chain_summary.get("decision_reason"):
    print(f"decision_reason: {chain_summary.get('decision_reason')}")
if chain_summary.get("final_artifact_path"):
    print(f"final_artifact_path: {chain_summary.get('final_artifact_path')}")
aggregated_artifact_paths = chain_summary.get("aggregated_artifact_paths") or chain_summary.get("artifact_paths") or []
print(f"aggregated_artifacts: {len(aggregated_artifact_paths)}")

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
        decision_reason = step.get("decision_reason", "")
        if decision_reason:
            print(f"  decision_reason: {decision_reason}")
        worker_state = step.get("worker_state") or ((child.get("worker_run") or {}).get("state", "") if child else "")
        worker_result_status = step.get("worker_result_status") or ((child.get("worker_run") or {}).get("result_status", "") if child else "")
        if worker_state or worker_result_status:
            print(
                f"  worker_state: {worker_state or '(none)'} | worker_result_status: {worker_result_status or '(none)'}"
            )
        worker_result_summary = step.get("worker_result_summary", "")
        if worker_result_summary:
            print(f"  worker_result_summary: {worker_result_summary}")
        worker_result_artifact_path = step.get("worker_result_artifact_path", "")
        if worker_result_artifact_path:
            print(f"  worker_result_artifact_path: {worker_result_artifact_path}")

worker_outcomes = chain_summary.get("worker_outcomes") or []
print("worker_outcomes:")
if not worker_outcomes:
    print("- (none)")
else:
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

conditional_outcomes = chain_summary.get("conditional_outcomes") or []
print("conditional_outcomes:")
if not conditional_outcomes:
    print("- (none)")
else:
    for outcome in conditional_outcomes:
        print(
            "- [{order}] {name} | selected={selected} | status={status} | condition_source_step={condition_source_step} | expected_worker_result_status={expected_worker_result_status}".format(
                order=outcome.get("step_order", "?"),
                name=outcome.get("step_name", "(none)"),
                selected="yes" if outcome.get("selected") else "no",
                status=outcome.get("status") or "(none)",
                condition_source_step=outcome.get("condition_source_step") or "(none)",
                expected_worker_result_status=outcome.get("expected_worker_result_status") or "(none)",
            )
        )
        if outcome.get("decision_reason"):
            print(f"  decision_reason: {outcome.get('decision_reason')}")
PY
