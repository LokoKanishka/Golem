#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GOLEM_BROWSER_SIDECAR_ROOT="${GOLEM_BROWSER_SIDECAR_ROOT:-${TMPDIR:-/tmp}/golem-browser-sidecar}"
GOLEM_BROWSER_SIDECAR_PORT="${GOLEM_BROWSER_SIDECAR_PORT:-9222}"
GOLEM_BROWSER_SIDECAR_HOST="${GOLEM_BROWSER_SIDECAR_HOST:-127.0.0.1}"
GOLEM_BROWSER_SIDECAR_URL="${GOLEM_BROWSER_SIDECAR_URL:-http://${GOLEM_BROWSER_SIDECAR_HOST}:${GOLEM_BROWSER_SIDECAR_PORT}}"
GOLEM_BROWSER_SIDECAR_PROFILE_DIR="${GOLEM_BROWSER_SIDECAR_PROFILE_DIR:-${GOLEM_BROWSER_SIDECAR_ROOT}/profile}"
GOLEM_BROWSER_SIDECAR_PIDFILE="${GOLEM_BROWSER_SIDECAR_PIDFILE:-${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.pid}"
GOLEM_BROWSER_SIDECAR_LOGFILE="${GOLEM_BROWSER_SIDECAR_LOGFILE:-${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.log}"
GOLEM_BROWSER_SIDECAR_READY_TIMEOUT="${GOLEM_BROWSER_SIDECAR_READY_TIMEOUT:-15}"
GOLEM_BROWSER_SIDECAR_NAV_DELAY="${GOLEM_BROWSER_SIDECAR_NAV_DELAY:-2}"

browser_sidecar_usage_common() {
  cat <<EOF
Config:
  GOLEM_BROWSER_SIDECAR_ROOT=$GOLEM_BROWSER_SIDECAR_ROOT
  GOLEM_BROWSER_SIDECAR_PORT=$GOLEM_BROWSER_SIDECAR_PORT
  GOLEM_BROWSER_SIDECAR_URL=$GOLEM_BROWSER_SIDECAR_URL
  GOLEM_BROWSER_SIDECAR_PROFILE_DIR=$GOLEM_BROWSER_SIDECAR_PROFILE_DIR
  GOLEM_BROWSER_SIDECAR_PIDFILE=$GOLEM_BROWSER_SIDECAR_PIDFILE
  GOLEM_BROWSER_SIDECAR_LOGFILE=$GOLEM_BROWSER_SIDECAR_LOGFILE
EOF
}

browser_sidecar_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

browser_sidecar_find_browser_bin() {
  if [ -n "${GOLEM_BROWSER_SIDECAR_BROWSER_BIN:-}" ]; then
    printf '%s\n' "$GOLEM_BROWSER_SIDECAR_BROWSER_BIN"
    return 0
  fi

  local candidate
  for candidate in /opt/google/chrome/chrome google-chrome google-chrome-stable; do
    if [[ "$candidate" == /* ]]; then
      if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      continue
    fi
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  browser_sidecar_fail "no se encontro un binario Chrome utilizable; setea GOLEM_BROWSER_SIDECAR_BROWSER_BIN"
}

browser_sidecar_require_tools() {
  local tool
  for tool in curl python3 ss; do
    command -v "$tool" >/dev/null 2>&1 || browser_sidecar_fail "falta herramienta requerida: $tool"
  done
}

browser_sidecar_pid() {
  [ -f "$GOLEM_BROWSER_SIDECAR_PIDFILE" ] || return 1
  tr -d '[:space:]' <"$GOLEM_BROWSER_SIDECAR_PIDFILE"
}

browser_sidecar_has_pidfile() {
  [ -f "$GOLEM_BROWSER_SIDECAR_PIDFILE" ]
}

browser_sidecar_pid_running() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

browser_sidecar_running() {
  local pid
  pid="$(browser_sidecar_pid 2>/dev/null || true)"
  [ -n "$pid" ] && browser_sidecar_pid_running "$pid"
}

browser_sidecar_listener_ready() {
  curl -fsS "${GOLEM_BROWSER_SIDECAR_URL}/json/list" >/dev/null 2>&1
}

browser_sidecar_port_busy() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$GOLEM_BROWSER_SIDECAR_PORT$"
}

browser_sidecar_wait_ready() {
  local timeout="${1:-$GOLEM_BROWSER_SIDECAR_READY_TIMEOUT}"
  local i
  for ((i = 0; i < timeout; i += 1)); do
    if browser_sidecar_listener_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

browser_sidecar_cleanup_stale_pidfile() {
  if browser_sidecar_has_pidfile && ! browser_sidecar_running; then
    rm -f "$GOLEM_BROWSER_SIDECAR_PIDFILE"
  fi
}

browser_sidecar_ensure_root() {
  mkdir -p "$GOLEM_BROWSER_SIDECAR_ROOT" "$GOLEM_BROWSER_SIDECAR_PROFILE_DIR"
}

browser_sidecar_require_running() {
  if ! browser_sidecar_running; then
    if browser_sidecar_port_busy; then
      browser_sidecar_fail "hay un listener en el puerto $GOLEM_BROWSER_SIDECAR_PORT pero no esta gobernado por este sidecar"
    fi
    browser_sidecar_fail "sidecar detenido; usa ./scripts/browser_sidecar_start.sh"
  fi

  if ! browser_sidecar_listener_ready; then
    browser_sidecar_fail "sidecar en proceso no listo; revisa $GOLEM_BROWSER_SIDECAR_LOGFILE"
  fi
}

browser_sidecar_page_tab_count() {
  python3 - <<'PY' "${GOLEM_BROWSER_SIDECAR_URL}"
import json
import sys
from urllib.request import urlopen

with urlopen(sys.argv[1] + "/json/list") as response:
    payload = json.load(response)
count = sum(1 for item in payload if item.get("type") == "page")
print(count)
PY
}

browser_sidecar_looks_like_url() {
  local value="${1:-}"
  [[ "$value" =~ ^https?:// ]]
}

browser_sidecar_run_tool() {
  GOLEM_BROWSER_CDP_URL="$GOLEM_BROWSER_SIDECAR_URL" "$SCRIPT_DIR/browser_cdp_tool.sh" "$@"
}

browser_sidecar_print_status() {
  local state="$1"
  local note="${2:-}"
  local pid=""
  if browser_sidecar_has_pidfile; then
    pid="$(browser_sidecar_pid 2>/dev/null || true)"
  fi

  printf 'browser_sidecar_state: %s\n' "$state"
  [ -n "$note" ] && printf 'note: %s\n' "$note"
  printf 'cdp_url: %s\n' "$GOLEM_BROWSER_SIDECAR_URL"
  printf 'port: %s\n' "$GOLEM_BROWSER_SIDECAR_PORT"
  printf 'root: %s\n' "$GOLEM_BROWSER_SIDECAR_ROOT"
  printf 'profile_dir: %s\n' "$GOLEM_BROWSER_SIDECAR_PROFILE_DIR"
  printf 'log_file: %s\n' "$GOLEM_BROWSER_SIDECAR_LOGFILE"
  if [ -n "$pid" ]; then
    printf 'pid: %s\n' "$pid"
  fi
  if browser_sidecar_listener_ready; then
    printf 'listener_ready: yes\n'
    printf 'page_tabs: %s\n' "$(browser_sidecar_page_tab_count)"
  else
    printf 'listener_ready: no\n'
  fi
}

browser_sidecar_start_managed() {
  local browser_bin pid

  browser_sidecar_require_tools
  browser_sidecar_cleanup_stale_pidfile

  if browser_sidecar_running && browser_sidecar_listener_ready; then
    browser_sidecar_print_status "running" "managed sidecar ya estaba listo"
    return 0
  fi

  if browser_sidecar_port_busy; then
    browser_sidecar_fail "puerto $GOLEM_BROWSER_SIDECAR_PORT ocupado por un listener no gobernado por este sidecar"
  fi

  browser_sidecar_ensure_root
  browser_bin="$(browser_sidecar_find_browser_bin)"

  nohup setsid "$browser_bin" \
    --headless=new \
    --no-sandbox \
    --remote-debugging-port="$GOLEM_BROWSER_SIDECAR_PORT" \
    --user-data-dir="$GOLEM_BROWSER_SIDECAR_PROFILE_DIR" \
    --no-first-run \
    --no-default-browser-check \
    about:blank >"$GOLEM_BROWSER_SIDECAR_LOGFILE" 2>&1 < /dev/null &
  pid="$!"
  printf '%s\n' "$pid" >"$GOLEM_BROWSER_SIDECAR_PIDFILE"

  if ! browser_sidecar_wait_ready "$GOLEM_BROWSER_SIDECAR_READY_TIMEOUT"; then
    printf 'ERROR: sidecar no quedo listo dentro de %ss\n' "$GOLEM_BROWSER_SIDECAR_READY_TIMEOUT" >&2
    printf 'last_log:\n' >&2
    tail -n 40 "$GOLEM_BROWSER_SIDECAR_LOGFILE" >&2 || true
    rm -f "$GOLEM_BROWSER_SIDECAR_PIDFILE"
    exit 1
  fi

  browser_sidecar_print_status "running" "managed sidecar iniciado"
}
