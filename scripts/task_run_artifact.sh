#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

task_id=""
task_path=""
finalized="0"
run_output=""
artifact_exit="1"
artifact_profile=""
artifact_path=""
mode=""
slug=""
query=""
cleanup_files=()
attempt_records=()

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_run_artifact.sh snapshot "<title>" <slug>
  ./scripts/task_run_artifact.sh find "<title>" <slug> <texto>
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

append_attempt_record() {
  local profile="$1"
  local exit_code="$2"
  local content_file="$3"
  local record_file

  record_file="$(mktemp "$TASKS_DIR/.task-artifact-attempt.XXXXXX.json")"
  register_cleanup "$record_file"

  python3 - "$profile" "$exit_code" "$content_file" > "$record_file" <<'PY'
import json
import pathlib
import sys

profile, exit_code, content_file = sys.argv[1:4]
content = pathlib.Path(content_file).read_text(encoding="utf-8", errors="replace")

json.dump(
    {
        "profile": profile,
        "exit_code": int(exit_code),
        "content": content,
    },
    sys.stdout,
    ensure_ascii=True,
)
sys.stdout.write("\n")
PY

  attempt_records+=("$record_file")
}

finalize_task_json() {
  local final_status="$1"
  local note_message="$2"
  local tmp_path

  if [ -z "$task_path" ] || [ ! -f "$task_path" ]; then
    return 0
  fi

  tmp_path="$(mktemp "$TASKS_DIR/.task-artifact-final.XXXXXX.tmp")"
  register_cleanup "$tmp_path"

  ATTEMPT_FILES="$(IFS=:; printf '%s' "${attempt_records[*]:-}")" \
  ARTIFACT_RUN_OUTPUT="$run_output" \
  ARTIFACT_EXIT="$artifact_exit" \
  ARTIFACT_PROFILE="$artifact_profile" \
  ARTIFACT_PATH="$artifact_path" \
  FINAL_STATUS="$final_status" \
  NOTE_MESSAGE="$note_message" \
  TASK_MODE="$mode" \
  TASK_SLUG="$slug" \
  TASK_QUERY="$query" \
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
query = os.environ.get("TASK_QUERY", "")
artifact_exit = int(os.environ.get("ARTIFACT_EXIT", "1"))
artifact_profile = os.environ.get("ARTIFACT_PROFILE", "")
artifact_path_raw = os.environ.get("ARTIFACT_PATH", "")
run_output = os.environ.get("ARTIFACT_RUN_OUTPUT", "")
attempt_files_raw = os.environ.get("ATTEMPT_FILES", "")

attempts = []
if attempt_files_raw:
    for raw_path in attempt_files_raw.split(":"):
        if not raw_path:
            continue
        with open(raw_path, encoding="utf-8") as fh:
            attempts.append(json.load(fh))

task["status"] = final_status
task["updated_at"] = now

output_entry = {
    "kind": f"artifact-{mode}",
    "captured_at": now,
    "command": f"./scripts/browser_artifact.sh {mode} {slug}" + (f" {query}" if query else ""),
    "mode": mode,
    "slug": slug,
    "exit_code": artifact_exit,
    "profile": artifact_profile,
    "content": run_output,
    "attempts": attempts,
}
if query:
    output_entry["query"] = query

outputs = task.setdefault("outputs", [])
outputs.append(output_entry)

if artifact_path_raw:
    artifact_path = pathlib.Path(artifact_path_raw)
    try:
      rel_path = artifact_path.relative_to(repo_root)
    except ValueError:
      rel_path = artifact_path

    artifacts = task.setdefault("artifacts", [])
    artifacts.append(
        {
            "path": str(rel_path),
            "kind": f"artifact-{mode}",
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
    finalize_task_json "failed" "task_run_artifact aborted before completion"
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

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

extract_artifact_path() {
  local output="$1"
  printf '%s\n' "$output" | awk '/^ARTIFACT_OK / {print $2}' | tail -n 1
}

run_artifact_attempts() {
  local profile output_file output_text exit_code path
  local -a profiles=()

  if [ -n "${GOLEM_BROWSER_PROFILE:-}" ]; then
    profiles=("$GOLEM_BROWSER_PROFILE")
  else
    profiles=("chrome" "openclaw")
  fi

  for profile in "${profiles[@]}"; do
    printf 'ARTIFACT_PROFILE %s\n' "$profile"
    output_file="$(mktemp "$TASKS_DIR/.task-artifact-output.XXXXXX.log")"
    register_cleanup "$output_file"

    set +e
    if [ "$mode" = "snapshot" ]; then
      GOLEM_BROWSER_PROFILE="$profile" ./scripts/browser_artifact.sh snapshot "$slug" >"$output_file" 2>&1
    else
      GOLEM_BROWSER_PROFILE="$profile" ./scripts/browser_artifact.sh find "$slug" "$query" >"$output_file" 2>&1
    fi
    exit_code="$?"
    set -e

    output_text="$(cat "$output_file")"
    printf '%s\n' "$output_text"
    append_attempt_record "$profile" "$exit_code" "$output_file"

    if [ "$exit_code" -eq 0 ]; then
      path="$(extract_artifact_path "$output_text")"
      if [ -n "$path" ]; then
        run_output="$output_text"
        artifact_exit="$exit_code"
        artifact_profile="$profile"
        artifact_path="$REPO_ROOT/$path"
        return 0
      fi
    fi
  done

  artifact_exit="1"
  artifact_profile=""
  artifact_path=""
  run_output="$(python3 - "${attempt_records[@]}" <<'PY'
import json
import pathlib
import sys

parts = []
for path in sys.argv[1:]:
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    parts.append(f"[profile={data['profile']} exit={data['exit_code']}]\n{data['content']}")
print("\n\n".join(parts))
PY
)"
  return 1
}

mode="${1:-}"
title="${2:-}"
slug="${3:-}"
query="${4:-}"

case "$mode" in
  snapshot)
    if [ -z "$title" ] || [ -z "$slug" ]; then
      usage
      printf 'ERROR: faltan title o slug\n' >&2
      exit 1
    fi
    task_type="artifact-snapshot"
    ;;
  find)
    if [ -z "$title" ] || [ -z "$slug" ] || [ -z "$query" ]; then
      usage
      printf 'ERROR: faltan title, slug o texto\n' >&2
      exit 1
    fi
    task_type="artifact-find"
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

if run_artifact_attempts; then
  finalize_task_json "done" "artifact generation completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

finalize_task_json "failed" "artifact generation failed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
