#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_verify_media_ready.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
item_selector="${2:-}"
actor="${3:-}"
evidence="${4:-}"
shift 4 || true

output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      usage
      fatal "argumento no soportado: $1"
      ;;
  esac
  shift
done

if [ -z "$task_id" ] || [ -z "$item_selector" ] || [ -z "$actor" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, item_id, actor o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-media-verify.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$item_selector" "$actor" "$evidence" >"$tmp_path" <<'PY'
import datetime
import hashlib
import json
import mimetypes
import os
import pathlib
import pwd
import sys

task_path = pathlib.Path(sys.argv[1]).resolve()
item_selector, actor, evidence = sys.argv[2:5]

task = json.loads(task_path.read_text(encoding="utf-8"))
media = task.setdefault("media", {})
media.setdefault("protocol_version", "1.0")
media.setdefault("required", False)
media.setdefault("current_state", "none")
media.setdefault("ready", False)
media.setdefault("allowed_for_delivery", False)
media.setdefault("items", [])
media.setdefault("events", [])
media.setdefault("last_event_at", "")
media.setdefault("last_event_reason", "")

items = media.get("items") or []
if not items:
    raise SystemExit("ERROR: la tarea no tiene media registrado")

if item_selector == "latest":
    target_index = len(items) - 1
else:
    matches = [idx for idx, item in enumerate(items) if item.get("item_id") == item_selector]
    if not matches:
        raise SystemExit(f"ERROR: no existe media item {item_selector}")
    target_index = matches[-1]

item = items[target_index]
path = pathlib.Path(item.get("normalized_path", "")).expanduser()
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

exists = path.exists()
readable = os.access(path, os.R_OK) if exists else False
is_directory = path.is_dir() if exists else False
is_file = path.is_file() if exists else False
owner = ""
owner_reliable = False
try:
    if exists:
        owner = pwd.getpwuid(path.stat().st_uid).pw_name
        owner_reliable = True
except Exception:
    owner = ""
    owner_reliable = False
size_bytes = path.stat().st_size if exists and is_file else 0
mime_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
sha256 = ""
if exists and readable and is_file:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest()

state = "verified"
reason = "media identity verified and ready for downstream delivery use"
expected_path = item.get("normalized_path", "")
expected_sha256 = item.get("sha256", "")
expected_size = int(item.get("size_bytes", 0) or 0)

if not exists or not readable:
    state = "blocked"
    reason = "registered media path is no longer readable or present"
elif is_directory or not is_file:
    state = "failed"
    reason = "registered media path resolved to a directory or non-file"
elif size_bytes <= 0:
    state = "failed"
    reason = "registered media file is empty"
elif str(path.resolve(strict=False)) != expected_path:
    state = "failed"
    reason = "registered media path drifted from the canonical normalized path"
elif expected_sha256 and sha256 != expected_sha256:
    state = "failed"
    reason = "registered media sha256 drifted from the canonical identity"
elif expected_size and size_bytes != expected_size:
    state = "failed"
    reason = "registered media size drifted from the canonical identity"
elif not owner_reliable:
    state = "blocked"
    reason = "registered media owner could not be verified reliably"

item.update(
    {
        "exists": exists,
        "readable": readable,
        "is_directory": is_directory,
        "is_file": is_file,
        "owner": owner,
        "owner_reliable": owner_reliable,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "sha256": sha256,
        "verified_at": now,
        "current_state": state,
        "verification_reason": reason,
        "verification_evidence": evidence,
        "verified_by": actor,
    }
)
items[target_index] = item

media["current_state"] = state
media["ready"] = state == "verified"
media["allowed_for_delivery"] = media["ready"]
media["last_event_at"] = now
media["last_event_reason"] = reason
media["events"].append(
    {
        "timestamp": now,
        "actor": actor,
        "action": "verify",
        "reason": reason,
        "item_id": item.get("item_id", ""),
        "evidence": evidence,
    }
)
task.setdefault("outputs", []).append(
    {
        "kind": "media-readiness",
        "captured_at": now,
        "exit_code": 0 if state == "verified" else (2 if state == "blocked" else 1),
        "content": f"TASK_MEDIA_READY_{state.upper()} {task.get('task_id', '')} item_id={item.get('item_id', '')}",
        "item_id": item.get("item_id", ""),
        "normalized_path": item.get("normalized_path", ""),
        "sha256": sha256,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "media_state": state,
        "reason": reason,
    }
)
task.setdefault("notes", []).append(
    f"media readiness {state} recorded for {path.name or item.get('normalized_path', '')}"
)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT

item_json="$(python3 - "$task_path" "$item_selector" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
items = (task.get("media") or {}).get("items", [])
selector = sys.argv[2]
if selector == "latest":
    item = items[-1]
else:
    item = [entry for entry in items if entry.get("item_id") == selector][-1]
print(json.dumps(item, ensure_ascii=True))
PY
)"

item_state="$(python3 - "$item_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("current_state", ""))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$item_json"
else
  printf 'TASK_MEDIA_READY_%s %s item_id=%s\n' "$(printf '%s' "$item_state" | tr '[:lower:]' '[:upper:]')" "$task_id" "$(python3 - "$item_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("item_id", ""))
PY
)"
fi

case "$item_state" in
  verified) exit 0 ;;
  blocked) exit 2 ;;
  *) exit 1 ;;
esac
