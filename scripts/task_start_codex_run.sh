#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
HANDOFFS_DIR="$REPO_ROOT/handoffs"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_start_codex_run.sh <task_id>
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

python3 - "$task_path" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task_id = task.get("task_id", task_path.stem)
if task.get("status") != "delegated":
    print(f"ERROR: la tarea {task_id} no esta en estado delegated", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(task.get("handoff"), dict):
    print(f"ERROR: la tarea {task_id} no tiene bloque handoff", file=sys.stderr)
    raise SystemExit(1)
PY

mkdir -p "$HANDOFFS_DIR"
cd "$REPO_ROOT"

ticket_path="$HANDOFFS_DIR/${task_id}.codex.md"
if [ ! -f "$ticket_path" ]; then
  ./scripts/task_prepare_codex_ticket.sh "$task_id" >/dev/null
fi

[ -f "$ticket_path" ] || fatal "no existe el ticket Codex para $task_id"

prompt_path="$HANDOFFS_DIR/${task_id}.run.prompt.md"
log_path="$HANDOFFS_DIR/${task_id}.run.log"
last_message_path="$HANDOFFS_DIR/${task_id}.run.last.md"
tmp_prompt="$(mktemp "$HANDOFFS_DIR/.task-run-prompt.XXXXXX.md")"
trap 'rm -f "$tmp_prompt"' EXIT

python3 - "$ticket_path" "$task_id" "$REPO_ROOT" >"$tmp_prompt" <<'PY'
import datetime
import pathlib
import sys

ticket_path = pathlib.Path(sys.argv[1])
task_id = sys.argv[2]
repo_root = sys.argv[3]
ticket = ticket_path.read_text(encoding="utf-8")
generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()

print(f"# Controlled Codex Run Prompt: {task_id}")
print()
print(f"generated_at: {generated_at}")
print(f"repo: {repo_root}")
print(f"task_id: {task_id}")
print()
print("## Run Rules")
print("- Work in read-only mode.")
print("- Do not modify files.")
print("- Do not run git commit or git push.")
print("- Produce a concise useful result only.")
print("- Use the ticket below as the primary task input.")
print()
print("## Codex Ticket")
print()
print(ticket.rstrip())
print()
print("## Final Response Format")
print("- resumen corto")
print("- evidencia/verificacion")
print("- git status --short")
PY

mv "$tmp_prompt" "$prompt_path"
trap - EXIT

started_at="$(date -u --iso-8601=seconds)"
command_string="codex exec -C \"$REPO_ROOT\" -s read-only --color never -o \"$last_message_path\" - < \"$prompt_path\" > \"$log_path\" 2>&1"

tmp_task="$(mktemp "$TASKS_DIR/.task-worker-run.XXXXXX.tmp")"
trap 'rm -f "$tmp_task"' EXIT
python3 - "$task_path" "$ticket_path" "$prompt_path" "$log_path" "$last_message_path" "$command_string" "$started_at" >"$tmp_task" <<'PY'
import datetime
import json
import pathlib
import sys

task_path, ticket_path, prompt_path, log_path, last_message_path, command_string, started_at = sys.argv[1:8]
task_path = pathlib.Path(task_path)
with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

task["status"] = "worker_running"
task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task["worker_run"] = {
    "runner": "codex_cli",
    "state": "running",
    "ticket_path": pathlib.Path(ticket_path).relative_to(task_path.parent.parent).as_posix(),
    "prompt_path": pathlib.Path(prompt_path).relative_to(task_path.parent.parent).as_posix(),
    "log_path": pathlib.Path(log_path).relative_to(task_path.parent.parent).as_posix(),
    "last_message_path": pathlib.Path(last_message_path).relative_to(task_path.parent.parent).as_posix(),
    "command": command_string,
    "started_at": started_at,
}
task.setdefault("notes", []).append(f"controlled codex run started on {started_at}")

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$task_path"
trap - EXIT

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$ticket_path" "$log_path" "$prompt_path" "$last_message_path" "$command_string" <<'PY'
import json
import pathlib
import sys

ticket_path, log_path, prompt_path, last_message_path, command_string = sys.argv[1:6]
repo_root = pathlib.Path(ticket_path).resolve().parent.parent
print(json.dumps({
    "ticket_path": pathlib.Path(ticket_path).resolve().relative_to(repo_root).as_posix(),
    "prompt_path": pathlib.Path(prompt_path).resolve().relative_to(repo_root).as_posix(),
    "log_path": pathlib.Path(log_path).resolve().relative_to(repo_root).as_posix(),
    "last_message_path": pathlib.Path(last_message_path).resolve().relative_to(repo_root).as_posix(),
    "command": command_string,
}))
PY
)" ./scripts/task_add_output.sh "$task_id" "worker-run-start" 0 "controlled codex run launched"

{
  printf 'TASK_WORKER_RUN_STARTED %s\n' "$task_id"
  printf 'started_at: %s\n' "$started_at"
  printf 'ticket_path: %s\n' "${ticket_path#$REPO_ROOT/}"
  printf 'prompt_path: %s\n' "${prompt_path#$REPO_ROOT/}"
  printf 'log_path: %s\n' "${log_path#$REPO_ROOT/}"
  printf 'last_message_path: %s\n' "${last_message_path#$REPO_ROOT/}"
  printf 'command: %s\n' "$command_string"
} >"$log_path"

set +e
codex exec -C "$REPO_ROOT" -s read-only --color never -o "$last_message_path" - <"$prompt_path" >>"$log_path" 2>&1
codex_exit="$?"
set -e

finished_at="$(date -u --iso-8601=seconds)"

tmp_task="$(mktemp "$TASKS_DIR/.task-worker-run-finish.XXXXXX.tmp")"
trap 'rm -f "$tmp_task"' EXIT
python3 - "$task_path" "$codex_exit" "$finished_at" >"$tmp_task" <<'PY'
import datetime
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
codex_exit = int(sys.argv[2])
finished_at = sys.argv[3]

with task_path.open(encoding="utf-8") as fh:
    task = json.load(fh)

worker_run = task.setdefault("worker_run", {})
worker_run["state"] = "finished"
worker_run["exit_code"] = codex_exit
worker_run["finished_at"] = finished_at
task["updated_at"] = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()
task.setdefault("notes", []).append(
    f"controlled codex run finished on {finished_at} with exit_code={codex_exit}"
)

json.dump(task, sys.stdout, indent=2, ensure_ascii=True)
sys.stdout.write("\n")
PY
mv "$tmp_task" "$task_path"
trap - EXIT

TASK_OUTPUT_EXTRA_JSON="$(
  python3 - "$codex_exit" "$log_path" "$last_message_path" <<'PY'
import json
import pathlib
import sys

codex_exit, log_path, last_message_path = sys.argv[1:4]
repo_root = pathlib.Path(log_path).resolve().parent.parent
print(json.dumps({
    "exit_code": int(codex_exit),
    "log_path": pathlib.Path(log_path).resolve().relative_to(repo_root).as_posix(),
    "last_message_path": pathlib.Path(last_message_path).resolve().relative_to(repo_root).as_posix(),
}))
PY
)" ./scripts/task_add_output.sh "$task_id" "worker-run-finish" "$codex_exit" "controlled codex run finished with exit_code=$codex_exit"

printf '\nTASK_WORKER_RUN_FINISHED %s\n' "$task_id" >>"$log_path"
printf 'finished_at: %s\n' "$finished_at" >>"$log_path"
printf 'exit_code: %s\n' "$codex_exit" >>"$log_path"

printf 'TASK_WORKER_RUN_STARTED %s\n' "$task_id"
printf 'TASK_WORKER_RUN_FINISHED %s\n' "$task_id"
printf 'log_path: %s\n' "${log_path#$REPO_ROOT/}"
