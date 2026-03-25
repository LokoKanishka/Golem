#!/usr/bin/env bash
set -euo pipefail

echo "--- git status --short ---"
git status --short

echo "--- git diff --stat ---"
git diff --stat

echo "--- git log --oneline -1 ---"
git log --oneline -1

echo "--- python compile check ---"
python3 -m py_compile scripts/golem_host_describe_analyze.py && echo "py_compile: OK"

echo "--- smoke tests not run: may require host environment (X11, wmctrl, etc.) ---"
echo "Run existing smoke scripts in tests/ when host environment is available."

exit 0
