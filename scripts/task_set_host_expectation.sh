#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_set_host_expectation.sh <task-id|path> [--target-kind <kind>] [--surface-category <category>] [--min-surface-confidence <uncertain|weak|moderate|strong>] [--require-summary] [--min-artifact-count <n>] [--require-structured-fields] [--note <note>] [--actor <actor>] [--json]
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

TARGET_KIND=""
SURFACE_CATEGORY=""
MIN_SURFACE_CONFIDENCE=""
REQUIRE_SUMMARY=0
MIN_ARTIFACT_COUNT=0
REQUIRE_STRUCTURED_FIELDS=0
NOTE=""
ACTOR="host-expectation"
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-kind)
      [[ $# -ge 2 ]] || usage
      TARGET_KIND="$2"
      shift 2
      ;;
    --surface-category)
      [[ $# -ge 2 ]] || usage
      SURFACE_CATEGORY="$2"
      shift 2
      ;;
    --min-surface-confidence)
      [[ $# -ge 2 ]] || usage
      MIN_SURFACE_CONFIDENCE="$2"
      shift 2
      ;;
    --require-summary)
      REQUIRE_SUMMARY=1
      shift
      ;;
    --min-artifact-count)
      [[ $# -ge 2 ]] || usage
      MIN_ARTIFACT_COUNT="$2"
      shift 2
      ;;
    --require-structured-fields)
      REQUIRE_STRUCTURED_FIELDS=1
      shift
      ;;
    --note)
      [[ $# -ge 2 ]] || usage
      NOTE="$2"
      shift 2
      ;;
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

[[ "$MIN_ARTIFACT_COUNT" =~ ^[0-9]+$ ]] || fail "min artifact count must be a non-negative integer"

set_result="$(
TARGET_KIND="$TARGET_KIND" \
SURFACE_CATEGORY="$SURFACE_CATEGORY" \
MIN_SURFACE_CONFIDENCE="$MIN_SURFACE_CONFIDENCE" \
REQUIRE_SUMMARY="$REQUIRE_SUMMARY" \
MIN_ARTIFACT_COUNT="$MIN_ARTIFACT_COUNT" \
REQUIRE_STRUCTURED_FIELDS="$REQUIRE_STRUCTURED_FIELDS" \
NOTE="$NOTE" \
ACTOR="$ACTOR" \
TASK_TARGET="$TASK_TARGET" \
REPO_ROOT="$REPO_ROOT" \
python3 - <<'PY'
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
target_kind = os.environ["TARGET_KIND"].strip()
surface_category = os.environ["SURFACE_CATEGORY"].strip()
min_surface_confidence = os.environ["MIN_SURFACE_CONFIDENCE"].strip()
require_summary = os.environ["REQUIRE_SUMMARY"] == "1"
min_artifact_count = int(os.environ["MIN_ARTIFACT_COUNT"])
require_structured_fields = os.environ["REQUIRE_STRUCTURED_FIELDS"] == "1"
note = os.environ["NOTE"]
actor = os.environ["ACTOR"] or "host-expectation"

if min_surface_confidence and min_surface_confidence not in {"uncertain", "weak", "moderate", "strong"}:
    raise SystemExit(f"invalid min surface confidence: {min_surface_confidence}")

if not any(
    [
        target_kind,
        surface_category,
        min_surface_confidence,
        require_summary,
        min_artifact_count > 0,
        require_structured_fields,
    ]
):
    raise SystemExit("host expectation requires at least one configured check")

with path.open(encoding="utf-8") as fh:
    task = json.load(fh)

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
iso_now = now.isoformat().replace("+00:00", "Z")

task["host_expectation"] = {
    "source": "host",
    "target_kind": target_kind,
    "surface_category": surface_category,
    "min_surface_confidence": min_surface_confidence,
    "require_summary": require_summary,
    "min_artifact_count": min_artifact_count,
    "require_structured_fields": require_structured_fields,
    "configured_at": iso_now,
    "configured_by": actor,
    "note": note,
}

host_summary = build_host_evidence_summary(task, repo_root)
expectation = normalize_host_expectation(task["host_expectation"])
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

task.setdefault("history", []).append(
    {
        "at": iso_now,
        "actor": actor,
        "action": "host_expectation_set",
        "note": "Host expectation configured and evaluated against the latest attached host evidence.",
    }
)
if note:
    task.setdefault("notes", []).append(note)
task["updated_at"] = iso_now

with path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

identifier = task.get("id") or task.get("task_id") or path.stem
print(f"TASK_HOST_EXPECTATION_SET {identifier} {verification['status']}")
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
    "TASK_HOST_EXPECTATION_SET "
    f"{task['id']} status={verification.get('status','')} reason={verification.get('reason','')}"
)
PY
fi
