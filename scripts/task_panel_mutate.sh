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
./scripts/task_panel_mutate.sh set-host-expectation <task-id|path> [--target-kind <kind>] [--surface-category <category>] [--min-surface-confidence <uncertain|weak|moderate|strong>] [--require-summary] [--min-artifact-count <n>] [--require-structured-fields] [--note <note>] [--actor <actor>]
./scripts/task_panel_mutate.sh refresh-host-verification <task-id|path> [--source <describe|perceive>] [--refresh-host <desktop|active-window|window>] [--title <substring>] [--window-id <id>] [--actor <actor>]
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
HOST_TARGET_KIND=""
HOST_SURFACE_CATEGORY=""
HOST_MIN_SURFACE_CONFIDENCE=""
HOST_REQUIRE_SUMMARY=0
HOST_MIN_ARTIFACT_COUNT=""
HOST_REQUIRE_STRUCTURED_FIELDS=0
HOST_SOURCE_KIND=""
HOST_REFRESH_TARGET=""
WINDOW_TITLE=""
WINDOW_ID=""
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
  set-host-expectation)
    ACTOR="panel"
    ;;
  refresh-host-verification)
    ACTOR="panel"
    ;;
  *)
    usage
    ;;
esac

if [[ "$COMMAND" == "update" || "$COMMAND" == "close" || "$COMMAND" == "set-host-expectation" || "$COMMAND" == "refresh-host-verification" ]]; then
  [[ $# -ge 1 ]] || usage
  TARGET="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || usage
      if [[ "$COMMAND" == "refresh-host-verification" ]]; then
        WINDOW_TITLE="$2"
      else
        TITLE="$2"
      fi
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
      if [[ "$COMMAND" == "refresh-host-verification" ]]; then
        HOST_SOURCE_KIND="$2"
      else
        SOURCE_CHANNEL="$2"
      fi
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
    --target-kind)
      [[ $# -ge 2 ]] || usage
      HOST_TARGET_KIND="$2"
      shift 2
      ;;
    --surface-category)
      [[ $# -ge 2 ]] || usage
      HOST_SURFACE_CATEGORY="$2"
      shift 2
      ;;
    --min-surface-confidence)
      [[ $# -ge 2 ]] || usage
      HOST_MIN_SURFACE_CONFIDENCE="$2"
      shift 2
      ;;
    --require-summary)
      HOST_REQUIRE_SUMMARY=1
      shift
      ;;
    --min-artifact-count)
      [[ $# -ge 2 ]] || usage
      HOST_MIN_ARTIFACT_COUNT="$2"
      shift 2
      ;;
    --require-structured-fields)
      HOST_REQUIRE_STRUCTURED_FIELDS=1
      shift
      ;;
    --refresh-host)
      [[ $# -ge 2 ]] || usage
      HOST_REFRESH_TARGET="$2"
      shift 2
      ;;
    --window-id)
      [[ $# -ge 2 ]] || usage
      WINDOW_ID="$2"
      shift 2
      ;;
    --source-kind)
      [[ $# -ge 2 ]] || usage
      HOST_SOURCE_KIND="$2"
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

if [[ "$COMMAND" == "set-host-expectation" ]]; then
  [[ -n "$TARGET" ]] || usage
  declare -a host_expect_cmd=("$SCRIPT_DIR/task_set_host_expectation.sh" "$TARGET")
  if [[ -n "$HOST_TARGET_KIND" ]]; then
    host_expect_cmd+=(--target-kind "$HOST_TARGET_KIND")
  fi
  if [[ -n "$HOST_SURFACE_CATEGORY" ]]; then
    host_expect_cmd+=(--surface-category "$HOST_SURFACE_CATEGORY")
  fi
  if [[ -n "$HOST_MIN_SURFACE_CONFIDENCE" ]]; then
    host_expect_cmd+=(--min-surface-confidence "$HOST_MIN_SURFACE_CONFIDENCE")
  fi
  if [[ "$HOST_REQUIRE_SUMMARY" -eq 1 ]]; then
    host_expect_cmd+=(--require-summary)
  fi
  if [[ -n "$HOST_MIN_ARTIFACT_COUNT" ]]; then
    host_expect_cmd+=(--min-artifact-count "$HOST_MIN_ARTIFACT_COUNT")
  fi
  if [[ "$HOST_REQUIRE_STRUCTURED_FIELDS" -eq 1 ]]; then
    host_expect_cmd+=(--require-structured-fields)
  fi
  if [[ -n "$NOTE" ]]; then
    host_expect_cmd+=(--note "$NOTE")
  fi
  if [[ -n "$ACTOR" ]]; then
    host_expect_cmd+=(--actor "$ACTOR")
  fi

  host_expect_output="$("${host_expect_cmd[@]}")"
  result_line="$(printf '%s\n' "$host_expect_output" | awk '/^TASK_HOST_EXPECTATION_SET / {print; exit}')"
  task_id="$(printf '%s\n' "$result_line" | awk '{print $2}')"
  [[ -n "$task_id" ]] || {
    echo "Failed to extract host expectation task id." >&2
    exit 1
  }
  emit_result "set-host-expectation" "$(printf '%q ' "${host_expect_cmd[@]}")" "$result_line" "$task_id"
  exit 0
fi

if [[ "$COMMAND" == "refresh-host-verification" ]]; then
  [[ -n "$TARGET" ]] || usage
  declare -a host_refresh_cmd=("$SCRIPT_DIR/task_refresh_host_verification.sh" "$TARGET")
  if [[ -n "$HOST_SOURCE_KIND" ]]; then
    host_refresh_cmd+=(--source "$HOST_SOURCE_KIND")
  fi
  if [[ -n "$HOST_REFRESH_TARGET" ]]; then
    host_refresh_cmd+=(--refresh-host "$HOST_REFRESH_TARGET")
  fi
  if [[ -n "$WINDOW_TITLE" ]]; then
    host_refresh_cmd+=(--title "$WINDOW_TITLE")
  fi
  if [[ -n "$WINDOW_ID" ]]; then
    host_refresh_cmd+=(--window-id "$WINDOW_ID")
  fi
  if [[ -n "$ACTOR" ]]; then
    host_refresh_cmd+=(--actor "$ACTOR")
  fi

  host_refresh_output="$("${host_refresh_cmd[@]}")"
  result_line="$(printf '%s\n' "$host_refresh_output" | awk '/^TASK_HOST_VERIFICATION_REFRESHED / {print; exit}')"
  task_id="$(printf '%s\n' "$result_line" | awk '{print $2}')"
  [[ -n "$task_id" ]] || {
    echo "Failed to extract host verification task id." >&2
    exit 1
  }
  emit_result "refresh-host-verification" "$(printf '%q ' "${host_refresh_cmd[@]}")" "$result_line" "$task_id"
  exit 0
fi

usage
