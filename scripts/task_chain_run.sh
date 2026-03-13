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

close_root() {
  local status="$1"
  local note="$2"
  ./scripts/task_close.sh "$root_task_id" "$status" "$note"
  finalized="1"
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$root_task_path" ] && [ -f "$root_task_path" ]; then
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
  self-check-compare) ;;
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

./scripts/task_update.sh "$root_task_id" running
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
add_chain_output "chain-child-self-check" "$self_check_exit" "self-check child completed with exit_code=$self_check_exit" "$self_check_task_id"

if [ "$self_check_exit" -ne 0 ] || [ -z "$self_check_task_id" ]; then
  close_root failed "chain failed during self-check child"
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

set +e
compare_output="$(
  TASK_PARENT_TASK_ID="$root_task_id" \
  TASK_DEPENDS_ON="[\"$self_check_task_id\"]" \
  ./scripts/task_run_compare.sh files "$chain_title / child compare" "chain-compare-${root_task_id}" docs/TASK_MODEL.md docs/TASK_LIFECYCLE.md 2>&1
)"
compare_exit="$?"
set -e
printf '%s\n' "$compare_output"

compare_task_id="$(extract_task_id_from_output "$compare_output" || true)"
add_chain_output "chain-child-compare" "$compare_exit" "compare child completed with exit_code=$compare_exit" "$compare_task_id"

if [ "$compare_exit" -ne 0 ] || [ -z "$compare_task_id" ]; then
  close_root failed "chain failed during compare-files child"
  printf 'TASK_CHAIN_FAIL %s\n' "$root_task_id"
  exit 1
fi

close_root done "chain self-check-compare completed"
printf 'TASK_CHAIN_OK %s\n' "$root_task_id"
