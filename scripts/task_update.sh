#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_update.sh <task-id|path> [options]

Options:
--status <todo|running|blocked|done|failed|canceled>
--owner <owner>
--title <title>
--objective <objective>
--source <panel|whatsapp|operator|script|worker|scheduled_process>
--append-accept <criterion>   (repeatable)
--note <note>
--actor <actor>

Compatibility:
./scripts/task_update.sh <task-id> <status>
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

INPUT="$1"
shift

STATUS=""
OWNER=""
TITLE=""
OBJECTIVE=""
SOURCE_CHANNEL=""
NOTE=""
ACTOR=""
declare -a APPEND_ACCEPT=()

if [[ $# -gt 0 && "$1" != --* ]]; then
  STATUS="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)
      [[ $# -ge 2 ]] || usage
      STATUS="$2"
      shift 2
      ;;
    --owner)
      [[ $# -ge 2 ]] || usage
      OWNER="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || usage
      TITLE="$2"
      shift 2
      ;;
    --objective)
      [[ $# -ge 2 ]] || usage
      OBJECTIVE="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || usage
      SOURCE_CHANNEL="$2"
      shift 2
      ;;
    --append-accept)
      [[ $# -ge 2 ]] || usage
      APPEND_ACCEPT+=("$2")
      shift 2
      ;;
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
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$STATUS" && -z "$OWNER" && -z "$TITLE" && -z "$OBJECTIVE" && -z "$SOURCE_CHANNEL" && ${#APPEND_ACCEPT[@]} -eq 0 && -z "$NOTE" ]]; then
  echo "No changes requested." >&2
  exit 2
fi

if [[ -n "$STATUS" ]]; then
  case "$STATUS" in
    todo|running|blocked|done|failed|canceled|queued|delegated|worker_running|cancelled) ;;
    *)
      echo "Invalid status: $STATUS" >&2
      exit 2
      ;;
  esac
  if [[ "$STATUS" == "cancelled" ]]; then
    STATUS="canceled"
  fi
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

TMP_PATH="$(mktemp "$TASKS_DIR/.task-update.XXXXXX.tmp")"
trap 'rm -f "$TMP_PATH"' EXIT

TASK_TARGET="$TARGET" \
STATUS="$STATUS" \
OWNER="$OWNER" \
TITLE="$TITLE" \
OBJECTIVE="$OBJECTIVE" \
SOURCE_CHANNEL="$SOURCE_CHANNEL" \
NOTE="$NOTE" \
ACTOR="$ACTOR" \
python3 - "${APPEND_ACCEPT[@]}" > "$TMP_PATH" <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys

path = pathlib.Path(os.environ["TASK_TARGET"])
status = os.environ["STATUS"]
owner = os.environ["OWNER"]
title = os.environ["TITLE"]
objective = os.environ["OBJECTIVE"]
source_channel = os.environ["SOURCE_CHANNEL"]
note = os.environ["NOTE"]
actor_override = os.environ["ACTOR"]
append_accept = sys.argv[1:]

with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

old_status = data.get("status", "")
old_owner = data.get("owner", "")
changes = []

if status and data.get("status") != status:
    changes.append(f"status:{data.get('status', '')}->{status}")
    data["status"] = status

if owner and data.get("owner") != owner:
    changes.append(f"owner:{data.get('owner', '')}->{owner}")
    data["owner"] = owner

if title and data.get("title") != title:
    changes.append("title:changed")
    data["title"] = title

if objective and data.get("objective") != objective:
    changes.append("objective:changed")
    data["objective"] = objective

if source_channel and data.get("source_channel") != source_channel:
    changes.append(f"source_channel:{data.get('source_channel', '')}->{source_channel}")
    data["source_channel"] = source_channel

if append_accept:
    if "acceptance_criteria" not in data or not isinstance(data["acceptance_criteria"], list):
        data["acceptance_criteria"] = []
    for item in append_accept:
        data["acceptance_criteria"].append(item)
    changes.append(f"acceptance_criteria:+{len(append_accept)}")

if not changes and not note:
    raise SystemExit("No effective changes detected.")

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")
data["updated_at"] = iso_now

actor = actor_override or owner or data.get("owner") or old_owner or "operator"

history_note_parts = []
if changes:
    history_note_parts.append("Changes: " + "; ".join(changes))
if note:
    history_note_parts.append("Note: " + note)
    if "task_id" in data or "notes" in data:
        data.setdefault("notes", []).append(note)

action = "updated"
if status and old_status != status:
    action = "status_changed"

data.setdefault("history", [])
data["history"].append(
    {
        "at": iso_now,
        "actor": actor,
        "action": action,
        "note": " | ".join(history_note_parts) if history_note_parts else "Task updated.",
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
printf 'TASK_UPDATED %s %s\n' "$TASK_IDENTIFIER" "$TASK_STATUS"
