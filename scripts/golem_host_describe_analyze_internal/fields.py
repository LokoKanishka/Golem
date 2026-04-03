from __future__ import annotations

import re
from typing import cast

from golem_host_describe_analyze_internal.core import fingerprint, normalize_visible_text

STRUCTURED_FIELD_NAMES = {
    "editor": [
        "workspace_or_project",
        "file_or_tab_candidates",
        "error_candidates",
        "active_editor_text_snippets",
        "sidebar_context",
    ],
    "chat": [
        "conversation_title_candidates",
        "visible_message_snippets",
        "input_area_text",
        "sidebar_chat_candidates",
    ],
    "terminal": [
        "prompt_candidates",
        "command_candidates",
        "error_output_candidates",
        "recent_output_snippets",
    ],
    "browser-web-app": [
        "page_title_candidates",
        "header_text",
        "sidebar_navigation_candidates",
        "primary_content_snippets",
        "cta_or_action_text_candidates",
    ],
}

FINE_FIELD_NAMES = {
    "editor": [
        "active_file_candidate",
        "visible_tab_candidates",
        "primary_error_candidate",
        "workspace_or_project_candidate",
        "explorer_context_candidates",
    ],
    "chat": [
        "conversation_title_candidate",
        "visible_message_snippets",
        "input_box_candidate",
        "sidebar_conversation_candidates",
    ],
    "terminal": [
        "active_prompt_candidate",
        "recent_command_candidate",
        "primary_error_output_candidate",
        "recent_output_block_snippets",
    ],
    "browser-web-app": [
        "primary_header_candidate",
        "sidebar_navigation_candidates",
        "primary_cta_candidate",
        "main_content_snippets",
        "page_title_candidate",
    ],
}

CONTEXTUAL_REFINEMENT_NAMES = {
    "editor": [
        "active_tab_candidate",
        "visible_tab_candidates",
        "primary_error_candidate",
        "secondary_error_candidates",
        "active_file_candidate",
        "sidebar_context_candidates",
    ],
    "chat": [
        "active_conversation_candidate",
        "sidebar_conversation_candidates",
        "input_box_candidate",
        "visible_message_snippets",
        "composer_text_candidate",
    ],
    "terminal": [
        "active_prompt_candidate",
        "historical_prompt_candidates",
        "recent_command_candidate",
        "primary_error_output_candidate",
        "recent_output_block_snippets",
    ],
    "browser-web-app": [
        "primary_header_candidate",
        "primary_cta_candidate",
        "secondary_action_candidates",
        "sidebar_navigation_candidates",
        "main_content_snippets",
    ],
}

SURFACE_STATE_BUNDLE_FIELDS = {
    "editor": [
        "active_file",
        "active_tab",
        "visible_tabs",
        "primary_error",
        "workspace_or_project",
        "sidebar_context",
        "main_text_focus",
    ],
    "chat": [
        "active_conversation",
        "visible_messages",
        "composer_text",
        "input_box",
        "sidebar_conversations",
        "main_text_focus",
    ],
    "terminal": [
        "active_prompt",
        "recent_command",
        "primary_error_output",
        "recent_output_block",
        "main_text_focus",
    ],
    "browser-web-app": [
        "primary_header",
        "sidebar_navigation",
        "primary_cta",
        "main_content",
        "page_title",
        "main_text_focus",
    ],
}


def unique_text_values(values: list[str]) -> list[str]:
    results = []
    seen = set()
    for raw in values:
        value = normalize_visible_text(raw)
        if len(value) < 2:
            continue
        key = fingerprint(value)
        if key in seen:
            continue
        seen.add(key)
        results.append(value)
    return results


def surface_confidence_score(surface_confidence: str) -> int:
    return {
        "strong": 3,
        "reasonable": 2,
        "uncertain": 1,
    }.get(surface_confidence, 1)


def structured_field_confidence(
    surface_confidence: str,
    source_refs: list[str],
    avg_confidence: float | int | None = None,
) -> str:
    score = surface_confidence_score(surface_confidence)
    if "window_metadata" in source_refs:
        score += 1
    if isinstance(avg_confidence, (int, float)):
        if avg_confidence >= 80:
            score += 1
        elif avg_confidence < 55:
            score -= 1
    if score >= 4:
        return "high"
    if score >= 2:
        return "medium"
    return "low"


def make_field_candidate(
    value: str,
    surface_confidence: str,
    source_refs: list[str],
    *,
    avg_confidence: float | int | None = None,
    section_role: str = "",
    priority_kind: str = "",
    center_x_ratio: float | int | None = None,
    center_y_ratio: float | int | None = None,
    width_ratio: float | int | None = None,
    note: str = "",
) -> dict[str, object] | None:
    normalized = normalize_visible_text(value)
    if len(normalized) < 2:
        return None
    candidate = {
        "value": normalized,
        "confidence": structured_field_confidence(surface_confidence, source_refs, avg_confidence),
        "source_refs": sorted(set(source_refs)),
        "approximate": True,
    }
    if section_role:
        candidate["section_role"] = section_role
    if priority_kind:
        candidate["priority_kind"] = priority_kind
    if isinstance(center_x_ratio, (int, float)):
        candidate["center_x_ratio"] = round(float(center_x_ratio), 4)
    if isinstance(center_y_ratio, (int, float)):
        candidate["center_y_ratio"] = round(float(center_y_ratio), 4)
    if isinstance(width_ratio, (int, float)):
        candidate["width_ratio"] = round(float(width_ratio), 4)
    if note:
        candidate["note"] = note
    return candidate


def dedupe_field_candidates(items: list[dict[str, object]], limit: int = 5) -> list[dict[str, object]]:
    deduped: list[dict[str, object]] = []
    seen = set()
    for item in items:
        value = normalize_visible_text(str(item.get("value") or ""))
        if len(value) < 2:
            continue
        key = fingerprint(value)
        if key in seen:
            continue
        seen.add(key)
        item["value"] = value
        deduped.append(item)
        if len(deduped) >= limit:
            break
    return deduped


def line_candidate(
    item: dict[str, object],
    surface_confidence: str,
    *,
    note: str = "",
) -> dict[str, object] | None:
    source_refs = list(item.get("sources") or [])
    if "structured_fields_heuristics" not in source_refs:
        source_refs.append("structured_fields_heuristics")
    return make_field_candidate(
        str(item.get("text") or ""),
        surface_confidence,
        source_refs,
        avg_confidence=item.get("avg_confidence"),
        section_role=str(item.get("section_role") or ""),
        priority_kind=str(item.get("priority_kind") or ""),
        center_x_ratio=item.get("center_x_ratio"),
        center_y_ratio=item.get("center_y_ratio"),
        width_ratio=item.get("width_ratio"),
        note=note,
    )


def merged_line_candidate(
    item: dict[str, object],
    surface_confidence: str,
    *,
    note: str = "",
) -> dict[str, object] | None:
    return make_field_candidate(
        str(item.get("text") or ""),
        surface_confidence,
        ["ocr_normalized", "layout_heuristics", "surface_classification_heuristics", "structured_fields_heuristics"],
        avg_confidence=item.get("avg_confidence"),
        section_role=str(item.get("section_role") or ""),
        center_x_ratio=item.get("center_x_ratio"),
        center_y_ratio=item.get("center_y_ratio"),
        width_ratio=item.get("width_ratio"),
        note=note,
    )


def metadata_candidate(
    value: str,
    surface_confidence: str,
    *,
    note: str = "",
) -> dict[str, object] | None:
    return make_field_candidate(
        value,
        surface_confidence,
        ["window_metadata", "structured_fields_heuristics"],
        note=note,
    )


def clone_existing_candidate(
    item: dict[str, object],
    *,
    note: str = "",
) -> dict[str, object] | None:
    source_refs = list(item.get("source_refs") or item.get("sources") or [])
    if "structured_fields_heuristics" not in source_refs:
        source_refs.append("structured_fields_heuristics")
    confidence = str(item.get("confidence") or "low")
    if confidence not in {"high", "medium", "low"}:
        confidence = "low"

    candidate = {
        "value": normalize_visible_text(str(item.get("value") or item.get("text") or "")),
        "confidence": confidence,
        "source_refs": sorted(set(source_refs)),
        "approximate": True,
    }
    if len(candidate["value"]) < 2:
        return None
    if item.get("section_role"):
        candidate["section_role"] = str(item["section_role"])
    if item.get("priority_kind"):
        candidate["priority_kind"] = str(item["priority_kind"])
    if isinstance(item.get("center_x_ratio"), (int, float)):
        candidate["center_x_ratio"] = round(float(item["center_x_ratio"]), 4)
    if isinstance(item.get("center_y_ratio"), (int, float)):
        candidate["center_y_ratio"] = round(float(item["center_y_ratio"]), 4)
    if isinstance(item.get("width_ratio"), (int, float)):
        candidate["width_ratio"] = round(float(item["width_ratio"]), 4)
    if note:
        candidate["note"] = note
    elif item.get("note"):
        candidate["note"] = str(item["note"])
    return candidate


def sort_field_candidates(
    items: list[dict[str, object]],
    *,
    prefer_roles: tuple[str, ...] = (),
    prefer_kinds: tuple[str, ...] = (),
    prefer_recent: bool = False,
    prefer_wider: bool = False,
    prefer_longer: bool = False,
) -> list[dict[str, object]]:
    role_order = {value: idx for idx, value in enumerate(prefer_roles)}
    kind_order = {value: idx for idx, value in enumerate(prefer_kinds)}
    confidence_order = {"high": 0, "medium": 1, "low": 2}

    def sort_key(item: dict[str, object]) -> tuple[object, ...]:
        role = str(item.get("section_role") or "")
        kind = str(item.get("priority_kind") or "")
        confidence = str(item.get("confidence") or "low")
        center_y = float(item.get("center_y_ratio") or 0.0)
        width_ratio = float(item.get("width_ratio") or 0.0)
        value = str(item.get("value") or "")
        return (
            kind_order.get(kind, len(kind_order)),
            role_order.get(role, len(role_order)),
            confidence_order.get(confidence, 3),
            -center_y if prefer_recent else 0.0,
            -width_ratio if prefer_wider else 0.0,
            -len(value) if prefer_longer else 0,
            value,
        )

    return sorted(items, key=sort_key)


def take_ranked_candidates(
    items: list[dict[str, object]],
    *,
    limit: int = 1,
    note: str = "",
    prefer_roles: tuple[str, ...] = (),
    prefer_kinds: tuple[str, ...] = (),
    prefer_recent: bool = False,
    prefer_wider: bool = False,
    prefer_longer: bool = False,
) -> list[dict[str, object]]:
    cloned = []
    for item in items:
        candidate = clone_existing_candidate(item, note=note)
        if candidate:
            cloned.append(candidate)
    ranked = sort_field_candidates(
        cloned,
        prefer_roles=prefer_roles,
        prefer_kinds=prefer_kinds,
        prefer_recent=prefer_recent,
        prefer_wider=prefer_wider,
        prefer_longer=prefer_longer,
    )
    return dedupe_field_candidates(ranked, limit=limit)


def candidate_identity(item: dict[str, object]) -> str:
    return fingerprint(str(item.get("value") or item.get("text") or ""))


def filter_candidates_by_value(
    items: list[dict[str, object]],
    excluded: list[dict[str, object]] | None = None,
) -> list[dict[str, object]]:
    excluded_keys = {candidate_identity(item) for item in (excluded or []) if candidate_identity(item)}
    return [item for item in items if candidate_identity(item) not in excluded_keys]


def filter_candidates_by_pattern(items: list[dict[str, object]], pattern: re.Pattern[str]) -> list[dict[str, object]]:
    return [item for item in items if pattern.search(str(item.get("value") or item.get("text") or ""))]


def contextualize_candidates(
    items: list[dict[str, object]],
    *,
    limit: int = 1,
    role: str = "",
    priority: str = "",
    activity_state: str = "",
    note: str = "",
) -> list[dict[str, object]]:
    results = []
    for item in items:
        candidate = clone_existing_candidate(item, note=note)
        if not candidate:
            continue
        source_refs = list(candidate.get("source_refs") or [])
        if "contextual_refinement_heuristics" not in source_refs:
            source_refs.append("contextual_refinement_heuristics")
        candidate["source_refs"] = sorted(set(source_refs))
        if role:
            candidate["role"] = role
        if priority:
            candidate["priority"] = priority
        if activity_state:
            candidate["activity_state"] = activity_state
        results.append(candidate)
    return dedupe_field_candidates(results, limit=limit)


def bundle_candidate_from_existing(
    item: dict[str, object],
    *,
    bundle_role: str,
    surface_type: str,
    derived_from: list[str],
    note: str = "",
) -> dict[str, object] | None:
    candidate = clone_existing_candidate(item, note=note)
    if not candidate:
        return None
    source_refs = list(candidate.get("source_refs") or [])
    if "surface_state_bundle_heuristics" not in source_refs:
        source_refs.append("surface_state_bundle_heuristics")
    candidate["source_refs"] = sorted(set(source_refs))
    candidate["bundle_role"] = bundle_role
    candidate["surface_type"] = surface_type
    candidate["derived_from"] = derived_from
    return candidate


def bundle_single_field(
    items: list[dict[str, object]],
    *,
    bundle_role: str,
    surface_type: str,
    derived_from: list[str],
    note: str = "",
) -> dict[str, object] | None:
    for item in items:
        candidate = bundle_candidate_from_existing(
            item,
            bundle_role=bundle_role,
            surface_type=surface_type,
            derived_from=derived_from,
            note=note,
        )
        if candidate:
            return candidate
    return None


def bundle_list_field(
    items: list[dict[str, object]],
    *,
    bundle_role: str,
    surface_type: str,
    derived_from: list[str],
    note: str = "",
    limit: int = 4,
) -> list[dict[str, object]]:
    results = []
    for item in items:
        candidate = bundle_candidate_from_existing(
            item,
            bundle_role=bundle_role,
            surface_type=surface_type,
            derived_from=derived_from,
            note=note,
        )
        if candidate:
            results.append(candidate)
    return dedupe_field_candidates(results, limit=limit)


def bundle_focus_field(
    items: list[dict[str, object]],
    *,
    bundle_role: str,
    surface_type: str,
    derived_from: list[str],
    note: str = "",
    limit: int = 3,
) -> dict[str, object] | None:
    candidates = bundle_list_field(
        items,
        bundle_role=bundle_role,
        surface_type=surface_type,
        derived_from=derived_from,
        note=note,
        limit=limit,
    )
    if not candidates:
        return None
    values = [str(item["value"]) for item in candidates[:limit]]
    source_refs = sorted({ref for item in candidates[:limit] for ref in item.get("source_refs") or []} | {"surface_state_bundle_heuristics"})
    confidence_order = {"high": 3, "medium": 2, "low": 1}
    confidence = max(candidates[:limit], key=lambda item: confidence_order.get(str(item.get("confidence")), 0)).get("confidence", "low")
    return {
        "value": " | ".join(values),
        "confidence": confidence,
        "source_refs": source_refs,
        "approximate": True,
        "bundle_role": bundle_role,
        "surface_type": surface_type,
        "derived_from": derived_from,
        "note": note or "condensed bundle field assembled from multiple contextual candidates",
    }


def split_window_title_candidates(title: str, app: str) -> list[str]:
    normalized_title = normalize_visible_text(title)
    if not normalized_title:
        return []
    generic_parts = {
        normalize_visible_text(app).lower(),
        "visual studio code",
        "chatgpt",
        "gnome terminal",
        "terminal",
        "google chrome",
        "chromium",
        "firefox",
        "tk",
    }
    results = []
    if normalized_title.lower() not in generic_parts:
        results.append(normalized_title)
    for separator in (" - ", " | ", " -- "):
        if separator not in normalized_title:
            continue
        for part in normalized_title.split(separator):
            cleaned = normalize_visible_text(part)
            if len(cleaned) < 3 or cleaned.lower() in generic_parts:
                continue
            results.append(cleaned)
    return unique_text_values(results)


def extract_path_tokens(text: str) -> list[str]:
    tokens = re.findall(r"(?:[\w.-]+/)+[\w./-]+|\b[\w.-]+\.[A-Za-z0-9]{1,5}\b", text)
    return unique_text_values(tokens)


def project_candidate_from_path(path: str) -> str:
    cleaned = normalize_visible_text(path).strip("/")
    if not cleaned:
        return ""
    parts = [part for part in cleaned.split("/") if part]
    if parts and "." in parts[-1]:
        parts = parts[:-1]
    if not parts:
        return ""
    if len(parts) >= 2 and parts[0].lower() == "workspace":
        return "/".join(parts[:2])
    if len(parts) >= 2:
        return "/".join(parts[:2])
    return parts[0]


def file_candidate_from_path(path: str) -> str:
    cleaned = normalize_visible_text(path)
    if not cleaned:
        return ""
    if "/" in cleaned:
        return cleaned.rsplit("/", 1)[-1]
    return cleaned


def extract_prompt_prefix(text: str) -> str:
    match = re.match(r"^(.*?[$#])\s*(?:.+)?$", text)
    if match:
        return normalize_visible_text(match.group(1))
    return ""


def extract_shell_command(text: str) -> str:
    match = re.match(r"^.*?[$#]\s*(.+)$", text)
    if match:
        return normalize_visible_text(match.group(1))
    return ""


def lines_for_section(lines: list[dict[str, object]], section_role: str) -> list[dict[str, object]]:
    return [item for item in lines if str(item.get("section_role") or "") == section_role]


def useful_candidates_for_kinds(
    useful_lines: list[dict[str, object]],
    surface_confidence: str,
    kinds: set[str],
    *,
    section_roles: set[str] | None = None,
    limit: int = 4,
    note: str = "",
) -> list[dict[str, object]]:
    results = []
    for item in useful_lines:
        if str(item.get("priority_kind") or "") not in kinds:
            continue
        if section_roles and str(item.get("section_role") or "") not in section_roles:
            continue
        candidate = line_candidate(item, surface_confidence, note=note)
        if candidate:
            results.append(candidate)
    return dedupe_field_candidates(results, limit=limit)


def merged_candidates_for_section(
    lines: list[dict[str, object]],
    surface_confidence: str,
    section_role: str,
    *,
    limit: int = 4,
    note: str = "",
) -> list[dict[str, object]]:
    results = []
    for item in lines_for_section(lines, section_role):
        candidate = merged_line_candidate(item, surface_confidence, note=note)
        if candidate:
            results.append(candidate)
    return dedupe_field_candidates(results, limit=limit)


def build_editor_structured_fields(
    title: str,
    app: str,
    surface_confidence: str,
    merged_lines: list[dict[str, object]],
    useful_lines: list[dict[str, object]],
) -> dict[str, list[dict[str, object]]]:
    fields = {name: [] for name in STRUCTURED_FIELD_NAMES["editor"]}

    for candidate in split_window_title_candidates(title, app):
        metadata_entry = metadata_candidate(candidate, surface_confidence, note="derived from window title metadata")
        if metadata_entry:
            fields["workspace_or_project"].append(dict(metadata_entry))
            fields["file_or_tab_candidates"].append(dict(metadata_entry))

    for item in useful_lines:
        priority_kind = str(item.get("priority_kind") or "")
        section_role = str(item.get("section_role") or "")
        text = str(item.get("text") or "")

        if priority_kind in {"file-reference", "workspace-header"}:
            for path in extract_path_tokens(text):
                project_value = project_candidate_from_path(path)
                if project_value:
                    candidate = make_field_candidate(
                        project_value,
                        surface_confidence,
                        list(item.get("sources") or []) + ["structured_fields_heuristics"],
                        avg_confidence=item.get("avg_confidence"),
                        section_role=section_role,
                        priority_kind=priority_kind,
                        note="derived from visible path or tab text",
                    )
                    if candidate:
                        fields["workspace_or_project"].append(candidate)
                file_value = file_candidate_from_path(path)
                if file_value:
                    candidate = make_field_candidate(
                        file_value,
                        surface_confidence,
                        list(item.get("sources") or []) + ["structured_fields_heuristics"],
                        avg_confidence=item.get("avg_confidence"),
                        section_role=section_role,
                        priority_kind=priority_kind,
                        note="derived from visible file path or tab text",
                    )
                    if candidate:
                        fields["file_or_tab_candidates"].append(candidate)

        if priority_kind == "error-line":
            candidate = line_candidate(item, surface_confidence, note="visible editor error or trace text")
            if candidate:
                fields["error_candidates"].append(candidate)

        if priority_kind in {"code-line", "file-reference", "error-line", "editor-detail"} and section_role == "main_content":
            candidate = line_candidate(item, surface_confidence, note="visible active editor text")
            if candidate:
                fields["active_editor_text_snippets"].append(candidate)

        if priority_kind == "explorer-item" or section_role == "left_sidebar":
            candidate = line_candidate(item, surface_confidence, note="visible explorer or sidebar context")
            if candidate:
                fields["sidebar_context"].append(candidate)

    for item in lines_for_section(merged_lines, "left_sidebar"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible explorer or sidebar context")
        if candidate:
            fields["sidebar_context"].append(candidate)

    for name in fields:
        fields[name] = dedupe_field_candidates(fields[name])
    return fields


def build_chat_structured_fields(
    title: str,
    app: str,
    surface_confidence: str,
    merged_lines: list[dict[str, object]],
    useful_lines: list[dict[str, object]],
) -> dict[str, list[dict[str, object]]]:
    fields = {name: [] for name in STRUCTURED_FIELD_NAMES["chat"]}

    for candidate in split_window_title_candidates(title, app):
        metadata_entry = metadata_candidate(candidate, surface_confidence, note="derived from window title metadata")
        if metadata_entry:
            fields["conversation_title_candidates"].append(metadata_entry)

    for item in lines_for_section(merged_lines, "header"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible chat header text")
        if candidate:
            fields["conversation_title_candidates"].append(candidate)

    fields["visible_message_snippets"] = useful_candidates_for_kinds(
        useful_lines,
        surface_confidence,
        {"visible-message"},
        section_roles={"main_content"},
        note="visible chat message text",
    )

    for item in useful_lines:
        if str(item.get("priority_kind") or "") == "composer" or str(item.get("section_role") or "") == "footer":
            candidate = line_candidate(item, surface_confidence, note="visible input or composer text")
            if candidate:
                fields["input_area_text"].append(candidate)
        if str(item.get("priority_kind") or "") == "conversation-sidebar" or str(item.get("section_role") or "") == "left_sidebar":
            candidate = line_candidate(item, surface_confidence, note="visible chat list or sidebar context")
            if candidate:
                fields["sidebar_chat_candidates"].append(candidate)

    for item in lines_for_section(merged_lines, "footer"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible input or composer text")
        if candidate:
            fields["input_area_text"].append(candidate)
    for item in lines_for_section(merged_lines, "left_sidebar"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible chat list or sidebar context")
        if candidate:
            fields["sidebar_chat_candidates"].append(candidate)

    for name in fields:
        fields[name] = dedupe_field_candidates(fields[name])
    return fields


def build_terminal_structured_fields(
    surface_confidence: str,
    merged_lines: list[dict[str, object]],
    useful_lines: list[dict[str, object]],
) -> dict[str, list[dict[str, object]]]:
    fields = {name: [] for name in STRUCTURED_FIELD_NAMES["terminal"]}

    for item in useful_lines:
        text = str(item.get("text") or "")
        if str(item.get("priority_kind") or "") == "command-or-prompt":
            prompt_value = extract_prompt_prefix(text)
            if prompt_value:
                candidate = make_field_candidate(
                    prompt_value,
                    surface_confidence,
                    list(item.get("sources") or []) + ["structured_fields_heuristics"],
                    avg_confidence=item.get("avg_confidence"),
                    section_role=str(item.get("section_role") or ""),
                    priority_kind=str(item.get("priority_kind") or ""),
                    note="derived from visible terminal prompt text",
                )
                if candidate:
                    fields["prompt_candidates"].append(candidate)
            command_value = extract_shell_command(text)
            if command_value:
                candidate = make_field_candidate(
                    command_value,
                    surface_confidence,
                    list(item.get("sources") or []) + ["structured_fields_heuristics"],
                    avg_confidence=item.get("avg_confidence"),
                    section_role=str(item.get("section_role") or ""),
                    priority_kind=str(item.get("priority_kind") or ""),
                    note="derived from visible terminal command text",
                )
                if candidate:
                    fields["command_candidates"].append(candidate)
        if str(item.get("priority_kind") or "") == "error-output":
            candidate = line_candidate(item, surface_confidence, note="visible terminal error output")
            if candidate:
                fields["error_output_candidates"].append(candidate)
        if str(item.get("priority_kind") or "") in {"visible-output", "error-output"}:
            candidate = line_candidate(item, surface_confidence, note="recent visible terminal output")
            if candidate:
                fields["recent_output_snippets"].append(candidate)

    recent_lines = sorted(
        [item for item in lines_for_section(merged_lines, "main_content") if not extract_shell_command(str(item.get("text") or ""))],
        key=lambda item: float(item.get("center_y_ratio") or 0.0),
        reverse=True,
    )
    for item in recent_lines[:6]:
        candidate = merged_line_candidate(item, surface_confidence, note="recent visible terminal output")
        if candidate:
            fields["recent_output_snippets"].append(candidate)

    for name in fields:
        fields[name] = dedupe_field_candidates(fields[name])
    return fields


def build_browser_structured_fields(
    title: str,
    app: str,
    surface_confidence: str,
    merged_lines: list[dict[str, object]],
    useful_lines: list[dict[str, object]],
) -> dict[str, list[dict[str, object]]]:
    fields = {name: [] for name in STRUCTURED_FIELD_NAMES["browser-web-app"]}

    for candidate in split_window_title_candidates(title, app):
        metadata_entry = metadata_candidate(candidate, surface_confidence, note="derived from browser window title metadata")
        if metadata_entry:
            fields["page_title_candidates"].append(metadata_entry)

    for item in lines_for_section(merged_lines, "header"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible page header text")
        if candidate:
            fields["page_title_candidates"].append(candidate)
            fields["header_text"].append(dict(candidate))

    for item in useful_lines:
        priority_kind = str(item.get("priority_kind") or "")
        section_role = str(item.get("section_role") or "")
        if priority_kind == "navigation" or section_role in {"left_sidebar", "right_sidebar"}:
            candidate = line_candidate(item, surface_confidence, note="visible browser navigation text")
            if candidate:
                fields["sidebar_navigation_candidates"].append(candidate)
        if priority_kind == "page-content" and section_role == "main_content":
            candidate = line_candidate(item, surface_confidence, note="visible primary page content")
            if candidate:
                fields["primary_content_snippets"].append(candidate)
        if priority_kind == "cta-or-control":
            candidate = line_candidate(item, surface_confidence, note="visible page action or CTA text")
            if candidate:
                fields["cta_or_action_text_candidates"].append(candidate)

    cta_pattern = re.compile(r"\bsubmit\b|\bconfirm\b|\bcontinue\b|\bopen\b|\blaunch\b|\bshare\b|\bsign in\b", re.IGNORECASE)
    for item in lines_for_section(merged_lines, "main_content") + lines_for_section(merged_lines, "footer"):
        text = str(item.get("text") or "")
        if cta_pattern.search(text):
            candidate = merged_line_candidate(item, surface_confidence, note="visible page action or CTA text")
            if candidate:
                fields["cta_or_action_text_candidates"].append(candidate)

    for item in lines_for_section(merged_lines, "left_sidebar") + lines_for_section(merged_lines, "right_sidebar"):
        candidate = merged_line_candidate(item, surface_confidence, note="visible browser navigation text")
        if candidate:
            fields["sidebar_navigation_candidates"].append(candidate)

    for name in fields:
        fields[name] = dedupe_field_candidates(fields[name])
    return fields


def build_editor_fine_fields(fields: dict[str, list[dict[str, object]]]) -> dict[str, list[dict[str, object]]]:
    fine_fields = {name: [] for name in FINE_FIELD_NAMES["editor"]}
    fine_fields["active_file_candidate"] = take_ranked_candidates(
        fields.get("file_or_tab_candidates") or [],
        note="best active file or tab candidate derived from editor-visible fields",
        prefer_roles=("header", "main_content"),
        prefer_kinds=("file-reference", "workspace-header"),
    )
    fine_fields["visible_tab_candidates"] = take_ranked_candidates(
        fields.get("file_or_tab_candidates") or [],
        limit=4,
        note="visible editor tabs or file labels derived from ranked field candidates",
        prefer_roles=("header", "main_content"),
        prefer_kinds=("file-reference", "workspace-header"),
    )
    fine_fields["primary_error_candidate"] = take_ranked_candidates(
        fields.get("error_candidates") or [],
        note="dominant visible editor error candidate",
        prefer_roles=("main_content", "bottom_panel"),
        prefer_kinds=("error-line",),
        prefer_recent=True,
    )
    fine_fields["workspace_or_project_candidate"] = take_ranked_candidates(
        fields.get("workspace_or_project") or [],
        note="best workspace or project candidate derived from editor-visible fields",
        prefer_roles=("header", "left_sidebar"),
        prefer_kinds=("workspace-header", "explorer-item", "file-reference"),
    )
    explorer_context_candidates = take_ranked_candidates(
        fields.get("sidebar_context") or [],
        limit=4,
        note="visible explorer or project-tree context",
        prefer_roles=("left_sidebar",),
        prefer_kinds=("explorer-item",),
    )
    if not explorer_context_candidates:
        explorer_context_candidates = take_ranked_candidates(
            (fields.get("workspace_or_project") or []) + (fields.get("file_or_tab_candidates") or []),
            limit=4,
            note="fallback editor project context when explicit explorer/sidebar text is weak",
            prefer_roles=("left_sidebar", "header", "main_content"),
            prefer_kinds=("explorer-item", "workspace-header", "file-reference"),
        )
    fine_fields["explorer_context_candidates"] = explorer_context_candidates
    return fine_fields


def build_chat_fine_fields(fields: dict[str, list[dict[str, object]]]) -> dict[str, list[dict[str, object]]]:
    fine_fields = {name: [] for name in FINE_FIELD_NAMES["chat"]}
    fine_fields["conversation_title_candidate"] = take_ranked_candidates(
        fields.get("conversation_title_candidates") or [],
        note="best conversation or thread title candidate",
        prefer_roles=("header",),
    )
    fine_fields["visible_message_snippets"] = take_ranked_candidates(
        fields.get("visible_message_snippets") or [],
        limit=4,
        note="visible chat message snippets prioritized from the conversation body",
        prefer_roles=("main_content",),
        prefer_kinds=("visible-message",),
    )
    input_box_candidate = take_ranked_candidates(
        fields.get("input_area_text") or [],
        note="best visible input or composer candidate",
        prefer_roles=("footer",),
        prefer_kinds=("composer",),
    )
    if not input_box_candidate:
        fallback_input_candidates = []
        input_pattern = re.compile(r"\bescrib\w*\b|\bmensaje\b|\bmessage\b|\binput\b|\bprompt\b", re.IGNORECASE)
        for item in (fields.get("visible_message_snippets") or []) + (fields.get("sidebar_chat_candidates") or []):
            if input_pattern.search(str(item.get("value") or "")):
                fallback_input_candidates.append(item)
        input_box_candidate = take_ranked_candidates(
            fallback_input_candidates,
            note="fallback input or composer candidate when footer OCR is weak",
            prefer_roles=("footer", "main_content"),
            prefer_recent=True,
        )
    fine_fields["input_box_candidate"] = input_box_candidate
    fine_fields["sidebar_conversation_candidates"] = take_ranked_candidates(
        fields.get("sidebar_chat_candidates") or [],
        limit=4,
        note="visible sidebar conversation or chat-list entries",
        prefer_roles=("left_sidebar",),
        prefer_kinds=("conversation-sidebar",),
    )
    return fine_fields


def build_terminal_fine_fields(fields: dict[str, list[dict[str, object]]]) -> dict[str, list[dict[str, object]]]:
    fine_fields = {name: [] for name in FINE_FIELD_NAMES["terminal"]}
    fine_fields["active_prompt_candidate"] = take_ranked_candidates(
        fields.get("prompt_candidates") or [],
        note="lowest visible terminal prompt candidate on screen",
        prefer_kinds=("command-or-prompt",),
        prefer_recent=True,
    )
    fine_fields["recent_command_candidate"] = take_ranked_candidates(
        fields.get("command_candidates") or [],
        note="most recent visible terminal command candidate",
        prefer_kinds=("command-or-prompt",),
        prefer_recent=True,
    )
    fine_fields["primary_error_output_candidate"] = take_ranked_candidates(
        fields.get("error_output_candidates") or [],
        note="dominant visible terminal error output candidate",
        prefer_kinds=("error-output",),
        prefer_recent=True,
    )
    fine_fields["recent_output_block_snippets"] = take_ranked_candidates(
        fields.get("recent_output_snippets") or [],
        limit=4,
        note="recent terminal output block snippets ranked near the lower visible area",
        prefer_roles=("main_content",),
        prefer_recent=True,
    )
    return fine_fields


def build_browser_fine_fields(fields: dict[str, list[dict[str, object]]]) -> dict[str, list[dict[str, object]]]:
    fine_fields = {name: [] for name in FINE_FIELD_NAMES["browser-web-app"]}
    fine_fields["primary_header_candidate"] = take_ranked_candidates(
        fields.get("header_text") or [],
        note="best primary header candidate from visible browser header text",
        prefer_roles=("header",),
        prefer_kinds=("page-header",),
    )
    fine_fields["sidebar_navigation_candidates"] = take_ranked_candidates(
        fields.get("sidebar_navigation_candidates") or [],
        limit=4,
        note="visible browser navigation entries from sidebars or rails",
        prefer_roles=("left_sidebar", "right_sidebar"),
        prefer_kinds=("navigation",),
    )
    fine_fields["primary_cta_candidate"] = take_ranked_candidates(
        fields.get("cta_or_action_text_candidates") or [],
        note="best visible primary browser CTA or action candidate",
        prefer_roles=("footer", "main_content"),
        prefer_kinds=("cta-or-control",),
    )
    fine_fields["main_content_snippets"] = take_ranked_candidates(
        fields.get("primary_content_snippets") or [],
        limit=4,
        note="primary visible browser content snippets",
        prefer_roles=("main_content",),
        prefer_kinds=("page-content",),
    )
    fine_fields["page_title_candidate"] = take_ranked_candidates(
        fields.get("page_title_candidates") or [],
        note="best page title candidate derived from browser metadata or header text",
        prefer_roles=("header",),
        prefer_kinds=("page-header",),
    )
    return fine_fields


def build_fine_fields(
    category: str,
    fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    fine_fields: dict[str, list[dict[str, object]]] = {name: [] for name in FINE_FIELD_NAMES.get(category, [])}
    if category == "editor":
        fine_fields = build_editor_fine_fields(fields)
    elif category == "chat":
        fine_fields = build_chat_fine_fields(fields)
    elif category == "terminal":
        fine_fields = build_terminal_fine_fields(fields)
    elif category == "browser-web-app":
        fine_fields = build_browser_fine_fields(fields)

    for name in fine_fields:
        fine_fields[name] = dedupe_field_candidates(fine_fields[name], limit=4)
    return fine_fields


def build_editor_contextual_refinements(
    fields: dict[str, list[dict[str, object]]],
    fine_fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    refinements = {name: [] for name in CONTEXTUAL_REFINEMENT_NAMES["editor"]}
    active_file = fine_fields.get("active_file_candidate") or []
    primary_error = fine_fields.get("primary_error_candidate") or []

    active_tab_base = take_ranked_candidates(
        fields.get("file_or_tab_candidates") or [],
        note="best visible tab candidate inferred from editor header/main content ordering",
        prefer_roles=("header", "main_content"),
        prefer_kinds=("workspace-header", "file-reference"),
        prefer_wider=True,
    )
    if not active_tab_base:
        active_tab_base = active_file
    refinements["active_tab_candidate"] = contextualize_candidates(
        active_tab_base,
        role="tab",
        priority="primary",
        activity_state="active",
        note="editor tab most likely active based on header prominence and file cues",
    )
    visible_tabs_base = filter_candidates_by_value(
        fields.get("file_or_tab_candidates") or [],
        refinements["active_tab_candidate"],
    )
    visible_tabs_base = take_ranked_candidates(
        visible_tabs_base,
        limit=4,
        note="other visible editor tabs or file labels besides the likely active tab",
        prefer_roles=("header", "main_content"),
        prefer_kinds=("workspace-header", "file-reference"),
        prefer_wider=True,
    )
    refinements["visible_tab_candidates"] = contextualize_candidates(
        visible_tabs_base,
        limit=4,
        role="tab",
        priority="secondary",
        activity_state="visible",
        note="visible editor tabs that do not appear to be the active one",
    )
    explicit_error_pattern = re.compile(r"\berror:\b|\berror\b|\bfailed\b", re.IGNORECASE)
    primary_error_base = filter_candidates_by_pattern(fields.get("error_candidates") or [], explicit_error_pattern)
    if not primary_error_base:
        primary_error_base = filter_candidates_by_pattern(
            fields.get("error_candidates") or [],
            re.compile(r"\btraceback\b", re.IGNORECASE),
        )
    primary_error_base = take_ranked_candidates(
        primary_error_base or (fields.get("error_candidates") or []),
        note="dominant editor error candidate emphasizing explicit error or traceback text",
        prefer_roles=("main_content", "bottom_panel"),
        prefer_kinds=("error-line",),
        prefer_recent=True,
        prefer_longer=True,
    )
    if not primary_error_base:
        primary_error_base = primary_error
    refinements["primary_error_candidate"] = contextualize_candidates(
        primary_error_base,
        role="error",
        priority="primary",
        activity_state="current",
        note="dominant editor error candidate based on error strength and reading priority",
    )
    secondary_error_base = filter_candidates_by_value(
        fields.get("error_candidates") or [],
        primary_error_base,
    )
    secondary_error_base = take_ranked_candidates(
        secondary_error_base,
        limit=4,
        note="other visible editor errors besides the dominant one",
        prefer_roles=("main_content", "bottom_panel"),
        prefer_kinds=("error-line",),
        prefer_recent=True,
        prefer_longer=True,
    )
    refinements["secondary_error_candidates"] = contextualize_candidates(
        secondary_error_base,
        limit=4,
        role="error",
        priority="secondary",
        activity_state="visible",
        note="secondary editor errors that remain visible but less dominant",
    )
    refinements["active_file_candidate"] = contextualize_candidates(
        active_file,
        role="file",
        priority="primary",
        activity_state="active",
        note="editor file most likely active in the current working area",
    )
    refinements["sidebar_context_candidates"] = contextualize_candidates(
        fine_fields.get("explorer_context_candidates") or [],
        limit=4,
        role="sidebar-context",
        priority="secondary",
        activity_state="visible",
        note="editor sidebar or explorer context that appears visible but not active",
    )
    return refinements


def build_chat_contextual_refinements(
    fine_fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    refinements = {name: [] for name in CONTEXTUAL_REFINEMENT_NAMES["chat"]}
    active_conversation = fine_fields.get("conversation_title_candidate") or []
    refinements["active_conversation_candidate"] = contextualize_candidates(
        active_conversation,
        role="conversation",
        priority="primary",
        activity_state="active",
        note="chat conversation most likely active based on header prominence",
    )
    sidebar_candidates = filter_candidates_by_value(
        fine_fields.get("sidebar_conversation_candidates") or [],
        active_conversation,
    )
    refinements["sidebar_conversation_candidates"] = contextualize_candidates(
        sidebar_candidates,
        limit=4,
        role="conversation",
        priority="secondary",
        activity_state="visible",
        note="sidebar conversations that appear visible but not active",
    )
    refinements["input_box_candidate"] = contextualize_candidates(
        fine_fields.get("input_box_candidate") or [],
        role="input-box",
        priority="primary",
        activity_state="active",
        note="current input box candidate for the visible chat surface",
    )
    refinements["visible_message_snippets"] = contextualize_candidates(
        fine_fields.get("visible_message_snippets") or [],
        limit=4,
        role="message",
        priority="primary",
        activity_state="visible",
        note="currently visible chat messages in the conversation body",
    )
    composer_base = take_ranked_candidates(
        (fine_fields.get("input_box_candidate") or []) + (fine_fields.get("visible_message_snippets") or []),
        note="best visible composer text candidate near the lower chat area",
        prefer_roles=("footer", "main_content"),
        prefer_recent=True,
        prefer_longer=True,
    )
    refinements["composer_text_candidate"] = contextualize_candidates(
        composer_base,
        role="composer",
        priority="primary",
        activity_state="active",
        note="chat composer text most likely current rather than historical interface text",
    )
    return refinements


def build_terminal_contextual_refinements(
    fields: dict[str, list[dict[str, object]]],
    fine_fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    refinements = {name: [] for name in CONTEXTUAL_REFINEMENT_NAMES["terminal"]}
    active_prompt = take_ranked_candidates(
        fields.get("prompt_candidates") or [],
        note="terminal prompt most likely current based on lower on-screen position",
        prefer_recent=True,
        prefer_longer=True,
    )
    if not active_prompt:
        active_prompt = fine_fields.get("active_prompt_candidate") or []
    refinements["active_prompt_candidate"] = contextualize_candidates(
        active_prompt,
        role="prompt",
        priority="primary",
        activity_state="active",
        note="terminal prompt most likely current based on lower on-screen position",
    )
    historical_prompts_base = filter_candidates_by_value(
        fields.get("prompt_candidates") or [],
        active_prompt,
    )
    historical_prompts_base = take_ranked_candidates(
        historical_prompts_base,
        limit=4,
        note="older terminal prompts that remain visible above the active one",
        prefer_recent=False,
        prefer_longer=True,
    )
    refinements["historical_prompt_candidates"] = contextualize_candidates(
        historical_prompts_base,
        limit=4,
        role="prompt",
        priority="secondary",
        activity_state="historical",
        note="terminal prompts that look historical rather than current",
    )
    recent_command_base = take_ranked_candidates(
        fields.get("command_candidates") or [],
        note="terminal command closest to the active lower prompt region",
        prefer_recent=True,
        prefer_longer=True,
    )
    if not recent_command_base:
        recent_command_base = fine_fields.get("recent_command_candidate") or []
    refinements["recent_command_candidate"] = contextualize_candidates(
        recent_command_base,
        role="command",
        priority="primary",
        activity_state="recent",
        note="terminal command most likely associated with the current active prompt",
    )
    explicit_error_pattern = re.compile(r"\berror\b|\btraceback\b|\bfailed\b", re.IGNORECASE)
    primary_error_base = filter_candidates_by_pattern(fields.get("error_output_candidates") or [], explicit_error_pattern)
    primary_error_base = take_ranked_candidates(
        primary_error_base or (fields.get("error_output_candidates") or []),
        note="strongest terminal error candidate emphasizing explicit error or traceback text",
        prefer_recent=True,
        prefer_longer=True,
    )
    if not primary_error_base:
        primary_error_base = fine_fields.get("primary_error_output_candidate") or []
    refinements["primary_error_output_candidate"] = contextualize_candidates(
        primary_error_base,
        role="error-output",
        priority="primary",
        activity_state="recent",
        note="terminal error output that appears dominant relative to surrounding output",
    )
    output_base = filter_candidates_by_value(
        fine_fields.get("recent_output_block_snippets") or [],
        primary_error_base,
    )
    refinements["recent_output_block_snippets"] = contextualize_candidates(
        output_base,
        limit=4,
        role="output-block",
        priority="primary",
        activity_state="recent",
        note="recent terminal output block kept separate from older prompts and dominant errors",
    )
    return refinements


def build_browser_contextual_refinements(
    fields: dict[str, list[dict[str, object]]],
    fine_fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    refinements = {name: [] for name in CONTEXTUAL_REFINEMENT_NAMES["browser-web-app"]}
    refinements["primary_header_candidate"] = contextualize_candidates(
        fine_fields.get("primary_header_candidate") or [],
        role="header",
        priority="primary",
        activity_state="active",
        note="browser header most likely central and primary rather than peripheral chrome",
    )
    primary_cta_base = take_ranked_candidates(
        fields.get("cta_or_action_text_candidates") or [],
        note="best visible primary CTA based on footer/main-content placement and control wording",
        prefer_roles=("footer", "main_content", "header"),
        prefer_kinds=("cta-or-control",),
        prefer_recent=True,
        prefer_wider=True,
        prefer_longer=True,
    )
    if not primary_cta_base:
        primary_cta_base = fine_fields.get("primary_cta_candidate") or []
    refinements["primary_cta_candidate"] = contextualize_candidates(
        primary_cta_base,
        role="action",
        priority="primary",
        activity_state="active",
        note="browser CTA most likely primary rather than secondary action chrome",
    )
    secondary_action_base = filter_candidates_by_value(
        fields.get("cta_or_action_text_candidates") or [],
        refinements["primary_cta_candidate"],
    )
    secondary_action_base = take_ranked_candidates(
        secondary_action_base,
        limit=4,
        note="other visible browser actions besides the dominant CTA",
        prefer_roles=("main_content", "footer", "header"),
        prefer_kinds=("cta-or-control",),
        prefer_recent=True,
        prefer_longer=True,
    )
    refinements["secondary_action_candidates"] = contextualize_candidates(
        secondary_action_base,
        limit=4,
        role="action",
        priority="secondary",
        activity_state="visible",
        note="secondary browser actions that remain visible but less primary than the main CTA",
    )
    refinements["sidebar_navigation_candidates"] = contextualize_candidates(
        fine_fields.get("sidebar_navigation_candidates") or [],
        limit=4,
        role="navigation",
        priority="secondary",
        activity_state="visible",
        note="browser navigation entries that appear lateral rather than central",
    )
    content_base = filter_candidates_by_value(
        fine_fields.get("main_content_snippets") or [],
        refinements["secondary_action_candidates"],
    )
    refinements["main_content_snippets"] = contextualize_candidates(
        content_base,
        limit=4,
        role="content",
        priority="primary",
        activity_state="visible",
        note="browser main content kept distinct from side navigation and secondary controls",
    )
    return refinements


def build_contextual_refinements(
    category: str,
    fields: dict[str, list[dict[str, object]]],
    fine_fields: dict[str, list[dict[str, object]]],
) -> dict[str, list[dict[str, object]]]:
    refinements: dict[str, list[dict[str, object]]] = {
        name: [] for name in CONTEXTUAL_REFINEMENT_NAMES.get(category, [])
    }
    if category == "editor":
        refinements = build_editor_contextual_refinements(fields, fine_fields)
    elif category == "chat":
        refinements = build_chat_contextual_refinements(fine_fields)
    elif category == "terminal":
        refinements = build_terminal_contextual_refinements(fields, fine_fields)
    elif category == "browser-web-app":
        refinements = build_browser_contextual_refinements(fields, fine_fields)

    for name in refinements:
        refinements[name] = dedupe_field_candidates(refinements[name], limit=4)
    return refinements


def build_editor_surface_state_bundle(
    fields: dict[str, list[dict[str, object]]],
    fine_fields: dict[str, list[dict[str, object]]],
    contextual_refinements: dict[str, list[dict[str, object]]],
) -> dict[str, object]:
    surface_type = "editor"
    bundle_fields = {name: None for name in SURFACE_STATE_BUNDLE_FIELDS[surface_type]}
    bundle_fields["active_file"] = bundle_single_field(
        contextual_refinements.get("active_file_candidate") or [],
        bundle_role="active-file",
        surface_type=surface_type,
        derived_from=["fine_fields.active_file_candidate", "contextual_refinements.active_file_candidate"],
        note="consolidated editor active file candidate",
    )
    bundle_fields["active_tab"] = bundle_single_field(
        contextual_refinements.get("active_tab_candidate") or [],
        bundle_role="active-tab",
        surface_type=surface_type,
        derived_from=["contextual_refinements.active_tab_candidate"],
        note="consolidated editor active tab candidate",
    )
    bundle_fields["visible_tabs"] = bundle_list_field(
        contextual_refinements.get("visible_tab_candidates") or [],
        bundle_role="visible-tab",
        surface_type=surface_type,
        derived_from=["fine_fields.visible_tab_candidates", "contextual_refinements.visible_tab_candidates"],
        note="consolidated editor visible tabs besides the active tab",
        limit=4,
    )
    bundle_fields["primary_error"] = bundle_single_field(
        contextual_refinements.get("primary_error_candidate") or [],
        bundle_role="primary-error",
        surface_type=surface_type,
        derived_from=["fine_fields.primary_error_candidate", "contextual_refinements.primary_error_candidate"],
        note="consolidated editor primary error candidate",
    )
    bundle_fields["workspace_or_project"] = bundle_single_field(
        fine_fields.get("workspace_or_project_candidate") or fields.get("workspace_or_project") or [],
        bundle_role="workspace-or-project",
        surface_type=surface_type,
        derived_from=["fields.workspace_or_project", "fine_fields.workspace_or_project_candidate"],
        note="consolidated editor workspace or project context",
    )
    bundle_fields["sidebar_context"] = bundle_list_field(
        contextual_refinements.get("sidebar_context_candidates") or [],
        bundle_role="sidebar-context",
        surface_type=surface_type,
        derived_from=["fine_fields.explorer_context_candidates", "contextual_refinements.sidebar_context_candidates"],
        note="consolidated editor sidebar or explorer context",
        limit=4,
    )
    bundle_fields["main_text_focus"] = bundle_focus_field(
        fields.get("active_editor_text_snippets") or [],
        bundle_role="main-text-focus",
        surface_type=surface_type,
        derived_from=["fields.active_editor_text_snippets"],
        note="condensed editor main text focus built from active editor snippets",
        limit=3,
    )
    return bundle_fields


def build_chat_surface_state_bundle(
    fine_fields: dict[str, list[dict[str, object]]],
    contextual_refinements: dict[str, list[dict[str, object]]],
) -> dict[str, object]:
    surface_type = "chat"
    bundle_fields = {name: None for name in SURFACE_STATE_BUNDLE_FIELDS[surface_type]}
    bundle_fields["active_conversation"] = bundle_single_field(
        contextual_refinements.get("active_conversation_candidate") or [],
        bundle_role="active-conversation",
        surface_type=surface_type,
        derived_from=["fine_fields.conversation_title_candidate", "contextual_refinements.active_conversation_candidate"],
        note="consolidated active chat conversation candidate",
    )
    bundle_fields["visible_messages"] = bundle_list_field(
        contextual_refinements.get("visible_message_snippets") or [],
        bundle_role="visible-message",
        surface_type=surface_type,
        derived_from=["fine_fields.visible_message_snippets", "contextual_refinements.visible_message_snippets"],
        note="consolidated visible chat messages in the conversation body",
        limit=4,
    )
    bundle_fields["composer_text"] = bundle_single_field(
        contextual_refinements.get("composer_text_candidate") or [],
        bundle_role="composer-text",
        surface_type=surface_type,
        derived_from=["contextual_refinements.composer_text_candidate"],
        note="consolidated composer text candidate for the active chat surface",
    )
    bundle_fields["input_box"] = bundle_single_field(
        contextual_refinements.get("input_box_candidate") or [],
        bundle_role="input-box",
        surface_type=surface_type,
        derived_from=["fine_fields.input_box_candidate", "contextual_refinements.input_box_candidate"],
        note="consolidated chat input box candidate",
    )
    bundle_fields["sidebar_conversations"] = bundle_list_field(
        contextual_refinements.get("sidebar_conversation_candidates") or [],
        bundle_role="sidebar-conversation",
        surface_type=surface_type,
        derived_from=["fine_fields.sidebar_conversation_candidates", "contextual_refinements.sidebar_conversation_candidates"],
        note="consolidated chat sidebar conversations distinct from the active thread",
        limit=4,
    )
    bundle_fields["main_text_focus"] = bundle_focus_field(
        contextual_refinements.get("visible_message_snippets") or [],
        bundle_role="main-text-focus",
        surface_type=surface_type,
        derived_from=["fine_fields.visible_message_snippets", "contextual_refinements.visible_message_snippets"],
        note="condensed chat main text focus built from visible messages",
        limit=3,
    )
    return bundle_fields


def build_terminal_surface_state_bundle(
    contextual_refinements: dict[str, list[dict[str, object]]],
) -> dict[str, object]:
    surface_type = "terminal"
    bundle_fields = {name: None for name in SURFACE_STATE_BUNDLE_FIELDS[surface_type]}
    bundle_fields["active_prompt"] = bundle_single_field(
        contextual_refinements.get("active_prompt_candidate") or [],
        bundle_role="active-prompt",
        surface_type=surface_type,
        derived_from=["fine_fields.active_prompt_candidate", "contextual_refinements.active_prompt_candidate"],
        note="consolidated active terminal prompt candidate",
    )
    bundle_fields["recent_command"] = bundle_single_field(
        contextual_refinements.get("recent_command_candidate") or [],
        bundle_role="recent-command",
        surface_type=surface_type,
        derived_from=["fine_fields.recent_command_candidate", "contextual_refinements.recent_command_candidate"],
        note="consolidated recent terminal command candidate",
    )
    bundle_fields["primary_error_output"] = bundle_single_field(
        contextual_refinements.get("primary_error_output_candidate") or [],
        bundle_role="primary-error-output",
        surface_type=surface_type,
        derived_from=["fine_fields.primary_error_output_candidate", "contextual_refinements.primary_error_output_candidate"],
        note="consolidated primary terminal error output candidate",
    )
    bundle_fields["recent_output_block"] = bundle_focus_field(
        contextual_refinements.get("recent_output_block_snippets") or [],
        bundle_role="recent-output-block",
        surface_type=surface_type,
        derived_from=["fine_fields.recent_output_block_snippets", "contextual_refinements.recent_output_block_snippets"],
        note="condensed terminal recent output block built from contextual snippets",
        limit=3,
    )
    main_focus_candidates = (
        contextual_refinements.get("recent_command_candidate") or []
    ) + (
        contextual_refinements.get("recent_output_block_snippets") or []
    ) + (
        contextual_refinements.get("primary_error_output_candidate") or []
    )
    bundle_fields["main_text_focus"] = bundle_focus_field(
        main_focus_candidates,
        bundle_role="main-text-focus",
        surface_type=surface_type,
        derived_from=[
            "contextual_refinements.recent_command_candidate",
            "contextual_refinements.recent_output_block_snippets",
            "contextual_refinements.primary_error_output_candidate",
        ],
        note="condensed terminal main text focus built from command, output, and dominant error",
        limit=3,
    )
    return bundle_fields


def build_browser_surface_state_bundle(
    fine_fields: dict[str, list[dict[str, object]]],
    contextual_refinements: dict[str, list[dict[str, object]]],
) -> dict[str, object]:
    surface_type = "browser-web-app"
    bundle_fields = {name: None for name in SURFACE_STATE_BUNDLE_FIELDS[surface_type]}
    bundle_fields["primary_header"] = bundle_single_field(
        contextual_refinements.get("primary_header_candidate") or [],
        bundle_role="primary-header",
        surface_type=surface_type,
        derived_from=["fine_fields.primary_header_candidate", "contextual_refinements.primary_header_candidate"],
        note="consolidated browser primary header candidate",
    )
    bundle_fields["sidebar_navigation"] = bundle_list_field(
        contextual_refinements.get("sidebar_navigation_candidates") or [],
        bundle_role="sidebar-navigation",
        surface_type=surface_type,
        derived_from=["fine_fields.sidebar_navigation_candidates", "contextual_refinements.sidebar_navigation_candidates"],
        note="consolidated browser sidebar navigation candidates",
        limit=4,
    )
    bundle_fields["primary_cta"] = bundle_single_field(
        contextual_refinements.get("primary_cta_candidate") or [],
        bundle_role="primary-cta",
        surface_type=surface_type,
        derived_from=["fine_fields.primary_cta_candidate", "contextual_refinements.primary_cta_candidate"],
        note="consolidated browser primary CTA candidate",
    )
    bundle_fields["main_content"] = bundle_focus_field(
        contextual_refinements.get("main_content_snippets") or [],
        bundle_role="main-content",
        surface_type=surface_type,
        derived_from=["fine_fields.main_content_snippets", "contextual_refinements.main_content_snippets"],
        note="condensed browser main content built from contextual content snippets",
        limit=3,
    )
    bundle_fields["page_title"] = bundle_single_field(
        fine_fields.get("page_title_candidate") or [],
        bundle_role="page-title",
        surface_type=surface_type,
        derived_from=["fields.page_title_candidates", "fine_fields.page_title_candidate"],
        note="consolidated browser page title candidate",
    )
    bundle_fields["main_text_focus"] = bundle_focus_field(
        contextual_refinements.get("main_content_snippets") or [],
        bundle_role="main-text-focus",
        surface_type=surface_type,
        derived_from=["fine_fields.main_content_snippets", "contextual_refinements.main_content_snippets"],
        note="condensed browser main text focus built from contextual main content",
        limit=3,
    )
    return bundle_fields


def build_surface_state_bundle(
    category: str,
    label: str,
    surface_confidence: str,
    structured_fields: dict[str, object],
) -> dict[str, object]:
    attempted_fields = SURFACE_STATE_BUNDLE_FIELDS.get(category, [])
    bundle_fields: dict[str, object] = {name: None for name in attempted_fields}
    fields = cast(dict[str, list[dict[str, object]]], structured_fields.get("fields") or {})
    fine_fields = cast(dict[str, list[dict[str, object]]], structured_fields.get("fine_fields") or {})
    contextual_refinements = cast(dict[str, list[dict[str, object]]], structured_fields.get("contextual_refinements") or {})

    if category == "editor":
        bundle_fields = build_editor_surface_state_bundle(fields, fine_fields, contextual_refinements)
    elif category == "chat":
        bundle_fields = build_chat_surface_state_bundle(fine_fields, contextual_refinements)
    elif category == "terminal":
        bundle_fields = build_terminal_surface_state_bundle(contextual_refinements)
    elif category == "browser-web-app":
        bundle_fields = build_browser_surface_state_bundle(fine_fields, contextual_refinements)

    empty_fields = []
    non_empty_fields = []
    for field_name in attempted_fields:
        value = bundle_fields.get(field_name)
        if value:
            non_empty_fields.append(field_name)
        else:
            empty_fields.append(field_name)

    source_refs = {"surface_state_bundle_heuristics"}
    if attempted_fields:
        source_refs.update(
            {
                "structured_fields_heuristics",
                "contextual_refinement_heuristics",
                "surface_classification_heuristics",
                "ocr_normalized",
                "layout_heuristics",
            }
        )

    result = {
        "surface_type": category,
        "label": label,
        "surface_confidence": surface_confidence,
        "attempted_fields": attempted_fields,
        "fields": bundle_fields,
        "empty_fields": empty_fields,
        "non_empty_fields": non_empty_fields,
        "source_refs": sorted(source_refs),
        "approximate": True,
    }
    try:
        return _normalize_surface_state_bundle(result)
    except Exception:
        # normalization is best-effort; on failure return original bundle to avoid breaking pipeline
        return result


def _normalize_surface_state_bundle(bundle: dict[str, object]) -> dict[str, object]:
    """Apply lightweight, deterministic normalization to a surface_state_bundle.

    - Normalize visible text in field candidates
    - Sort list-valued fields by fingerprint to provide deterministic ordering
    - Ensure source refs are sorted
    This is intentionally conservative and keeps all evidence and confidence intact.
    """
    from functools import cmp_to_key

    fields = bundle.get("fields") or {}
    for name, value in list(fields.items()):
        # normalize single candidate dicts
        if isinstance(value, dict):
            v = value.get("value")
            if isinstance(v, str):
                fields[name]["value"] = normalize_visible_text(v)
            # keep source_refs sorted if present
            if isinstance(value.get("source_refs"), list):
                value["source_refs"] = sorted(value["source_refs"])
        # normalize lists of candidates
        elif isinstance(value, list):
            cleaned: list[dict[str, object]] = []
            for item in value:
                if not isinstance(item, dict):
                    continue
                if "value" in item and isinstance(item.get("value"), str):
                    item["value"] = normalize_visible_text(item["value"])
                if isinstance(item.get("source_refs"), list):
                    item["source_refs"] = sorted(item["source_refs"])
                cleaned.append(item)

            # sort deterministically by fingerprint of the value, fallback to text repr
            def _cmp(a: dict[str, object], b: dict[str, object]) -> int:
                ka = fingerprint(str(a.get("value") or ""))
                kb = fingerprint(str(b.get("value") or ""))
                if ka < kb:
                    return -1
                if ka > kb:
                    return 1
                return 0

            cleaned.sort(key=cmp_to_key(_cmp))

            # dedupe by fingerprint while preserving order for stability
            seen = set()
            deduped: list[dict[str, object]] = []
            for item in cleaned:
                key = fingerprint(str(item.get("value") or ""))
                if key in seen:
                    continue
                seen.add(key)
                deduped.append(item)
            fields[name] = deduped

    # post-process single candidate dicts for conservative canonicalization
    for name, value in list(fields.items()):
        if isinstance(value, dict):
            v = value.get("value")
            if isinstance(v, str):
                # if candidate was condensed (e.g., "a | b | c"), pick the most informative part
                if " | " in v:
                    parts = [normalize_visible_text(p).strip() for p in v.split(" | ")]
                    parts = [p for p in parts if p]
                    if parts:
                        parts.sort(key=lambda s: (-len(s), fingerprint(s)))
                        value["value"] = parts[0]
                        value["note"] = (value.get("note") or "") + " | canonicalized from condensed candidate"
                # truncate overly long values to avoid noisy diffs
                if isinstance(value.get("value"), str) and len(value["value"]) > 400:
                    value["value"] = value["value"][:400]
                    value["note"] = (value.get("note") or "") + " | truncated for stability"

    # ensure top-level source_refs sorted
    if isinstance(bundle.get("source_refs"), list):
        bundle["source_refs"] = sorted(bundle["source_refs"])

    # ensure attempted/empty/non_empty fields are lists in stable order
    for key in ("attempted_fields", "empty_fields", "non_empty_fields"):
        if isinstance(bundle.get(key), list):
            bundle[key] = list(bundle[key])

    bundle["fields"] = fields
    return bundle


def build_structured_fields(
    category: str,
    label: str,
    surface_confidence: str,
    title: str,
    app: str,
    merged_lines: list[dict[str, object]],
    useful_lines: list[dict[str, object]],
    useful_regions: list[dict[str, object]],
) -> dict[str, object]:
    attempted_fields = STRUCTURED_FIELD_NAMES.get(category, [])
    attempted_fine_fields = FINE_FIELD_NAMES.get(category, [])
    attempted_contextual_refinements = CONTEXTUAL_REFINEMENT_NAMES.get(category, [])
    fields: dict[str, list[dict[str, object]]] = {name: [] for name in attempted_fields}
    fine_fields: dict[str, list[dict[str, object]]] = {name: [] for name in attempted_fine_fields}
    contextual_refinements: dict[str, list[dict[str, object]]] = {
        name: [] for name in attempted_contextual_refinements
    }

    if category == "editor":
        fields = build_editor_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)
    elif category == "chat":
        fields = build_chat_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)
    elif category == "terminal":
        fields = build_terminal_structured_fields(surface_confidence, merged_lines, useful_lines)
    elif category == "browser-web-app":
        fields = build_browser_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)

    empty_fields = [name for name in attempted_fields if not fields.get(name)]
    fine_fields = build_fine_fields(category, fields)
    empty_fine_fields = [name for name in attempted_fine_fields if not fine_fields.get(name)]
    contextual_refinements = build_contextual_refinements(category, fields, fine_fields)
    empty_contextual_refinements = [
        name for name in attempted_contextual_refinements if not contextual_refinements.get(name)
    ]
    source_refs = {"structured_fields_heuristics", "surface_classification_heuristics"}
    if attempted_fields or attempted_fine_fields or attempted_contextual_refinements:
        source_refs.update({"ocr_normalized", "layout_heuristics"})
    if title:
        source_refs.add("window_metadata")
    if attempted_contextual_refinements:
        source_refs.add("contextual_refinement_heuristics")

    return {
        "category": category,
        "label": label,
        "surface_confidence": surface_confidence,
        "attempted_fields": attempted_fields,
        "fields": fields,
        "empty_fields": empty_fields,
        "non_empty_fields": [name for name in attempted_fields if fields.get(name)],
        "attempted_fine_fields": attempted_fine_fields,
        "fine_fields": fine_fields,
        "empty_fine_fields": empty_fine_fields,
        "non_empty_fine_fields": [name for name in attempted_fine_fields if fine_fields.get(name)],
        "attempted_contextual_refinements": attempted_contextual_refinements,
        "contextual_refinements": contextual_refinements,
        "empty_contextual_refinements": empty_contextual_refinements,
        "non_empty_contextual_refinements": [
            name for name in attempted_contextual_refinements if contextual_refinements.get(name)
        ],
        "useful_region_roles": [str(item.get("role") or "") for item in useful_regions],
        "source_refs": sorted(source_refs),
        "approximate": True,
    }

