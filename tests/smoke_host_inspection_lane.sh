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
  ./scripts/golem_host_inspect.sh snapshot --json
)"

python3 - "$json_output" <<'PY'
import json
import pathlib
import sys

payload = json.loads(sys.argv[1])
assert payload["kind"] == "golem_host_inspect"
assert payload["counts"]["process_rows"] > 0
assert payload["counts"]["listener_rows"] > 0
assert payload["top_processes"], payload
assert payload["top_listeners"], payload

for key in ("summary", "processes", "user_services", "ports"):
    path = pathlib.Path(payload["artifacts"][key])
    assert path.exists(), path
    assert path.stat().st_size > 0, path

print("SMOKE_HOST_INSPECTION_LANE_OK")
print(f"HOST_INSPECTION_PROCESS_ROWS {payload['counts']['process_rows']}")
print(f"HOST_INSPECTION_LISTENER_ROWS {payload['counts']['listener_rows']}")
print(f"HOST_INSPECTION_RUN_DIR {payload['run_dir']}")
PY
