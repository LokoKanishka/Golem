#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTBOX_DIR="${REPO_ROOT}/outbox/manual"

timestamp_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

iso_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/render_status_triangulation_artifact.sh [options]

Options:
  --slug <value>                 Short artifact slug. Default: quick-reentry
  --gateway-summary <text>       Summary for `openclaw gateway status`
  --openclaw-summary <text>      Summary for `openclaw status`
  --channels-summary <text>      Summary for `openclaw channels status --probe`
  --alignment-note <text>        Alignment/divergence note
  --verify-result <text>         PASS|PARTIAL|BLOCKED|UNVERIFIED. Default: UNVERIFIED
  --limitations <text>           Extra limitation line. Repeatable.
  --short-conclusion <text>      Short conclusion line
  --output <path>                Write to exact path instead of stdout
  --write                        Write to outbox/manual with canonical name
  --help                         Show this help
EOF
}

slug="quick-reentry"
gateway_summary="TODO: summarize \`openclaw gateway status\`"
openclaw_summary="TODO: summarize \`openclaw status\`"
channels_summary="TODO: summarize \`openclaw channels status --probe\`"
alignment_note="TODO: aligned | acceptable divergence | divergence needs more evidence"
verify_result="UNVERIFIED"
short_conclusion="TODO: close with a 3-5 line read-side conclusion and explicit limits."
output_path=""
write_outbox="no"
limitations=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)
      slug="${2:-}"
      shift 2
      ;;
    --gateway-summary)
      gateway_summary="${2:-}"
      shift 2
      ;;
    --openclaw-summary)
      openclaw_summary="${2:-}"
      shift 2
      ;;
    --channels-summary)
      channels_summary="${2:-}"
      shift 2
      ;;
    --alignment-note)
      alignment_note="${2:-}"
      shift 2
      ;;
    --verify-result)
      verify_result="${2:-}"
      shift 2
      ;;
    --limitations)
      limitations+=("${2:-}")
      shift 2
      ;;
    --short-conclusion)
      short_conclusion="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    --write)
      write_outbox="yes"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#limitations[@]} -eq 0 ]]; then
  limitations=(
    "no prueba delivery real"
    "no prueba browser usable"
    "no autoriza tocar runtime"
  )
fi

repo_branch="$(git -C "${REPO_ROOT}" branch --show-current)"
repo_commit="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
if [[ -n "$(git -C "${REPO_ROOT}" status --short)" ]]; then
  repo_dirty="yes"
else
  repo_dirty="no"
fi

artifact_timestamp="$(timestamp_utc)"
artifact_iso="$(iso_utc)"
artifact_slug="$(slugify "${slug}")"
canonical_filename="${artifact_timestamp}_status-triangulation-artifact_${artifact_slug}.md"

render_artifact() {
  cat <<EOF
# OpenClaw Status Triangulation Artifact

status_triangulation_at: ${artifact_iso}
repo_branch: ${repo_branch}
repo_commit: ${repo_commit}
repo_dirty: ${repo_dirty}
gateway_status_summary: ${gateway_summary}
openclaw_status_summary: ${openclaw_summary}
channels_probe_summary: ${channels_summary}
alignment_or_divergence_note: ${alignment_note}
primary_verify: ./scripts/verify_openclaw_capability_truth.sh
primary_verify_result: ${verify_result}
limitations:
EOF
  for limitation in "${limitations[@]}"; do
    printf -- "- %s\n" "${limitation}"
  done
  cat <<EOF
short_conclusion: ${short_conclusion}

canonical_docs:
- docs/OPENCLAW_STATUS_EVIDENCE_PACK.md
- docs/OPENCLAW_STATUS_CONSISTENCY_PACK.md
- docs/OPENCLAW_STATUS_TRIANGULATION_ARTIFACT_PACK.md
- docs/CAPABILITY_MATRIX.md
- docs/CURRENT_STATE.md
- handoffs/HANDOFF_CURRENT.md
EOF
}

if [[ -n "${output_path}" && "${write_outbox}" == "yes" ]]; then
  echo "Choose either --output or --write, not both." >&2
  exit 1
fi

if [[ "${write_outbox}" == "yes" ]]; then
  mkdir -p "${OUTBOX_DIR}"
  output_path="${OUTBOX_DIR}/${canonical_filename}"
fi

if [[ -n "${output_path}" ]]; then
  render_artifact > "${output_path}"
  printf '%s\n' "${output_path}"
else
  render_artifact
fi
