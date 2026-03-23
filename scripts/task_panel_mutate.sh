#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
Usage:
./scripts/task_panel_mutate.sh create --title <title> --objective <objective> [--type <task_type>] [--owner <owner>] [--source <panel|whatsapp|operator|script|worker|scheduled_process>] [--accept <criterion>] [--canonical-session <session>] [--origin <origin>]
./scripts/task_panel_mutate.sh update <task-id|path> [--status <status>] [--owner <owner>] [--title <title>] [--objective <objective>] [--source <panel|whatsapp|operator|script|worker|scheduled_process>] [--append-accept <criterion>] [--note <note>] [--actor <actor>]
./scripts/task_panel_mutate.sh close <task-id|path> --status <done|failed|blocked|canceled> --note <note> [--actor <actor>] [--owner <owner>] [--source <panel|whatsapp|operator|script|worker|scheduled_process>]
USAGE
  exit 1
}

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

TITLE=""
OBJECTIVE=""
TASK_TYPE=""
OWNER=""
SOURCE_CHANNEL=""
CANONICAL_SESSION=""
ORIGIN=""
STATUS=""
NOTE=""
ACTOR=""
TARGET=""
declare -a ACCEPTANCE=()
declare -a APPEND_ACCEPT=()

case "$COMMAND" in
  create)
    SOURCE_CHANNEL="panel"
    ORIGIN="panel"
    ;;
  update)
    SOURCE_CHANNEL="panel"
    ACTOR="panel"
    ;;
  close)
    ACTOR="panel"
    ;;
  *)
    usage
    ;;
esac

if [[ "$COMMAND" == "update" || "$COMMAND" == "close" ]]; then
  [[ $# -ge 1 ]] || usage
  TARGET="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || usage
      TITLE="$2"
      shift 2
      ;;
    --objective)
      [[ $# -ge 2 ]] || usage
      OBJECTIVE="$2"
      shift 2
      ;;
    --type)
      [[ $# -ge 2 ]] || usage
      TASK_TYPE="$2"
      shift 2
      ;;
    --owner)
      [[ $# -ge 2 ]] || usage
      OWNER="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || usage
      SOURCE_CHANNEL="$2"
      shift 2
      ;;
    --accept)
      [[ $# -ge 2 ]] || usage
      ACCEPTANCE+=("$2")
      shift 2
      ;;
    --canonical-session)
      [[ $# -ge 2 ]] || usage
      CANONICAL_SESSION="$2"
      shift 2
      ;;
    --origin)
      [[ $# -ge 2 ]] || usage
      ORIGIN="$2"
      shift 2
      ;;
    --status)
      [[ $# -ge 2 ]] || usage
      STATUS="$2"
      shift 2
      ;;
    --append-accept)
      [[ $# -ge 2 ]] || usage
      APPEND_ACCEPT+=("$2")
      shift 2
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
    *)
      usage
      ;;
  esac
done

case "$SOURCE_CHANNEL" in
  panel|whatsapp|operator|script|worker|scheduled_process|"") ;;
  *)
    echo "Invalid source_channel: $SOURCE_CHANNEL" >&2
    exit 2
    ;;
esac

emit_result() {
  local operation="$1"
  local command_line="$2"
  local result_line="$3"
  local task_id="$4"

  python3 - "$operation" "$command_line" "$result_line" "$task_id" "$REPO_ROOT" <<'PY'
import json
import pathlib
import subprocess
import sys

operation, command_line, result_line, task_id, repo_root = sys.argv[1:]

show_output = subprocess.check_output(
    [str(pathlib.Path(repo_root) / "scripts" / "task_panel_read.sh"), "show", task_id],
    text=True,
)
show_payload = json.loads(show_output)

payload = {
    "meta": {
        "command": operation,
        "repo_root": repo_root,
        "source_of_truth": "tasks/*.json",
        "canonical_only": True,
        "panel_adapter": "task_panel_mutate.sh",
        "canonical_script_command": command_line,
        "canonical_script_result": result_line,
    },
    "task": show_payload["task"],
}

print(json.dumps(payload, ensure_ascii=True, indent=2))
PY
}

if [[ "$COMMAND" == "create" ]]; then
  [[ -n "$TITLE" && -n "$OBJECTIVE" ]] || usage
  declare -a create_cmd=("$SCRIPT_DIR/task_create.sh" "$TITLE" "$OBJECTIVE")
  if [[ -n "$TASK_TYPE" ]]; then
    create_cmd+=(--type "$TASK_TYPE")
  fi
  if [[ -n "$OWNER" ]]; then
    create_cmd+=(--owner "$OWNER")
  fi
  if [[ -n "$SOURCE_CHANNEL" ]]; then
    create_cmd+=(--source "$SOURCE_CHANNEL")
  fi
  for criterion in "${ACCEPTANCE[@]}"; do
    create_cmd+=(--accept "$criterion")
  done

  create_output="$(
    TASK_CANONICAL_SESSION="$CANONICAL_SESSION" \
    TASK_ORIGIN="$ORIGIN" \
    "${create_cmd[@]}"
  )"
  result_line="$(printf '%s\n' "$create_output" | awk '/^TASK_CREATED / {print; exit}')"
  task_id="$(printf '%s\n' "$result_line" | awk '{print $2}')"
  [[ -n "$task_id" ]] || {
    echo "Failed to extract created task id." >&2
    exit 1
  }
  command_line="TASK_CANONICAL_SESSION=${CANONICAL_SESSION:-} TASK_ORIGIN=${ORIGIN:-} $(printf '%q ' "${create_cmd[@]}")"
  emit_result "create" "${command_line% }" "$result_line" "$task_id"
  exit 0
fi

if [[ "$COMMAND" == "update" ]]; then
  [[ -n "$TARGET" ]] || usage
  declare -a update_cmd=("$SCRIPT_DIR/task_update.sh" "$TARGET")
  if [[ -n "$STATUS" ]]; then
    update_cmd+=(--status "$STATUS")
  fi
  if [[ -n "$OWNER" ]]; then
    update_cmd+=(--owner "$OWNER")
  fi
  if [[ -n "$TITLE" ]]; then
    update_cmd+=(--title "$TITLE")
  fi
  if [[ -n "$OBJECTIVE" ]]; then
    update_cmd+=(--objective "$OBJECTIVE")
  fi
  if [[ -n "$SOURCE_CHANNEL" ]]; then
    update_cmd+=(--source "$SOURCE_CHANNEL")
  fi
  for criterion in "${APPEND_ACCEPT[@]}"; do
    update_cmd+=(--append-accept "$criterion")
  done
  if [[ -n "$NOTE" ]]; then
    update_cmd+=(--note "$NOTE")
  fi
  if [[ -n "$ACTOR" ]]; then
    update_cmd+=(--actor "$ACTOR")
  fi

  update_output="$("${update_cmd[@]}")"
  result_line="$(printf '%s\n' "$update_output" | awk '/^TASK_UPDATED / {print; exit}')"
  task_id="$(printf '%s\n' "$result_line" | awk '{print $2}')"
  [[ -n "$task_id" ]] || {
    echo "Failed to extract updated task id." >&2
    exit 1
  }
  emit_result "update" "$(printf '%q ' "${update_cmd[@]}")" "$result_line" "$task_id"
  exit 0
fi

if [[ "$COMMAND" == "close" ]]; then
  [[ -n "$TARGET" && -n "$STATUS" && -n "$NOTE" ]] || usage
  declare -a close_cmd=("$SCRIPT_DIR/task_close.sh" "$TARGET" "$STATUS" --note "$NOTE")
  if [[ -n "$ACTOR" ]]; then
    close_cmd+=(--actor "$ACTOR")
  fi
  if [[ -n "$OWNER" ]]; then
    close_cmd+=(--owner "$OWNER")
  fi
  if [[ -n "$SOURCE_CHANNEL" ]]; then
    close_cmd+=(--source "$SOURCE_CHANNEL")
  fi

  close_output="$("${close_cmd[@]}")"
  result_line="$(printf '%s\n' "$close_output" | awk '/^TASK_CLOSED / {print; exit}')"
  task_id="$(printf '%s\n' "$result_line" | awk '{print $2}')"
  [[ -n "$task_id" ]] || {
    echo "Failed to extract closed task id." >&2
    exit 1
  }
  emit_result "close" "$(printf '%q ' "${close_cmd[@]}")" "$result_line" "$task_id"
  exit 0
fi

usage
