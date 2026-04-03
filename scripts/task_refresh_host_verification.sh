#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_refresh_host_verification.sh <task-id|path> [--refresh-host <desktop|active-window|window>] [--title <substring>] [--window-id <id>] [--actor <actor>] [--json]
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

REFRESH_HOST=""
WINDOW_TITLE=""
WINDOW_ID=""
ACTOR="host-refresh"
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh-host)
      [[ $# -ge 2 ]] || usage
      REFRESH_HOST="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || usage
      WINDOW_TITLE="$2"
      shift 2
      ;;
    --window-id)
      [[ $# -ge 2 ]] || usage
      WINDOW_ID="$2"
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

python3 - "$TASK_TARGET" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
task = json.loads(path.read_text(encoding="utf-8"))
expectation = task.get("host_expectation") or {}
checks = any(
    [
        expectation.get("target_kind"),
        expectation.get("surface_category"),
        expectation.get("min_surface_confidence"),
        expectation.get("require_summary"),
        int(expectation.get("min_artifact_count") or 0) > 0,
        expectation.get("require_structured_fields"),
    ]
)
if not checks:
    raise SystemExit("task has no configured host expectation to refresh")
PY

if [[ -n "$REFRESH_HOST" ]]; then
  attach_cmd=("./scripts/task_attach_host_describe_evidence.sh" "$TASK_TARGET" "$REFRESH_HOST" --actor "$ACTOR")
  if [[ "$REFRESH_HOST" == "window" ]]; then
    if [[ -n "$WINDOW_TITLE" && -n "$WINDOW_ID" ]]; then
      fail "choose either --title or --window-id, not both"
    fi
    if [[ -z "$WINDOW_TITLE" && -z "$WINDOW_ID" ]]; then
      fail "window refresh requires --title or --window-id"
    fi
    if [[ -n "$WINDOW_TITLE" ]]; then
      attach_cmd+=(--title "$WINDOW_TITLE")
    else
      attach_cmd+=(--window-id "$WINDOW_ID")
    fi
  else
    [[ -z "$WINDOW_TITLE" && -z "$WINDOW_ID" ]] || usage
  fi
  "${attach_cmd[@]}" >/dev/null
fi

eval_payload="$(./scripts/task_evaluate_host_expectation.sh "$TASK_TARGET" --actor "$ACTOR" --json)"

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  python3 - "$eval_payload" "$REFRESH_HOST" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
refresh_host = sys.argv[2]
task = payload["task"]
verification = task.get("host_verification") or {}

print(
    json.dumps(
        {
            "meta": {
                "bridge": "task_refresh_host_verification",
                "refreshed_host_evidence": bool(refresh_host),
                "refresh_target": refresh_host,
                "verification_status": verification.get("status", ""),
                "verification_reason": verification.get("reason", ""),
                "source_of_truth": "tasks/*.json",
                "canonical_only": True,
            },
            "task": task,
        },
        ensure_ascii=True,
        indent=2,
    )
)
PY
else
  python3 - "$eval_payload" "$REFRESH_HOST" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
refresh_host = sys.argv[2]
task = payload["task"]
verification = task.get("host_verification") or {}
print(
    "TASK_HOST_VERIFICATION_REFRESHED "
    f"{task['id']} status={verification.get('status','')} "
    f"refreshed_host_evidence={'yes' if refresh_host else 'no'}"
)
PY
fi
