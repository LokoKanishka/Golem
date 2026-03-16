#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

LAST_OUTPUT=""
LAST_EXIT_CODE="0"

run_cmd() {
  local label="$1"
  local cmd="$2"
  local key="$3"
  local output_file="$tmp_dir/${key}.out"
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
  printf '%s\n' "$output" >"$output_file"
  LAST_OUTPUT="$output"
  LAST_EXIT_CODE="$exit_code"
}

render_contract_table() {
  python3 - "$@" <<'PY'
import json
import pathlib
import sys

(
    remediation_path,
    remediation_exit,
    chrome_snapshot_path,
    chrome_snapshot_exit,
    browser_cli_help_path,
    wrapper_surface_path,
    attach_search_path,
    manual_host_path,
) = sys.argv[1:9]

remediation_text = pathlib.Path(remediation_path).read_text(encoding="utf-8", errors="replace")
chrome_snapshot_text = pathlib.Path(chrome_snapshot_path).read_text(encoding="utf-8", errors="replace")
browser_cli_help_text = pathlib.Path(browser_cli_help_path).read_text(encoding="utf-8", errors="replace")
wrapper_surface_text = pathlib.Path(wrapper_surface_path).read_text(encoding="utf-8", errors="replace")
attach_search_text = pathlib.Path(attach_search_path).read_text(encoding="utf-8", errors="replace")
manual_host_text = pathlib.Path(manual_host_path).read_text(encoding="utf-8", errors="replace")

try:
    remediation = json.loads(remediation_text)
except Exception as exc:
    print("contract/check | status | note")
    print(f"repo browser contract | FAIL | remediation evidence was not parseable: {exc}")
    print("overall_conclusion: unable to formalize the host/browser contract because repo-local evidence generation failed")
    print("next_step_location: repo")
    print("VERIFY_BROWSER_HOST_CONTRACT_FAIL parse_error=browser_remediation_json")
    raise SystemExit(1)

steps = {step.get("remediation_step", ""): step for step in remediation.get("remediation_steps", [])}
checks = remediation.get("checks", {})

def step_result(name):
    return steps.get(name, {}).get("result", "")

def step_note(name):
    return steps.get(name, {}).get("note", "")

def check_output(name):
    return checks.get(name, {}).get("output", "")

def check_exit(name):
    return checks.get(name, {}).get("exit_code", 1)

rows = []

repo_contract_status = "PASS"
repo_contract_note = "repo emitted coherent remediation evidence and kept the blocker classified without collapsing it into a generic failure"
required_step_names = {
    "detect_chrome_usable_tab",
    "attempt_chrome_attach_refresh",
    "probe_openclaw_snapshot",
    "attempt_openclaw_start",
}
missing_steps = sorted(required_step_names.difference(steps.keys()))
if int(remediation_exit) not in (0, 2):
    repo_contract_status = "FAIL"
    repo_contract_note = f"browser_remediate exited unexpectedly with code {remediation_exit}"
elif missing_steps:
    repo_contract_status = "FAIL"
    repo_contract_note = "browser_remediate omitted expected contract evidence: " + ", ".join(missing_steps)

chrome_tab_result = step_result("detect_chrome_usable_tab")
chrome_tabs_output = check_output("chrome_tabs")
if chrome_tab_result == "ok":
    chrome_relay_status = "PASS"
    chrome_relay_note = "chrome relay contract is satisfied with at least one usable attached tab"
elif "No tabs" in chrome_tabs_output or "no targets" in chrome_tabs_output or chrome_tab_result == "blocked":
    chrome_relay_status = "BLOCKED"
    chrome_relay_note = "chrome relay commands exist, but the host exposes no usable attached tab through the relay"
else:
    chrome_relay_status = "FAIL"
    chrome_relay_note = "chrome relay probe did not produce a coherent tab-availability reading"
rows.append(("chrome relay contract", chrome_relay_status, chrome_relay_note))

openclaw_tabs_output = check_output("openclaw_tabs")
openclaw_tabs_after_start_output = check_output("openclaw_tabs_after_start")
if chrome_tab_result == "ok":
    tab_availability_status = "PASS"
    tab_availability_note = "tab availability contract is satisfied by the chrome relay"
elif "No tabs" in chrome_tabs_output and "No tabs" in openclaw_tabs_output and not openclaw_tabs_after_start_output.strip():
    tab_availability_status = "BLOCKED"
    tab_availability_note = "the host currently exposes no usable tab through either chrome relay or managed openclaw"
elif step_result("probe_openclaw_tabs_after_start") == "ok":
    tab_availability_status = "PASS"
    tab_availability_note = "managed openclaw recovered a usable tab after the controlled start attempt"
else:
    tab_availability_status = "BLOCKED"
    tab_availability_note = "tab availability remains externally blocked after probing both relay lanes"
rows.append(("tab availability contract", tab_availability_status, tab_availability_note))

attach_step = steps.get("attempt_chrome_attach_refresh", {})
repo_invokes_attach = bool(attach_search_text.strip())
cli_lists_attach = "\n  attach" in browser_cli_help_text or "\n  reattach" in browser_cli_help_text
manual_only_hint = "badge ON" in manual_host_text or "reattach manual" in manual_host_text or "adjuntar una pestaña" in manual_host_text
if (
    attach_step.get("result") == "skipped"
    and "no non-destructive CLI attach path" in attach_step.get("note", "")
    and not repo_invokes_attach
    and not cli_lists_attach
):
    attach_status = "MISSING_CAPABILITY"
    attach_note = "repo exposes tabs/open/snapshot/find surfaces, but neither the repo nor the current browser CLI expose a non-destructive attach path for the chrome relay; operator/manual host action is still required"
elif repo_invokes_attach or cli_lists_attach:
    attach_status = "PASS"
    attach_note = "a real attach or reattach path appears to exist in the repo or browser CLI surface and should be integrated into the remediation ladder"
elif manual_only_hint:
    attach_status = "MISSING_CAPABILITY"
    attach_note = "repo docs describe manual relay attachment, but the repo surface still lacks a non-destructive CLI attach path"
else:
    attach_status = "FAIL"
    attach_note = "attach capability could not be classified cleanly from repo-local evidence"
rows.append(("chrome relay attach path", attach_status, attach_note))

openclaw_start_result = step_result("attempt_openclaw_start")
openclaw_start_output = check_output("openclaw_start")
if openclaw_start_result == "ok":
    openclaw_contract_status = "PASS"
    openclaw_contract_note = "managed openclaw start contract is currently usable from the repo surface"
elif "gateway timeout" in openclaw_start_output or openclaw_start_result == "blocked":
    openclaw_contract_status = "BLOCKED"
    openclaw_contract_note = "managed openclaw start path exists, but the host/runtime blocks it in the current environment"
else:
    openclaw_contract_status = "FAIL"
    openclaw_contract_note = "managed openclaw start contract failed in a way not classified as an external host/runtime block"
rows.append(("managed openclaw contract", openclaw_contract_status, openclaw_contract_note))

chrome_snapshot_blocked = "no tab is connected" in chrome_snapshot_text or "No tabs" in chrome_snapshot_text or "browser closed or no targets" in chrome_snapshot_text
openclaw_snapshot_result = step_result("probe_openclaw_snapshot")
retry_snapshot_result = step_result("retry_openclaw_snapshot_after_start")
if check_exit("chrome_tabs") == 0 and chrome_tab_result == "ok" and int(chrome_snapshot_exit) == 0:
    snapshot_status = "PASS"
    snapshot_note = "raw chrome snapshot contract is satisfied"
elif chrome_snapshot_blocked and openclaw_snapshot_result in {"not_usable", ""} and retry_snapshot_result in {"blocked", "skipped", ""}:
    snapshot_status = "BLOCKED"
    snapshot_note = "snapshot contract remains blocked: chrome lacks an attached tab and the managed openclaw fallback never becomes usable"
else:
    snapshot_status = "FAIL"
    snapshot_note = "snapshot contract failed without a clean host/runtime blocker classification"
rows.append(("snapshot contract", snapshot_status, snapshot_note))

rows.append(("repo browser contract", repo_contract_status, repo_contract_note))

print("contract/check | status | note")
for name, status, note in rows:
    print(f"{name} | {status} | {note}")

dominant_blocker = "host_runtime_failure"
if attach_status == "MISSING_CAPABILITY" and openclaw_contract_status == "BLOCKED":
    dominant_blocker = "host_contract_gap_plus_host_runtime_failure"
elif attach_status == "MISSING_CAPABILITY":
    dominant_blocker = "host_contract_gap"
elif openclaw_contract_status == "BLOCKED":
    dominant_blocker = "host_runtime_failure"

next_step_location = "outside_repo_now"
if repo_contract_status == "FAIL":
    next_step_location = "repo"

print(f"overall_conclusion: browser stack remains BLOCKED because the chrome relay lacks a repo-local non-destructive attach path and the managed openclaw start/snapshot path stays blocked by the current host runtime")
print(f"dominant_blocker: {dominant_blocker}")
print(f"next_step_location: {next_step_location}")
print("unblock_condition_1: attach a usable tab to the chrome relay from the host/operator side")
print("unblock_condition_2: make managed openclaw start plus snapshot usable in the current host runtime")
print("repo_follow_up_rule: only add repo-side attach remediation if OpenClaw later exposes a safe non-destructive CLI attach or refresh path")
print(f"VERIFY_BROWSER_HOST_CONTRACT_OK dominant_blocker={dominant_blocker} next_step_location={next_step_location}")
PY
}

printf '# Browser Host Contract Verification\n'
printf 'generated_at: %s\n' "$(date -u --iso-8601=seconds)"
printf 'repo: %s\n' "$REPO_ROOT"

run_cmd \
  "Browser Remediation Source" \
  "./scripts/browser_remediate.sh reading snapshot --json" \
  "browser-remediation-json"
remediation_exit="$LAST_EXIT_CODE"
remediation_json_file="$tmp_dir/browser-remediation-json.out"

run_cmd \
  "Chrome Snapshot Raw" \
  "openclaw browser --browser-profile chrome snapshot" \
  "chrome-snapshot-raw"
chrome_snapshot_exit="$LAST_EXIT_CODE"
chrome_snapshot_file="$tmp_dir/chrome-snapshot-raw.out"

run_cmd \
  "Browser CLI Surface" \
  "openclaw browser --help" \
  "browser-cli-help"
browser_cli_help_file="$tmp_dir/browser-cli-help.out"

run_cmd \
  "Repo Browser Wrapper Surface" \
  "rg -n 'tabs\\)|open\\)|snapshot\\)|find\\)' scripts/browser_nav.sh scripts/browser_read.sh scripts/browser_artifact.sh" \
  "repo-wrapper-surface"
wrapper_surface_file="$tmp_dir/repo-wrapper-surface.out"

run_cmd \
  "Repo Attach Path Search" \
  "rg -n 'openclaw browser .*attach|openclaw browser .*reattach|openclaw browser extension .*attach|openclaw browser extension .*reattach' scripts/browser_nav.sh scripts/browser_read.sh scripts/browser_artifact.sh scripts/browser_ready_check.sh scripts/browser_remediate.sh scripts/task_run_nav.sh scripts/task_run_read.sh scripts/task_run_artifact.sh" \
  "repo-attach-search"
attach_search_file="$tmp_dir/repo-attach-search.out"

run_cmd \
  "Manual Host Attach Hints" \
  "rg -n 'badge ON|reattach manual|adjuntar una pestaña|relay del browser en estado ON' docs/LAUNCHER.md docs/V1_DECISION.md docs/V1_CHECKLIST.md docs/BROWSER_BLOCKERS_ANALYSIS.md" \
  "manual-host-hints"
manual_host_file="$tmp_dir/manual-host-hints.out"

printf '\n## Contract Classification\n'
render_contract_table \
  "$remediation_json_file" "$remediation_exit" \
  "$chrome_snapshot_file" "$chrome_snapshot_exit" \
  "$browser_cli_help_file" \
  "$wrapper_surface_file" "$attach_search_file" "$manual_host_file"
