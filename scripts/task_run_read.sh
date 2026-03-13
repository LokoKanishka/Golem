#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

task_id=""
task_path=""
finalized="0"
run_output=""
read_exit="1"
read_profile=""
mode=""
query=""
cleanup_files=()
attempt_records=()

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_run_read.sh find "<title>" <texto>
  ./scripts/task_run_read.sh snapshot "<title>"
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

  record_file="$(mktemp "$TASKS_DIR/.task-read-attempt.XXXXXX.json")"
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

build_output_extra_json() {
  python3 - "${attempt_records[@]}" "$mode" "$query" "$read_profile" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-3]
mode, query, profile = sys.argv[-3:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]

extra = {
    "command": f"./scripts/browser_read.sh {mode}" + (f" {query}" if query else ""),
    "mode": mode,
    "profile": profile,
    "attempts": attempts,
}
if query:
    extra["query"] = query

print(json.dumps(extra))
PY
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "read-$mode" "$read_exit" "$run_output" >/dev/null 2>&1 || true
    ./scripts/task_close.sh "$task_id" failed "task_run_read aborted before completion" >/dev/null 2>&1 || true
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

run_read_for_profile() {
  local profile="$1"
  local output_file="$2"
  local tabs_raw tmp_file out_file

  if [ "$profile" = "chrome" ]; then
    if [ "$mode" = "snapshot" ]; then
      ./scripts/browser_read.sh snapshot >"$output_file" 2>&1
    else
      ./scripts/browser_read.sh find "$query" >"$output_file" 2>&1
    fi
    return $?
  fi

  tabs_raw="$(openclaw browser --browser-profile "$profile" tabs 2>&1 || true)"
  if printf '%s' "$tabs_raw" | grep -q 'No tabs'; then
    {
      echo "ERROR: no hay tabs adjuntas al perfil $profile"
      echo "Adjuntá una pestaña con OpenClaw Browser Relay (badge ON) y volvé a probar."
    } >"$output_file"
    return 1
  fi

  if [ "$mode" = "snapshot" ]; then
    openclaw browser --browser-profile "$profile" snapshot >"$output_file" 2>&1
    return $?
  fi

  tmp_file="$(mktemp)"
  out_file="$(mktemp)"
  register_cleanup "$tmp_file"
  register_cleanup "$out_file"
  openclaw browser --browser-profile "$profile" snapshot >"$tmp_file" 2>&1 || {
    cat "$tmp_file" >"$output_file"
    return 1
  }
  if grep -Ein -C 2 -- "$query" "$tmp_file" >"$out_file"; then
    sed -n '1,160p' "$out_file" >"$output_file"
    return 0
  fi
  echo "Sin coincidencias para: $query" >"$output_file"
  return 0
}

run_read_attempts() {
  local profile output_file output_text exit_code
  local -a profiles=()

  if [ -n "${GOLEM_BROWSER_PROFILE:-}" ]; then
    profiles=("$GOLEM_BROWSER_PROFILE")
  else
    profiles=("chrome" "openclaw")
  fi

  for profile in "${profiles[@]}"; do
    printf 'READ_PROFILE %s\n' "$profile"
    output_file="$(mktemp "$TASKS_DIR/.task-read-output.XXXXXX.log")"
    register_cleanup "$output_file"

    set +e
    run_read_for_profile "$profile" "$output_file"
    exit_code="$?"
    set -e

    output_text="$(cat "$output_file")"
    printf '%s\n' "$output_text"
    append_attempt_record "$profile" "$exit_code" "$output_file"

    if [ "$exit_code" -eq 0 ]; then
      run_output="$output_text"
      read_exit="$exit_code"
      read_profile="$profile"
      return 0
    fi
  done

  read_exit="1"
  read_profile=""
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
query="${3:-}"

case "$mode" in
  find)
    if [ -z "$title" ] || [ -z "$query" ]; then
      usage
      printf 'ERROR: faltan title o texto\n' >&2
      exit 1
    fi
    task_type="read-find"
    ;;
  snapshot)
    if [ -z "$title" ]; then
      usage
      printf 'ERROR: falta title\n' >&2
      exit 1
    fi
    task_type="read-snapshot"
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

if run_read_attempts; then
  TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "read-$mode" "$read_exit" "$run_output"
  ./scripts/task_close.sh "$task_id" done "reading completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "read-$mode" "$read_exit" "$run_output"
./scripts/task_close.sh "$task_id" failed "reading failed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
