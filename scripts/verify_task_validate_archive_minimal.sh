#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
  [[ -n "${CREATED_TASK_PATH:-}" && -f "${CREATED_TASK_PATH:-}" ]] && rm -f "$CREATED_TASK_PATH"
  [[ -n "${ARCHIVED_TASK_PATH:-}" && -f "${ARCHIVED_TASK_PATH:-}" ]] && rm -f "$ARCHIVED_TASK_PATH"
}
trap cleanup EXIT

CREATE_OUT="$TMPDIR/create.out"
VALIDATE1_OUT="$TMPDIR/validate1.out"
CLOSE_OUT="$TMPDIR/close.out"
ARCHIVE_OUT="$TMPDIR/archive.out"
VALIDATE2_OUT="$TMPDIR/validate2.out"

./scripts/task_create.sh \
  "Verify validate archive minimal" \
  "Comprobar validate y archive end to end" \
  --owner system \
  --source script \
  --accept "La tarea se crea" \
  > "$CREATE_OUT"

TASK_ID="$(awk '/^TASK_CREATED /{print $2}' "$CREATE_OUT")"
CREATED_TASK_PATH="$(tail -n 1 "$CREATE_OUT")"

[[ -n "$TASK_ID" ]] || { echo "FAIL: no task id"; exit 1; }
[[ -f "$CREATED_TASK_PATH" ]] || { echo "FAIL: created task missing"; exit 1; }

./scripts/task_validate.sh "$TASK_ID" --strict > "$VALIDATE1_OUT"
grep -q "^TASK_VALID $TASK_ID canonical " "$VALIDATE1_OUT" || {
  echo "FAIL: strict validation did not pass for fresh task"
  exit 1
}

./scripts/task_close.sh "$TASK_ID" done \
  --actor system \
  --note "Validate/archive verify completed." \
  > "$CLOSE_OUT"

grep -q "^TASK_CLOSED $TASK_ID done$" "$CLOSE_OUT" || {
  echo "FAIL: task_close output mismatch"
  exit 1
}

./scripts/task_archive.sh "$TASK_ID" \
  --actor system \
  --note "Archived by validate/archive verify." \
  > "$ARCHIVE_OUT"

grep -q "^TASK_ARCHIVED $TASK_ID done$" "$ARCHIVE_OUT" || {
  echo "FAIL: task_archive output mismatch"
  exit 1
}

ARCHIVED_TASK_PATH="$(tail -n 1 "$ARCHIVE_OUT")"
[[ -f "$ARCHIVED_TASK_PATH" ]] || { echo "FAIL: archived task missing"; exit 1; }
[[ ! -f "$CREATED_TASK_PATH" ]] || { echo "FAIL: original task still exists"; exit 1; }

./scripts/task_validate.sh "$ARCHIVED_TASK_PATH" --strict > "$VALIDATE2_OUT"
grep -q "^TASK_VALID $TASK_ID canonical " "$VALIDATE2_OUT" || {
  echo "FAIL: archived task did not validate strictly"
  exit 1
}

python3 - "$TASK_ID" "$ARCHIVED_TASK_PATH" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
path = pathlib.Path(sys.argv[2])

with path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

assert data["id"] == task_id, "id mismatch"
assert data["status"] == "done", "final status should remain done"
assert data["closure_note"] == "Validate/archive verify completed.", "closure note mismatch"
assert isinstance(data.get("history"), list) and len(data["history"]) >= 3, "history too short"
assert data["history"][-1]["action"] == "archived", "last history action should be archived"

print("VERIFY_TASK_VALIDATE_ARCHIVE_JSON_OK")
PY

echo "VERIFY_TASK_VALIDATE_ARCHIVE_MINIMAL_OK"
