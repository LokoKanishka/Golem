#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
diagnostics_root="$tmpdir/diagnostics-host"
snapshot_dir="$diagnostics_root/20260323T000000Z-golem-host-diagnose"
helper_txt="$tmpdir/helper.txt"
summary_path="$snapshot_dir/summary.txt"
manifest_path="$snapshot_dir/manifest.json"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mkdir -p "$snapshot_dir"

cat >"$summary_path" <<EOF
GOLEM HOST DIAGNOSIS

SNAPSHOT:
snapshot_dir: $snapshot_dir
trigger_mode: manual
trigger_source: ux_smoke
trigger_reason: manual_request
trigger_requested_at_utc: 2026-03-23T00:00:00Z
auto_cooldown_seconds: 300
overall: FAIL

CURRENT CONTEXT:
gateway_context: active, runtime running, rpc ok | gateway_last_signal: RPC probe: ok
task_api_active: active | whatsapp_bridge_active: inactive

DO FIRST:
suggested_first_action: revisar healthcheck de whatsapp_bridge

DO NEXT:
second_action: mirar journal del servicio whatsapp_bridge

READ FIRST:
look_first: $summary_path

READ NEXT:
look_next: $manifest_path
EOF

cat >"$manifest_path" <<EOF
{
  "snapshot_dir": "$snapshot_dir",
  "quick_triage": {
    "suggested_first_action": "revisar healthcheck de whatsapp_bridge",
    "second_action": "mirar journal del servicio whatsapp_bridge"
  }
}
EOF

GOLEM_HOST_DIAGNOSTICS_ROOT="$diagnostics_root" \
./scripts/golem_host_last_snapshot.sh >"$helper_txt"

python3 - "$summary_path" "$helper_txt" "$manifest_path" <<'PY'
import pathlib
import sys

summary = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
helper = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
manifest_path = pathlib.Path(sys.argv[3])

def summary_value(prefix: str) -> str:
    for line in summary.splitlines():
        for segment in line.split(" | "):
            if segment.startswith(prefix + ": "):
                return segment.split(": ", 1)[1]
    raise AssertionError(f"missing {prefix}")

assert "GOLEM HOST LAST SNAPSHOT" in helper, helper
assert "CURRENT CONTEXT:" in helper, helper
assert "gateway_context / gateway_last_signal:" in helper, helper
assert "task_api_active / whatsapp_bridge_active:" in helper, helper
assert (
    "gateway_context / gateway_last_signal: "
    f"{summary_value('gateway_context')} | {summary_value('gateway_last_signal')}"
) in helper, helper
assert (
    "task_api_active / whatsapp_bridge_active: "
    f"{summary_value('task_api_active')} | {summary_value('whatsapp_bridge_active')}"
) in helper, helper
assert f"suggested_first_action: {summary_value('suggested_first_action')}" in helper, helper
assert f"second_action: {summary_value('second_action')}" in helper, helper
assert f"look_first: {summary_value('look_first')}" in helper, helper
assert f"look_next: {manifest_path}" in helper, helper
assert "gateway_context: active, runtime running, rpc ok | gateway_last_signal: RPC probe: ok" in summary, summary
assert "task_api_active: active | whatsapp_bridge_active: inactive" in summary, summary

print("SMOKE_HOST_LAST_SNAPSHOT_CONTEXT_LAYOUT_OK")
PY
