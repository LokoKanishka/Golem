#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_PATH="${REPO_ROOT}/desktop/golem.desktop.template"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
DESKTOP_PATH="${APPLICATIONS_DIR}/golem.desktop"
LAUNCHER_PATH="${REPO_ROOT}/scripts/launch_golem.sh"

if [ ! -f "$TEMPLATE_PATH" ]; then
  printf 'ERROR: no existe la plantilla %s\n' "$TEMPLATE_PATH" >&2
  exit 1
fi

if [ ! -x "$LAUNCHER_PATH" ]; then
  printf 'ERROR: el launcher no es ejecutable: %s\n' "$LAUNCHER_PATH" >&2
  exit 1
fi

mkdir -p "$APPLICATIONS_DIR"

sed \
  -e "s|__GOLEM_LAUNCHER__|${LAUNCHER_PATH}|g" \
  -e "s|__GOLEM_REPO__|${REPO_ROOT}|g" \
  "$TEMPLATE_PATH" > "$DESKTOP_PATH"

chmod 755 "$DESKTOP_PATH"

printf 'DESKTOP_ENTRY_OK %s\n' "$DESKTOP_PATH"
