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
plan = root_task.get("chain_plan") if isinstance(root_task.get("chain_plan"), dict) else {}
plan_steps = plan.get("steps") if isinstance(plan.get("steps"), list) else []
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
        child_task_id = step.get("child_task_id", "")
        child = children_by_id.get(child_task_id)
        if child is None:
            for candidate in ordered_children:
                if candidate.get("step_name") == step_name:
                    child = candidate
                    child_task_id = candidate.get("task_id", "")
                    break

        child_status = child.get("status", "") if child else ""
        status = normalize_step_status(step.get("status", ""), child_status, child is not None)
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
        step_summary = compact_text(step.get("summary") or "") or task_summary_line(child)

        step_results.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", index),
                "task_type": step.get("task_type") or (child.get("type", "") if child else ""),
                "execution_mode": step.get("execution_mode") or (child.get("execution_mode", "") if child else ""),
                "critical": bool(step.get("critical", False)),
                "depends_on_step_names": step.get("depends_on_step_names") or [],
                "await_worker_result": bool(step.get("await_worker_result", False)),
                "condition_source_step": step.get("condition_source_step", ""),
                "run_if_worker_result_status": step.get("run_if_worker_result_status", ""),
                "status": status,
                "child_task_id": child_task_id,
                "child_status": child_status,
                "warning": warning,
                "summary": step_summary,
                "decision_source_step": step.get("decision_source_step", ""),
                "decision_reason": step.get("decision_reason", ""),
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
                "depends_on_step_names": [],
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
    headline += ", and a worker result is still required before the chain can continue."
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
    "worker_steps_done": worker_steps_done,
    "worker_steps_blocked": worker_steps_blocked,
    "worker_steps_failed": worker_steps_failed,
    "worker_steps_delegated": worker_steps_delegated,
    "worker_steps_running": worker_steps_running,
    "worker_child_ids": worker_child_ids,
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
    "awaiting_worker_result_steps": awaiting_worker_result_steps,
}

print(json.dumps(summary))
PY
