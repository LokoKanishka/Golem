#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmpdir="$(mktemp -d)"
task_tie_id=""
task_fresh_id=""

cleanup() {
  if [[ -n "$task_tie_id" && -f "$REPO_ROOT/tasks/$task_tie_id.json" ]]; then
    rm -f "$REPO_ROOT/tasks/$task_tie_id.json"
  fi
  if [[ -n "$task_fresh_id" && -f "$REPO_ROOT/tasks/$task_fresh_id.json" ]]; then
    rm -f "$REPO_ROOT/tasks/$task_fresh_id.json"
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

create_out_tie="$(./scripts/task_create.sh "Smoke host verification policy tie" "Formalize host evidence tie precedence" --type smoke-host-policy-tie --owner system --source script)"
task_tie_id="$(printf '%s\n' "$create_out_tie" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_tie_id" ] || {
  echo "FAIL: no tie task id extracted" >&2
  exit 1
}

create_out_fresh="$(./scripts/task_create.sh "Smoke host verification policy freshness" "Formalize host evidence freshness and stale reasons" --type smoke-host-policy-freshness --owner system --source script)"
task_fresh_id="$(printf '%s\n' "$create_out_fresh" | awk '/^TASK_CREATED / {print $2}' | tail -n 1)"
[ -n "$task_fresh_id" ] || {
  echo "FAIL: no freshness task id extracted" >&2
  exit 1
}

python3 - "$REPO_ROOT" "$tmpdir" "$task_tie_id" "$task_fresh_id" <<'PY'
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
tmpdir = pathlib.Path(sys.argv[2]).resolve()
task_tie_id = sys.argv[3]
task_fresh_id = sys.argv[4]


def ensure_run(base: pathlib.Path, *, label: str):
    run_dir = base / label
    run_dir.mkdir(parents=True, exist_ok=True)
    manifest = run_dir / "manifest.json"
    summary = run_dir / "summary.txt"
    manifest.write_text(json.dumps({"run_dir": str(run_dir), "label": label}, indent=2) + "\n", encoding="utf-8")
    summary.write_text(f"summary for {label}\n", encoding="utf-8")
    return run_dir, manifest, summary


def write_task(task_id: str, payload: dict):
    task_path = repo_root / "tasks" / f"{task_id}.json"
    task = json.loads(task_path.read_text(encoding="utf-8"))
    task["artifacts"] = payload["artifacts"]
    task["evidence"] = payload["evidence"]
    task["outputs"] = payload["outputs"]
    task["host_expectation"] = payload["host_expectation"]
    task["host_verification"] = payload["host_verification"]
    task["updated_at"] = payload["updated_at"]
    task_path.write_text(json.dumps(task, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


tie_base = tmpdir / "tie"
tie_base.mkdir(parents=True, exist_ok=True)
tie_perceive_run, tie_perceive_manifest, tie_perceive_summary = ensure_run(tie_base, label="perceive")
tie_describe_run, tie_describe_manifest, tie_describe_summary = ensure_run(tie_base, label="describe")

tie_attached_at = "2026-04-03T10:00:00Z"
tie_payload = {
    "artifacts": [
        str(tie_perceive_summary),
        str(tie_describe_summary),
    ],
    "evidence": [
        {
            "type": "host-perceive",
            "note": "source=host source_kind=perceive capture_lane=golem_host_perceive target=active-window windows_total=2. tie perceive evidence",
            "path": str(tie_perceive_manifest),
            "command": "./scripts/golem_host_perceive.sh snapshot --json",
            "result": json.dumps(
                {
                    "source": "host",
                    "source_family": "host",
                    "source_kind": "perceive",
                    "capture_lane": "golem_host_perceive",
                    "target_kind": "active-window",
                    "run_dir": str(tie_perceive_run),
                    "summary": "tie perceive evidence",
                },
                separators=(",", ":"),
            ),
        },
        {
            "type": "host-describe",
            "note": "source=host source_kind=describe capture_lane=golem_host_describe target=active-window surface=desktop-app/moderate. tie describe evidence",
            "path": str(tie_describe_manifest),
            "command": "./scripts/golem_host_describe.sh active-window --json",
            "result": json.dumps(
                {
                    "source": "host",
                    "source_family": "host",
                    "source_kind": "describe",
                    "capture_lane": "golem_host_describe",
                    "target_kind": "active-window",
                    "run_dir": str(tie_describe_run),
                    "surface_category": "desktop-app",
                    "surface_confidence": "moderate",
                    "summary": "tie describe evidence",
                },
                separators=(",", ":"),
            ),
        },
    ],
    "outputs": [
        {
            "kind": "host-perceive-evidence",
            "captured_at": tie_attached_at,
            "exit_code": 0,
            "content": "TASK_HOST_PERCEIVE_EVIDENCE_ATTACHED",
            "source": "host",
            "source_family": "host",
            "source_kind": "perceive",
            "capture_lane": "golem_host_perceive",
            "target_kind": "active-window",
            "run_dir": str(tie_perceive_run),
        },
        {
            "kind": "host-describe-evidence",
            "captured_at": tie_attached_at,
            "exit_code": 0,
            "content": "TASK_HOST_DESCRIBE_EVIDENCE_ATTACHED",
            "source": "host",
            "source_family": "host",
            "source_kind": "describe",
            "capture_lane": "golem_host_describe",
            "target_kind": "active-window",
            "run_dir": str(tie_describe_run),
            "surface_category": "desktop-app",
            "surface_confidence": "moderate",
        },
    ],
    "host_expectation": {
        "source": "host",
        "target_kind": "active-window",
        "require_summary": True,
        "min_artifact_count": 1,
        "configured_at": "2026-04-03T10:00:00Z",
        "configured_by": "verify-host-policy",
        "note": "Tie-case policy expectation.",
    },
    "host_verification": {
        "evaluated_at": "2026-04-03T10:00:00Z",
        "evaluated_by": "verify-host-policy",
    },
    "updated_at": "2026-04-03T10:00:00Z",
}
write_task(task_tie_id, tie_payload)

fresh_base = tmpdir / "freshness"
fresh_base.mkdir(parents=True, exist_ok=True)
fresh_describe_run, fresh_describe_manifest, fresh_describe_summary = ensure_run(fresh_base, label="describe-old")
fresh_perceive_run, fresh_perceive_manifest, fresh_perceive_summary = ensure_run(fresh_base, label="perceive-new")

fresh_payload = {
    "artifacts": [
        str(fresh_describe_summary),
        str(fresh_perceive_summary),
    ],
    "evidence": [
        {
            "type": "host-describe",
            "note": "source=host source_kind=describe capture_lane=golem_host_describe target=active-window surface=desktop-app/strong. older describe evidence",
            "path": str(fresh_describe_manifest),
            "command": "./scripts/golem_host_describe.sh active-window --json",
            "result": json.dumps(
                {
                    "source": "host",
                    "source_family": "host",
                    "source_kind": "describe",
                    "capture_lane": "golem_host_describe",
                    "target_kind": "active-window",
                    "run_dir": str(fresh_describe_run),
                    "surface_category": "desktop-app",
                    "surface_confidence": "strong",
                    "summary": "older describe evidence",
                },
                separators=(",", ":"),
            ),
        },
        {
            "type": "host-perceive",
            "note": "source=host source_kind=perceive capture_lane=golem_host_perceive target=active-window windows_total=3. newer perceive evidence",
            "path": str(fresh_perceive_manifest),
            "command": "./scripts/golem_host_perceive.sh snapshot --json",
            "result": json.dumps(
                {
                    "source": "host",
                    "source_family": "host",
                    "source_kind": "perceive",
                    "capture_lane": "golem_host_perceive",
                    "target_kind": "active-window",
                    "run_dir": str(fresh_perceive_run),
                    "summary": "newer perceive evidence",
                },
                separators=(",", ":"),
            ),
        },
    ],
    "outputs": [
        {
            "kind": "host-describe-evidence",
            "captured_at": "2026-04-03T10:00:00Z",
            "exit_code": 0,
            "content": "TASK_HOST_DESCRIBE_EVIDENCE_ATTACHED",
            "source": "host",
            "source_family": "host",
            "source_kind": "describe",
            "capture_lane": "golem_host_describe",
            "target_kind": "active-window",
            "run_dir": str(fresh_describe_run),
            "surface_category": "desktop-app",
            "surface_confidence": "strong",
        },
        {
            "kind": "host-perceive-evidence",
            "captured_at": "2026-04-03T10:00:10Z",
            "exit_code": 0,
            "content": "TASK_HOST_PERCEIVE_EVIDENCE_ATTACHED",
            "source": "host",
            "source_family": "host",
            "source_kind": "perceive",
            "capture_lane": "golem_host_perceive",
            "target_kind": "active-window",
            "run_dir": str(fresh_perceive_run),
        },
    ],
    "host_expectation": {
        "source": "host",
        "target_kind": "active-window",
        "require_summary": True,
        "min_artifact_count": 1,
        "configured_at": "2026-04-03T10:00:20Z",
        "configured_by": "verify-host-policy",
        "note": "Freshness-case policy expectation.",
    },
    "host_verification": {
        "evaluated_at": "2026-04-03T10:00:05Z",
        "evaluated_by": "verify-host-policy",
    },
    "updated_at": "2026-04-03T10:00:20Z",
}
write_task(task_fresh_id, fresh_payload)
PY

show_tie_path="$tmpdir/show-tie.json"
summary_tie_path="$tmpdir/summary-tie.txt"
show_fresh_path="$tmpdir/show-fresh.json"
summary_fresh_path="$tmpdir/summary-fresh.txt"

./scripts/task_panel_read.sh show "$task_tie_id" >"$show_tie_path"
./scripts/task_summary.sh "$task_tie_id" >"$summary_tie_path"
./scripts/task_panel_read.sh show "$task_fresh_id" >"$show_fresh_path"
./scripts/task_summary.sh "$task_fresh_id" >"$summary_fresh_path"

python3 - "$show_tie_path" "$summary_tie_path" "$show_fresh_path" "$summary_fresh_path" <<'PY'
import json
import pathlib
import sys

show_tie = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
summary_tie = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
show_fresh = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
summary_fresh = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")

task_tie = show_tie["task"]
host_tie = task_tie["host_evidence_summary"]
verification_tie = task_tie["host_verification"]
assert host_tie["source_kind"] == "describe", host_tie
assert host_tie["selection_policy"] == "latest_attached_then_source_precedence", host_tie
assert "source precedence describe>perceive broke the tie" in host_tie["selection_reason"], host_tie
assert host_tie["candidate_count"] == 2, host_tie
assert host_tie["candidate_source_counts"] == {"describe": 1, "perceive": 1}, host_tie
assert verification_tie["status"] == "match", verification_tie
assert verification_tie["stale"] is False, verification_tie
assert verification_tie["stale_reasons"] == [], verification_tie
assert "host_selection_policy: latest_attached_then_source_precedence" in summary_tie, summary_tie
assert "host_verification_stale_reasons: (none)" in summary_tie, summary_tie

task_fresh = show_fresh["task"]
host_fresh = task_fresh["host_evidence_summary"]
verification_fresh = task_fresh["host_verification"]
assert host_fresh["source_kind"] == "perceive", host_fresh
assert host_fresh["selection_policy"] == "latest_attached_then_source_precedence", host_fresh
assert "selected freshest attached_at=2026-04-03T10:00:10Z" in host_fresh["selection_reason"], host_fresh
assert host_fresh["candidate_count"] == 2, host_fresh
assert verification_fresh["status"] == "match", verification_fresh
assert verification_fresh["stale"] is True, verification_fresh
assert verification_fresh["freshness_policy"] == "evaluation_must_cover_selected_evidence_and_current_expectation", verification_fresh
assert verification_fresh["stale_reasons"] == ["newer_host_evidence_attached", "host_expectation_updated"], verification_fresh
assert "host_verification_stale: yes" in summary_fresh, summary_fresh
assert "host_verification_stale_reasons: newer_host_evidence_attached,host_expectation_updated" in summary_fresh, summary_fresh

print("SMOKE_TASK_HOST_VERIFICATION_POLICY_OK")
print(f"TASK_HOST_POLICY_TIE_SOURCE {host_tie['source_kind']}")
print(f"TASK_HOST_POLICY_TIE_REASON {host_tie['selection_reason']}")
print(f"TASK_HOST_POLICY_FRESH_SOURCE {host_fresh['source_kind']}")
print(f"TASK_HOST_POLICY_STALE_REASONS {','.join(verification_fresh['stale_reasons'])}")
PY
