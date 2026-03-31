#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

TMP_DIR="$(mktemp -d)"
SERVER_PID=""
SIDECAR_STARTED_HERE="0"

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  if [ "$SIDECAR_STARTED_HERE" = "1" ]; then
    "$SCRIPT_DIR/browser_sidecar_stop.sh" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cd "$REPO_ROOT"

printf '# Browser Sidecar Operational Verify\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

if ! browser_sidecar_listener_ready; then
  "$SCRIPT_DIR/browser_sidecar_start.sh" >/dev/null
  SIDECAR_STARTED_HERE="1"
fi

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
    <title>Golem Browser Truth</title>
  </head>
  <body>
    <h1>Golem Browser Truth</h1>
    <p>This browser sidecar path is real.</p>
    <p>Needle: CAPYBARA_SIGNAL_31415</p>
  </body>
</html>
EOF

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 -d "$TMP_DIR" >"$TMP_DIR/http.log" 2>&1 &
SERVER_PID="$!"
sleep 1

printf '\n## Sidecar Status\n'
"$SCRIPT_DIR/browser_sidecar_status.sh"

printf '\n## Sidecar Open\n'
"$SCRIPT_DIR/browser_sidecar_open.sh" "$TEST_URL"
sleep 2

printf '\n## Sidecar Tabs\n'
tabs_output="$("$SCRIPT_DIR/browser_sidecar_tabs.sh")"
printf '%s\n' "$tabs_output"

printf '\n## Sidecar Snapshot\n'
snapshot_output="$("$SCRIPT_DIR/browser_sidecar_snapshot.sh" "Golem Browser Truth")"
printf '%s\n' "$snapshot_output"

printf '\n## Sidecar Find\n'
find_output="$("$SCRIPT_DIR/browser_sidecar_find.sh" CAPYBARA_SIGNAL_31415 "Golem Browser Truth")"
printf '%s\n' "$find_output"

printf '\n## Classification\n'
if printf '%s\n' "$tabs_output" | grep -q 'Golem Browser Truth' && \
   printf '%s\n' "$snapshot_output" | grep -q 'Needle: CAPYBARA_SIGNAL_31415' && \
   printf '%s\n' "$find_output" | grep -q 'CAPYBARA_SIGNAL_31415'; then
  printf 'browser_sidecar_operational | PASS | start/status/open/tabs/snapshot/find completed on the proof page\n'
  printf '\nVERIFY_BROWSER_SIDECAR_OPERATIONAL_OK\n'
else
  printf 'browser_sidecar_operational | FAIL | one or more operational checks did not match the expected proof page\n'
  printf '\nVERIFY_BROWSER_SIDECAR_OPERATIONAL_FAIL\n'
  exit 1
fi
