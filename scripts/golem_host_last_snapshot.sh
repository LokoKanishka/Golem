#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIAGNOSTICS_ROOT="${GOLEM_HOST_DIAGNOSTICS_ROOT:-${REPO_ROOT}/diagnostics/host}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_last_snapshot.sh
  ./scripts/golem_host_last_snapshot.sh path
  ./scripts/golem_host_last_snapshot.sh quick
  ./scripts/golem_host_last_snapshot.sh json

Env overrides:
  GOLEM_HOST_DIAGNOSTICS_ROOT
EOF
}

latest_snapshot_dir() {
  find "${DIAGNOSTICS_ROOT}" -mindepth 1 -maxdepth 1 -type d -name '*-golem-host-diagnose' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | awk 'NR==1 {print substr($0, index($0,$2))}'
}

main() {
  local mode="${1:-quick}"
  local snapshot_dir

  if [ "$#" -gt 1 ]; then
    usage >&2
    exit 2
  fi

  case "$mode" in
    path|quick|json)
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  snapshot_dir="$(latest_snapshot_dir)"
  if [ -z "$snapshot_dir" ]; then
    printf 'FAIL: no host snapshots found under %s\n' "$DIAGNOSTICS_ROOT" >&2
    exit 1
  fi

  python3 - "$snapshot_dir" "$mode" <<'PY'
import json
import pathlib
import sys

snapshot_dir = pathlib.Path(sys.argv[1])
mode = sys.argv[2]

summary_path = snapshot_dir / "summary.txt"
manifest_path = snapshot_dir / "manifest.json"

summary_text = summary_path.read_text(encoding="utf-8") if summary_path.exists() else ""
manifest = {}
if manifest_path.exists():
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        manifest = {}

def summary_value(prefix: str) -> str:
    for line in summary_text.splitlines():
        if line.startswith(prefix):
            return line.split(": ", 1)[1]
    return ""

payload = {
    "snapshot_dir": str(snapshot_dir),
    "summary_path": str(summary_path),
    "manifest_path": str(manifest_path),
    "timestamp_utc": summary_value("trigger_requested_at_utc") or summary_value("snapshot_dir").split("/")[-1].split("-golem-host-diagnose")[0],
    "trigger_mode": summary_value("trigger_mode"),
    "trigger_source": summary_value("trigger_source"),
    "trigger_reason": summary_value("trigger_reason"),
    "overall": summary_value("overall"),
    "task_api_active": summary_value("task_api_active"),
    "whatsapp_bridge_active": summary_value("whatsapp_bridge_active"),
    "look_first": str(summary_path),
    "look_next": str(manifest_path),
}

if mode == "path":
    print(payload["snapshot_dir"])
elif mode == "json":
    print(json.dumps(payload, ensure_ascii=True, indent=2))
else:
    print("GOLEM HOST LAST SNAPSHOT")
    for key in (
        "snapshot_dir",
        "timestamp_utc",
        "trigger_mode",
        "trigger_source",
        "trigger_reason",
        "overall",
        "task_api_active",
        "whatsapp_bridge_active",
        "look_first",
        "look_next",
    ):
        print(f"{key}: {payload[key] or '(none)'}")
PY
}

main "$@"
