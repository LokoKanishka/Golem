#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import pathlib
import re
import statistics
import sys
import unicodedata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze audited host semantic description artifacts.")
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--summary-path", required=True)
    parser.add_argument("--manifest-path", required=True)
    parser.add_argument("--description-path", required=True)
    parser.add_argument("--sources-path", required=True)
    parser.add_argument("--selection-path", required=True)
    parser.add_argument("--windows-json-path", required=True)
    parser.add_argument("--desktops-path", required=True)
    parser.add_argument("--root-props-path", required=True)
    parser.add_argument("--target-props-path", required=True)
    parser.add_argument("--target-process-path", required=True)
    parser.add_argument("--target-screenshot", required=True)
    parser.add_argument("--size-path", required=True)
    parser.add_argument("--ocr-text", required=True)
    parser.add_argument("--ocr-tsv", required=True)
    parser.add_argument("--ocr-enhanced-image", required=True)
    parser.add_argument("--ocr-enhanced-text", required=True)
    parser.add_argument("--ocr-enhanced-tsv", required=True)
    parser.add_argument("--ocr-normalized-text", required=True)
    parser.add_argument("--layout-path", required=True)
    parser.add_argument("--source-perceive-manifest", required=True)
    parser.add_argument("--source-windows", required=True)
    parser.add_argument("--source-active-props", required=True)
    parser.add_argument("--supporting-active-png", required=True)
    return parser.parse_args()


def read_text(path: pathlib.Path) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8", errors="replace")
    return ""


def parse_dimensions(size_text: str) -> tuple[int, int]:
    match = re.match(r"^\s*(\d+)x(\d+)\s*$", size_text)
    if not match:
        return (0, 0)
    return (int(match.group(1)), int(match.group(2)))


def parse_desktops(text: str) -> tuple[int | None, list[dict[str, object]]]:
    entries: list[dict[str, object]] = []
    current = None
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line:
            continue
        match = re.match(r"^(\d+)\s+([*-])\s+", line)
        if not match:
            continue
        desktop_id = int(match.group(1))
        is_current = match.group(2) == "*"
        entries.append({"desktop": desktop_id, "is_current": is_current, "raw": line})
        if is_current:
            current = desktop_id
    return current, entries


def parse_xprop(text: str) -> dict[str, object]:
    data: dict[str, object] = {"wm_class": [], "wm_name": "", "pid": ""}
    for line in text.splitlines():
        if line.startswith("WM_CLASS"):
            data["wm_class"] = re.findall(r'"([^"]+)"', line)
        elif line.startswith("WM_NAME"):
            matches = re.findall(r'"([^"]+)"', line)
            if matches:
                data["wm_name"] = matches[-1]
        elif "_NET_WM_PID" in line:
            match = re.search(r"=\s*(\d+)", line)
            if match:
                data["pid"] = match.group(1)
    return data


def parse_process(text: str) -> dict[str, str]:
    line = text.strip()
    if not line or line == "pid unavailable" or line.lower().startswith("error:"):
        return {"pid": "", "comm": "", "args": ""}
    parts = line.split(None, 2)
    return {
        "pid": parts[0] if len(parts) > 0 else "",
        "comm": parts[1] if len(parts) > 1 else "",
        "args": parts[2] if len(parts) > 2 else "",
    }


def app_name(props: dict[str, object], process: dict[str, str], title: str) -> str:
    tokens = " ".join(
        list(props.get("wm_class", [])) + [process.get("comm", ""), process.get("args", ""), title or ""]
    ).lower()
    mapping = [
        ("chatgpt", "ChatGPT"),
        ("notebooklm", "NotebookLM"),
        ("code", "Visual Studio Code"),
        ("visual studio code", "Visual Studio Code"),
        ("google-chrome", "Google Chrome"),
        ("chromium", "Chromium"),
        ("firefox", "Firefox"),
        ("xmessage", "XMessage"),
        ("zenity", "Zenity"),
        ("gnome-terminal", "GNOME Terminal"),
        ("xterm", "XTerm"),
        ("kitty", "Kitty"),
        ("alacritty", "Alacritty"),
        ("tilix", "Tilix"),
        ("konsole", "Konsole"),
    ]
    for needle, label in mapping:
        if needle in tokens:
            return label
    wm_class = props.get("wm_class", [])
    if isinstance(wm_class, list):
        for value in reversed(wm_class):
            if value:
                return value
    if process.get("comm"):
        return process["comm"]
    if title:
        return title
    return "unknown-app"


def surface_kind(app: str, title: str, ocr_text: str) -> str:
    haystack = " ".join([app, title, ocr_text]).lower()
    if "chatgpt" in haystack or "notebooklm" in haystack:
        return "chat-assistant"
    if "visual studio code" in haystack or "code" in haystack:
        return "editor"
    if any(term in haystack for term in ["terminal", "xterm", "bash", "zsh", "fish", "kitty", "alacritty", "konsole", "tilix"]):
        return "terminal"
    if any(term in haystack for term in ["xmessage", "zenity", "dialog"]):
        return "dialog"
    if any(term in haystack for term in ["chrome", "chromium", "firefox", "browser"]):
        return "browser"
    return "generic-window"


def normalize_visible_text(text: str) -> str:
    if not text:
        return ""
    text = unicodedata.normalize("NFKC", text)
    replacements = {
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2013": "-",
        "\u2014": "-",
        "\u2022": "-",
        "\ufb01": "fi",
        "\ufb02": "fl",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s+([,.;:!?])", r"\1", text)
    text = re.sub(r"([(\[{])\s+", r"\1", text)
    text = re.sub(r"\s+([)\]}])", r"\1", text)
    text = re.sub(r"^[^0-9A-Za-z]+(?=[0-9A-Za-z])", "", text)
    text = re.sub(r"(?<=[0-9A-Za-z])[|¦]{2,}$", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def fingerprint(text: str) -> str:
    normalized = normalize_visible_text(text).lower()
    compact = re.sub(r"[^a-z0-9]+", "", normalized)
    return compact or normalized


def parse_ocr_confidence(path: pathlib.Path) -> dict[str, float | int | None]:
    if not path.exists():
        return {"words": 0, "avg_conf": None}
    words: list[float] = []
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            text = normalize_visible_text((row.get("text") or "").strip())
            if not text:
                continue
            try:
                conf = float(row.get("conf") or "-1")
            except ValueError:
                continue
            if conf >= 0:
                words.append(conf)
    return {
        "words": len(words),
        "avg_conf": round(statistics.mean(words), 1) if words else None,
    }


def parse_tsv_lines(path: pathlib.Path, variant: str, width: int, height: int) -> list[dict[str, object]]:
    if not path.exists():
        return []
    groups: dict[tuple[int, int, int, int], dict[str, object]] = {}
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            text = normalize_visible_text(row.get("text") or "")
            if not text:
                continue
            try:
                conf = float(row.get("conf") or "-1")
            except ValueError:
                conf = -1
            try:
                key = (
                    int(row.get("page_num") or 0),
                    int(row.get("block_num") or 0),
                    int(row.get("par_num") or 0),
                    int(row.get("line_num") or 0),
                )
                left = int(row.get("left") or 0)
                top = int(row.get("top") or 0)
                item_width = int(row.get("width") or 0)
                item_height = int(row.get("height") or 0)
            except ValueError:
                continue
            group = groups.setdefault(
                key,
                {
                    "variant": variant,
                    "words": [],
                    "left": left,
                    "top": top,
                    "right": left + item_width,
                    "bottom": top + item_height,
                    "confidences": [],
                },
            )
            group["words"].append((left, text))
            group["left"] = min(int(group["left"]), left)
            group["top"] = min(int(group["top"]), top)
            group["right"] = max(int(group["right"]), left + item_width)
            group["bottom"] = max(int(group["bottom"]), top + item_height)
            if conf >= 0:
                group["confidences"].append(conf)

    lines: list[dict[str, object]] = []
    for group in groups.values():
        words = [item[1] for item in sorted(group["words"], key=lambda item: item[0])]
        text = normalize_visible_text(" ".join(words))
        if len(text) < 2:
            continue
        avg_conf = None
        if group["confidences"]:
            avg_conf = round(statistics.mean(group["confidences"]), 1)
        left = int(group["left"])
        top = int(group["top"])
        right = int(group["right"])
        bottom = int(group["bottom"])
        line_width = max(right - left, 1)
        line_height = max(bottom - top, 1)
        lines.append(
            {
                "variant": variant,
                "text": text,
                "left": left,
                "top": top,
                "width": line_width,
                "height": line_height,
                "center_x_ratio": round((left + line_width / 2) / width, 4) if width else 0.0,
                "center_y_ratio": round((top + line_height / 2) / height, 4) if height else 0.0,
                "width_ratio": round(line_width / width, 4) if width else 0.0,
                "height_ratio": round(line_height / height, 4) if height else 0.0,
                "avg_confidence": avg_conf,
            }
        )
    return sorted(lines, key=lambda item: (item["top"], item["left"]))


def fallback_lines_from_text(text: str, variant: str) -> list[dict[str, object]]:
    results = []
    for idx, raw_line in enumerate(text.replace("\f", "\n").splitlines(), start=1):
        line = normalize_visible_text(raw_line)
        if len(line) < 3:
            continue
        results.append(
            {
                "variant": variant,
                "text": line,
                "left": 0,
                "top": idx * 10,
                "width": 0,
                "height": 0,
                "center_x_ratio": 0.5,
                "center_y_ratio": round(min(idx * 0.02, 0.99), 4),
                "width_ratio": 0.0,
                "height_ratio": 0.0,
                "avg_confidence": None,
            }
        )
    return results


def merge_lines(raw_lines: list[dict[str, object]], enhanced_lines: list[dict[str, object]]) -> list[dict[str, object]]:
    selected: dict[str, dict[str, object]] = {}
    for candidate in raw_lines + enhanced_lines:
        key = fingerprint(str(candidate["text"]))
        if len(key) < 4:
            continue
        conf = candidate.get("avg_confidence")
        score = (conf if isinstance(conf, (int, float)) else 0.0) * 2
        score += len(str(candidate["text"]))
        if candidate.get("variant") == "enhanced":
            score += 8
        existing = selected.get(key)
        if existing is None or score > float(existing["_score"]):
            candidate_copy = dict(candidate)
            candidate_copy["_score"] = round(score, 2)
            selected[key] = candidate_copy
    merged = sorted(selected.values(), key=lambda item: (item["top"], item["left"]))
    for item in merged:
        item.pop("_score", None)
    return merged


def classify_section(line: dict[str, object], surface: str) -> str:
    text = str(line["text"]).lower()
    x_ratio = float(line.get("center_x_ratio") or 0)
    y_ratio = float(line.get("center_y_ratio") or 0)
    width_ratio = float(line.get("width_ratio") or 0)
    if y_ratio < 0.14:
        return "header"
    if y_ratio > 0.86:
        return "footer"
    if x_ratio < 0.24 or any(marker in text for marker in ["nuevo chat", "biblioteca", "explorer", "sidebar", "fuentes", "chats"]):
        return "left_sidebar"
    if x_ratio > 0.78:
        return "right_sidebar"
    if surface in {"chat-assistant", "editor", "browser"} and y_ratio > 0.72 and width_ratio > 0.35:
        return "bottom_panel"
    return "main_content"


def section_label(role: str, surface: str) -> str:
    mapping = {
        "header": "header bar",
        "left_sidebar": "left sidebar/navigation",
        "right_sidebar": "right-side panel",
        "main_content": "main content area",
        "bottom_panel": "bottom panel",
        "footer": "footer/input area",
    }
    if surface == "editor" and role == "left_sidebar":
        return "explorer/sidebar"
    if surface == "chat-assistant" and role == "main_content":
        return "conversation/body area"
    if surface == "chat-assistant" and role == "footer":
        return "composer/footer area"
    return mapping.get(role, role.replace("_", " "))


def build_layout(lines: list[dict[str, object]], surface: str) -> dict[str, object]:
    sections: dict[str, list[dict[str, object]]] = {}
    for line in lines:
        role = classify_section(line, surface)
        line["section_role"] = role
        sections.setdefault(role, []).append(line)
    ordered_roles = ["header", "left_sidebar", "right_sidebar", "main_content", "bottom_panel", "footer"]
    summary_sections: list[dict[str, object]] = []
    for role in ordered_roles:
        items = sections.get(role, [])
        if not items:
            continue
        confidences = [item["avg_confidence"] for item in items if isinstance(item.get("avg_confidence"), (int, float))]
        summary_sections.append(
            {
                "role": role,
                "label": section_label(role, surface),
                "line_count": len(items),
                "approximate": True,
                "average_confidence": round(statistics.mean(confidences), 1) if confidences else None,
                "sample_text": [str(item["text"]) for item in items[:3]],
            }
        )
    labels = [section["label"] for section in summary_sections]
    if not labels:
        summary = "Layout heuristics could not isolate stable sections from the OCR evidence."
    elif len(labels) == 1:
        summary = f"Layout heuristics suggest a single dominant {labels[0]}."
    else:
        summary = f"Layout heuristics suggest {', '.join(labels[:-1])}, and {labels[-1]}."
    return {
        "summary": summary,
        "approximate": True,
        "sections": summary_sections,
    }


def summarize_windows(items: list[dict[str, object]]) -> list[dict[str, object]]:
    summarized = []
    for item in items[:5]:
        title = item.get("title") or "(untitled)"
        summarized.append(
            {
                "window_id": item.get("window_id"),
                "desktop": item.get("desktop"),
                "title": title,
                "pid": item.get("pid"),
            }
        )
    return summarized


def select_excerpt_lines(lines: list[dict[str, object]], preferred_sections: list[str]) -> list[str]:
    priorities = {role: index for index, role in enumerate(preferred_sections)}
    ranked = sorted(
        lines,
        key=lambda item: (
            priorities.get(str(item.get("section_role")), len(preferred_sections)),
            -(item.get("avg_confidence") or 0),
            -len(str(item["text"])),
        ),
    )
    excerpts = []
    seen = set()
    for item in ranked:
        text = str(item["text"])
        key = fingerprint(text)
        if key in seen or len(text) < 4:
            continue
        seen.add(key)
        excerpts.append(text)
        if len(excerpts) >= 8:
            break
    return excerpts


def describe_visible_content(target_kind: str, surface: str, app: str, title: str, layout: dict[str, object], excerpts: list[str]) -> str:
    if not excerpts:
        if target_kind == "desktop":
            return "The desktop screenshot is real, but even after OCR cleanup there is not enough stable readable text to describe the visible content beyond metadata."
        return "The target screenshot is real, but even after OCR cleanup there is not enough stable readable text to describe the visible content confidently."

    snippets = ", ".join(f'"{line}"' for line in excerpts[:3])
    layout_summary = str(layout.get("summary") or "")
    if surface == "chat-assistant":
        return f'The visible content is consistent with a chat workspace. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'
    if surface == "editor":
        return f'The visible content is consistent with an editor or review workspace. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'
    if surface == "browser":
        return f'The visible content is consistent with a browser page or web application. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'
    if surface == "terminal":
        return f'The visible content is consistent with a terminal session. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'
    if surface == "dialog":
        return f'The visible content is consistent with a dialog or message surface. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'
    return f'The visible content is text-heavy and its layout can be partially structured. {layout_summary} Normalized OCR recovered snippets such as {snippets}.'


def consistency_claim(surface: str, app: str, excerpts: list[str]) -> str:
    joined = " ".join(excerpts).lower()
    if surface == "chat-assistant":
        if any(marker in joined for marker in ["nuevo chat", "biblioteca", "pregunta", "chat"]):
            return "Window metadata and readable text are mutually consistent with a chat-style workspace, so the semantic label is supported by both metadata and visible evidence."
        return "Window metadata suggests a chat workspace, but the visible text only partially confirms that reading."
    if surface == "editor":
        if any(marker in joined for marker in ["explorer", "review", "workspace", "editor"]):
            return "Window metadata and readable text are mutually consistent with an editor/review workspace rather than a generic browser tab."
        return "Window metadata suggests an editor workspace, but the visible text only partially confirms that reading."
    if surface == "browser":
        return "Window metadata identifies a browser-class surface; the visible text supports that but does not by itself identify hidden tabs or page state beyond the captured frame."
    return f'Window metadata identifies the surface as {app}; the visible text is directionally consistent but still approximate.'


def main() -> int:
    args = parse_args()
    run_dir = pathlib.Path(args.run_dir)
    summary_path = pathlib.Path(args.summary_path)
    manifest_path = pathlib.Path(args.manifest_path)
    description_path = pathlib.Path(args.description_path)
    sources_path = pathlib.Path(args.sources_path)
    selection_path = pathlib.Path(args.selection_path)
    windows_json_path = pathlib.Path(args.windows_json_path)
    desktops_path = pathlib.Path(args.desktops_path)
    root_props_path = pathlib.Path(args.root_props_path)
    target_props_path = pathlib.Path(args.target_props_path)
    target_process_path = pathlib.Path(args.target_process_path)
    target_screenshot = pathlib.Path(args.target_screenshot)
    size_path = pathlib.Path(args.size_path)
    ocr_text_path = pathlib.Path(args.ocr_text)
    ocr_tsv_path = pathlib.Path(args.ocr_tsv)
    ocr_enhanced_image = pathlib.Path(args.ocr_enhanced_image)
    ocr_enhanced_text_path = pathlib.Path(args.ocr_enhanced_text)
    ocr_enhanced_tsv_path = pathlib.Path(args.ocr_enhanced_tsv)
    ocr_normalized_text_path = pathlib.Path(args.ocr_normalized_text)
    layout_path = pathlib.Path(args.layout_path)
    source_perceive_manifest = pathlib.Path(args.source_perceive_manifest)
    source_windows = pathlib.Path(args.source_windows)
    source_active_props = pathlib.Path(args.source_active_props)
    supporting_active_png = pathlib.Path(args.supporting_active_png)

    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    windows_payload = json.loads(windows_json_path.read_text(encoding="utf-8"))
    source_manifest = json.loads(source_perceive_manifest.read_text(encoding="utf-8"))
    target = selection["resolved_window"]
    target_kind = selection["target_kind"]
    requested = selection["requested"]
    windows = windows_payload["windows"]

    current_desktop, desktops = parse_desktops(read_text(desktops_path))
    target_props = parse_xprop(read_text(target_props_path))
    process_info = parse_process(read_text(target_process_path))
    raw_ocr_text = read_text(ocr_text_path)
    enhanced_ocr_text = read_text(ocr_enhanced_text_path)
    width, height = parse_dimensions(read_text(size_path))
    title = str(target_props.get("wm_name") or target.get("title") or "")
    app = app_name(target_props, process_info, title)
    resolved_pid = target.get("pid")
    if resolved_pid in {"", "0", None}:
        resolved_pid = target_props.get("pid") or process_info.get("pid") or ""

    raw_lines = parse_tsv_lines(ocr_tsv_path, "raw", width, height) or fallback_lines_from_text(raw_ocr_text, "raw")
    enhanced_lines = parse_tsv_lines(ocr_enhanced_tsv_path, "enhanced", width, height) or fallback_lines_from_text(enhanced_ocr_text, "enhanced")
    merged_lines = merge_lines(raw_lines, enhanced_lines)
    if not merged_lines:
        merged_lines = fallback_lines_from_text(raw_ocr_text or enhanced_ocr_text, "fallback")
    joined_ocr = "\n".join(str(item["text"]) for item in merged_lines)
    surface = surface_kind(app, title, joined_ocr or raw_ocr_text or enhanced_ocr_text)
    layout = build_layout(merged_lines, surface)
    normalized_excerpts = select_excerpt_lines(merged_lines, ["main_content", "left_sidebar", "header", "bottom_panel", "footer", "right_sidebar"])
    readable_text_lines = [str(item["text"]) for item in merged_lines[:24]]
    ocr_normalized_text_path.write_text("\n".join(readable_text_lines) + ("\n" if readable_text_lines else ""), encoding="utf-8")
    layout_path.write_text(json.dumps(layout, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    raw_confidence = parse_ocr_confidence(ocr_tsv_path)
    enhanced_confidence = parse_ocr_confidence(ocr_enhanced_tsv_path)
    normalized_confidences = [item["avg_confidence"] for item in merged_lines if isinstance(item.get("avg_confidence"), (int, float))]
    normalized_confidence = round(statistics.mean(normalized_confidences), 1) if normalized_confidences else None

    current_desktop_windows = []
    if current_desktop is not None:
        for item in windows:
            desktop = item.get("desktop")
            if desktop == "-1":
                current_desktop_windows.append(item)
            else:
                try:
                    if int(desktop) == current_desktop:
                        current_desktop_windows.append(item)
                except (TypeError, ValueError):
                    continue

    registered_current_desktop = [
        item for item in current_desktop_windows if item.get("title") and item.get("title") != "Desktop Icons 1"
    ]

    screenshot_source_id = "desktop_screenshot" if target_kind == "desktop" else "target_screenshot"
    claims: list[dict[str, object]] = []
    limits: list[str] = []
    window_identity = f'{app} window "{title or target.get("title") or "(untitled)"}"'

    if target_kind == "desktop":
        claims.append(
            {
                "confidence": "high",
                "sources": ["window_metadata"],
                "inference_strength": "direct",
                "text": f'The active surface registered by metadata is {window_identity} (window_id={target.get("window_id") or "unknown"}, pid={resolved_pid or "unknown"}).',
            }
        )
        if current_desktop is not None and registered_current_desktop:
            titles = ", ".join(f'"{item["title"]}"' for item in registered_current_desktop[:5])
            claims.append(
                {
                    "confidence": "medium",
                    "sources": ["window_metadata"],
                    "inference_strength": "direct",
                    "text": f'Window metadata registers {len(registered_current_desktop)} titled surfaces on current desktop {current_desktop}: {titles}. This remains metadata evidence, not proof that every listed window is fully unobscured in the screenshot.',
                }
            )
        claims.append(
            {
                "confidence": "medium" if normalized_excerpts else "low",
                "sources": [screenshot_source_id, "ocr_enhanced", "ocr_normalized", "layout_heuristics"],
                "inference_strength": "approximate",
                "text": describe_visible_content(target_kind, surface, app, title, layout, normalized_excerpts),
            }
        )
        claims.append(
            {
                "confidence": "medium" if normalized_excerpts else "low",
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics"],
                "inference_strength": "approximate",
                "text": consistency_claim(surface, app, normalized_excerpts),
            }
        )
        limits.append("Window metadata can confirm registered surfaces on the current desktop, but it does not prove whether a window is hidden behind another one.")
        limits.append("Layout heuristics are approximate and only describe the captured frame, not off-screen monitors or hidden workspaces.")
        limits.append("OCR normalization improves readability, but stylized text, icons, and non-text imagery can still be missed or distorted.")
    else:
        claims.append(
            {
                "confidence": "high",
                "sources": ["window_metadata"],
                "inference_strength": "direct",
                "text": f'The described target resolves to {window_identity} (window_id={target.get("window_id") or "unknown"}, pid={resolved_pid or "unknown"}).',
            }
        )
        claims.append(
            {
                "confidence": "medium" if layout["sections"] else "low",
                "sources": [screenshot_source_id, "ocr_enhanced", "layout_heuristics"],
                "inference_strength": "approximate",
                "text": f'{layout["summary"]} This is inferred from OCR line placement on the captured screenshot, not from hidden UI state.',
            }
        )
        claims.append(
            {
                "confidence": "medium" if normalized_excerpts else "low",
                "sources": [screenshot_source_id, "ocr_raw", "ocr_enhanced", "ocr_normalized"],
                "inference_strength": "approximate",
                "text": describe_visible_content(target_kind, surface, app, title, layout, normalized_excerpts),
            }
        )
        claims.append(
            {
                "confidence": "medium" if normalized_excerpts else "low",
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics"],
                "inference_strength": "approximate",
                "text": consistency_claim(surface, app, normalized_excerpts),
            }
        )
        limits.append("OCR normalization improves legibility but does not guarantee exact transcription of small text, punctuation, or stylized UI labels.")
        limits.append("Layout sections are heuristic regions derived from OCR geometry; they are useful structure hints, not pixel-perfect segmentation.")
        limits.append("The description only covers the captured target window, not hidden tabs, background windows, or content outside the frame.")

    summary = " ".join(claim["text"] for claim in claims[:3])
    if target_kind == "desktop":
        summary = " ".join(claim["text"] for claim in claims[:4])

    description = {
        "summary": summary,
        "claims": claims,
        "target_kind": target_kind,
        "target_window": {
            "window_id": target.get("window_id"),
            "title": title or target.get("title"),
            "pid": resolved_pid,
            "app": app,
            "surface_kind": surface,
            "is_active": bool(target.get("is_active")),
        },
        "selection_reason": selection.get("selection_reason"),
        "matched_window_count": selection.get("matched_window_count"),
        "requested": requested,
        "current_desktop": current_desktop,
        "registered_current_desktop_windows": summarize_windows(registered_current_desktop),
        "layout": layout,
        "readable_text": {
            "raw_excerpt": [str(item["text"]) for item in raw_lines[:8]],
            "enhanced_excerpt": [str(item["text"]) for item in enhanced_lines[:8]],
            "normalized_excerpt": normalized_excerpts,
            "normalized_lines_total": len(merged_lines),
            "approximate": True,
        },
        "ocr": {
            "raw": {
                "words_with_confidence": raw_confidence["words"],
                "average_confidence": raw_confidence["avg_conf"],
            },
            "enhanced": {
                "words_with_confidence": enhanced_confidence["words"],
                "average_confidence": enhanced_confidence["avg_conf"],
            },
            "normalized": {
                "lines": len(merged_lines),
                "average_confidence": normalized_confidence,
            },
            "approximate": True,
        },
        "source_breakdown": {
            "metadata": "window identity, pid hints, current desktop inventory",
            "ocr_raw": "verbatim OCR output from the original screenshot",
            "ocr_enhanced": "OCR output from the contrast-enhanced screenshot",
            "ocr_normalized": "deduplicated, whitespace-normalized text assembled from OCR candidates",
            "layout_heuristics": "approximate section labels inferred from OCR bounding boxes",
        },
        "limits": limits,
    }

    sources = {
        "used": [
            {
                "id": "window_metadata",
                "kind": "metadata",
                "paths": [
                    str(source_windows),
                    str(desktops_path),
                    str(target_props_path),
                    str(target_process_path),
                    str(source_active_props),
                ],
                "role": "window identity, current desktop inventory, pid, and app hints",
                "certainty": "high",
            },
            {
                "id": screenshot_source_id,
                "kind": "screenshot",
                "paths": [str(target_screenshot)],
                "role": "raw visual evidence for the described target",
                "certainty": "high",
            },
            {
                "id": "ocr_raw",
                "kind": "ocr",
                "paths": [str(ocr_text_path), str(ocr_tsv_path)],
                "role": "raw OCR extraction from the original screenshot",
                "certainty": "medium" if raw_lines else "low",
                "notes": "Raw OCR preserves the first-pass text extraction, including noise.",
            },
            {
                "id": "ocr_enhanced",
                "kind": "ocr",
                "paths": [str(ocr_enhanced_image), str(ocr_enhanced_text_path), str(ocr_enhanced_tsv_path)],
                "role": "OCR extraction from a contrast-enhanced screenshot derivative",
                "certainty": "medium" if enhanced_lines else "low",
                "notes": "The enhanced image is a deterministic preprocessing step, not new visual evidence.",
            },
            {
                "id": "ocr_normalized",
                "kind": "ocr-postprocess",
                "paths": [str(ocr_normalized_text_path)],
                "role": "deduplicated and normalized readable text derived from raw and enhanced OCR",
                "certainty": "medium" if merged_lines else "low",
                "notes": "Normalization improves usability but remains approximate and auditable against the raw OCR artifacts.",
            },
            {
                "id": "layout_heuristics",
                "kind": "heuristic",
                "paths": [str(layout_path)],
                "role": "approximate layout regions inferred from OCR geometry",
                "certainty": "medium" if layout["sections"] else "low",
                "notes": "Layout sections are heuristics derived from visible OCR positions.",
            },
        ],
        "supporting": [
            {
                "id": "source_perceive_manifest",
                "kind": "manifest",
                "paths": [str(source_perceive_manifest)],
                "role": "links the semantic run back to the raw host perception capture",
            },
            {
                "id": "root_properties",
                "kind": "metadata",
                "paths": [str(root_props_path)],
                "role": "root window properties for active desktop context",
            },
        ],
    }
    if supporting_active_png.exists():
        sources["supporting"].append(
            {
                "id": "supporting_active_window_screenshot",
                "kind": "screenshot",
                "paths": [str(supporting_active_png)],
                "role": "zoomed active-window screenshot captured by the raw perception lane",
            }
        )

    artifacts = {
        "summary": str(summary_path),
        "description": str(description_path),
        "sources": str(sources_path),
        "selection": str(selection_path),
        "target_screenshot": str(target_screenshot),
        "windows": str(source_windows),
        "windows_json": str(windows_json_path),
        "desktops": str(desktops_path),
        "root_properties": str(root_props_path),
        "target_window_properties": str(target_props_path),
        "target_process": str(target_process_path),
        "ocr_text": str(ocr_text_path),
        "ocr_tsv": str(ocr_tsv_path),
        "ocr_enhanced_image": str(ocr_enhanced_image),
        "ocr_enhanced_text": str(ocr_enhanced_text_path),
        "ocr_enhanced_tsv": str(ocr_enhanced_tsv_path),
        "ocr_normalized_text": str(ocr_normalized_text_path),
        "layout": str(layout_path),
        "source_perceive_manifest": str(source_perceive_manifest),
    }
    if source_active_props.exists():
        artifacts["active_window_properties"] = str(source_active_props)
    if supporting_active_png.exists():
        artifacts["supporting_active_window_screenshot"] = str(supporting_active_png)

    manifest = {
        "kind": "golem_host_describe",
        "run_dir": str(run_dir),
        "target": {
            "kind": target_kind,
            "requested": requested,
            "selection_reason": selection.get("selection_reason"),
            "matched_window_count": selection.get("matched_window_count"),
            "resolved_window": description["target_window"],
        },
        "source_perceive_run_dir": source_manifest.get("run_dir"),
        "sources_used": [item["id"] for item in sources["used"]],
        "artifacts": artifacts,
        "description": description,
        "current_desktop": current_desktop,
        "registered_current_desktop_windows": description["registered_current_desktop_windows"],
        "ocr": description["ocr"],
        "layout": description["layout"],
    }

    description_path.write_text(json.dumps(description, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    sources_path.write_text(json.dumps(sources, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    summary_lines = [
        "GOLEM HOST SEMANTIC DESCRIPTION",
        "",
        f"run_dir: {run_dir}",
        f"target: {target_kind}",
        f"requested_window_id: {requested.get('window_id') or '(none)'}",
        f"requested_title: {requested.get('title') or '(none)'}",
        f"selection_reason: {selection.get('selection_reason')}",
        f"matched_window_count: {selection.get('matched_window_count')}",
        f"target_window_id: {description['target_window']['window_id'] or '(none)'}",
        f"target_title: {description['target_window']['title'] or '(none)'}",
        f"target_app: {description['target_window']['app']}",
        f"target_surface_kind: {description['target_window']['surface_kind']}",
        f"target_screenshot: {target_screenshot}",
        f"target_screenshot_size: {read_text(size_path).strip() or '(unknown)'}",
        "sources_used:",
    ]
    summary_lines.extend(f"- {item['id']}: {item['role']}" for item in sources["used"])
    summary_lines.append("layout_summary:")
    summary_lines.append(f"- {layout['summary']}")
    summary_lines.append("claims:")
    summary_lines.extend(
        f"- [{'+'.join(claim['sources'])}/{claim['confidence']}/{claim['inference_strength']}] {claim['text']}"
        for claim in claims
    )
    summary_lines.append("normalized_ocr_excerpt:")
    summary_lines.extend(f"- {line}" for line in normalized_excerpts or ["(none)"])
    summary_lines.append("limits:")
    summary_lines.extend(f"- {line}" for line in limits)
    summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
