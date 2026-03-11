#!/usr/bin/env bash
set -euo pipefail
test -f README.md
test -f docs/ARCHITECTURE.md
test -f docs/PROTOCOL.md
test -d openclaw
test -d codex
test -d outbox
echo "SMOKE_REPO_OK"
