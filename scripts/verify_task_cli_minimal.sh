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

TITLE="Verify minimal task CLI"
OBJECTIVE="Comprobar create list show"

CREATE_OUT="$TMPDIR/create.out"
./scripts/task_create.sh "$TITLE" "$OBJECTIVE" --owner system --source script --accept "La tarea se crea" > "$CREATE_OUT"

TASK_ID="$(awk '/^TASK_CREATED /{print $2}' "$CREATE_OUT")"
TASK_PATH="$(tail -n 1 "$CREATE_OUT")"

[[ -n "$TASK_ID" ]] || { echo "FAIL: no task id"; exit 1; }
[[ -f "$TASK_PATH" ]] || { echo "FAIL: task file not found"; exit 1; }

LIST_OUT="$TMPDIR/list.out"
./scripts/task_list.sh > "$LIST_OUT"
grep -q "$TASK_ID" "$LIST_OUT" || { echo "FAIL: task_list does not include created task"; exit 1; }

SHOW_OUT="$TMPDIR/show.out"
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
assert data["status"] == "todo", "unexpected initial status"
assert data["history"], "history must not be empty"
assert data["history"][0]["action"] == "created", "first history action must be created"
assert "acceptance_criteria" in data, "missing acceptance_criteria"
print("VERIFY_TASK_JSON_OK")
PY

echo "VERIFY_TASK_CLI_MINIMAL_OK"
