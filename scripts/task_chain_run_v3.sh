#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
COLLECT_RESULTS="$REPO_ROOT/scripts/task_chain_collect_results.sh"
DECIDE_NEXT="$REPO_ROOT/scripts/task_chain_decide_next.sh"

root_task_id=""
root_task_path=""
chain_type=""
chain_title=""
finalized="0"
force_worker_result=""

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_run_v3.sh repo-analysis-worker-conditional "<title>" [--force-worker-result failed]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

extract_task_path() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^(TASK_CREATED|TASK_CHILD_CREATED) / {print $2}' | tail -n 1
}

extract_task_id() {
  local output="$1"
  local task_path
  task_path="$(extract_task_path "$output")"
  if [ -z "$task_path" ]; then
    return 1
  fi
  basename "$task_path" .json
}

set_root_chain_status() {
  local new_status="$1"
  local tmp_path
  tmp_path="$(mktemp "$TASKS_DIR/.task-chain-root.XXXXXX.tmp")"
  python3 - "$root_task_path" "$new_status" <<'PY' >"$tmp_path"
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
new_status = sys.argv[2]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["chain_status"] = new_status
task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
  mv "$tmp_path" "$root_task_path"
}

update_chain_step() {
  local step_name="$1"
  local new_status="$2"
  local child_task_id="${3:-}"
  local summary="${4:-}"
  local exit_code="${5:-}"
  local tmp_path
  tmp_path="$(mktemp "$TASKS_DIR/.task-chain-step.XXXXXX.tmp")"
  python3 - "$root_task_path" "$step_name" "$new_status" "$child_task_id" "$summary" "$exit_code" <<'PY' >"$tmp_path"
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
step_name, new_status, child_task_id, summary, exit_code_raw = sys.argv[2:7]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

chain_plan = task.get("chain_plan")
if not isinstance(chain_plan, dict):
    print("ERROR: la tarea raiz no tiene chain_plan", file=sys.stderr)
    raise SystemExit(1)

steps = chain_plan.get("steps")
if not isinstance(steps, list):
    print("ERROR: chain_plan.steps no es una lista", file=sys.stderr)
    raise SystemExit(1)

for step in steps:
    if step.get("step_name") != step_name:
        continue
    step["status"] = new_status
    if child_task_id:
        step["child_task_id"] = child_task_id
    if summary:
        step["summary"] = summary
    if exit_code_raw:
        step["last_exit_code"] = int(exit_code_raw)
    if new_status == "running":
        step.setdefault("started_at", now)
    if new_status in {"done", "failed", "skipped"}:
        step["finished_at"] = now
    break
else:
    print(f"ERROR: step no encontrado: {step_name}", file=sys.stderr)
    raise SystemExit(1)

task["updated_at"] = now
json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
  mv "$tmp_path" "$root_task_path"
}

task_compact_summary() {
  local task_id="$1"
  python3 - "$TASKS_DIR/${task_id}.json" <<'PY'
import json
import pathlib
import sys


def compact(value: str, limit: int = 240) -> str:
    text = " ".join(str(value).split())
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.get("worker_run") or {}
if worker_run.get("extracted_summary"):
    print(compact(worker_run["extracted_summary"]))
    raise SystemExit(0)

for output in reversed(task.get("outputs", [])):
    if output.get("summary"):
        print(compact(output["summary"]))
        raise SystemExit(0)
    if output.get("content"):
        print(compact(output["content"]))
        raise SystemExit(0)

notes = task.get("notes") or []
if notes:
    print(compact(notes[-1]))
PY
}

enrich_task_metadata() {
  local task_id="$1"
  local objective="${2:-}"
  local step_name="${3:-}"
  local step_order="${4:-}"
  local critical="${5:-}"
  local execution_mode="${6:-}"
  local tmp_path
  tmp_path="$(mktemp "$TASKS_DIR/.task-enrich.XXXXXX.tmp")"
  python3 - "$TASKS_DIR/${task_id}.json" "$objective" "$step_name" "$step_order" "$critical" "$execution_mode" <<'PY' >"$tmp_path"
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
objective, step_name, step_order_raw, critical_raw, execution_mode = sys.argv[2:7]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

if objective:
    task["objective"] = objective
if step_name:
    task["step_name"] = step_name
if step_order_raw:
    task["step_order"] = int(step_order_raw)
if critical_raw:
    task["critical"] = critical_raw.lower() in {"1", "true", "yes", "y", "on"}
if execution_mode:
    task["execution_mode"] = execution_mode

task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
  mv "$tmp_path" "$TASKS_DIR/${task_id}.json"
}

add_chain_output() {
  local kind="$1"
  local exit_code="$2"
  local content="$3"
  local extra_json="${4:-}"
  if [ -n "$extra_json" ]; then
    TASK_OUTPUT_EXTRA_JSON="$extra_json" ./scripts/task_add_output.sh "$root_task_id" "$kind" "$exit_code" "$content" >/dev/null
  else
    TASK_OUTPUT_EXTRA_JSON="$(
      python3 - "$chain_type" <<'PY'
import json
import sys

print(json.dumps({"chain_type": sys.argv[1]}))
PY
    )" ./scripts/task_add_output.sh "$root_task_id" "$kind" "$exit_code" "$content" >/dev/null
  fi
}

record_chain_collection() {
  local summary_json
  local content
  local extra_json

  summary_json="$("$COLLECT_RESULTS" "$root_task_id")"
  content="$(
    python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(
    "chain_status={chain_status} steps_completed={steps_completed}/{step_count} "
    "steps_skipped={steps_skipped} worker_steps_done={worker_steps_done} "
    "worker_steps_failed={worker_steps_failed} next_step_selected={next_step_selected}".format(
        chain_status=summary["chain_status"],
        steps_completed=summary["steps_completed"],
        step_count=summary["step_count"],
        steps_skipped=summary["steps_skipped"],
        worker_steps_done=summary["worker_steps_done"],
        worker_steps_failed=summary["worker_steps_failed"],
        next_step_selected=summary["next_step_selected"] or "(none)",
    )
)
PY
  )"
  extra_json="$(
    python3 - "$summary_json" <<'PY'
import json
import sys

summary = json.loads(sys.argv[1])
print(json.dumps({
    "chain_type": summary["chain_type"],
    "chain_status": summary["chain_status"],
    "step_count": summary["step_count"],
    "steps_completed": summary["steps_completed"],
    "steps_failed": summary["steps_failed"],
    "steps_skipped": summary["steps_skipped"],
    "steps_pending": summary["steps_pending"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_failed": summary["worker_steps_failed"],
    "decision_reason": summary["decision_reason"],
    "decision_source_step": summary["decision_source_step"],
    "decision_source_worker_result_status": summary["decision_source_worker_result_status"],
    "next_step_selected": summary["next_step_selected"],
    "skipped_steps": summary["skipped_steps"],
    "conditional_outcomes": summary["conditional_outcomes"],
    "worker_result_summaries": summary["worker_result_summaries"],
    "aggregated_artifact_paths": summary["aggregated_artifact_paths"],
}))
PY
  )"
  TASK_OUTPUT_EXTRA_JSON="$extra_json" ./scripts/task_add_output.sh "$root_task_id" "chain-results-collected" 0 "$content" >/dev/null
}

close_root() {
  record_chain_collection
  ./scripts/task_chain_finalize.sh "$root_task_id" >/dev/null
  finalized="1"
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$root_task_path" ] && [ -f "$root_task_path" ]; then
    ./scripts/task_chain_finalize.sh "$root_task_id" >/dev/null 2>&1 || \
      ./scripts/task_close.sh "$root_task_id" failed "task_chain_run_v3 aborted before completion" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

create_root_chain() {
  local created_output
  local root_task_rel
  local tmp_path

  created_output="$(./scripts/task_new.sh task-chain "$chain_title")"
  printf '%s\n' "$created_output"

  root_task_rel="$(extract_task_path "$created_output")"
  [ -n "$root_task_rel" ] || fatal "no se pudo extraer la ruta de la tarea raiz"
  root_task_path="$REPO_ROOT/$root_task_rel"
  root_task_id="$(basename "$root_task_path" .json)"

  tmp_path="$(mktemp "$TASKS_DIR/.task-chain-plan-v3.XXXXXX.tmp")"
  python3 - "$root_task_path" "$chain_type" "$chain_title" <<'PY' >"$tmp_path"
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
chain_type = sys.argv[2]
chain_title = sys.argv[3]
planned_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["objective"] = (
    "Execute a mixed local-worker chain with one conditional follow-up step and "
    f"produce an aggregated final artifact for {chain_type}."
)
steps = [
    {
        "step_name": "local-self-check",
        "step_order": 1,
        "task_type": "self-check",
        "execution_mode": "local",
        "critical": True,
        "title": f"{chain_title} / local self check",
        "objective": "Validate the local Golem environment before delegation.",
        "depends_on_step_names": [],
        "status": "planned",
        "child_task_id": "",
    },
    {
        "step_name": "delegated-repo-analysis",
        "step_order": 2,
        "task_type": "repo-analysis",
        "execution_mode": "worker",
        "critical": True,
        "title": f"{chain_title} / delegated repo analysis",
        "objective": (
            "Analyze the repository and explain the mixed local-worker orchestration flow, "
            "covering conditional decisions, aggregated summary quality, and final artifact integrity."
        ),
        "depends_on_step_names": ["local-self-check"],
        "status": "planned",
        "child_task_id": "",
    },
    {
        "step_name": "conditional-decision",
        "step_order": 3,
        "task_type": "chain-decision",
        "execution_mode": "local",
        "critical": True,
        "title": f"{chain_title} / conditional decision",
        "objective": "Select the next local step according to the delegated worker outcome.",
        "depends_on_step_names": ["delegated-repo-analysis"],
        "status": "planned",
        "child_task_id": "",
    },
    {
        "step_name": "local-review-worker-outcome",
        "step_order": 4,
        "task_type": "compare-files",
        "execution_mode": "local",
        "critical": False,
        "title": f"{chain_title} / local worker outcome review",
        "objective": "Produce one local review artifact only when the worker result closed successfully.",
        "depends_on_step_names": ["conditional-decision"],
        "condition_source_step": "delegated-repo-analysis",
        "run_if_worker_result_status": "done",
        "status": "planned",
        "child_task_id": "",
    },
]

task["chain_type"] = chain_type
task["chain_status"] = "planned"
task["chain_plan"] = {
    "version": "3.0",
    "planned_at": planned_at,
    "mixes_execution_modes": True,
    "supports_conditional_steps": True,
    "local_step_count": 3,
    "worker_step_count": 1,
    "critical_step_count": 3,
    "conditional_step_count": 1,
    "step_count": len(steps),
    "steps": steps,
}
task.setdefault("notes", []).append(f"chain plan v3 created at {planned_at}")
task["updated_at"] = planned_at

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
  mv "$tmp_path" "$root_task_path"

  TASK_OUTPUT_EXTRA_JSON="$(
    python3 - "$chain_type" <<'PY'
import json
import sys

print(json.dumps({
    "chain_type": sys.argv[1],
    "plan_version": "3.0",
    "step_count": 4,
    "local_step_count": 3,
    "worker_step_count": 1,
    "critical_step_count": 3,
    "conditional_step_count": 1,
}))
PY
  )" ./scripts/task_add_output.sh "$root_task_id" "chain-plan" 0 "planned 4-step conditional mixed local-worker chain" >/dev/null

  printf 'TASK_CHAIN_PLANNED %s\n' "$root_task_id"
}

trap on_exit EXIT

chain_type="${1:-}"
chain_title="${2:-}"
shift 2 || true

if [ -z "$chain_type" ] || [ -z "$chain_title" ]; then
  usage
  fatal "faltan chain_type o title"
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force-worker-result)
      force_worker_result="${2:-}"
      [ -n "$force_worker_result" ] || fatal "falta valor para --force-worker-result"
      shift 2
      ;;
    *)
      usage
      fatal "argumento no soportado: $1"
      ;;
  esac
done

case "$chain_type" in
  repo-analysis-worker-conditional) ;;
  *)
    usage
    fatal "chain_type no soportado: $chain_type"
    ;;
esac

case "$force_worker_result" in
  ""|failed) ;;
  *)
    fatal "solo se soporta --force-worker-result failed en esta version"
    ;;
esac

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR"

create_root_chain

./scripts/task_update.sh "$root_task_id" running >/dev/null
set_root_chain_status running
add_chain_output "chain-start" 0 "chain v3 started for ${chain_type}"

self_check_task_id=""
worker_task_id=""
review_task_id=""

update_chain_step "local-self-check" running "" "local self-check started"
set +e
self_check_output="$(
  TASK_PARENT_TASK_ID="$root_task_id" \
  TASK_DEPENDS_ON="[\"$root_task_id\"]" \
  TASK_OBJECTIVE="Validate the local Golem environment before a delegated worker run." \
  TASK_STEP_NAME="local-self-check" \
  TASK_STEP_ORDER="1" \
  TASK_CRITICAL="true" \
  TASK_EXECUTION_MODE="local" \
  ./scripts/task_run_self_check.sh "$chain_title / local self check" 2>&1
)"
self_check_exit="$?"
set -e
printf '%s\n' "$self_check_output"

self_check_task_id="$(extract_task_id "$self_check_output" || true)"
self_check_summary=""
if [ -n "$self_check_task_id" ] && [ -f "$TASKS_DIR/${self_check_task_id}.json" ]; then
  enrich_task_metadata "$self_check_task_id" \
    "Validate the local Golem environment before a delegated worker run." \
    "local-self-check" "1" "true" "local"
  self_check_summary="$(task_compact_summary "$self_check_task_id")"
fi
update_chain_step "local-self-check" "$([ "$self_check_exit" -eq 0 ] && printf 'done' || printf 'failed')" "$self_check_task_id" "${self_check_summary:-self-check finished}" "$self_check_exit"
add_chain_output "chain-step-local" "$self_check_exit" "local-self-check exit_code=${self_check_exit}" "$(
  python3 - "$chain_type" "$self_check_task_id" <<'PY'
import json
import sys

print(json.dumps({
    "chain_type": sys.argv[1],
    "step_name": "local-self-check",
    "child_task_id": sys.argv[2],
    "execution_mode": "local",
    "critical": True,
}))
PY
)"

if [ "$self_check_exit" -ne 0 ] || [ -z "$self_check_task_id" ]; then
  close_root
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

update_chain_step "delegated-repo-analysis" running "" "delegated repo-analysis child started"
worker_create_output="$(
  TASK_CHILD_DEPENDS_ON="[\"$self_check_task_id\"]" \
  TASK_CHILD_OBJECTIVE="Analyze the repository and explain the mixed local-worker orchestration flow, covering conditional decisions, aggregated summary quality, and final artifact integrity." \
  TASK_CHILD_STEP_NAME="delegated-repo-analysis" \
  TASK_CHILD_STEP_ORDER="2" \
  TASK_CHILD_CRITICAL="true" \
  TASK_CHILD_EXECUTION_MODE="worker" \
  ./scripts/task_spawn_child.sh "$root_task_id" repo-analysis "$chain_title / delegated repo analysis"
)"
printf '%s\n' "$worker_create_output"

worker_task_id="$(extract_task_id "$worker_create_output" || true)"
if [ -z "$worker_task_id" ]; then
  update_chain_step "delegated-repo-analysis" failed "" "worker child could not be created" "1"
  update_chain_step "conditional-decision" failed "" "conditional decision could not run because worker child was missing" "1"
  close_root
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$root_task_id" <<'PY'
import json
import sys

print(json.dumps({
    "root_task_id": sys.argv[1],
    "requested_deliverable": "Explain the mixed local-worker chain and validate the conditional final artifact flow.",
}))
PY
)" ./scripts/task_add_output.sh "$worker_task_id" "chain-context" 0 "Conditional mixed local-worker chain child for repo-analysis step." >/dev/null

delegate_output="$(./scripts/task_delegate.sh "$worker_task_id")"
printf '%s\n' "$delegate_output"
ticket_output="$(./scripts/task_prepare_codex_ticket.sh "$worker_task_id")"
printf '%s\n' "$ticket_output"

set +e
worker_start_output="$(./scripts/task_start_codex_run.sh "$worker_task_id" 2>&1)"
worker_start_exit="$?"
set -e
printf '%s\n' "$worker_start_output"

worker_finalize_status="done"
if [ "$worker_start_exit" -ne 0 ] || [ "$force_worker_result" = "failed" ]; then
  worker_finalize_status="failed"
fi

set +e
worker_finalize_output="$(./scripts/task_finalize_codex_run.sh "$worker_task_id" "$worker_finalize_status" 2>&1)"
worker_finalize_exit="$?"
set -e
printf '%s\n' "$worker_finalize_output"

worker_step_exit=0
if [ "$worker_start_exit" -ne 0 ] || [ "$worker_finalize_exit" -ne 0 ] || [ "$worker_finalize_status" = "failed" ]; then
  worker_step_exit=1
fi

worker_summary="$(task_compact_summary "$worker_task_id" || true)"
update_chain_step "delegated-repo-analysis" "$([ "$worker_step_exit" -eq 0 ] && printf 'done' || printf 'failed')" "$worker_task_id" "${worker_summary:-worker step finished}" "$worker_step_exit"
add_chain_output "chain-step-worker" "$worker_step_exit" "delegated-repo-analysis exit_code=${worker_step_exit} worker_finalize_status=${worker_finalize_status}" "$(
  python3 - "$chain_type" "$worker_task_id" "$worker_finalize_status" <<'PY'
import json
import sys

print(json.dumps({
    "chain_type": sys.argv[1],
    "step_name": "delegated-repo-analysis",
    "child_task_id": sys.argv[2],
    "execution_mode": "worker",
    "critical": True,
    "worker_finalize_status": sys.argv[3],
}))
PY
)"

update_chain_step "conditional-decision" running "" "evaluating conditional next step after worker"
set +e
decision_output="$("$DECIDE_NEXT" "$root_task_id" 2>&1)"
decision_exit="$?"
set -e
printf '%s\n' "$decision_output"

if [ "$decision_exit" -ne 0 ]; then
  update_chain_step "conditional-decision" failed "" "conditional decision failed" "$decision_exit"
  close_root
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

decision_reason="$(
  python3 - "$decision_output" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
print(decision.get("decision_reason", ""))
PY
)"
next_step_selected="$(
  python3 - "$decision_output" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
print(decision.get("next_step_selected", ""))
PY
)"
add_chain_output "chain-decision" 0 "conditional decision applied: next_step_selected=${next_step_selected:-"(none)"}" "$(
  python3 - "$decision_output" "$chain_type" <<'PY'
import json
import sys

decision = json.loads(sys.argv[1])
decision["chain_type"] = sys.argv[2]
print(json.dumps(decision))
PY
)"

if [ "$next_step_selected" = "local-review-worker-outcome" ]; then
  update_chain_step "local-review-worker-outcome" running "" "local worker outcome review started"
  set +e
  review_output="$(
    TASK_PARENT_TASK_ID="$root_task_id" \
    TASK_DEPENDS_ON="[\"$worker_task_id\"]" \
    TASK_OBJECTIVE="Generate a local review artifact after a successful worker outcome to prove the conditional mixed chain." \
    TASK_STEP_NAME="local-review-worker-outcome" \
    TASK_STEP_ORDER="4" \
    TASK_CRITICAL="false" \
    TASK_EXECUTION_MODE="local" \
    ./scripts/task_run_compare.sh files "$chain_title / local worker outcome review" "chain-v3-review-${root_task_id}" docs/TASK_CHAIN_RESULTS.md docs/TASK_ORCHESTRATION_CONDITIONAL.md 2>&1
  )"
  review_exit="$?"
  set -e
  printf '%s\n' "$review_output"

  review_task_id="$(extract_task_id "$review_output" || true)"
  review_summary=""
  if [ -n "$review_task_id" ] && [ -f "$TASKS_DIR/${review_task_id}.json" ]; then
    enrich_task_metadata "$review_task_id" \
      "Generate a local review artifact after a successful worker outcome to prove the conditional mixed chain." \
      "local-review-worker-outcome" "4" "false" "local"
    review_summary="$(task_compact_summary "$review_task_id")"
  fi
  update_chain_step "local-review-worker-outcome" "$([ "$review_exit" -eq 0 ] && printf 'done' || printf 'failed')" "$review_task_id" "${review_summary:-local review finished}" "$review_exit"
  add_chain_output "chain-step-local" "$review_exit" "local-review-worker-outcome exit_code=${review_exit}" "$(
    python3 - "$chain_type" "$review_task_id" <<'PY'
import json
import sys

print(json.dumps({
    "chain_type": sys.argv[1],
    "step_name": "local-review-worker-outcome",
    "child_task_id": sys.argv[2],
    "execution_mode": "local",
    "critical": False,
}))
PY
  )"
fi

close_root

root_status="$(
  python3 - "$root_task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)
print(task.get("status", ""))
print(task.get("chain_status", ""))
PY
)"
printf '%s\n' "$root_status"

root_final_status="$(printf '%s\n' "$root_status" | sed -n '1p')"
if [ "$root_final_status" = "failed" ]; then
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
