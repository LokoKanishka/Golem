#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
ARCHIVE_DIR="$TASKS_DIR/archive"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_validate.sh <task-id|path> [--strict]
./scripts/task_validate.sh --all [--strict] [--include-archive]
USAGE
  exit 1
}

STRICT=0
INCLUDE_ARCHIVE=0
MODE="single"
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1
      shift
      ;;
    --include-archive)
      INCLUDE_ARCHIVE=1
      shift
      ;;
    --all)
      MODE="all"
      shift
      ;;
    -*)
      usage
      ;;
    *)
      if [[ -n "$INPUT" ]]; then
        usage
      fi
      INPUT="$1"
      shift
      ;;
  esac
done

if [[ "$MODE" == "single" && -z "$INPUT" ]]; then
  usage
fi

declare -a TARGETS=()

if [[ "$MODE" == "single" ]]; then
  if [[ -f "$INPUT" ]]; then
    TARGETS=("$INPUT")
  elif [[ -f "$TASKS_DIR/$INPUT.json" ]]; then
    TARGETS=("$TASKS_DIR/$INPUT.json")
  elif [[ -f "$TASKS_DIR/$INPUT" ]]; then
    TARGETS=("$TASKS_DIR/$INPUT")
  elif [[ -f "$ARCHIVE_DIR/$INPUT.json" ]]; then
    TARGETS=("$ARCHIVE_DIR/$INPUT.json")
  elif [[ -f "$ARCHIVE_DIR/$INPUT" ]]; then
    TARGETS=("$ARCHIVE_DIR/$INPUT")
  else
    echo "Task not found: $INPUT" >&2
    exit 2
  fi
else
  while IFS= read -r -d '' file; do
    TARGETS+=("$file")
  done < <(find "$TASKS_DIR" -maxdepth 1 -type f -name 'task-*.json' -print0 | sort -z)
  if [[ "$INCLUDE_ARCHIVE" -eq 1 ]]; then
    while IFS= read -r -d '' file; do
      TARGETS+=("$file")
    done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name 'task-*.json' -print0 2>/dev/null | sort -z)
  fi
fi

STRICT="$STRICT" python3 - "${TARGETS[@]}" <<'PY'
import json
import os
import pathlib
import re
import sys

strict = os.environ["STRICT"] == "1"
paths = [pathlib.Path(p) for p in sys.argv[1:]]

if not paths:
    print("VALIDATE_SUMMARY total=0 valid=0 legacy=0 invalid=0")
    raise SystemExit(0)

status_enum = {"todo", "queued", "running", "blocked", "delegated", "worker_running", "done", "failed", "canceled", "cancelled"}
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


def legacy_compatible(data):
    if not isinstance(data, dict):
        return False
    legacy_id = data.get("task_id") or data.get("id")
    return (
        isinstance(legacy_id, str)
        and bool(legacy_id.strip())
        and isinstance(data.get("title"), str)
        and bool(data.get("title").strip())
        and isinstance(data.get("status"), str)
        and bool(data.get("status").strip())
    )


valid = 0
legacy = 0
invalid = 0

for path in paths:
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        invalid += 1
        print(f"TASK_INVALID_JSON {path} {exc}")
        continue

    errors = canonical_errors(data)
    identifier = data.get("id") or data.get("task_id") or path.name
    if not errors:
        valid += 1
        print(f"TASK_VALID {identifier} canonical {path}")
        continue

    if not strict and legacy_compatible(data):
        legacy += 1
        print(f"TASK_VALID_LEGACY {identifier} legacy-compatible {path}")
        continue

    invalid += 1
    print(f"TASK_INVALID {identifier} {';'.join(errors)} {path}")

print(f"VALIDATE_SUMMARY total={len(paths)} valid={valid} legacy={legacy} invalid={invalid}")
raise SystemExit(1 if invalid else 0)
PY
