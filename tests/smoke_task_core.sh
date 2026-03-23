#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
task_id=""
artifact_abs=""

cleanup() {
  if [[ -n "$artifact_abs" && -f "$artifact_abs" ]]; then
    rm -f "$artifact_abs"
  fi
  if [[ -n "$task_id" && -f "$TASKS_DIR/$task_id.json" ]]; then
    rm -f "$TASKS_DIR/$task_id.json"
  fi
}
trap cleanup EXIT

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR" "$OUTBOX_DIR"

created_output="$(./scripts/task_create.sh "Smoke task core" "Smoke task core" --type smoke-task-core --owner system --source script)"
printf '%s\n' "$created_output"

task_id="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_id" ] || {
  echo "ERROR: no se pudo extraer task_id" >&2
  exit 1
}

./scripts/task_add_output.sh "$task_id" smoke-output 0 "smoke output recorded"

artifact_rel="outbox/manual/$(date -u +%Y%m%dT%H%M%SZ)-smoke-task-core.md"
artifact_abs="$REPO_ROOT/$artifact_rel"

cat >"$artifact_abs" <<EOF
# Smoke Task Core Artifact

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT
task_type: smoke-task-core

## Summary
- smoke test artifact for task core validation

## Results
- task_id: $task_id
- output_kind: smoke-output

## Notes
- generated without touching live OpenClaw state
EOF

./scripts/validate_markdown_artifact.sh "$artifact_abs"
./scripts/task_add_artifact.sh "$task_id" smoke-artifact "$artifact_rel"
./scripts/task_close.sh "$task_id" done "smoke task core completed"

summary_output="$(./scripts/task_summary.sh "$task_id")"
printf '%s\n' "$summary_output"

python3 - "$TASKS_DIR/$task_id.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert len(task["outputs"]) == 1, task["outputs"]
assert len(task["artifacts"]) == 1, task["artifacts"]
assert task["outputs"][0]["kind"] == "smoke-output", task["outputs"][0]
artifact_entry = task["artifacts"][0]
if isinstance(artifact_entry, str):
    assert artifact_entry.endswith("-smoke-task-core.md"), artifact_entry
else:
    assert artifact_entry["path"].endswith("-smoke-task-core.md"), artifact_entry
PY

printf 'SMOKE_TASK_CORE_OK\n'
