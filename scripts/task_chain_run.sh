#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

root_task_id=""
root_task_path=""
finalized="0"
chain_type=""
chain_title=""

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_chain_run.sh self-check-compare "<title>"
  ./scripts/task_chain_run.sh self-check-compare-fail "<title>"
  ./scripts/task_chain_run.sh browser-nav-tabs "<title>"
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

extract_task_id_from_output() {
  local output="$1"
  local created_path
  created_path="$(printf '%s\n' "$output" | awk '/^TASK_CREATED / {print $2}' | head -n 1)"
  if [ -z "$created_path" ]; then
    return 1
  fi
  basename "$created_path" .json
}

add_chain_output() {
  local kind="$1"
  local exit_code="$2"
  local content="$3"
  local child_task_id="${4:-}"

  TASK_OUTPUT_EXTRA_JSON="$(
    python3 - "$chain_type" "$child_task_id" <<'PY'
import json
import sys

chain_type, child_task_id = sys.argv[1:3]
extra = {"chain_type": chain_type}
if child_task_id:
    extra["child_task_id"] = child_task_id
print(json.dumps(extra))
PY
  )" ./scripts/task_add_output.sh "$root_task_id" "$kind" "$exit_code" "$content"
}

enrich_task_metadata() {
  local task_id="$1"
  local objective="${2:-}"
  local step_name="${3:-}"
  local step_order="${4:-}"
  local critical="${5:-}"
  local execution_mode="${6:-}"
  local tmp_path

  tmp_path="$(mktemp "$TASKS_DIR/.task-chain-basic-enrich.XXXXXX.tmp")"
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

close_root() {
  ./scripts/task_chain_finalize.sh "$root_task_id" >/dev/null
  finalized="1"
}

set_root_chain_state() {
  local new_chain_status="$1"
  local tmp_path
  tmp_path="$(mktemp "$TASKS_DIR/.task-chain-state.XXXXXX.tmp")"
  python3 - "$root_task_path" "$chain_type" "$new_chain_status" >"$tmp_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
chain_type = sys.argv[2]
chain_status = sys.argv[3]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["chain_type"] = chain_type
task["chain_status"] = chain_status

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
  mv "$tmp_path" "$root_task_path"
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$root_task_path" ] && [ -f "$root_task_path" ]; then
    ./scripts/task_chain_finalize.sh "$root_task_id" >/dev/null 2>&1 || \
      ./scripts/task_close.sh "$root_task_id" failed "task_chain_run aborted before completion" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

trap on_exit EXIT

chain_type="${1:-}"
chain_title="${2:-}"

if [ -z "$chain_type" ] || [ -z "$chain_title" ]; then
  usage
  fatal "faltan chain_type o title"
fi

case "$chain_type" in
  self-check-compare|self-check-compare-fail|browser-nav-tabs) ;;
  *)
    usage
    fatal "chain_type no soportado: $chain_type"
    ;;
esac

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR"

created_output="$(./scripts/task_new.sh task-chain "$chain_title")"
printf '%s\n' "$created_output"

root_task_path="$(extract_task_path "$created_output")"
if [ -z "$root_task_path" ]; then
  fatal "no se pudo extraer la ruta de la tarea raiz"
fi
root_task_id="$(basename "$root_task_path" .json)"
set_root_chain_state planned

./scripts/task_update.sh "$root_task_id" running
set_root_chain_state running
add_chain_output "chain-start" 0 "chain_type=$chain_type root_task_id=$root_task_id"

set +e
self_check_output="$(
  TASK_PARENT_TASK_ID="$root_task_id" \
  TASK_DEPENDS_ON="[\"$root_task_id\"]" \
  ./scripts/task_run_self_check.sh "$chain_title / child self-check" 2>&1
)"
self_check_exit="$?"
set -e
printf '%s\n' "$self_check_output"

self_check_task_id="$(extract_task_id_from_output "$self_check_output" || true)"
if [ -n "$self_check_task_id" ] && [ -f "$TASKS_DIR/${self_check_task_id}.json" ]; then
  enrich_task_metadata "$self_check_task_id" \
    "Run the chain self-check child step." \
    "local-self-check" "1" "true" "local"
fi
add_chain_output "chain-child-self-check" "$self_check_exit" "self-check child completed with exit_code=$self_check_exit" "$self_check_task_id"

if [ "$self_check_exit" -ne 0 ] || [ -z "$self_check_task_id" ]; then
  close_root failed "chain failed during self-check child"
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

compare_file_b="docs/TASK_LIFECYCLE.md"
if [ "$chain_type" = "browser-nav-tabs" ]; then
  set +e
  nav_output="$(
    TASK_PARENT_TASK_ID="$root_task_id" \
    TASK_DEPENDS_ON="[\"$root_task_id\"]" \
    TASK_STEP_NAME="browser-nav-tabs" \
    TASK_STEP_ORDER="1" \
    TASK_CRITICAL="true" \
    TASK_EXECUTION_MODE="local" \
    ./scripts/task_run_nav.sh tabs "$chain_title / child browser nav" 2>&1
  )"
  nav_exit="$?"
  set -e
  printf '%s\n' "$nav_output"

  nav_task_id="$(extract_task_id_from_output "$nav_output" || true)"
  if [ -n "$nav_task_id" ] && [ -f "$TASKS_DIR/${nav_task_id}.json" ]; then
    enrich_task_metadata "$nav_task_id" \
      "Run the browser navigation child step." \
      "browser-nav-tabs" "2" "true" "local"
  fi
  add_chain_output "chain-child-browser-nav" "$nav_exit" "browser nav child completed with exit_code=$nav_exit" "$nav_task_id"

  if [ -z "$nav_task_id" ]; then
    close_root
    printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
    exit 1
  fi

  close_root
  root_status="$(
    python3 - "$root_task_path" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
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
  if [ "$root_final_status" = "blocked" ]; then
    printf 'TASK_CHAIN_BLOCKED %s\n' "$root_task_id"
    exit 2
  fi
  printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
  exit 0
fi

if [ "$chain_type" = "self-check-compare-fail" ]; then
  compare_file_b="docs/NO_SUCH_FILE_FOR_CHAIN_FAIL.md"
fi

set +e
compare_output="$(
  TASK_PARENT_TASK_ID="$root_task_id" \
  TASK_DEPENDS_ON="[\"$self_check_task_id\"]" \
  ./scripts/task_run_compare.sh files "$chain_title / child compare" "chain-compare-${root_task_id}" docs/TASK_MODEL.md "$compare_file_b" 2>&1
)"
compare_exit="$?"
set -e
printf '%s\n' "$compare_output"

compare_task_id="$(extract_task_id_from_output "$compare_output" || true)"
if [ -n "$compare_task_id" ] && [ -f "$TASKS_DIR/${compare_task_id}.json" ]; then
  enrich_task_metadata "$compare_task_id" \
    "Run the compare-files child step." \
    "local-compare" "2" "true" "local"
fi
add_chain_output "chain-child-compare" "$compare_exit" "compare child completed with exit_code=$compare_exit" "$compare_task_id"

if [ "$compare_exit" -ne 0 ] || [ -z "$compare_task_id" ]; then
  close_root failed "chain failed during compare-files child"
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

close_root done "chain self-check-compare completed"
printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
