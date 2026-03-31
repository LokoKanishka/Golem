#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

browser_sidecar_require_tools
browser_sidecar_cleanup_stale_pidfile

if browser_sidecar_running; then
  if browser_sidecar_listener_ready; then
    browser_sidecar_print_status "running"
  else
    browser_sidecar_print_status "starting" "pid gestionado presente pero listener todavia no listo"
  fi
  exit 0
fi

if browser_sidecar_port_busy; then
  browser_sidecar_print_status "unmanaged-listener" "hay un listener activo fuera del lifecycle gestionado"
  exit 1
fi

browser_sidecar_print_status "stopped"
