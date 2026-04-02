#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH_PROFILES_FILE="${OPENCLAW_AUTH_PROFILES_FILE:-$HOME/.openclaw/lib/node_modules/openclaw/dist/auth-profiles-B5ypC5S-.js}"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_FILE:-$HOME/.openclaw/openclaw.json}"
ENABLE_FLAG="${OPENCLAW_WHATSAPP_ENABLE_FLAG:-$HOME/.config/openclaw/whatsapp.enable}"
RUNTIME_REPLAY_FIXTURE="$(mktemp)"
RUNTIME_STATE_FILE="$(mktemp)"
RUNTIME_STATUS_FILE="$(mktemp)"
RUNTIME_AUDIT_FILE="$(mktemp)"
cleanup() {
  rm -f "${RUNTIME_REPLAY_FIXTURE}" "${RUNTIME_STATE_FILE}" "${RUNTIME_STATUS_FILE}" "${RUNTIME_AUDIT_FILE}"
}
trap cleanup EXIT

fail() {
  echo "VERIFY_FAIL: $*" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || fail "${file} missing expected text: ${needle}"
}

assert_jq() {
  local expr="$1"
  jq -e "$expr" "${OPENCLAW_CONFIG_FILE}" >/dev/null || fail "config assertion failed: ${expr}"
}

assert_file_contains "${AUTH_PROFILES_FILE}" 'whatsapp pairing reply suppressed for ${candidate}; recorded locally only'
assert_jq '.channels.whatsapp.enabled == false'
assert_jq '.channels.whatsapp.selfChatMode == false'
assert_jq '.channels.whatsapp.dmPolicy == "disabled"'
assert_jq '.channels.whatsapp.accounts.default.enabled == false'
assert_jq '.channels.whatsapp.accounts.default.dmPolicy == "disabled"'

for service in openclaw-gateway.service openclaw-direct-chat.service fusion-total-direct-chat.service; do
  dropin="$HOME/.config/systemd/user/${service}.d/10-whatsapp-kill-switch.conf"
  [ -f "${dropin}" ] || fail "missing kill-switch drop-in for ${service}"
  assert_file_contains "${dropin}" "${ENABLE_FLAG}"
done

[ ! -e "${ENABLE_FLAG}" ] || fail "enable flag must be absent to keep whatsapp frozen"

cat > "${RUNTIME_REPLAY_FIXTURE}" <<'EOF'
{"type":"log","module":"web-inbound","raw":"{\"1\":{\"from\":\"+5491100000000\",\"to\":\"+5491199999999\",\"body\":\"summary\",\"timestamp\":\"2026-04-01T23:59:59Z\"},\"2\":\"inbound message\"}"}
EOF

python3 "${REPO_ROOT}/scripts/task_whatsapp_bridge_runtime.py" \
  --base-url http://127.0.0.1:1 \
  --state-file "${RUNTIME_STATE_FILE}" \
  --runtime-status-file "${RUNTIME_STATUS_FILE}" \
    --audit-file "${RUNTIME_AUDIT_FILE}" \
    --replay-file "${RUNTIME_REPLAY_FIXTURE}" >/dev/null

assert_file_contains "${RUNTIME_AUDIT_FILE}" '"blocked": true'
assert_file_contains "${RUNTIME_AUDIT_FILE}" '"reason": "outbound_disabled"'

if ps -eo pid=,args= | grep -E 'openclaw/dist/index\.js gateway|openclaw_direct_chat\.py|task_whatsapp_bridge_runtime\.py' | grep -v grep >/dev/null; then
  fail "unexpected whatsapp-related process still running"
fi

echo "VERIFY_OK: whatsapp fail-closed checks passed"
