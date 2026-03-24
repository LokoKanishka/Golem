#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/golem_host_capability_common.sh
source "${SCRIPT_DIR}/golem_host_capability_common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_inspect.sh
  ./scripts/golem_host_inspect.sh snapshot [--json]
  ./scripts/golem_host_inspect.sh path
  ./scripts/golem_host_inspect.sh json

Env overrides:
  GOLEM_HOST_CAPABILITIES_ROOT
EOF
}

snapshot() {
  local run_dir summary_path manifest_path ps_txt services_txt ports_txt lsof_txt

  golem_host_capabilities_require_tools python3 ps ss
  run_dir="$(golem_host_capabilities_create_dir inspect)"
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"
  ps_txt="${run_dir}/processes.txt"
  services_txt="${run_dir}/user-services.txt"
  ports_txt="${run_dir}/ports.txt"
  lsof_txt="${run_dir}/lsof-listeners.txt"

  ps -eo pid,ppid,stat,%cpu,%mem,comm,args --sort=-%cpu >"$ps_txt"
  systemctl --user --type=service --all --no-pager --no-legend >"$services_txt" 2>&1 || true
  ss -ltnp >"$ports_txt"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP -sTCP:LISTEN >"$lsof_txt" 2>&1 || true
  else
    printf 'lsof not available\n' >"$lsof_txt"
  fi

  python3 - "$run_dir" "$ps_txt" "$services_txt" "$ports_txt" "$lsof_txt" "$summary_path" "$manifest_path" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
ps_txt = pathlib.Path(sys.argv[2])
services_txt = pathlib.Path(sys.argv[3])
ports_txt = pathlib.Path(sys.argv[4])
lsof_txt = pathlib.Path(sys.argv[5])
summary_path = pathlib.Path(sys.argv[6])
manifest_path = pathlib.Path(sys.argv[7])

process_lines = ps_txt.read_text(encoding="utf-8").splitlines()
service_lines = [line for line in services_txt.read_text(encoding="utf-8").splitlines() if line.strip()]
port_lines = [line for line in ports_txt.read_text(encoding="utf-8").splitlines() if line.strip()]
lsof_lines = [line for line in lsof_txt.read_text(encoding="utf-8").splitlines() if line.strip()]

interesting_ports = []
for line in port_lines[1:]:
    if "LISTEN" not in line:
        continue
    interesting_ports.append(line)

top_processes = process_lines[1:6]
top_services = service_lines[:8]
top_listeners = interesting_ports[:8]

summary_lines = [
    "GOLEM HOST INSPECTION",
    "",
    f"run_dir: {run_dir}",
    f"process_rows: {max(len(process_lines) - 1, 0)}",
    f"user_service_rows: {len(service_lines)}",
    f"listener_rows: {max(len(interesting_ports), 0)}",
    "top_processes:",
]
summary_lines.extend(f"- {line}" for line in top_processes or ["(none)"])
summary_lines.append("top_user_services:")
summary_lines.extend(f"- {line}" for line in top_services or ["(none)"])
summary_lines.append("top_listeners:")
summary_lines.extend(f"- {line}" for line in top_listeners or ["(none)"])

summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

manifest = {
    "kind": "golem_host_inspect",
    "run_dir": str(run_dir),
    "artifacts": {
        "summary": str(summary_path),
        "processes": str(ps_txt),
        "user_services": str(services_txt),
        "ports": str(ports_txt),
        "lsof_listeners": str(lsof_txt),
    },
    "counts": {
        "process_rows": max(len(process_lines) - 1, 0),
        "user_service_rows": len(service_lines),
        "listener_rows": len(interesting_ports),
    },
    "top_processes": top_processes,
    "top_user_services": top_services,
    "top_listeners": top_listeners,
}
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY

  golem_host_capabilities_emit "text" "$summary_path" "$manifest_path" "GOLEM HOST INSPECTION"
}

latest() {
  local run_dir summary_path manifest_path
  run_dir="$(golem_host_capabilities_latest_dir inspect)"
  [ -n "$run_dir" ] || {
    printf 'FAIL: no host inspection runs found under %s\n' "$GOLEM_HOST_CAPABILITIES_ROOT" >&2
    exit 1
  }
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"
  golem_host_capabilities_emit "$1" "$summary_path" "$manifest_path" "GOLEM HOST INSPECTION"
}

main() {
  local mode="${1:-snapshot}"
  local format="text"

  case "$mode" in
    snapshot)
      shift || true
      if [ "${1:-}" = "--json" ]; then
        format="json"
      elif [ "$#" -gt 0 ]; then
        usage >&2
        exit 2
      fi
      if [ "$format" = "json" ]; then
        snapshot >/dev/null
        latest json
      else
        snapshot
      fi
      ;;
    path)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest path
      ;;
    json)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest json
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
