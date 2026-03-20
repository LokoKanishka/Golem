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
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-whatsapp-status-temporal-evolution.md"
TASK_ID=""
TARGET=""
CHECKPOINTS_RAW="${GOLEM_WHATSAPP_STATUS_CHECKPOINTS:-0,10,30,60,120,300}"

usage() {
  cat <<USAGE
Uso:
  ./scripts/verify_whatsapp_status_temporal_evolution.sh [--target <whatsapp_target>] [--checkpoints <csv_seconds>]
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      shift
      TARGET="${1:-}"
      ;;
    --checkpoints)
      shift
      CHECKPOINTS_RAW="${1:-}"
      ;;
    *)
      usage
      printf 'ERROR: argumento no soportado: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift || true
done

mkdir -p "$OUTBOX_DIR"

run_cmd() {
  local label="$1"
  local cmd="$2"
  local output
  local exit_code

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

record_verify_task() {
  local final_status="$1"
  local final_note="$2"
  local summary_json="$3"
  local report_rel="${REPORT_PATH#$REPO_ROOT/}"
  local exit_code="1"

  case "$final_status" in
    PASS) exit_code="0" ;;
    BLOCKED|INTERMEDIATE) exit_code="2" ;;
  esac

  ./scripts/task_add_artifact.sh "$TASK_ID" whatsapp-status-temporal-evolution-report "$report_rel" >/dev/null
  TASK_OUTPUT_EXTRA_JSON="$summary_json" ./scripts/task_add_output.sh "$TASK_ID" whatsapp-status-temporal-evolution "$exit_code" "$final_note" >/dev/null

  case "$final_status" in
    PASS) ./scripts/task_close.sh "$TASK_ID" done "$final_note" >/dev/null ;;
    BLOCKED|INTERMEDIATE) ./scripts/task_close.sh "$TASK_ID" blocked "$final_note" >/dev/null ;;
    *) ./scripts/task_close.sh "$TASK_ID" failed "$final_note" >/dev/null ;;
  esac
}

generate_header() {
  cat >"$REPORT_PATH" <<EOF
# WhatsApp Status Temporal Evolution Verify

generated_at: $(date -u --iso-8601=seconds)
repo: $REPO_ROOT

This report answers one operational question:

Does the canonical WhatsApp status surface evolve over time for a real outbound message,
or does it stay at sent/server_ack under controlled polling?
EOF
}

generate_header

printf '# WhatsApp Status Temporal Evolution Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd "Create Verify Task" "./scripts/task_new.sh verification-whatsapp-status-temporal-evolution 'Verify WhatsApp status temporal evolution'"
TASK_ID="$(extract_task_id "$LAST_OUTPUT")"
if [ -z "$TASK_ID" ]; then
  printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_FAIL report=%s task=(missing) reason=task_creation_failed\n' "$REPORT_PATH" >&2
  exit 1
fi

run_cmd "Move Verify Task To Running" "./scripts/task_update.sh $TASK_ID running"

target_source="explicit-arg"
target_note="provided explicitly via --target"
if [ -z "$TARGET" ]; then
  run_cmd "Resolve Canary Target" "./scripts/resolve_whatsapp_canary_target.sh --json"
  target_json="$LAST_OUTPUT"
  target_exit="$LAST_EXIT_CODE"
  TARGET="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("target", ""))
except Exception:
    print("")
PY
)"
  target_source="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("source", ""))
except Exception:
    print("")
PY
)"
  target_note="$(python3 - "$target_json" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("note", ""))
except Exception:
    print("")
PY
)"
  if [ "${target_exit:-1}" -ne 0 ] || [ -z "$TARGET" ]; then
    final_status="BLOCKED"
    final_note="no canonical safe WhatsApp target is currently resolvable for temporal status polling"
    summary_json="$(python3 - "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "task_id": "",
    "target": "",
    "message_id": "",
    "dictamen": "BLOCKED_GOLEM_WHATSAPP_STATUS_EVOLUTION_INCONSISTENT",
    "report_path": sys.argv[1],
}, ensure_ascii=True))
PY
)"
    append_report "" "## Target Resolution" "- verify_status: BLOCKED" "- note: ${final_note}"
    record_verify_task "$final_status" "$final_note" "$summary_json"
    printf 'report_path: %s\n' "$REPORT_PATH"
    printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_BLOCKED task=%s report=%s reason=target_unresolved\n' "$TASK_ID" "$REPORT_PATH"
    exit 2
  fi
fi

canary_message="GOLEM-212 status timeline ${TIMESTAMP}"
run_cmd "Live Temporal Send" "./scripts/task_send_whatsapp_live.sh $TASK_ID $TARGET --message '$canary_message' --actor verify-whatsapp-status-temporal-evolution --evidence 'controlled temporal status probe' --json"
send_output="$LAST_OUTPUT"
send_exit="$LAST_EXIT_CODE"
wrapper_status="$(python3 - "$send_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("wrapper_status", ""))
except Exception:
    print("")
PY
)"
wrapper_state="$(python3 - "$send_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("wrapper_state", ""))
except Exception:
    print("")
PY
)"
message_id="$(python3 - "$send_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("message_id", ""))
except Exception:
    print("")
PY
)"
send_report="$(python3 - "$send_output" <<'PY'
import json
import sys
try:
    print(json.loads(sys.argv[1]).get("report_path", ""))
except Exception:
    print("")
PY
)"

if [ "$send_exit" -ne 0 ] || [ -z "$message_id" ]; then
  final_status="FAIL"
  final_note="the live send did not produce an auditable WhatsApp message_id for temporal polling"
  summary_json="$(python3 - "$TASK_ID" "$TARGET" "$REPORT_PATH" <<'PY'
import json
import sys
print(json.dumps({
    "task_id": sys.argv[1],
    "target": sys.argv[2],
    "message_id": "",
    "dictamen": "BLOCKED_GOLEM_WHATSAPP_STATUS_EVOLUTION_INCONSISTENT",
    "report_path": sys.argv[3],
}, ensure_ascii=True))
PY
)"
  append_report "" "## Live Temporal Send" "- verify_status: FAIL" "- wrapper_status: ${wrapper_status:-'(none)'}" "- wrapper_state: ${wrapper_state:-'(none)'}" "- note: ${final_note}"
  record_verify_task "$final_status" "$final_note" "$summary_json"
  printf 'report_path: %s\n' "$REPORT_PATH"
  printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_FAIL task=%s report=%s reason=message_id_missing\n' "$TASK_ID" "$REPORT_PATH" >&2
  exit 1
fi

timeline_file="$(mktemp)"
trap 'rm -f "$timeline_file"' EXIT

checkpoints_json="$(python3 - "$CHECKPOINTS_RAW" <<'PY'
import json
import sys

raw = sys.argv[1]
values = []
for chunk in raw.split(","):
    piece = chunk.strip()
    if not piece:
        continue
    value = int(piece)
    if value < 0:
        raise SystemExit("negative checkpoints are not allowed")
    values.append(value)
values = sorted(dict.fromkeys(values))
if not values:
    raise SystemExit("no checkpoints")
print(json.dumps(values, ensure_ascii=True))
PY
)"

start_epoch="$(date +%s)"
last_checkpoint="0"

python3 - "$timeline_file" "$checkpoints_json" >/dev/null <<'PY'
import json
import pathlib
import sys
pathlib.Path(sys.argv[1]).write_text("", encoding="utf-8")
json.loads(sys.argv[2])
PY

mapfile -t checkpoints < <(python3 - "$checkpoints_json" <<'PY'
import json
import sys
for value in json.loads(sys.argv[1]):
    print(value)
PY
)

for checkpoint in "${checkpoints[@]}"; do
  now_epoch="$(date +%s)"
  elapsed="$((now_epoch - start_epoch))"
  if [ "$checkpoint" -gt "$elapsed" ]; then
    sleep "$((checkpoint - elapsed))"
  fi
  run_cmd "Status T+${checkpoint}s" "openclaw message status --channel whatsapp --id $message_id --json"
  poll_output="$LAST_OUTPUT"
  poll_exit="$LAST_EXIT_CODE"
  poll_json="$(python3 - "$poll_output" <<'PY'
import json
import sys

text = sys.argv[1]
decoder = json.JSONDecoder()
for index, ch in enumerate(text):
    if ch != "{":
        continue
    try:
        obj, _ = decoder.raw_decode(text[index:])
        print(json.dumps(obj, ensure_ascii=True))
        raise SystemExit(0)
    except Exception:
        continue
print("")
PY
)"
  python3 - "$timeline_file" "$checkpoint" "$poll_exit" "$poll_json" "$poll_output" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
checkpoint = int(sys.argv[2])
exit_code = int(sys.argv[3])
payload_raw = sys.argv[4]
raw_output = sys.argv[5]
payload = json.loads(payload_raw) if payload_raw else {}

def normalize(value):
    if value is None:
        return ""
    text = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "delivery_ack": "delivered",
        "read_by_recipient": "read",
        "provider_delivered": "delivered",
    }
    return aliases.get(text, text)

entry = {
    "t_plus_seconds": checkpoint,
    "exit_code": exit_code,
    "found": payload.get("found"),
    "currentStatus": payload.get("currentStatus") or payload.get("current_status") or "",
    "strongestStatus": payload.get("strongestStatus") or payload.get("strongest_status") or "",
    "normalizedCurrentStatus": normalize(payload.get("currentStatus") or payload.get("current_status") or ""),
    "normalizedStrongestStatus": normalize(payload.get("strongestStatus") or payload.get("strongest_status") or ""),
    "latestEventAt": payload.get("latestEventAt") or payload.get("latest_event_at") or "",
    "raw_payload": payload,
    "raw_output_excerpt": " ".join(raw_output.replace("\r", " ").replace("\n", " ").split())[:280],
}
with path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=True) + "\n")
PY
  last_checkpoint="$checkpoint"
done

timeline_summary="$(python3 - "$timeline_file" <<'PY'
import json
import pathlib
import sys

entries = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
strong = {"delivered", "read", "played"}
intermediate = {"server_ack"}
sent_only = {"sent"}

observed = []
for entry in entries:
    status = entry.get("normalizedStrongestStatus") or entry.get("normalizedCurrentStatus") or ""
    if status:
        observed.append(status)

observed_set = set(observed)
final_entry = entries[-1] if entries else {}
final_status = (final_entry.get("normalizedStrongestStatus") or final_entry.get("normalizedCurrentStatus") or "")

if entries and any(status in strong for status in observed):
    dictamen = "PASS_GOLEM_WHATSAPP_STATUS_ESCALATES_TO_STRONG_SIGNAL"
    verify_status = "PASS"
    note = "the canonical WhatsApp status surface escalated to a strong signal during the controlled polling window"
elif entries and observed_set and observed_set <= sent_only:
    dictamen = "BLOCKED_GOLEM_WHATSAPP_STATUS_NEVER_ESCALATES_BEYOND_SENT"
    verify_status = "BLOCKED"
    note = "the canonical WhatsApp status surface stayed at sent for the full controlled polling window"
elif entries and observed_set and observed_set <= (sent_only | intermediate):
    dictamen = "INTERMEDIATE_GOLEM_WHATSAPP_STATUS_STOPS_AT_SENT_OR_SERVER_ACK"
    verify_status = "INTERMEDIATE"
    note = "the canonical WhatsApp status surface did not reach delivered/read/played and stopped at sent/server_ack"
else:
    dictamen = "BLOCKED_GOLEM_WHATSAPP_STATUS_EVOLUTION_INCONSISTENT"
    verify_status = "BLOCKED"
    note = "the canonical WhatsApp status surface did not evolve coherently enough to classify as a stable sent/server_ack or strong-signal pattern"

print(json.dumps({
    "entries": entries,
    "observed_statuses": observed,
    "observed_status_set": sorted(observed_set),
    "final_status": final_status,
    "verify_status": verify_status,
    "dictamen": dictamen,
    "note": note,
}, ensure_ascii=True))
PY
)"

verify_status="$(python3 - "$timeline_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("verify_status", "FAIL"))
PY
)"
dictamen="$(python3 - "$timeline_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("dictamen", "BLOCKED_GOLEM_WHATSAPP_STATUS_EVOLUTION_INCONSISTENT"))
PY
)"
final_note="$(python3 - "$timeline_summary" <<'PY'
import json
import sys
print(json.loads(sys.argv[1]).get("note", ""))
PY
)"
observed_statuses="$(python3 - "$timeline_summary" <<'PY'
import json
import sys
print(",".join(json.loads(sys.argv[1]).get("observed_statuses", [])))
PY
)"

final_strongest="$(python3 - "$timeline_summary" <<'PY'
import json
import sys
entries = json.loads(sys.argv[1]).get("entries", [])
if not entries:
    print("")
else:
    last = entries[-1]
    print(last.get("normalizedStrongestStatus") or last.get("normalizedCurrentStatus") or "")
PY
)"

if [ "$verify_status" = "PASS" ]; then
  ./scripts/task_record_whatsapp_provider_delivery.sh \
    "$TASK_ID" \
    verify-whatsapp-status-temporal-evolution \
    core \
    "$TARGET" \
    "$message_id" \
    delivered \
    "$(python3 - "$timeline_summary" <<'PY'
import json
import sys
entries = json.loads(sys.argv[1]).get("entries", [])
last = entries[-1] if entries else {}
print((last.get("raw_output_excerpt") or "")[:240])
PY
)" \
    --run-id "verify-whatsapp-status-temporal-evolution" \
    --provider-status "$final_strongest" \
    --reason "$final_note" \
    --normalized-evidence-json "$timeline_summary" >/dev/null
elif [ -n "$final_strongest" ]; then
  ./scripts/task_record_whatsapp_provider_delivery.sh \
    "$TASK_ID" \
    verify-whatsapp-status-temporal-evolution \
    core \
    "$TARGET" \
    "$message_id" \
    ambiguous \
    "$(python3 - "$timeline_summary" <<'PY'
import json
import sys
entries = json.loads(sys.argv[1]).get("entries", [])
last = entries[-1] if entries else {}
print((last.get("raw_output_excerpt") or "")[:240])
PY
)" \
    --run-id "verify-whatsapp-status-temporal-evolution" \
    --provider-status "$final_strongest" \
    --reason "$final_note" \
    --normalized-evidence-json "$timeline_summary" >/dev/null
fi

run_cmd "Delivery Summary" "./scripts/task_delivery_summary.sh $TASK_ID"
delivery_summary="$LAST_OUTPUT"

append_report \
  "" \
  "## Temporal Probe" \
  "- task_id: ${TASK_ID}" \
  "- target: ${TARGET}" \
  "- target_source: ${target_source}" \
  "- target_note: ${target_note}" \
  "- message_id: ${message_id}" \
  "- wrapper_status: ${wrapper_status}" \
  "- wrapper_state: ${wrapper_state}" \
  "- send_report: ${send_report}" \
  "- checkpoints: ${CHECKPOINTS_RAW}" \
  "- observed_statuses: ${observed_statuses:-'(none)'}" \
  "- dictamen: ${dictamen}" \
  "- final_note: ${final_note}" \
  "" \
  "## Timeline"

python3 - "$timeline_summary" "$REPORT_PATH" <<'PY'
import json
import pathlib
import sys

summary = json.loads(sys.argv[1])
report = pathlib.Path(sys.argv[2])
with report.open("a", encoding="utf-8") as fh:
    fh.write("| T+ | found | currentStatus | strongestStatus | latestEventAt |\n")
    fh.write("| --- | --- | --- | --- | --- |\n")
    for entry in summary.get("entries", []):
        fh.write(
            f"| {entry.get('t_plus_seconds')}s | {entry.get('found')} | "
            f"{entry.get('normalizedCurrentStatus') or '(none)'} | "
            f"{entry.get('normalizedStrongestStatus') or '(none)'} | "
            f"{entry.get('latestEventAt') or '(none)'} |\n"
        )
PY

append_report \
  "" \
  "## Delivery Summary" \
  '```text' \
  "$delivery_summary" \
  '```'

summary_json="$(python3 - "$TASK_ID" "$TARGET" "$message_id" "$dictamen" "$REPORT_PATH" "$timeline_summary" <<'PY'
import json
import sys

payload = {
    "task_id": sys.argv[1],
    "target": sys.argv[2],
    "message_id": sys.argv[3],
    "dictamen": sys.argv[4],
    "report_path": sys.argv[5],
    "timeline": json.loads(sys.argv[6]),
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
record_verify_task "$verify_status" "$final_note" "$summary_json"

printf 'task_id: %s\n' "$TASK_ID"
printf 'target: %s\n' "$TARGET"
printf 'message_id: %s\n' "$message_id"
printf 'wrapper_status: %s\n' "$wrapper_status"
printf 'wrapper_state: %s\n' "$wrapper_state"
printf 'observed_statuses: %s\n' "${observed_statuses:-(none)}"
printf 'dictamen: %s\n' "$dictamen"
printf 'report_path: %s\n' "$REPORT_PATH"

case "$verify_status" in
  PASS)
    printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_OK task=%s report=%s reason=strong_signal_observed\n' "$TASK_ID" "$REPORT_PATH"
    exit 0
    ;;
  INTERMEDIATE)
    printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_BLOCKED task=%s report=%s reason=stops_at_sent_or_server_ack\n' "$TASK_ID" "$REPORT_PATH"
    exit 2
    ;;
  BLOCKED)
    printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_BLOCKED task=%s report=%s reason=%s\n' "$TASK_ID" "$REPORT_PATH" "$dictamen"
    exit 2
    ;;
  *)
    printf 'VERIFY_WHATSAPP_STATUS_TEMPORAL_EVOLUTION_FAIL task=%s report=%s reason=temporal_probe_incoherent\n' "$TASK_ID" "$REPORT_PATH" >&2
    exit 1
    ;;
esac
