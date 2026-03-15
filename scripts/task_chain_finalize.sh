#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"
COLLECT_RESULTS="$REPO_ROOT/scripts/task_chain_collect_results.sh"

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

summary_json="$("$COLLECT_RESULTS" "$task_id")"

artifact_rel="$(
  python3 - "$summary_json" <<'PY'
import datetime
import json
import sys

summary = json.loads(sys.argv[1])
print(
    "outbox/manual/{ts}-{slug}-chain-final.md".format(
        ts=datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        slug=summary["artifact_slug"],
    )
)
PY
)"

artifact_abs="$REPO_ROOT/$artifact_rel"
tmp_artifact="$(mktemp "$OUTBOX_DIR/.chain-final.XXXXXX.md")"
trap 'rm -f "$tmp_artifact"' EXIT

python3 - "$root_task_path" "$summary_json" "$artifact_rel" >"$tmp_artifact" <<'PY'
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])
artifact_rel = sys.argv[3]

with root_task_path.open(encoding="utf-8") as fh:
    root_task = json.load(fh)

print(f"# Chain Summary: {summary['chain_type']}")
print()
print(f"generated_at: {summary['generated_at']}")
print(f"repo: {root_task_path.parent.parent.as_posix()}")
print("task_type: task-chain")
print(f"root_task_id: {summary['root_task_id']}")
print(f"chain_type: {summary['chain_type']}")
print(f"final_artifact_path: {artifact_rel}")
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
print(f"- local_steps_count: {summary['local_steps_count']}")
print(f"- delegated_steps_count: {summary['delegated_steps_count']}")
print(f"- worker_steps_done: {summary['worker_steps_done']}")
print(f"- worker_steps_failed: {summary['worker_steps_failed']}")
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
print("## Worker Outcomes")
if not summary["worker_outcomes"]:
    print("- (none)")
else:
    for outcome in summary["worker_outcomes"]:
        print(
            f"- [{outcome.get('step_order')}] {outcome.get('step_name')} | "
            f"child_task_id={outcome.get('child_task_id') or '(none)'} | "
            f"status={outcome.get('status') or '(none)'} | "
            f"worker_state={outcome.get('worker_state') or '(none)'} | "
            f"worker_result_status={outcome.get('worker_result_status') or '(none)'}"
        )
        if outcome.get("summary"):
            print(f"  summary: {outcome.get('summary')}")
        if outcome.get("result_artifact_path"):
            print(f"  result_artifact_path: {outcome.get('result_artifact_path')}")
        if outcome.get("result_source_files"):
            print(f"  result_source_files: {', '.join(outcome.get('result_source_files'))}")
        if outcome.get("artifact_paths"):
            print(f"  artifact_paths: {', '.join(outcome.get('artifact_paths'))}")
print()
print("## Result")
print(f"- {summary['headline']}")
if summary["chain_status"] == "failed":
    print("- Final status was forced to failed because at least one critical step was incomplete or failed.")
elif summary["chain_status"] == "completed_with_warnings":
    print("- Final status stayed done, but warning-level evidence or non-critical failures were recorded.")
else:
    print("- All planned steps completed cleanly.")
if summary["worker_result_summaries"]:
    print("- Worker result summaries were incorporated automatically into the root aggregation.")
print()
print("## Aggregated Artifacts")
if not summary["aggregated_artifact_paths"]:
    print("- (none)")
else:
    for path in summary["aggregated_artifact_paths"]:
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
python3 - "$root_task_path" "$summary_json" "$artifact_rel" <<'PY' >"$tmp_task"
import json
import pathlib
import sys

root_task_path = pathlib.Path(sys.argv[1])
summary = json.loads(sys.argv[2])
artifact_rel = sys.argv[3]

with root_task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["chain_status"] = summary["chain_status"]
task["chain_summary"] = {
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "failed_child_ids": summary["failed_child_ids"],
    "warning_child_ids": summary["warning_child_ids"],
    "artifact_paths": summary["artifact_paths"],
    "aggregated_artifact_paths": summary["aggregated_artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_pending": summary["steps_pending"],
    "critical_step_count": summary["critical_step_count"],
    "critical_steps_failed": summary["critical_steps_failed"],
    "critical_steps_pending": summary["critical_steps_pending"],
    "local_step_count": summary["local_step_count"],
    "worker_step_count": summary["worker_step_count"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_failed": summary["worker_steps_failed"],
    "worker_child_ids": summary["worker_child_ids"],
    "worker_result_summaries": summary["worker_result_summaries"],
    "worker_outcomes": summary["worker_outcomes"],
    "headline": summary["headline"],
    "final_artifact_path": artifact_rel,
    "last_collected_at": summary["generated_at"],
}

chain_plan = task.get("chain_plan") if isinstance(task.get("chain_plan"), dict) else {}
chain_plan["step_count"] = summary["step_count"]
chain_plan["local_step_count"] = summary["local_step_count"]
chain_plan["worker_step_count"] = summary["worker_step_count"]
chain_plan["steps"] = summary["step_results"]
chain_plan["last_finalized_at"] = summary["generated_at"]
task["chain_plan"] = chain_plan

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$root_task_path"
trap - EXIT

summary_content="$(
  python3 - "$summary_json" "$artifact_rel" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
artifact_rel = sys.argv[2]
print(
    "chain_status={chain_status} step_count={step_count} steps_completed={steps_completed} "
    "steps_failed={steps_failed} worker_steps_done={worker_steps_done} "
    "worker_steps_failed={worker_steps_failed} headline={headline} final_artifact_path={artifact_rel}".format(
        chain_status=summary["chain_status"],
        step_count=summary["step_count"],
        steps_completed=summary["steps_completed"],
        steps_failed=summary["steps_failed"],
        worker_steps_done=summary["worker_steps_done"],
        worker_steps_failed=summary["worker_steps_failed"],
        headline=summary["headline"],
        artifact_rel=artifact_rel,
    )
)
PY
)"

summary_extra_json="$(
  python3 - "$summary_json" "$artifact_rel" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
artifact_rel = sys.argv[2]
extra = {
    "chain_type": summary["chain_type"],
    "chain_status": summary["chain_status"],
    "child_task_ids": summary["child_task_ids"],
    "child_count": summary["child_count"],
    "children_done": summary["children_done"],
    "children_failed": summary["children_failed"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
    "aggregated_artifact_paths": summary["aggregated_artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_pending": summary["steps_pending"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_failed": summary["worker_steps_failed"],
    "worker_result_summaries": summary["worker_result_summaries"],
    "worker_outcomes": summary["worker_outcomes"],
    "headline": summary["headline"],
    "final_artifact_path": artifact_rel,
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
