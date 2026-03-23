#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

find tasks -maxdepth 1 -type f -name 'task-*.json' | sort > "$tmp"

total="$(grep -c . "$tmp" || true)"
ignored=0
tracked=0
untracked_visible=0

while IFS= read -r path; do
  [[ -n "$path" ]] || continue

  if git check-ignore -q "$path"; then
    ignored=$((ignored + 1))
  fi

  if git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    tracked=$((tracked + 1))
  else
    untracked_visible=$((untracked_visible + 1))
  fi
done < "$tmp"

echo "TASK_GIT_TRACE_SUMMARY total=$total tracked=$tracked ignored=$ignored visible_untracked=$untracked_visible"

if [[ "$ignored" -gt 0 ]]; then
  echo "FAIL: active canonical task files are still ignored by Git." >&2
  exit 1
fi

echo "TASK_GIT_TRACE_OK"
