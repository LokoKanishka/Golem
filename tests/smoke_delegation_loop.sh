#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"

cd "$REPO_ROOT"
mkdir -p "$TASKS_DIR" "$HANDOFFS_DIR" "$OUTBOX_DIR"

created_output="$(./scripts/task_new.sh repo-analysis "Smoke delegation loop")"
printf '%s\n' "$created_output"

task_path="$(printf '%s\n' "$created_output" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_path" ] || {
  echo "ERROR: no se pudo extraer task_path" >&2
  exit 1
}
task_id="$(basename "$task_path" .json)"

./scripts/task_delegate.sh "$task_id"
./scripts/task_prepare_codex_handoff.sh "$task_id"
./scripts/task_prepare_codex_ticket.sh "$task_id"

./scripts/validate_markdown_artifact.sh "$HANDOFFS_DIR/$task_id.md"
./scripts/validate_markdown_artifact.sh "$HANDOFFS_DIR/$task_id.codex.md"

artifact_rel="outbox/manual/$(date -u +%Y%m%dT%H%M%SZ)-${task_id}-delegation-smoke.md"
artifact_abs="$REPO_ROOT/$artifact_rel"

cat >"$artifact_abs" <<EOF
# Delegation Smoke Result

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT
task_type: repo-analysis
task_id: $task_id

## Summary
- delegation loop smoke result

## Findings
- handoff generated
- codex ticket generated
- manual worker result can be recorded

## Notes
- no external APIs were called
EOF

./scripts/task_record_worker_result.sh "$task_id" done "Smoke delegation loop completed" --artifact "$artifact_abs"

summary_output="$(./scripts/task_worker_summary.sh "$task_id")"
printf '%s\n' "$summary_output"

python3 - "$TASKS_DIR/$task_id.json" <<'PY'
import json
import pathlib
import sys

task = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert task["status"] == "done", task["status"]
assert task["handoff"]["delegated_to"] == "worker_future", task["handoff"]
assert task["outputs"][-1]["kind"] == "worker-result", task["outputs"][-1]
assert task["outputs"][-1]["status"] == "done", task["outputs"][-1]
assert len(task["artifacts"]) >= 1, task["artifacts"]
PY

printf 'SMOKE_DELEGATION_LOOP_OK\n'
