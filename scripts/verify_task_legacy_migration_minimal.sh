#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TMPDIR="$(mktemp -d)"
LEGACY_PATH="$REPO_ROOT/tasks/task-legacy-verify.json"
MIGRATED_PATH=""
BACKUP_GLOB="$REPO_ROOT/tasks/legacy_backup/task-legacy-verify.json.bak."*

cleanup() {
  rm -rf "$TMPDIR"
  [[ -f "$LEGACY_PATH" ]] && rm -f "$LEGACY_PATH"
  [[ -n "$MIGRATED_PATH" && -f "$MIGRATED_PATH" ]] && rm -f "$MIGRATED_PATH"
  rm -f $BACKUP_GLOB 2>/dev/null || true
}
trap cleanup EXIT

cat > "$LEGACY_PATH" <<'JSON'
{
  "task_id": "legacy-verify-001",
  "title": "Legacy verify task",
  "status": "in_progress",
  "owner": "legacy-worker",
  "source": "worker",
  "notes": "Legacy note",
  "artifacts": [
    {
      "kind": "doc",
      "path": "docs/OLD_LEGACY_DOC.md",
      "created_at": "2026-03-20T00:00:00Z"
    }
  ]
}
JSON

SCAN_OUT="$TMPDIR/scan.out"
MIGRATE_OUT="$TMPDIR/migrate.out"
VALIDATE_OUT="$TMPDIR/validate.out"

./scripts/task_scan_legacy.sh "$LEGACY_PATH" > "$SCAN_OUT"
grep -q "^TASK_SCAN_LEGACY legacy-verify-001 " "$SCAN_OUT" || {
  echo "FAIL: scan did not classify synthetic task as legacy"
  exit 1
}

./scripts/task_migrate_legacy.sh "$LEGACY_PATH" --actor system > "$MIGRATE_OUT"

MIGRATED_ID="$(awk '/^TASK_MIGRATED /{print $3}' "$MIGRATE_OUT")"
MIGRATED_PATH="$(tail -n 1 "$MIGRATE_OUT")"

[[ -n "$MIGRATED_ID" ]] || { echo "FAIL: migrate did not return canonical id"; exit 1; }
[[ -f "$MIGRATED_PATH" ]] || { echo "FAIL: migrated path missing"; exit 1; }
[[ ! -f "$LEGACY_PATH" ]] || { echo "FAIL: legacy source still exists after migration"; exit 1; }

./scripts/task_validate.sh "$MIGRATED_PATH" --strict > "$VALIDATE_OUT"
grep -q "^TASK_VALID $MIGRATED_ID canonical " "$VALIDATE_OUT" || {
  echo "FAIL: migrated task did not validate strictly"
  exit 1
}

python3 - "$MIGRATED_ID" "$MIGRATED_PATH" "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
task_path = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3])

with task_path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

assert data["id"] == task_id, "id mismatch"
assert data["status"] == "running", "legacy in_progress should normalize to running"
assert data["owner"] == "legacy-worker", "owner mismatch"
assert data["source_channel"] == "worker", "source normalization mismatch"
assert isinstance(data.get("history"), list) and len(data["history"]) >= 2, "history too short"
assert data["history"][-1]["action"] == "migrated_from_legacy", "missing migration history action"

migration_evidence = [e for e in data.get("evidence", []) if isinstance(e, dict) and e.get("type") == "migration"]
assert migration_evidence, "migration evidence missing"

backup_rel = migration_evidence[-1]["path"]
backup_abs = repo_root / backup_rel
assert backup_abs.exists(), "backup file missing"

artifacts = data.get("artifacts", [])
assert isinstance(artifacts, list) and len(artifacts) == 1, "legacy artifacts should be preserved as list"

print("VERIFY_TASK_LEGACY_MIGRATION_JSON_OK")
PY

echo "VERIFY_TASK_LEGACY_MIGRATION_MINIMAL_OK"
