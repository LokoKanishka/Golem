#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/browser_sidecar_common.sh"

TASK_MANIFEST="${1:-browser_tasks/prioritize-golem-openclaw-next-tranche.json}"
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

printf '# Browser Sidecar Project Prioritization Lane Verify\n'
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

printf '\n## Prioritization Task Run\n'
prioritization_output="$("$SCRIPT_DIR/browser_sidecar_prioritization_run.sh" "$TASK_MANIFEST" 2>&1)"
printf '%s\n' "$prioritization_output"

printf '\n## Classification\n'
if printf '%s\n' "$prioritization_output" | grep -q 'artifact_kind: browser-sidecar-project-prioritization' && \
   printf '%s\n' "$prioritization_output" | grep -q '## Priority Matrix' && \
   printf '%s\n' "$prioritization_output" | grep -q '## Final Prioritization' && \
   printf '%s\n' "$prioritization_output" | grep -q 'PRIORITIZATION_FINAL_ARTIFACT_JSON' && \
   printf '%s\n' "$prioritization_output" | grep -q 'PRIORITIZATION_FINAL_ARTIFACT_MD'; then
  printf 'browser_sidecar_prioritization_lane | PASS | project fronts were ranked into explicit buckets with versioned local and public evidence\n'
  printf '\nVERIFY_BROWSER_SIDECAR_PRIORITIZATION_LANE_OK\n'
else
  printf 'browser_sidecar_prioritization_lane | FAIL | prioritization lane did not emit the expected matrix/bucket markers\n'
  printf '\nVERIFY_BROWSER_SIDECAR_PRIORITIZATION_LANE_FAIL\n'
  exit 1
fi
