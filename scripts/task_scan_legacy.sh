#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
ARCHIVE_DIR="$TASKS_DIR/archive"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_scan_legacy.sh --all [--include-archive]
./scripts/task_scan_legacy.sh <task-id|task_id|path>
USAGE
  exit 1
}

MODE="single"
INPUT=""
INCLUDE_ARCHIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      MODE="all"
      shift
      ;;
    --include-archive)
      INCLUDE_ARCHIVE=1
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

resolve_target() {
  local input="$1"
  if [[ -f "$input" ]]; then
    printf '%s\n' "$input"
    return 0
  fi
  python3 - "$input" "$TASKS_DIR" "$ARCHIVE_DIR" <<'PY'
import json
import pathlib
import sys

needle = sys.argv[1]
tasks_dir = pathlib.Path(sys.argv[2])
archive_dir = pathlib.Path(sys.argv[3])

candidates = []
for base in (tasks_dir, archive_dir):
    if base.exists():
        candidates.extend(sorted(base.glob("task-*.json")))

for path in candidates:
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        continue
    if data.get("id") == needle or data.get("task_id") == needle or path.stem == needle:
        print(path)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

declare -a TARGETS=()
if [[ "$MODE" == "single" ]]; then
  TARGET="$(resolve_target "$INPUT")" || {
    echo "Task not found: $INPUT" >&2
    exit 2
  }
  TARGETS+=("$TARGET")
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

python3 - "${TARGETS[@]}" <<'PY'
import json
import pathlib
import re
import sys

paths = [pathlib.Path(p) for p in sys.argv[1:]]

id_re = re.compile(r"^task-\d{8}T\d{6}Z-[a-z0-9]{6,16}$")
status_enum = {"todo", "running", "blocked", "done", "failed", "canceled"}
source_enum = {"panel", "whatsapp", "operator", "script", "worker", "scheduled_process"}


def is_canonical(data):
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
    for key in required:
        if key not in data:
            return False
    if not isinstance(data.get("id"), str) or not id_re.match(data["id"]):
        return False
    if data.get("status") not in status_enum:
        return False
    if data.get("source_channel") not in source_enum:
        return False
    if not isinstance(data.get("history"), list) or len(data["history"]) < 1:
        return False
    return True


def is_legacy(data):
    if not isinstance(data, dict):
        return False
    return any(
        [
            isinstance(data.get("task_id"), str) and bool(data.get("task_id")),
            isinstance(data.get("id"), str) and bool(data.get("id")),
            isinstance(data.get("title"), str) and bool(data.get("title")),
            isinstance(data.get("status"), str) and bool(data.get("status")),
        ]
    )


canonical = 0
legacy = 0
corrupt = 0
invalid = 0

for path in paths:
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as exc:
        corrupt += 1
        print(f"TASK_SCAN_CORRUPT {path} {exc}")
        continue

    if is_canonical(data):
        canonical += 1
        print(f"TASK_SCAN_CANONICAL {data.get('id', path.stem)} {path}")
    elif is_legacy(data):
        legacy += 1
        ref = data.get("task_id") or data.get("id") or path.stem
        print(f"TASK_SCAN_LEGACY {ref} {path}")
    else:
        invalid += 1
        print(f"TASK_SCAN_INVALID {path}")

print(f"SCAN_SUMMARY total={len(paths)} canonical={canonical} legacy={legacy} corrupt={corrupt} invalid={invalid}")
PY
