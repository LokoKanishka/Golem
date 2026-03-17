#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
OUTBOX_REL="outbox/manual"
TIMESTAMP="$(
  python3 - <<'PY'
import datetime
print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
PY
)"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-live-send-path.md"
TASK_ID=""

RESULT_NAMES=()
RESULT_CLASSES=()
RESULT_NOTES=()

mkdir -p "$OUTBOX_DIR"

append_result() {
  RESULT_NAMES+=("$1")
  RESULT_CLASSES+=("$2")
  RESULT_NOTES+=("$3")
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

run_cmd() {
  local label="$1"
  local cmd="$2"
  local output exit_code

  printf '\n## %s\n' "$label"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf 'exit_code: %s\n' "$exit_code"
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
  fi
  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

extract_task_id() {
  printf '%s\n' "$1" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Live Send Path Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report determines whether the current repository exposes a canonical live WhatsApp send path.

Canonical means all of the following:

- repo-local entrypoint under the repo surface
- invocable without hidden manual steps
- auditable by \`task_id\`
- compatible with \`delivery.whatsapp\`
- able to persist evidence such as \`message_id\` when available
- honest semantic separation between \`requested\`, \`accepted_by_gateway\`, \`delivered\`, and \`verified_by_user\`
EOF
}

record_verify_task() {
  local final_status="$1"
  local final_note="$2"
  local summary_json="$3"
  local report_rel="${REPORT_PATH#$REPO_ROOT/}"
  local exit_code="1"

  case "$final_status" in
    PASS) exit_code="0" ;;
    BLOCKED) exit_code="2" ;;
  esac

  ./scripts/task_add_artifact.sh "$TASK_ID" whatsapp-live-send-path-report "$report_rel" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$(python3 - "$summary_json" "$report_rel" <<'PY'
import json
import sys
print(json.dumps({"classification_summary": json.loads(sys.argv[1]), "report_path": sys.argv[2]}, ensure_ascii=True))
PY
)" ./scripts/task_add_output.sh "$TASK_ID" whatsapp-live-send-path "$exit_code" "$final_note" >/dev/null

  case "$final_status" in
    PASS) ./scripts/task_close.sh "$TASK_ID" done "$final_note" >/dev/null ;;
    BLOCKED) ./scripts/task_close.sh "$TASK_ID" blocked "$final_note" >/dev/null ;;
    *) ./scripts/task_close.sh "$TASK_ID" failed "$final_note" >/dev/null ;;
  esac
}

generate_header

printf '# WhatsApp Live Send Path Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Create Verify Task" "./scripts/task_new.sh verification-whatsapp-live-send-path 'Verify canonical WhatsApp live send path'"
TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
if [ -z "$TASK_ID" ]; then
  printf 'VERIFY_WHATSAPP_LIVE_SEND_PATH_FAIL report=%s dominant_blocker=task_creation_failed\n' "$REPORT_PATH" >&2
  exit 1
fi

run_cmd "Move Verify Task To Running" "./scripts/task_update.sh $TASK_ID running"

run_cmd "Repo Wrapper Search" "find scripts -maxdepth 1 -type f | sort | rg 'task_run_whatsapp.*send|task_run_.*whatsapp.*send|task_whatsapp_live_send|whatsapp_live_send_adapter|whatsapp_live_send_runner'"
wrapper_output="$LAST_OUTPUT"
wrapper_exit="$LAST_EXIT_CODE"
if [ "$wrapper_exit" -eq 0 ] && [ -n "$wrapper_output" ]; then
  append_result "repo wrapper path" "present_but_not_invocable" "repo-side WhatsApp send candidates exist, but this verify still needs to confirm task_id auditability and delivery.whatsapp integration"
else
  append_result "repo wrapper path" "missing" "no repo-local wrapper script for live WhatsApp send exists under scripts/"
fi

run_cmd "Truth Lane Search" "find scripts -maxdepth 1 -type f | sort | rg 'task_record_whatsapp_delivery|task_claim_whatsapp_delivery|verify_whatsapp_delivery_claim_truth'"
truth_output="$LAST_OUTPUT"
if printf '%s\n' "$truth_output" | rg -q 'task_record_whatsapp_delivery\.sh' && \
   printf '%s\n' "$truth_output" | rg -q 'task_claim_whatsapp_delivery\.sh'; then
  append_result "delivery.whatsapp truth lane" "auditable_but_not_canonical" "the repo can persist WhatsApp claim truth and drift detection, but these scripts do not perform a live send"
else
  append_result "delivery.whatsapp truth lane" "missing" "the repo is missing one or more canonical WhatsApp truth scripts"
fi

run_cmd "CLI Surface Help" "openclaw message send --help"
cli_help_output="$LAST_OUTPUT"
cli_help_exit="$LAST_EXIT_CODE"
if [ "$cli_help_exit" -eq 0 ] && printf '%s\n' "$cli_help_output" | rg -q -- '--channel <channel>' && printf '%s\n' "$cli_help_output" | rg -q -- '--dry-run'; then
  append_result "openclaw message send help" "present_but_not_invocable" "the host CLI exposes a WhatsApp-capable send surface with json and dry-run options, but help text alone is not a task-bound canonical repo path"
else
  append_result "openclaw message send help" "missing" "the host CLI help does not expose the expected send surface"
fi

run_cmd "CLI Dry Run Probe" "openclaw message send --channel whatsapp --target +5491100000000 --message 'GOLEM-208 dry run probe' --dry-run --json"
dry_run_output="$LAST_OUTPUT"
dry_run_exit="$LAST_EXIT_CODE"
if [ "$dry_run_exit" -eq 0 ] && printf '%s\n' "$dry_run_output" | rg -q '"channel": "whatsapp"' && printf '%s\n' "$dry_run_output" | rg -q '"dryRun": true'; then
  append_result "openclaw message send dry-run" "invocable_but_not_auditable" "the host CLI can be invoked safely and returns machine-readable WhatsApp payload evidence, but the current repo does not bind it to task_id or persist delivery.whatsapp automatically"
else
  append_result "openclaw message send dry-run" "present_but_not_invocable" "the host CLI send surface exists but did not complete a safe dry-run probe coherently"
fi

run_cmd "Channel Status Probe" "openclaw channels status"
channels_output="$LAST_OUTPUT"
channels_exit="$LAST_EXIT_CODE"
if [ "$channels_exit" -eq 0 ] && printf '%s\n' "$channels_output" | rg -q 'WhatsApp' && printf '%s\n' "$channels_output" | rg -q 'connected'; then
  append_result "whatsapp runtime channel" "auditable_but_not_canonical" "the host runtime shows WhatsApp connected, so the dominant gap is not a missing channel session but the lack of a canonical repo-local task-bound wrapper"
else
  append_result "whatsapp runtime channel" "canonical_but_runtime_blocked" "the host send surface exists but the channel runtime is not ready enough to support a canonical live send path"
fi

pass_like=0
blocked_like=0
fail_like=0

overall_status="BLOCKED"
overall_note="no canonical repo-local WhatsApp live send path is currently exposed: the host CLI send surface exists, but the repo still lacks a task-bound canonical wrapper"
dominant_blocker="repo_canonical_whatsapp_live_send_wrapper_missing"

if [ "$wrapper_exit" -eq 0 ] && [ -n "$wrapper_output" ] && [ "$dry_run_exit" -eq 0 ]; then
  overall_status="PASS"
  overall_note="a canonical repo-local WhatsApp live send wrapper exists and the host CLI send surface is invocable with machine-readable evidence"
  dominant_blocker="none"
fi

if [ "$cli_help_exit" -ne 0 ] || [ "$channels_exit" -ne 0 ]; then
  overall_status="FAIL"
  overall_note="the WhatsApp live send path verify could not classify the candidate surface coherently"
  dominant_blocker="verify_inconsistency_or_missing_cli_surface"
fi

for class in "${RESULT_CLASSES[@]}"; do
  case "$class" in
    canonical_and_usable)
      pass_like=$((pass_like + 1))
      ;;
    missing|present_but_not_invocable|invocable_but_not_auditable|auditable_but_not_canonical|canonical_but_runtime_blocked)
      blocked_like=$((blocked_like + 1))
      ;;
    *)
      fail_like=$((fail_like + 1))
      ;;
  esac
done

summary_json="$(python3 - <<'PY' "${RESULT_NAMES[@]}" __CLASSES__ "${RESULT_CLASSES[@]}" __NOTES__ "${RESULT_NOTES[@]}"
import json
import sys

args = sys.argv[1:]
split_classes = args.index("__CLASSES__")
split_notes = args.index("__NOTES__")
names = args[:split_classes]
classes = args[split_classes + 1:split_notes]
notes = args[split_notes + 1:]
rows = []
for name, klass, note in zip(names, classes, notes):
    rows.append({"candidate": name, "classification": klass, "note": note})
print(json.dumps(rows, ensure_ascii=True))
PY
)"

record_verify_task "$overall_status" "$overall_note" "$summary_json"

printf '\ncandidate/check | classification | note\n'
append_report "" "## Candidate Classification" "candidate/check | classification | note"
for index in "${!RESULT_NAMES[@]}"; do
  printf '%s | %s | %s\n' "${RESULT_NAMES[$index]}" "${RESULT_CLASSES[$index]}" "${RESULT_NOTES[$index]}"
  append_report "${RESULT_NAMES[$index]} | ${RESULT_CLASSES[$index]} | ${RESULT_NOTES[$index]}"
done

append_report "" "## Overall Conclusion" "task_id: $TASK_ID" "pass_like: $pass_like" "blocked_like: $blocked_like" "fail_like: $fail_like" "overall_status: $overall_status" "overall_note: $overall_note" "dominant_blocker: $dominant_blocker"

printf 'task_id: %s\n' "$TASK_ID"
printf 'pass_like: %s\n' "$pass_like"
printf 'blocked_like: %s\n' "$blocked_like"
printf 'fail_like: %s\n' "$fail_like"
printf 'overall_status: %s\n' "$overall_status"
printf 'overall_note: %s\n' "$overall_note"
printf 'dominant_blocker: %s\n' "$dominant_blocker"
printf 'report_path: %s\n' "$REPORT_PATH"

case "$overall_status" in
  PASS)
    printf 'VERIFY_WHATSAPP_LIVE_SEND_PATH_OK task=%s report=%s dominant_blocker=%s\n' "$TASK_ID" "$REPORT_PATH" "$dominant_blocker"
    exit 0
    ;;
  BLOCKED)
    printf 'VERIFY_WHATSAPP_LIVE_SEND_PATH_BLOCKED task=%s report=%s dominant_blocker=%s\n' "$TASK_ID" "$REPORT_PATH" "$dominant_blocker"
    exit 2
    ;;
  *)
    printf 'VERIFY_WHATSAPP_LIVE_SEND_PATH_FAIL task=%s report=%s dominant_blocker=%s\n' "$TASK_ID" "$REPORT_PATH" "$dominant_blocker" >&2
    exit 1
    ;;
esac
