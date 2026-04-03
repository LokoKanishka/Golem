#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_panel_read.sh list [--status <status>] [--limit <n>]
./scripts/task_panel_read.sh show <task-id|path>
./scripts/task_panel_read.sh summary
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

STATUS_FILTER=""
LIMIT=""
SHOW_INPUT=""

while [[ $# -gt 0 ]]; do
  case "$COMMAND:$1" in
    list:--status)
      [[ $# -ge 2 ]] || usage
      STATUS_FILTER="$2"
      shift 2
      ;;
    list:--limit)
      [[ $# -ge 2 ]] || usage
      LIMIT="$2"
      shift 2
      ;;
    show:*)
      if [[ -n "$SHOW_INPUT" || "$1" == -* ]]; then
        usage
      fi
      SHOW_INPUT="$1"
      shift
      ;;
    summary:*)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

if [[ "$COMMAND" == "show" && -z "$SHOW_INPUT" ]]; then
  usage
fi

TASKS_DIR="$TASKS_DIR" \
COMMAND="$COMMAND" \
STATUS_FILTER="$STATUS_FILTER" \
LIMIT="$LIMIT" \
SHOW_INPUT="$SHOW_INPUT" \
python3 - <<'PY'
import json
import os
import pathlib
import re
import sys

tasks_dir = pathlib.Path(os.environ["TASKS_DIR"])
scripts_dir = (tasks_dir.parent / "scripts").resolve()
sys.path.insert(0, str(scripts_dir))

from task_host_verification_common import (
    build_host_evidence_summary,
    empty_host_evidence_summary,
    empty_host_verification_summary,
    evaluate_host_expectation,
    normalize_host_expectation,
)

command = os.environ["COMMAND"]
status_filter = os.environ["STATUS_FILTER"].strip()
limit_raw = os.environ["LIMIT"].strip()
show_input = os.environ["SHOW_INPUT"].strip()

status_enum = {
    "todo",
    "queued",
    "running",
    "blocked",
    "delegated",
    "worker_running",
    "done",
    "failed",
    "canceled",
    "cancelled",
}
source_enum = {"panel", "whatsapp", "operator", "script", "worker", "scheduled_process"}
id_re = re.compile(r"^task-\d{8}T\d{6}Z-[a-z0-9]{6,16}$")
required = [
    "id",
    "title",
    "objective",
    "status",
    "owner",
    "source_channel",
    "created_at",
    "updated_at",
    "acceptance_criteria",
    "evidence",
    "artifacts",
    "closure_note",
    "history",
]

default_delivery = {
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
}

default_media = {
    "protocol_version": "1.0",
    "required": False,
    "current_state": "none",
    "ready": False,
    "allowed_for_delivery": False,
    "items": [],
    "events": [],
    "last_event_at": "",
    "last_event_reason": "",
}

default_screenshot = {
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
}


def canonical_errors(data):
    errors = []
    for key in required:
        if key not in data:
            errors.append(f"missing:{key}")
    if errors:
        return errors

    if not isinstance(data["id"], str) or not id_re.match(data["id"]):
        errors.append("invalid:id")
    if not isinstance(data["title"], str) or not data["title"].strip():
        errors.append("invalid:title")
    if not isinstance(data["objective"], str) or not data["objective"].strip():
        errors.append("invalid:objective")
    if data["status"] not in status_enum:
        errors.append("invalid:status")
    if not isinstance(data["owner"], str) or not data["owner"].strip():
        errors.append("invalid:owner")
    if data["source_channel"] not in source_enum:
        errors.append("invalid:source_channel")
    if not isinstance(data["created_at"], str) or not data["created_at"].strip():
        errors.append("invalid:created_at")
    if not isinstance(data["updated_at"], str) or not data["updated_at"].strip():
        errors.append("invalid:updated_at")
    if not isinstance(data["acceptance_criteria"], list):
        errors.append("invalid:acceptance_criteria")
    if not isinstance(data["evidence"], list):
        errors.append("invalid:evidence")
    if not isinstance(data["artifacts"], list):
        errors.append("invalid:artifacts")
    if not isinstance(data["closure_note"], str):
        errors.append("invalid:closure_note")
    if not isinstance(data["history"], list) or len(data["history"]) < 1:
        errors.append("invalid:history")
    return errors


def load_task(path):
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    errors = canonical_errors(data)
    if errors:
        raise SystemExit(
            json.dumps(
                {
                    "error": "task_not_canonical",
                    "path": str(path),
                    "details": errors,
                },
                ensure_ascii=True,
                indent=2,
            )
        )
    normalized = dict(data)
    normalized["task_id"] = normalized.get("task_id") or normalized["id"]
    normalized["type"] = normalized.get("type", "")
    normalized["parent_task_id"] = normalized.get("parent_task_id", "")
    normalized["depends_on"] = normalized.get("depends_on") or []
    normalized["inputs"] = normalized.get("inputs") or []
    normalized["outputs"] = normalized.get("outputs") or []
    normalized["notes"] = normalized.get("notes") or []
    normalized["delivery"] = normalized.get("delivery") or json.loads(json.dumps(default_delivery))
    normalized["media"] = normalized.get("media") or json.loads(json.dumps(default_media))
    normalized["screenshot"] = normalized.get("screenshot") or json.loads(json.dumps(default_screenshot))
    normalized["host_evidence_summary"] = build_host_evidence_summary(normalized, tasks_dir.parent.resolve())
    normalized["host_expectation"] = normalize_host_expectation(normalized.get("host_expectation"))
    normalized["host_verification"] = evaluate_host_expectation(
        normalized["host_expectation"],
        normalized["host_evidence_summary"],
        evaluated_at=str((normalized.get("host_verification") or {}).get("last_evaluated_at") or (normalized.get("host_verification") or {}).get("evaluated_at") or ""),
        evaluated_by=str((normalized.get("host_verification") or {}).get("evaluated_by") or ""),
    ) if normalized["host_expectation"].get("present") else empty_host_verification_summary()
    return normalized


def find_task_path(input_value):
    candidate = pathlib.Path(input_value)
    if candidate.is_file():
        return candidate

    direct = tasks_dir / f"{input_value}.json"
    if direct.is_file():
        return direct

    nested = tasks_dir / input_value
    if nested.is_file():
        return nested

    raise SystemExit(
        json.dumps(
            {"error": "task_not_found", "task": input_value},
            ensure_ascii=True,
            indent=2,
        )
    )


def task_card(task):
    delivery = task.get("delivery") or {}
    whatsapp = delivery.get("whatsapp") or {}
    host_summary = task.get("host_evidence_summary") or empty_host_evidence_summary()
    host_expectation = task.get("host_expectation") or {}
    host_verification = task.get("host_verification") or empty_host_verification_summary()
    return {
        "id": task["id"],
        "task_id": task.get("task_id", task["id"]),
        "title": task["title"],
        "status": task["status"],
        "type": task.get("type", ""),
        "owner": task["owner"],
        "source_channel": task["source_channel"],
        "updated_at": task["updated_at"],
        "created_at": task["created_at"],
        "parent_task_id": task.get("parent_task_id", ""),
        "depends_on_count": len(task.get("depends_on") or []),
        "delivery_state": delivery.get("current_state", ""),
        "user_facing_ready": bool(delivery.get("user_facing_ready")),
        "whatsapp_delivery_state": whatsapp.get("current_state", ""),
        "host_evidence_present": bool(host_summary.get("present")),
        "host_last_attached_at": host_summary.get("last_attached_at", ""),
        "host_surface_category": host_summary.get("surface_category", ""),
        "host_surface_confidence": host_summary.get("surface_confidence", ""),
        "host_expectation_present": bool(host_expectation.get("present")),
        "host_verification_status": host_verification.get("status", ""),
        "host_verification_stale": bool(host_verification.get("stale")),
    }


if limit_raw:
    try:
        limit = int(limit_raw)
    except ValueError:
        print(json.dumps({"error": "invalid_limit", "value": limit_raw}, ensure_ascii=True, indent=2))
        raise SystemExit(2)
    if limit < 1:
        print(json.dumps({"error": "invalid_limit", "value": limit_raw}, ensure_ascii=True, indent=2))
        raise SystemExit(2)
else:
    limit = None

if command == "show":
    path = find_task_path(show_input)
    task = load_task(path)
    print(
        json.dumps(
            {
                "meta": {
                    "command": "show",
                    "repo_root": str(tasks_dir.parent),
                    "tasks_dir": str(tasks_dir),
                    "source_of_truth": "tasks/*.json",
                    "canonical_only": True,
                    "path": str(path),
                },
                "task": task,
            },
            ensure_ascii=True,
            indent=2,
        )
    )
    raise SystemExit(0)

task_files = sorted(tasks_dir.glob("task-*.json"))
tasks = []

for path in task_files:
    try:
        task = load_task(path)
    except FileNotFoundError:
        continue
    if status_filter and task["status"] != status_filter:
        continue
    tasks.append((path, task))

if command == "list":
    listed = [task_card(task) for _, task in tasks]
    if limit is not None:
      listed = listed[:limit]
    payload = {
        "meta": {
            "command": "list",
            "repo_root": str(tasks_dir.parent),
            "tasks_dir": str(tasks_dir),
            "source_of_truth": "tasks/*.json",
            "canonical_only": True,
            "status_filter": status_filter,
            "limit": limit,
            "returned": len(listed),
            "matched": len(tasks),
        },
        "tasks": listed,
    }
    print(json.dumps(payload, ensure_ascii=True, indent=2))
    raise SystemExit(0)

if command == "summary":
    counts = {status: 0 for status in sorted(status_enum)}
    owners = {}
    latest_updated_at = ""
    host_evidence_tasks = 0
    host_expectation_tasks = 0
    host_verification_counts = {}

    for _, task in tasks:
        counts[task["status"]] = counts.get(task["status"], 0) + 1
        owners[task["owner"]] = owners.get(task["owner"], 0) + 1
        if task["updated_at"] > latest_updated_at:
            latest_updated_at = task["updated_at"]
        if (task.get("host_evidence_summary") or {}).get("present"):
            host_evidence_tasks += 1
        if (task.get("host_expectation") or {}).get("present"):
            host_expectation_tasks += 1
            status = str((task.get("host_verification") or {}).get("status") or "")
            if status:
                host_verification_counts[status] = host_verification_counts.get(status, 0) + 1

    active_counts = {key: value for key, value in counts.items() if value > 0}
    top_owners = sorted(
        ({"owner": owner, "count": count} for owner, count in owners.items()),
        key=lambda item: (-item["count"], item["owner"]),
    )[:10]

    payload = {
        "meta": {
            "command": "summary",
            "repo_root": str(tasks_dir.parent),
            "tasks_dir": str(tasks_dir),
            "source_of_truth": "tasks/*.json",
            "canonical_only": True,
        },
        "inventory": {
            "total": len(tasks),
            "status_counts": active_counts,
            "latest_updated_at": latest_updated_at,
            "top_owners": top_owners,
            "host_evidence_tasks": host_evidence_tasks,
            "host_expectation_tasks": host_expectation_tasks,
            "host_verification_counts": host_verification_counts,
        },
    }
    print(json.dumps(payload, ensure_ascii=True, indent=2))
    raise SystemExit(0)

usage()
PY
