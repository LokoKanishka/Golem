#!/usr/bin/env bash
set -euo pipefail

DOC="docs/OPENCLAW_STATUS_PRE_CLOSURE_INDEX.md"

fail() {
  echo "VERIFY_FAIL: $1" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "missing $DOC"

patterns=(
  "## Pre-Closure Chain Index"
  "### status-evidence-pack"
  "### status-consistency-pack"
  "### status-triangulation-artifact-pack"
  "### status-triangulation-snapshot-workflow"
  "### status-snapshot-ticket-seeds-pack"
  "### status-seed-instantiation-examples-pack"
  "### status-ticket-skeletons-pack"
  "### status-skeleton-completion-examples-pack"
  "### status-ticket-near-final-examples-pack"
  "### status-ticket-finalization-checklist-pack"
  "### status-ticket-closure-notes-pack"
  '`doc_reference`'
  '`primary_role`'
  '`what_it_defines`'
  '`when_to_read`'
  '`do_not_infer`'
  "## When To Read Which"
  "docs/OPENCLAW_STATUS_REAL_CLOSURE_INDEX.md"
)

for pattern in "${patterns[@]}"; do
  grep -Fq "$pattern" "$DOC" || fail "missing pattern '$pattern' in $DOC"
done

echo "VERIFY_OK: openclaw status pre-closure index checks passed"
