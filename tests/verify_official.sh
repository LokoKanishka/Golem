#!/usr/bin/env bash
set -euo pipefail

echo "Running official verify: syntax, bundle verify, repo status"

# 1) Python syntax check across key scripts
python3 -m py_compile scripts/golem_host_describe_analyze.py

# 2) Run the lightweight surface bundle verify
if [ -f tests/verify_surface_bundle.sh ]; then
  bash tests/verify_surface_bundle.sh
else
  echo "tests/verify_surface_bundle.sh not found — skipping lightweight verify"
fi

# 3) Run a fixture-backed bundle normalization verify
if [ -f tests/verify_surface_bundle_fixture.py ]; then
  python3 tests/verify_surface_bundle_fixture.py
else
  echo "tests/verify_surface_bundle_fixture.py not found — skipping fixture verify"
fi

# 4) Show last commit and diffstat to make the run auditable
git --no-pager log -n 1 --oneline || true
git --no-pager diff --stat HEAD~1..HEAD || true

printf '%s\n%s\n' \
  "Official verify completed." \
  "Notes: full smoke tests require X11 and host tools (wmctrl, tesseract)."
