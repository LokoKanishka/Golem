#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

TARGET_A_URL="${GOLEM_BROWSER_REAL_TARGET_A_URL:-https://www.iana.org/domains/reserved}"
TARGET_A_SELECTOR="${GOLEM_BROWSER_REAL_TARGET_A_SELECTOR:-Reserved Domains}"
TARGET_A_FIND="${GOLEM_BROWSER_REAL_TARGET_A_FIND:-Example domains}"

TARGET_B_URL="${GOLEM_BROWSER_REAL_TARGET_B_URL:-https://www.rfc-editor.org/rfc/rfc2606.html}"
TARGET_B_SELECTOR="${GOLEM_BROWSER_REAL_TARGET_B_SELECTOR:-rfc-editor.org}"
TARGET_B_FIND="${GOLEM_BROWSER_REAL_TARGET_B_FIND:-.localhost}"

SIDECAR_STARTED_HERE="0"
VERIFY_TMP_ROOT="$(mktemp -d)"

cleanup() {
  if [ "$SIDECAR_STARTED_HERE" = "1" ]; then
    "$SCRIPT_DIR/browser_sidecar_stop.sh" >/dev/null 2>&1 || true
  fi
  rm -rf "$VERIFY_TMP_ROOT"
}
trap cleanup EXIT

cd "$REPO_ROOT"

printf '# Browser Sidecar Real Web Verify\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"
printf 'target_a: %s\n' "$TARGET_A_URL"
printf 'target_b: %s\n' "$TARGET_B_URL"

VERIFY_PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

GOLEM_BROWSER_SIDECAR_ROOT="$VERIFY_TMP_ROOT"
GOLEM_BROWSER_SIDECAR_PORT="$VERIFY_PORT"
GOLEM_BROWSER_SIDECAR_HOST="127.0.0.1"
GOLEM_BROWSER_SIDECAR_URL="http://${GOLEM_BROWSER_SIDECAR_HOST}:${GOLEM_BROWSER_SIDECAR_PORT}"
GOLEM_BROWSER_SIDECAR_PROFILE_DIR="${GOLEM_BROWSER_SIDECAR_ROOT}/profile"
GOLEM_BROWSER_SIDECAR_PIDFILE="${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.pid"
GOLEM_BROWSER_SIDECAR_LOGFILE="${GOLEM_BROWSER_SIDECAR_ROOT}/chrome.log"

export GOLEM_BROWSER_SIDECAR_ROOT
export GOLEM_BROWSER_SIDECAR_PORT
export GOLEM_BROWSER_SIDECAR_HOST
export GOLEM_BROWSER_SIDECAR_URL
export GOLEM_BROWSER_SIDECAR_PROFILE_DIR
export GOLEM_BROWSER_SIDECAR_PIDFILE
export GOLEM_BROWSER_SIDECAR_LOGFILE

printf 'verify_sidecar_url: %s\n' "$GOLEM_BROWSER_SIDECAR_URL"

"$SCRIPT_DIR/browser_sidecar_start.sh" >/dev/null
SIDECAR_STARTED_HERE="1"

printf '\n## Sidecar Status\n'
"$SCRIPT_DIR/browser_sidecar_status.sh"

printf '\n## Open Target A\n'
open_a_output="$("$SCRIPT_DIR/browser_sidecar_open.sh" "$TARGET_A_URL")"
printf '%s\n' "$open_a_output"
sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"

printf '\n## Open Target B\n'
open_b_output="$("$SCRIPT_DIR/browser_sidecar_open.sh" "$TARGET_B_URL")"
printf '%s\n' "$open_b_output"
sleep "$GOLEM_BROWSER_SIDECAR_NAV_DELAY"

printf '\n## Tabs\n'
tabs_output="$("$SCRIPT_DIR/browser_sidecar_tabs.sh")"
printf '%s\n' "$tabs_output"

printf '\n## Select By Title Partial\n'
select_title_output="$("$SCRIPT_DIR/browser_sidecar_select.sh" "$TARGET_A_SELECTOR")"
printf '%s\n' "$select_title_output"

printf '\n## Select By URL Partial\n'
select_url_output="$("$SCRIPT_DIR/browser_sidecar_select.sh" "$TARGET_B_SELECTOR")"
printf '%s\n' "$select_url_output"

printf '\n## Select By Index\n'
select_index_output="$("$SCRIPT_DIR/browser_sidecar_select.sh" 0)"
printf '%s\n' "$select_index_output"

printf '\n## Read Target A\n'
read_a_output="$("$SCRIPT_DIR/browser_sidecar_read.sh" "$TARGET_A_SELECTOR")"
printf '%s\n' "$read_a_output"

printf '\n## Find Target A\n'
find_a_output="$("$SCRIPT_DIR/browser_sidecar_find.sh" "$TARGET_A_FIND" "$TARGET_A_SELECTOR")"
printf '%s\n' "$find_a_output"

printf '\n## Read Target B\n'
read_b_output="$("$SCRIPT_DIR/browser_sidecar_read.sh" "$TARGET_B_SELECTOR")"
printf '%s\n' "$read_b_output"

printf '\n## Find Target B\n'
find_b_output="$("$SCRIPT_DIR/browser_sidecar_find.sh" "$TARGET_B_FIND" "$TARGET_B_SELECTOR")"
printf '%s\n' "$find_b_output"

printf '\n## Classification\n'
if printf '%s\n' "$tabs_output" | grep -q 'IANA-managed Reserved Domains' && \
   printf '%s\n' "$tabs_output" | grep -q 'RFC 2606: Reserved Top Level DNS Names' && \
   printf '%s\n' "$read_a_output" | grep -q 'IANA-managed Reserved Domains' && \
   printf '%s\n' "$find_a_output" | grep -q 'Example domains' && \
   printf '%s\n' "$read_b_output" | grep -q 'RFC 2606: Reserved Top Level DNS Names' && \
   printf '%s\n' "$find_b_output" | grep -q '.localhost'; then
  printf 'browser_sidecar_real_web | PASS | public web open/tabs/select/read/find completed on stable external pages\n'
  printf '\nVERIFY_BROWSER_SIDECAR_REAL_WEB_OK\n'
else
  printf 'browser_sidecar_real_web | FAIL | one or more public web checks did not match the expected pages\n'
  printf '\nVERIFY_BROWSER_SIDECAR_REAL_WEB_FAIL\n'
  exit 1
fi
