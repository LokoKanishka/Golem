#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_register_media_ingestion.sh <task_id> <task-artifact|visible-artifact|local-path> <source_ref> <actor> <evidence> [--json]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
source_kind="${2:-}"
source_ref_raw="${3:-}"
actor="${4:-}"
evidence="${5:-}"
shift 5 || true

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

if [ -z "$task_id" ] || [ -z "$source_kind" ] || [ -z "$source_ref_raw" ] || [ -z "$actor" ] || [ -z "$evidence" ]; then
  usage
  fatal "faltan task_id, source_kind, source_ref, actor o evidence"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

tmp_path="$(mktemp "$TASKS_DIR/.task-media-register.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$REPO_ROOT" "$task_path" "$source_kind" "$source_ref_raw" "$actor" "$evidence" >"$tmp_path" <<'PY'
import datetime
import hashlib
import json
import mimetypes
import os
import pathlib
import pwd
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
task_path = pathlib.Path(sys.argv[2]).resolve()
source_kind, source_ref_raw, actor, evidence = sys.argv[3:7]

allowed_source_kinds = {"task-artifact", "visible-artifact", "local-path"}
if source_kind not in allowed_source_kinds:
    raise SystemExit("ERROR: source_kind invalido. Usar task-artifact, visible-artifact o local-path")

task = json.loads(task_path.read_text(encoding="utf-8"))
media = task.setdefault("media", {})
media.setdefault("protocol_version", "1.0")
media["required"] = True
media.setdefault("current_state", "none")
media.setdefault("ready", False)
media.setdefault("allowed_for_delivery", False)
media.setdefault("items", [])
media.setdefault("events", [])
media.setdefault("last_event_at", "")
media.setdefault("last_event_reason", "")

now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
source_ref = pathlib.Path(source_ref_raw).expanduser()
if not source_ref.is_absolute():
    source_ref = (repo_root / source_ref_raw).resolve(strict=False)
normalized_path = str(source_ref.resolve(strict=False))
source_path = pathlib.Path(normalized_path)

artifacts = task.get("artifacts") or []
delivery = task.get("delivery") or {}
visible_artifact_deliveries = (delivery.get("visible_artifact_deliveries") or [])

if source_kind == "task-artifact":
    artifact_match = any(
        str((repo_root / artifact.get("path")).resolve(strict=False)) == normalized_path
        if artifact.get("path", "").startswith("outbox/") or artifact.get("path", "").startswith("tasks/") or not pathlib.Path(artifact.get("path", "")).is_absolute()
        else str(pathlib.Path(artifact.get("path", "")).expanduser().resolve(strict=False)) == normalized_path
        for artifact in artifacts
    )
    if not artifact_match:
        raise SystemExit("ERROR: el source_ref no coincide con un artifact interno registrado en la task")
elif source_kind == "visible-artifact":
    visible_match = False
    for entry in visible_artifact_deliveries:
        resolved_path = entry.get("resolved_path", "")
        if resolved_path and str(pathlib.Path(resolved_path).expanduser().resolve(strict=False)) == normalized_path:
            visible_match = entry.get("verification_result") == "PASS"
            break
    if not visible_match:
        raise SystemExit("ERROR: el source_ref no coincide con un visible artifact verificado de la task")

exists = source_path.exists()
readable = os.access(source_path, os.R_OK) if exists else False
is_directory = source_path.is_dir() if exists else False
is_file = source_path.is_file() if exists else False
owner = ""
owner_reliable = False
try:
    if exists:
        owner = pwd.getpwuid(source_path.stat().st_uid).pw_name
        owner_reliable = True
except Exception:
    owner = ""
    owner_reliable = False

size_bytes = source_path.stat().st_size if exists and is_file else 0
mime_type = mimetypes.guess_type(source_path.name)[0] or "application/octet-stream"
sha256 = ""
if exists and readable and is_file:
    digest = hashlib.sha256()
    with source_path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest()

current_state = "registered"
reason = "media registered and awaiting readiness verification"
if not exists or not readable:
    current_state = "blocked"
    reason = "media source path is missing or unreadable"
elif is_directory or not is_file:
    current_state = "failed"
    reason = "media ingestion expects a file, not a directory or non-file path"
elif size_bytes <= 0:
    current_state = "failed"
    reason = "media file is empty and cannot be treated as ready for delivery"

item_id = f"media-{len(media.get('items') or []) + 1:04d}"
item = {
    "item_id": item_id,
    "source_kind": source_kind,
    "source_path": source_ref_raw,
    "normalized_path": normalized_path,
    "basename": source_path.name,
    "extension": source_path.suffix.lower(),
    "mime_type": mime_type,
    "size_bytes": size_bytes,
    "sha256": sha256,
    "readable": readable,
    "exists": exists,
    "owner": owner,
    "owner_reliable": owner_reliable,
    "is_directory": is_directory,
    "is_file": is_file,
    "collected_at": now,
    "verified_at": "",
    "current_state": current_state,
    "evidence": evidence,
    "actor": actor,
}

media["items"].append(item)
media["current_state"] = current_state
media["ready"] = current_state == "verified"
media["allowed_for_delivery"] = media["ready"]
media["last_event_at"] = now
media["last_event_reason"] = reason
media["events"].append(
    {
        "timestamp": now,
        "actor": actor,
        "action": "register",
        "reason": reason,
        "item_id": item_id,
        "evidence": evidence,
    }
)

task.setdefault("outputs", []).append(
    {
        "kind": "media-ingestion",
        "captured_at": now,
        "exit_code": 0 if current_state == "registered" else (2 if current_state == "blocked" else 1),
        "content": f"TASK_MEDIA_REGISTERED {task.get('task_id', '')} item_id={item_id} state={current_state}",
        "item_id": item_id,
        "source_kind": source_kind,
        "normalized_path": normalized_path,
        "sha256": sha256,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "media_state": current_state,
    }
)
task.setdefault("notes", []).append(
    f"media ingestion {current_state} recorded for {source_path.name or normalized_path}"
)
task["updated_at"] = now

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY

mv "$tmp_path" "$task_path"
trap - EXIT

item_json="$(python3 - "$task_path" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
item = (task.get("media") or {}).get("items", [])[-1]
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
  printf 'TASK_MEDIA_REGISTERED %s item_id=%s state=%s\n' "$task_id" "$(python3 - "$item_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("item_id", ""))
PY
)" "$item_state"
fi

case "$item_state" in
  registered) exit 0 ;;
  blocked) exit 2 ;;
  *) exit 1 ;;
esac
