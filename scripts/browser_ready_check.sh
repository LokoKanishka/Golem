#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Uso:
  ./scripts/browser_ready_check.sh <navigation|reading|artifacts> <mode> [--json] [--diagnosis-only]
USAGE
}

capability="${1:-}"
mode="${2:-}"
shift 2 || true

output_json="0"
diagnosis_only="0"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    --diagnosis-only)
      diagnosis_only="1"
      ;;
    *)
      usage
      printf 'ERROR: argumento no soportado: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$capability" ] || [ -z "$mode" ]; then
  usage
  exit 1
fi

load_cached_json() {
  local cache_file="${GOLEM_BROWSER_READYNESS_JSON_FILE:-}"
  if [ -z "$cache_file" ] || [ ! -f "$cache_file" ]; then
    return 1
  fi

  python3 - "$cache_file" "$capability" "$mode" <<'PY'
import json
import pathlib
import sys

cache_path = pathlib.Path(sys.argv[1])
capability = sys.argv[2]
mode = sys.argv[3]
payload = json.loads(cache_path.read_text(encoding="utf-8"))

if payload.get("capability") != capability or payload.get("mode") != mode:
    raise SystemExit(1)

print(json.dumps(payload, ensure_ascii=True))
PY
}

render_text_from_json() {
  python3 - "$1" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])

print("# Browser Readiness Check")
print(f"capability: {payload.get('capability', '')}")
print(f"mode: {payload.get('mode', '')}")
print(f"remediation_mode: {payload.get('remediation_mode', '')}")
print(f"readiness_state: {payload.get('readiness_state', '')}")
chosen_profile = payload.get("chosen_profile") or "none"
print(f"chosen_profile: {chosen_profile}")
print(f"reason: {payload.get('reason', '')}")
print("attempted_recovery: " + ("true" if payload.get("attempted_recovery") else "false"))
print(f"final_decision: {payload.get('final_decision', '')}")
print(f"summary: {payload.get('human_summary', '')}")
print("")
print("## Remediation Steps")
print("remediation_step | attempted | result | note")
for step in payload.get("remediation_steps", []):
    attempted = "true" if step.get("attempted") else "false"
    print(f"{step.get('remediation_step', '')} | {attempted} | {step.get('result', '')} | {step.get('note', '')}")

section_order = [
    ("gateway_status", "Gateway Status"),
    ("browser_profiles", "Browser Profiles"),
    ("chrome_status", "Chrome Status"),
    ("chrome_tabs", "Chrome Tabs"),
    ("openclaw_status", "OpenClaw Status"),
    ("openclaw_tabs", "OpenClaw Tabs"),
    ("openclaw_snapshot", "OpenClaw Snapshot"),
    ("openclaw_start", "OpenClaw Start"),
    ("openclaw_status_after_start", "OpenClaw Status After Start"),
    ("openclaw_tabs_after_start", "OpenClaw Tabs After Start"),
    ("openclaw_snapshot_after_start", "OpenClaw Snapshot After Start"),
]

for key, title in section_order:
    data = payload.get("checks", {}).get(key, {})
    command = data.get("command", "")
    output = data.get("output", "")
    if not command and not output:
        continue
    if not output and data.get("exit_code", 0) == 0:
        continue
    print("")
    print(f"## {title}")
    print(f"$ {command}")
    print(f"exit_code: {data.get('exit_code', 0)}")
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
PY
}

readiness_json=""
if ! readiness_json="$(load_cached_json)"; then
  remediate_args=("$capability" "$mode" "--json")
  if [ "$diagnosis_only" = "1" ]; then
    remediate_args+=("--diagnosis-only")
  fi
  set +e
  readiness_json="$(cd "$REPO_ROOT" && ./scripts/browser_remediate.sh "${remediate_args[@]}")"
  remediation_exit="$?"
  set -e
  if [ "$remediation_exit" -ne 0 ] && [ -z "$readiness_json" ]; then
    printf 'ERROR: browser_remediate no produjo salida reutilizable\n' >&2
    exit "$remediation_exit"
  fi
fi

if [ "$output_json" = "1" ]; then
  printf '%s\n' "$readiness_json"
else
  render_text_from_json "$readiness_json"
fi

final_decision="$(python3 - "$readiness_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get("final_decision", ""))
PY
)"

case "$final_decision" in
  proceed) exit 0 ;;
  block) exit 2 ;;
  *) exit 0 ;;
esac
