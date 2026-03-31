#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLEM_BROWSER_SIDECAR_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GOLEM_BROWSER_SIDECAR_ROOT="${GOLEM_BROWSER_SIDECAR_ROOT:-${TMPDIR:-/tmp}/golem-browser-sidecar}"
GOLEM_BROWSER_SIDECAR_PORT="${GOLEM_BROWSER_SIDECAR_PORT:-9222}"
GOLEM_BROWSER_SIDECAR_HOST="${GOLEM_BROWSER_SIDECAR_HOST:-127.0.0.1}"
GOLEM_BROWSER_SIDECAR_URL="${GOLEM_BROWSER_SIDECAR_URL:-http://${GOLEM_BROWSER_SIDECAR_HOST}:${GOLEM_BROWSER_SIDECAR_PORT}}"
GOLEM_BROWSER_SIDECAR_PROFILE_DIR="${GOLEM_BROWSER_SIDECAR_PROFILE_DIR:-${GOLEM_BROWSER_SIDECAR_ROOT}/profile}"
GOLEM_BROWSER_SIDECAR_PIDFILE="${GOLEM_BROWSER_SIDECAR_PIDFILE:-${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.pid}"
GOLEM_BROWSER_SIDECAR_LOGFILE="${GOLEM_BROWSER_SIDECAR_LOGFILE:-${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.log}"
GOLEM_BROWSER_SIDECAR_READY_TIMEOUT="${GOLEM_BROWSER_SIDECAR_READY_TIMEOUT:-15}"
GOLEM_BROWSER_SIDECAR_NAV_DELAY="${GOLEM_BROWSER_SIDECAR_NAV_DELAY:-2}"
GOLEM_BROWSER_SIDECAR_OUTBOX_DIR="${GOLEM_BROWSER_SIDECAR_OUTBOX_DIR:-${GOLEM_BROWSER_SIDECAR_REPO_ROOT}/outbox/manual}"

browser_sidecar_usage_common() {
  cat <<EOF
Config:
  GOLEM_BROWSER_SIDECAR_REPO_ROOT=$GOLEM_BROWSER_SIDECAR_REPO_ROOT
  GOLEM_BROWSER_SIDECAR_ROOT=$GOLEM_BROWSER_SIDECAR_ROOT
  GOLEM_BROWSER_SIDECAR_PORT=$GOLEM_BROWSER_SIDECAR_PORT
  GOLEM_BROWSER_SIDECAR_URL=$GOLEM_BROWSER_SIDECAR_URL
  GOLEM_BROWSER_SIDECAR_PROFILE_DIR=$GOLEM_BROWSER_SIDECAR_PROFILE_DIR
  GOLEM_BROWSER_SIDECAR_PIDFILE=$GOLEM_BROWSER_SIDECAR_PIDFILE
  GOLEM_BROWSER_SIDECAR_LOGFILE=$GOLEM_BROWSER_SIDECAR_LOGFILE
  GOLEM_BROWSER_SIDECAR_OUTBOX_DIR=$GOLEM_BROWSER_SIDECAR_OUTBOX_DIR
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

browser_sidecar_validate_slug() {
  local slug="${1:-}"
  if [ -z "$slug" ]; then
    browser_sidecar_fail "falta slug"
  fi
  if [[ "$slug" == *"/"* ]]; then
    browser_sidecar_fail "slug invalido: no puede contener /"
  fi
  if [[ ! "$slug" =~ ^[A-Za-z0-9._-]+$ ]]; then
    browser_sidecar_fail "slug invalido: usa solo letras, numeros, punto, guion y guion bajo"
  fi
}

browser_sidecar_make_outbox() {
  mkdir -p "$GOLEM_BROWSER_SIDECAR_OUTBOX_DIR"
}

browser_sidecar_artifact_path() {
  local slug="$1"
  local extension="$2"
  local ts
  ts="$(date -u +"%Y%m%dT%H%M%SZ")"
  printf '%s/%s_%s.%s\n' "$GOLEM_BROWSER_SIDECAR_OUTBOX_DIR" "$ts" "$slug" "$extension"
}

browser_sidecar_display_repo_path() {
  local path="$1"
  printf '%s\n' "${path#$GOLEM_BROWSER_SIDECAR_REPO_ROOT/}"
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

browser_sidecar_tabs_json() {
  python3 - <<'PY' "${GOLEM_BROWSER_SIDECAR_URL}"
import json
import sys
from urllib.request import urlopen

base_url = sys.argv[1].rstrip("/")
with urlopen(base_url + "/json/list") as response:
    payload = json.load(response)

tabs = []
for item in payload:
    if not item or item.get("type") != "page":
        continue
    tabs.append(
        {
            "index": len(tabs),
            "id": item.get("id") or item.get("targetId") or "",
            "title": item.get("title") or "",
            "url": item.get("url") or "",
            "wsUrl": item.get("webSocketDebuggerUrl") or "",
        }
    )

print(json.dumps(tabs))
PY
}

browser_sidecar_resolve_selector_json() {
  local selector="${1:-}"

  python3 - <<'PY' "${GOLEM_BROWSER_SIDECAR_URL}" "$selector"
import json
import sys
from urllib.request import urlopen

base_url = sys.argv[1].rstrip("/")
selector = sys.argv[2].strip()

with urlopen(base_url + "/json/list") as response:
    payload = json.load(response)

tabs = []
for item in payload:
    if not item or item.get("type") != "page":
        continue
    tabs.append(
        {
            "index": len(tabs),
            "id": item.get("id") or item.get("targetId") or "",
            "title": item.get("title") or "",
            "url": item.get("url") or "",
            "wsUrl": item.get("webSocketDebuggerUrl") or "",
        }
    )

if not tabs:
    print("ERROR: no hay tabs disponibles en el browser remoto", file=sys.stderr)
    sys.exit(1)

def is_internal(tab):
    return tab["url"].startswith("chrome://") or tab["url"].startswith("devtools://")

def emit(tab, match_type):
    out = dict(tab)
    out["match_type"] = match_type
    print(json.dumps(out))
    sys.exit(0)

def print_matches(label, matches):
    print(f"ERROR: {label}", file=sys.stderr)
    for tab in matches:
        print(
            f'  - [{tab["index"]}] {tab["title"]} :: {tab["url"]}',
            file=sys.stderr,
        )

if not selector:
    non_internal = [tab for tab in tabs if not is_internal(tab)]
    default = non_internal[-1] if non_internal else tabs[-1]
    emit(default, "default")

if selector.isdigit():
    wanted = int(selector)
    for tab in tabs:
        if tab["index"] == wanted:
            emit(tab, "index")
    print(f"ERROR: no existe una tab con indice {selector}", file=sys.stderr)
    sys.exit(1)

needle = selector.lower()
exact = [
    tab
    for tab in tabs
    if tab["title"].lower() == needle or tab["url"].lower() == needle
]
if len(exact) == 1:
    emit(exact[0], "exact")
if len(exact) > 1:
    print_matches(f'selector exacto ambiguo: "{selector}"', exact)
    sys.exit(1)

partial = [
    tab
    for tab in tabs
    if needle in tab["title"].lower() or needle in tab["url"].lower()
]
if len(partial) == 1:
    emit(partial[0], "partial")
if len(partial) > 1:
    print_matches(
        f'selector ambiguo: "{selector}". Usa un selector mas especifico o el indice.',
        partial,
    )
    sys.exit(1)

print(f'ERROR: no se encontro una tab que coincida con "{selector}"', file=sys.stderr)
print("Tabs disponibles:", file=sys.stderr)
for tab in tabs:
    print(f'  - [{tab["index"]}] {tab["title"]} :: {tab["url"]}', file=sys.stderr)
sys.exit(1)
PY
}

browser_sidecar_resolve_selector_field() {
  local selector="${1:-}"
  local field="$2"
  local json_payload

  if ! json_payload="$(browser_sidecar_resolve_selector_json "$selector")"; then
    return 1
  fi
  python3 - <<'PY' "$field" "$json_payload"
import json
import sys

field = sys.argv[1]
payload = json.loads(sys.argv[2])
value = payload.get(field, "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

browser_sidecar_resolve_latest_url_json() {
  local url="${1:-}"
  if [ -z "$url" ]; then
    browser_sidecar_fail "falta URL para resolver la tab mas reciente"
  fi

  python3 - <<'PY' "${GOLEM_BROWSER_SIDECAR_URL}" "$url"
import json
import sys
from urllib.request import urlopen

base_url = sys.argv[1].rstrip("/")
wanted_url = sys.argv[2].strip()

with urlopen(base_url + "/json/list") as response:
    payload = json.load(response)

tabs = []
for item in payload:
    if not item or item.get("type") != "page":
        continue
    tabs.append(
        {
            "index": len(tabs),
            "id": item.get("id") or item.get("targetId") or "",
            "title": item.get("title") or "",
            "url": item.get("url") or "",
            "wsUrl": item.get("webSocketDebuggerUrl") or "",
        }
    )

matches = [tab for tab in tabs if tab["url"] == wanted_url]
if not matches:
    print(f'ERROR: no se encontro una tab con URL exacta "{wanted_url}"', file=sys.stderr)
    sys.exit(1)

# /json/list expone primero las tabs mas recientes; elegimos la primera exacta
# para que el flujo del dossier quede determinista aunque existan tabs viejas.
resolved = dict(matches[0])
resolved["match_type"] = "latest_url_exact"
print(json.dumps(resolved))
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
