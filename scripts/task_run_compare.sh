#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

task_id=""
task_path=""
finalized="0"
run_output=""
compare_exit="1"
comparison_path=""
mode=""
slug=""
input_a=""
input_b=""
cleanup_files=()

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_run_compare.sh files "<title>" <slug> <file_a> <file_b>
USAGE
}

cleanup() {
  local file
  for file in "${cleanup_files[@]}"; do
    rm -f "$file"
  done
}

register_cleanup() {
  cleanup_files+=("$1")
}

extract_task_id() {
  local created_output="$1"
  local created_path

  created_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
  if [ -z "$created_path" ]; then
    printf 'ERROR: no se pudo extraer la ruta de la tarea creada\n' >&2
    exit 1
  fi

  basename "$created_path" .json
}

extract_comparison_path() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^COMPARISON_OK / {print $2}' | tail -n 1
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    TASK_OUTPUT_EXTRA_JSON="$(
      python3 - "$mode" "$slug" "$input_a" "$input_b" <<'PY'
import json
import sys

mode, slug, input_a, input_b = sys.argv[1:5]
print(json.dumps({
    "command": f"./scripts/browser_compare.sh {mode} {slug} {input_a} {input_b}",
    "mode": mode,
    "slug": slug,
    "input_a": input_a,
    "input_b": input_b,
}))
PY
    )" ./scripts/task_add_output.sh "$task_id" "comparison-files" "$compare_exit" "$run_output" >/dev/null 2>&1 || true
    if [ -n "$comparison_path" ]; then
      ./scripts/task_add_artifact.sh "$task_id" "comparison-files" "${comparison_path#$REPO_ROOT/}" >/dev/null 2>&1 || true
    fi
    ./scripts/task_close.sh "$task_id" failed "task_run_compare aborted before completion" >/dev/null 2>&1 || true
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

mode="${1:-}"
title="${2:-}"
slug="${3:-}"
input_a="${4:-}"
input_b="${5:-}"

case "$mode" in
  files)
    if [ -z "$title" ] || [ -z "$slug" ] || [ -z "$input_a" ] || [ -z "$input_b" ]; then
      usage
      printf 'ERROR: faltan title, slug, file_a o file_b\n' >&2
      exit 1
    fi
    task_type="compare-files"
    ;;
  *)
    usage
    exit 1
    ;;
esac

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR"

created_output="$(./scripts/task_new.sh "$task_type" "$title")"
printf '%s\n' "$created_output"

task_id="$(extract_task_id "$created_output")"
task_path="$TASKS_DIR/${task_id}.json"

running_output="$(./scripts/task_update.sh "$task_id" running)"
printf '%s\n' "$running_output"

output_file="$(mktemp "$TASKS_DIR/.task-compare-output.XXXXXX.log")"
register_cleanup "$output_file"

set +e
./scripts/browser_compare.sh files "$slug" "$input_a" "$input_b" >"$output_file" 2>&1
compare_exit="$?"
set -e

run_output="$(cat "$output_file")"
printf '%s\n' "$run_output"

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$mode" "$slug" "$input_a" "$input_b" <<'PY'
import json
import sys

mode, slug, input_a, input_b = sys.argv[1:5]
print(json.dumps({
    "command": f"./scripts/browser_compare.sh {mode} {slug} {input_a} {input_b}",
    "mode": mode,
    "slug": slug,
    "input_a": input_a,
    "input_b": input_b,
}))
PY
)" ./scripts/task_add_output.sh "$task_id" "comparison-files" "$compare_exit" "$run_output"

if [ "$compare_exit" -eq 0 ]; then
  path="$(extract_comparison_path "$run_output")"
  if [ -n "$path" ]; then
    comparison_path="$REPO_ROOT/$path"
    ./scripts/task_add_artifact.sh "$task_id" "comparison-files" "${comparison_path#$REPO_ROOT/}"
    ./scripts/task_close.sh "$task_id" done "comparison generation completed and task closed"
    finalized="1"
    printf 'TASK_RUN_OK %s\n' "$task_id"
    exit 0
  fi
fi

comparison_path=""
./scripts/task_close.sh "$task_id" failed "comparison generation failed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
