#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLEM_BROWSER_RELAY_REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GOLEM_BROWSER_RELAY_ROOT="${GOLEM_BROWSER_RELAY_ROOT:-${TMPDIR:-/tmp}/golem-browser-relay}"
GOLEM_BROWSER_RELAY_HOST="${GOLEM_BROWSER_RELAY_HOST:-127.0.0.1}"
GOLEM_BROWSER_RELAY_PORT="${GOLEM_BROWSER_RELAY_PORT:-18792}"
GOLEM_BROWSER_RELAY_URL="${GOLEM_BROWSER_RELAY_URL:-http://${GOLEM_BROWSER_RELAY_HOST}:${GOLEM_BROWSER_RELAY_PORT}}"
GOLEM_BROWSER_RELAY_WS_URL="${GOLEM_BROWSER_RELAY_WS_URL:-ws://${GOLEM_BROWSER_RELAY_HOST}:${GOLEM_BROWSER_RELAY_PORT}}"
GOLEM_BROWSER_RELAY_GATEWAY_HOST="${GOLEM_BROWSER_RELAY_GATEWAY_HOST:-127.0.0.1}"
GOLEM_BROWSER_RELAY_GATEWAY_PORT="${GOLEM_BROWSER_RELAY_GATEWAY_PORT:-18789}"
GOLEM_BROWSER_RELAY_GATEWAY_URL="${GOLEM_BROWSER_RELAY_GATEWAY_URL:-ws://${GOLEM_BROWSER_RELAY_GATEWAY_HOST}:${GOLEM_BROWSER_RELAY_GATEWAY_PORT}}"
GOLEM_BROWSER_RELAY_SERVER_PIDFILE="${GOLEM_BROWSER_RELAY_SERVER_PIDFILE:-${GOLEM_BROWSER_RELAY_ROOT}/relay.pid}"
GOLEM_BROWSER_RELAY_SERVER_LOGFILE="${GOLEM_BROWSER_RELAY_SERVER_LOGFILE:-${GOLEM_BROWSER_RELAY_ROOT}/relay.log}"
GOLEM_BROWSER_RELAY_START_TIMEOUT="${GOLEM_BROWSER_RELAY_START_TIMEOUT:-15}"
GOLEM_BROWSER_RELAY_CONFIG_PATH="${GOLEM_BROWSER_RELAY_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
GOLEM_BROWSER_RELAY_SERVICE_GATE_FILE="${GOLEM_BROWSER_RELAY_SERVICE_GATE_FILE:-$HOME/.config/openclaw/whatsapp.enable}"
GOLEM_BROWSER_RELAY_BROWSER_CDP_URL="${GOLEM_BROWSER_RELAY_BROWSER_CDP_URL:-http://127.0.0.1:9222}"
GOLEM_BROWSER_RELAY_EXTENSION_ID="${GOLEM_BROWSER_RELAY_EXTENSION_ID:-ojdcajknhechockcggjbkgkgloklcbde}"
GOLEM_BROWSER_RELAY_EXTENSION_PATH="${GOLEM_BROWSER_RELAY_EXTENSION_PATH:-$HOME/.openclaw/browser/chrome-extension}"
GOLEM_BROWSER_RELAY_EXTENSION_MANIFEST_PATH="${GOLEM_BROWSER_RELAY_EXTENSION_MANIFEST_PATH:-${GOLEM_BROWSER_RELAY_EXTENSION_PATH}/manifest.json}"

browser_relay_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

browser_relay_require_tools() {
  local tool
  for tool in curl python3 openclaw node; do
    command -v "$tool" >/dev/null 2>&1 || browser_relay_fail "falta herramienta requerida: $tool"
  done
}

browser_relay_ensure_root() {
  mkdir -p "$GOLEM_BROWSER_RELAY_ROOT"
}

browser_relay_find_browser_bin() {
  local candidate
  for candidate in /opt/google/chrome/chrome google-chrome google-chrome-stable chromium chromium-browser; do
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

  browser_relay_fail "no se encontro un binario browser utilizable"
}

browser_relay_resolve_config_env() {
  python3 - <<'PY' "$GOLEM_BROWSER_RELAY_CONFIG_PATH" "${GOLEM_BROWSER_RELAY_PROFILE:-}"
import json
import pathlib
import shlex
import sys

config_path = pathlib.Path(sys.argv[1]).expanduser()
profile_override = sys.argv[2].strip()

profile = profile_override or "chrome"
driver = ""
attach_only = ""
user_data_dir = ""
config_present = "false"
browser_default = ""

if config_path.exists():
    config_present = "true"
    try:
        data = json.loads(config_path.read_text(encoding="utf-8"))
        browser = data.get("browser") or {}
        profiles = browser.get("profiles") or {}
        browser_default = str(browser.get("defaultProfile") or "")
        if not profile_override:
            profile = browser_default or profile
        current = profiles.get(profile) or {}
        driver = str(current.get("driver") or "")
        attach_only = "true" if bool(current.get("attachOnly")) else "false"
        user_data_dir = str(current.get("userDataDir") or "")
    except Exception:
        pass

for key, value in {
    "GOLEM_BROWSER_RELAY_PROFILE": profile,
    "GOLEM_BROWSER_RELAY_PROFILE_DRIVER": driver,
    "GOLEM_BROWSER_RELAY_PROFILE_ATTACH_ONLY": attach_only,
    "GOLEM_BROWSER_RELAY_PROFILE_USER_DATA_DIR": user_data_dir,
    "GOLEM_BROWSER_RELAY_CONFIG_PRESENT": config_present,
    "GOLEM_BROWSER_RELAY_CONFIG_DEFAULT_PROFILE": browser_default,
}.items():
    print(f"{key}={shlex.quote(value)}")
PY
}

eval "$(browser_relay_resolve_config_env)"

browser_relay_gateway_pid() {
  [ -f "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE" ] || return 1
  tr -d '[:space:]' <"$GOLEM_BROWSER_RELAY_SERVER_PIDFILE"
}

browser_relay_gateway_pid_running() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

browser_relay_gateway_managed_running() {
  local pid
  pid="$(browser_relay_gateway_pid 2>/dev/null || true)"
  [ -n "$pid" ] && browser_relay_gateway_pid_running "$pid"
}

browser_relay_cleanup_stale_pidfile() {
  if [ -f "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE" ] && ! browser_relay_gateway_managed_running; then
    rm -f "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE"
  fi
}

browser_relay_service_gate_present() {
  [ -f "$GOLEM_BROWSER_RELAY_SERVICE_GATE_FILE" ]
}

browser_relay_port_busy() {
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$GOLEM_BROWSER_RELAY_PORT$"
}

browser_relay_port_probe() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :$GOLEM_BROWSER_RELAY_PORT )" 2>/dev/null || true
    return 0
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$GOLEM_BROWSER_RELAY_PORT" -sTCP:LISTEN 2>/dev/null || true
    return 0
  fi

  return 1
}

browser_relay_extension_manifest_probe() {
  [ -f "$GOLEM_BROWSER_RELAY_EXTENSION_MANIFEST_PATH" ] || return 1
  cat "$GOLEM_BROWSER_RELAY_EXTENSION_MANIFEST_PATH"
}

browser_relay_version_probe() {
  curl -fsS --max-time 2 "${GOLEM_BROWSER_RELAY_URL}/json/version"
}

browser_relay_tabs_probe() {
  curl -fsS --max-time 2 "${GOLEM_BROWSER_RELAY_URL}/json/list"
}

browser_relay_gateway_probe() {
  openclaw gateway probe --json
}

browser_relay_wait_listener() {
  local timeout="${1:-$GOLEM_BROWSER_RELAY_START_TIMEOUT}"
  local i
  for ((i = 0; i < timeout; i += 1)); do
    if browser_relay_version_probe >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

browser_relay_gateway_probe_ok() {
  local output="${1:-}"
  python3 - "$output" <<'PY'
import json
import sys

text = sys.argv[1].strip()
if not text:
    raise SystemExit(1)

try:
    payload = json.loads(text)
except Exception:
    raise SystemExit(1)

targets = payload.get("targets") or []
for item in targets:
    connect = item.get("connect") or {}
    if connect.get("ok") and connect.get("rpcOk"):
        raise SystemExit(0)

raise SystemExit(1)
PY
}

browser_relay_wait_gateway() {
  local timeout="${1:-$GOLEM_BROWSER_RELAY_START_TIMEOUT}"
  local i output
  for ((i = 0; i < timeout; i += 1)); do
    output="$(browser_relay_gateway_probe 2>/dev/null || true)"
    if browser_relay_gateway_probe_ok "$output"; then
      return 0
    fi
    sleep 1
  done
  return 1
}
