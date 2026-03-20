#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
ARCHIVE_DIR="$TASKS_DIR/archive"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_migrate_legacy.sh <task-id|task_id|path> [--actor <actor>] [--dry-run]
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

INPUT="$1"
shift

ACTOR=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

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

TARGET="$(resolve_target "$INPUT")" || {
  echo "Task not found: $INPUT" >&2
  exit 2
}

TASK_TARGET="$TARGET" REPO_ROOT="$REPO_ROOT" ACTOR="$ACTOR" DRY_RUN="$DRY_RUN" python3 - <<'PY'
import datetime as dt
import json
import os
import pathlib
import re
import secrets

path = pathlib.Path(os.environ["TASK_TARGET"])
repo_root = pathlib.Path(os.environ["REPO_ROOT"])
actor_override = os.environ["ACTOR"]
dry_run = os.environ["DRY_RUN"] == "1"

id_re = re.compile(r"^task-\d{8}T\d{6}Z-[a-z0-9]{6,16}$")
source_enum = {"panel", "whatsapp", "operator", "script", "worker", "scheduled_process"}


def now_iso():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def make_task_id():
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    return f"task-{stamp}-{secrets.token_hex(4)}"


def normalize_status(value):
    mapping = {
        "todo": "todo",
        "pending": "todo",
        "new": "todo",
        "queued": "todo",
        "running": "running",
        "in_progress": "running",
        "in-progress": "running",
        "started": "running",
        "worker_running": "running",
        "blocked": "blocked",
        "on_hold": "blocked",
        "hold": "blocked",
        "done": "done",
        "completed": "done",
        "complete": "done",
        "success": "done",
        "closed": "done",
        "failed": "failed",
        "error": "failed",
        "errored": "failed",
        "canceled": "canceled",
        "cancelled": "canceled",
        "aborted": "canceled",
    }
    if not isinstance(value, str):
        return "todo"
    return mapping.get(value.strip().lower(), "todo")


def normalize_source(value):
    if not isinstance(value, str):
        return "operator"
    v = value.strip().lower()
    return v if v in source_enum else "operator"


def normalize_list(value):
    if isinstance(value, list):
        return value
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def normalize_history(raw, notes, fallback_at):
    out = []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, dict):
                out.append(
                    {
                        "at": item.get("at") or item.get("created_at") or fallback_at,
                        "actor": item.get("actor") or item.get("owner") or "legacy",
                        "action": item.get("action") or "legacy_event",
                        "note": item.get("note") or item.get("message") or "Legacy history item imported.",
                    }
                )
            elif isinstance(item, str) and item.strip():
                out.append(
                    {
                        "at": fallback_at,
                        "actor": "legacy",
                        "action": "legacy_event",
                        "note": item.strip(),
                    }
                )
    elif isinstance(raw, str) and raw.strip():
        out.append(
            {
                "at": fallback_at,
                "actor": "legacy",
                "action": "legacy_event",
                "note": raw.strip(),
            }
        )

    if isinstance(notes, list):
        for item in notes:
            if isinstance(item, str) and item.strip():
                out.append(
                    {
                        "at": fallback_at,
                        "actor": "legacy",
                        "action": "legacy_note",
                        "note": item.strip(),
                    }
                )
    elif isinstance(notes, str) and notes.strip():
        out.append(
            {
                "at": fallback_at,
                "actor": "legacy",
                "action": "legacy_note",
                "note": notes.strip(),
            }
        )

    return out


with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

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
already_canonical = (
    all(k in data for k in required)
    and isinstance(data.get("history"), list)
    and len(data.get("history", [])) >= 1
    and isinstance(data.get("id"), str)
    and bool(id_re.match(data["id"]))
)
if already_canonical:
    print(f"TASK_CANONICAL {data.get('id', path.stem)}")
    print(path)
    raise SystemExit(0)

legacy_ref = data.get("task_id") or data.get("id") or path.stem
created_at = data.get("created_at") or data.get("created") or data.get("timestamp") or now_iso()
updated_at = data.get("updated_at") or data.get("modified_at") or created_at
canonical_id = data.get("id") if isinstance(data.get("id"), str) and id_re.match(data["id"]) else None
if not canonical_id and isinstance(data.get("task_id"), str) and id_re.match(data["task_id"]):
    canonical_id = data["task_id"]
if not canonical_id:
    canonical_id = make_task_id()

title = data.get("title") or data.get("name") or f"Migrated legacy task {legacy_ref}"
objective = data.get("objective") or data.get("description") or data.get("goal") or title
status = normalize_status(data.get("status"))
owner = data.get("owner") or data.get("assignee") or "unassigned"
source_channel = normalize_source(data.get("source_channel") or data.get("source"))

acceptance = normalize_list(data.get("acceptance_criteria") or data.get("acceptance") or data.get("criteria"))
evidence = data.get("evidence") if isinstance(data.get("evidence"), list) else []
artifacts = data.get("artifacts") if isinstance(data.get("artifacts"), list) else normalize_list(data.get("artifact"))
closure_note = data.get("closure_note") or data.get("close_note") or ""
history = normalize_history(data.get("history"), data.get("notes"), created_at)

backup_dir = path.parent / "legacy_backup"
backup_dir.mkdir(parents=True, exist_ok=True)
backup_stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
backup_path = backup_dir / f"{path.name}.bak.{backup_stamp}.json"

migration_time = now_iso()
actor = actor_override or owner or "operator"

evidence = list(evidence)
evidence.append(
    {
        "type": "migration",
        "path": str(backup_path.relative_to(repo_root)),
        "note": f"Migrated from legacy representation. legacy_ref={legacy_ref}",
    }
)

history = list(history)
if not history:
    history.append(
        {
            "at": created_at,
            "actor": "legacy",
            "action": "legacy_imported",
            "note": f"Legacy task imported from raw representation. legacy_ref={legacy_ref}",
        }
    )

history.append(
    {
        "at": migration_time,
        "actor": actor,
        "action": "migrated_from_legacy",
        "note": f"Migrated legacy task. legacy_ref={legacy_ref}; backup={backup_path.relative_to(repo_root)}",
    }
)

canonical = {
    "id": canonical_id,
    "title": str(title),
    "objective": str(objective),
    "status": status,
    "owner": str(owner),
    "source_channel": source_channel,
    "created_at": str(created_at),
    "updated_at": migration_time,
    "acceptance_criteria": acceptance,
    "evidence": evidence,
    "artifacts": artifacts,
    "closure_note": str(closure_note),
    "history": history,
}

dest = path.parent / f"{canonical_id}.json"
if dest.exists() and dest != path:
    raise SystemExit(f"Refusing to overwrite existing canonical destination: {dest}")

if dry_run:
    print(f"TASK_WOULD_MIGRATE {legacy_ref} {canonical_id}")
    print(dest)
    raise SystemExit(0)

with backup_path.open("w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

tmp_dest = dest.with_suffix(dest.suffix + ".tmp")
with tmp_dest.open("w", encoding="utf-8") as fh:
    json.dump(canonical, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
tmp_dest.replace(dest)

if dest != path and path.exists():
    path.unlink()

print(f"TASK_MIGRATED {legacy_ref} {canonical_id}")
print(dest)
PY
