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

finalize_task_json() {
  local final_status="$1"
  local note_message="$2"
  local tmp_path

  if [ -z "$task_path" ] || [ ! -f "$task_path" ]; then
    return 0
  fi

  tmp_path="$(mktemp "$TASKS_DIR/.task-compare-final.XXXXXX.tmp")"
  register_cleanup "$tmp_path"

  COMPARE_RUN_OUTPUT="$run_output" \
  COMPARE_EXIT="$compare_exit" \
  COMPARISON_PATH="$comparison_path" \
  FINAL_STATUS="$final_status" \
  NOTE_MESSAGE="$note_message" \
  TASK_MODE="$mode" \
  TASK_SLUG="$slug" \
  TASK_INPUT_A="$input_a" \
  TASK_INPUT_B="$input_b" \
  python3 - "$task_path" "$REPO_ROOT" > "$tmp_path" <<'PY'
import datetime
import json
import os
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
final_status = os.environ["FINAL_STATUS"]
note_message = os.environ["NOTE_MESSAGE"]
mode = os.environ["TASK_MODE"]
slug = os.environ["TASK_SLUG"]
input_a = os.environ["TASK_INPUT_A"]
input_b = os.environ["TASK_INPUT_B"]
compare_exit = int(os.environ.get("COMPARE_EXIT", "1"))
comparison_path_raw = os.environ.get("COMPARISON_PATH", "")
run_output = os.environ.get("COMPARE_RUN_OUTPUT", "")

task["status"] = final_status
task["updated_at"] = now

output_entry = {
    "kind": "comparison-files",
    "captured_at": now,
    "command": f"./scripts/browser_compare.sh {mode} {slug} {input_a} {input_b}",
    "mode": mode,
    "slug": slug,
    "input_a": input_a,
    "input_b": input_b,
    "exit_code": compare_exit,
    "content": run_output,
}

outputs = task.setdefault("outputs", [])
outputs.append(output_entry)

if comparison_path_raw:
    comparison_path = pathlib.Path(comparison_path_raw)
    try:
        rel_path = comparison_path.relative_to(repo_root)
    except ValueError:
        rel_path = comparison_path

    artifacts = task.setdefault("artifacts", [])
    artifacts.append(
        {
            "path": str(rel_path),
            "kind": "comparison-files",
            "created_at": now,
        }
    )

notes = task.setdefault("notes", [])
if note_message:
    notes.append(note_message)

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

  mv "$tmp_path" "$task_path"
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    finalize_task_json "failed" "task_run_compare aborted before completion"
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

if [ "$compare_exit" -eq 0 ]; then
  path="$(extract_comparison_path "$run_output")"
  if [ -n "$path" ]; then
    comparison_path="$REPO_ROOT/$path"
    finalize_task_json "done" "comparison generation completed and task closed"
    finalized="1"
    printf 'TASK_RUN_OK %s\n' "$task_id"
    exit 0
  fi
fi

comparison_path=""
finalize_task_json "failed" "comparison generation failed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
