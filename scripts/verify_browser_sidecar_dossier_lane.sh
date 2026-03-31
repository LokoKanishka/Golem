#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

TASK_MANIFEST="${1:-browser_tasks/reserved-domains-technical.json}"
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

printf '# Browser Sidecar Dossier Lane Verify\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"
printf 'task_manifest: %s\n' "$TASK_MANIFEST"

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
GOLEM_BROWSER_SIDECAR_OUTBOX_DIR="${GOLEM_BROWSER_SIDECAR_REPO_ROOT}/outbox/manual"

export GOLEM_BROWSER_SIDECAR_ROOT
export GOLEM_BROWSER_SIDECAR_PORT
export GOLEM_BROWSER_SIDECAR_HOST
export GOLEM_BROWSER_SIDECAR_URL
export GOLEM_BROWSER_SIDECAR_PROFILE_DIR
export GOLEM_BROWSER_SIDECAR_PIDFILE
export GOLEM_BROWSER_SIDECAR_LOGFILE
export GOLEM_BROWSER_SIDECAR_OUTBOX_DIR

printf 'verify_sidecar_url: %s\n' "$GOLEM_BROWSER_SIDECAR_URL"

"$SCRIPT_DIR/browser_sidecar_start.sh" >/dev/null
SIDECAR_STARTED_HERE="1"

printf '\n## Sidecar Status\n'
"$SCRIPT_DIR/browser_sidecar_status.sh"

printf '\n## Dossier Task Run\n'
dossier_output="$("$SCRIPT_DIR/browser_sidecar_dossier_run.sh" "$TASK_MANIFEST" 2>&1)"
printf '%s\n' "$dossier_output"

printf '\n## Classification\n'
if printf '%s\n' "$dossier_output" | grep -q 'artifact_kind: browser-sidecar-dossier' && \
   printf '%s\n' "$dossier_output" | grep -q '## Sources' && \
   printf '%s\n' "$dossier_output" | grep -q '## Comparisons' && \
   printf '%s\n' "$dossier_output" | grep -q 'DOSSIER_FINAL_ARTIFACT_JSON' && \
   printf '%s\n' "$dossier_output" | grep -q 'DOSSIER_FINAL_ARTIFACT_MD'; then
  printf 'browser_sidecar_dossier_lane | PASS | declarative task run produced extracts, compares and a final dossier artifact\n'
  printf '\nVERIFY_BROWSER_SIDECAR_DOSSIER_LANE_OK\n'
else
  printf 'browser_sidecar_dossier_lane | FAIL | dossier lane did not emit the expected final report markers\n'
  printf '\nVERIFY_BROWSER_SIDECAR_DOSSIER_LANE_FAIL\n'
  exit 1
fi
