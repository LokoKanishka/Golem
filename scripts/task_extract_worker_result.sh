#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
VALIDATE_MARKDOWN="$REPO_ROOT/scripts/validate_markdown_artifact.sh"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_extract_worker_result.sh <task_id>
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

artifact_rel="$(
  python3 - "$task_path" "$HANDOFFS_DIR" <<'PY'
import datetime
import json
import pathlib
import re
import sys


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").strip()


def headingish(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    return stripped.startswith("#") or (stripped.startswith("**") and stripped.endswith("**"))


def clean_line(line: str) -> str:
    stripped = line.strip()
    stripped = re.sub(r"^\s*[-*]\s*", "", stripped)
    stripped = re.sub(r"^\s*\d+\.\s*", "", stripped)
    return stripped.strip()


def summarize_block(text: str) -> list[str]:
    lines = text.splitlines()
    summary_lines = []
    in_summary = False

    for raw in lines:
        line = raw.rstrip()
        normalized = clean_line(line).lower()
        if headingish(line):
            if in_summary:
                break
            if "resumen" in normalized or "summary" in normalized:
                in_summary = True
                continue

        if not in_summary:
            continue

        cleaned = clean_line(line)
        if not cleaned or cleaned == "```":
            continue
        summary_lines.append(cleaned)
        if len(summary_lines) >= 5:
            break

    if summary_lines:
        return summary_lines

    fallback = []
    for raw in lines:
        cleaned = clean_line(raw)
        if not cleaned or cleaned == "```":
            continue
        if cleaned.lower().startswith("git status"):
            break
        fallback.append(cleaned)
        if len(fallback) >= 5:
            break
    return fallback


def log_fallback_summary(text: str) -> list[str]:
    lines = []
    for raw in text.splitlines():
        cleaned = clean_line(raw)
        if not cleaned:
            continue
        if cleaned.startswith("TASK_WORKER_RUN_"):
            continue
        if cleaned.startswith("started_at:") or cleaned.startswith("finished_at:"):
            continue
        if cleaned.startswith("ticket_path:") or cleaned.startswith("prompt_path:"):
            continue
        if cleaned.startswith("log_path:") or cleaned.startswith("last_message_path:"):
            continue
        if cleaned.startswith("command:"):
            continue
        lines.append(cleaned)
    return lines[-5:]


def snippet_lines(text: str, limit: int = 20) -> list[str]:
    snippet = []
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            if snippet and snippet[-1] != "":
                snippet.append("")
            continue
        snippet.append(line)
        if len(snippet) >= limit:
            break
    return snippet or ["(no raw result snippet available)"]


def compact_summary(lines: list[str], limit: int = 420) -> str:
    if not lines:
        return "No extracted summary available."
    compact = " | ".join(lines[:2])
    if len(compact) > limit:
        return compact[: limit - 3].rstrip() + "..."
    return compact


task_path = pathlib.Path(sys.argv[1]).resolve()
handoffs_dir = pathlib.Path(sys.argv[2]).resolve()
repo_root = task_path.parent.parent.resolve()

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task_id = task.get("task_id", task_path.stem)
task_type = task.get("type", "")
worker_run = task.get("worker_run")
if not isinstance(worker_run, dict):
    print(f"ERROR: la tarea {task_id} no tiene bloque worker_run", file=sys.stderr)
    raise SystemExit(1)

last_message_rel = worker_run.get("last_message_path", "")
log_rel = worker_run.get("log_path", "")

source_entries = []
last_message_text = ""
log_text = ""

if last_message_rel:
    last_message_path = (repo_root / last_message_rel).resolve()
    if last_message_path.exists():
        last_message_text = read_text(last_message_path)
        source_entries.append(("last_message_path", last_message_rel))

if log_rel:
    log_path = (repo_root / log_rel).resolve()
    if log_path.exists():
        log_text = read_text(log_path)
        source_entries.append(("log_path", log_rel))

if not source_entries:
    print(
        f"ERROR: la tarea {task_id} no tiene last_message_path ni log_path legibles",
        file=sys.stderr,
    )
    raise SystemExit(1)

summary_lines = summarize_block(last_message_text) if last_message_text else []
if not summary_lines and log_text:
    summary_lines = log_fallback_summary(log_text)

if not summary_lines:
    summary_lines = ["No se pudo extraer un resumen fuerte; revisar los archivos fuente."]

raw_source_name = "last_message_path" if last_message_text else "log_path"
raw_source_text = last_message_text or log_text
raw_snippet = snippet_lines(raw_source_text)

artifact_path = handoffs_dir / f"{task_id}.run.result.md"
generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

artifact_lines = [
    f"# Codex Worker Result: {task_id}",
    "",
    f"generated_at: {generated_at}",
    f"repo: {repo_root.as_posix()}",
    f"task_type: {task_type}",
    f"task_id: {task_id}",
    f"worker_runner: {worker_run.get('runner', '(none)')}",
    f"worker_state: {worker_run.get('state', '(none)')}",
    f"exit_code: {worker_run.get('exit_code', '(none)')}",
    "",
    "## Source Files",
]

for label, rel_path in source_entries:
    artifact_lines.append(f"- {label}: {rel_path}")

artifact_lines.extend(["", "## Extracted Summary"])
for line in summary_lines:
    artifact_lines.append(f"- {line}")

artifact_lines.extend(
    [
        "",
        "## Raw Result Snippet",
        f"Source: {raw_source_name}",
        "",
        "```text",
        *raw_snippet,
        "```",
        "",
        "## Notes",
        "- This artifact is generated automatically from the controlled Codex run outputs.",
        "- The extracted summary is heuristic and aims to reduce manual closure effort, not replace review.",
        "- When `run.last.md` exists it is preferred over the log because it is usually the cleanest final answer.",
    ]
)

artifact_path.write_text("\n".join(artifact_lines) + "\n", encoding="utf-8")

worker_run["extracted_at"] = generated_at
worker_run["result_artifact_path"] = artifact_path.relative_to(repo_root).as_posix()
worker_run["extracted_summary"] = compact_summary(summary_lines)
worker_run["extracted_summary_lines"] = summary_lines
worker_run["result_source_files"] = [rel_path for _, rel_path in source_entries]
task["updated_at"] = generated_at
note = f"worker result extracted automatically at {generated_at}"
notes = task.setdefault("notes", [])
if not notes or not notes[-1].startswith("worker result extracted automatically at "):
    notes.append(note)

with task_path.open("w", encoding="utf-8") as fh:
    json.dump(task, fh, indent=2, ensure_ascii=True)
    fh.write("\n")

print(artifact_path.relative_to(repo_root).as_posix())
PY
)"

"$VALIDATE_MARKDOWN" "$REPO_ROOT/$artifact_rel" >/dev/null
printf 'WORKER_RESULT_EXTRACTED %s\n' "$artifact_rel"
