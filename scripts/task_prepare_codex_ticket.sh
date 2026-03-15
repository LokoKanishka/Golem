#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"
EXPORT_HANDOFF_PACKET="$REPO_ROOT/scripts/task_export_worker_handoff.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_prepare_codex_ticket.sh <task_id>
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

handoff_packet_path="$HANDOFFS_DIR/${task_id}.md"
if [ ! -f "$handoff_packet_path" ]; then
  ./scripts/task_prepare_codex_handoff.sh "$task_id" >/dev/null
fi

ticket_path="$HANDOFFS_DIR/${task_id}.codex.md"
tmp_path="$(mktemp "$HANDOFFS_DIR/.codex-ticket.XXXXXX.md")"
trap 'rm -f "$tmp_path"' EXIT

python3 - "$task_path" "$handoff_packet_path" >"$tmp_path" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
handoff_packet_path = pathlib.Path(sys.argv[2])

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

if not handoff_packet_path.exists():
    print(f"ERROR: no existe handoff packet para {task_id}", file=sys.stderr)
    raise SystemExit(1)

def render_lines(title, items, fallback="(none)"):
    lines = [title]
    if not items:
        lines.append(f"- {fallback}")
        return lines
    for item in items:
        lines.append(f"- {item}")
    return lines

def render_outputs(outputs):
    lines = ["## Contexto: Outputs"]
    if not outputs:
        lines.append("- (none)")
        return lines
    for output in outputs:
        kind = output.get("kind", "unknown")
        exit_code = output.get("exit_code", "?")
        captured_at = output.get("captured_at", "")
        content = str(output.get("content", "")).strip()
        preview = content if len(content) <= 320 else content[:317] + "..."
        preview = preview.replace("\n", "\\n")
        lines.append(f"- kind: {kind}")
        lines.append(f"  exit_code: {exit_code}")
        if captured_at:
            lines.append(f"  captured_at: {captured_at}")
        lines.append(f"  content_preview: {preview or '(empty)'}")
    return lines

def render_artifacts(artifacts):
    lines = ["## Contexto: Artifacts"]
    if not artifacts:
        lines.append("- (none)")
        return lines
    for artifact in artifacts:
        lines.append(f"- kind: {artifact.get('kind', 'unknown')}")
        lines.append(f"  path: {artifact.get('path', '')}")
        created_at = artifact.get("created_at", "")
        if created_at:
            lines.append(f"  created_at: {created_at}")
    return lines

project = "Golem"
repo = "~/Escritorio/golem"
repo_abs = task_path.parent.parent.as_posix()
task_type = task.get("type", "")
title = task.get("title", "")
objective = task.get("objective", "")
notes = task.get("notes", [])
outputs = task.get("outputs", [])
artifacts = task.get("artifacts", [])
generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

goal = handoff.get("recommended_next_step", "resolver la tarea delegada de forma controlada")
rationale = handoff.get("rationale", "")
required_present = handoff.get("required_fields_present", [])
missing_required = handoff.get("missing_required_fields", [])

lines = [
    f"# Codex Ticket: {task_id}",
    "",
    f"generated_at: {generated_at}",
    f"repo: {repo_abs}",
    f"task_type: {task_type}",
    "",
    "## Header",
    f"- Proyecto: {project}",
    f"- Repo: {repo}",
    f"- task_id: {task_id}",
    f"- task_type: {task_type}",
    f"- title: {title}",
    f"- objective: {objective}",
    f"- status: {status}",
    "",
    "## Contexto",
    f"- rationale: {rationale}",
    f"- recommended_next_step: {goal}",
    f"- delegated_to: {handoff.get('delegated_to', '')}",
    f"- delegated_at: {handoff.get('delegated_at', '')}",
    "",
]

lines.extend(render_lines("## Contexto: Notes", notes))
lines.append("")
lines.extend(render_outputs(outputs))
lines.append("")
lines.extend(render_artifacts(artifacts))
lines.append("")
lines.extend(render_lines("## Contexto: Required Fields Present", required_present))
lines.append("")
lines.extend(render_lines("## Contexto: Missing Required Fields", missing_required))
lines.append("")
lines.append("## Instrucciones para Codex")
lines.append("Objetivo para Codex:")
lines.append(goal)
lines.append("")
lines.append("Usar como base adicional el handoff packet ya generado en el repo.")
lines.append("")
lines.append("## Restricciones")
lines.append("- trabajar solo dentro del repo golem")
lines.append("- no tocar ~/.openclaw")
lines.append("- no modificar config viva del gateway")
lines.append("- no llamar APIs externas salvo que en el futuro se autorice")
lines.append("- no hacer commit si la validacion falla")
lines.append("")
lines.append("## Entrega esperada")
lines.append("- resumen corto")
lines.append("- evidencia/verificacion")
lines.append("- git status --short")
lines.append("- y solo si todo da bien: commit/push")
lines.append("")
lines.append("## Handoff Packet Reference")
lines.append(f"- path: {handoff_packet_path.as_posix()}")
lines.append(f"- handoff_packet_json: {(handoff_packet_path.parent / (task_id + '.packet.json')).as_posix()}")

print("\n".join(lines))
PY

"$VALIDATE_MARKDOWN" "$tmp_path" >/dev/null
mv "$tmp_path" "$ticket_path"
trap - EXIT
if [ "${TASK_SKIP_HANDOFF_PACKET_EXPORT:-0}" != "1" ] && [ -x "$EXPORT_HANDOFF_PACKET" ]; then
  "$EXPORT_HANDOFF_PACKET" "$task_id" >/dev/null
fi
printf 'CODEX_TICKET_OK %s\n' "${ticket_path#$REPO_ROOT/}"
