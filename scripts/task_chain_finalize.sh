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
print(f"- children_done: {summary['children_done']}")
print(f"- children_failed: {summary['children_failed']}")
print(f"- children_blocked: {summary['children_blocked']}")
print(f"- children_delegated: {summary['children_delegated']}")
print(f"- children_running: {summary['children_running']}")
print(f"- step_count: {summary['step_count']}")
print(f"- steps_completed: {summary['steps_completed']}")
print(f"- steps_failed: {summary['steps_failed']}")
print(f"- steps_blocked: {summary['steps_blocked']}")
print(f"- steps_delegated: {summary['steps_delegated']}")
print(f"- steps_running: {summary['steps_running']}")
print(f"- steps_skipped: {summary['steps_skipped']}")
print(f"- steps_pending: {summary['steps_pending']}")
print(f"- local_steps_count: {summary['local_steps_count']}")
print(f"- delegated_steps_count: {summary['delegated_steps_count']}")
print(f"- worker_steps_done: {summary['worker_steps_done']}")
print(f"- worker_steps_blocked: {summary['worker_steps_blocked']}")
print(f"- worker_steps_failed: {summary['worker_steps_failed']}")
print(f"- worker_steps_delegated: {summary['worker_steps_delegated']}")
print(f"- worker_steps_running: {summary['worker_steps_running']}")
print(f"- awaiting_worker_result_steps: {summary['awaiting_worker_result_steps']}")
print(f"- resolved_worker_result_steps: {summary['resolved_worker_result_steps']}")
if summary.get("decision_source_step"):
    print(f"- decision_source_step: {summary.get('decision_source_step')}")
if summary.get("decision_source_worker_result_status"):
    print(f"- decision_source_worker_result_status: {summary.get('decision_source_worker_result_status')}")
if summary.get("next_step_selected"):
    print(f"- next_step_selected: {summary.get('next_step_selected')}")
if summary.get("skipped_steps"):
    print(f"- skipped_steps: {', '.join(summary.get('skipped_steps'))}")
if summary.get("decision_reason"):
    print(f"- decision_reason: {summary.get('decision_reason')}")
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
        if step.get("decision_reason"):
            print(f"  decision_reason: {step.get('decision_reason')}")
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
print("## Conditional Outcomes")
if not summary["conditional_outcomes"]:
    print("- (none)")
else:
    for outcome in summary["conditional_outcomes"]:
        print(
            f"- [{outcome.get('step_order')}] {outcome.get('step_name')} | "
            f"selected={'yes' if outcome.get('selected') else 'no'} | "
            f"status={outcome.get('status') or '(none)'} | "
            f"condition_source_step={outcome.get('condition_source_step') or '(none)'} | "
            f"expected_worker_result_status={outcome.get('expected_worker_result_status') or '(none)'}"
        )
        if outcome.get("decision_reason"):
            print(f"  decision_reason: {outcome.get('decision_reason')}")
        if outcome.get("summary"):
            print(f"  summary: {outcome.get('summary')}")
print()
print("## Result")
print(f"- {summary['headline']}")
if summary["chain_status"] == "failed":
    print("- Final status was forced to failed because at least one critical step was incomplete or failed.")
elif summary["chain_status"] == "completed_with_warnings":
    print("- Final status stayed done, but warning-level evidence or non-critical failures were recorded.")
elif summary["chain_status"] == "blocked":
    print("- Final status was blocked because one or more critical steps hit an external or operational blocker.")
elif summary["chain_status"] == "awaiting_worker_result":
    print("- Final status was delegated because a worker step is still awaiting a manual-controlled result.")
else:
    print("- All planned steps completed cleanly.")
if summary["worker_result_summaries"]:
    print("- Worker result summaries were incorporated automatically into the root aggregation.")
if summary.get("awaiting_worker_child_ids"):
    print(f"- Awaiting worker children: {', '.join(summary['awaiting_worker_child_ids'])}")
if summary.get("resolved_worker_child_ids"):
    print(f"- Resolved worker children: {', '.join(summary['resolved_worker_child_ids'])}")
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
if summary["blocked_child_ids"]:
    print(f"- blocked_child_ids: {', '.join(summary['blocked_child_ids'])}")
if summary["warning_child_ids"]:
    print(f"- warning_child_ids: {', '.join(summary['warning_child_ids'])}")
if summary["worker_child_ids"]:
    print(f"- worker_child_ids: {', '.join(summary['worker_child_ids'])}")
if summary.get("awaiting_worker_child_ids"):
    print(f"- awaiting_worker_child_ids: {', '.join(summary['awaiting_worker_child_ids'])}")
if summary.get("resolved_worker_child_ids"):
    print(f"- resolved_worker_child_ids: {', '.join(summary['resolved_worker_child_ids'])}")
if not summary["failed_child_ids"] and not summary["blocked_child_ids"] and not summary["warning_child_ids"] and not summary["worker_child_ids"]:
    print("- no extra failure, blocked, warning, or worker notes")
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
    "children_blocked": summary["children_blocked"],
    "children_delegated": summary["children_delegated"],
    "children_running": summary["children_running"],
    "children_with_warnings": summary["children_with_warnings"],
    "failed_child_ids": summary["failed_child_ids"],
    "blocked_child_ids": summary["blocked_child_ids"],
    "warning_child_ids": summary["warning_child_ids"],
    "artifact_paths": summary["artifact_paths"],
    "aggregated_artifact_paths": summary["aggregated_artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_blocked": summary["steps_blocked"],
    "steps_delegated": summary["steps_delegated"],
    "steps_running": summary["steps_running"],
    "steps_skipped": summary["steps_skipped"],
    "steps_pending": summary["steps_pending"],
    "critical_step_count": summary["critical_step_count"],
    "critical_steps_failed": summary["critical_steps_failed"],
    "critical_steps_blocked": summary["critical_steps_blocked"],
    "critical_steps_skipped": summary["critical_steps_skipped"],
    "critical_steps_pending": summary["critical_steps_pending"],
    "local_step_count": summary["local_step_count"],
    "worker_step_count": summary["worker_step_count"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_blocked": summary["worker_steps_blocked"],
    "worker_steps_failed": summary["worker_steps_failed"],
    "worker_steps_delegated": summary["worker_steps_delegated"],
    "worker_steps_running": summary["worker_steps_running"],
    "worker_child_ids": summary["worker_child_ids"],
    "awaiting_worker_child_ids": summary["awaiting_worker_child_ids"],
    "awaiting_worker_step_names": summary["awaiting_worker_step_names"],
    "awaiting_worker_result_steps": summary["awaiting_worker_result_steps"],
    "resolved_worker_child_ids": summary["resolved_worker_child_ids"],
    "resolved_worker_step_names": summary["resolved_worker_step_names"],
    "resolved_worker_result_steps": summary["resolved_worker_result_steps"],
    "worker_result_summaries": summary["worker_result_summaries"],
    "worker_outcomes": summary["worker_outcomes"],
    "decision_reason": summary["decision_reason"],
    "decision_source_step": summary["decision_source_step"],
    "decision_source_worker_result_status": summary["decision_source_worker_result_status"],
    "next_step_selected": summary["next_step_selected"],
    "skipped_steps": summary["skipped_steps"],
    "conditional_outcomes": summary["conditional_outcomes"],
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
    "steps_failed={steps_failed} steps_blocked={steps_blocked} steps_delegated={steps_delegated} "
    "steps_running={steps_running} steps_skipped={steps_skipped} "
    "worker_steps_done={worker_steps_done} worker_steps_blocked={worker_steps_blocked} "
    "worker_steps_delegated={worker_steps_delegated} worker_steps_running={worker_steps_running} "
    "worker_steps_failed={worker_steps_failed} awaiting_worker_result_steps={awaiting_worker_result_steps} "
    "resolved_worker_result_steps={resolved_worker_result_steps} next_step_selected={next_step_selected} "
    "headline={headline} final_artifact_path={artifact_rel}".format(
        chain_status=summary["chain_status"],
        step_count=summary["step_count"],
        steps_completed=summary["steps_completed"],
        steps_failed=summary["steps_failed"],
        steps_blocked=summary["steps_blocked"],
        steps_delegated=summary["steps_delegated"],
        steps_running=summary["steps_running"],
        steps_skipped=summary["steps_skipped"],
        worker_steps_done=summary["worker_steps_done"],
        worker_steps_blocked=summary["worker_steps_blocked"],
        worker_steps_delegated=summary["worker_steps_delegated"],
        worker_steps_running=summary["worker_steps_running"],
        worker_steps_failed=summary["worker_steps_failed"],
        awaiting_worker_result_steps=summary["awaiting_worker_result_steps"],
        resolved_worker_result_steps=summary["resolved_worker_result_steps"],
        next_step_selected=summary["next_step_selected"] or "(none)",
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
    "children_blocked": summary["children_blocked"],
    "children_delegated": summary["children_delegated"],
    "children_running": summary["children_running"],
    "children_with_warnings": summary["children_with_warnings"],
    "artifact_paths": summary["artifact_paths"],
    "aggregated_artifact_paths": summary["aggregated_artifact_paths"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_blocked": summary["steps_blocked"],
    "steps_delegated": summary["steps_delegated"],
    "steps_running": summary["steps_running"],
    "steps_skipped": summary["steps_skipped"],
    "steps_pending": summary["steps_pending"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_blocked": summary["worker_steps_blocked"],
    "worker_steps_failed": summary["worker_steps_failed"],
    "worker_steps_delegated": summary["worker_steps_delegated"],
    "worker_steps_running": summary["worker_steps_running"],
    "awaiting_worker_child_ids": summary["awaiting_worker_child_ids"],
    "awaiting_worker_step_names": summary["awaiting_worker_step_names"],
    "awaiting_worker_result_steps": summary["awaiting_worker_result_steps"],
    "resolved_worker_child_ids": summary["resolved_worker_child_ids"],
    "resolved_worker_step_names": summary["resolved_worker_step_names"],
    "resolved_worker_result_steps": summary["resolved_worker_result_steps"],
    "worker_result_summaries": summary["worker_result_summaries"],
    "worker_outcomes": summary["worker_outcomes"],
    "decision_reason": summary["decision_reason"],
    "decision_source_step": summary["decision_source_step"],
    "decision_source_worker_result_status": summary["decision_source_worker_result_status"],
    "next_step_selected": summary["next_step_selected"],
    "skipped_steps": summary["skipped_steps"],
    "conditional_outcomes": summary["conditional_outcomes"],
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
