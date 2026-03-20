#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TMPDIR="$(mktemp -d)"
TASK_PATH=""

cleanup() {
  rm -rf "$TMPDIR"
  if [[ -n "$TASK_PATH" && -f "$TASK_PATH" ]]; then
    rm -f "$TASK_PATH"
  fi
}
trap cleanup EXIT

CREATE_OUT="$TMPDIR/create.out"
UPDATE_OUT="$TMPDIR/update.out"
CLOSE_OUT="$TMPDIR/close.out"
SHOW_OUT="$TMPDIR/show.out"

./scripts/task_create.sh \
  "Verify minimal task lifecycle" \
  "Comprobar create update close" \
  --owner unassigned \
  --source script \
  --accept "La tarea se crea" \
  > "$CREATE_OUT"

TASK_ID="$(awk '/^TASK_CREATED /{print $2}' "$CREATE_OUT")"
TASK_PATH="$(tail -n 1 "$CREATE_OUT")"

[[ -n "$TASK_ID" ]] || { echo "FAIL: no task id"; exit 1; }
[[ -f "$TASK_PATH" ]] || { echo "FAIL: task file missing"; exit 1; }

./scripts/task_update.sh "$TASK_ID" \
  --status running \
  --owner system \
  --append-accept "La tarea puede pasar a running" \
  --note "Inicio del lifecycle mínimo." \
  > "$UPDATE_OUT"

grep -q "^TASK_UPDATED $TASK_ID running$" "$UPDATE_OUT" || {
  echo "FAIL: task_update output mismatch"
  exit 1
}

./scripts/task_close.sh "$TASK_ID" done \
  --actor system \
  --note "Lifecycle mínimo verificado end to end." \
  > "$CLOSE_OUT"

grep -q "^TASK_CLOSED $TASK_ID done$" "$CLOSE_OUT" || {
  echo "FAIL: task_close output mismatch"
  exit 1
}

./scripts/task_show.sh "$TASK_ID" > "$SHOW_OUT"

python3 - "$TASK_ID" "$SHOW_OUT" <<'PY'
import json
import pathlib
import sys

task_id = sys.argv[1]
show_path = pathlib.Path(sys.argv[2])

with show_path.open("r", encoding="utf-8") as fh:
    data = json.load(fh)

assert data["id"] == task_id, "id mismatch"
assert data["status"] == "done", "final status should be done"
assert data["owner"] == "system", "owner should be updated to system"
assert data["closure_note"] == "Lifecycle mínimo verificado end to end.", "closure note mismatch"
assert len(data["acceptance_criteria"]) >= 2, "acceptance criteria should have been appended"
assert len(data["history"]) >= 3, "history should contain create/update/close"

actions = [item["action"] for item in data["history"]]
assert actions[0] == "created", "first action should be created"
assert "status_changed" in actions, "status_changed action missing"
assert actions[-1] == "closed_done", "last action should be closed_done"

print("VERIFY_TASK_LIFECYCLE_JSON_OK")
PY

echo "VERIFY_TASK_LIFECYCLE_MINIMAL_OK"
