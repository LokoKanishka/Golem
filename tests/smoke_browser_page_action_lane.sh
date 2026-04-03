#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TMP_DIR="$(mktemp -d)"
HTTP_PID=""
CHROME_PID=""
STARTED_RELAY_HERE="0"

cleanup() {
  if [ -n "$HTTP_PID" ]; then
    kill "$HTTP_PID" >/dev/null 2>&1 || true
    wait "$HTTP_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$CHROME_PID" ]; then
    kill "$CHROME_PID" >/dev/null 2>&1 || true
    sleep 1
    kill -9 "$CHROME_PID" >/dev/null 2>&1 || true
    wait "$CHROME_PID" >/dev/null 2>&1 || true
  fi
  if [ "$STARTED_RELAY_HERE" = "1" ]; then
    ./scripts/golem_browser_relay_ctl.sh stop >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

HTTP_PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
START_URL="http://127.0.0.1:${HTTP_PORT}/"
TARGET_URL="http://127.0.0.1:${HTTP_PORT}/after.html"

cat >"$TMP_DIR/index.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Golem Browser Action Start</title>
  </head>
  <body>
    <h1>Golem Browser Action Start</h1>
    <p>Needle: CAPYBARA_ACTION_START_111</p>
  </body>
</html>
EOF

cat >"$TMP_DIR/after.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Golem Browser Action Finish</title>
  </head>
  <body>
    <h1>Golem Browser Action Finish</h1>
    <p>Needle: CAPYBARA_ACTION_FINISH_222</p>
  </body>
</html>
EOF

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 -d "$TMP_DIR" >"$TMP_DIR/http.log" 2>&1 &
HTTP_PID="$!"
sleep 1

printf 'SMOKE_BROWSER_PAGE_ACTION_LANE_BEGIN\n'

if ! ./scripts/golem_browser_relay_status.sh --json >/dev/null 2>&1; then
  ./scripts/golem_browser_relay_ctl.sh start >/dev/null
  STARTED_RELAY_HERE="1"
fi

browser_bin="$(source ./scripts/golem_browser_relay_common.sh; browser_relay_find_browser_bin)"
extension_path="$HOME/.openclaw/browser/chrome-extension"
[ -d "$extension_path" ] || {
  echo "ERROR: no se encontro la extension real en $extension_path" >&2
  exit 1
}

"$browser_bin" \
  --user-data-dir="$TMP_DIR/chrome-profile" \
  --disable-extensions-except="$extension_path" \
  --load-extension="$extension_path" \
  --remote-debugging-port=9222 \
  --no-first-run \
  --no-default-browser-check \
  --new-window "$START_URL" \
  >"$TMP_DIR/chrome.log" 2>&1 &
CHROME_PID="$!"

cdp_ready="0"
for _ in $(seq 1 20); do
  if curl -fsS --max-time 2 http://127.0.0.1:9222/json/list >/dev/null 2>&1; then
    cdp_ready="1"
    break
  fi
  sleep 1
done

[ "$cdp_ready" = "1" ] || {
  echo "ERROR: Chrome no expuso CDP en 127.0.0.1:9222" >&2
  sed -n '1,160p' "$TMP_DIR/chrome.log" >&2 || true
  exit 1
}

start_page_ready="0"
for _ in $(seq 1 20); do
  if python3 - <<'PY' "$START_URL"
import json
import sys
from urllib.request import urlopen

url = sys.argv[1]
with urlopen("http://127.0.0.1:9222/json/list") as response:
    payload = json.load(response)
if any(str(item.get("url") or "").startswith(url) for item in payload if isinstance(item, dict)):
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    start_page_ready="1"
    break
  fi
  sleep 1
done

[ "$start_page_ready" = "1" ] || {
  echo "ERROR: Chrome no expuso la start page en CDP" >&2
  curl -fsS --max-time 2 http://127.0.0.1:9222/json/list >&2 || true
  sed -n '1,160p' "$TMP_DIR/chrome.log" >&2 || true
  exit 1
}

attach_json="$(./scripts/golem_browser_relay_attach_tab.sh --json --match-url "$START_URL")"
status_ready="0"
for _ in $(seq 1 20); do
  status_json="$(./scripts/golem_browser_relay_status.sh --json 2>/dev/null || true)"
  if python3 - <<'PY' "$status_json" "$START_URL"
import json
import sys
payload = json.loads(sys.argv[1] or "{}")
start_url = sys.argv[2]
if payload.get("relay_state") == "relay_up_with_attach" and payload.get("active_tab_url", "").startswith(start_url):
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    status_ready="1"
    break
  fi
  sleep 1
done

[ "$status_ready" = "1" ] || {
  echo "ERROR: el relay no expuso la tab inicial adjunta" >&2
  ./scripts/golem_browser_relay_status.sh || true
  sed -n '1,200p' "$TMP_DIR/chrome.log" >&2 || true
  sed -n '1,200p' /tmp/golem-browser-relay/relay.log >&2 || true
  exit 1
}

python3 - <<'PY' "$attach_json" "$START_URL"
import json
import sys
payload = json.loads(sys.argv[1])
start_url = sys.argv[2]
assert payload.get("ok") is True, payload
assert (payload.get("attached_tab_url") or "").startswith(start_url), payload
print("PAGE_ACTION_CASE_A_STATE relay_up_with_attach")
print(f"PAGE_ACTION_CASE_A_ACTIVE_URL {payload.get('attached_tab_url')}")
print(f"PAGE_ACTION_CASE_A_ACTIVE_TITLE {payload.get('attached_tab_title')}")
PY

navigate_json="$(./scripts/golem_browser_relay_navigate.sh --json --target "$START_URL" "$TARGET_URL")"
python3 - <<'PY' "$navigate_json" "$TARGET_URL"
import json
import sys
payload = json.loads(sys.argv[1])
target_url = sys.argv[2]
assert payload.get("ok") is True, payload
assert payload.get("action") == "navigate", payload
assert payload.get("target_mode") == "selector-match", payload
assert (payload.get("requested_url") or "").startswith(target_url), payload
print(f"RELAY_NAVIGATE_TARGET {payload.get('target_selector')}")
print(f"RELAY_NAVIGATE_URL {payload.get('requested_url')}")
print(f"RELAY_NAVIGATE_MODE {payload.get('target_mode')}")
print("RELAY_NAVIGATE_OK")
PY

read_back_ready="0"
for _ in $(seq 1 30); do
  read_json="$(./scripts/golem_browser_relay_read.sh --json "$TARGET_URL" 2>/dev/null || true)"
  if python3 - <<'PY' "$read_json" "$TARGET_URL"
import json
import sys
payload = json.loads(sys.argv[1] or "{}")
target_url = sys.argv[2]
if payload.get("ok") and (payload.get("url") or "").startswith(target_url) and payload.get("title") == "Golem Browser Action Finish":
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    read_back_ready="1"
    break
  fi
  sleep 1
done

[ "$read_back_ready" = "1" ] || {
  echo "ERROR: no hubo read-back consistente despues de navigate" >&2
  ./scripts/golem_browser_relay_tabs.sh || true
  ./scripts/golem_browser_relay_read.sh "$TARGET_URL" || true
  sed -n '1,200p' /tmp/golem-browser-relay/relay.log >&2 || true
  exit 1
}

post_status_json="$(./scripts/golem_browser_relay_status.sh --json)"
post_read_json="$(./scripts/golem_browser_relay_read.sh --json "$TARGET_URL")"

python3 - <<'PY' "$post_status_json" "$post_read_json" "$TARGET_URL"
import json
import sys
status = json.loads(sys.argv[1])
read = json.loads(sys.argv[2])
target_url = sys.argv[3]
assert status.get("relay_state") == "relay_up_with_attach", status
assert (status.get("active_tab_url") or "").startswith(target_url), status
assert read.get("ok") is True, read
assert read.get("title") == "Golem Browser Action Finish", read
assert (read.get("url") or "").startswith(target_url), read
assert "CAPYBARA_ACTION_FINISH_222" in (read.get("raw_snapshot") or ""), read
preview = " | ".join(read.get("content_preview") or [])
print(f"RELAY_POST_NAV_TITLE {read.get('title')}")
print(f"RELAY_POST_NAV_URL {read.get('url')}")
print(f"RELAY_POST_NAV_PREVIEW {preview}")
PY

printf 'SMOKE_BROWSER_PAGE_ACTION_LANE_OK\n'
