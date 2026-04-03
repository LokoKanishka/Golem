#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_evaluate_host_expectation.sh <task-id|path> [--actor <actor>] [--json]
USAGE
  exit 1
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage

TASK_INPUT="$1"
shift

ACTOR="host-verification"
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -f "$TASK_INPUT" ]]; then
  TASK_TARGET="$TASK_INPUT"
elif [[ -f "$TASKS_DIR/$TASK_INPUT.json" ]]; then
  TASK_TARGET="$TASKS_DIR/$TASK_INPUT.json"
elif [[ -f "$TASKS_DIR/$TASK_INPUT" ]]; then
  TASK_TARGET="$TASKS_DIR/$TASK_INPUT"
else
  fail "task not found: $TASK_INPUT"
fi

eval_result="$(
ACTOR="$ACTOR" TASK_TARGET="$TASK_TARGET" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import datetime as dt
import json
import os
import pathlib
import sys

sys.path.insert(0, str((pathlib.Path(os.environ["REPO_ROOT"]) / "scripts").resolve()))

from task_host_verification_common import (
    build_host_evidence_summary,
    evaluate_host_expectation,
    normalize_host_expectation,
)

path = pathlib.Path(os.environ["TASK_TARGET"])
repo_root = pathlib.Path(os.environ["REPO_ROOT"]).resolve()
actor = os.environ["ACTOR"] or "host-verification"

with path.open(encoding="utf-8") as fh:
    task = json.load(fh)

expectation = normalize_host_expectation(task.get("host_expectation"))
if not expectation.get("present"):
    raise SystemExit("task has no host expectation configured")

host_summary = build_host_evidence_summary(task, repo_root)
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")
verification = evaluate_host_expectation(expectation, host_summary, evaluated_at=iso_now, evaluated_by=actor)

task["host_verification"] = {
    "evaluated_at": verification["last_evaluated_at"],
    "evaluated_by": verification["evaluated_by"],
    "status": verification["status"],
    "reason": verification["reason"],
    "mismatch_summary": verification["mismatch_summary"],
    "used_host_last_attached_at": verification["used_host_last_attached_at"],
    "target_kind": verification["target_kind"],
    "surface_category": verification["surface_category"],
    "surface_confidence": verification["surface_confidence"],
    "summary": verification["summary"],
    "evidence_path": verification["evidence_path"],
    "run_dir": verification["run_dir"],
    "artifact_count": verification["artifact_count"],
    "artifact_references": verification["artifact_references"],
    "matched_checks": verification["matched_checks"],
    "mismatch_checks": verification["mismatch_checks"],
    "insufficient_checks": verification["insufficient_checks"],
    "stale": verification["stale"],
}
task["updated_at"] = iso_now
task.setdefault("history", []).append(
    {
        "at": iso_now,
        "actor": actor,
        "action": "host_expectation_evaluated",
        "note": f"Host expectation evaluated with status={verification['status']}.",
    }
)

with path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

identifier = task.get("id") or task.get("task_id") or path.stem
print(f"TASK_HOST_VERIFICATION_UPDATED {identifier} {verification['status']}")
print(path)
PY
)"

show_payload="$(./scripts/task_panel_read.sh show "$TASK_TARGET")"

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  printf '%s\n' "$show_payload"
else
  python3 - "$show_payload" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
task = payload["task"]
verification = task.get("host_verification") or {}
print(
    "TASK_HOST_VERIFICATION_UPDATED "
    f"{task['id']} status={verification.get('status','')} reason={verification.get('reason','')}"
)
PY
fi
