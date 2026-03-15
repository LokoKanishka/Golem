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

refresh_resume_state() {
  eval "$(
    python3 - "$root_task_path" "$TASKS_DIR" <<'PY'
import json
import pathlib
import shlex
import sys


TERMINAL = {"done", "failed", "blocked", "skipped"}
WAITING = {"delegated", "running", "planned"}


def dedupe(items):
    seen = set()
    ordered = []
    for item in items:
        value = str(item or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def latest_worker_result_output(task: dict) -> dict:
    for output in reversed(task.get("outputs", [])):
        if output.get("kind") == "worker-result":
            return output
    return {}


def normalize_step_status(step: dict, child: dict) -> str:
    step_status = str(step.get("status", "")).strip().lower()
    child_status = str((child or {}).get("status", "")).strip().lower()
    worker_result = latest_worker_result_output(child or {})
    worker_result_status = str(worker_result.get("status", "") or ((child or {}).get("worker_run") or {}).get("result_status", "")).strip().lower()

    if step.get("await_worker_result"):
        if child_status in {"done", "failed", "blocked", "cancelled"} and worker_result_status:
            if child_status == "cancelled":
                return "failed"
            return child_status
        if child_status in {"delegated", "worker_running", "running"}:
            return "delegated" if child_status == "delegated" else "running"
        if step_status in {"done", "failed", "blocked", "skipped"}:
            return step_status
        if child:
            return "delegated"

    if step_status in {"done", "failed", "blocked", "skipped", "delegated", "running", "planned"}:
        return step_status
    if child_status in {"done", "failed", "blocked"}:
        return child_status
    if child_status == "cancelled":
        return "failed"
    if child_status in {"delegated", "worker_running", "running"}:
        return "delegated" if child_status == "delegated" else "running"
    return "planned"


task_path = pathlib.Path(sys.argv[1])
tasks_dir = pathlib.Path(sys.argv[2])
root = json.loads(task_path.read_text(encoding="utf-8"))
chain_plan = root.get("chain_plan") or {}
steps = chain_plan.get("steps") or []
declared_groups = chain_plan.get("dependency_groups") or []
children = {}
for path in tasks_dir.glob("*.json"):
    task = json.loads(path.read_text(encoding="utf-8"))
    children[task.get("task_id", path.stem)] = task

step_states = {}
step_children = {}
resolved_workers = []
waiting_workers = []

for step in sorted(steps, key=lambda value: (int(value.get("step_order", 0) or 0), value.get("step_name", ""))):
    child = {}
    child_task_id = str(step.get("child_task_id", "")).strip()
    if child_task_id:
      child = children.get(child_task_id, {})
    if not child and step.get("step_name"):
        for candidate in children.values():
            if candidate.get("parent_task_id") != root.get("task_id"):
                continue
            if candidate.get("step_name") == step.get("step_name"):
                child = candidate
                child_task_id = candidate.get("task_id", "")
                break
    status = normalize_step_status(step, child)
    step_states[step.get("step_name", "")] = status
    step_children[step.get("step_name", "")] = child

    if step.get("await_worker_result"):
        worker_result = latest_worker_result_output(child or {})
        worker_result_status = (
            worker_result.get("status")
            or ((child or {}).get("worker_run") or {}).get("result_status", "")
        )
        item = {
            "step_name": step.get("step_name", ""),
            "step_order": step.get("step_order", ""),
            "critical": bool(step.get("critical", False)),
            "status": status,
            "current_step_status": step.get("status", ""),
            "child_task_id": child_task_id,
            "child_status": (child or {}).get("status", ""),
            "worker_result_status": worker_result_status,
            "await_group": step.get("await_group", ""),
        }
        if status in {"done", "failed", "blocked"} and child_task_id and worker_result_status:
            resolved_workers.append(item)
        elif status in WAITING or not child_task_id or not worker_result_status:
            waiting_workers.append(item)

group_to_used_by = {}
for step in steps:
    join_group = str(step.get("join_group", "")).strip()
    if join_group:
        group_to_used_by.setdefault(join_group, []).append(step.get("step_name", ""))

barrier_states = []
barrier_state_map = {}
for group in declared_groups:
    group_name = str(group.get("group_name") or group.get("name") or "").strip()
    if not group_name:
        continue
    group_type = str(group.get("group_type") or "join_barrier").strip() or "join_barrier"
    satisfaction_policy = str(group.get("satisfaction_policy") or "all_done").strip() or "all_done"
    continue_on_blocked = bool(group.get("continue_on_blocked", False))
    continue_on_failed = bool(group.get("continue_on_failed", False))
    step_names = dedupe(group.get("step_names") or [])
    if not step_names and group_type == "await_group":
        step_names = [
            step.get("step_name", "")
            for step in steps
            if str(step.get("await_group", "")).strip() == group_name
        ]
    if not step_names:
        step_names = dedupe(
            dependency
            for step in steps
            if str(step.get("join_group", "")).strip() == group_name
            for dependency in (step.get("depends_on_step_names") or [])
        )

    step_rows = []
    done_names = []
    waiting_names = []
    failed_names = []
    blocked_names = []
    skipped_names = []
    for step_name in step_names:
        status = step_states.get(step_name, "planned")
        row = {"step_name": step_name, "status": status}
        step_rows.append(row)
        if status == "done":
            done_names.append(step_name)
        elif status in WAITING:
            waiting_names.append(step_name)
        elif status == "failed":
            failed_names.append(step_name)
        elif status == "blocked":
            blocked_names.append(step_name)
        elif status == "skipped":
            skipped_names.append(step_name)

    if failed_names and not continue_on_failed:
        barrier_status = "failed"
        barrier_reason = "failed dependency steps: " + ", ".join(failed_names)
    elif blocked_names and not continue_on_blocked:
        barrier_status = "blocked"
        barrier_reason = "blocked dependency steps: " + ", ".join(blocked_names)
    elif skipped_names and not continue_on_failed:
        barrier_status = "failed"
        barrier_reason = "skipped dependency steps: " + ", ".join(skipped_names)
    elif satisfaction_policy == "all_done" and step_names and len(done_names) == len(step_names):
        barrier_status = "satisfied"
        barrier_reason = "all dependency steps resolved as done"
    else:
        barrier_status = "waiting"
        waiting_set = waiting_names or [row["step_name"] for row in step_rows if row["status"] != "done"]
        barrier_reason = (
            "waiting for dependency steps: " + ", ".join(waiting_set)
            if waiting_set
            else "waiting for dependency state changes"
        )

    barrier_state = {
        "group_name": group_name,
        "group_type": group_type,
        "satisfaction_policy": satisfaction_policy,
        "continue_on_blocked": continue_on_blocked,
        "continue_on_failed": continue_on_failed,
        "status": barrier_status,
        "reason": barrier_reason,
        "step_names": step_names,
        "step_states": step_rows,
        "done_step_names": done_names,
        "waiting_step_names": waiting_names,
        "failed_step_names": failed_names,
        "blocked_step_names": blocked_names,
        "skipped_step_names": skipped_names,
        "used_by_step_names": dedupe(group.get("used_by_step_names") or group_to_used_by.get(group_name, [])),
    }
    barrier_states.append(barrier_state)
    barrier_state_map[group_name] = barrier_state

runnable_local_steps = []
skippable_steps = []
for step in sorted(steps, key=lambda value: (int(value.get("step_order", 0) or 0), value.get("step_name", ""))):
    if step.get("execution_mode") != "local":
        continue
    step_name = step.get("step_name", "")
    if step_states.get(step_name) != "planned":
        continue
    dependencies = step.get("depends_on_step_names") or []
    join_group = str(step.get("join_group", "")).strip()
    barrier = barrier_state_map.get(join_group) if join_group else None

    if barrier:
        if barrier["status"] == "satisfied":
            runnable_local_steps.append(
                {
                    "step_name": step_name,
                    "step_order": step.get("step_order", ""),
                    "critical": bool(step.get("critical", False)),
                    "task_type": step.get("task_type", ""),
                    "title": step.get("title", ""),
                    "objective": step.get("objective", ""),
                    "join_group": join_group,
                    "join_group_status": barrier["status"],
                    "join_group_reason": barrier["reason"],
                    "dependency_child_task_ids": [
                        (step_children.get(name) or {}).get("task_id", "")
                        for name in dependencies
                        if (step_children.get(name) or {}).get("task_id", "")
                    ],
                }
            )
            continue
        if barrier["status"] in {"failed", "blocked"}:
            skippable_steps.append(
                {
                    "step_name": step_name,
                    "step_order": step.get("step_order", ""),
                    "critical": bool(step.get("critical", False)),
                    "task_type": step.get("task_type", ""),
                    "title": step.get("title", ""),
                    "objective": step.get("objective", ""),
                    "current_status": step.get("status", ""),
                    "join_group": join_group,
                    "join_group_status": barrier["status"],
                    "join_group_reason": barrier["reason"],
                    "reason": "dependency_barrier_not_satisfied",
                    "blocking_dependencies": barrier["step_states"],
                }
            )
        continue

    dependency_states = [step_states.get(name, "planned") for name in dependencies]
    if any(state in {"failed", "blocked", "skipped"} for state in dependency_states):
        blocking_dependencies = [
            {"step_name": name, "status": step_states.get(name, "planned")}
            for name in dependencies
            if step_states.get(name, "planned") in {"failed", "blocked", "skipped"}
        ]
        skippable_steps.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", ""),
                "critical": bool(step.get("critical", False)),
                "task_type": step.get("task_type", ""),
                "title": step.get("title", ""),
                "objective": step.get("objective", ""),
                "current_status": step.get("status", ""),
                "reason": "dependencies_not_done",
                "blocking_dependencies": blocking_dependencies,
            }
        )
        continue
    if any(state in WAITING for state in dependency_states):
        continue
    if not dependencies:
        runnable_local_steps.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", ""),
                "critical": bool(step.get("critical", False)),
                "task_type": step.get("task_type", ""),
                "title": step.get("title", ""),
                "objective": step.get("objective", ""),
                "dependency_child_task_ids": [],
            }
        )
        continue
    if all(state == "done" for state in dependency_states):
        runnable_local_steps.append(
            {
                "step_name": step_name,
                "step_order": step.get("step_order", ""),
                "critical": bool(step.get("critical", False)),
                "task_type": step.get("task_type", ""),
                "title": step.get("title", ""),
                "objective": step.get("objective", ""),
                "join_group": join_group,
                "dependency_child_task_ids": [
                    (step_children.get(name) or {}).get("task_id", "")
                    for name in dependencies
                    if (step_children.get(name) or {}).get("task_id", "")
                ],
            }
        )

values = {
    "ROOT_STATUS": root.get("status", ""),
    "ROOT_CHAIN_STATUS": root.get("chain_status", ""),
    "CHAIN_TYPE": root.get("chain_type", ""),
    "ROOT_TITLE": root.get("title", ""),
    "DEPENDENCY_BARRIERS_JSON": json.dumps(barrier_states),
    "RESOLVED_WORKERS_JSON": json.dumps(resolved_workers),
    "WAITING_WORKERS_JSON": json.dumps(waiting_workers),
    "RUNNABLE_LOCAL_STEPS_JSON": json.dumps(runnable_local_steps),
    "SKIPPABLE_STEPS_JSON": json.dumps(skippable_steps),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
  )"
}

run_local_resume_step() {
  local step_json="$1"
  local step_name step_order step_critical step_task_type step_title step_objective depends_json
  local compare_slug step_output step_exit step_task_id step_summary

  step_name="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("step_name", ""))
PY
  )"
  step_order="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("step_order", ""))
PY
  )"
  step_critical="$(python3 - "$step_json" <<'PY'
import json, sys
print("true" if json.loads(sys.argv[1]).get("critical") else "false")
PY
  )"
  step_task_type="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("task_type", ""))
PY
  )"
  step_title="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("title", ""))
PY
  )"
  step_objective="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("objective", ""))
PY
  )"
  depends_json="$(python3 - "$step_json" <<'PY'
import json, sys
print(json.dumps(json.loads(sys.argv[1]).get("dependency_child_task_ids", [])))
PY
  )"

  if [ "$step_task_type" != "compare-files" ]; then
    fatal "resume v2 no sabe ejecutar local task_type=$step_task_type para step=$step_name"
  fi

  compare_slug="$(
    python3 - "$root_task_id" "$step_name" <<'PY'
import re
import sys

root_task_id, step_name = sys.argv[1:3]
slug = re.sub(r"[^a-z0-9]+", "-", step_name.lower()).strip("-") or "step"
print(f"chain-v2-{slug}-{root_task_id}")
PY
  )"

  update_chain_step "$step_name" running "" "local continuation started"
  set +e
  step_output="$(
    TASK_PARENT_TASK_ID="$root_task_id" \
    TASK_DEPENDS_ON="$depends_json" \
    TASK_OBJECTIVE="$step_objective" \
    TASK_STEP_NAME="$step_name" \
    TASK_STEP_ORDER="$step_order" \
    TASK_CRITICAL="$step_critical" \
    TASK_EXECUTION_MODE="local" \
    ./scripts/task_run_compare.sh files "$step_title" "$compare_slug" docs/TASK_ORCHESTRATION.md docs/TASK_ORCHESTRATION_V2.md 2>&1
  )"
  step_exit="$?"
  set -e
  printf '%s\n' "$step_output"

  step_task_id="$(extract_task_id "$step_output" || true)"
  step_summary=""
  if [ -n "$step_task_id" ] && [ -f "$TASKS_DIR/${step_task_id}.json" ]; then
    enrich_task_metadata "$step_task_id" \
      "$step_objective" \
      "$step_name" "$step_order" "$step_critical" "local"
    step_summary="$(task_compact_summary "$step_task_id")"
  fi

  update_chain_step "$step_name" "$([ "$step_exit" -eq 0 ] && printf 'done' || printf 'failed')" "$step_task_id" "${step_summary:-continuation step finished}" "$step_exit"
  add_chain_output "chain-step-local" "$step_exit" "${step_name} exit_code=${step_exit}" "$step_name" "$step_task_id" "local" "$step_critical"
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

refresh_resume_state

if [ "$CHAIN_TYPE" != "repo-analysis-worker-manual" ] && [ "$CHAIN_TYPE" != "repo-analysis-worker-manual-multi" ]; then
  fatal "resume v2 solo soporta por ahora chains manuales con worker awaitable"
fi

if [ "$ROOT_STATUS" != "delegated" ] || [ "$ROOT_CHAIN_STATUS" != "awaiting_worker_result" ]; then
  fatal "la tarea raiz no esta en delegated/awaiting_worker_result"
fi

resume_started="0"
while :; do
  refresh_resume_state

  while IFS= read -r worker_json; do
    [ -n "$worker_json" ] || continue
    worker_step_name="$(python3 - "$worker_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("step_name", ""))
PY
    )"
    worker_child_task_id="$(python3 - "$worker_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("child_task_id", ""))
PY
    )"
    worker_child_status="$(python3 - "$worker_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("child_status", ""))
PY
    )"
    worker_result_status="$(python3 - "$worker_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("worker_result_status", ""))
PY
    )"
    worker_step_critical="$(python3 - "$worker_json" <<'PY'
import json, sys
print("1" if json.loads(sys.argv[1]).get("critical") else "0")
PY
    )"
    current_step_status="$(python3 - "$worker_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("current_step_status", ""))
PY
    )"

    case "$worker_child_status" in
      done) worker_step_exit="0" ;;
      blocked) worker_step_exit="2" ;;
      failed|cancelled) worker_step_exit="1" ;;
      *) continue ;;
    esac

    if [ "$current_step_status" != "$worker_child_status" ]; then
      worker_summary="$(task_compact_summary "$worker_child_task_id" || true)"
      update_chain_step "$worker_step_name" "$worker_child_status" "$worker_child_task_id" "${worker_summary:-worker result recorded}" "$worker_step_exit"
      add_chain_output "chain-resume-worker" "$worker_step_exit" "${worker_step_name} resumed from worker child status=${worker_child_status} worker_result_status=${worker_result_status}" "$worker_step_name" "$worker_child_task_id" "worker" "$worker_step_critical"
    fi
  done < <(
    python3 - "$RESOLVED_WORKERS_JSON" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(json.dumps(item))
PY
  )

  refresh_resume_state

  while IFS= read -r skip_json; do
    [ -n "$skip_json" ] || continue
    skip_step_name="$(python3 - "$skip_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("step_name", ""))
PY
    )"
    skip_current_status="$(python3 - "$skip_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get("current_status", ""))
PY
    )"
    skip_step_critical="$(python3 - "$skip_json" <<'PY'
import json, sys
print("1" if json.loads(sys.argv[1]).get("critical") else "0")
PY
    )"
    skip_reason="$(python3 - "$skip_json" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
deps = ", ".join(f"{item.get('step_name')}={item.get('status')}" for item in row.get("blocking_dependencies", []))
join_group = row.get("join_group", "")
join_group_status = row.get("join_group_status", "")
join_group_reason = row.get("join_group_reason", "")
if join_group:
    if join_group_reason:
        print(f"step skipped because dependency barrier {join_group} is {join_group_status}: {join_group_reason}")
    else:
        print(f"step skipped because dependency barrier {join_group} is {join_group_status}")
elif deps:
    print(f"step skipped because blocking dependencies reached terminal non-done states: {deps}")
else:
    print("step skipped because dependencies did not finish as done")
PY
    )"
    if [ "$skip_current_status" = "planned" ] || [ "$skip_current_status" = "queued" ]; then
      update_chain_step "$skip_step_name" "skipped" "" "$skip_reason" ""
      add_chain_output "chain-step-local" 0 "$skip_reason" "$skip_step_name" "" "local" "$skip_step_critical"
    fi
  done < <(
    python3 - "$SKIPPABLE_STEPS_JSON" <<'PY'
import json, sys
for item in json.loads(sys.argv[1]):
    print(json.dumps(item))
PY
  )

  refresh_resume_state
  runnable_count="$(python3 - "$RUNNABLE_LOCAL_STEPS_JSON" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
  )"
  waiting_count="$(python3 - "$WAITING_WORKERS_JSON" <<'PY'
import json, sys
print(len(json.loads(sys.argv[1])))
PY
  )"

  if [ "$runnable_count" -eq 0 ]; then
    break
  fi

  if [ "$resume_started" != "1" ]; then
    ./scripts/task_update.sh "$root_task_id" running >/dev/null
    set_root_chain_status running
    add_chain_output "chain-resume" 0 "chain resume started after one or more worker results"
    resume_started="1"
  fi

  next_local_step_json="$(
    python3 - "$RUNNABLE_LOCAL_STEPS_JSON" <<'PY'
import json, sys

steps = json.loads(sys.argv[1])
if steps:
    steps.sort(key=lambda item: (int(item.get("step_order", 0) or 0), item.get("step_name", "")))
    print(json.dumps(steps[0]))
PY
  )"
  [ -n "$next_local_step_json" ] || break
  run_local_resume_step "$next_local_step_json"
done

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
