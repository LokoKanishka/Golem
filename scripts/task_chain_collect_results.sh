#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_collect_results.sh <root_task_id>
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

python3 - "$TASKS_DIR" "$root_task_path" <<'PY'
import datetime
import json
import pathlib
import re
import sys


def iso_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def normalize_step_status(step_status: str, child_status: str, child_exists: bool) -> str:
    status = (step_status or "").strip().lower()
    if status in {"done", "completed"}:
        return "done"
    if status in {"blocked", "block"}:
        return "blocked"
    if status in {"failed", "cancelled"}:
        return "failed"
    if status in {"skipped", "skip"}:
        return "skipped"
    if status == "delegated":
        return "delegated"
    if status in {"running", "worker_running"}:
        return "running"
    if status in {"planned", "queued"}:
        return "planned"

    if child_status == "done":
        return "done"
    if child_status == "blocked":
        return "blocked"
    if child_status in {"failed", "cancelled"}:
        return "failed"
    if child_status == "delegated":
        return "delegated"
    if child_status in {"running", "worker_running"}:
        return "running"
    if child_exists:
        return "planned"
    return "planned"


def has_warning(task: dict) -> bool:
    if not task:
        return False
    for output in task.get("outputs", []):
        candidates = [
            output.get("estado_general", ""),
            output.get("status", ""),
            output.get("level", ""),
            output.get("result_status", ""),
        ]
        for candidate in candidates:
            text = str(candidate).upper()
            if "WARN" in text or "WARNING" in text:
                return True
    return False


def compact_text(value: str, limit: int = 220) -> str:
    text = " ".join(str(value).split())
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "chain"


def task_summary_line(task: dict) -> str:
    if not task:
        return ""

    worker_run = task.get("worker_run") or {}
    extracted = compact_text(worker_run.get("extracted_summary", ""))
    if extracted:
        return extracted

    for output in reversed(task.get("outputs", [])):
        summary = compact_text(output.get("summary", ""))
        if summary:
            return summary
        content = compact_text(output.get("content", ""))
        if content:
            return content

    notes = task.get("notes") or []
    if notes:
        return compact_text(notes[-1])

    return ""


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


def dedupe_paths(paths):
    seen = set()
    ordered = []
    for path in paths:
        value = str(path or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def dedupe_values(items):
    seen = set()
    ordered = []
    for item in items:
        value = str(item or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


tasks_dir = pathlib.Path(sys.argv[1])
root_task_path = pathlib.Path(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    root_task = json.load(fh)

root_task_id = root_task.get("task_id", root_task_path.stem)
chain_type = root_task.get("chain_type", "")
if not chain_type:
    print("ERROR: la tarea raiz no tiene chain_type", file=sys.stderr)
    raise SystemExit(1)

children = []
for path in sorted(tasks_dir.glob("*.json")):
    if not path.is_file():
        continue
    with path.open(encoding="utf-8") as fh:
        task = json.load(fh)
    if (task.get("parent_task_id") or "") == root_task_id:
        children.append(task)

children_by_id = {task.get("task_id", ""): task for task in children}
runtime_plan = root_task.get("chain_plan") if isinstance(root_task.get("chain_plan"), dict) else {}
effective_plan = root_task.get("effective_chain_plan") if isinstance(root_task.get("effective_chain_plan"), dict) else {}
plan = effective_plan or runtime_plan
plan_steps = plan.get("steps") if isinstance(plan.get("steps"), list) else []
runtime_plan_steps = runtime_plan.get("steps") if isinstance(runtime_plan.get("steps"), list) else []
runtime_steps_by_name = {
    str(step.get("step_name") or "").strip(): step
    for step in runtime_plan_steps
    if isinstance(step, dict) and str(step.get("step_name") or "").strip()
}
chain_decision = root_task.get("chain_decision") if isinstance(root_task.get("chain_decision"), dict) else {}

ordered_children = sorted(
    children,
    key=lambda task: (
        task.get("step_order", 10**9),
        task.get("created_at", ""),
        task.get("task_id", ""),
    ),
)

step_results = []
if plan_steps:
    for index, step in enumerate(plan_steps, start=1):
        step_name = step.get("step_name") or f"step-{index}"
        runtime_step = runtime_steps_by_name.get(step_name, step)
        child_task_id = runtime_step.get("child_task_id", "") or step.get("child_task_id", "")
        child = children_by_id.get(child_task_id)
        if child is None:
            for candidate in ordered_children:
                if candidate.get("step_name") == step_name:
                    child = candidate
                    child_task_id = candidate.get("task_id", "")
                    break

        child_status = child.get("status", "") if child else ""
        status = normalize_step_status(runtime_step.get("status", ""), child_status, child is not None)
        warning = has_warning(child)
        worker_run = (child or {}).get("worker_run") or {}
        worker_result = latest_worker_result_output(child or {})
        child_artifacts = [artifact.get("path", "") for artifact in (child or {}).get("artifacts", []) if artifact.get("path")]
        worker_result_artifact_path = (
            worker_result.get("result_artifact_path")
            or worker_run.get("result_artifact_path", "")
        )
        artifact_paths = dedupe_paths(child_artifacts + worker_result.get("artifact_paths", []) + [worker_result_artifact_path])
        worker_summary = compact_text(
            worker_result.get("summary")
            or worker_result.get("extracted_summary")
            or worker_run.get("extracted_summary", "")
        )
        step_summary = compact_text(runtime_step.get("summary") or "") or task_summary_line(child)

        step_results.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", index),
                "task_type": step.get("task_type") or (child.get("type", "") if child else ""),
                "execution_mode": step.get("execution_mode") or (child.get("execution_mode", "") if child else ""),
                "critical": bool(step.get("critical", False)),
                "title": step.get("title") or (child.get("title", "") if child else ""),
                "objective": step.get("objective") or (child.get("objective", "") if child else ""),
                "depends_on_step_names": step.get("depends_on_step_names") or [],
                "join_group": step.get("join_group", ""),
                "await_group": step.get("await_group", ""),
                "await_worker_result": bool(step.get("await_worker_result", False)),
                "condition_source_step": step.get("condition_source_step", ""),
                "run_if_worker_result_status": step.get("run_if_worker_result_status", ""),
                "status": status,
                "child_task_id": child_task_id,
                "child_status": child_status,
                "warning": warning,
                "summary": step_summary,
                "decision_source_step": runtime_step.get("decision_source_step", "") or step.get("decision_source_step", ""),
                "decision_reason": runtime_step.get("decision_reason", "") or step.get("decision_reason", ""),
                "artifact_paths": artifact_paths,
                "worker_state": worker_run.get("state", ""),
                "worker_result_status": worker_result.get("status") or worker_run.get("result_status", ""),
                "worker_result_summary": worker_summary,
                "worker_result_artifact_path": worker_result_artifact_path,
                "worker_result_source_files": dedupe_paths(
                    worker_result.get("result_source_files", []) + worker_run.get("result_source_files", [])
                ),
            }
        )
else:
    for index, child in enumerate(ordered_children, start=1):
        worker_run = child.get("worker_run") or {}
        worker_result = latest_worker_result_output(child)
        worker_result_artifact_path = (
            worker_result.get("result_artifact_path")
            or worker_run.get("result_artifact_path", "")
        )
        artifact_paths = dedupe_paths(
            [artifact.get("path", "") for artifact in child.get("artifacts", []) if artifact.get("path")]
            + worker_result.get("artifact_paths", [])
            + [worker_result_artifact_path]
        )
        step_results.append(
            {
                "step_name": child.get("step_name") or f"step-{index}",
                "step_order": child.get("step_order", index),
                "task_type": child.get("type", ""),
                "execution_mode": child.get("execution_mode", ""),
                "critical": bool(child.get("critical", True)),
                "title": child.get("title", ""),
                "objective": child.get("objective", ""),
                "depends_on_step_names": [],
                "join_group": child.get("join_group", ""),
                "await_group": child.get("await_group", ""),
                "await_worker_result": bool(child.get("await_worker_result", False)),
                "condition_source_step": child.get("condition_source_step", ""),
                "run_if_worker_result_status": child.get("run_if_worker_result_status", ""),
                "status": normalize_step_status("", child.get("status", ""), True),
                "child_task_id": child.get("task_id", ""),
                "child_status": child.get("status", ""),
                "warning": has_warning(child),
                "summary": task_summary_line(child),
                "decision_source_step": child.get("decision_source_step", ""),
                "decision_reason": child.get("decision_reason", ""),
                "artifact_paths": artifact_paths,
                "worker_state": worker_run.get("state", ""),
                "worker_result_status": worker_result.get("status") or worker_run.get("result_status", ""),
                "worker_result_summary": compact_text(
                    worker_result.get("summary")
                    or worker_result.get("extracted_summary")
                    or worker_run.get("extracted_summary", "")
                ),
                "worker_result_artifact_path": worker_result_artifact_path,
                "worker_result_source_files": dedupe_paths(
                    worker_result.get("result_source_files", []) + worker_run.get("result_source_files", [])
                ),
            }
        )

step_results.sort(key=lambda step: (step.get("step_order", 10**9), step.get("step_name", "")))
step_results_by_name = {step.get("step_name", ""): step for step in step_results}

dependency_groups = plan.get("dependency_groups") if isinstance(plan.get("dependency_groups"), list) else []
effective_plan_path = str(root_task.get("effective_plan_path") or "").strip()
effective_plan_sha256 = str(root_task.get("effective_plan_sha256") or "").strip()
preflight_artifact_path = str(root_task.get("preflight_artifact_path") or "").strip()
preflight_sha256 = str(root_task.get("preflight_sha256") or "").strip()
validated_plan_version = str(root_task.get("validated_plan_version") or plan.get("plan_version") or plan.get("version") or "").strip()
validated_at = str(root_task.get("validated_at") or "").strip()
preflighted_at = str(root_task.get("preflighted_at") or "").strip()
dependency_barriers = []
dependency_barrier_map = {}
for group in dependency_groups:
    group_name = str(group.get("group_name") or group.get("name") or "").strip()
    if not group_name:
        continue

    group_type = str(group.get("group_type") or "join_barrier").strip() or "join_barrier"
    satisfaction_policy = str(group.get("satisfaction_policy") or "all_done").strip() or "all_done"
    continue_on_blocked = bool(group.get("continue_on_blocked", False))
    continue_on_failed = bool(group.get("continue_on_failed", False))
    step_names = dedupe_values(group.get("step_names") or [])
    if not step_names and group_type == "await_group":
        step_names = [
            step.get("step_name", "")
            for step in step_results
            if str(step.get("await_group", "")).strip() == group_name
        ]
    if not step_names:
        step_names = dedupe_values(
            dependency
            for step in step_results
            if str(step.get("join_group", "")).strip() == group_name
            for dependency in (step.get("depends_on_step_names") or [])
        )

    step_states = []
    done_step_names = []
    waiting_step_names = []
    failed_step_names = []
    blocked_step_names = []
    skipped_step_names = []
    for step_name in step_names:
        state = (step_results_by_name.get(step_name) or {}).get("status", "planned")
        step_states.append({"step_name": step_name, "status": state})
        if state == "done":
            done_step_names.append(step_name)
        elif state in {"delegated", "running", "planned"}:
            waiting_step_names.append(step_name)
        elif state == "failed":
            failed_step_names.append(step_name)
        elif state == "blocked":
            blocked_step_names.append(step_name)
        elif state == "skipped":
            skipped_step_names.append(step_name)

    if failed_step_names and not continue_on_failed:
        barrier_status = "failed"
        barrier_reason = "failed dependency steps: " + ", ".join(failed_step_names)
    elif blocked_step_names and not continue_on_blocked:
        barrier_status = "blocked"
        barrier_reason = "blocked dependency steps: " + ", ".join(blocked_step_names)
    elif skipped_step_names and not continue_on_failed:
        barrier_status = "failed"
        barrier_reason = "skipped dependency steps: " + ", ".join(skipped_step_names)
    elif satisfaction_policy == "all_done" and step_names and len(done_step_names) == len(step_names):
        barrier_status = "satisfied"
        barrier_reason = "all dependency steps resolved as done"
    else:
        barrier_status = "waiting"
        unresolved = waiting_step_names or [row["step_name"] for row in step_states if row["status"] != "done"]
        barrier_reason = (
            "waiting for dependency steps: " + ", ".join(unresolved)
            if unresolved
            else "waiting for dependency state changes"
        )

    barrier = {
        "group_name": group_name,
        "group_type": group_type,
        "satisfaction_policy": satisfaction_policy,
        "continue_on_blocked": continue_on_blocked,
        "continue_on_failed": continue_on_failed,
        "status": barrier_status,
        "reason": barrier_reason,
        "step_names": step_names,
        "step_states": step_states,
        "done_step_names": done_step_names,
        "waiting_step_names": waiting_step_names,
        "failed_step_names": failed_step_names,
        "blocked_step_names": blocked_step_names,
        "skipped_step_names": skipped_step_names,
        "used_by_step_names": dedupe_values(group.get("used_by_step_names") or []),
    }
    dependency_barriers.append(barrier)
    dependency_barrier_map[group_name] = barrier

for step in step_results:
    join_group = str(step.get("join_group", "")).strip()
    await_group = str(step.get("await_group", "")).strip()
    if join_group and join_group in dependency_barrier_map:
        step["join_group_status"] = dependency_barrier_map[join_group]["status"]
        step["join_group_reason"] = dependency_barrier_map[join_group]["reason"]
    else:
        step["join_group_status"] = ""
        step["join_group_reason"] = ""
    if await_group and await_group in dependency_barrier_map:
        step["await_group_status"] = dependency_barrier_map[await_group]["status"]
        step["await_group_reason"] = dependency_barrier_map[await_group]["reason"]
    else:
        step["await_group_status"] = ""
        step["await_group_reason"] = ""

child_task_ids = [task.get("task_id", "") for task in children]
children_done = sum(1 for child in children if child.get("status") == "done")
children_failed = sum(1 for child in children if child.get("status") in {"failed", "cancelled"})
children_blocked = sum(1 for child in children if child.get("status") == "blocked")
children_delegated = sum(1 for child in children if child.get("status") == "delegated")
children_running = sum(1 for child in children if child.get("status") in {"running", "worker_running"})
warning_child_ids = [child.get("task_id", "") for child in children if has_warning(child)]
children_with_warnings = len(warning_child_ids)
failed_child_ids = [child.get("task_id", "") for child in children if child.get("status") in {"failed", "cancelled"}]
blocked_child_ids = [child.get("task_id", "") for child in children if child.get("status") == "blocked"]

aggregated_artifact_paths = dedupe_paths(
    path
    for step in step_results
    for path in step.get("artifact_paths", [])
)

step_count = len(step_results)
steps_completed = sum(1 for step in step_results if step.get("status") == "done")
steps_failed = sum(1 for step in step_results if step.get("status") == "failed")
steps_blocked = sum(1 for step in step_results if step.get("status") == "blocked")
steps_delegated = sum(1 for step in step_results if step.get("status") == "delegated")
steps_running = sum(1 for step in step_results if step.get("status") == "running")
steps_skipped = sum(1 for step in step_results if step.get("status") == "skipped")
steps_pending = sum(1 for step in step_results if step.get("status") == "planned")
critical_step_count = sum(1 for step in step_results if step.get("critical"))
critical_steps_failed = sum(1 for step in step_results if step.get("critical") and step.get("status") == "failed")
critical_steps_blocked = sum(1 for step in step_results if step.get("critical") and step.get("status") == "blocked")
critical_steps_delegated = sum(1 for step in step_results if step.get("critical") and step.get("status") == "delegated")
critical_steps_running = sum(1 for step in step_results if step.get("critical") and step.get("status") == "running")
critical_steps_skipped = sum(1 for step in step_results if step.get("critical") and step.get("status") == "skipped")
critical_steps_pending = sum(1 for step in step_results if step.get("critical") and step.get("status") == "planned")
noncritical_steps_failed = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "failed")
noncritical_steps_blocked = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "blocked")
noncritical_steps_delegated = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "delegated")
noncritical_steps_running = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "running")
noncritical_steps_skipped = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "skipped")
noncritical_steps_pending = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "planned")
local_step_count = sum(1 for step in step_results if step.get("execution_mode") == "local")
worker_step_count = sum(1 for step in step_results if step.get("execution_mode") == "worker")
worker_steps_done = sum(
    1
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("status") == "done"
)
worker_steps_blocked = sum(
    1
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("status") == "blocked"
)
worker_steps_failed = sum(
    1
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("status") == "failed"
)
worker_steps_delegated = sum(
    1
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("status") == "delegated"
)
worker_steps_running = sum(
    1
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("status") == "running"
)
worker_child_ids = [
    step.get("child_task_id", "")
    for step in step_results
    if step.get("execution_mode") == "worker" and step.get("child_task_id")
]
awaiting_worker_child_ids = [
    step.get("child_task_id", "")
    for step in step_results
    if step.get("await_worker_result") and step.get("status") in {"delegated", "running", "planned"} and step.get("child_task_id")
]
awaiting_worker_step_names = [
    step.get("step_name", "")
    for step in step_results
    if step.get("await_worker_result") and step.get("status") in {"delegated", "running", "planned"}
]
resolved_worker_child_ids = [
    step.get("child_task_id", "")
    for step in step_results
    if step.get("await_worker_result") and step.get("status") in {"done", "failed", "blocked"} and step.get("child_task_id")
]
resolved_worker_step_names = [
    step.get("step_name", "")
    for step in step_results
    if step.get("await_worker_result") and step.get("status") in {"done", "failed", "blocked"}
]
dependency_barriers_satisfied = sum(1 for barrier in dependency_barriers if barrier.get("status") == "satisfied")
dependency_barriers_waiting = sum(1 for barrier in dependency_barriers if barrier.get("status") == "waiting")
dependency_barriers_failed = sum(1 for barrier in dependency_barriers if barrier.get("status") == "failed")
dependency_barriers_blocked = sum(1 for barrier in dependency_barriers if barrier.get("status") == "blocked")
waiting_dependency_barrier_names = [
    barrier.get("group_name", "")
    for barrier in dependency_barriers
    if barrier.get("status") == "waiting"
]
failed_dependency_barrier_names = [
    barrier.get("group_name", "")
    for barrier in dependency_barriers
    if barrier.get("status") == "failed"
]
blocked_dependency_barrier_names = [
    barrier.get("group_name", "")
    for barrier in dependency_barriers
    if barrier.get("status") == "blocked"
]
local_child_ids = [
    step.get("child_task_id", "")
    for step in step_results
    if step.get("execution_mode") != "worker" and step.get("child_task_id")
]

worker_outcomes = []
worker_result_summaries = []
for step in step_results:
    if step.get("execution_mode") != "worker":
        continue
    outcome = {
        "step_name": step.get("step_name"),
        "step_order": step.get("step_order"),
        "child_task_id": step.get("child_task_id", ""),
        "child_status": step.get("child_status", ""),
        "status": step.get("status", ""),
        "worker_state": step.get("worker_state", ""),
        "worker_result_status": step.get("worker_result_status", ""),
        "summary": step.get("worker_result_summary") or step.get("summary", ""),
        "result_artifact_path": step.get("worker_result_artifact_path", ""),
        "result_source_files": step.get("worker_result_source_files", []),
        "artifact_paths": step.get("artifact_paths", []),
        "warning": bool(step.get("warning", False)),
    }
    worker_outcomes.append(outcome)
    if outcome["summary"]:
        worker_result_summaries.append(outcome["summary"])

conditional_outcomes = []
skipped_steps = []
for step in step_results:
    has_condition = bool(step.get("condition_source_step") or step.get("run_if_worker_result_status"))
    if not has_condition and step.get("status") != "skipped":
        continue
    if step.get("status") == "skipped":
        skipped_steps.append(step.get("step_name", ""))
    conditional_outcomes.append(
        {
            "step_name": step.get("step_name"),
            "step_order": step.get("step_order"),
            "condition_source_step": step.get("condition_source_step") or chain_decision.get("decision_source_step", ""),
            "expected_worker_result_status": step.get("run_if_worker_result_status", ""),
            "selected": step.get("status") != "skipped",
            "status": step.get("status", ""),
            "child_task_id": step.get("child_task_id", ""),
            "decision_source_step": step.get("decision_source_step") or chain_decision.get("decision_source_step", ""),
            "decision_reason": step.get("decision_reason") or chain_decision.get("decision_reason", ""),
            "summary": step.get("summary", ""),
        }
    )

decision_reason = chain_decision.get("decision_reason", "")
decision_source_step = chain_decision.get("decision_source_step", "")
next_step_selected = chain_decision.get("next_step_selected", "")
decision_source_worker_result_status = chain_decision.get("decision_source_worker_result_status", "")

if not decision_source_step and conditional_outcomes:
    decision_source_step = conditional_outcomes[0].get("condition_source_step", "")
if not skipped_steps:
    skipped_steps = [step.get("step_name", "") for step in step_results if step.get("status") == "skipped"]
if not next_step_selected:
    for outcome in conditional_outcomes:
        if outcome.get("selected"):
            next_step_selected = outcome.get("step_name", "")
            break
if not decision_reason and conditional_outcomes:
    decision_reason = conditional_outcomes[0].get("decision_reason", "")
if not decision_source_worker_result_status and decision_source_step:
    for step in step_results:
        if step.get("step_name") == decision_source_step:
            decision_source_worker_result_status = step.get("worker_result_status") or step.get("status", "")
            break

awaiting_worker_result_steps = sum(
    1
    for step in step_results
    if step.get("await_worker_result") and step.get("status") in {"delegated", "running"}
)

if critical_steps_failed > 0 or critical_steps_pending > 0 or critical_steps_skipped > 0:
    chain_status = "failed"
    final_task_status = "failed"
elif critical_steps_blocked > 0:
    chain_status = "blocked"
    final_task_status = "blocked"
elif awaiting_worker_result_steps > 0:
    chain_status = "awaiting_worker_result"
    final_task_status = "delegated"
elif noncritical_steps_failed > 0 or noncritical_steps_pending > 0 or noncritical_steps_blocked > 0 or children_with_warnings > 0:
    chain_status = "completed_with_warnings"
    final_task_status = "done"
else:
    chain_status = "completed"
    final_task_status = "done"

if chain_status == "failed":
    headline = f"Chain failed: {steps_completed}/{step_count} step(s) completed"
    if steps_blocked:
        headline += f", {steps_blocked} blocked"
    if steps_skipped:
        headline += f", {steps_skipped} skipped"
    headline += ", and one or more critical steps did not finish cleanly."
elif chain_status == "blocked":
    headline = f"Chain blocked: {steps_completed}/{step_count} step(s) completed, {steps_blocked} blocked"
    if steps_skipped:
        headline += f", {steps_skipped} skipped"
    headline += ", and one or more critical steps could not start or continue."
elif chain_status == "awaiting_worker_result":
    headline = (
        f"Chain delegated and waiting: {steps_completed}/{step_count} step(s) completed, "
        f"{steps_delegated} delegated, {steps_running} running"
    )
    headline += f", awaiting {awaiting_worker_result_steps} worker result(s) before the chain can continue."
    if waiting_dependency_barrier_names:
        headline += " Waiting dependency barriers: " + ", ".join(waiting_dependency_barrier_names) + "."
elif chain_status == "completed_with_warnings":
    headline = f"Chain completed with warnings: {steps_completed}/{step_count} step(s) completed, {steps_failed} failed"
    if steps_blocked:
        headline += f", {steps_blocked} blocked"
    if steps_skipped:
        headline += f", {steps_skipped} skipped"
    headline += f", {children_with_warnings} warning signal(s)."
else:
    headline = f"Chain completed cleanly: {steps_completed}/{step_count} step(s) done"
    if steps_skipped:
        headline += f", {steps_skipped} skipped"
    headline += f" across {local_step_count} local and {worker_step_count} worker step(s)."

summary = {
    "root_task_id": root_task_id,
    "chain_type": chain_type,
    "generated_at": iso_now(),
    "artifact_slug": slugify(chain_type),
    "child_task_ids": child_task_ids,
    "child_count": len(children),
    "children_done": children_done,
    "children_failed": children_failed,
    "children_blocked": children_blocked,
    "children_delegated": children_delegated,
    "children_running": children_running,
    "children_with_warnings": children_with_warnings,
    "failed_child_ids": failed_child_ids,
    "blocked_child_ids": blocked_child_ids,
    "warning_child_ids": warning_child_ids,
    "aggregated_artifact_paths": aggregated_artifact_paths,
    "artifact_paths": aggregated_artifact_paths,
    "effective_plan_path": effective_plan_path,
    "effective_plan_sha256": effective_plan_sha256,
    "preflight_artifact_path": preflight_artifact_path,
    "preflight_sha256": preflight_sha256,
    "validated_plan_version": validated_plan_version,
    "validated_at": validated_at,
    "preflighted_at": preflighted_at,
    "step_results": step_results,
    "step_count": step_count,
    "steps_completed": steps_completed,
    "steps_failed": steps_failed,
    "steps_blocked": steps_blocked,
    "steps_delegated": steps_delegated,
    "steps_running": steps_running,
    "steps_skipped": steps_skipped,
    "steps_pending": steps_pending,
    "critical_step_count": critical_step_count,
    "critical_steps_failed": critical_steps_failed,
    "critical_steps_blocked": critical_steps_blocked,
    "critical_steps_delegated": critical_steps_delegated,
    "critical_steps_running": critical_steps_running,
    "critical_steps_skipped": critical_steps_skipped,
    "critical_steps_pending": critical_steps_pending,
    "noncritical_steps_failed": noncritical_steps_failed,
    "noncritical_steps_blocked": noncritical_steps_blocked,
    "noncritical_steps_delegated": noncritical_steps_delegated,
    "noncritical_steps_running": noncritical_steps_running,
    "noncritical_steps_skipped": noncritical_steps_skipped,
    "noncritical_steps_pending": noncritical_steps_pending,
    "local_step_count": local_step_count,
    "worker_step_count": worker_step_count,
    "local_steps_count": local_step_count,
    "delegated_steps_count": worker_step_count,
    "dependency_group_count": len(dependency_barriers),
    "dependency_barriers": dependency_barriers,
    "dependency_barriers_satisfied": dependency_barriers_satisfied,
    "dependency_barriers_waiting": dependency_barriers_waiting,
    "dependency_barriers_failed": dependency_barriers_failed,
    "dependency_barriers_blocked": dependency_barriers_blocked,
    "waiting_dependency_barrier_names": waiting_dependency_barrier_names,
    "failed_dependency_barrier_names": failed_dependency_barrier_names,
    "blocked_dependency_barrier_names": blocked_dependency_barrier_names,
    "worker_steps_done": worker_steps_done,
    "worker_steps_blocked": worker_steps_blocked,
    "worker_steps_failed": worker_steps_failed,
    "worker_steps_delegated": worker_steps_delegated,
    "worker_steps_running": worker_steps_running,
    "worker_child_ids": worker_child_ids,
    "awaiting_worker_child_ids": awaiting_worker_child_ids,
    "awaiting_worker_step_names": awaiting_worker_step_names,
    "awaiting_worker_result_steps": awaiting_worker_result_steps,
    "resolved_worker_child_ids": resolved_worker_child_ids,
    "resolved_worker_step_names": resolved_worker_step_names,
    "resolved_worker_result_steps": len(resolved_worker_step_names),
    "local_child_ids": local_child_ids,
    "worker_result_summaries": worker_result_summaries,
    "worker_outcomes": worker_outcomes,
    "decision_reason": decision_reason,
    "decision_source_step": decision_source_step,
    "decision_source_worker_result_status": decision_source_worker_result_status,
    "next_step_selected": next_step_selected,
    "skipped_steps": [step_name for step_name in skipped_steps if step_name],
    "conditional_outcomes": conditional_outcomes,
    "headline": headline,
    "chain_status": chain_status,
    "final_task_status": final_task_status,
}

print(json.dumps(summary))
PY
