#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

run_check() {
  local label="$1"
  shift

  printf '== %s ==\n' "$label"
  "$@"
  printf '\n'
}

printf 'HOST_LANE_NOTE: this verify covers only the audited host perception/action lane\n'
printf 'HOST_LANE_NOTE: it does not prove delivery real, browser usable, readiness total, or permission to touch runtime\n\n'

run_check "host describe analyzer compile" python3 -m py_compile \
  scripts/golem_host_describe_analyze.py \
  scripts/golem_host_describe_analyze_internal/core.py \
  scripts/golem_host_describe_analyze_internal/fields.py
run_check "surface bundle fixture" python3 tests/verify_surface_bundle_fixture.py
run_check "smoke host perception session" ./tests/smoke_host_perception_session.sh
run_check "smoke host inspection lane" ./tests/smoke_host_inspection_lane.sh
run_check "smoke host action lane" ./tests/smoke_host_action_lane.sh
run_check "smoke host describe lane" ./tests/smoke_host_describe_lane.sh
run_check "smoke host describe visual reading" ./tests/smoke_host_describe_visual_reading.sh
run_check "smoke host describe surface profiles" ./tests/smoke_host_describe_surface_profiles.sh

printf 'HOST_LANE_ENFORCEMENT_OK\n'
