#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_create.sh "Title" "Objective" [--type <task_type>] [--owner <owner>] [--source <source_channel>] [--accept <criterion>]...

Examples:
./scripts/task_create.sh "Definir X" "Cerrar Y"
./scripts/task_create.sh "Definir X" "Cerrar Y" --type repo-analysis --owner diego --source panel
./scripts/task_create.sh "Definir X" "Cerrar Y" --accept "Existe doc" --accept "Verify pasa"

Optional compatibility env:
  TASK_PARENT_TASK_ID=<task_id_padre>
  TASK_DEPENDS_ON='["task-a","task-b"]'
  TASK_STEP_NAME=<step_name>
  TASK_STEP_ORDER=<numero>
  TASK_CRITICAL=true|false
  TASK_EXECUTION_MODE=local|worker
  TASK_CANONICAL_SESSION=<session>
  TASK_ORIGIN=<origin>
USAGE
  exit 1
}

[[ $# -ge 2 ]] || usage

TITLE="$1"
OBJECTIVE="$2"
shift 2

TASK_TYPE="${TASK_TYPE:-}"
OWNER="unassigned"
SOURCE_CHANNEL="operator"
declare -a ACCEPTANCE=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      [[ $# -ge 2 ]] || usage
      TASK_TYPE="$2"
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
TASK_TYPE="$TASK_TYPE" \
OWNER="$OWNER" \
SOURCE_CHANNEL="$SOURCE_CHANNEL" \
TASK_PARENT_TASK_ID="${TASK_PARENT_TASK_ID:-}" \
TASK_DEPENDS_ON="${TASK_DEPENDS_ON:-}" \
TASK_STEP_NAME="${TASK_STEP_NAME:-}" \
TASK_STEP_ORDER="${TASK_STEP_ORDER:-}" \
TASK_CRITICAL="${TASK_CRITICAL:-}" \
TASK_EXECUTION_MODE="${TASK_EXECUTION_MODE:-}" \
TASK_CANONICAL_SESSION="${TASK_CANONICAL_SESSION:-}" \
TASK_ORIGIN="${TASK_ORIGIN:-local}" \
python3 - "${ACCEPTANCE[@]}" <<'PY'
import datetime as dt
import json
import os
import pathlib
import secrets
import sys


def parse_depends_on(raw):
    raw = raw.strip()
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        parsed = [item.strip() for item in raw.split(",") if item.strip()]
    if not isinstance(parsed, list):
        raise SystemExit("TASK_DEPENDS_ON debe ser una lista JSON o una lista separada por comas")
    return [str(item).strip() for item in parsed if str(item).strip()]


def parse_bool(raw, env_name):
    raw = raw.strip().lower()
    if not raw:
        return None
    if raw in {"1", "true", "yes", "y", "on"}:
        return True
    if raw in {"0", "false", "no", "n", "off"}:
        return False
    raise SystemExit(f"{env_name} debe ser true/false")


tasks_dir = pathlib.Path(os.environ["TASK_PATH"])
title = os.environ["TITLE"]
objective = os.environ["OBJECTIVE"]
task_type = os.environ.get("TASK_TYPE", "").strip()
owner = os.environ["OWNER"]
source_channel = os.environ["SOURCE_CHANNEL"]
parent_task_id = os.environ.get("TASK_PARENT_TASK_ID", "").strip()
depends_on = parse_depends_on(os.environ.get("TASK_DEPENDS_ON", ""))
step_name = os.environ.get("TASK_STEP_NAME", "").strip()
step_order_raw = os.environ.get("TASK_STEP_ORDER", "").strip()
critical = parse_bool(os.environ.get("TASK_CRITICAL", ""), "TASK_CRITICAL")
execution_mode = os.environ.get("TASK_EXECUTION_MODE", "").strip()
canonical_session = os.environ.get("TASK_CANONICAL_SESSION", "").strip()
origin = os.environ.get("TASK_ORIGIN", "local").strip() or "local"
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
    "task_id": task_id,
    "type": task_type,
    "origin": origin,
    "canonical_session": canonical_session,
    "parent_task_id": parent_task_id,
    "depends_on": depends_on,
    "status": "todo",
    "owner": owner,
    "source_channel": source_channel,
    "created_at": iso_now,
    "updated_at": iso_now,
    "title": title,
    "objective": objective,
    "acceptance_criteria": acceptance,
    "inputs": [],
    "outputs": [],
    "evidence": [],
    "artifacts": [],
    "notes": [],
    "closure_note": "",
    "history": [
        {
            "at": iso_now,
            "actor": owner,
            "action": "created",
            "note": (
                f"Task created from source_channel={source_channel}"
                + (f" type={task_type}." if task_type else ".")
            ),
        }
    ],
    "delivery": {
        "protocol_version": "1.0",
        "minimum_user_facing_success_state": "visible",
        "current_state": "",
        "user_facing_ready": False,
        "visible_artifact_required": False,
        "visible_artifact_ready": False,
        "visible_artifact_deliveries": [],
        "whatsapp": {
            "protocol_version": "1.0",
            "required": False,
            "current_state": "",
            "delivery_confidence": "unknown",
            "allowed_claim_level": "",
            "allowed_user_facing_claim": "",
            "user_facing_ready": False,
            "tracked_message_id": "",
            "message_ids": [],
            "provider": "",
            "to": "",
            "run_id": "",
            "provider_delivery_status": "",
            "provider_delivery_reason": "",
            "provider_delivery_proof_at": "",
            "last_provider_evidence_at": "",
            "attempts": [],
            "claim_history": [],
        },
        "transitions": [],
        "claim_history": [],
    },
    "media": {
        "protocol_version": "1.0",
        "required": False,
        "current_state": "none",
        "ready": False,
        "allowed_for_delivery": False,
        "items": [],
        "events": [],
        "last_event_at": "",
        "last_event_reason": "",
    },
    "screenshot": {
        "protocol_version": "1.0",
        "required": False,
        "current_state": "none",
        "ready_for_claim": False,
        "items": [],
        "events": [],
        "last_transition_at": "",
        "last_verified_at": "",
        "block_reason": "",
        "fail_reason": "",
    },
}

if step_name:
    task["step_name"] = step_name
if step_order_raw:
    task["step_order"] = int(step_order_raw)
if critical is not None:
    task["critical"] = critical
if execution_mode:
    task["execution_mode"] = execution_mode

with path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, ensure_ascii=True, indent=2)
    fh.write("\n")

print(f"TASK_CREATED {task_id}")
print(path)
PY
