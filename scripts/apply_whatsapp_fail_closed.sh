#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_PROFILES_FILE="${OPENCLAW_AUTH_PROFILES_FILE:-$HOME/.openclaw/lib/node_modules/openclaw/dist/auth-profiles-B5ypC5S-.js}"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_FILE:-$HOME/.openclaw/openclaw.json}"
KILL_SWITCH_TEMPLATE="${REPO_ROOT}/config/systemd-user/openclaw-whatsapp-kill-switch.conf"
ENABLE_FLAG="${OPENCLAW_WHATSAPP_ENABLE_FLAG:-$HOME/.config/openclaw/whatsapp.enable}"
BACKUP_DIR_DEFAULT="${HOME}/.openclaw/backups/incident_whatsapp_fail_closed"
BACKUP_DIR="${1:-$BACKUP_DIR_DEFAULT}"

mkdir -p "${BACKUP_DIR}"

if [ ! -f "${AUTH_PROFILES_FILE}" ]; then
  echo "missing auth profiles file: ${AUTH_PROFILES_FILE}" >&2
  exit 1
fi

if [ ! -f "${OPENCLAW_CONFIG_FILE}" ]; then
  echo "missing config file: ${OPENCLAW_CONFIG_FILE}" >&2
  exit 1
fi

cp "${AUTH_PROFILES_FILE}" "${BACKUP_DIR}/auth-profiles-B5ypC5S-.js.bak"
cp "${OPENCLAW_CONFIG_FILE}" "${BACKUP_DIR}/openclaw.json.bak"

python3 - "${AUTH_PROFILES_FILE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """\t\t\t\tsendPairingReply: async (text) => {\n\t\t\t\t\tawait params.sock.sendMessage(params.remoteJid, { text });\n\t\t\t\t},"""
new = """\t\t\t\tsendPairingReply: async (_text) => {\n\t\t\t\t\tlogVerbose(`whatsapp pairing reply suppressed for ${candidate}; recorded locally only`);\n\t\t\t\t},"""
marker = "whatsapp pairing reply suppressed for ${candidate}; recorded locally only"

if marker in text:
    sys.exit(0)
if old not in text:
    raise SystemExit("could not locate whatsapp pairing send callback in auth profiles file")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

tmp_config="$(mktemp)"
jq '
  .channels.whatsapp.enabled = false
  | .channels.whatsapp.selfChatMode = false
  | .channels.whatsapp.dmPolicy = "disabled"
  | .channels.whatsapp.accounts.default.enabled = false
  | .channels.whatsapp.accounts.default.dmPolicy = "disabled"
' "${OPENCLAW_CONFIG_FILE}" > "${tmp_config}"
mv "${tmp_config}" "${OPENCLAW_CONFIG_FILE}"

mkdir -p "$HOME/.config/openclaw"
rm -f "${ENABLE_FLAG}"

rendered_kill_switch="$(mktemp)"
sed "s|{enable_flag}|${ENABLE_FLAG}|g" "${KILL_SWITCH_TEMPLATE}" > "${rendered_kill_switch}"

for service in openclaw-gateway.service openclaw-direct-chat.service fusion-total-direct-chat.service; do
  dropin_dir="$HOME/.config/systemd/user/${service}.d"
  mkdir -p "${dropin_dir}"
  cp "${rendered_kill_switch}" "${dropin_dir}/10-whatsapp-kill-switch.conf"
done
rm -f "${rendered_kill_switch}"

systemctl --user daemon-reload

echo "APPLIED_WHATSAPP_FAIL_CLOSED"
echo "AUTH_PROFILES_FILE=${AUTH_PROFILES_FILE}"
echo "OPENCLAW_CONFIG_FILE=${OPENCLAW_CONFIG_FILE}"
echo "ENABLE_FLAG=${ENABLE_FLAG}"
echo "BACKUP_DIR=${BACKUP_DIR}"
