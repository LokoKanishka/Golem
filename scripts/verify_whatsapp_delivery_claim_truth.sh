#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

set +e
output="$(cd "$REPO_ROOT" && bash ./scripts/verify_whatsapp_provider_delivery_truth.sh 2>&1)"
exit_code="$?"
set -e

printf '%s\n' "$output"

report_path="$(printf '%s\n' "$output" | awk '/^report_path: / {print $2}' | tail -n 1)"
if [ -z "$report_path" ]; then
  report_path="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^report=/) {sub(/^report=/, "", $i); print $i}}' | tail -n 1)"
fi

gateway_task="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^gateway=/) {sub(/^gateway=/, "", $i); print $i}}' | tail -n 1)"
ambiguous_task="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^ambiguous=/) {sub(/^ambiguous=/, "", $i); print $i}}' | tail -n 1)"
delivered_task="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^delivered=/) {sub(/^delivered=/, "", $i); print $i}}' | tail -n 1)"
verified_task="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^verified=/) {sub(/^verified=/, "", $i); print $i}}' | tail -n 1)"
drift_task="$(printf '%s\n' "$output" | awk '/^VERIFY_WHATSAPP_PROVIDER_DELIVERY_TRUTH_(OK|FAIL) / {for (i = 1; i <= NF; i++) if ($i ~ /^drift=/) {sub(/^drift=/, "", $i); print $i}}' | tail -n 1)"

if [ "$exit_code" -eq 0 ]; then
  printf 'VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_OK gateway=%s delivered=%s verified=%s ambiguous=%s drift=%s report=%s\n' \
    "$gateway_task" "$delivered_task" "$verified_task" "$ambiguous_task" "$drift_task" "$report_path"
  exit 0
fi

printf 'VERIFY_WHATSAPP_DELIVERY_CLAIM_TRUTH_FAIL gateway=%s delivered=%s verified=%s ambiguous=%s drift=%s report=%s\n' \
  "$gateway_task" "$delivered_task" "$verified_task" "$ambiguous_task" "$drift_task" "$report_path" >&2
exit "$exit_code"
