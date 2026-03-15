#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

task_id=""
task_path=""
finalized="0"
run_output=""
nav_exit="1"
nav_profile=""
mode=""
url=""
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
  ./scripts/task_run_nav.sh tabs "<title>"
  ./scripts/task_run_nav.sh open "<title>" <url>
  ./scripts/task_run_nav.sh snapshot "<title>"
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

  record_file="$(mktemp "$TASKS_DIR/.task-nav-attempt.XXXXXX.json")"
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
  python3 - "${attempt_records[@]}" "$mode" "$url" "$nav_profile" "$browser_readiness_json" <<'PY'
import json
import pathlib
import sys

attempt_paths = sys.argv[1:-4]
mode, url, profile, readiness_json = sys.argv[-4:]
attempts = [json.loads(pathlib.Path(path).read_text(encoding="utf-8")) for path in attempt_paths]

extra = {
    "command": f"./scripts/browser_nav.sh {mode}" + (f" {url}" if url else ""),
    "mode": mode,
    "profile": profile,
    "attempts": attempts,
    "browser_readiness": json.loads(readiness_json) if readiness_json else {},
}
if url:
    extra["url"] = url

print(json.dumps(extra))
PY
}

on_exit() {
  local exit_code="$?"
  set +e

  if [ "$exit_code" -ne 0 ] && [ "$finalized" != "1" ] && [ -n "$task_path" ] && [ -f "$task_path" ]; then
    TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "nav-$mode" "$nav_exit" "$run_output" >/dev/null 2>&1 || true
    ./scripts/task_close.sh "$task_id" failed "task_run_nav aborted before completion" >/dev/null 2>&1 || true
  fi

  cleanup
  exit "$exit_code"
}

trap on_exit EXIT

run_browser_readiness() {
  local fields readiness_exit
  set +e
  browser_readiness_json="$(./scripts/browser_ready_check.sh navigation "$mode" --json)"
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

run_nav_for_profile() {
  local profile="$1"
  local output_file="$2"

  if [ "$profile" = "chrome" ]; then
    case "$mode" in
      tabs)
        ./scripts/browser_nav.sh tabs >"$output_file" 2>&1
        ;;
      open)
        ./scripts/browser_nav.sh open "$url" >"$output_file" 2>&1
        ;;
      snapshot)
        ./scripts/browser_nav.sh snapshot >"$output_file" 2>&1
        ;;
    esac
    return $?
  fi

  case "$mode" in
    tabs)
      openclaw browser --browser-profile "$profile" tabs >"$output_file" 2>&1
      ;;
    open)
      openclaw browser --browser-profile "$profile" open "$url" >"$output_file" 2>&1
      ;;
    snapshot)
      openclaw browser --browser-profile "$profile" snapshot >"$output_file" 2>&1
      ;;
  esac
}

run_nav_attempts() {
  local profile output_file output_text exit_code
  local -a profiles=()

  if [ -n "${GOLEM_BROWSER_PROFILE:-}" ]; then
    profiles=("$GOLEM_BROWSER_PROFILE")
  else
    profiles=("chrome" "openclaw")
  fi

  for profile in "${profiles[@]}"; do
    printf 'NAV_PROFILE %s\n' "$profile"
    output_file="$(mktemp "$TASKS_DIR/.task-nav-output.XXXXXX.log")"
    register_cleanup "$output_file"

    set +e
    run_nav_for_profile "$profile" "$output_file"
    exit_code="$?"
    set -e

    output_text="$(cat "$output_file")"
    printf '%s\n' "$output_text"
    append_attempt_record "$profile" "$exit_code" "$output_file"

    if [ "$exit_code" -eq 0 ]; then
      case "$mode" in
        tabs|snapshot)
          if printf '%s\n' "$output_text" | grep -Eq '(^Error:|No tabs|gateway closed|abnormal closure)'; then
            continue
          fi
          ;;
      esac
      run_output="$output_text"
      nav_exit="$exit_code"
      nav_profile="$profile"
      return 0
    fi
  done

  nav_exit="1"
  nav_profile=""
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
url="${3:-}"

case "$mode" in
  tabs)
    if [ -z "$title" ]; then
      usage
      printf 'ERROR: falta title\n' >&2
      exit 1
    fi
    task_type="nav-tabs"
    ;;
  open)
    if [ -z "$title" ] || [ -z "$url" ]; then
      usage
      printf 'ERROR: faltan title o url\n' >&2
      exit 1
    fi
    task_type="nav-open"
    ;;
  snapshot)
    if [ -z "$title" ]; then
      usage
      printf 'ERROR: falta title\n' >&2
      exit 1
    fi
    task_type="nav-snapshot"
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
  nav_exit="2"
  nav_profile="$browser_readiness_profile"
  TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "nav-$mode" "$nav_exit" "$run_output"
  ./scripts/task_close.sh "$task_id" blocked "browser blocked before navigation execution"
  finalized="1"
  printf 'TASK_RUN_BLOCKED %s\n' "$task_id"
  exit 2
fi

running_output="$(./scripts/task_update.sh "$task_id" running)"
printf '%s\n' "$running_output"

if [ -n "$browser_readiness_profile" ]; then
  export GOLEM_BROWSER_PROFILE="$browser_readiness_profile"
fi

if run_nav_attempts; then
  TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "nav-$mode" "$nav_exit" "$run_output"
  ./scripts/task_close.sh "$task_id" done "navigation completed and task closed"
  finalized="1"
  printf 'TASK_RUN_OK %s\n' "$task_id"
  exit 0
fi

TASK_OUTPUT_EXTRA_JSON="$(build_output_extra_json)" ./scripts/task_add_output.sh "$task_id" "nav-$mode" "$nav_exit" "$run_output"
./scripts/task_close.sh "$task_id" failed "navigation failed after browser readiness passed"
finalized="1"
printf 'TASK_RUN_FAIL %s\n' "$task_id"
exit 1
