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
EVIDENCE_OUT="$TMPDIR/evidence.out"
ARTIFACT_OUT="$TMPDIR/artifact.out"
SHOW_OUT="$TMPDIR/show.out"

./scripts/task_create.sh \
  "Verify evidence and artifacts" \
  "Comprobar agregado mínimo de evidencia y artifacts" \
  --owner system \
  --source script \
  --accept "La tarea se crea" \
  > "$CREATE_OUT"

TASK_ID="$(awk '/^TASK_CREATED /{print $2}' "$CREATE_OUT")"
TASK_PATH="$(tail -n 1 "$CREATE_OUT")"

[[ -n "$TASK_ID" ]] || { echo "FAIL: no task id"; exit 1; }
[[ -f "$TASK_PATH" ]] || { echo "FAIL: task file missing"; exit 1; }

./scripts/task_add_evidence.sh "$TASK_ID" \
  --type verify \
  --note "Verify mínimo ejecutado." \
  --command "./scripts/verify_task_evidence_artifacts_minimal.sh" \
  --result "pending-self-check" \
  --actor system \
  > "$EVIDENCE_OUT"

grep -q "^TASK_EVIDENCE_ADDED $TASK_ID$" "$EVIDENCE_OUT" || {
  echo "FAIL: task_add_evidence output mismatch"
  exit 1
}

./scripts/task_add_artifact.sh "$TASK_ID" \
  "docs/TASK_EVIDENCE_ARTIFACTS_MINIMAL.md" \
  --actor system \
  --note "Documento del tramo agregado como artifact." \
  > "$ARTIFACT_OUT"

grep -q "^TASK_ARTIFACT_ADDED $TASK_ID$" "$ARTIFACT_OUT" || {
  echo "FAIL: task_add_artifact output mismatch"
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
assert isinstance(data.get("evidence"), list), "evidence must be a list"
assert isinstance(data.get("artifacts"), list), "artifacts must be a list"
assert len(data["evidence"]) >= 1, "evidence should have at least one entry"
assert len(data["artifacts"]) >= 1, "artifacts should have at least one entry"

ev = data["evidence"][-1]
assert ev["type"] == "verify", "unexpected evidence type"
assert ev["note"] == "Verify mínimo ejecutado.", "unexpected evidence note"
assert ev["command"] == "./scripts/verify_task_evidence_artifacts_minimal.sh", "unexpected evidence command"

assert "docs/TASK_EVIDENCE_ARTIFACTS_MINIMAL.md" in data["artifacts"], "artifact missing"

actions = [item["action"] for item in data.get("history", [])]
assert "evidence_added" in actions, "history missing evidence_added"
assert "artifact_added" in actions, "history missing artifact_added"

print("VERIFY_TASK_EVIDENCE_ARTIFACTS_JSON_OK")
PY

echo "VERIFY_TASK_EVIDENCE_ARTIFACTS_MINIMAL_OK"
