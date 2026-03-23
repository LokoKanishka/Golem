#!/usr/bin/env bash
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

overall="OK"

OPENCLAW_GATEWAY_SERVICE="${GOLEM_OPENCLAW_GATEWAY_SERVICE_NAME:-openclaw-gateway.service}"
TASK_API_SERVICE="${GOLEM_TASK_API_SERVICE_NAME:-golem-task-panel-http.service}"
TASK_API_HOST="${GOLEM_TASK_API_HOST:-127.0.0.1}"
TASK_API_PORT="${GOLEM_TASK_API_PORT:-8765}"
WHATSAPP_BRIDGE_SERVICE="${GOLEM_WHATSAPP_BRIDGE_SERVICE_NAME:-golem-whatsapp-bridge.service}"
WHATSAPP_BRIDGE_BASE_URL="${GOLEM_WHATSAPP_BRIDGE_BASE_URL:-http://${TASK_API_HOST}:${TASK_API_PORT}}"
WHATSAPP_BRIDGE_STATE_FILE="${GOLEM_WHATSAPP_BRIDGE_STATE_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_state.json}"
WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE="${GOLEM_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_runtime.json}"
WHATSAPP_BRIDGE_AUDIT_FILE="${GOLEM_WHATSAPP_BRIDGE_AUDIT_FILE:-${REPO_ROOT}/state/tmp/whatsapp_task_bridge_runtime_audit.jsonl}"

env_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
  esac
  return 1
}

set_overall_warn() {
  if [ "$overall" = "OK" ]; then
    overall="WARN"
  fi
}

set_overall_fail() {
  overall="FAIL"
}

check_core_service() {
  local component="$1"
  local service_name="$2"
  local enabled_raw active_raw note state

  enabled_raw="$(systemctl --user is-enabled "$service_name" 2>&1 || true)"
  active_raw="$(systemctl --user is-active "$service_name" 2>&1 || true)"

  if [ "$active_raw" = "active" ]; then
    if [ "$enabled_raw" = "enabled" ] || [ "$enabled_raw" = "enabled-runtime" ]; then
      state="OK"
      note="enabled, active"
    else
      state="WARN"
      note="active pero no enabled (${enabled_raw})"
      set_overall_warn
    fi
  else
    state="FAIL"
    note="enabled=${enabled_raw}, active=${active_raw}"
    set_overall_fail
  fi

  printf -v "${component}_state" '%s' "$state"
  printf -v "${component}_note" '%s' "$note"
}

check_task_api_service() {
  local enabled_raw active_raw status_raw health_raw health_status status_line note state

  enabled_raw="$(systemctl --user is-enabled "$TASK_API_SERVICE" 2>&1 || true)"
  active_raw="$(systemctl --user is-active "$TASK_API_SERVICE" 2>&1 || true)"
  status_raw="$(python3 "${REPO_ROOT}/scripts/task_panel_http_ctl.py" status --service --service-name "$TASK_API_SERVICE" --host "$TASK_API_HOST" --port "$TASK_API_PORT" --json 2>&1 || true)"
  health_raw="$(python3 "${REPO_ROOT}/scripts/task_panel_http_ctl.py" healthcheck --service --service-name "$TASK_API_SERVICE" --host "$TASK_API_HOST" --port "$TASK_API_PORT" --json 2>&1)"
  health_status=$?

  status_line="$(STATUS_RAW="$status_raw" python3 - <<'PY'
import json
import os

raw = os.environ.get("STATUS_RAW", "")
try:
    payload = json.loads(raw)
except json.JSONDecodeError:
    print("unknown|unknown|(parse_error)")
    raise SystemExit(0)

print(
    f"{payload.get('service_active_state', 'unknown')}|"
    f"{'yes' if payload.get('api_ready') else 'no'}|"
    f"{payload.get('base_url', '(none)')}"
)
PY
)"

  local service_state api_ready base_url
  service_state="$(printf '%s' "$status_line" | cut -d'|' -f1)"
  api_ready="$(printf '%s' "$status_line" | cut -d'|' -f2)"
  base_url="$(printf '%s' "$status_line" | cut -d'|' -f3-)"

  if [ "$active_raw" = "active" ] && [ "$service_state" = "active" ] && [ "$api_ready" = "yes" ] && [ "$health_status" -eq 0 ]; then
    if [ "$enabled_raw" = "enabled" ] || [ "$enabled_raw" = "enabled-runtime" ]; then
      state="OK"
      note="enabled, active, health ok, url ${base_url}"
    else
      state="WARN"
      note="active y sano, pero no enabled (${enabled_raw}), url ${base_url}"
      set_overall_warn
    fi
  elif [ "$active_raw" = "active" ] || [ "$service_state" = "active" ]; then
    state="WARN"
    note="systemd activo pero healthcheck falla en ${base_url}"
    set_overall_warn
  else
    state="FAIL"
    note="enabled=${enabled_raw}, active=${active_raw}, url ${base_url}"
    set_overall_fail
  fi

  task_api_state="$state"
  task_api_note="$note"
}

check_bridge_service() {
  local enabled_raw active_raw status_raw health_raw health_status status_line note state

  enabled_raw="$(systemctl --user is-enabled "$WHATSAPP_BRIDGE_SERVICE" 2>&1 || true)"
  active_raw="$(systemctl --user is-active "$WHATSAPP_BRIDGE_SERVICE" 2>&1 || true)"
  status_raw="$(python3 "${REPO_ROOT}/scripts/task_whatsapp_bridge_ctl.py" status --service --service-name "$WHATSAPP_BRIDGE_SERVICE" --base-url "$WHATSAPP_BRIDGE_BASE_URL" --state-file "$WHATSAPP_BRIDGE_STATE_FILE" --runtime-status-file "$WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE" --audit-file "$WHATSAPP_BRIDGE_AUDIT_FILE" --json 2>&1 || true)"
  health_raw="$(python3 "${REPO_ROOT}/scripts/task_whatsapp_bridge_ctl.py" healthcheck --service --service-name "$WHATSAPP_BRIDGE_SERVICE" --base-url "$WHATSAPP_BRIDGE_BASE_URL" --state-file "$WHATSAPP_BRIDGE_STATE_FILE" --runtime-status-file "$WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE" --audit-file "$WHATSAPP_BRIDGE_AUDIT_FILE" --json 2>&1)"
  health_status=$?

  status_line="$(STATUS_RAW="$status_raw" HEALTH_RAW="$health_raw" python3 - <<'PY'
import json
import os

status_raw = os.environ.get("STATUS_RAW", "")
health_raw = os.environ.get("HEALTH_RAW", "")

try:
    status_payload = json.loads(status_raw)
except json.JSONDecodeError:
    print("unknown|unknown|unknown|(parse_error)|(none)")
    raise SystemExit(0)

try:
    health_payload = json.loads(health_raw)
except json.JSONDecodeError:
    health_payload = {}

runtime = status_payload.get("runtime", {})
reasons = health_payload.get("reasons", [])
if not isinstance(reasons, list):
    reasons = []

print(
    f"{status_payload.get('service_active_state', 'unknown')}|"
    f"{runtime.get('status', 'unknown')}|"
    f"{'yes' if status_payload.get('api_ready') else 'no'}|"
    f"{','.join(str(item) for item in reasons) if reasons else 'ok'}|"
    f"{runtime.get('last_operation', '(none)')}"
)
PY
)"

  local service_state runtime_state api_ready reasons last_operation
  service_state="$(printf '%s' "$status_line" | cut -d'|' -f1)"
  runtime_state="$(printf '%s' "$status_line" | cut -d'|' -f2)"
  api_ready="$(printf '%s' "$status_line" | cut -d'|' -f3)"
  reasons="$(printf '%s' "$status_line" | cut -d'|' -f4)"
  last_operation="$(printf '%s' "$status_line" | cut -d'|' -f5-)"

  if [ "$active_raw" = "active" ] && [ "$service_state" = "active" ] && [ "$runtime_state" = "running" ] && [ "$api_ready" = "yes" ] && [ "$health_status" -eq 0 ]; then
    if [ "$enabled_raw" = "enabled" ] || [ "$enabled_raw" = "enabled-runtime" ]; then
      state="OK"
      note="enabled, active, health ok, base ${WHATSAPP_BRIDGE_BASE_URL}, last_op ${last_operation}"
    else
      state="WARN"
      note="active y sano, pero no enabled (${enabled_raw}), last_op ${last_operation}"
      set_overall_warn
    fi
  elif [ "$active_raw" = "active" ] || [ "$service_state" = "active" ]; then
    state="WARN"
    note="systemd activo pero bridge no está sano (${reasons})"
    set_overall_warn
  else
    state="FAIL"
    note="enabled=${enabled_raw}, active=${active_raw}, base ${WHATSAPP_BRIDGE_BASE_URL}"
    set_overall_fail
  fi

  bridge_service_state="$state"
  bridge_service_note="$note"
}

if ! env_true "${GOLEM_SELF_CHECK_SKIP_GATEWAY:-0}"; then
  gateway_raw="$(openclaw gateway status 2>&1 || true)"
  systemd_raw="$(systemctl --user is-active "$OPENCLAW_GATEWAY_SERVICE" 2>&1 || true)"

  gateway_state="FAIL"
  gateway_note="gateway caído o no responde"
  if printf '%s' "$systemd_raw" | grep -qx 'active'; then
    if printf '%s' "$gateway_raw" | grep -q 'Runtime: running' && printf '%s' "$gateway_raw" | grep -q 'RPC probe: ok'; then
      gateway_state="OK"
      gateway_note="gateway activo, runtime running, rpc ok"
    else
      gateway_state="WARN"
      gateway_note="systemd activo pero faltan señales fuertes"
      set_overall_warn
    fi
  else
    set_overall_fail
  fi
else
  gateway_state="SKIP"
  gateway_note="omitido por GOLEM_SELF_CHECK_SKIP_GATEWAY"
fi

if ! env_true "${GOLEM_SELF_CHECK_SKIP_WHATSAPP:-0}"; then
  wa_raw="$(openclaw channels status --probe 2>&1 || openclaw channels status 2>&1 || true)"
  wa_state="FAIL"
  wa_note="whatsapp no disponible"
  if printf '%s' "$wa_raw" | grep -q 'Gateway reachable.'; then
    if printf '%s' "$wa_raw" | grep -Eq 'WhatsApp .*enabled, configured, linked, running, connected'; then
      wa_state="OK"
      wa_note="whatsapp conectado"
    else
      wa_state="WARN"
      wa_note="whatsapp reachable pero no totalmente conectado"
      set_overall_warn
    fi
  else
    set_overall_fail
  fi
else
  wa_state="SKIP"
  wa_note="omitido por GOLEM_SELF_CHECK_SKIP_WHATSAPP"
fi

if ! env_true "${GOLEM_SELF_CHECK_SKIP_BROWSER:-0}"; then
  profiles_raw="$(openclaw browser profiles 2>&1 || true)"
  browser_state="FAIL"
  browser_note="perfil chrome no disponible"
  if printf '%s' "$profiles_raw" | grep -q '^chrome:'; then
    if printf '%s' "$profiles_raw" | grep -q '^chrome: running'; then
      browser_state="OK"
      browser_note="browser relay chrome running"
    else
      browser_state="WARN"
      browser_note="perfil chrome existe pero no está running"
      set_overall_warn
    fi
  else
    set_overall_fail
  fi
else
  browser_state="SKIP"
  browser_note="omitido por GOLEM_SELF_CHECK_SKIP_BROWSER"
fi

if ! env_true "${GOLEM_SELF_CHECK_SKIP_TABS:-0}"; then
  tabs_raw="$(openclaw browser --browser-profile chrome tabs 2>&1 || true)"
  tabs_state="FAIL"
  tabs_note="no se pudieron consultar tabs"
  tabs_count="0"
  if printf '%s' "$tabs_raw" | grep -q 'No tabs'; then
    tabs_state="WARN"
    tabs_note="relay activo pero 0 tabs adjuntas"
    tabs_count="0"
    set_overall_warn
  elif printf '%s' "$tabs_raw" | grep -Eq '^[0-9]+\.'; then
    tabs_count="$(printf '%s\n' "$tabs_raw" | grep -Ec '^[0-9]+\.')"
    tabs_state="OK"
    tabs_note="${tabs_count} tab(s) adjunta(s)"
  else
    set_overall_fail
  fi
else
  tabs_state="SKIP"
  tabs_note="omitido por GOLEM_SELF_CHECK_SKIP_TABS"
  tabs_count="0"
fi

check_task_api_service
check_bridge_service

printf 'SELF-CHECK GOLEM\n'
printf 'gateway: %s — %s\n' "$gateway_state" "$gateway_note"
printf 'whatsapp: %s — %s\n' "$wa_state" "$wa_note"
printf 'browser_relay: %s — %s\n' "$browser_state" "$browser_note"
printf 'tabs: %s — %s\n' "$tabs_state" "$tabs_note"
printf 'task_api: %s — %s\n' "$task_api_state" "$task_api_note"
printf 'whatsapp_bridge_service: %s — %s\n' "$bridge_service_state" "$bridge_service_note"
printf 'estado_general: %s\n' "$overall"

case "$overall" in
  OK)
    printf 'sintesis: gateway activo, stack local sano, whatsapp conectado, relay operativo y tabs disponibles.\n'
    ;;
  WARN)
    printf 'sintesis: el sistema está mayormente operativo pero hay señales a revisar.\n'
    ;;
  FAIL)
    printf 'sintesis: el sistema no está en estado operativo confiable.\n'
    ;;
esac
