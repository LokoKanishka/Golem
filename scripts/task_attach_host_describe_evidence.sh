#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_attach_host_describe_evidence.sh <task-id|path> desktop [--actor <actor>] [--json]
./scripts/task_attach_host_describe_evidence.sh <task-id|path> active-window [--actor <actor>] [--json]
./scripts/task_attach_host_describe_evidence.sh <task-id|path> window (--title <substring> | --window-id <id>) [--actor <actor>] [--json]
USAGE
  exit 1
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 2 ]] || usage

TASK_INPUT="$1"
shift
TARGET_MODE="$1"
shift

ACTOR="host-task-bridge"
OUTPUT_JSON=0
WINDOW_TITLE=""
WINDOW_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor)
      [[ $# -ge 2 ]] || usage
      ACTOR="$2"
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
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

case "$TARGET_MODE" in
  desktop|active-window)
    [[ -z "$WINDOW_TITLE" && -z "$WINDOW_ID" ]] || usage
    ;;
  window)
    if [[ -n "$WINDOW_TITLE" && -n "$WINDOW_ID" ]]; then
      fail "choose either --title or --window-id, not both"
    fi
    if [[ -z "$WINDOW_TITLE" && -z "$WINDOW_ID" ]]; then
      fail "window mode requires --title or --window-id"
    fi
    ;;
  *)
    usage
    ;;
esac

if [[ -f "$TASK_INPUT" ]]; then
  TASK_TARGET="$TASK_INPUT"
elif [[ -f "$TASKS_DIR/$TASK_INPUT.json" ]]; then
  TASK_TARGET="$TASKS_DIR/$TASK_INPUT.json"
elif [[ -f "$TASKS_DIR/$TASK_INPUT" ]]; then
  TASK_TARGET="$TASKS_DIR/$TASK_INPUT"
else
  fail "task not found: $TASK_INPUT"
fi

show_payload="$(./scripts/task_panel_read.sh show "$TASK_TARGET")"
TASK_ID="$(python3 - "$show_payload" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["task"]["id"])
PY
)"

[[ -n "$TASK_ID" ]] || fail "could not resolve canonical task id"

describe_cmd=("./scripts/golem_host_describe.sh" "$TARGET_MODE")
if [[ "$TARGET_MODE" == "window" ]]; then
  if [[ -n "$WINDOW_TITLE" ]]; then
    describe_cmd+=(--title "$WINDOW_TITLE")
  else
    describe_cmd+=(--window-id "$WINDOW_ID")
  fi
fi
describe_cmd+=(--json)

host_payload="$("${describe_cmd[@]}")"
meta_tmp="$(mktemp)"
trap 'rm -f "$meta_tmp"' EXIT

python3 - "$host_payload" "$REPO_ROOT" >"$meta_tmp" <<'PY'
import json
import pathlib
import sys

payload = json.loads(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2]).resolve()
description = payload["description"]
surface = description["surface_classification"]
structured = description["structured_fields"]
bundle = description["surface_state_bundle"]
artifacts = payload["artifacts"]

def repo_relative(raw: str) -> str:
    path = pathlib.Path(raw).expanduser()
    resolved = path.resolve(strict=False)
    try:
        return str(resolved.relative_to(repo_root))
    except Exception:
        return str(resolved)

summary = " ".join(str(description.get("summary") or "").split())
note = (
    f"source=host capture_lane=golem_host_describe target={payload['target']['kind']} "
    f"surface={surface.get('category')}/{surface.get('confidence')}. {summary}"
).strip()
result = {
    "source": "host",
    "capture_lane": "golem_host_describe",
    "target_kind": payload["target"]["kind"],
    "run_dir": payload["run_dir"],
    "surface_category": surface.get("category", ""),
    "surface_label": surface.get("label", ""),
    "surface_confidence": surface.get("confidence", ""),
    "summary": summary,
    "non_empty_structured_fields": structured.get("non_empty_fields", []),
    "non_empty_fine_fields": structured.get("non_empty_fine_fields", []),
    "non_empty_contextual_refinements": structured.get("non_empty_contextual_refinements", []),
    "non_empty_surface_state_fields": bundle.get("non_empty_fields", []),
}
output_extra = {
    "source": "host",
    "bridge": "task_attach_host_describe_evidence",
    "target_kind": payload["target"]["kind"],
    "run_dir": payload["run_dir"],
    "surface_category": surface.get("category", ""),
    "surface_confidence": surface.get("confidence", ""),
}

primary_artifacts = [
    artifacts.get("summary", ""),
    artifacts.get("description", ""),
    artifacts.get("sources", ""),
    artifacts.get("target_screenshot", ""),
    artifacts.get("surface_profile", ""),
    artifacts.get("structured_fields", ""),
    artifacts.get("surface_state_bundle", ""),
]

print("META\tmanifest_path\t" + repo_relative(payload["artifacts"]["description"]).replace("description.json", "manifest.json"))
print("META\tevidence_path\t" + repo_relative(payload["artifacts"]["description"]).replace("description.json", "manifest.json"))
print("META\tnote\t" + note)
print("META\tresult_json\t" + json.dumps(result, ensure_ascii=True, separators=(",", ":")))
print("META\toutput_extra_json\t" + json.dumps(output_extra, ensure_ascii=True, separators=(",", ":")))
for path in primary_artifacts:
    if path:
        print("ARTIFACT\t" + repo_relative(path))
PY

declare -A META=()
declare -a ARTIFACTS=()

while IFS=$'\t' read -r kind key value; do
  if [[ "$kind" == "META" ]]; then
    META["$key"]="$value"
  elif [[ "$kind" == "ARTIFACT" ]]; then
    ARTIFACTS+=("$key")
  fi
done <"$meta_tmp"

[[ -n "${META[evidence_path]:-}" ]] || fail "failed to derive host evidence manifest path"
[[ -n "${META[note]:-}" ]] || fail "failed to derive host evidence note"
[[ -n "${META[result_json]:-}" ]] || fail "failed to derive host evidence result json"
[[ -n "${META[output_extra_json]:-}" ]] || fail "failed to derive host evidence output json"

command_display="$(printf '%q ' "${describe_cmd[@]}")"
command_display="${command_display% }"

./scripts/task_add_evidence.sh "$TASK_TARGET" \
  --type host-describe \
  --note "${META[note]}" \
  --path "${META[evidence_path]}" \
  --command "$command_display" \
  --result "${META[result_json]}" \
  --actor "$ACTOR" >/dev/null

for artifact_path in "${ARTIFACTS[@]}"; do
  ./scripts/task_add_artifact.sh "$TASK_TARGET" "$artifact_path" \
    --actor "$ACTOR" \
    --note "Host describe artifact attached through the canonical host->task bridge." >/dev/null
done

TASK_OUTPUT_EXTRA_JSON="${META[output_extra_json]}" \
  ./scripts/task_add_output.sh "$TASK_ID" host-describe-evidence 0 \
  "TASK_HOST_DESCRIBE_EVIDENCE_ATTACHED $TASK_ID target=$TARGET_MODE" >/dev/null

final_payload="$(./scripts/task_panel_read.sh show "$TASK_TARGET")"

if [[ "$OUTPUT_JSON" -eq 1 ]]; then
  python3 - "$final_payload" "${META[result_json]}" "${META[evidence_path]}" "$command_display" "${ARTIFACTS[@]}" <<'PY'
import json
import sys

task_payload = json.loads(sys.argv[1])
result = json.loads(sys.argv[2])
evidence_path = sys.argv[3]
command_display = sys.argv[4]
artifacts = sys.argv[5:]

print(
    json.dumps(
        {
            "meta": {
                "bridge": "task_attach_host_describe_evidence",
                "source_of_truth": "tasks/*.json",
                "canonical_only": True,
                "host_capture_lane": "golem_host_describe",
                "canonical_script_command": command_display,
                "evidence_path": evidence_path,
                "attached_artifacts": artifacts,
                "result": result,
            },
            "task": task_payload["task"],
        },
        ensure_ascii=True,
        indent=2,
    )
)
PY
else
  printf 'TASK_HOST_DESCRIBE_EVIDENCE_ATTACHED %s target=%s surface=%s confidence=%s\n' \
    "$TASK_ID" \
    "$TARGET_MODE" \
    "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("surface_category",""))' "${META[result_json]}")" \
    "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("surface_confidence",""))' "${META[result_json]}")"
fi
