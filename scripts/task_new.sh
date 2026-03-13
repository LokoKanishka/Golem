#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_new.sh <type> <title>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_tasks_dir() {
  mkdir -p "$TASKS_DIR"
}

display_path() {
  local file="$1"
  printf '%s\n' "${file#$REPO_ROOT/}"
}

task_type="${1:-}"
if [ -z "$task_type" ]; then
  usage
  fatal "falta type"
fi

if [ "$#" -lt 2 ]; then
  usage
  fatal "falta title"
fi

title="${*:2}"

ensure_tasks_dir

task_id="$(
  python3 - <<'PY'
import datetime
import uuid

ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
suffix = uuid.uuid4().hex[:8]
print(f"task-{ts}-{suffix}")
PY
)"

task_path="$TASKS_DIR/${task_id}.json"
tmp_path="$(mktemp "$TASKS_DIR/.task-new.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_id" "$task_type" "$title" > "$tmp_path" <<'PY'
import datetime
import json
import sys

task_id, task_type, title = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

task = {
    "task_id": task_id,
    "type": task_type,
    "origin": "local",
    "canonical_session": "",
    "status": "queued",
    "created_at": now,
    "updated_at": now,
    "title": title,
    "objective": title,
    "inputs": [],
    "outputs": [],
    "artifacts": [],
    "notes": [],
}

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT
printf 'TASK_CREATED %s\n' "$(display_path "$task_path")"
