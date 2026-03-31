#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
cleanup() {
  if [ -n "${CHROME_PID:-}" ]; then
    kill "$CHROME_PID" >/dev/null 2>&1 || true
    wait "$CHROME_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_capture() {
  local key="$1"
  shift
  local out="$TMP_DIR/${key}.out"
  local code="$TMP_DIR/${key}.code"
  local exit_code

  set +e
  "$@" >"$out" 2>&1
  exit_code="$?"
  printf '%s' "$exit_code" >"$code"
}

print_section() {
  printf '\n## %s\n' "$1"
}

PORT_CDP=9222
PORT_HTTP=8011
TEST_URL="http://127.0.0.1:${PORT_HTTP}/"

printf '# Browser Capability Truth Verify\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"
printf 'test_url: %s\n' "$TEST_URL"

cd "$REPO_ROOT"

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

python3 -m http.server "$PORT_HTTP" --bind 127.0.0.1 -d "$TMP_DIR" >"$TMP_DIR/http.log" 2>&1 &
SERVER_PID="$!"

/opt/google/chrome/chrome \
  --headless=new \
  --no-sandbox \
  --remote-debugging-port="$PORT_CDP" \
  --user-data-dir="$TMP_DIR/profile" \
  --no-first-run \
  --no-default-browser-check \
  about:blank >"$TMP_DIR/chrome.log" 2>&1 &
CHROME_PID="$!"

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:${PORT_CDP}/json/list" >"$TMP_DIR/json-list.ready" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  print_section "Failure"
  printf 'browser_sidecar | BLOCKED | cdp listener did not become ready on %s\n' "$PORT_CDP"
  printf '\nVERIFY_BROWSER_CAPABILITY_TRUTH_FAIL native=BLOCKED sidecar=BLOCKED\n'
  exit 1
fi

run_capture profiles bash -lc 'openclaw browser profiles || true'
run_capture native_status bash -lc 'openclaw browser status || true'
run_capture native_tabs bash -lc 'openclaw browser tabs || true'
run_capture native_snapshot bash -lc 'openclaw browser snapshot || true'

run_capture helper_open bash -lc "GOLEM_BROWSER_CDP_URL=http://127.0.0.1:${PORT_CDP} ./scripts/browser_cdp_tool.sh open ${TEST_URL} || true"
sleep 2
run_capture helper_tabs bash -lc "GOLEM_BROWSER_CDP_URL=http://127.0.0.1:${PORT_CDP} ./scripts/browser_cdp_tool.sh tabs || true"
run_capture helper_snapshot bash -lc "GOLEM_BROWSER_CDP_URL=http://127.0.0.1:${PORT_CDP} ./scripts/browser_cdp_tool.sh snapshot \"Golem Browser Truth\" || true"
run_capture helper_find bash -lc "GOLEM_BROWSER_CDP_URL=http://127.0.0.1:${PORT_CDP} ./scripts/browser_cdp_tool.sh find CAPYBARA_SIGNAL_31415 \"Golem Browser Truth\" || true"

native_status_value="BLOCKED"
if grep -q 'profile:' "$TMP_DIR/native_status.out" && grep -q 'http://127.0.0.1:8011/' "$TMP_DIR/native_snapshot.out"; then
  native_status_value="PASS"
fi

sidecar_status_value="BLOCKED"
if grep -q 'Golem Browser Truth' "$TMP_DIR/helper_tabs.out" && \
   grep -q 'Needle: CAPYBARA_SIGNAL_31415' "$TMP_DIR/helper_snapshot.out" && \
   grep -q 'CAPYBARA_SIGNAL_31415' "$TMP_DIR/helper_find.out"; then
  sidecar_status_value="PASS"
fi

print_section "Classification"
printf 'capability | status | note\n'
if [ "$native_status_value" = "PASS" ]; then
  printf 'browser_nativo_oc | PASS | native openclaw browser returned usable tabs + snapshot on the proof page\n'
else
  printf 'browser_nativo_oc | BLOCKED | native openclaw browser could not use the live raw CDP listener on %s\n' "$PORT_CDP"
fi

if [ "$sidecar_status_value" = "PASS" ]; then
  printf 'browser_sidecar | PASS | dedicated chrome sidecar + browser_cdp_tool.sh proved tabs + snapshot + find on a real HTTP page\n'
else
  printf 'browser_sidecar | BLOCKED | sidecar helper could not complete tabs + snapshot + find on the proof page\n'
fi

print_section "OpenClaw Profiles"
cat "$TMP_DIR/profiles.out"

print_section "OpenClaw Status"
cat "$TMP_DIR/native_status.out"

print_section "OpenClaw Tabs"
cat "$TMP_DIR/native_tabs.out"

print_section "OpenClaw Snapshot"
cat "$TMP_DIR/native_snapshot.out"

print_section "Sidecar Open"
cat "$TMP_DIR/helper_open.out"

print_section "Sidecar Tabs"
cat "$TMP_DIR/helper_tabs.out"

print_section "Sidecar Snapshot"
cat "$TMP_DIR/helper_snapshot.out"

print_section "Sidecar Find"
cat "$TMP_DIR/helper_find.out"

print_section "Infra"
printf 'server_pid: %s\n' "$SERVER_PID"
printf 'chrome_pid: %s\n' "$CHROME_PID"
printf 'cdp_url: http://127.0.0.1:%s\n' "$PORT_CDP"
printf 'test_url: %s\n' "$TEST_URL"

if [ "$native_status_value" = "PASS" ] && [ "$sidecar_status_value" = "PASS" ]; then
  printf '\nVERIFY_BROWSER_CAPABILITY_TRUTH_OK native=PASS sidecar=PASS\n'
elif [ "$sidecar_status_value" = "PASS" ]; then
  printf '\nVERIFY_BROWSER_CAPABILITY_TRUTH_OK native=BLOCKED sidecar=PASS\n'
else
  printf '\nVERIFY_BROWSER_CAPABILITY_TRUTH_FAIL native=%s sidecar=%s\n' "$native_status_value" "$sidecar_status_value"
  exit 1
fi
