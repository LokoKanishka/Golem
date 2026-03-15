#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
COLLECT_RESULTS="$REPO_ROOT/scripts/task_chain_collect_results.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_decide_next.sh <root_task_id>
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

root_task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$root_task_path" ]; then
  fatal "no existe la tarea raiz: $task_id"
fi

./scripts/validate_chain_plan.sh "$task_id"

summary_json="$("$COLLECT_RESULTS" "$task_id")"
tmp_path="$(mktemp "$TASKS_DIR/.task-chain-decision.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

decision_json="$(
  python3 - "$root_task_path" "$summary_json" "$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])
tmp_path = pathlib.Path(sys.argv[3])
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

with root_task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

chain_plan = task.get("chain_plan")
if not isinstance(chain_plan, dict):
    print("ERROR: la tarea raiz no tiene chain_plan", file=sys.stderr)
    raise SystemExit(1)

steps = chain_plan.get("steps")
if not isinstance(steps, list):
    print("ERROR: chain_plan.steps no es una lista", file=sys.stderr)
    raise SystemExit(1)

conditional_steps = [step for step in steps if step.get("condition_source_step") or step.get("run_if_worker_result_status")]
if not conditional_steps:
    print("ERROR: la cadena no tiene pasos condicionales", file=sys.stderr)
    raise SystemExit(1)

step_results = {step.get("step_name", ""): step for step in summary.get("step_results", [])}
decision_source_step = conditional_steps[0].get("condition_source_step", "")
source_step = step_results.get(decision_source_step)
if not decision_source_step or source_step is None:
    print("ERROR: no se pudo resolver el paso fuente para la decision", file=sys.stderr)
    raise SystemExit(1)

source_worker_result_status = source_step.get("worker_result_status") or source_step.get("status", "")
decision_step = None
for step in steps:
    if step.get("task_type") == "chain-decision":
        decision_step = step
        break

conditional_outcomes = []
selected_steps = []
skipped_steps = []

for step in steps:
    if step.get("step_name") == decision_source_step:
        continue
    if not (step.get("condition_source_step") or step.get("run_if_worker_result_status")):
        continue

    expected_status = step.get("run_if_worker_result_status", "done")
    step_name = step.get("step_name", "")
    selected = source_worker_result_status == expected_status
    if selected:
        reason = (
            f"selected {step_name} because {decision_source_step} returned "
            f"worker_result_status={source_worker_result_status or '(none)'}"
        )
        selected_steps.append(step_name)
        if step.get("status") == "skipped":
            step["status"] = "planned"
        step["summary"] = reason
    else:
        reason = (
            f"skipped {step_name} because {decision_source_step} returned "
            f"worker_result_status={source_worker_result_status or '(none)'} "
            f"instead of {expected_status}"
        )
        skipped_steps.append(step_name)
        step["status"] = "skipped"
        step["summary"] = reason
        step["finished_at"] = now

    step["decision_source_step"] = decision_source_step
    step["decision_reason"] = reason

    conditional_outcomes.append(
        {
            "step_name": step_name,
            "step_order": step.get("step_order"),
            "condition_source_step": decision_source_step,
            "expected_worker_result_status": expected_status,
            "selected": selected,
            "status": step.get("status", ""),
            "child_task_id": step.get("child_task_id", ""),
            "decision_source_step": decision_source_step,
            "decision_reason": reason,
            "summary": step.get("summary", ""),
        }
    )

next_step_selected = selected_steps[0] if selected_steps else "close-root"
decision_reason = (
    f"selected {next_step_selected} because {decision_source_step} returned "
    f"worker_result_status={source_worker_result_status or '(none)'}"
    if selected_steps
    else (
        f"selected close-root because {decision_source_step} returned "
        f"worker_result_status={source_worker_result_status or '(none)'} "
        f"and the conditional local follow-up was skipped"
    )
)

if decision_step is not None:
    decision_step["status"] = "done"
    decision_step["summary"] = decision_reason
    decision_step["decision_source_step"] = decision_source_step
    decision_step["decision_reason"] = decision_reason
    decision_step["finished_at"] = now

task["chain_decision"] = {
    "decided_at": now,
    "decision_reason": decision_reason,
    "decision_source_step": decision_source_step,
    "decision_source_worker_result_status": source_worker_result_status,
    "next_step_selected": next_step_selected,
    "skipped_steps": skipped_steps,
    "conditional_outcomes": conditional_outcomes,
}
task["updated_at"] = now

with tmp_path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, indent=2, ensure_ascii=True)
    fh.write("\n")

print(
    json.dumps(
        {
            "decision_reason": decision_reason,
            "decision_source_step": decision_source_step,
            "decision_source_worker_result_status": source_worker_result_status,
            "next_step_selected": next_step_selected,
            "skipped_steps": skipped_steps,
            "conditional_outcomes": conditional_outcomes,
        }
    )
)
PY
)"

mv "$tmp_path" "$root_task_path"
trap - EXIT
printf '%s\n' "$decision_json"
