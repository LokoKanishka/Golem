#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/task_new.sh <type> <title>

Compatibilidad:
  Wrapper legacy sobre ./scripts/task_create.sh.

Opcional por entorno:
  TASK_PARENT_TASK_ID=<task_id_padre>
  TASK_DEPENDS_ON='["task-a","task-b"]'
  TASK_OBJECTIVE="objetivo explicito"
  TASK_STEP_NAME="nombre-del-step"
  TASK_STEP_ORDER=<numero>
  TASK_CRITICAL=true|false
  TASK_EXECUTION_MODE=local|worker
USAGE
}

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

task_type="${1:-}"
if [ -z "$task_type" ]; then
  usage
  fatal "falta type"
fi

if [ "$#" -lt 2 ]; then
  usage
  fatal "falta title"
fi

title="${*:2}"
objective="${TASK_OBJECTIVE:-$title}"

created_output="$(
  TASK_PARENT_TASK_ID="${TASK_PARENT_TASK_ID:-}" \
  TASK_DEPENDS_ON="${TASK_DEPENDS_ON:-}" \
  TASK_STEP_NAME="${TASK_STEP_NAME:-}" \
  TASK_STEP_ORDER="${TASK_STEP_ORDER:-}" \
  TASK_CRITICAL="${TASK_CRITICAL:-}" \
  TASK_EXECUTION_MODE="${TASK_EXECUTION_MODE:-}" \
  TASK_CANONICAL_SESSION="${TASK_CANONICAL_SESSION:-}" \
  TASK_ORIGIN="${TASK_ORIGIN:-local}" \
  "$SCRIPT_DIR/task_create.sh" "$title" "$objective" --type "$task_type"
)"

task_path="$(printf '%s\n' "$created_output" | tail -n 1)"
if [ -z "$task_path" ]; then
  fatal "no se pudo extraer la ruta creada"
fi

printf 'TASK_CREATED %s\n' "${task_path#$REPO_ROOT/}"
