#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

browser_sidecar_require_tools
browser_sidecar_cleanup_stale_pidfile

if browser_sidecar_running; then
  pid="$(browser_sidecar_pid)"
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  rm -f "$GOLEM_BROWSER_SIDECAR_PIDFILE"
  browser_sidecar_print_status "stopped" "managed sidecar detenido"
  exit 0
fi

if browser_sidecar_port_busy; then
  browser_sidecar_fail "hay un listener en el puerto $GOLEM_BROWSER_SIDECAR_PORT pero no esta gobernado por este sidecar"
fi

browser_sidecar_print_status "stopped" "no habia sidecar gestionado en ejecucion"
