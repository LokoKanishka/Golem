#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_plan.sh repo-analysis-worker "<title>"
  ./scripts/task_chain_plan.sh repo-analysis-worker-manual "<title>"
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

extract_task_path() {
  local created_output="$1"
  printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1
}

chain_type="${1:-}"
chain_title="${2:-}"

if [ -z "$chain_type" ] || [ -z "$chain_title" ]; then
  usage
  fatal "faltan chain_type o title"
fi

case "$chain_type" in
  repo-analysis-worker|repo-analysis-worker-manual) ;;
  *)
    usage
    fatal "chain_type no soportado: $chain_type"
    ;;
esac

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR"

created_output="$(./scripts/task_new.sh task-chain "$chain_title")"
printf '%s\n' "$created_output"

root_task_rel="$(extract_task_path "$created_output")"
if [ -z "$root_task_rel" ]; then
  fatal "no se pudo extraer la ruta de la tarea raiz"
fi

root_task_path="$REPO_ROOT/$root_task_rel"
root_task_id="$(basename "$root_task_path" .json)"
tmp_path="$(mktemp "$TASKS_DIR/.task-chain-plan.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

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

if chain_type == "repo-analysis-worker-manual":
    task["objective"] = (
        "Execute a mixed local-worker chain that delegates the worker step, prepares the handoff, "
        "waits for a manual-controlled worker result, and resumes one local closing step after that result exists."
    )
    steps = [
        {
            "step_name": "local-self-check",
            "step_order": 1,
            "task_type": "self-check",
            "execution_mode": "local",
            "critical": True,
            "title": f"{chain_title} / local self-check",
            "objective": "Validate the local Golem environment before any delegation.",
            "depends_on_step_names": [],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": False,
        },
        {
            "step_name": "delegated-repo-analysis",
            "step_order": 2,
            "task_type": "repo-analysis",
            "execution_mode": "worker",
            "critical": True,
            "title": f"{chain_title} / delegated repo analysis",
            "objective": (
                "Prepare a real delegated repo-analysis worker step with durable handoff and ticket, "
                "then wait for manual-controlled worker execution and result closure."
            ),
            "depends_on_step_names": ["local-self-check"],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": True,
        },
        {
            "step_name": "local-compare-orchestration-docs",
            "step_order": 3,
            "task_type": "compare-files",
            "execution_mode": "local",
            "critical": False,
            "title": f"{chain_title} / local orchestration docs comparison",
            "objective": (
                "Produce one local artifact after the manual-controlled worker result is registered so the chain "
                "can resume and close with mixed evidence."
            ),
            "depends_on_step_names": ["delegated-repo-analysis"],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": False,
        },
    ]
    version = "2.2"
else:
    task["objective"] = f"Execute a mixed local-worker chain and produce an aggregated final artifact for {chain_type}."
    steps = [
        {
            "step_name": "local-self-check",
            "step_order": 1,
            "task_type": "self-check",
            "execution_mode": "local",
            "critical": True,
            "title": f"{chain_title} / local self-check",
            "objective": "Validate the local Golem environment before any delegation.",
            "depends_on_step_names": [],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": False,
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
                "covering chain plan richness, aggregated summary quality, and final artifact integrity."
            ),
            "depends_on_step_names": ["local-self-check"],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": False,
        },
        {
            "step_name": "local-compare-orchestration-docs",
            "step_order": 3,
            "task_type": "compare-files",
            "execution_mode": "local",
            "critical": False,
            "title": f"{chain_title} / local orchestration docs comparison",
            "objective": "Produce one local artifact after the worker step to prove mixed execution inside one chain.",
            "depends_on_step_names": ["delegated-repo-analysis"],
            "status": "planned",
            "child_task_id": "",
            "await_worker_result": False,
        },
    ]
    version = "2.0"

task["chain_type"] = chain_type
task["chain_status"] = "planned"
task["chain_plan"] = {
    "version": version,
    "planned_at": planned_at,
    "mixes_execution_modes": True,
    "manual_worker_controlled": chain_type == "repo-analysis-worker-manual",
    "local_step_count": sum(1 for step in steps if step["execution_mode"] == "local"),
    "worker_step_count": 1,
    "critical_step_count": sum(1 for step in steps if step["critical"]),
    "await_worker_result_step_count": sum(1 for step in steps if step.get("await_worker_result")),
    "step_count": len(steps),
    "steps": steps,
}
task.setdefault("notes", []).append(f"chain plan v2 created at {planned_at}")
task["updated_at"] = planned_at

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$root_task_path"
trap - EXIT

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$chain_type" <<'PY'
import json
import sys

chain_type = sys.argv[1]
print(json.dumps({
    "chain_type": chain_type,
    "plan_version": "2.2" if chain_type == "repo-analysis-worker-manual" else "2.0",
    "step_count": 3,
    "local_step_count": 2,
    "worker_step_count": 1,
    "critical_step_count": 2,
    "await_worker_result_step_count": 1 if chain_type == "repo-analysis-worker-manual" else 0,
}))
PY
)" ./scripts/task_add_output.sh "$root_task_id" "chain-plan" 0 "$(
  if [ "$chain_type" = "repo-analysis-worker-manual" ]; then
    printf 'planned 3-step mixed local-worker chain with manual worker await and resume'
  else
    printf 'planned 3-step mixed local-worker chain'
  fi
)"

printf 'TASK_CHAIN_PLANNED %s\n' "$root_task_id"
