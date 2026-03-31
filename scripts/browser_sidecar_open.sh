#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'Uso: ./scripts/browser_sidecar_open.sh <url>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

browser_sidecar_require_running
browser_sidecar_run_tool open "$1"
