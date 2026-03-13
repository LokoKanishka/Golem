#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_prepare_codex_handoff.sh <task_id>
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_id="${1:-}"
if [ -z "$task_id" ]; then
  usage
  fatal "falta task_id"
fi

task_path="$TASKS_DIR/${task_id}.json"
if [ ! -f "$task_path" ]; then
  fatal "no existe la tarea: $task_id"
fi

mkdir -p "$HANDOFFS_DIR"

packet_path="$HANDOFFS_DIR/${task_id}.md"
tmp_path="$(mktemp "$HANDOFFS_DIR/.handoff-packet.XXXXXX.tmp")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" >"$tmp_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task_id = task.get("task_id", task_path.stem)
status = task.get("status", "")
handoff = task.get("handoff")

if status != "delegated":
    print(f"ERROR: la tarea {task_id} no esta en estado delegated", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(handoff, dict):
    print(f"ERROR: la tarea {task_id} no tiene bloque handoff", file=sys.stderr)
    raise SystemExit(1)

def render_list(items):
    if not items:
        return "- (none)"
    lines = []
    for item in items:
        lines.append(f"- {item}")
    return "\n".join(lines)

def render_outputs(outputs):
    if not outputs:
        return "- (none)"
    lines = []
    for output in outputs:
        kind = output.get("kind", "unknown")
        exit_code = output.get("exit_code", "?")
        captured_at = output.get("captured_at", "")
        content = str(output.get("content", "")).strip()
        preview = content if len(content) <= 280 else content[:277] + "..."
        preview = preview.replace("\n", "\\n")
        lines.append(f"- kind: {kind}")
        lines.append(f"  exit_code: {exit_code}")
        if captured_at:
            lines.append(f"  captured_at: {captured_at}")
        lines.append(f"  content_preview: {preview or '(empty)'}")
    return "\n".join(lines)

def render_artifacts(artifacts):
    if not artifacts:
        return "- (none)"
    lines = []
    for artifact in artifacts:
        kind = artifact.get("kind", "unknown")
        path = artifact.get("path", "")
        created_at = artifact.get("created_at", "")
        lines.append(f"- kind: {kind}")
        lines.append(f"  path: {path}")
        if created_at:
            lines.append(f"  created_at: {created_at}")
    return "\n".join(lines)

required_present = handoff.get("required_fields_present", [])
missing_required = handoff.get("missing_required_fields", [])
notes = task.get("notes", [])
outputs = task.get("outputs", [])
artifacts = task.get("artifacts", [])

codex_goal = handoff.get("recommended_next_step", "prepare and execute the delegated task")

lines = [
    f"# Codex Handoff Packet: {task_id}",
    "",
    "## Task",
    f"- task_id: {task_id}",
    f"- type: {task.get('type', '')}",
    f"- title: {task.get('title', '')}",
    f"- objective: {task.get('objective', '')}",
    f"- status: {status}",
    f"- created_at: {task.get('created_at', '')}",
    f"- updated_at: {task.get('updated_at', '')}",
    "",
    "## Handoff",
    f"- delegated_to: {handoff.get('delegated_to', '')}",
    f"- delegated_at: {handoff.get('delegated_at', '')}",
    f"- rationale: {handoff.get('rationale', '')}",
    f"- recommended_next_step: {handoff.get('recommended_next_step', '')}",
    f"- source_status: {handoff.get('source_status', '')}",
    "",
    "## Required Fields Present",
    render_list(required_present),
    "",
    "## Missing Required Fields",
    render_list(missing_required),
    "",
    "## Notes",
    render_list(notes),
    "",
    "## Outputs",
    render_outputs(outputs),
    "",
    "## Artifacts",
    render_artifacts(artifacts),
    "",
    "## Codex Execution Goal",
    codex_goal,
]

print("\n".join(lines))
PY

mv "$tmp_path" "$packet_path"
trap - EXIT
printf 'HANDOFF_PACKET_OK %s\n' "${packet_path#$REPO_ROOT/}"
