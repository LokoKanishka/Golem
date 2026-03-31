#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_cmd() {
  local key="$1"
  local cmd="$2"
  local out="$TMP_DIR/${key}.out"
  local code_file="$TMP_DIR/${key}.code"
  local exit_code

  set +e
  bash -lc "$cmd" >"$out" 2>&1
  exit_code="$?"
  printf '%s' "$exit_code" >"$code_file"
}

cmd_out() {
  cat "$TMP_DIR/$1.out"
}

cmd_code() {
  cat "$TMP_DIR/$1.code"
}

add_result() {
  printf '%s | %s | %s\n' "$1" "$2" "$3"
}

extract_user_data_dir() {
  python3 - <<'PY'
import json
import os
from pathlib import Path

cfg = Path.home() / ".openclaw" / "openclaw.json"
if not cfg.exists():
    raise SystemExit(0)
data = json.loads(cfg.read_text(encoding="utf-8"))
print((((data.get("browser") or {}).get("profiles") or {}).get("user") or {}).get("userDataDir", ""))
PY
}

printf '# OpenClaw Capability Truth Verify\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

cd "$REPO_ROOT"

run_cmd git_status 'git status --short'
run_cmd git_branch 'git branch --show-current'
run_cmd git_log 'git log --oneline -3'
run_cmd version 'openclaw --version'
run_cmd gateway 'openclaw gateway status'
run_cmd status 'openclaw status || true'
run_cmd channels 'openclaw channels status --probe || openclaw channels status'
run_cmd panel_head 'curl -fsS -I http://127.0.0.1:18789/ || true'
run_cmd panel_html 'curl -fsS http://127.0.0.1:18789/ | sed -n "1,20p" || true'
run_cmd plugins 'openclaw plugins list | rg -n "Browser|WhatsApp|Slack|Telegram|Discord|Signal|browser|whatsapp|slack|telegram|discord|signal" || true'
run_cmd browser_profiles 'openclaw browser profiles || true'
run_cmd browser_user_status 'openclaw browser --browser-profile user status || true'
run_cmd browser_user_snapshot 'openclaw browser --browser-profile user snapshot || true'
run_cmd browser_openclaw_status 'openclaw browser --browser-profile openclaw status || true'
run_cmd browser_openclaw_tabs 'openclaw browser --browser-profile openclaw tabs || true'
run_cmd browser_openclaw_snapshot 'openclaw browser --browser-profile openclaw snapshot || true'
run_cmd ports 'ss -ltnp | rg "(:18789|:9222|:18800|:8765)" || true'
run_cmd chrome_ps 'ps -ef | rg "chrome|chromium|brave|edge" | rg -v "rg " || true'
run_cmd host_perceive 'timeout 20s ./scripts/golem_host_perceive.sh json || true'
run_cmd host_describe 'timeout 20s ./scripts/golem_host_describe.sh active-window --json || true'

USER_DATA_DIR="$(extract_user_data_dir)"
DEVTOOLS_FILE=""
if [ -n "$USER_DATA_DIR" ] && [ -f "$USER_DATA_DIR/DevToolsActivePort" ]; then
  DEVTOOLS_FILE="$USER_DATA_DIR/DevToolsActivePort"
  run_cmd cdp_tabs "GOLEM_BROWSER_DEVTOOLS_FILE=\"$DEVTOOLS_FILE\" ./scripts/browser_cdp_tool.sh tabs || true"
  run_cmd cdp_probe "port=\$(head -n1 \"$DEVTOOLS_FILE\"); curl -fsS \"http://127.0.0.1:\${port}/json/list\" || true"
else
  run_cmd cdp_tabs './scripts/browser_cdp_tool.sh tabs || true'
  run_cmd cdp_probe 'printf "no-devtools-file\n"'
fi

HOST_PERCEIVE_SUMMARY="$(python3 - <<'PY' "$TMP_DIR/host_perceive.out"
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not text:
    print("host perception did not return data")
    raise SystemExit(0)
try:
    data = json.loads(text)
except Exception:
    print("host perception output not parseable as json")
    raise SystemExit(0)
active = ((data.get("active_window") or {}).get("title") or "(none)")
total = data.get("windows_total", "?")
print(f"active_window={active}; windows_total={total}")
PY
)"

HOST_DESCRIBE_SUMMARY="$(python3 - <<'PY' "$TMP_DIR/host_describe.out"
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not text:
    print("host describe did not return data")
    raise SystemExit(0)
try:
    data = json.loads(text)
except Exception:
    print("host describe output not parseable as json")
    raise SystemExit(0)
target = ((((data.get("target") or {}).get("resolved_window")) or {}).get("title") or "(none)")
surface = (((data.get("surface_state_bundle") or {}).get("surface_type")) or "(none)")
print(f"target={target}; surface_type={surface}")
PY
)"

printf '\n## Baseline\n'
printf 'git_status_clean: %s\n' "$([ -z "$(cmd_out git_status)" ] && printf 'yes' || printf 'no')"
printf 'branch: %s\n' "$(cmd_out git_branch)"
printf 'recent_commits:\n%s\n' "$(cmd_out git_log)"
printf 'openclaw_version: %s\n' "$(cmd_out version)"
if [ -n "$USER_DATA_DIR" ]; then
  printf 'browser_userDataDir: %s\n' "$USER_DATA_DIR"
fi
if [ -n "$DEVTOOLS_FILE" ]; then
  printf 'browser_devtools_file: %s\n' "$DEVTOOLS_FILE"
fi

printf '\n## Classification\n'
printf 'capability | status | evidence\n'

if grep -q 'Runtime: running' "$TMP_DIR/gateway.out" && grep -q 'RPC probe: ok' "$TMP_DIR/gateway.out"; then
  add_result 'gateway_health' 'PASS' 'openclaw gateway status -> runtime running, rpc ok'
else
  add_result 'gateway_health' 'BLOCKED' 'openclaw gateway status did not prove running gateway + rpc'
fi

if grep -q 'HTTP/1.1 200' "$TMP_DIR/panel_head.out" && grep -q 'OpenClaw Control' "$TMP_DIR/panel_html.out"; then
  add_result 'panel_control_ui' 'PASS' 'dashboard returns HTTP 200 and serves OpenClaw Control HTML'
else
  add_result 'panel_control_ui' 'BLOCKED' 'dashboard did not return healthy HTTP/HTML evidence'
fi

if grep -Eq 'WhatsApp .*connected|WhatsApp .* OK|connected' "$TMP_DIR/status.out" && grep -q 'connected' "$TMP_DIR/channels.out"; then
  add_result 'whatsapp_connectivity' 'PASS' 'status + channels probe both report connected'
else
  add_result 'whatsapp_connectivity' 'BLOCKED' 'status/probe did not jointly prove connected whatsapp'
fi

if grep -q 'WhatsApp' "$TMP_DIR/status.out" && grep -q 'connected' "$TMP_DIR/channels.out"; then
  add_result 'status_probe_consistency' 'PARTIAL' 'both surfaces prove healthy whatsapp, but they are not the same status view'
else
  add_result 'status_probe_consistency' 'BLOCKED' 'status/probe pair did not prove a coherent whatsapp health view'
fi

if grep -q 'browser  .*loaded' "$TMP_DIR/plugins.out" || grep -q 'Browser      │ browser .* loaded' "$TMP_DIR/plugins.out"; then
  add_result 'browser_plugin_bundled' 'PASS' 'plugins list shows bundled browser plugin loaded'
else
  add_result 'browser_plugin_bundled' 'BLOCKED' 'browser plugin not shown as loaded'
fi

if grep -q '^user:' "$TMP_DIR/browser_profiles.out" && grep -q '^openclaw:' "$TMP_DIR/browser_profiles.out"; then
  add_result 'browser_profiles_inventory' 'PASS' 'browser profiles list user + openclaw'
else
  add_result 'browser_profiles_inventory' 'BLOCKED' 'browser profile inventory missing expected profiles'
fi

if grep -Eq 'timed out|ECONNREFUSED|Could not connect to Chrome' "$TMP_DIR/browser_user_snapshot.out" || grep -Eq 'ECONNREFUSED|Could not connect to Chrome' "$TMP_DIR/browser_user_status.out"; then
  add_result 'browser_user_attach' 'BLOCKED' 'user existing-session attach fails with timeout/econnrefused'
else
  add_result 'browser_user_attach' 'PASS' 'user attach returned usable evidence'
fi

if grep -q 'Missing X server or $DISPLAY' "$TMP_DIR/browser_openclaw_snapshot.out" || grep -q 'No tabs (browser closed or no targets)' "$TMP_DIR/browser_openclaw_tabs.out"; then
  add_result 'browser_managed_openclaw' 'BLOCKED' 'managed openclaw profile has no tabs and snapshot path is unusable'
else
  add_result 'browser_managed_openclaw' 'PASS' 'managed openclaw profile returned tabs/snapshot evidence'
fi

if [ -f "$SCRIPT_DIR/browser_cdp_tool.sh" ] && [ -n "$DEVTOOLS_FILE" ]; then
  add_result 'browser_cdp_helper_surface' 'PASS' "helper exists and user DevTools file is present at $DEVTOOLS_FILE"
elif [ -f "$SCRIPT_DIR/browser_cdp_tool.sh" ]; then
  add_result 'browser_cdp_helper_surface' 'PARTIAL' 'helper exists but no resolved user DevTools file was found'
else
  add_result 'browser_cdp_helper_surface' 'BLOCKED' 'helper script missing'
fi

if grep -qi 'fetch failed' "$TMP_DIR/cdp_tabs.out" || ! grep -q '^\[' "$TMP_DIR/cdp_probe.out"; then
  add_result 'browser_cdp_helper_live' 'BLOCKED' 'helper cannot fetch /json/list from the current CDP endpoint'
else
  add_result 'browser_cdp_helper_live' 'PASS' 'helper reached a live CDP endpoint'
fi

if grep -q '/opt/google/chrome/chrome' "$TMP_DIR/chrome_ps.out" && ! grep -q ':9222' "$TMP_DIR/ports.out"; then
  add_result 'chrome_process_vs_cdp' 'PARTIAL' 'chrome process exists but no 9222 listener is visible'
elif grep -q '/opt/google/chrome/chrome' "$TMP_DIR/chrome_ps.out"; then
  add_result 'chrome_process_vs_cdp' 'PASS' 'chrome process and cdp listener are both visible'
else
  add_result 'chrome_process_vs_cdp' 'BLOCKED' 'no chrome process evidence was found'
fi

if grep -q '"kind": "golem_host_perceive"' "$TMP_DIR/host_perceive.out"; then
  add_result 'host_perception_readside' 'PASS' "$HOST_PERCEIVE_SUMMARY"
else
  add_result 'host_perception_readside' 'BLOCKED' 'golem_host_perceive did not return valid evidence'
fi

if grep -q '"kind": "golem_host_describe"' "$TMP_DIR/host_describe.out"; then
  add_result 'host_describe_readside' 'PASS' "$HOST_DESCRIBE_SUMMARY"
else
  add_result 'host_describe_readside' 'BLOCKED' 'golem_host_describe did not return valid evidence'
fi

add_result 'whatsapp_delivery_live' 'UNVERIFIED' 'quick verify does not send a live whatsapp message'
add_result 'worker_readiness_deep' 'UNVERIFIED' 'use ./scripts/verify_worker_orchestration_stack.sh for deep worker proof'
add_result 'host_control_total' 'BLOCKED' 'read-side host evidence exists, but total control is not proven here'

printf '\n## Key Evidence\n'
printf 'gateway_summary: %s\n' "$(grep -E 'Runtime:|RPC probe:' "$TMP_DIR/gateway.out" | tr '\n' ' ' | sed 's/  */ /g')"
printf 'channels_summary: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/channels.out" | sed 's/  */ /g')"
printf 'browser_user_status: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/browser_user_status.out" | sed 's/  */ /g')"
printf 'browser_user_snapshot: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/browser_user_snapshot.out" | sed 's/  */ /g')"
printf 'browser_openclaw_snapshot: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/browser_openclaw_snapshot.out" | sed 's/  */ /g')"
printf 'cdp_helper_tabs: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/cdp_tabs.out" | sed 's/  */ /g')"
printf 'ports: %s\n' "$(tr '\n' ' ' <"$TMP_DIR/ports.out" | sed 's/  */ /g')"

printf '\n## Deep Follow-ups\n'
printf './scripts/verify_browser_stack.sh --diagnosis-only\n'
printf './scripts/verify_worker_orchestration_stack.sh\n'
