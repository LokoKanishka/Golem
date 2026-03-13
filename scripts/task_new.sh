#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_new.sh <type> <title>

Opcional por entorno:
  TASK_PARENT_TASK_ID=<task_id_padre>
  TASK_DEPENDS_ON='["task-a","task-b"]'
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

TASK_PARENT_TASK_ID="${TASK_PARENT_TASK_ID:-}" \
TASK_DEPENDS_ON="${TASK_DEPENDS_ON:-}" \
python3 - "$task_id" "$task_type" "$title" > "$tmp_path" <<'PY'
import datetime
import json
import os
import sys

task_id, task_type, title = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
parent_task_id = os.environ.get("TASK_PARENT_TASK_ID", "").strip()
depends_on_raw = os.environ.get("TASK_DEPENDS_ON", "").strip()

depends_on = []
if depends_on_raw:
    try:
        parsed = json.loads(depends_on_raw)
    except json.JSONDecodeError:
        parsed = [item.strip() for item in depends_on_raw.split(",") if item.strip()]
    if isinstance(parsed, list):
        depends_on = [str(item).strip() for item in parsed if str(item).strip()]
    else:
        raise SystemExit("TASK_DEPENDS_ON debe ser una lista JSON o una lista separada por comas")

task = {
    "task_id": task_id,
    "type": task_type,
    "origin": "local",
    "canonical_session": "",
    "parent_task_id": parent_task_id,
    "depends_on": depends_on,
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
