import datetime as dt
import json
import pathlib


CONFIDENCE_ORDER = {
    "uncertain": 0,
    "weak": 1,
    "moderate": 2,
    "strong": 3,
}


def empty_host_evidence_summary():
    return {
        "present": False,
        "source": "",
        "capture_lane": "",
        "event_count": 0,
        "last_attached_at": "",
        "target_kind": "",
        "surface_category": "",
        "surface_label": "",
        "surface_confidence": "",
        "summary": "",
        "evidence_path": "",
        "command": "",
        "run_dir": "",
        "artifact_count": 0,
        "artifact_references": [],
        "non_empty_structured_fields": [],
        "non_empty_fine_fields": [],
        "non_empty_contextual_refinements": [],
        "non_empty_surface_state_fields": [],
    }


def empty_host_expectation():
    return {
        "present": False,
        "source": "host",
        "target_kind": "",
        "surface_category": "",
        "min_surface_confidence": "",
        "require_summary": False,
        "min_artifact_count": 0,
        "require_structured_fields": False,
        "configured_at": "",
        "configured_by": "",
        "note": "",
        "configured_checks": [],
    }


def empty_host_verification_summary():
    return {
        "present": False,
        "status": "",
        "reason": "",
        "mismatch_summary": "",
        "last_evaluated_at": "",
        "evaluated_by": "",
        "used_host_last_attached_at": "",
        "target_kind": "",
        "surface_category": "",
        "surface_confidence": "",
        "summary": "",
        "evidence_path": "",
        "run_dir": "",
        "artifact_count": 0,
        "artifact_references": [],
        "matched_checks": [],
        "mismatch_checks": [],
        "insufficient_checks": [],
        "stale": False,
    }


def parse_json_object(raw):
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    return parsed


def path_matches_run_dir(raw_path, run_dir, repo_root):
    if not raw_path or not run_dir:
        return False
    try:
        artifact_path = pathlib.Path(raw_path)
        if not artifact_path.is_absolute():
            artifact_path = repo_root / artifact_path
        artifact_resolved = artifact_path.resolve(strict=False)

        run_path = pathlib.Path(run_dir)
        if not run_path.is_absolute():
            run_path = repo_root / run_path
        run_resolved = run_path.resolve(strict=False)

        artifact_resolved.relative_to(run_resolved)
        return True
    except Exception:
        return False


def build_host_evidence_summary(task, repo_root):
    summary = empty_host_evidence_summary()

    host_entries = []
    for entry in task.get("evidence") or []:
        if not isinstance(entry, dict):
            continue
        result = parse_json_object(entry.get("result", ""))
        note = str(entry.get("note") or "")
        result_source = (result or {}).get("source", "")
        if entry.get("type") == "host-describe" or result_source == "host" or "source=host" in note:
            host_entries.append((entry, result))

    if not host_entries:
        return summary

    entry, result = host_entries[-1]
    latest_output = {}
    for output in reversed(task.get("outputs") or []):
        if not isinstance(output, dict):
            continue
        if output.get("kind") == "host-describe-evidence":
            latest_output = output
            break

    result = result or {}
    run_dir = str(result.get("run_dir") or latest_output.get("run_dir") or "")
    artifact_references = []
    for artifact in task.get("artifacts") or []:
        if not isinstance(artifact, str) or not artifact:
            continue
        if path_matches_run_dir(artifact, run_dir, repo_root):
            artifact_references.append(artifact)

    summary.update(
        {
            "present": True,
            "source": str(result.get("source") or latest_output.get("source") or "host"),
            "capture_lane": str(result.get("capture_lane") or "golem_host_describe"),
            "event_count": len(host_entries),
            "last_attached_at": str(latest_output.get("captured_at") or task.get("updated_at") or ""),
            "target_kind": str(result.get("target_kind") or latest_output.get("target_kind") or ""),
            "surface_category": str(result.get("surface_category") or latest_output.get("surface_category") or ""),
            "surface_label": str(result.get("surface_label") or ""),
            "surface_confidence": str(result.get("surface_confidence") or latest_output.get("surface_confidence") or ""),
            "summary": str(result.get("summary") or entry.get("note") or ""),
            "evidence_path": str(entry.get("path") or ""),
            "command": str(entry.get("command") or ""),
            "run_dir": run_dir,
            "artifact_count": len(artifact_references),
            "artifact_references": artifact_references,
            "non_empty_structured_fields": list(result.get("non_empty_structured_fields") or []),
            "non_empty_fine_fields": list(result.get("non_empty_fine_fields") or []),
            "non_empty_contextual_refinements": list(result.get("non_empty_contextual_refinements") or []),
            "non_empty_surface_state_fields": list(result.get("non_empty_surface_state_fields") or []),
        }
    )
    return summary


def normalize_host_expectation(raw):
    normalized = empty_host_expectation()
    if not isinstance(raw, dict) or not raw:
        return normalized

    normalized.update(
        {
            "present": True,
            "source": str(raw.get("source") or "host"),
            "target_kind": str(raw.get("target_kind") or ""),
            "surface_category": str(raw.get("surface_category") or ""),
            "min_surface_confidence": str(raw.get("min_surface_confidence") or ""),
            "require_summary": bool(raw.get("require_summary")),
            "min_artifact_count": int(raw.get("min_artifact_count") or 0),
            "require_structured_fields": bool(raw.get("require_structured_fields")),
            "configured_at": str(raw.get("configured_at") or ""),
            "configured_by": str(raw.get("configured_by") or ""),
            "note": str(raw.get("note") or ""),
        }
    )

    checks = []
    if normalized["target_kind"]:
        checks.append("target_kind")
    if normalized["surface_category"]:
        checks.append("surface_category")
    if normalized["min_surface_confidence"]:
        checks.append("min_surface_confidence")
    if normalized["require_summary"]:
        checks.append("require_summary")
    if normalized["min_artifact_count"] > 0:
        checks.append("min_artifact_count")
    if normalized["require_structured_fields"]:
        checks.append("require_structured_fields")
    normalized["configured_checks"] = checks
    return normalized


def _rank_confidence(value):
    return CONFIDENCE_ORDER.get(str(value or "").strip(), -1)


def _parse_iso(raw):
    if not raw:
        return None
    value = str(raw).strip()
    if not value:
        return None
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return dt.datetime.fromisoformat(value)
    except ValueError:
        return None


def evaluate_host_expectation(expectation, host_summary, evaluated_at="", evaluated_by=""):
    summary = empty_host_verification_summary()
    if not expectation.get("present"):
        return summary

    summary["present"] = True
    matched = []
    mismatches = []
    insufficient = []

    if not expectation.get("configured_checks"):
        insufficient.append("no host expectation checks configured")

    host_present = bool(host_summary.get("present"))
    if not host_present:
        insufficient.append("no host evidence attached")

    actual_target_kind = str(host_summary.get("target_kind") or "")
    actual_surface_category = str(host_summary.get("surface_category") or "")
    actual_confidence = str(host_summary.get("surface_confidence") or "")
    actual_summary = str(host_summary.get("summary") or "")
    actual_artifact_count = int(host_summary.get("artifact_count") or 0)
    structured_total = (
        len(host_summary.get("non_empty_structured_fields") or [])
        + len(host_summary.get("non_empty_fine_fields") or [])
        + len(host_summary.get("non_empty_contextual_refinements") or [])
        + len(host_summary.get("non_empty_surface_state_fields") or [])
    )

    expected_target_kind = expectation.get("target_kind") or ""
    if expected_target_kind:
        if not actual_target_kind:
            insufficient.append(f"missing host target_kind, expected {expected_target_kind}")
        elif actual_target_kind != expected_target_kind:
            mismatches.append(f"target_kind expected {expected_target_kind} got {actual_target_kind}")
        else:
            matched.append(f"target_kind={expected_target_kind}")

    expected_surface_category = expectation.get("surface_category") or ""
    if expected_surface_category:
        if not actual_surface_category:
            insufficient.append(f"missing host surface_category, expected {expected_surface_category}")
        elif actual_surface_category != expected_surface_category:
            mismatches.append(
                f"surface_category expected {expected_surface_category} got {actual_surface_category}"
            )
        else:
            matched.append(f"surface_category={expected_surface_category}")

    expected_confidence = expectation.get("min_surface_confidence") or ""
    if expected_confidence:
        if _rank_confidence(expected_confidence) < 0:
            insufficient.append(f"invalid expectation min_surface_confidence {expected_confidence}")
        elif not actual_confidence or _rank_confidence(actual_confidence) < 0:
            insufficient.append(
                f"missing comparable host surface_confidence, expected >= {expected_confidence}"
            )
        elif _rank_confidence(actual_confidence) < _rank_confidence(expected_confidence):
            mismatches.append(
                f"surface_confidence expected >= {expected_confidence} got {actual_confidence}"
            )
        else:
            matched.append(f"surface_confidence>={expected_confidence}")

    if expectation.get("require_summary"):
        if not actual_summary.strip():
            insufficient.append("expected non-empty host summary")
        else:
            matched.append("summary_present")

    min_artifact_count = int(expectation.get("min_artifact_count") or 0)
    if min_artifact_count > 0:
        if actual_artifact_count < min_artifact_count:
            insufficient.append(
                f"expected at least {min_artifact_count} host artifacts, got {actual_artifact_count}"
            )
        else:
            matched.append(f"artifact_count>={min_artifact_count}")

    if expectation.get("require_structured_fields"):
        if structured_total <= 0:
            insufficient.append("expected non-empty host structured/fine/contextual/bundle fields")
        else:
            matched.append("structured_fields_present")

    if mismatches:
        status = "mismatch"
        reason = mismatches[0]
    elif insufficient:
        status = "insufficient_evidence"
        reason = insufficient[0]
    else:
        status = "match"
        reason = "host evidence satisfies configured expectation"

    last_evaluated_at = str(evaluated_at or "")
    used_host_last_attached_at = str(host_summary.get("last_attached_at") or "")
    stale = False
    evaluated_dt = _parse_iso(last_evaluated_at)
    attached_dt = _parse_iso(used_host_last_attached_at)
    if evaluated_dt and attached_dt and evaluated_dt < attached_dt:
        stale = True

    summary.update(
        {
            "status": status,
            "reason": reason,
            "mismatch_summary": "; ".join(mismatches or insufficient[:1]),
            "last_evaluated_at": last_evaluated_at,
            "evaluated_by": str(evaluated_by or ""),
            "used_host_last_attached_at": used_host_last_attached_at,
            "target_kind": actual_target_kind,
            "surface_category": actual_surface_category,
            "surface_confidence": actual_confidence,
            "summary": actual_summary,
            "evidence_path": str(host_summary.get("evidence_path") or ""),
            "run_dir": str(host_summary.get("run_dir") or ""),
            "artifact_count": actual_artifact_count,
            "artifact_references": list(host_summary.get("artifact_references") or []),
            "matched_checks": matched,
            "mismatch_checks": mismatches,
            "insufficient_checks": insufficient,
            "stale": stale,
        }
    )
    return summary
