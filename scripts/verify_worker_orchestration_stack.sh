#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RESULT_NAMES=()
RESULT_STATUSES=()
RESULT_NOTES=()

classify_log_status() {
  local log_path="$1"
  if rg -qi 'Permission denied|Read-only file system|No space left on device|Operation not permitted' "$log_path"; then
    printf 'BLOCKED\n'
  else
    printf 'FAIL\n'
  fi
}

run_verify() {
  local name="$1"
  local marker="$2"
  local cmd="$3"
  local log_path
  local output
  local exit_code
  local status
  local note

  log_path="$(mktemp "${TMPDIR:-/tmp}/golem-${name// /-}.XXXXXX.log")"

  printf '\n## %s\n' "$name"
  printf '$ %s\n' "$cmd"
  set +e
  output="$(cd "$REPO_ROOT" && bash -lc "$cmd" 2>&1)"
  exit_code="$?"
  set -e
  printf '%s\n' "$output"
  printf '%s\n' "$output" >"$log_path"

  if [ "$exit_code" -eq 0 ] && printf '%s\n' "$output" | rg -q "^${marker} "; then
    status="PASS"
    note="canonical verify passed"
  else
    status="$(classify_log_status "$log_path")"
    if [ "$status" = "BLOCKED" ]; then
      note="canonical verify was externally blocked by repo-local prerequisites"
    else
      note="canonical verify exposed an internal subsystem failure"
    fi
  fi

  RESULT_NAMES+=("$name")
  RESULT_STATUSES+=("$status")
  RESULT_NOTES+=("$note")

  printf 'subsystem_check: %s | %s | %s\n' "$name" "$status" "$note"
  rm -f "$log_path"
}

cd "$REPO_ROOT"

run_verify \
  "worker packet roundtrip" \
  "VERIFY_WORKER_PACKET_ROUNDTRIP_OK" \
  "bash ./scripts/verify_worker_packet_roundtrip.sh"

run_verify \
  "multi-worker barrier orchestration" \
  "VERIFY_MULTI_WORKER_AWAIT_OK" \
  "bash ./scripts/verify_multi_worker_await_roundtrip.sh"

run_verify \
  "chain execution audit" \
  "VERIFY_CHAIN_EXECUTION_AUDIT_OK" \
  "bash ./scripts/verify_chain_execution_audit.sh"

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

printf '\nsub_capability | status | note\n'
for index in "${!RESULT_NAMES[@]}"; do
  printf '%s | %s | %s\n' "${RESULT_NAMES[$index]}" "${RESULT_STATUSES[$index]}" "${RESULT_NOTES[$index]}"
done

printf 'PASS: %s\n' "$pass_count"
printf 'FAIL: %s\n' "$fail_count"
printf 'BLOCKED: %s\n' "$blocked_count"

if [ "$fail_count" -gt 0 ]; then
  printf 'VERIFY_WORKER_ORCHESTRATION_STACK_FAIL pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count" >&2
  exit 1
fi

if [ "$blocked_count" -gt 0 ]; then
  printf 'VERIFY_WORKER_ORCHESTRATION_STACK_BLOCKED pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count"
  exit 2
fi

printf 'VERIFY_WORKER_ORCHESTRATION_STACK_OK pass=%s fail=%s blocked=%s\n' "$pass_count" "$fail_count" "$blocked_count"
