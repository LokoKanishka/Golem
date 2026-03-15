#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_finalize.sh <root_task_id>
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

mkdir -p "$OUTBOX_DIR"

summary_json="$(
  python3 - "$TASKS_DIR" "$root_task_path" <<'PY'
import datetime
import json
import pathlib
import re
import sys


def iso_now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "chain"


def normalize_step_status(step_status: str, child_status: str, child_exists: bool) -> str:
    status = (step_status or "").strip().lower()
    if status in {"done", "completed"}:
        return "done"
    if status in {"failed", "cancelled"}:
        return "failed"
    if status in {"running", "worker_running", "delegated"}:
        return "running"
    if status in {"planned", "queued"}:
        return "planned"

    if child_status == "done":
        return "done"
    if child_status in {"failed", "cancelled"}:
        return "failed"
    if child_status in {"running", "delegated", "worker_running"}:
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
        artifacts = [artifact.get("path", "") for artifact in (child or {}).get("artifacts", []) if artifact.get("path")]
        worker_run = (child or {}).get("worker_run") or {}

        step_results.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", index),
                "task_type": step.get("task_type") or (child.get("type", "") if child else ""),
                "execution_mode": step.get("execution_mode") or (child.get("execution_mode", "") if child else ""),
                "critical": bool(step.get("critical", False)),
                "depends_on_step_names": step.get("depends_on_step_names") or [],
                "status": status,
                "child_task_id": child_task_id,
                "child_status": child_status,
                "warning": warning,
                "summary": task_summary_line(child),
                "artifact_paths": artifacts,
                "worker_state": worker_run.get("state", ""),
                "worker_result_status": worker_run.get("result_status", ""),
                "worker_result_artifact_path": worker_run.get("result_artifact_path", ""),
            }
        )
else:
    for index, child in enumerate(ordered_children, start=1):
        child_status = child.get("status", "")
        worker_run = child.get("worker_run") or {}
        step_results.append(
            {
                "step_name": child.get("step_name") or f"step-{index}",
                "step_order": child.get("step_order", index),
                "task_type": child.get("type", ""),
                "execution_mode": child.get("execution_mode", ""),
                "critical": bool(child.get("critical", True)),
                "depends_on_step_names": [],
                "status": normalize_step_status("", child_status, True),
                "child_task_id": child.get("task_id", ""),
                "child_status": child_status,
                "warning": has_warning(child),
                "summary": task_summary_line(child),
                "artifact_paths": [artifact.get("path", "") for artifact in child.get("artifacts", []) if artifact.get("path")],
                "worker_state": worker_run.get("state", ""),
                "worker_result_status": worker_run.get("result_status", ""),
                "worker_result_artifact_path": worker_run.get("result_artifact_path", ""),
            }
        )

step_results.sort(key=lambda step: (step.get("step_order", 10**9), step.get("step_name", "")))

child_task_ids = [task.get("task_id", "") for task in children]
children_done = sum(1 for child in children if child.get("status") == "done")
children_failed = sum(1 for child in children if child.get("status") in {"failed", "cancelled"})
warning_child_ids = [child.get("task_id", "") for child in children if has_warning(child)]
children_with_warnings = len(warning_child_ids)
failed_child_ids = [child.get("task_id", "") for child in children if child.get("status") in {"failed", "cancelled"}]

aggregated_artifacts = []
for child in children:
    for artifact in child.get("artifacts", []):
        path = artifact.get("path", "")
        if path and path not in aggregated_artifacts:
            aggregated_artifacts.append(path)

step_count = len(step_results)
steps_completed = sum(1 for step in step_results if step.get("status") == "done")
steps_failed = sum(1 for step in step_results if step.get("status") == "failed")
steps_pending = sum(1 for step in step_results if step.get("status") not in {"done", "failed"})
critical_step_count = sum(1 for step in step_results if step.get("critical"))
critical_steps_failed = sum(1 for step in step_results if step.get("critical") and step.get("status") == "failed")
critical_steps_pending = sum(1 for step in step_results if step.get("critical") and step.get("status") != "done")
noncritical_steps_failed = sum(1 for step in step_results if not step.get("critical") and step.get("status") == "failed")
noncritical_steps_pending = sum(1 for step in step_results if not step.get("critical") and step.get("status") not in {"done", "failed"})
local_step_count = sum(1 for step in step_results if step.get("execution_mode") == "local")
worker_step_count = sum(1 for step in step_results if step.get("execution_mode") == "worker")
worker_child_ids = [step.get("child_task_id", "") for step in step_results if step.get("execution_mode") == "worker" and step.get("child_task_id")]
local_child_ids = [step.get("child_task_id", "") for step in step_results if step.get("execution_mode") != "worker" and step.get("child_task_id")]

if critical_steps_failed > 0 or critical_steps_pending > 0:
    chain_status = "failed"
    final_task_status = "failed"
elif noncritical_steps_failed > 0 or noncritical_steps_pending > 0 or children_with_warnings > 0:
    chain_status = "completed_with_warnings"
    final_task_status = "done"
else:
    chain_status = "completed"
    final_task_status = "done"

if chain_status == "failed":
    headline = (
        f"Chain failed: {steps_completed}/{step_count} step(s) completed and one or more critical steps did not finish cleanly."
    )
elif chain_status == "completed_with_warnings":
    headline = (
        f"Chain completed with warnings: {steps_completed}/{step_count} step(s) completed, "
        f"{steps_failed} failed, {children_with_warnings} warning signal(s)."
    )
else:
    headline = (
        f"Chain completed cleanly: {steps_completed}/{step_count} step(s) done "
        f"across {local_step_count} local and {worker_step_count} worker step(s)."
    )

generated_at = iso_now()
artifact_rel = "outbox/manual/{ts}-{slug}-chain-final.md".format(
    ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
    slug=slugify(chain_type),
)

summary = {
    "root_task_id": root_task_id,
    "chain_type": chain_type,
    "generated_at": generated_at,
    "artifact_rel": artifact_rel,
    "child_task_ids": child_task_ids,
    "child_count": len(children),
    "children_done": children_done,
    "children_failed": children_failed,
    "children_with_warnings": children_with_warnings,
    "failed_child_ids": failed_child_ids,
    "warning_child_ids": warning_child_ids,
    "artifact_paths": aggregated_artifacts,
    "step_results": step_results,
    "step_count": step_count,
    "steps_completed": steps_completed,
    "steps_failed": steps_failed,
    "steps_pending": steps_pending,
    "critical_step_count": critical_step_count,
    "critical_steps_failed": critical_steps_failed,
    "critical_steps_pending": critical_steps_pending,
    "noncritical_steps_failed": noncritical_steps_failed,
    "noncritical_steps_pending": noncritical_steps_pending,
    "local_step_count": local_step_count,
    "worker_step_count": worker_step_count,
    "worker_child_ids": worker_child_ids,
    "local_child_ids": local_child_ids,
    "headline": headline,
    "chain_status": chain_status,
    "final_task_status": final_task_status,
}

print(json.dumps(summary))
PY
)"

artifact_rel="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(summary["artifact_rel"])
PY
)"

artifact_abs="$REPO_ROOT/$artifact_rel"
tmp_artifact="$(mktemp "$OUTBOX_DIR/.chain-final.XXXXXX.md")"
trap 'rm -f "$tmp_artifact"' EXIT

python3 - "$root_task_path" "$summary_json" >"$tmp_artifact" <<'PY'
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    root_task = json.load(fh)

print(f"# Chain Summary: {summary['chain_type']}")
print()
print(f"generated_at: {summary['generated_at']}")
print(f"repo: {root_task_path.parent.parent.as_posix()}")
print("task_type: task-chain")
print(f"root_task_id: {summary['root_task_id']}")
print(f"chain_type: {summary['chain_type']}")
print()
print("## Summary")
print(f"- final_task_status: {summary['final_task_status']}")
print(f"- chain_status: {summary['chain_status']}")
print(f"- headline: {summary['headline']}")
print(f"- child_count: {summary['child_count']}")
print(f"- step_count: {summary['step_count']}")
print(f"- steps_completed: {summary['steps_completed']}")
print(f"- steps_failed: {summary['steps_failed']}")
print(f"- steps_pending: {summary['steps_pending']}")
print(f"- local_step_count: {summary['local_step_count']}")
print(f"- worker_step_count: {summary['worker_step_count']}")
print()
print("## Chain Plan")
if not summary["step_results"]:
    print("- (none)")
else:
    for step in summary["step_results"]:
        critical = "yes" if step.get("critical") else "no"
        child_task_id = step.get("child_task_id") or "(none)"
        print(
            f"- [{step.get('step_order')}] {step.get('step_name')} | "
            f"mode={step.get('execution_mode') or '(none)'} | "
            f"critical={critical} | status={step.get('status')} | "
            f"task_type={step.get('task_type') or '(none)'} | child_task_id={child_task_id}"
        )
        if step.get("summary"):
            print(f"  summary: {step.get('summary')}")
        if step.get("artifact_paths"):
            print(f"  artifacts: {', '.join(step.get('artifact_paths'))}")
print()
print("## Worker Evidence")
worker_steps = [step for step in summary["step_results"] if step.get("execution_mode") == "worker"]
if not worker_steps:
    print("- (none)")
else:
    for step in worker_steps:
        print(
            f"- {step.get('step_name')} | child_task_id={step.get('child_task_id') or '(none)'} | "
            f"worker_state={step.get('worker_state') or '(none)'} | "
            f"worker_result_status={step.get('worker_result_status') or '(none)'}"
        )
        if step.get("worker_result_artifact_path"):
            print(f"  worker_result_artifact_path: {step.get('worker_result_artifact_path')}")
print()
print("## Result")
print(f"- {summary['headline']}")
if summary["chain_status"] == "failed":
    print("- Final status was forced to failed because at least one critical step was incomplete or failed.")
elif summary["chain_status"] == "completed_with_warnings":
    print("- Final status stayed done, but warning-level evidence or non-critical failures were recorded.")
else:
    print("- All planned steps completed cleanly.")
print()
print("## Aggregated Artifacts")
if not summary["artifact_paths"]:
    print("- (none)")
else:
    for path in summary["artifact_paths"]:
        print(f"- {path}")
print()
print("## Notes")
if summary["failed_child_ids"]:
    print(f"- failed_child_ids: {', '.join(summary['failed_child_ids'])}")
if summary["warning_child_ids"]:
    print(f"- warning_child_ids: {', '.join(summary['warning_child_ids'])}")
if summary["worker_child_ids"]:
    print(f"- worker_child_ids: {', '.join(summary['worker_child_ids'])}")
if not summary["failed_child_ids"] and not summary["warning_child_ids"] and not summary["worker_child_ids"]:
    print("- no extra failure, warning, or worker notes")
PY

"$VALIDATE_MARKDOWN" "$tmp_artifact" >/dev/null
mv "$tmp_artifact" "$artifact_abs"
trap - EXIT
chmod 664 "$artifact_abs"

tmp_task="$(mktemp "$TASKS_DIR/.task-chain-finalize.XXXXXX.tmp")"
trap 'rm -f "$tmp_task"' EXIT
python3 - "$root_task_path" "$summary_json" <<'PY' >"$tmp_task"
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])

with root_task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["chain_status"] = summary["chain_status"]
task["chain_summary"] = {
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_pending": summary["steps_pending"],
    "critical_step_count": summary["critical_step_count"],
    "critical_steps_failed": summary["critical_steps_failed"],
    "local_step_count": summary["local_step_count"],
    "worker_step_count": summary["worker_step_count"],
    "worker_child_ids": summary["worker_child_ids"],
    "headline": summary["headline"],
    "final_artifact_path": summary["artifact_rel"],
}

chain_plan = task.get("chain_plan") if isinstance(task.get("chain_plan"), dict) else {}
chain_plan["step_count"] = summary["step_count"]
chain_plan["steps"] = summary["step_results"]
chain_plan["last_finalized_at"] = summary["generated_at"]
task["chain_plan"] = chain_plan

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$root_task_path"
trap - EXIT

summary_content="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(
    "chain_status={chain_status} step_count={step_count} steps_completed={steps_completed} "
    "steps_failed={steps_failed} steps_pending={steps_pending} headline={headline}".format(
        chain_status=summary["chain_status"],
        step_count=summary["step_count"],
        steps_completed=summary["steps_completed"],
        steps_failed=summary["steps_failed"],
        steps_pending=summary["steps_pending"],
        headline=summary["headline"],
    )
)
PY
)"

summary_extra_json="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
extra = {
    "chain_type": summary["chain_type"],
    "chain_status": summary["chain_status"],
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_pending": summary["steps_pending"],
    "headline": summary["headline"],
    "final_artifact_path": summary["artifact_rel"],
}
print(json.dumps(extra))
PY
)"

TASK_OUTPUT_EXTRA_JSON="$summary_extra_json" ./scripts/task_add_output.sh "$task_id" "chain-summary" 0 "$summary_content"
./scripts/task_add_artifact.sh "$task_id" "chain-final" "$artifact_rel"

close_status="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(summary["final_task_status"])
PY
)"

close_note="$(
  python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(summary["headline"])
PY
)"

./scripts/task_close.sh "$task_id" "$close_status" "$close_note"
printf 'TASK_CHAIN_FINALIZED %s %s\n' "$task_id" "$artifact_rel"
