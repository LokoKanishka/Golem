#!/usr/bin/env bash
set -euo pipefail

GOLEM_HOST_CAPABILITY_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLEM_HOST_CAPABILITY_REPO_ROOT="$(cd "${GOLEM_HOST_CAPABILITY_COMMON_DIR}/.." && pwd)"
GOLEM_HOST_CAPABILITIES_ROOT="${GOLEM_HOST_CAPABILITIES_ROOT:-${GOLEM_HOST_CAPABILITY_REPO_ROOT}/diagnostics/host-capabilities}"

golem_host_capabilities_latest_dir() {
  local suffix="$1"
  find "${GOLEM_HOST_CAPABILITIES_ROOT}" -mindepth 1 -maxdepth 1 -type d -name "*-golem-host-${suffix}" 2>/dev/null \
    | while read -r dir; do
        [ -f "${dir}/manifest.json" ] || continue
        printf '%s %s\n' "$(stat -c '%Y' "$dir" 2>/dev/null || printf '0')" "$dir"
      done \
    | sort -nr \
    | awk 'NR==1 {print substr($0, index($0,$2))}'
}

golem_host_capabilities_create_dir() {
  local suffix="$1"
  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${GOLEM_HOST_CAPABILITIES_ROOT}"
  local run_dir="${GOLEM_HOST_CAPABILITIES_ROOT}/${run_id}-golem-host-${suffix}"
  mkdir -p "${run_dir}"
  printf '%s\n' "$run_dir"
}

golem_host_capabilities_require_tools() {
  local missing=()
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'ERROR: missing required host tool(s): %s\n' "${missing[*]}" >&2
    exit 1
  fi
}

golem_host_capabilities_emit() {
  local format="$1"
  local summary_path="$2"
  local manifest_path="$3"
  local mode_label="$4"

  python3 - "$format" "$summary_path" "$manifest_path" "$mode_label" <<'PY'
import json
import pathlib
import sys

fmt = sys.argv[1]
summary_path = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
mode_label = sys.argv[4]

summary_text = summary_path.read_text(encoding="utf-8") if summary_path.exists() else ""
manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}

if fmt == "json":
    print(json.dumps(manifest, indent=2, ensure_ascii=True))
elif fmt == "path":
    print(manifest.get("run_dir", ""))
else:
    print(summary_text.rstrip())
PY
}
