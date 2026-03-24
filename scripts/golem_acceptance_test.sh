#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACCEPTANCE_ROOT="${GOLEM_ACCEPTANCE_ROOT:-${REPO_ROOT}/diagnostics/acceptance}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${ACCEPTANCE_ROOT}/${RUN_ID}-golem-acceptance"
LOG_DIR="${RUN_DIR}/logs"
RESULTS_TSV="${RUN_DIR}/checks.tsv"
SUMMARY_TXT="${RUN_DIR}/summary.txt"
MANIFEST_JSON="${RUN_DIR}/manifest.json"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$LOG_DIR"

cat >"$RESULTS_TSV" <<'EOF'
block_id	block_label	check_id	severity	status	exit_code	label	log_path	started_at	ended_at	command
EOF

run_check() {
  local block_id="$1"
  local block_label="$2"
  local check_id="$3"
  local severity="$4"
  local label="$5"
  local command="$6"
  local started_at ended_at exit_code status log_path

  log_path="${LOG_DIR}/${check_id}.log"
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  printf '== %s / %s ==\n' "$block_label" "$label"

  set +e
  {
    printf 'label: %s\n' "$label"
    printf 'severity: %s\n' "$severity"
    printf 'command: %s\n' "$command"
    printf 'started_at: %s\n' "$started_at"
    printf '\n'
    bash -lc "cd \"$REPO_ROOT\" && $command"
  } >"$log_path" 2>&1
  exit_code=$?
  set -e

  ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$exit_code" -eq 0 ]; then
    status="PASS"
  elif [ "$severity" = "warn" ]; then
    status="WARN"
  else
    status="FAIL"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$block_id" \
    "$block_label" \
    "$check_id" \
    "$severity" \
    "$status" \
    "$exit_code" \
    "$label" \
    "$log_path" \
    "$started_at" \
    "$ended_at" \
    "$command" >>"$RESULTS_TSV"

  printf '[%s] %s\n' "$status" "$label"
}

finalize_acceptance() {
  local ended_at
  ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  python3 - "$RESULTS_TSV" "$SUMMARY_TXT" "$MANIFEST_JSON" "$RUN_DIR" "$REPO_ROOT" "$RUN_ID" "$STARTED_AT" "$ended_at" <<'PY'
import csv
import json
import pathlib
import sys

results_path = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
run_dir = pathlib.Path(sys.argv[4])
repo_root = pathlib.Path(sys.argv[5])
run_id = sys.argv[6]
started_at = sys.argv[7]
ended_at = sys.argv[8]

with results_path.open(encoding="utf-8") as handle:
    reader = csv.DictReader(handle, delimiter="\t")
    checks = list(reader)

block_order = []
blocks: dict[str, dict] = {}
fail_count = 0
warn_count = 0

for check in checks:
    block_id = check["block_id"]
    block_label = check["block_label"]
    if block_id not in blocks:
        block_order.append(block_id)
        blocks[block_id] = {
            "id": block_id,
            "label": block_label,
            "status": "PASS",
            "checks": [],
        }
    blocks[block_id]["checks"].append(check)
    if check["status"] == "FAIL":
        fail_count += 1
        blocks[block_id]["status"] = "FAIL"
    elif check["status"] == "WARN":
        warn_count += 1
        if blocks[block_id]["status"] != "FAIL":
            blocks[block_id]["status"] = "WARN"

if fail_count:
    verdict = "FAIL"
elif warn_count:
    verdict = "PASS WITH WARNINGS"
else:
    verdict = "PASS"

summary_lines = [
    "GOLEM ACCEPTANCE TEST",
    "",
    f"run_id: {run_id}",
    f"repo_root: {repo_root}",
    f"started_at_utc: {started_at}",
    f"ended_at_utc: {ended_at}",
    f"artifacts_dir: {run_dir}",
    f"global_verdict: {verdict}",
    "",
    "BLOCKS:",
]

for block_id in block_order:
    block = blocks[block_id]
    summary_lines.append(f"- {block['label']}: {block['status']}")
    for check in block["checks"]:
        summary_lines.append(
            f"  - [{check['status']}] {check['label']} (exit={check['exit_code']})"
        )

summary_lines.extend(
    [
        "",
        "ARTIFACTS:",
        f"- manifest: {manifest_path}",
        f"- checks: {results_path}",
        f"- logs: {run_dir / 'logs'}",
    ]
)

summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

manifest = {
    "run_id": run_id,
    "repo_root": str(repo_root),
    "started_at_utc": started_at,
    "ended_at_utc": ended_at,
    "artifacts_dir": str(run_dir),
    "global_verdict": verdict,
    "counts": {
        "checks_total": len(checks),
        "checks_fail": fail_count,
        "checks_warn": warn_count,
        "checks_pass": len(checks) - fail_count - warn_count,
    },
    "blocks": [
        {
            "id": blocks[block_id]["id"],
            "label": blocks[block_id]["label"],
            "status": blocks[block_id]["status"],
            "checks": blocks[block_id]["checks"],
        }
        for block_id in block_order
    ],
}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
print(verdict)
PY
}

run_check \
  "repo_integrity" \
  "A. Repo e integridad" \
  "repo_git_clean" \
  "required" \
  "Git worktree limpio" \
  'if [ -z "$(git status --short)" ]; then echo GIT_WORKTREE_CLEAN_OK; else git status --short; exit 1; fi'

run_check \
  "repo_integrity" \
  "A. Repo e integridad" \
  "repo_fsck" \
  "required" \
  "Git fsck completo" \
  'git fsck --full'

run_check \
  "repo_integrity" \
  "A. Repo e integridad" \
  "repo_remote" \
  "required" \
  "Remote origin presente" \
  'git remote -v && git remote get-url origin >/dev/null'

run_check \
  "official_gate" \
  "B. Gate oficial" \
  "verify_task_lane_enforcement" \
  "required" \
  "Task lane enforcement" \
  './scripts/verify_task_lane_enforcement.sh'

run_check \
  "official_gate" \
  "B. Gate oficial" \
  "task_validate_strict" \
  "required" \
  "Inventario canonico estricto" \
  './scripts/task_validate.sh --all --strict'

run_check \
  "task_api_panel" \
  "C. Task API / Panel" \
  "smoke_task_panel_http_service" \
  "required" \
  "Task API HTTP service" \
  './tests/smoke_task_panel_http_service.sh'

run_check \
  "task_api_panel" \
  "C. Task API / Panel" \
  "smoke_panel_task_http" \
  "required" \
  "Panel HTTP surface" \
  './tests/smoke_panel_task_http.sh'

run_check \
  "task_api_panel" \
  "C. Task API / Panel" \
  "smoke_panel_visible_ui" \
  "warn" \
  "Panel visible surface" \
  './tests/smoke_panel_visible_ui.sh'

run_check \
  "local_services" \
  "D. Servicios locales" \
  "smoke_whatsapp_bridge_service" \
  "required" \
  "WhatsApp bridge como servicio" \
  './tests/smoke_whatsapp_bridge_service.sh'

run_check \
  "local_services" \
  "D. Servicios locales" \
  "smoke_task_panel_bridge_service_stack" \
  "required" \
  "Convivencia API + bridge serviceificados" \
  './tests/smoke_task_panel_bridge_service_stack.sh'

run_check \
  "whatsapp" \
  "E. WhatsApp" \
  "smoke_whatsapp_task_query" \
  "required" \
  "WhatsApp query path" \
  './tests/smoke_whatsapp_task_query.sh'

run_check \
  "whatsapp" \
  "E. WhatsApp" \
  "smoke_whatsapp_task_mutate" \
  "required" \
  "WhatsApp mutate path" \
  './tests/smoke_whatsapp_task_mutate.sh'

run_check \
  "whatsapp" \
  "E. WhatsApp" \
  "smoke_whatsapp_bridge_runtime" \
  "required" \
  "WhatsApp runtime bridge" \
  './tests/smoke_whatsapp_bridge_runtime.sh'

run_check \
  "host_daily" \
  "F. Host diario" \
  "smoke_host_daily_stack" \
  "required" \
  "Launcher, self_check y stack diario" \
  './tests/smoke_host_daily_stack.sh'

run_check \
  "diagnostics" \
  "G. Diagnostico y falla controlada" \
  "smoke_host_auto_diagnose_failure" \
  "required" \
  "Auto diagnose ante falla controlada" \
  './tests/smoke_host_auto_diagnose_failure.sh'

run_check \
  "diagnostics" \
  "G. Diagnostico y falla controlada" \
  "smoke_host_failure_operator_summary" \
  "required" \
  "Quick triage y resumen corto" \
  './tests/smoke_host_failure_operator_summary.sh'

run_check \
  "diagnostics" \
  "G. Diagnostico y falla controlada" \
  "smoke_host_last_snapshot_context_layout" \
  "required" \
  "Helper del ultimo snapshot" \
  './tests/smoke_host_last_snapshot_context_layout.sh'

VERDICT="$(finalize_acceptance)"

printf '\nGOLEM ACCEPTANCE RESULT\n'
printf 'run_dir: %s\n' "$RUN_DIR"
printf 'summary: %s\n' "$SUMMARY_TXT"
printf 'manifest: %s\n' "$MANIFEST_JSON"
printf 'global_verdict: %s\n' "$VERDICT"
