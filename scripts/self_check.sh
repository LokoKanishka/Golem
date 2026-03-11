#!/usr/bin/env bash
set -u

overall="OK"

set_overall_warn() {
  if [ "$overall" = "OK" ]; then
    overall="WARN"
  fi
}

set_overall_fail() {
  overall="FAIL"
}

gateway_raw="$(openclaw gateway status 2>&1 || true)"
wa_raw="$(openclaw channels status --probe 2>&1 || openclaw channels status 2>&1 || true)"
profiles_raw="$(openclaw browser profiles 2>&1 || true)"
tabs_raw="$(openclaw browser --browser-profile chrome tabs 2>&1 || true)"
systemd_raw="$(systemctl --user is-active openclaw-gateway.service 2>&1 || true)"

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

if [ "$gateway_state" = "FAIL" ] || [ "$wa_state" = "FAIL" ] || [ "$browser_state" = "FAIL" ] || [ "$tabs_state" = "FAIL" ]; then
  overall="FAIL"
fi

printf 'SELF-CHECK GOLEM\n'
printf 'gateway: %s — %s\n' "$gateway_state" "$gateway_note"
printf 'whatsapp: %s — %s\n' "$wa_state" "$wa_note"
printf 'browser_relay: %s — %s\n' "$browser_state" "$browser_note"
printf 'tabs: %s — %s\n' "$tabs_state" "$tabs_note"
printf 'estado_general: %s\n' "$overall"

case "$overall" in
  OK)
    printf 'sintesis: gateway activo, whatsapp conectado, relay operativo y tabs disponibles.\n'
    ;;
  WARN)
    printf 'sintesis: el sistema está mayormente operativo pero hay señales a revisar.\n'
    ;;
  FAIL)
    printf 'sintesis: el sistema no está en estado operativo confiable.\n'
    ;;
esac
