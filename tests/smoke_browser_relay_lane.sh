#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TMP_DIR="$(mktemp -d)"
HTTP_PID=""
CHROME_PID=""
STARTED_GATEWAY_HERE="0"

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
  if [ "$STARTED_GATEWAY_HERE" = "1" ]; then
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
TEST_URL="http://127.0.0.1:${HTTP_PORT}/"

cat >"$TMP_DIR/index.html" <<'EOF'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Golem Browser Relay Proof</title>
  </head>
  <body>
    <h1>Golem Browser Relay Proof</h1>
    <p>Needle: CAPYBARA_RELAY_SIGNAL_90210</p>
  </body>
</html>
EOF

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 -d "$TMP_DIR" >"$TMP_DIR/http.log" 2>&1 &
HTTP_PID="$!"
sleep 1

printf 'SMOKE_BROWSER_RELAY_LANE_BEGIN\n'

case_a_json="$(GOLEM_BROWSER_RELAY_PORT=9 ./scripts/golem_browser_relay_status.sh --json 2>/dev/null || true)"
python3 - <<'PY' "$case_a_json"
import json, sys
payload = json.loads(sys.argv[1] or "{}")
assert payload.get("relay_state") == "relay_down", payload
print(f"RELAY_CASE_A_STATE {payload.get('relay_state')}")
print(f"RELAY_CASE_A_DIAG {payload.get('diagnosis')}")
PY

if ! ./scripts/golem_browser_relay_status.sh --json >/dev/null 2>&1; then
  ./scripts/golem_browser_relay_ctl.sh start >/dev/null
  STARTED_GATEWAY_HERE="1"
fi

status_after_start="$(./scripts/golem_browser_relay_status.sh --json 2>/dev/null || true)"
python3 - <<'PY' "$status_after_start"
import json, sys
payload = json.loads(sys.argv[1] or "{}")
assert payload.get("relay_state") == "relay_up_without_attach", payload
print(f"RELAY_CASE_B_STATE {payload.get('relay_state')}")
print(f"RELAY_CASE_B_ATTACH_COUNT {payload.get('relay_attach_count')}")
print(f"RELAY_CASE_B_DIAG {payload.get('diagnosis')}")
PY

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
  --new-window "$TEST_URL" \
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

proof_page_ready="0"
for _ in $(seq 1 20); do
  if python3 - <<'PY' "$TEST_URL"
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
    proof_page_ready="1"
    break
  fi
  sleep 1
done

[ "$proof_page_ready" = "1" ] || {
  echo "ERROR: Chrome no expuso la proof page en CDP" >&2
  curl -fsS --max-time 2 http://127.0.0.1:9222/json/list >&2 || true
  sed -n '1,160p' "$TMP_DIR/chrome.log" >&2 || true
  exit 1
}

attach_json="$(./scripts/golem_browser_relay_attach_tab.sh --json --match-url "$TEST_URL")"
python3 - <<'PY' "$attach_json"
import json, sys
payload = json.loads(sys.argv[1])
assert payload.get("ok") is True, payload
print(f"RELAY_ATTACH_RELAY_URL {payload.get('relay_url')}")
print(f"RELAY_ATTACH_TARGET {payload.get('attached_tab_url')}")
PY

relay_ready="0"
for _ in $(seq 1 20); do
  status_json="$(./scripts/golem_browser_relay_status.sh --json 2>/dev/null || true)"
  if python3 - <<'PY' "$status_json" "$TEST_URL"
import json, sys
payload = json.loads(sys.argv[1] or "{}")
url = sys.argv[2]
if payload.get("relay_state") == "relay_up_with_attach" and payload.get("active_tab_url", "").startswith(url):
    raise SystemExit(0)
raise SystemExit(1)
PY
  then
    relay_ready="1"
    break
  fi
  sleep 1
done

[ "$relay_ready" = "1" ] || {
  echo "ERROR: el relay no expuso una tab adjunta para la proof page" >&2
  ./scripts/golem_browser_relay_status.sh || true
  sed -n '1,200p' "$TMP_DIR/chrome.log" >&2 || true
  sed -n '1,200p' /tmp/golem-browser-relay/relay.log >&2 || true
  exit 1
}

tabs_json="$(./scripts/golem_browser_relay_tabs.sh --json)"
read_json="$(./scripts/golem_browser_relay_read.sh --json)"

python3 - <<'PY' "$tabs_json" "$read_json" "$TEST_URL"
import json, sys
tabs = json.loads(sys.argv[1])
read = json.loads(sys.argv[2])
test_url = sys.argv[3]
assert tabs.get("relay_state") == "relay_up_with_attach", tabs
assert tabs.get("attach_count", 0) >= 1, tabs
page_tabs = tabs.get("page_tabs") or []
assert any((item.get("url") or "").startswith(test_url) for item in page_tabs), tabs
assert read.get("ok") is True, read
assert read.get("title") == "Golem Browser Relay Proof", read
assert (read.get("url") or "").startswith(test_url), read
preview = " | ".join(read.get("content_preview") or [])
assert "CAPYBARA_RELAY_SIGNAL_90210" in read.get("raw_snapshot", ""), read
matching_tab = next(item for item in page_tabs if (item.get("url") or "").startswith(test_url))
print(f"RELAY_CASE_C_STATE {tabs.get('relay_state')}")
print(f"RELAY_CASE_C_ATTACH_COUNT {tabs.get('attach_count')}")
print(f"RELAY_CASE_C_ACTIVE_URL {matching_tab.get('url')}")
print(f"RELAY_CASE_C_READ_TITLE {read.get('title')}")
print(f"RELAY_CASE_C_READ_URL {read.get('url')}")
print(f"RELAY_CASE_C_PREVIEW {preview}")
PY

printf 'SMOKE_BROWSER_RELAY_LANE_OK\n'
