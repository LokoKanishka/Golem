#!/usr/bin/env bash
set -euo pipefail

echo "Running official verify: syntax, bundle verify, repo status"

# 1) Python syntax check across key scripts
python -m py_compile scripts/golem_host_describe_analyze.py

# 2) Run the lightweight surface bundle verify
if [ -f tests/verify_surface_bundle.sh ]; then
  bash tests/verify_surface_bundle.sh
else
  echo "tests/verify_surface_bundle.sh not found — skipping lightweight verify"
fi

# 3) Show last commit and diffstat to make the run auditable
git --no-pager log -n 1 --oneline || true
git --no-pager diff --stat HEAD~1..HEAD || true

echo "Official verify completed.\nNotes: full smoke tests require X11 and host tools (wmctrl, tesseract)."