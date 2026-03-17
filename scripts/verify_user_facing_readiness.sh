#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
TIMESTAMP="$(
  python3 - <<'PY'
import datetime
print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
PY
)"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-user-facing-readiness.md"

RESULT_NAMES=()
RESULT_STATUSES=()
RESULT_NOTES=()
RESULT_ARTIFACTS=()

mkdir -p "$OUTBOX_DIR"

append_result() {
  RESULT_NAMES+=("$1")
  RESULT_STATUSES+=("$2")
  RESULT_NOTES+=("$3")
  RESULT_ARTIFACTS+=("$4")
}

append_report() {
  python3 - "$REPORT_PATH" "$@" <<'PY'
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
with report_path.open("a", encoding="utf-8") as fh:
    for line in sys.argv[2:]:
        fh.write(line + "\n")
PY
}

extract_report_path_from_output() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1]
for pattern in (r"^report_path: (\S+)$", r"^REPORT_PATH (\S+)$"):
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        print(match.group(1))
        raise SystemExit(0)
for pattern in (
    r"^VERIFY_[A-Z0-9_]+_(?:OK|BLOCKED|FAIL)\b.*\breport=(\S+)",
    r"^VERIFY_DONE (\S+)$",
):
    match = re.search(pattern, text, re.MULTILINE)
    if match:
        print(match.group(1))
        raise SystemExit(0)
print("")
PY
}

run_capability() {
  local name="$1"
  local cmd="$2"
  local ok_marker="$3"
  local blocked_marker="${4:-}"
  local fail_note="$5"
  local pass_note="$6"
  local blocked_note="${7:-}"
  local output exit_code status artifact_path

  printf '\n## %s\n' "$name"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"

  artifact_path="$(extract_report_path_from_output "$output")"
  status="FAIL"
  if [ "$exit_code" -eq 0 ] && printf '%s\n' "$output" | rg -q "^${ok_marker}\b"; then
    status="PASS"
  elif [ -n "$blocked_marker" ] && [ "$exit_code" -eq 2 ] && printf '%s\n' "$output" | rg -q "^${blocked_marker}\b"; then
    status="BLOCKED"
  elif [ "$exit_code" -eq 2 ] && printf '%s\n' "$output" | rg -q '^VERIFY_.*_BLOCKED\b'; then
    status="BLOCKED"
  fi

  case "$status" in
    PASS) append_result "$name" "$status" "$pass_note" "$artifact_path" ;;
    BLOCKED) append_result "$name" "$status" "$blocked_note" "$artifact_path" ;;
    *) append_result "$name" "$status" "$fail_note" "$artifact_path" ;;
  esac
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# User-Facing Readiness Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report aggregates the canonical user-facing verification lanes without reimplementing their internal logic.
EOF
}

cd "$REPO_ROOT"
generate_header

printf '# User-Facing Readiness Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_capability \
  "delivery truth" \
  "bash ./scripts/verify_user_facing_delivery_truth.sh" \
  "VERIFY_USER_FACING_DELIVERY_TRUTH_OK" \
  "" \
  "user-facing delivery truth verify failed internally or stopped proving the canonical claim guardrail" \
  "user-facing delivery truth verify passed: accepted stays below visible, visible authorizes the generic claim, and drift is rejected" \
  ""

run_capability \
  "visible artifact truth" \
  "bash ./scripts/verify_visible_artifact_delivery_truth.sh" \
  "VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_OK" \
  "VERIFY_VISIBLE_ARTIFACT_DELIVERY_TRUTH_BLOCKED" \
  "visible artifact delivery truth verify failed internally or exposed path/verification drift" \
  "visible artifact delivery truth verify passed: canonical desktop/downloads delivery stayed auditable and claim-gated" \
  "visible artifact delivery truth remains externally blocked because a canonical visible destination could not be proven in the current environment"

run_capability \
  "whatsapp delivery truth" \
  "bash ./scripts/verify_whatsapp_delivery_claim_truth.sh" \
  "VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_OK" \
  "" \
  "whatsapp delivery claim truth verify failed internally or stopped degrading claims honestly" \
  "whatsapp delivery claim truth verify passed: gateway acceptance, delivered evidence, user confirmation, and drift stayed semantically separated" \
  ""

run_capability \
  "media ingestion truth" \
  "bash ./scripts/verify_media_ingestion_truth.sh" \
  "VERIFY_MEDIA_INGESTION_TRUTH_OK" \
  "" \
  "media ingestion truth verify failed internally or stopped proving canonical file identity before downstream delivery use" \
  "media ingestion truth verify passed: internal, visible, and local media paths stayed auditable and drift-aware" \
  ""

run_capability \
  "host screenshot truth" \
  "bash ./scripts/verify_host_screenshot_truth.sh" \
  "VERIFY_HOST_SCREENSHOT_TRUTH_OK" \
  "" \
  "host screenshot truth verify failed internally or stopped proving captured-versus-verified visual evidence" \
  "host screenshot truth verify passed: host visual evidence stayed blocked before verification and failed on identity drift" \
  ""

pass_count=0
blocked_count=0
fail_count=0
for status in "${RESULT_STATUSES[@]}"; do
  case "$status" in
    PASS) pass_count=$((pass_count + 1)) ;;
    BLOCKED) blocked_count=$((blocked_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
  esac
done

overall_status="PASS"
overall_note="all critical user-facing verification lanes passed"
if [ "$fail_count" -gt 0 ]; then
  overall_status="FAIL"
  overall_note="at least one critical user-facing verification lane failed internally or exposed drift/inconsistency"
elif [ "$blocked_count" -gt 0 ]; then
  overall_status="BLOCKED"
  overall_note="no critical user-facing verification lane failed, but at least one remains externally blocked"
fi

printf '\nsubsystem/check | status | note\n'
append_report "" "## Aggregated Results" "subsystem/check | status | note | artifact"
for index in "${!RESULT_NAMES[@]}"; do
  printf '%s | %s | %s\n' "${RESULT_NAMES[$index]}" "${RESULT_STATUSES[$index]}" "${RESULT_NOTES[$index]}"
  append_report "${RESULT_NAMES[$index]} | ${RESULT_STATUSES[$index]} | ${RESULT_NOTES[$index]} | ${RESULT_ARTIFACTS[$index]:-(none)}"
done

printf 'PASS: %s\n' "$pass_count"
printf 'FAIL: %s\n' "$fail_count"
printf 'BLOCKED: %s\n' "$blocked_count"
printf 'overall_status: %s\n' "$overall_status"
printf 'overall_note: %s\n' "$overall_note"

append_report "" "PASS: $pass_count" "FAIL: $fail_count" "BLOCKED: $blocked_count" "overall_status: $overall_status" "overall_note: $overall_note"
printf 'report_path: %s\n' "$REPORT_PATH"

if [ "$fail_count" -gt 0 ]; then
  printf 'VERIFY_USER_FACING_READINESS_FAIL pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
  exit 1
fi

if [ "$blocked_count" -gt 0 ]; then
  printf 'VERIFY_USER_FACING_READINESS_BLOCKED pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
  exit 2
fi

printf 'VERIFY_USER_FACING_READINESS_OK pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
