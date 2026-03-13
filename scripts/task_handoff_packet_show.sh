#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HANDOFFS_DIR="$REPO_ROOT/handoffs"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_handoff_packet_show.sh <task_id>
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

packet_path="$HANDOFFS_DIR/${task_id}.md"
if [ ! -f "$packet_path" ]; then
  fatal "no existe handoff packet para: $task_id"
fi

cat "$packet_path"
