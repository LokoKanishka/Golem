#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
COLLECT_RESULTS="$REPO_ROOT/scripts/task_chain_collect_results.sh"

root_task_id=""
root_task_path=""
finalized="0"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_resume.sh <root_task_id>
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
    if new_status in {"done", "failed", "blocked", "skipped"}:
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
  local step_name="${4:-}"
  local child_task_id="${5:-}"
  local execution_mode="${6:-}"
  local critical="${7:-}"
  local extra_json
  extra_json="$(
    python3 - "$step_name" "$child_task_id" "$execution_mode" "$critical" <<'PY'
import json
import sys

step_name, child_task_id, execution_mode, critical = sys.argv[1:5]
payload = {}
if step_name:
    payload["step_name"] = step_name
if child_task_id:
    payload["child_task_id"] = child_task_id
if execution_mode:
    payload["execution_mode"] = execution_mode
if critical:
    payload["critical"] = critical.lower() in {"1", "true", "yes", "y", "on"}
print(json.dumps(payload))
PY
  )"
  TASK_OUTPUT_EXTRA_JSON="$extra_json" ./scripts/task_add_output.sh "$root_task_id" "$kind" "$exit_code" "$content" >/dev/null
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
    "steps_blocked={steps_blocked} worker_steps_done={worker_steps_done} "
    "worker_steps_blocked={worker_steps_blocked} worker_steps_failed={worker_steps_failed} "
    "steps_delegated={steps_delegated} steps_running={steps_running} "
    "worker_steps_delegated={worker_steps_delegated} worker_steps_running={worker_steps_running} "
    "delegated_steps_count={delegated_steps_count} local_steps_count={local_steps_count}".format(
        chain_status=summary["chain_status"],
        steps_completed=summary["steps_completed"],
        step_count=summary["step_count"],
        steps_blocked=summary["steps_blocked"],
        worker_steps_done=summary["worker_steps_done"],
        worker_steps_blocked=summary["worker_steps_blocked"],
        worker_steps_failed=summary["worker_steps_failed"],
        steps_delegated=summary["steps_delegated"],
        steps_running=summary["steps_running"],
        worker_steps_delegated=summary["worker_steps_delegated"],
        worker_steps_running=summary["worker_steps_running"],
        delegated_steps_count=summary["delegated_steps_count"],
        local_steps_count=summary["local_steps_count"],
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
    "steps_blocked": summary["steps_blocked"],
    "steps_delegated": summary["steps_delegated"],
    "steps_running": summary["steps_running"],
    "steps_pending": summary["steps_pending"],
    "children_delegated": summary["children_delegated"],
    "children_running": summary["children_running"],
    "local_steps_count": summary["local_steps_count"],
    "delegated_steps_count": summary["delegated_steps_count"],
    "worker_steps_done": summary["worker_steps_done"],
    "worker_steps_blocked": summary["worker_steps_blocked"],
    "worker_steps_delegated": summary["worker_steps_delegated"],
    "worker_steps_running": summary["worker_steps_running"],
    "worker_steps_failed": summary["worker_steps_failed"],
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

root_status_snapshot() {
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
}

on_exit() {
  local exit_code="$?"
  set +e

  case "$exit_code" in
    0|2|3)
      exit "$exit_code"
      ;;
  esac

  if [ "$finalized" != "1" ] && [ -n "$root_task_path" ] && [ -f "$root_task_path" ]; then
    ./scripts/task_chain_finalize.sh "$root_task_id" >/dev/null 2>&1 || \
      ./scripts/task_close.sh "$root_task_id" failed "task_chain_resume aborted before completion" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

trap on_exit EXIT

root_task_id="${1:-}"

if [ -z "$root_task_id" ]; then
  usage
  fatal "falta root_task_id"
fi

root_task_path="$TASKS_DIR/${root_task_id}.json"
if [ ! -f "$root_task_path" ]; then
  fatal "no existe la tarea raiz: $root_task_id"
fi

eval "$(
  python3 - "$root_task_path" "$TASKS_DIR" <<'PY'
import json
import pathlib
import shlex
import sys


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


task_path = pathlib.Path(sys.argv[1])
tasks_dir = pathlib.Path(sys.argv[2])

with task_path.open(encoding="utf-8") as fh:
    root = json.load(fh)

chain_plan = root.get("chain_plan") if isinstance(root.get("chain_plan"), dict) else {}
steps = chain_plan.get("steps") if isinstance(chain_plan.get("steps"), list) else []
children = {}
for path in tasks_dir.glob("*.json"):
    with path.open(encoding="utf-8") as fh:
        task = json.load(fh)
    task_id = task.get("task_id", path.stem)
    children[task_id] = task

worker_step = {}
for step in steps:
    if step.get("await_worker_result"):
        worker_step = step
        break

worker_child = {}
worker_child_task_id = worker_step.get("child_task_id", "")
if worker_child_task_id:
    worker_child = children.get(worker_child_task_id, {})
else:
    for task in children.values():
        if task.get("parent_task_id") == root.get("task_id") and task.get("step_name") == worker_step.get("step_name"):
            worker_child = task
            worker_child_task_id = task.get("task_id", "")
            break

worker_result = latest_worker_result_output(worker_child) if worker_child else {}
worker_run = worker_child.get("worker_run") or {}

continuation_step = {}
worker_step_name = worker_step.get("step_name", "")
for step in steps:
    if step.get("status") not in {"planned", "queued"}:
        continue
    dependencies = step.get("depends_on_step_names") or []
    if worker_step_name and worker_step_name in dependencies:
        continuation_step = step
        break

values = {
    "ROOT_STATUS": root.get("status", ""),
    "ROOT_CHAIN_STATUS": root.get("chain_status", ""),
    "CHAIN_TYPE": root.get("chain_type", ""),
    "ROOT_TITLE": root.get("title", ""),
    "WORKER_STEP_NAME": worker_step.get("step_name", ""),
    "WORKER_STEP_ORDER": str(worker_step.get("step_order", "")),
    "WORKER_STEP_CRITICAL": "1" if worker_step.get("critical") else "0",
    "WORKER_STEP_STATUS": worker_step.get("status", ""),
    "WORKER_CHILD_TASK_ID": worker_child_task_id,
    "WORKER_CHILD_STATUS": worker_child.get("status", ""),
    "WORKER_RESULT_STATUS": worker_result.get("status") or worker_run.get("result_status", ""),
    "WORKER_RESULT_REGISTERED": "1" if (worker_result or worker_run.get("result_status")) else "0",
    "CONTINUATION_STEP_NAME": continuation_step.get("step_name", ""),
    "CONTINUATION_STEP_ORDER": str(continuation_step.get("step_order", "")),
    "CONTINUATION_STEP_CRITICAL": "1" if continuation_step.get("critical") else "0",
    "CONTINUATION_STEP_TITLE": continuation_step.get("title", ""),
    "CONTINUATION_STEP_OBJECTIVE": continuation_step.get("objective", ""),
    "CONTINUATION_STEP_STATUS": continuation_step.get("status", ""),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

if [ "$CHAIN_TYPE" != "repo-analysis-worker-manual" ]; then
  fatal "resume v2 solo soporta por ahora repo-analysis-worker-manual"
fi

if [ "$ROOT_STATUS" != "delegated" ] || [ "$ROOT_CHAIN_STATUS" != "awaiting_worker_result" ]; then
  fatal "la tarea raiz no esta en delegated/awaiting_worker_result"
fi

if [ -z "$WORKER_STEP_NAME" ] || [ -z "$WORKER_CHILD_TASK_ID" ]; then
  fatal "no se encontro un step worker pendiente de reanudacion"
fi

if [ "$WORKER_RESULT_REGISTERED" != "1" ] || [ -z "$WORKER_RESULT_STATUS" ] || [[ "$WORKER_CHILD_STATUS" =~ ^(delegated|worker_running|running|queued)?$ ]]; then
  printf 'TASK_CHAIN_STILL_WAITING %s\n' "$root_task_id"
  exit 3
fi

worker_step_exit="1"
case "$WORKER_CHILD_STATUS" in
  done) worker_step_exit="0" ;;
  blocked) worker_step_exit="2" ;;
  failed|cancelled) worker_step_exit="1" ;;
  *)
    printf 'TASK_CHAIN_STILL_WAITING %s\n' "$root_task_id"
    exit 3
    ;;
esac

worker_summary="$(task_compact_summary "$WORKER_CHILD_TASK_ID" || true)"
update_chain_step "$WORKER_STEP_NAME" "$WORKER_CHILD_STATUS" "$WORKER_CHILD_TASK_ID" "${worker_summary:-worker result recorded}" "$worker_step_exit"
add_chain_output "chain-resume-worker" "$worker_step_exit" "${WORKER_STEP_NAME} resumed from worker child status=${WORKER_CHILD_STATUS} worker_result_status=${WORKER_RESULT_STATUS}" "$WORKER_STEP_NAME" "$WORKER_CHILD_TASK_ID" "worker" "$WORKER_STEP_CRITICAL"

if [ "$WORKER_CHILD_STATUS" != "done" ]; then
  if [ -n "$CONTINUATION_STEP_NAME" ] && [ "$CONTINUATION_STEP_STATUS" = "planned" ]; then
    update_chain_step "$CONTINUATION_STEP_NAME" "skipped" "" "step skipped because worker outcome was ${WORKER_CHILD_STATUS}" ""
    add_chain_output "chain-step-local" 0 "${CONTINUATION_STEP_NAME} skipped because worker outcome was ${WORKER_CHILD_STATUS}" "$CONTINUATION_STEP_NAME" "" "local" "$CONTINUATION_STEP_CRITICAL"
  fi
  close_root
  root_status="$(root_status_snapshot)"
  printf '%s\n' "$root_status"
  root_final_status="$(printf '%s\n' "$root_status" | sed -n '1p')"
  if [ "$root_final_status" = "blocked" ]; then
    printf 'TASK_CHAIN_BLOCKED %s\n' "$root_task_id"
    exit 2
  fi
  if [ "$root_final_status" = "failed" ]; then
    printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
    exit 1
  fi
  if [ "$root_final_status" = "delegated" ]; then
    printf 'TASK_CHAIN_DELEGATED %s\n' "$root_task_id"
    exit 3
  fi
  printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
  exit 0
fi

./scripts/task_update.sh "$root_task_id" running >/dev/null
set_root_chain_status running
add_chain_output "chain-resume" 0 "chain resume started after worker result" "$WORKER_STEP_NAME" "$WORKER_CHILD_TASK_ID" "worker" "$WORKER_STEP_CRITICAL"

compare_title="$CONTINUATION_STEP_TITLE"
if [ -z "$compare_title" ] && [ -n "$CONTINUATION_STEP_NAME" ]; then
  compare_title="${ROOT_TITLE} / ${CONTINUATION_STEP_NAME}"
fi

compare_objective="$CONTINUATION_STEP_OBJECTIVE"
if [ -z "$compare_objective" ] && [ -n "$CONTINUATION_STEP_NAME" ]; then
  compare_objective="Produce one local artifact after the manual-controlled worker result is registered so the chain can close with mixed evidence."
fi

if [ -n "$CONTINUATION_STEP_NAME" ] && [ "$CONTINUATION_STEP_STATUS" = "planned" ]; then
  update_chain_step "$CONTINUATION_STEP_NAME" running "" "local continuation started"
  set +e
  compare_output="$(
    TASK_PARENT_TASK_ID="$root_task_id" \
    TASK_DEPENDS_ON="[\"$WORKER_CHILD_TASK_ID\"]" \
    TASK_OBJECTIVE="$compare_objective" \
    TASK_STEP_NAME="$CONTINUATION_STEP_NAME" \
    TASK_STEP_ORDER="$CONTINUATION_STEP_ORDER" \
    TASK_CRITICAL="$CONTINUATION_STEP_CRITICAL" \
    TASK_EXECUTION_MODE="local" \
    ./scripts/task_run_compare.sh files "$compare_title" "chain-v2-compare-${root_task_id}" docs/TASK_ORCHESTRATION.md docs/TASK_ORCHESTRATION_V2.md 2>&1
  )"
  compare_exit="$?"
  set -e
  printf '%s\n' "$compare_output"

  compare_task_id="$(extract_task_id "$compare_output" || true)"
  compare_summary=""
  if [ -n "$compare_task_id" ] && [ -f "$TASKS_DIR/${compare_task_id}.json" ]; then
    enrich_task_metadata "$compare_task_id" \
      "$compare_objective" \
      "$CONTINUATION_STEP_NAME" "$CONTINUATION_STEP_ORDER" "$CONTINUATION_STEP_CRITICAL" "local"
    compare_summary="$(task_compact_summary "$compare_task_id")"
  fi
  update_chain_step "$CONTINUATION_STEP_NAME" "$([ "$compare_exit" -eq 0 ] && printf 'done' || printf 'failed')" "$compare_task_id" "${compare_summary:-continuation step finished}" "$compare_exit"
  add_chain_output "chain-step-local" "$compare_exit" "${CONTINUATION_STEP_NAME} exit_code=${compare_exit}" "$CONTINUATION_STEP_NAME" "$compare_task_id" "local" "$CONTINUATION_STEP_CRITICAL"
fi

close_root

root_status="$(root_status_snapshot)"
printf '%s\n' "$root_status"

root_final_status="$(printf '%s\n' "$root_status" | sed -n '1p')"
if [ "$root_final_status" = "failed" ]; then
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

if [ "$root_final_status" = "blocked" ]; then
  printf 'TASK_CHAIN_BLOCKED %s\n' "$root_task_id"
  exit 2
fi

if [ "$root_final_status" = "delegated" ]; then
  printf 'TASK_CHAIN_DELEGATED %s\n' "$root_task_id"
  exit 3
fi

printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
