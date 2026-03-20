#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_create.sh "Title" "Objective" [--owner <owner>] [--source <source_channel>] [--accept <criterion>]...

Examples:
./scripts/task_create.sh "Definir X" "Cerrar Y"
./scripts/task_create.sh "Definir X" "Cerrar Y" --owner diego --source panel
./scripts/task_create.sh "Definir X" "Cerrar Y" --accept "Existe doc" --accept "Verify pasa"
USAGE
  exit 1
}

[[ $# -ge 2 ]] || usage

TITLE="$1"
OBJECTIVE="$2"
shift 2

OWNER="unassigned"
SOURCE_CHANNEL="operator"
declare -a ACCEPTANCE=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      [[ $# -ge 2 ]] || usage
      OWNER="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || usage
      SOURCE_CHANNEL="$2"
      shift 2
      ;;
    --accept)
      [[ $# -ge 2 ]] || usage
      ACCEPTANCE+=("$2")
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

case "$SOURCE_CHANNEL" in
  panel|whatsapp|operator|script|worker|scheduled_process) ;;
  *)
    echo "Invalid source_channel: $SOURCE_CHANNEL" >&2
    exit 2
    ;;
esac

mkdir -p "$TASKS_DIR"

TASK_PATH="$TASKS_DIR" \
TITLE="$TITLE" \
OBJECTIVE="$OBJECTIVE" \
OWNER="$OWNER" \
SOURCE_CHANNEL="$SOURCE_CHANNEL" \
python3 - "${ACCEPTANCE[@]}" <<'PY'
import datetime as dt
import json
import os
import pathlib
import secrets
import sys

tasks_dir = pathlib.Path(os.environ["TASK_PATH"])
title = os.environ["TITLE"]
objective = os.environ["OBJECTIVE"]
owner = os.environ["OWNER"]
source_channel = os.environ["SOURCE_CHANNEL"]
acceptance = sys.argv[1:]

while True:
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    shortid = secrets.token_hex(4)
    task_id = f"task-{stamp}-{shortid}"
    path = tasks_dir / f"{task_id}.json"
    if not path.exists():
        break

iso_now = now.isoformat().replace("+00:00", "Z")
task = {
    "id": task_id,
    "title": title,
    "objective": objective,
    "status": "todo",
    "owner": owner,
    "source_channel": source_channel,
    "created_at": iso_now,
    "updated_at": iso_now,
    "acceptance_criteria": acceptance,
    "evidence": [],
    "artifacts": [],
    "closure_note": "",
    "history": [
        {
            "at": iso_now,
            "actor": owner,
            "action": "created",
            "note": f"Task created from source_channel={source_channel}.",
        }
    ],
}

with path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

print(f"TASK_CREATED {task_id}")
print(path)
PY
