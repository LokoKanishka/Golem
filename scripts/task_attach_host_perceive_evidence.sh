#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_attach_host_perceive_evidence.sh <task-id|path> [--actor <actor>] [--json]
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

ACTOR="host-task-bridge"
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

show_payload="$(./scripts/task_panel_read.sh show "$TASK_TARGET")"
TASK_ID="$(python3 - "$show_payload" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["task"]["id"])
PY
)"

[[ -n "$TASK_ID" ]] || fail "could not resolve canonical task id"

perceive_cmd=("./scripts/golem_host_perceive.sh" "snapshot" "--json")
host_payload="$("${perceive_cmd[@]}")"
meta_tmp="$(mktemp)"
trap 'rm -f "$meta_tmp"' EXIT

python3 - "$host_payload" "$REPO_ROOT" >"$meta_tmp" <<'PY'
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[2]).resolve()
scripts_dir = (repo_root / "scripts").resolve()
sys.path.insert(0, str(scripts_dir))

from task_host_verification_common import build_host_bridge_payload

payload = json.loads(sys.argv[1])
bridge_payload = build_host_bridge_payload(payload, repo_root, "perceive")
output_extra = dict(bridge_payload["output_extra"])
output_extra["bridge"] = "task_attach_host_perceive_evidence"

print("META\tevidence_path\t" + bridge_payload["evidence_path"])
print("META\tnote\t" + bridge_payload["note"])
print("META\tresult_json\t" + json.dumps(bridge_payload["result"], ensure_ascii=True, separators=(",", ":")))
print("META\toutput_extra_json\t" + json.dumps(output_extra, ensure_ascii=True, separators=(",", ":")))
for path in bridge_payload["artifact_paths"]:
    print("ARTIFACT\t" + path)
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

command_display="$(printf '%q ' "${perceive_cmd[@]}")"
command_display="${command_display% }"

./scripts/task_add_evidence.sh "$TASK_TARGET" \
  --type host-perceive \
  --note "${META[note]}" \
  --path "${META[evidence_path]}" \
  --command "$command_display" \
  --result "${META[result_json]}" \
  --actor "$ACTOR" >/dev/null

for artifact_path in "${ARTIFACTS[@]}"; do
  ./scripts/task_add_artifact.sh "$TASK_TARGET" "$artifact_path" \
    --actor "$ACTOR" \
    --note "Host perceive artifact attached through the canonical host->task bridge." >/dev/null
done

TASK_OUTPUT_EXTRA_JSON="${META[output_extra_json]}" \
  ./scripts/task_add_output.sh "$TASK_ID" host-perceive-evidence 0 \
  "TASK_HOST_PERCEIVE_EVIDENCE_ATTACHED $TASK_ID" >/dev/null

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
                "bridge": "task_attach_host_perceive_evidence",
                "source_of_truth": "tasks/*.json",
                "canonical_only": True,
                "host_capture_lane": "golem_host_perceive",
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
  printf 'TASK_HOST_PERCEIVE_EVIDENCE_ATTACHED %s target=%s source_kind=%s\n' \
    "$TASK_ID" \
    "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("target_kind",""))' "${META[result_json]}")" \
    "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("source_kind",""))' "${META[result_json]}")"
fi
