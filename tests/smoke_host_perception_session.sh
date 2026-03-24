#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
cap_root="$tmpdir/host-capabilities"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

json_output="$(
  GOLEM_HOST_CAPABILITIES_ROOT="$cap_root" \
  ./scripts/golem_host_perceive.sh snapshot --json
)"

python3 - "$json_output" <<'PY'
import json
import pathlib
import sys

payload = json.loads(sys.argv[1])
assert payload["kind"] == "golem_host_perceive"
assert payload["windows_total"] > 0
assert payload["active_window"]["window_id"]
assert payload["active_window"]["title"]
assert payload["visible_context"], payload

desktop = pathlib.Path(payload["artifacts"]["desktop_screenshot"])
active = pathlib.Path(payload["artifacts"]["active_window_screenshot"])
windows = pathlib.Path(payload["artifacts"]["windows"])
summary = pathlib.Path(payload["artifacts"]["summary"])

for path in (desktop, active, windows, summary):
    assert path.exists(), path
    assert path.stat().st_size > 0, path

summary_text = summary.read_text(encoding="utf-8")
assert "visible_context:" in summary_text

print("SMOKE_HOST_PERCEPTION_SESSION_OK")
print(f"HOST_PERCEPTION_ACTIVE_WINDOW {payload['active_window']['title']}")
print(f"HOST_PERCEPTION_WINDOWS_TOTAL {payload['windows_total']}")
print(f"HOST_PERCEPTION_RUN_DIR {payload['run_dir']}")
PY
