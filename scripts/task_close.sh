#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_close.sh <task-id|path> <done|failed|canceled> --note "closure note" [--actor <actor>] [--owner <owner>] [--source <panel|whatsapp|operator|script|worker|scheduled_process>]

Compatibility:
./scripts/task_close.sh <task-id> <status> [note]
USAGE
  exit 1
}

[[ $# -ge 2 ]] || usage

INPUT="$1"
CLOSE_STATUS="$2"
shift 2

NOTE=""
ACTOR=""
OWNER=""
SOURCE_CHANNEL=""

if [[ $# -gt 0 && "$1" != --* ]]; then
  NOTE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --note)
      [[ $# -ge 2 ]] || usage
      NOTE="$2"
      shift 2
      ;;
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
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
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

case "$CLOSE_STATUS" in
  done|failed|canceled|blocked|cancelled) ;;
  *)
    echo "Invalid terminal status: $CLOSE_STATUS" >&2
    exit 2
    ;;
esac

if [[ "$CLOSE_STATUS" == "cancelled" ]]; then
  CLOSE_STATUS="canceled"
fi

if [[ -n "$SOURCE_CHANNEL" ]]; then
  case "$SOURCE_CHANNEL" in
    panel|whatsapp|operator|script|worker|scheduled_process) ;;
    *)
      echo "Invalid source_channel: $SOURCE_CHANNEL" >&2
      exit 2
      ;;
  esac
fi

[[ -n "$NOTE" ]] || {
  echo "Closure note is required." >&2
  exit 2
}

if [[ -f "$INPUT" ]]; then
  TARGET="$INPUT"
elif [[ -f "$TASKS_DIR/$INPUT.json" ]]; then
  TARGET="$TASKS_DIR/$INPUT.json"
elif [[ -f "$TASKS_DIR/$INPUT" ]]; then
  TARGET="$TASKS_DIR/$INPUT"
else
  echo "Task not found: $INPUT" >&2
  exit 2
fi

TMP_PATH="$(mktemp "$TASKS_DIR/.task-close.XXXXXX.tmp")"
trap 'rm -f "$TMP_PATH"' EXIT

TASK_TARGET="$TARGET" CLOSE_STATUS="$CLOSE_STATUS" NOTE="$NOTE" ACTOR="$ACTOR" OWNER="$OWNER" SOURCE_CHANNEL="$SOURCE_CHANNEL" python3 - > "$TMP_PATH" <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys

path = pathlib.Path(os.environ["TASK_TARGET"])
close_status = os.environ["CLOSE_STATUS"]
note = os.environ["NOTE"]
actor_override = os.environ["ACTOR"]
owner_override = os.environ["OWNER"]
source_channel = os.environ["SOURCE_CHANNEL"]

with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

current_status = data.get("status", "")
if current_status in {"done", "failed", "canceled"}:
    raise SystemExit(f"Task already closed with terminal status={current_status}.")

if owner_override:
    data["owner"] = owner_override

if source_channel:
    data["source_channel"] = source_channel

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")

data["status"] = close_status
data["updated_at"] = iso_now
if close_status in {"done", "failed", "canceled"}:
    data["closure_note"] = note

if "task_id" in data or "notes" in data:
    data.setdefault("notes", []).append(note)

actor = actor_override or owner_override or data.get("owner") or "operator"
data.setdefault("history", [])
data["history"].append(
    {
        "at": iso_now,
        "actor": actor,
        "action": f"closed_{close_status}",
        "note": note,
    }
)

identifier = data.get("id") or data.get("task_id") or path.stem
json.dump(data, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY

mv "$TMP_PATH" "$TARGET"
trap - EXIT
IDENTIFIER="$(
  TARGET="$TARGET" python3 - <<'PY'
import json
import os
import pathlib

path = pathlib.Path(os.environ["TARGET"])
with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("id") or data.get("task_id") or path.stem)
print(data.get("status", ""))
PY
)"
TASK_IDENTIFIER="$(printf '%s\n' "$IDENTIFIER" | sed -n '1p')"
TASK_STATUS="$(printf '%s\n' "$IDENTIFIER" | sed -n '2p')"
printf 'TASK_CLOSED %s %s\n' "$TASK_IDENTIFIER" "$TASK_STATUS"
