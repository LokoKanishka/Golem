#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_verify_host_screenshot.sh <task_id> <item_id|latest> <actor> <evidence> [--json]
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

tmp_path="$(mktemp "$TASKS_DIR/.task-host-screenshot-verify.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$item_selector" "$actor" "$evidence" >"$tmp_path" <<'PY'
import datetime
import hashlib
import json
import mimetypes
import os
import pathlib
import pwd
import shutil
import subprocess
import sys

task_path = pathlib.Path(sys.argv[1])
item_selector, actor, evidence = sys.argv[2:5]

task = json.loads(task_path.read_text(encoding="utf-8"))
screenshot = task.setdefault("screenshot", {})
screenshot.setdefault("protocol_version", "1.0")
screenshot.setdefault("required", False)
screenshot.setdefault("current_state", "none")
screenshot.setdefault("ready_for_claim", False)
screenshot.setdefault("items", [])
screenshot.setdefault("events", [])
screenshot.setdefault("last_transition_at", "")
screenshot.setdefault("last_verified_at", "")
screenshot.setdefault("block_reason", "")
screenshot.setdefault("fail_reason", "")

items = screenshot.get("items") or []
if not items:
    raise SystemExit("ERROR: la tarea no tiene screenshots registrados")

if item_selector == "latest":
    target_index = len(items) - 1
else:
    matches = [idx for idx, item in enumerate(items) if item.get("item_id") == item_selector]
    if not matches:
        raise SystemExit(f"ERROR: no existe screenshot item {item_selector}")
    target_index = matches[-1]

item = items[target_index]
path_raw = item.get("normalized_path", "")
path = pathlib.Path(path_raw).expanduser() if path_raw else None
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

exists = path.exists() if path else False
readable = os.access(path, os.R_OK) if exists else False
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

mime_type = ""
if exists and is_file and shutil.which("file"):
    proc = subprocess.run(
        ["file", "--mime-type", "-b", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    mime_type = proc.stdout.strip()
if not mime_type:
    mime_type = mimetypes.guess_type(path.name if path else "")[0] or "application/octet-stream"

sha256 = ""
if exists and readable and is_file:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest()

state = "verified"
reason = "host screenshot artifact was verified and can back visual claims"
expected_path = item.get("normalized_path", "")
expected_sha256 = item.get("sha256", "")
expected_size = int(item.get("size_bytes", 0) or 0)

if not path_raw:
    state = "blocked"
    reason = "no screenshot path was persisted for verification"
elif not exists or not readable:
    state = "blocked"
    reason = "registered screenshot path is missing or unreadable"
elif not is_file:
    state = "failed"
    reason = "registered screenshot path is not a file"
elif size_bytes <= 0:
    state = "failed"
    reason = "registered screenshot file is empty"
elif str(path.resolve(strict=False)) != expected_path:
    state = "failed"
    reason = "registered screenshot path drifted from the canonical normalized path"
elif expected_sha256 and sha256 != expected_sha256:
    state = "failed"
    reason = "registered screenshot sha256 drifted from the canonical identity"
elif expected_size and size_bytes != expected_size:
    state = "failed"
    reason = "registered screenshot size drifted from the canonical identity"
elif not owner_reliable:
    state = "blocked"
    reason = "registered screenshot owner could not be verified reliably"
elif not mime_type.startswith("image/"):
    state = "failed"
    reason = "registered screenshot mime_type is not image-compatible"

item.update(
    {
        "exists": exists,
        "readable": readable,
        "owner": owner,
        "owner_reliable": owner_reliable,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "sha256": sha256,
        "verified_at": now,
        "state": state,
        "verification_reason": reason,
        "verification_evidence": evidence,
        "verified_by": actor,
    }
)
items[target_index] = item

screenshot["current_state"] = state
screenshot["ready_for_claim"] = state == "verified"
screenshot["last_transition_at"] = now
screenshot["last_verified_at"] = now if state == "verified" else screenshot.get("last_verified_at", "")
if state == "blocked":
    screenshot["block_reason"] = reason
    screenshot["fail_reason"] = ""
elif state == "failed":
    screenshot["fail_reason"] = reason
    screenshot["block_reason"] = ""
else:
    screenshot["block_reason"] = ""
    screenshot["fail_reason"] = ""
screenshot["events"].append(
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
        "kind": "host-screenshot-verify",
        "captured_at": now,
        "exit_code": 0 if state == "verified" else (2 if state == "blocked" else 1),
        "content": f"TASK_HOST_SCREENSHOT_READY_{state.upper()} {task.get('task_id', '')} item_id={item.get('item_id', '')}",
        "item_id": item.get("item_id", ""),
        "normalized_path": item.get("normalized_path", ""),
        "sha256": sha256,
        "size_bytes": size_bytes,
        "mime_type": mime_type,
        "screenshot_state": state,
        "reason": reason,
    }
)
task.setdefault("notes", []).append(
    f"host screenshot verification {state} recorded for {item.get('target_kind', '')}"
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
items = (task.get("screenshot") or {}).get("items", [])
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
print(json.loads(sys.argv[1]).get("state", ""))
PY
)"

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$item_json"
else
  printf 'TASK_HOST_SCREENSHOT_READY_%s %s item_id=%s\n' "$(printf '%s' "$item_state" | tr '[:lower:]' '[:upper:]')" "$task_id" "$(python3 - "$item_json" <<'PY'
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
