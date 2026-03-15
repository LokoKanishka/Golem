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
browser_readiness_json=""
browser_readiness_state=""
browser_readiness_profile=""
browser_readiness_reason=""
browser_attempted_recovery="false"
browser_final_decision=""
browser_readiness_summary=""

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

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    TASK_OUTPUT_EXTRA_JSON="$(
      python3 - "${attempt_records[@]}" "$mode" "$slug" "$query" "$artifact_profile" "$browser_readiness_json" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-5]
mode, slug, query, profile, readiness_json = sys.argv[-5:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]
extra = {
    "command": f"./scripts/browser_artifact.sh {mode} {slug}" + (f" {query}" if query else ""),
    "mode": mode,
    "slug": slug,
    "profile": profile,
    "attempts": attempts,
    "browser_readiness": json.loads(readiness_json) if readiness_json else {},
}
if query:
    extra["query"] = query
print(json.dumps(extra))
PY
    )" ./scripts/task_add_output.sh "$task_id" "artifact-$mode" "$artifact_exit" "$run_output" >/dev/null 2>&1 || true
    if [ -n "$artifact_path" ]; then
      ./scripts/task_add_artifact.sh "$task_id" "artifact-$mode" "${artifact_path#$REPO_ROOT/}" >/dev/null 2>&1 || true
    fi
    ./scripts/task_close.sh "$task_id" failed "task_run_artifact aborted before completion" >/dev/null 2>&1 || true
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

run_browser_readiness() {
  local fields readiness_exit
  set +e
  browser_readiness_json="$(./scripts/browser_ready_check.sh artifacts "$mode" --json)"
  readiness_exit="$?"
  set -e
  fields="$(python3 - "$browser_readiness_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get("readiness_state", ""))
print(payload.get("chosen_profile", ""))
print(payload.get("reason", ""))
print("true" if payload.get("attempted_recovery") else "false")
print(payload.get("final_decision", ""))
print(payload.get("human_summary", ""))
PY
)"
  mapfile -t readiness_parts <<<"$fields"
  browser_readiness_state="${readiness_parts[0]:-}"
  browser_readiness_profile="${readiness_parts[1]:-}"
  browser_readiness_reason="${readiness_parts[2]:-}"
  browser_attempted_recovery="${readiness_parts[3]:-false}"
  browser_final_decision="${readiness_parts[4]:-}"
  browser_readiness_summary="${readiness_parts[5]:-}"

  if [ "$readiness_exit" -ne 0 ] && [ "$browser_final_decision" != "block" ]; then
    printf 'ERROR: browser_ready_check devolvio exit=%s sin decision block valida\n' "$readiness_exit" >&2
    return 1
  fi
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

run_browser_readiness

if [ "$browser_final_decision" = "block" ]; then
  run_output="BROWSER_BLOCKED ${browser_readiness_summary}"
  artifact_exit="2"
  artifact_profile="$browser_readiness_profile"
  TASK_OUTPUT_EXTRA_JSON="$(
    python3 - "${attempt_records[@]}" "$mode" "$slug" "$query" "$artifact_profile" "$browser_readiness_json" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-5]
mode, slug, query, profile, readiness_json = sys.argv[-5:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]
extra = {
    "command": f"./scripts/browser_artifact.sh {mode} {slug}" + (f" {query}" if query else ""),
    "mode": mode,
    "slug": slug,
    "profile": profile,
    "attempts": attempts,
    "browser_readiness": json.loads(readiness_json) if readiness_json else {},
}
if query:
    extra["query"] = query
print(json.dumps(extra))
PY
  )" ./scripts/task_add_output.sh "$task_id" "artifact-$mode" "$artifact_exit" "$run_output"
  ./scripts/task_close.sh "$task_id" blocked "browser blocked before artifact execution"
  finalized="1"
  printf 'TASK_RUN_BLOCKED %s\n' "$task_id"
  exit 2
fi

running_output="$(./scripts/task_update.sh "$task_id" running)"
printf '%s\n' "$running_output"

if [ -n "$browser_readiness_profile" ]; then
  export GOLEM_BROWSER_PROFILE="$browser_readiness_profile"
fi

if run_artifact_attempts; then
  TASK_OUTPUT_EXTRA_JSON="$(
    python3 - "${attempt_records[@]}" "$mode" "$slug" "$query" "$artifact_profile" "$browser_readiness_json" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-5]
mode, slug, query, profile, readiness_json = sys.argv[-5:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]
extra = {
    "command": f"./scripts/browser_artifact.sh {mode} {slug}" + (f" {query}" if query else ""),
    "mode": mode,
    "slug": slug,
    "profile": profile,
    "attempts": attempts,
    "browser_readiness": json.loads(readiness_json) if readiness_json else {},
}
if query:
    extra["query"] = query
print(json.dumps(extra))
PY
  )" ./scripts/task_add_output.sh "$task_id" "artifact-$mode" "$artifact_exit" "$run_output"
  ./scripts/task_add_artifact.sh "$task_id" "artifact-$mode" "${artifact_path#$REPO_ROOT/}"
  ./scripts/task_close.sh "$task_id" done "artifact generation completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "${attempt_records[@]}" "$mode" "$slug" "$query" "$artifact_profile" "$browser_readiness_json" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-5]
mode, slug, query, profile, readiness_json = sys.argv[-5:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]
extra = {
    "command": f"./scripts/browser_artifact.sh {mode} {slug}" + (f" {query}" if query else ""),
    "mode": mode,
    "slug": slug,
    "profile": profile,
    "attempts": attempts,
    "browser_readiness": json.loads(readiness_json) if readiness_json else {},
}
if query:
    extra["query"] = query
print(json.dumps(extra))
PY
)" ./scripts/task_add_output.sh "$task_id" "artifact-$mode" "$artifact_exit" "$run_output"
./scripts/task_close.sh "$task_id" failed "artifact generation failed after browser readiness passed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
