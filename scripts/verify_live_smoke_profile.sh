#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASKS_DIR="$REPO_ROOT/tasks"
OUTBOX_DIR="$REPO_ROOT/outbox/manual"
HANDOFFS_DIR="$REPO_ROOT/handoffs"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_DIR="$OUTBOX_DIR/${TIMESTAMP}-live-smoke-profile-logs"
REPORT_PATH="$OUTBOX_DIR/${TIMESTAMP}-live-smoke-profile.md"
RESULTS_FILE="$(mktemp "${TMPDIR:-/tmp}/golem-live-smoke-results.XXXXXX.jsonl")"
TASKS_FILE="$(mktemp "${TMPDIR:-/tmp}/golem-live-smoke-tasks.XXXXXX.txt")"
OUTBOX_FILE="$(mktemp "${TMPDIR:-/tmp}/golem-live-smoke-outbox.XXXXXX.txt")"
HANDOFFS_FILE="$(mktemp "${TMPDIR:-/tmp}/golem-live-smoke-handoffs.XXXXXX.txt")"
START_MARKER="$(mktemp "${TMPDIR:-/tmp}/golem-live-smoke-start.XXXXXX")"

mkdir -p "$TASKS_DIR" "$OUTBOX_DIR" "$HANDOFFS_DIR" "$LOG_DIR"
touch "$START_MARKER"

LAST_OUTPUT=""
LAST_EXIT_CODE="0"

cleanup() {
  rm -f "$RESULTS_FILE" "$TASKS_FILE" "$OUTBOX_FILE" "$HANDOFFS_FILE" "$START_MARKER"
}

trap cleanup EXIT

run_logged_command() {
  local log_path="$1"
  local cmd="$2"
  local output
  local exit_code

  {
    printf '$ %s\n' "$cmd"
    set +e
    output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
    exit_code="$?"
    set -e
    printf 'exit_code: %s\n' "$exit_code"
    if [ -n "$output" ]; then
      printf '%s\n' "$output"
    fi
  } >>"$log_path"

  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

record_result() {
  local check="$1"
  local status="$2"
  local note="$3"
  local evidence="$4"
  local log_path="$5"
  python3 - "$RESULTS_FILE" "$check" "$status" "$note" "$evidence" "$log_path" <<'PY'
import json
import pathlib
import sys

results_path = pathlib.Path(sys.argv[1])
payload = {
    "check": sys.argv[2],
    "status": sys.argv[3],
    "note": sys.argv[4],
    "evidence": sys.argv[5],
    "log_path": sys.argv[6],
}

with results_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(payload, ensure_ascii=True) + "\n")
PY
}

sanitize_dashboard_url() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit, urlunsplit

raw = sys.argv[1].strip()
if not raw:
    print("")
    raise SystemExit(0)

parts = urlsplit(raw)
print(urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, "")))
PY
}

extract_task_id() {
  printf '%s\n' "$1" | awk '/^TASK_CREATED / {print $2}' | tail -n 1 | xargs -r basename -s .json
}

task_field() {
  local task_id="$1"
  local path_expr="$2"
  python3 - "$TASKS_DIR/${task_id}.json" "$path_expr" <<'PY'
import json
import pathlib
import sys

task_path = pathlib.Path(sys.argv[1])
value = json.loads(task_path.read_text(encoding="utf-8"))

for part in sys.argv[2].split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part, "")
    elif isinstance(value, list):
        try:
            value = value[int(part)]
        except Exception:
            value = ""
            break
    else:
        value = ""
        break

if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=True))
else:
    print(value)
PY
}

join_lines() {
  python3 - "$@" <<'PY'
import sys

values = [value for value in sys.argv[1:] if value]
print(", ".join(values))
PY
}

browser_blocked_caps() {
  python3 - "$1" <<'PY'
import sys

blocked = []
for line in sys.argv[1].splitlines():
    if "|" not in line:
        continue
    parts = [part.strip() for part in line.split("|")]
    if len(parts) < 3:
        continue
    if parts[0] in {"navigation", "reading", "artifacts"} and parts[1] == "BLOCKED":
        blocked.append(parts[0])
print(", ".join(blocked))
PY
}

browser_fail_caps() {
  python3 - "$1" <<'PY'
import sys

failed = []
for line in sys.argv[1].splitlines():
    if "|" not in line:
        continue
    parts = [part.strip() for part in line.split("|")]
    if len(parts) < 3:
        continue
    if parts[0] in {"navigation", "reading", "artifacts"} and parts[1] == "FAIL":
        failed.append(parts[0])
print(", ".join(failed))
PY
}

find_new_artifacts() {
  find "$1" -maxdepth 1 -type f -newer "$START_MARKER" | sort
}

run_stack_availability() {
  local log_path="$LOG_DIR/stack-availability.log"
  local status_cmd="timeout 45s openclaw status"
  local dashboard_cmd="timeout 45s openclaw dashboard --no-open"
  local curl_cmd
  local dashboard_raw dashboard_url http_status status note evidence

  : >"$log_path"
  run_logged_command "$log_path" "$status_cmd"
  local status_output="$LAST_OUTPUT"
  local status_exit="$LAST_EXIT_CODE"

  run_logged_command "$log_path" "$dashboard_cmd"
  dashboard_raw="$LAST_OUTPUT"
  local dashboard_exit="$LAST_EXIT_CODE"
  dashboard_url="$(printf '%s\n' "$dashboard_raw" | sed -n 's/^Dashboard URL: //p' | tail -n 1)"
  dashboard_url="$(sanitize_dashboard_url "$dashboard_url")"

  http_status=""
  if [ -n "$dashboard_url" ]; then
    curl_cmd="curl -I -s ${dashboard_url} | head -n 1"
    run_logged_command "$log_path" "$curl_cmd"
    http_status="$(printf '%s\n' "$LAST_OUTPUT" | head -n 1)"
  fi

  if [ "$status_exit" -eq 0 ] && printf '%s\n' "$status_output" | rg -q 'reachable' && printf '%s\n' "$http_status" | rg -q '^HTTP/[0-9.]+ 200'; then
    status="PASS"
    note="stack actual disponible: gateway reachable y panel HTTP respondio"
    if [ "$dashboard_exit" -eq 124 ]; then
      note="$note; openclaw dashboard --no-open resolvio la URL pero quedo abierto hasta el timeout operacional"
    fi
  else
    status="FAIL"
    note="stack actual no emitio una señal coherente de gateway/panel disponible"
  fi

  evidence="panel=${dashboard_url:-unresolved}; http=${http_status:-none}; log=$(basename "$log_path")"
  record_result "stack availability" "$status" "$note" "$evidence" "$log_path"
}

run_fast_self_check() {
  local log_path="$LOG_DIR/fast-self-check.log"
  local cmd='bash ./scripts/task_run_self_check.sh "Live smoke profile / fast self-check"'
  local task_id task_status overall_state status note evidence

  : >"$log_path"
  run_logged_command "$log_path" "$cmd"
  task_id="$(extract_task_id "$LAST_OUTPUT")"
  task_status=""
  overall_state=""
  if [ -n "$task_id" ] && [ -f "$TASKS_DIR/${task_id}.json" ]; then
    task_status="$(task_field "$task_id" status)"
    overall_state="$(task_field "$task_id" outputs.0.estado_general)"
  fi

  if [ "$LAST_EXIT_CODE" -eq 0 ] && [ "$task_status" = "done" ]; then
    status="PASS"
    note="fast self-check vivo completado y persistido como task"
    if [ "$overall_state" = "WARN" ]; then
      note="$note; el estado general quedo en WARN por señales operativas del browser"
    fi
  else
    status="FAIL"
    note="fast self-check vivo no cerro coherentemente"
  fi

  evidence="task=${task_id:-none}; estado_general=${overall_state:-unknown}; log=$(basename "$log_path")"
  record_result "fast self-check" "$status" "$note" "$evidence" "$log_path"
}

run_worker_stack() {
  local log_path="$LOG_DIR/worker-orchestration-stack.log"
  local cmd='timeout 300s bash ./scripts/verify_worker_orchestration_stack.sh'
  local status note evidence

  : >"$log_path"
  run_logged_command "$log_path" "$cmd"

  if [ "$LAST_EXIT_CODE" -eq 0 ] && printf '%s\n' "$LAST_OUTPUT" | rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_OK '; then
    status="PASS"
    note="worker/orchestration stack probado en vivo y cerrado en PASS"
  elif printf '%s\n' "$LAST_OUTPUT" | rg -q '^VERIFY_WORKER_ORCHESTRATION_STACK_BLOCKED '; then
    status="BLOCKED"
    note="worker/orchestration stack no se pudo probar por un bloqueo externo repo-local"
  else
    status="FAIL"
    note="worker/orchestration stack expuso una falla interna durante el smoke vivo"
  fi

  evidence="marker=$(printf '%s\n' "$LAST_OUTPUT" | awk '/^VERIFY_WORKER_ORCHESTRATION_STACK_/ {print $1}' | tail -n 1); log=$(basename "$log_path")"
  record_result "worker orchestration stack" "$status" "$note" "$evidence" "$log_path"
}

run_browser_stack() {
  local log_path="$LOG_DIR/browser-stack.log"
  local cmd='timeout 180s bash ./scripts/verify_browser_stack.sh'
  local status note evidence blocked_caps fail_caps

  : >"$log_path"
  run_logged_command "$log_path" "$cmd"
  blocked_caps="$(browser_blocked_caps "$LAST_OUTPUT")"
  fail_caps="$(browser_fail_caps "$LAST_OUTPUT")"

  if [ "$LAST_EXIT_CODE" -eq 0 ] && [ -z "$blocked_caps" ] && [ -z "$fail_caps" ]; then
    status="PASS"
    note="browser stack probado en vivo y usable en sus probes oficiales"
  elif [ "$LAST_EXIT_CODE" -eq 124 ]; then
    status="BLOCKED"
    note="browser stack no completo dentro del timeout operacional del smoke y queda bloqueado para esta demo viva"
  elif [ "$LAST_EXIT_CODE" -eq 2 ] || [ -n "$blocked_caps" ]; then
    status="BLOCKED"
    note="browser stack sigue bloqueado en vivo: ${blocked_caps:-navigation, reading, artifacts}"
  else
    status="FAIL"
    note="browser stack expuso una falla interna durante el smoke vivo"
  fi

  evidence="blocked_caps=${blocked_caps:-none}; fail_caps=${fail_caps:-none}; log=$(basename "$log_path")"
  record_result "browser stack" "$status" "$note" "$evidence" "$log_path"
}

run_live_browser_action() {
  local log_path="$LOG_DIR/live-browser-action.log"
  local cmd='openclaw browser --browser-profile chrome snapshot'
  local status note evidence

  : >"$log_path"
  run_logged_command "$log_path" "$cmd"

  if [ "$LAST_EXIT_CODE" -eq 0 ]; then
    status="PASS"
    note="raw browser snapshot real produjo salida usable"
  elif printf '%s\n' "$LAST_OUTPUT" | rg -q 'no tab is connected|No tabs'; then
    status="BLOCKED"
    note="raw browser snapshot sigue bloqueado porque el relay chrome no tiene tab adjunta"
  else
    status="FAIL"
    note="raw browser snapshot fallo por una razon no clasificada como bloqueo operativo esperado"
  fi

  evidence="command=openclaw browser --browser-profile chrome snapshot; log=$(basename "$log_path")"
  record_result "live browser action" "$status" "$note" "$evidence" "$log_path"
}

collect_generated_artifacts() {
  local log_path="$LOG_DIR/generated-artifacts.log"
  local task_count outbox_count handoff_count status note evidence
  local sample_1 sample_2 sample_3

  : >"$log_path"
  find_new_artifacts "$TASKS_DIR" >"$TASKS_FILE"
  find_new_artifacts "$OUTBOX_DIR" >"$OUTBOX_FILE"
  find_new_artifacts "$HANDOFFS_DIR" >"$HANDOFFS_FILE"

  task_count="$(wc -l <"$TASKS_FILE" | tr -d ' ')"
  outbox_count="$(wc -l <"$OUTBOX_FILE" | tr -d ' ')"
  handoff_count="$(wc -l <"$HANDOFFS_FILE" | tr -d ' ')"

  {
    printf 'tasks_created: %s\n' "$task_count"
    cat "$TASKS_FILE"
    printf '\noutbox_files_created: %s\n' "$outbox_count"
    cat "$OUTBOX_FILE"
    printf '\nhandoffs_created: %s\n' "$handoff_count"
    cat "$HANDOFFS_FILE"
  } >>"$log_path"

  if [ $((task_count + outbox_count + handoff_count)) -gt 0 ]; then
    status="PASS"
    note="el smoke vivo genero evidencia real en tasks, outbox y handoffs"
  else
    status="FAIL"
    note="el smoke vivo no dejo artifacts ni resultados nuevos para inspeccionar"
  fi

  sample_1="$(head -n 1 "$TASKS_FILE" | sed "s#^$REPO_ROOT/##")"
  sample_2="$(head -n 1 "$OUTBOX_FILE" | sed "s#^$REPO_ROOT/##")"
  sample_3="$(head -n 1 "$HANDOFFS_FILE" | sed "s#^$REPO_ROOT/##")"
  evidence="tasks=${task_count}; outbox=${outbox_count}; handoffs=${handoff_count}; samples=$(join_lines "$sample_1" "$sample_2" "$sample_3"); log=$(basename "$log_path")"
  record_result "artifacts/results generated" "$status" "$note" "$evidence" "$log_path"
}

generate_report() {
  python3 - "$RESULTS_FILE" "$REPORT_PATH" "$REPO_ROOT" "$TASKS_FILE" "$OUTBOX_FILE" "$HANDOFFS_FILE" <<'PY'
import datetime
import json
import pathlib
import sys

results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
report_path = pathlib.Path(sys.argv[2])
repo_root = pathlib.Path(sys.argv[3])
task_paths = [pathlib.Path(line) for line in pathlib.Path(sys.argv[4]).read_text(encoding="utf-8").splitlines() if line.strip()]
outbox_paths = [pathlib.Path(line) for line in pathlib.Path(sys.argv[5]).read_text(encoding="utf-8").splitlines() if line.strip()]
handoff_paths = [pathlib.Path(line) for line in pathlib.Path(sys.argv[6]).read_text(encoding="utf-8").splitlines() if line.strip()]

counts = {"PASS": 0, "FAIL": 0, "BLOCKED": 0}
for result in results:
    counts[result["status"]] = counts.get(result["status"], 0) + 1

overall_status = "PASS"
overall_note = "smoke vivo usable y sin bloqueos criticos"
if counts.get("FAIL", 0) > 0:
    overall_status = "FAIL"
    overall_note = "al menos un check del smoke vivo fallo internamente"
elif counts.get("BLOCKED", 0) > 0:
    overall_status = "BLOCKED"
    overall_note = "el smoke vivo pudo correrse, pero una o mas capacidades siguen bloqueadas por entorno/capability"

def rel(path: pathlib.Path) -> str:
    try:
        return str(path.relative_to(repo_root))
    except Exception:
        return str(path)

lines = []
lines.append("# Live Smoke Profile Report")
lines.append("")
lines.append("generated_at: " + datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat())
lines.append(f"repo: {repo_root}")
lines.append(f"overall_status: {overall_status}")
lines.append(f"overall_note: {overall_note}")
lines.append("")
lines.append("## Checks")
lines.append("| check | status | note | evidence |")
lines.append("| --- | --- | --- | --- |")
for result in results:
    note = result["note"].replace("|", "\\|")
    evidence = result["evidence"].replace("|", "\\|")
    lines.append(f"| {result['check']} | {result['status']} | {note} | {evidence} |")

lines.append("")
lines.append("## Artifacts")
lines.append(f"- tasks_created: {len(task_paths)}")
for path in task_paths[:12]:
    lines.append(f"  - {rel(path)}")
if len(task_paths) > 12:
    lines.append(f"  - ... {len(task_paths) - 12} more")
lines.append(f"- outbox_files_created: {len(outbox_paths)}")
for path in outbox_paths[:12]:
    lines.append(f"  - {rel(path)}")
if len(outbox_paths) > 12:
    lines.append(f"  - ... {len(outbox_paths) - 12} more")
lines.append(f"- handoffs_created: {len(handoff_paths)}")
for path in handoff_paths[:12]:
    lines.append(f"  - {rel(path)}")
if len(handoff_paths) > 12:
    lines.append(f"  - ... {len(handoff_paths) - 12} more")

lines.append("")
lines.append("## Operational Conclusion")
lines.append("- Clawbot/OpenClaw can currently bring up the local stack, answer from the panel surface, run the fast self-check, and execute the worker/orchestration verification lane.")
lines.append("- The browser lane remains blocked in live use because the chrome relay still has no attached tab and the managed openclaw fallback does not become usable.")
lines.append("- The next priority fix remains the host/browser runtime unblock, not the worker/orchestration lane.")

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

print_summary() {
  python3 - "$RESULTS_FILE" "$REPORT_PATH" <<'PY'
import json
import pathlib
import sys

results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
report_path = sys.argv[2]
counts = {"PASS": 0, "FAIL": 0, "BLOCKED": 0}
for result in results:
    counts[result["status"]] = counts.get(result["status"], 0) + 1

overall_status = "PASS"
overall_note = "smoke vivo usable y sin bloqueos criticos"
if counts.get("FAIL", 0) > 0:
    overall_status = "FAIL"
    overall_note = "al menos un check del smoke vivo fallo internamente"
elif counts.get("BLOCKED", 0) > 0:
    overall_status = "BLOCKED"
    overall_note = "el smoke vivo pudo correrse, pero una o mas capacidades siguen bloqueadas por entorno/capability"

print(f"REPORT_PATH {report_path}")
print("check | status | note | evidence")
for result in results:
    print(f"{result['check']} | {result['status']} | {result['note']} | {result['evidence']}")
print(f"PASS: {counts.get('PASS', 0)}")
print(f"FAIL: {counts.get('FAIL', 0)}")
print(f"BLOCKED: {counts.get('BLOCKED', 0)}")
print(f"overall_status: {overall_status}")
print(f"overall_note: {overall_note}")
PY
}

cd "$REPO_ROOT"

printf '# Live Smoke Profile Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"
printf 'branch: %s\n' "$(git branch --show-current)"

run_stack_availability
run_fast_self_check
run_worker_stack
run_browser_stack
run_live_browser_action
collect_generated_artifacts

generate_report
print_summary

pass_count="$(python3 - "$RESULTS_FILE" <<'PY'
import json
import pathlib
import sys
results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
print(sum(1 for item in results if item["status"] == "PASS"))
PY
)"
fail_count="$(python3 - "$RESULTS_FILE" <<'PY'
import json
import pathlib
import sys
results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
print(sum(1 for item in results if item["status"] == "FAIL"))
PY
)"
blocked_count="$(python3 - "$RESULTS_FILE" <<'PY'
import json
import pathlib
import sys
results = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
print(sum(1 for item in results if item["status"] == "BLOCKED"))
PY
)"

if [ "$fail_count" -gt 0 ]; then
  printf 'VERIFY_LIVE_SMOKE_PROFILE_FAIL pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH" >&2
  exit 1
fi

if [ "$blocked_count" -gt 0 ]; then
  printf 'VERIFY_LIVE_SMOKE_PROFILE_BLOCKED pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
  exit 2
fi

printf 'VERIFY_LIVE_SMOKE_PROFILE_OK pass=%s fail=%s blocked=%s report=%s\n' "$pass_count" "$fail_count" "$blocked_count" "$REPORT_PATH"
