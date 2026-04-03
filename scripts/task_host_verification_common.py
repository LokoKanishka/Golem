import datetime as dt
import json
import pathlib


CONFIDENCE_ORDER = {
    "uncertain": 0,
    "weak": 1,
    "moderate": 2,
    "strong": 3,
}

HOST_SOURCE_DEFAULTS = {
    "describe": {
        "evidence_type": "host-describe",
        "output_kind": "host-describe-evidence",
        "capture_lane": "golem_host_describe",
    },
    "perceive": {
        "evidence_type": "host-perceive",
        "output_kind": "host-perceive-evidence",
        "capture_lane": "golem_host_perceive",
    },
}

HOST_EVIDENCE_TYPES = {
    config["evidence_type"] for config in HOST_SOURCE_DEFAULTS.values()
}
HOST_OUTPUT_KINDS = {
    config["output_kind"] for config in HOST_SOURCE_DEFAULTS.values()
}

HOST_SOURCE_PRECEDENCE = {
    "describe": 20,
    "perceive": 10,
}

HOST_EVIDENCE_SELECTION_POLICY = "latest_attached_then_source_precedence"
HOST_VERIFICATION_FRESHNESS_POLICY = (
    "evaluation_must_cover_selected_evidence_and_current_expectation"
)


def empty_host_evidence_summary():
    return {
        "present": False,
        "source": "",
        "source_family": "",
        "source_kind": "",
        "source_precedence": 0,
        "capture_lane": "",
        "event_count": 0,
        "candidate_count": 0,
        "candidate_source_counts": {},
        "selection_policy": "",
        "selection_reason": "",
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
        "source_family": "",
        "source_kind": "",
        "capture_lane": "",
        "selection_policy": "",
        "selection_reason": "",
        "freshness_policy": "",
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
        "stale_reasons": [],
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


def host_source_defaults(source_kind):
    return HOST_SOURCE_DEFAULTS.get(str(source_kind or "").strip(), {})


def infer_host_source_kind(result=None, entry_type="", output_kind="", capture_lane=""):
    result = result if isinstance(result, dict) else {}
    explicit = str(result.get("source_kind") or result.get("capture_source_kind") or "").strip()
    if explicit:
        return explicit

    entry_type = str(entry_type or "").strip()
    if entry_type == "host-describe":
        return "describe"
    if entry_type == "host-perceive":
        return "perceive"

    output_kind = str(output_kind or "").strip()
    if output_kind == "host-describe-evidence":
        return "describe"
    if output_kind == "host-perceive-evidence":
        return "perceive"

    capture_lane = str(capture_lane or result.get("capture_lane") or "").strip()
    if capture_lane == "golem_host_describe":
        return "describe"
    if capture_lane == "golem_host_perceive":
        return "perceive"

    return ""


def infer_host_capture_lane(source_kind="", capture_lane=""):
    if capture_lane:
        return str(capture_lane)
    defaults = host_source_defaults(source_kind)
    return str(defaults.get("capture_lane") or "")


def normalize_host_evidence_result(raw, entry_type="", output_kind=""):
    result = raw if isinstance(raw, dict) else {}
    source_kind = infer_host_source_kind(
        result=result,
        entry_type=entry_type,
        output_kind=output_kind,
        capture_lane=result.get("capture_lane") if isinstance(result, dict) else "",
    )
    source_family = str(result.get("source_family") or result.get("source") or "")
    if not source_family and source_kind:
        source_family = "host"

    return {
        "source": source_family,
        "source_family": source_family,
        "source_kind": source_kind,
        "capture_lane": infer_host_capture_lane(source_kind, result.get("capture_lane")),
        "target_kind": str(result.get("target_kind") or ""),
        "surface_category": str(result.get("surface_category") or ""),
        "surface_label": str(result.get("surface_label") or ""),
        "surface_confidence": str(result.get("surface_confidence") or ""),
        "summary": str(result.get("summary") or ""),
        "run_dir": str(result.get("run_dir") or ""),
        "non_empty_structured_fields": list(result.get("non_empty_structured_fields") or []),
        "non_empty_fine_fields": list(result.get("non_empty_fine_fields") or []),
        "non_empty_contextual_refinements": list(result.get("non_empty_contextual_refinements") or []),
        "non_empty_surface_state_fields": list(result.get("non_empty_surface_state_fields") or []),
    }


def is_host_evidence_entry(entry, result=None):
    if not isinstance(entry, dict):
        return False
    entry_type = str(entry.get("type") or "").strip()
    if entry_type in HOST_EVIDENCE_TYPES:
        return True

    normalized = normalize_host_evidence_result(result, entry_type=entry_type)
    if normalized.get("source_family") == "host":
        return True

    note = str(entry.get("note") or "")
    return "source=host" in note


def is_host_output(output):
    if not isinstance(output, dict):
        return False
    output_kind = str(output.get("kind") or "").strip()
    if output_kind in HOST_OUTPUT_KINDS:
        return True

    source_family = str(output.get("source_family") or output.get("source") or "").strip()
    return source_family == "host"


def repo_relative(raw_path, repo_root):
    path = pathlib.Path(raw_path).expanduser()
    resolved = path.resolve(strict=False)
    repo_root = pathlib.Path(repo_root).resolve()
    try:
        return str(resolved.relative_to(repo_root))
    except Exception:
        return str(resolved)


def _compact_summary(raw):
    return " ".join(str(raw or "").split()).strip()


def _host_source_precedence(source_kind):
    return HOST_SOURCE_PRECEDENCE.get(str(source_kind or "").strip(), 0)


def _format_iso_z(value):
    if not value:
        return ""
    parsed = _parse_iso(value)
    if parsed is None:
        return str(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _find_matching_host_output(task, normalized_result, source_kind):
    for output in reversed(task.get("outputs") or []):
        if not isinstance(output, dict):
            continue
        if not is_host_output(output):
            continue
        output_kind = str(output.get("kind") or "")
        output_source_kind = infer_host_source_kind(
            output_kind=output_kind,
            capture_lane=output.get("capture_lane"),
        )
        output_run_dir = str(output.get("run_dir") or "")
        if normalized_result.get("run_dir") and output_run_dir and output_run_dir != normalized_result.get("run_dir"):
            continue
        if source_kind and output_source_kind and output_source_kind != source_kind:
            continue
        return output
    return {}


def _host_artifact_references(task, run_dir, repo_root):
    artifact_references = []
    for artifact in task.get("artifacts") or []:
        if not isinstance(artifact, str) or not artifact:
            continue
        if path_matches_run_dir(artifact, run_dir, repo_root):
            artifact_references.append(artifact)
    return artifact_references


def _build_host_evidence_candidates(task, repo_root):
    candidates = []
    for entry_index, entry in enumerate(task.get("evidence") or []):
        if not isinstance(entry, dict):
            continue
        result = parse_json_object(entry.get("result", ""))
        if not is_host_evidence_entry(entry, result):
            continue
        normalized = normalize_host_evidence_result(result, entry_type=entry.get("type"))
        source_kind = str(normalized.get("source_kind") or "")
        output = _find_matching_host_output(task, normalized, source_kind)
        run_dir = str(normalized.get("run_dir") or output.get("run_dir") or "")
        artifact_references = _host_artifact_references(task, run_dir, repo_root)
        attached_at = str(output.get("captured_at") or "")
        attached_dt = _parse_iso(attached_at)
        source_precedence = _host_source_precedence(source_kind)

        candidates.append(
            {
                "entry": entry,
                "entry_index": entry_index,
                "result": normalized,
                "output": output,
                "run_dir": run_dir,
                "attached_at": attached_at,
                "attached_dt": attached_dt,
                "artifact_references": artifact_references,
                "artifact_count": len(artifact_references),
                "source_kind": source_kind,
                "source_family": str(normalized.get("source_family") or output.get("source_family") or output.get("source") or ""),
                "source_precedence": source_precedence,
            }
        )
    return candidates


def _candidate_sort_key(candidate):
    attached_dt = candidate.get("attached_dt")
    return (
        attached_dt.timestamp() if attached_dt else float("-inf"),
        int(candidate.get("source_precedence") or 0),
        int(candidate.get("artifact_count") or 0),
        int(candidate.get("entry_index") or 0),
    )


def _candidate_source_counts(candidates):
    counts = {}
    for candidate in candidates:
        source_kind = str(candidate.get("source_kind") or "unknown")
        counts[source_kind] = counts.get(source_kind, 0) + 1
    return counts


def _build_selection_reason(selected, candidates):
    if not selected:
        return ""
    selected_attached_at = str(selected.get("attached_at") or "")
    if selected_attached_at:
        tied_candidates = [
            candidate for candidate in candidates if str(candidate.get("attached_at") or "") == selected_attached_at
        ]
        if len(tied_candidates) > 1:
            return (
                f"selected attached_at={_format_iso_z(selected_attached_at)}; "
                f"source precedence describe>perceive broke the tie"
            )
        return f"selected freshest attached_at={_format_iso_z(selected_attached_at)}"
    return (
        f"selected by source precedence describe>perceive; "
        f"no comparable attached_at was available"
    )


def build_host_bridge_payload(payload, repo_root, source_kind):
    repo_root = pathlib.Path(repo_root).resolve()
    payload = payload if isinstance(payload, dict) else {}
    source_kind = str(source_kind or "").strip()

    if source_kind == "describe":
        description = payload.get("description") or {}
        surface = description.get("surface_classification") or {}
        structured = description.get("structured_fields") or {}
        bundle = description.get("surface_state_bundle") or {}
        artifacts = payload.get("artifacts") or {}
        target = payload.get("target") or {}

        summary = _compact_summary(description.get("summary"))
        result = normalize_host_evidence_result(
            {
                "source": "host",
                "source_family": "host",
                "source_kind": "describe",
                "capture_lane": "golem_host_describe",
                "target_kind": target.get("kind") or "",
                "run_dir": payload.get("run_dir") or "",
                "surface_category": surface.get("category") or "",
                "surface_label": surface.get("label") or "",
                "surface_confidence": surface.get("confidence") or "",
                "summary": summary,
                "non_empty_structured_fields": structured.get("non_empty_fields") or [],
                "non_empty_fine_fields": structured.get("non_empty_fine_fields") or [],
                "non_empty_contextual_refinements": structured.get("non_empty_contextual_refinements") or [],
                "non_empty_surface_state_fields": bundle.get("non_empty_fields") or [],
            },
            entry_type="host-describe",
        )
        note = (
            f"source=host source_kind=describe capture_lane=golem_host_describe "
            f"target={result['target_kind']} surface={result['surface_category']}/{result['surface_confidence']}. "
            f"{summary}"
        ).strip()
        output_extra = {
            "source": "host",
            "source_family": "host",
            "source_kind": "describe",
            "capture_lane": "golem_host_describe",
            "target_kind": result["target_kind"],
            "run_dir": result["run_dir"],
            "surface_category": result["surface_category"],
            "surface_confidence": result["surface_confidence"],
        }
        artifact_paths = [
            artifacts.get("summary", ""),
            artifacts.get("description", ""),
            artifacts.get("sources", ""),
            artifacts.get("target_screenshot", ""),
            artifacts.get("surface_profile", ""),
            artifacts.get("structured_fields", ""),
            artifacts.get("surface_state_bundle", ""),
        ]
        evidence_path = repo_relative(
            pathlib.Path(result["run_dir"]) / "manifest.json",
            repo_root,
        )
        return {
            "note": note,
            "result": result,
            "output_extra": output_extra,
            "evidence_path": evidence_path,
            "artifact_paths": [repo_relative(path, repo_root) for path in artifact_paths if path],
        }

    if source_kind == "perceive":
        artifacts = payload.get("artifacts") or {}
        active_window = payload.get("active_window") or {}
        visible_context = list(payload.get("visible_context") or [])
        active_title = _compact_summary(active_window.get("title"))
        summary_parts = []
        if active_title:
            summary_parts.append(f"Active window: {active_title}.")
        if visible_context:
            summary_parts.append(
                "Visible context: " + ", ".join(_compact_summary(item) for item in visible_context[:5] if item)
            )
        if not summary_parts:
            summary_parts.append(f"Perceived {int(payload.get('windows_total') or 0)} visible windows.")
        summary = _compact_summary(" ".join(summary_parts))

        target_kind = "active-window" if active_window.get("window_id") or active_title else ""
        result = normalize_host_evidence_result(
            {
                "source": "host",
                "source_family": "host",
                "source_kind": "perceive",
                "capture_lane": "golem_host_perceive",
                "target_kind": target_kind,
                "run_dir": payload.get("run_dir") or "",
                "summary": summary,
            },
            entry_type="host-perceive",
        )
        note = (
            f"source=host source_kind=perceive capture_lane=golem_host_perceive "
            f"target={target_kind or 'unknown'} windows_total={int(payload.get('windows_total') or 0)}. "
            f"{summary}"
        ).strip()
        output_extra = {
            "source": "host",
            "source_family": "host",
            "source_kind": "perceive",
            "capture_lane": "golem_host_perceive",
            "target_kind": result["target_kind"],
            "run_dir": result["run_dir"],
        }
        artifact_paths = [
            artifacts.get("summary", ""),
            artifacts.get("desktop_screenshot", ""),
            artifacts.get("active_window_screenshot", ""),
            artifacts.get("windows", ""),
            artifacts.get("active_window_properties", ""),
        ]
        evidence_path = repo_relative(
            pathlib.Path(result["run_dir"]) / "manifest.json",
            repo_root,
        )
        return {
            "note": note,
            "result": result,
            "output_extra": output_extra,
            "evidence_path": evidence_path,
            "artifact_paths": [repo_relative(path, repo_root) for path in artifact_paths if path],
        }

    raise ValueError(f"unsupported host source kind: {source_kind}")


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
    candidates = _build_host_evidence_candidates(task, repo_root)
    if not candidates:
        return summary

    selected = max(candidates, key=_candidate_sort_key)
    entry = selected["entry"]
    result = selected["result"]
    output = selected["output"]
    run_dir = str(selected.get("run_dir") or "")
    artifact_references = list(selected.get("artifact_references") or [])
    source_kind = str(selected.get("source_kind") or "")
    source_family = str(selected.get("source_family") or "")
    if not source_family and source_kind:
        source_family = "host"

    summary.update(
        {
            "present": True,
            "source": source_family,
            "source_family": source_family,
            "source_kind": source_kind,
            "source_precedence": int(selected.get("source_precedence") or 0),
            "capture_lane": str(
                result.get("capture_lane")
                or output.get("capture_lane")
                or infer_host_capture_lane(source_kind)
            ),
            "event_count": len(candidates),
            "candidate_count": len(candidates),
            "candidate_source_counts": _candidate_source_counts(candidates),
            "selection_policy": HOST_EVIDENCE_SELECTION_POLICY,
            "selection_reason": _build_selection_reason(selected, candidates),
            "last_attached_at": str(selected.get("attached_at") or task.get("updated_at") or ""),
            "target_kind": str(result.get("target_kind") or output.get("target_kind") or ""),
            "surface_category": str(result.get("surface_category") or output.get("surface_category") or ""),
            "surface_label": str(result.get("surface_label") or ""),
            "surface_confidence": str(result.get("surface_confidence") or output.get("surface_confidence") or ""),
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
    stale_reasons = []
    evaluated_dt = _parse_iso(last_evaluated_at)
    attached_dt = _parse_iso(used_host_last_attached_at)
    if evaluated_dt and attached_dt and evaluated_dt < attached_dt:
        stale = True
        stale_reasons.append("newer_host_evidence_attached")

    configured_at = str(expectation.get("configured_at") or "")
    configured_dt = _parse_iso(configured_at)
    if evaluated_dt and configured_dt and evaluated_dt < configured_dt:
        stale = True
        stale_reasons.append("host_expectation_updated")

    summary.update(
        {
            "status": status,
            "reason": reason,
            "mismatch_summary": "; ".join(mismatches or insufficient[:1]),
            "last_evaluated_at": last_evaluated_at,
            "evaluated_by": str(evaluated_by or ""),
            "used_host_last_attached_at": used_host_last_attached_at,
            "source_family": str(host_summary.get("source_family") or host_summary.get("source") or ""),
            "source_kind": str(host_summary.get("source_kind") or ""),
            "capture_lane": str(host_summary.get("capture_lane") or ""),
            "selection_policy": str(host_summary.get("selection_policy") or ""),
            "selection_reason": str(host_summary.get("selection_reason") or ""),
            "freshness_policy": HOST_VERIFICATION_FRESHNESS_POLICY,
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
            "stale_reasons": stale_reasons,
            "stale": stale,
        }
    )
    return summary
