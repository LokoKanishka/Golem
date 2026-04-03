#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/golem_browser_relay_common.sh"

usage() {
  cat <<EOF
Usage:
  ./scripts/golem_browser_relay_ctl.sh status
  ./scripts/golem_browser_relay_ctl.sh healthcheck
  ./scripts/golem_browser_relay_ctl.sh start
  ./scripts/golem_browser_relay_ctl.sh stop
  ./scripts/golem_browser_relay_ctl.sh restart
EOF
}

browser_relay_require_tools
browser_relay_ensure_root
browser_relay_cleanup_stale_pidfile

status_json() {
  "$SCRIPT_DIR/golem_browser_relay_status.sh" --json 2>/dev/null || true
}

status_gateway_reachable() {
  local raw="${1:-}"
  python3 - "$raw" <<'PY'
import json
import sys
text = sys.argv[1].strip()
if not text:
    raise SystemExit(1)
payload = json.loads(text)
raise SystemExit(0 if payload.get("gateway_reachable") else 1)
PY
}

command="${1:-}"
case "$command" in
  status)
    exec "$SCRIPT_DIR/golem_browser_relay_status.sh"
    ;;
  healthcheck)
    exec "$SCRIPT_DIR/golem_browser_relay_status.sh"
    ;;
  start)
    current_status="$(status_json)"
    if "$SCRIPT_DIR/golem_browser_relay_status.sh" --json >/dev/null 2>&1; then
      printf 'relay_ctl: already-up\n'
      printf 'control_mode: external-or-existing\n'
      exit 0
    fi

    if browser_relay_gateway_managed_running; then
      if browser_relay_wait_listener; then
        printf 'relay_ctl: relay-already-managed\n'
        printf 'relay_pid: %s\n' "$(browser_relay_gateway_pid)"
        exit 0
      fi
      browser_relay_fail "relay gestionado detectado pero no responde"
    fi

    if browser_relay_port_busy; then
      browser_relay_fail "puerto $GOLEM_BROWSER_RELAY_PORT ocupado pero el relay no responde; usa ./scripts/golem_browser_relay_status.sh para diagnostico"
    fi

    nohup setsid python3 "$SCRIPT_DIR/golem_browser_relay_server.py" >"$GOLEM_BROWSER_RELAY_SERVER_LOGFILE" 2>&1 < /dev/null &
    relay_pid="$!"
    printf '%s\n' "$relay_pid" >"$GOLEM_BROWSER_RELAY_SERVER_PIDFILE"

    if browser_relay_wait_listener; then
      printf 'relay_ctl: started\n'
      printf 'relay_pid: %s\n' "$relay_pid"
      printf 'relay_log: %s\n' "$GOLEM_BROWSER_RELAY_SERVER_LOGFILE"
      exit 0
    fi

    kill "$relay_pid" >/dev/null 2>&1 || true
    wait "$relay_pid" >/dev/null 2>&1 || true
    rm -f "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE"
    printf 'last_log:\n' >&2
    tail -n 40 "$GOLEM_BROWSER_RELAY_SERVER_LOGFILE" >&2 || true
    browser_relay_fail "relay no quedo listo; revisa $GOLEM_BROWSER_RELAY_SERVER_LOGFILE"
    ;;
  stop)
    if ! browser_relay_gateway_managed_running; then
      browser_relay_cleanup_stale_pidfile
      current_status="$(status_json)"
      if "$SCRIPT_DIR/golem_browser_relay_status.sh" --json >/dev/null 2>&1; then
        browser_relay_fail "hay un relay activo pero no esta gobernado por este ctl"
      fi
      printf 'relay_ctl: already-stopped\n'
      exit 0
    fi

    pid="$(browser_relay_gateway_pid)"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    rm -f "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE"
    printf 'relay_ctl: stopped\n'
    printf 'relay_pid: %s\n' "$pid"
    ;;
  restart)
    "$0" stop >/dev/null 2>&1 || true
    exec "$0" start
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    usage >&2
    browser_relay_fail "comando no soportado: $command"
    ;;
esac
