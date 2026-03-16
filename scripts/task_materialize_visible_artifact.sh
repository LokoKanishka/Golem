#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_materialize_visible_artifact.sh <task_id> <artifact_path> <desktop|downloads> [filename] [--json]
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

persist_copy_blocked() {
  local task_path="$1"
  local source_path="$2"
  local delivery_target="$3"
  local filename="$4"
  local captured_at="$5"
  local resolution_json="$6"
  local reported_path="$7"
  local copy_output="$8"
  local tmp_path

  tmp_path="$(mktemp "$TASKS_DIR/.task-visible-artifact-copy-blocked.XXXXXX.tmp")"
  trap 'rm -f "$tmp_path"' EXIT
  python3 - "$task_path" "$source_path" "$delivery_target" "$filename" "$captured_at" "$resolution_json" "$reported_path" "$copy_output" >"$tmp_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
source_path, delivery_target, filename, captured_at = sys.argv[2:6]
resolution = json.loads(sys.argv[6])
reported_path = sys.argv[7]
copy_output = sys.argv[8]

task = json.loads(task_path.read_text(encoding="utf-8"))
delivery = task.setdefault("delivery", {})
delivery.setdefault("protocol_version", "1.0")
delivery.setdefault("minimum_user_facing_success_state", "visible")
delivery.setdefault("current_state", "")
delivery.setdefault("user_facing_ready", False)
delivery["visible_artifact_required"] = True
delivery["visible_artifact_ready"] = False
delivery.setdefault("visible_artifact_deliveries", [])
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])

verification = {
    "exists": False,
    "readable": False,
    "owner": "",
    "path_normalized": "",
    "verified_at": captured_at,
    "verification_result": "BLOCKED",
    "reason": "artifact could not be materialized into the resolved visible destination",
}

entry = {
    "delivery_target": delivery_target,
    "requested_filename": filename,
    "source_artifact_path": source_path,
    "captured_at": captured_at,
    "selected_directory": resolution.get("absolute_directory", ""),
    "resolved_path": reported_path,
    "path_normalized": "",
    "resolution_reason": resolution.get("resolution_reason", ""),
    "verification_result": "BLOCKED",
    "verified_at": captured_at,
    "verification": verification,
    "resolution": resolution,
    "materialization_output": copy_output,
}
delivery["visible_artifact_deliveries"].append(entry)
delivery["last_visible_artifact_delivery_at"] = captured_at
delivery["last_visible_artifact_delivery_result"] = "BLOCKED"
task.setdefault("outputs", []).append(
    {
        "kind": "visible-artifact-delivery",
        "captured_at": captured_at,
        "exit_code": 2,
        "content": f"VISIBLE_ARTIFACT_DELIVERY_BLOCKED target={delivery_target} path={reported_path}",
        "delivery_target": delivery_target,
        "source_artifact_path": source_path,
        "requested_filename": filename,
        "resolved_path": reported_path,
        "verification_result": "BLOCKED",
        "verification_result_detail": verification,
        "materialization_output": copy_output,
    }
)
task.setdefault("notes", []).append(
    f"visible artifact delivery blocked for target {delivery_target}: materialization into the resolved destination failed"
)
task["updated_at"] = captured_at

print(json.dumps(task, indent=2, ensure_ascii=True))
PY
  mv "$tmp_path" "$task_path"
  trap - EXIT
}

task_id="${1:-}"
source_path_raw="${2:-}"
delivery_target="${3:-}"
shift 3 || true

filename=""
output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      if [ -n "$filename" ]; then
        usage
        fatal "argumento no soportado: $1"
      fi
      filename="$1"
      ;;
  esac
  shift
done

if [ -z "$task_id" ] || [ -z "$source_path_raw" ] || [ -z "$delivery_target" ]; then
  usage
  fatal "faltan task_id, artifact_path o delivery_target"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

source_path="$source_path_raw"
if [ ! -e "$source_path" ]; then
  source_path="$REPO_ROOT/$source_path_raw"
fi
if [ ! -f "$source_path" ]; then
  fatal "no existe el artifact fuente: $source_path_raw"
fi

if [ -z "$filename" ]; then
  filename="$(basename "$source_path")"
fi

set +e
resolution_json="$(./scripts/resolve_user_visible_destination.sh "$delivery_target" "$filename" --json 2>&1)"
resolution_exit="$?"
set -e

captured_at="$(date -u --iso-8601=seconds)"

if [ "$resolution_exit" -ne 0 ]; then
  tmp_path="$(mktemp "$TASKS_DIR/.task-visible-artifact-blocked.XXXXXX.tmp")"
  trap 'rm -f "$tmp_path"' EXIT
  python3 - "$task_path" "$source_path" "$delivery_target" "$filename" "$captured_at" "$resolution_json" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
source_path, delivery_target, filename, captured_at, resolution_output = sys.argv[2:7]
task = json.loads(task_path.read_text(encoding="utf-8"))
delivery = task.setdefault("delivery", {})
delivery.setdefault("protocol_version", "1.0")
delivery.setdefault("minimum_user_facing_success_state", "visible")
delivery.setdefault("current_state", "")
delivery.setdefault("user_facing_ready", False)
delivery["visible_artifact_required"] = True
delivery["visible_artifact_ready"] = False
delivery.setdefault("visible_artifact_deliveries", [])
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])

entry = {
    "delivery_target": delivery_target,
    "requested_filename": filename,
    "source_artifact_path": source_path,
    "captured_at": captured_at,
    "resolved_path": "",
    "path_normalized": "",
    "verification_result": "BLOCKED",
    "resolution_output": resolution_output,
    "verification": {
        "exists": False,
        "readable": False,
        "owner": "",
        "path_normalized": "",
        "verified_at": captured_at,
        "verification_result": "BLOCKED",
        "reason": "visible destination could not be resolved as a readable existing user-facing directory",
    },
}
delivery["visible_artifact_deliveries"].append(entry)
delivery["last_visible_artifact_delivery_at"] = captured_at
delivery["last_visible_artifact_delivery_result"] = "BLOCKED"
task.setdefault("outputs", []).append(
    {
        "kind": "visible-artifact-delivery",
        "captured_at": captured_at,
        "exit_code": 2,
        "content": f"VISIBLE_ARTIFACT_DELIVERY_BLOCKED target={delivery_target} source={source_path}",
        "delivery_target": delivery_target,
        "source_artifact_path": source_path,
        "requested_filename": filename,
        "verification_result": "BLOCKED",
        "resolution_output": resolution_output,
        "verification_result_detail": entry["verification"],
    }
)
task.setdefault("notes", []).append(
    f"visible artifact delivery blocked for target {delivery_target}: unresolved or unreadable visible destination"
)
task["updated_at"] = captured_at

print(json.dumps(task, indent=2, ensure_ascii=True))
PY
  mv "$tmp_path" "$task_path"
  trap - EXIT
  if [ "$output_json" = "1" ]; then
    python3 - "$task_path" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
entry = (task.get("delivery") or {}).get("visible_artifact_deliveries", [])[-1]
print(json.dumps(entry, ensure_ascii=True))
PY
  else
    printf 'VISIBLE_ARTIFACT_DELIVERY_BLOCKED %s target=%s source=%s\n' "$task_id" "$delivery_target" "$source_path"
  fi
  exit 2
fi

resolved_path="$(python3 - "$resolution_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("resolved_path", ""))
PY
)"

actual_destination_path="$resolved_path"
if [ -n "${GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_ACTUAL_PATH:-}" ]; then
  actual_destination_path="${GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_ACTUAL_PATH}"
fi

mkdir -p "$(dirname "$actual_destination_path")"
set +e
copy_output="$(cp "$source_path" "$actual_destination_path" 2>&1)"
copy_exit="$?"
set -e

if [ "$copy_exit" -ne 0 ]; then
  persist_copy_blocked "$task_path" "$source_path" "$delivery_target" "$filename" "$captured_at" "$resolution_json" "$resolved_path" "$copy_output"
  if [ "$output_json" = "1" ]; then
    python3 - "$task_path" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
entry = (task.get("delivery") or {}).get("visible_artifact_deliveries", [])[-1]
print(json.dumps(entry, ensure_ascii=True))
PY
  else
    printf 'VISIBLE_ARTIFACT_DELIVERY_BLOCKED %s target=%s path=%s\n' "$task_id" "$delivery_target" "$resolved_path"
  fi
  exit 2
fi

reported_path="$resolved_path"
if [ -n "${GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_REPORTED_PATH:-}" ]; then
  reported_path="${GOLEM_VISIBLE_ARTIFACT_SIMULATE_DRIFT_REPORTED_PATH}"
fi

verification_json="$(python3 - "$reported_path" "$actual_destination_path" "$captured_at" <<'PY'
import json
import os
import pathlib
import pwd
import sys

reported_path = pathlib.Path(sys.argv[1]).expanduser()
actual_path = pathlib.Path(sys.argv[2]).expanduser()
captured_at = sys.argv[3]

try:
    normalized_reported = str(reported_path.resolve(strict=False))
except Exception:
    normalized_reported = ""

try:
    normalized_actual = str(actual_path.resolve(strict=False))
except Exception:
    normalized_actual = ""

exists = actual_path.exists()
readable = os.access(actual_path, os.R_OK) if exists else False

owner = ""
owner_matches_current_user = False
owner_check_reliable = True
if exists:
    try:
        stat_data = actual_path.stat()
        owner = pwd.getpwuid(stat_data.st_uid).pw_name
        owner_matches_current_user = owner == pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        owner_check_reliable = False
    except OSError:
        owner_check_reliable = False
else:
    owner_check_reliable = False

path_matches_report = normalized_reported == normalized_actual and normalized_reported != ""

result = "PASS"
reason = "visible artifact path verified"
if not exists or not readable:
    result = "FAIL"
    reason = "materialized artifact is missing or unreadable at the delivered path"
elif not owner_check_reliable:
    result = "BLOCKED"
    reason = "artifact owner could not be verified reliably"
elif not path_matches_report:
    result = "FAIL"
    reason = "reported visible path does not match the actual materialized path"
elif os.environ.get("GOLEM_VISIBLE_ARTIFACT_SIMULATE_UNVERIFIABLE", "").strip():
    result = "BLOCKED"
    reason = "verification was intentionally forced into an unverifiable state for reproducible blocking"

payload = {
    "exists": exists,
    "readable": readable,
    "owner": owner,
    "owner_matches_current_user": owner_matches_current_user,
    "owner_check_reliable": owner_check_reliable,
    "path_normalized": normalized_actual,
    "reported_path_normalized": normalized_reported,
    "path_matches_reported_path": path_matches_report,
    "verified_at": captured_at,
    "verification_result": result,
    "reason": reason,
}

print(json.dumps(payload, ensure_ascii=True))
PY
)"

verification_result="$(python3 - "$verification_json" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("verification_result", ""))
PY
)"

tmp_path="$(mktemp "$TASKS_DIR/.task-visible-artifact.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT
python3 - "$task_path" "$source_path" "$delivery_target" "$filename" "$captured_at" "$resolution_json" "$verification_json" "$reported_path" >"$tmp_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
source_path, delivery_target, filename, captured_at = sys.argv[2:6]
resolution = json.loads(sys.argv[6])
verification = json.loads(sys.argv[7])
reported_path = sys.argv[8]

task = json.loads(task_path.read_text(encoding="utf-8"))
delivery = task.setdefault("delivery", {})
delivery.setdefault("protocol_version", "1.0")
delivery.setdefault("minimum_user_facing_success_state", "visible")
delivery.setdefault("current_state", "")
delivery.setdefault("user_facing_ready", False)
delivery["visible_artifact_required"] = True
delivery.setdefault("visible_artifact_deliveries", [])
delivery.setdefault("transitions", [])
delivery.setdefault("claim_history", [])

entry = {
    "delivery_target": delivery_target,
    "requested_filename": filename,
    "source_artifact_path": source_path,
    "captured_at": captured_at,
    "selected_directory": resolution.get("absolute_directory", ""),
    "resolved_path": reported_path,
    "path_normalized": verification.get("path_normalized", ""),
    "resolution_reason": resolution.get("resolution_reason", ""),
    "verification_result": verification.get("verification_result", ""),
    "verified_at": verification.get("verified_at", ""),
    "verification": verification,
    "resolution": resolution,
}
delivery["visible_artifact_deliveries"].append(entry)
delivery["visible_artifact_ready"] = verification.get("verification_result") == "PASS"
delivery["last_visible_artifact_delivery_at"] = captured_at
delivery["last_visible_artifact_delivery_result"] = verification.get("verification_result", "")

exit_code_map = {"PASS": 0, "FAIL": 1, "BLOCKED": 2}
task.setdefault("outputs", []).append(
    {
        "kind": "visible-artifact-delivery",
        "captured_at": captured_at,
        "exit_code": exit_code_map.get(verification.get("verification_result", ""), 1),
        "content": (
            f"VISIBLE_ARTIFACT_DELIVERY_{verification.get('verification_result', 'FAIL')} "
            f"target={delivery_target} path={reported_path}"
        ),
        "delivery_target": delivery_target,
        "source_artifact_path": source_path,
        "requested_filename": filename,
        "resolved_path": reported_path,
        "path_normalized": verification.get("path_normalized", ""),
        "verification_result": verification.get("verification_result", ""),
        "verification_result_detail": verification,
    }
)
task.setdefault("artifacts", []).append(
    {
        "path": reported_path,
        "kind": "visible-artifact-delivery",
        "created_at": captured_at,
        "source_artifact_path": source_path,
        "delivery_target": delivery_target,
        "path_normalized": verification.get("path_normalized", ""),
        "verification_result": verification.get("verification_result", ""),
        "user_visible": True,
    }
)
task.setdefault("notes", []).append(
    f"visible artifact delivery {verification.get('verification_result', 'FAIL').lower()} for target {delivery_target}"
)
task["updated_at"] = captured_at

print(json.dumps(task, indent=2, ensure_ascii=True))
PY
mv "$tmp_path" "$task_path"
trap - EXIT

if [ "$output_json" = "1" ]; then
  python3 - "$task_path" <<'PY'
import json
import pathlib
import sys
task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
entry = (task.get("delivery") or {}).get("visible_artifact_deliveries", [])[-1]
print(json.dumps(entry, ensure_ascii=True))
PY
else
  printf 'VISIBLE_ARTIFACT_DELIVERY_%s %s target=%s path=%s\n' "$verification_result" "$task_id" "$delivery_target" "$reported_path"
fi

case "$verification_result" in
  PASS) exit 0 ;;
  BLOCKED) exit 2 ;;
  *) exit 1 ;;
esac
