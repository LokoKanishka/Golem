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
from typing import cast


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


SURFACE_LABELS = {
    "editor": "editor / IDE",
    "chat": "chat / messaging workspace",
    "terminal": "terminal / console",
    "browser-web-app": "browser / web app",
    "unknown": "unknown / mixed surface",
}


def empty_category_scores() -> dict[str, int]:
    return {
        "editor": 0,
        "chat": 0,
        "terminal": 0,
        "browser-web-app": 0,
        "unknown": 0,
    }


def add_score(
    scores: dict[str, int],
    evidence: list[dict[str, object]],
    category: str,
    weight: int,
    source: str,
    reason: str,
) -> None:
    scores[category] = scores.get(category, 0) + weight
    evidence.append(
        {
            "category": category,
            "weight": weight,
            "source": source,
            "reason": reason,
        }
    )


def metadata_surface_scores(
    app: str,
    title: str,
    process: dict[str, str],
    props: dict[str, object],
) -> tuple[dict[str, int], list[dict[str, object]]]:
    scores = empty_category_scores()
    evidence: list[dict[str, object]] = []
    text = " ".join(
        [
            app,
            title,
            process.get("comm", ""),
            process.get("args", ""),
            " ".join(str(item) for item in props.get("wm_class", [])),
        ]
    ).lower()

    if "visual studio code" in text or re.search(r"\bcode\b", text):
        add_score(scores, evidence, "editor", 12, "window_metadata", "metadata identifies Visual Studio Code/editor tooling")
    if "chatgpt" in text:
        add_score(scores, evidence, "chat", 12, "window_metadata", "metadata identifies ChatGPT")
    if "notebooklm" in text:
        add_score(scores, evidence, "browser-web-app", 10, "window_metadata", "metadata identifies NotebookLM web app")
    if any(term in text for term in ["gnome-terminal", "xterm", "terminal", "konsole", "alacritty", "kitty", "tilix"]):
        add_score(scores, evidence, "terminal", 12, "window_metadata", "metadata identifies terminal software")
    if any(term in text for term in ["google-chrome", "chromium", "firefox"]) and scores["chat"] < 10:
        add_score(scores, evidence, "browser-web-app", 7, "window_metadata", "metadata identifies a browser-class window")
    if any(term in text for term in ["xmessage", "zenity", "dialog"]):
        add_score(scores, evidence, "unknown", 5, "window_metadata", "metadata identifies a generic dialog surface")

    return scores, evidence


def ocr_surface_scores(lines: list[dict[str, object]]) -> tuple[dict[str, int], list[dict[str, object]]]:
    scores = empty_category_scores()
    evidence: list[dict[str, object]] = []

    editor_patterns = [
        (re.compile(r"\bexplorer\b|\bopen file\b|\brepository\b|\bworkspace\b"), 4, "editor-style navigation or workspace labels"),
        (re.compile(r"\bdef\b|\bclass\b|\bimport\b|\breturn\b|\bfunction\b|\bmodule\b|\bconst\b|\blet\b|=>"), 4, "code-like tokens"),
        (re.compile(r"\b[\w.-]+\.[a-z0-9]{1,5}\b|(?:^|\s)(?:[\w.-]+/)+[\w./-]+|@[A-Za-z0-9_.-]+\.[A-Za-z0-9]+"), 3, "file paths or file extensions"),
        (re.compile(r"\berror\b|\btraceback\b|\bfailed\b|\bwarning\b"), 3, "editor-visible error or trace text"),
    ]
    chat_patterns = [
        (re.compile(r"\bnuevo chat\b|\bbiblioteca\b|\bbuscar chats\b|\bchatgpt\b|\bcompartir\b"), 4, "chat-style sidebar or header labels"),
        (re.compile(r"\bmarkdown\b|\bmensaje\b|\bpregunta\b|\bconversation\b|\bchat\b|\busuario:\b|\basistente:\b|\bassistant:\b"), 3, "chat/message vocabulary"),
        (re.compile(r"^[-*]\s|\b##\b|\b###\b"), 2, "chat or assistant output formatting"),
    ]
    terminal_patterns = [
        (re.compile(r"(^| )\$ ?|# ?|~/?|[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+"), 4, "prompt-like shell markers"),
        (re.compile(r"\btraceback\b|\berror\b|\bfailed\b|\bexit code\b"), 5, "terminal error/output markers"),
        (re.compile(r"\bgit\b|\bpython3?\b|\bbash\b|\bpip\b|\bnpm\b|\bmake\b|\bcd\b|\brg\b|\bls\b|\bpytest\b"), 4, "command-line vocabulary"),
    ]
    browser_patterns = [
        (re.compile(r"\bsources\b|\bsearch\b|\bshare\b|\bconfigur\w*\b|\bdashboard\b|\bsettings\b|\boverview\b|\bdocs?\b|\bhome\b"), 3, "web app controls or navigation"),
        (re.compile(r"\bsubmit\b|\bconfirm\b|\bcontinue\b|\bopen\b|\blaunch\b|\bsign in\b"), 3, "browser/web CTA text"),
        (re.compile(r"\bnotebooklm\b|\bweb\b|\bpage\b|\bsource\b"), 3, "browser/web app nouns"),
    ]

    for line in lines:
        text = str(line["text"])
        lowered = text.lower()
        for pattern, weight, reason in editor_patterns:
            if pattern.search(lowered):
                add_score(scores, evidence, "editor", weight, "ocr_normalized", reason)
        for pattern, weight, reason in chat_patterns:
            if pattern.search(lowered):
                add_score(scores, evidence, "chat", weight, "ocr_normalized", reason)
        for pattern, weight, reason in terminal_patterns:
            if pattern.search(text):
                add_score(scores, evidence, "terminal", weight, "ocr_normalized", reason)
        for pattern, weight, reason in browser_patterns:
            if pattern.search(lowered):
                add_score(scores, evidence, "browser-web-app", weight, "ocr_normalized", reason)

        section_role = str(line.get("section_role") or "")
        if section_role == "left_sidebar":
            add_score(scores, evidence, "editor", 1, "layout_heuristics", "sidebar layout supports editor/chat/browser categories")
            add_score(scores, evidence, "chat", 1, "layout_heuristics", "sidebar layout supports editor/chat/browser categories")
            add_score(scores, evidence, "browser-web-app", 1, "layout_heuristics", "sidebar layout supports editor/chat/browser categories")
        if section_role == "footer" and ("chat" in lowered or "prompt" in lowered or "search" in lowered):
            add_score(scores, evidence, "chat", 2, "layout_heuristics", "footer text looks like a composer or search/input area")
        if section_role == "main_content" and any(token in lowered for token in ["traceback", "build failed", "error"]):
            add_score(scores, evidence, "terminal", 2, "layout_heuristics", "main content contains terminal-style error/output text")

    return scores, evidence


def classify_surface_profile(
    app: str,
    title: str,
    process: dict[str, str],
    props: dict[str, object],
    lines: list[dict[str, object]],
    layout: dict[str, object],
) -> dict[str, object]:
    metadata_scores, metadata_evidence = metadata_surface_scores(app, title, process, props)
    ocr_scores, ocr_evidence = ocr_surface_scores(lines)
    layout_evidence: list[dict[str, object]] = []
    combined_scores = empty_category_scores()
    for category in combined_scores:
        combined_scores[category] = metadata_scores.get(category, 0) + ocr_scores.get(category, 0)

    if len(layout.get("sections", [])) >= 3:
        if any(section["role"] == "left_sidebar" for section in layout["sections"]):
            combined_scores["editor"] += 1
            combined_scores["chat"] += 1
            combined_scores["browser-web-app"] += 1
            for category in ("editor", "chat", "browser-web-app"):
                layout_evidence.append(
                    {
                        "category": category,
                        "weight": 1,
                        "source": "layout_heuristics",
                        "reason": "layout includes a left sidebar region often seen in editor/chat/browser surfaces",
                    }
                )
        if any(section["role"] == "footer" for section in layout["sections"]):
            combined_scores["chat"] += 1
            layout_evidence.append(
                {
                    "category": "chat",
                    "weight": 1,
                    "source": "layout_heuristics",
                    "reason": "layout includes a footer/input region consistent with a chat composer",
                }
            )
        if any(section["role"] == "main_content" for section in layout["sections"]) and not any(
            section["role"] == "left_sidebar" for section in layout["sections"]
        ):
            combined_scores["terminal"] += 1
            layout_evidence.append(
                {
                    "category": "terminal",
                    "weight": 1,
                    "source": "layout_heuristics",
                    "reason": "layout is dominated by a central content region consistent with terminal output",
                }
            )

    sorted_scores = sorted(combined_scores.items(), key=lambda item: item[1], reverse=True)
    best_category, best_score = sorted_scores[0]
    second_score = sorted_scores[1][1] if len(sorted_scores) > 1 else 0
    margin = best_score - second_score

    if best_score >= 12 and margin >= 4:
        confidence = "strong"
    elif best_score >= 7 and margin >= 2:
        confidence = "reasonable"
    else:
        confidence = "uncertain"

    if best_score < 5:
        best_category = "unknown"
        confidence = "uncertain"

    evidence = metadata_evidence + ocr_evidence + layout_evidence
    relevant_evidence = [
        item for item in evidence if item["category"] == best_category
    ]
    relevant_evidence.sort(key=lambda item: (-int(item["weight"]), str(item["source"]), str(item["reason"])))

    return {
        "category": best_category,
        "label": SURFACE_LABELS.get(best_category, best_category),
        "confidence": confidence,
        "approximate": confidence != "strong",
        "scores": combined_scores,
        "ranked_categories": [
            {"category": category, "label": SURFACE_LABELS.get(category, category), "score": score}
            for category, score in sorted_scores
        ],
        "best_score": best_score,
        "margin": margin,
        "evidence": relevant_evidence[:8],
        "sources": sorted({str(item["source"]) for item in relevant_evidence}),
    }


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


SURFACE_SECTION_PRIORITIES = {
    "editor": ["main_content", "left_sidebar", "header", "footer", "bottom_panel", "right_sidebar"],
    "chat": ["main_content", "footer", "left_sidebar", "header", "right_sidebar", "bottom_panel"],
    "terminal": ["main_content", "header", "footer", "left_sidebar", "right_sidebar"],
    "browser-web-app": ["main_content", "header", "left_sidebar", "right_sidebar", "footer", "bottom_panel"],
    "unknown": ["main_content", "header", "left_sidebar", "footer", "right_sidebar", "bottom_panel"],
}

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
    explicit_error_pattern = re.compile(r"\berror\b|\btraceback\b|\bfailed\b", re.IGNORECASE)
    primary_error_base = filter_candidates_by_pattern(fields.get("error_candidates") or [], explicit_error_pattern)
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


def priority_kind_for_line(category: str, text: str, section_role: str) -> str:
    lowered = text.lower()
    if category == "editor":
        if re.search(r"\berror\b|\btraceback\b|\bfailed\b|\bwarning\b", lowered):
            return "error-line"
        if re.search(r"\b[\w.-]+\.[a-z0-9]{1,5}\b|(?:^|\s)(?:[\w.-]+/)+[\w./-]+|@[A-Za-z0-9_.-]+\.[A-Za-z0-9]+", text):
            return "file-reference"
        if re.search(r"\bdef\b|\bclass\b|\bimport\b|\breturn\b|\bfunction\b|\bconst\b|\blet\b|=>", lowered):
            return "code-line"
        if section_role == "left_sidebar":
            return "explorer-item"
        return "workspace-header" if section_role == "header" else "editor-detail"
    if category == "chat":
        if section_role == "footer":
            return "composer"
        if section_role == "left_sidebar":
            return "conversation-sidebar"
        return "visible-message"
    if category == "terminal":
        if re.search(r"\btraceback\b|\berror\b|\bfailed\b|\bexit code\b", lowered):
            return "error-output"
        if re.search(r"(^| )\$ ?|# ?|~/?|[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+", text) or re.search(r"\bgit\b|\bpython3?\b|\bbash\b|\bpip\b|\bnpm\b|\bmake\b", lowered):
            return "command-or-prompt"
        return "visible-output"
    if category == "browser-web-app":
        if section_role == "header":
            return "page-header"
        if section_role in {"left_sidebar", "right_sidebar"}:
            return "navigation"
        if re.search(r"\bsubmit\b|\bconfirm\b|\bcontinue\b|\bopen\b|\blaunch\b|\bshare\b", lowered):
            return "cta-or-control"
        return "page-content"
    return "visible-text"


def score_line_for_category(line: dict[str, object], category: str) -> tuple[float, list[str]]:
    text = str(line["text"])
    lowered = text.lower()
    section_role = str(line.get("section_role") or "")
    section_priorities = SURFACE_SECTION_PRIORITIES.get(category, SURFACE_SECTION_PRIORITIES["unknown"])
    priority_index = section_priorities.index(section_role) if section_role in section_priorities else len(section_priorities)
    score = 25.0 - float(priority_index * 2)
    score += min(len(text) / 18.0, 6.0)
    if isinstance(line.get("avg_confidence"), (int, float)):
        score += float(line["avg_confidence"]) / 20.0
    reasons = [f"section:{section_role or 'unknown'}"]

    kind = priority_kind_for_line(category, text, section_role)
    reasons.append(f"kind:{kind}")

    if category == "editor":
        if kind == "error-line":
            score += 8
        if kind == "file-reference":
            score += 7
        if kind == "code-line":
            score += 6
        if kind == "explorer-item":
            score += 4
        if kind == "workspace-header":
            score += 3
    elif category == "chat":
        if kind == "visible-message":
            score += 6
        if kind == "composer":
            score += 5
        if kind == "conversation-sidebar":
            score += 4
        if re.search(r"^[-*]\s|\b##\b|\b###\b", lowered):
            score += 2
            reasons.append("chat-formatting")
    elif category == "terminal":
        if kind == "error-output":
            score += 8
        if kind == "command-or-prompt":
            score += 7
        if kind == "visible-output":
            score += 4
        score += float(line.get("center_y_ratio") or 0) * 3
    elif category == "browser-web-app":
        if kind == "page-header":
            score += 5
        if kind == "navigation":
            score += 4
        if kind == "cta-or-control":
            score += 5
        if kind == "page-content":
            score += 4
    else:
        score += 2

    return score, reasons


def build_useful_lines(lines: list[dict[str, object]], category: str) -> list[dict[str, object]]:
    ranked: list[dict[str, object]] = []
    seen = set()
    for line in lines:
        text = str(line["text"])
        key = fingerprint(text)
        if key in seen or len(text) < 4:
            continue
        seen.add(key)
        score, reasons = score_line_for_category(line, category)
        ranked.append(
            {
                "text": text,
                "score": round(score, 2),
                "section_role": str(line.get("section_role") or ""),
                "priority_kind": priority_kind_for_line(category, text, str(line.get("section_role") or "")),
                "center_y_ratio": round(float(line.get("center_y_ratio") or 0.0), 4),
                "reasons": reasons,
                "sources": ["ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "approximate": True,
                "avg_confidence": line.get("avg_confidence"),
            }
        )
    ranked.sort(key=lambda item: (-float(item["score"]), item["text"]))
    return ranked[:10]


def build_useful_regions(layout: dict[str, object], category: str) -> list[dict[str, object]]:
    priorities = SURFACE_SECTION_PRIORITIES.get(category, SURFACE_SECTION_PRIORITIES["unknown"])
    section_map = {section["role"]: section for section in layout.get("sections", [])}
    region_reasons = {
        "editor": {
            "main_content": "likely editor/code working area",
            "left_sidebar": "likely explorer/project tree",
            "header": "window header or active tab strip",
            "footer": "status or bottom input area",
            "bottom_panel": "problems/output panel",
        },
        "chat": {
            "main_content": "visible conversation body",
            "left_sidebar": "conversation list or context rail",
            "footer": "composer/input area",
            "header": "chat header and controls",
        },
        "terminal": {
            "main_content": "visible prompt, command, and output block",
            "header": "terminal title/header",
            "footer": "lower edge of the visible terminal block",
        },
        "browser-web-app": {
            "main_content": "primary page or app content",
            "header": "page header or app controls",
            "left_sidebar": "navigation rail",
            "right_sidebar": "secondary side panel",
            "footer": "footer or lower controls",
        },
        "unknown": {
            "main_content": "main visible text area",
            "header": "header or title region",
            "left_sidebar": "side context area",
            "footer": "lower visible area",
        },
    }
    results = []
    for role in priorities:
        section = section_map.get(role)
        if not section:
            continue
        results.append(
            {
                "role": role,
                "label": section["label"],
                "line_count": section["line_count"],
                "reason": region_reasons.get(category, region_reasons["unknown"]).get(role, "useful visible region"),
                "sources": ["layout_heuristics", "surface_classification_heuristics"],
                "approximate": True,
            }
        )
    return results


def summarize_priority_focus(category: str, useful_lines: list[dict[str, object]]) -> str:
    kinds = [str(item["priority_kind"]) for item in useful_lines[:5]]
    if category == "editor":
        parts = []
        if any(kind == "workspace-header" for kind in kinds):
            parts.append("workspace or active tab cues")
        if any(kind == "explorer-item" for kind in kinds):
            parts.append("explorer/sidebar entries")
        if any(kind in {"code-line", "file-reference"} for kind in kinds):
            parts.append("code or file-reference lines")
        if any(kind == "error-line" for kind in kinds):
            parts.append("visible errors or trace lines")
        return ", ".join(parts) if parts else "editor-visible code, file, and sidebar cues"
    if category == "chat":
        parts = []
        if any(kind == "conversation-sidebar" for kind in kinds):
            parts.append("conversation list entries")
        if any(kind == "visible-message" for kind in kinds):
            parts.append("visible messages")
        if any(kind == "composer" for kind in kinds):
            parts.append("the composer/input area")
        return ", ".join(parts) if parts else "chat messages, context rails, and input cues"
    if category == "terminal":
        parts = []
        if any(kind == "command-or-prompt" for kind in kinds):
            parts.append("prompt and recent command lines")
        if any(kind == "error-output" for kind in kinds):
            parts.append("recent errors or trace output")
        if any(kind == "visible-output" for kind in kinds):
            parts.append("the latest visible output block")
        return ", ".join(parts) if parts else "prompt, command, and output cues"
    if category == "browser-web-app":
        parts = []
        if any(kind == "page-header" for kind in kinds):
            parts.append("page header text")
        if any(kind == "navigation" for kind in kinds):
            parts.append("navigation/sidebar labels")
        if any(kind == "cta-or-control" for kind in kinds):
            parts.append("CTA or control text")
        if any(kind == "page-content" for kind in kinds):
            parts.append("central page content")
        return ", ".join(parts) if parts else "navigation, header, central content, and CTA cues"
    return "the most stable visible text across the captured frame"


def describe_surface_specific_content(
    target_kind: str,
    category: str,
    layout: dict[str, object],
    useful_lines: list[dict[str, object]],
    useful_regions: list[dict[str, object]],
) -> str:
    if not useful_lines:
        if target_kind == "desktop":
            return "The desktop screenshot is real, but even after OCR cleanup there is not enough stable readable text to describe the visible content beyond metadata."
        return "The target screenshot is real, but even after OCR cleanup there is not enough stable readable text to describe the visible content confidently."

    line_snippets = ", ".join(f'"{item["text"]}"' for item in useful_lines[:3])
    region_snippets = ", ".join(region["label"] for region in useful_regions[:3]) if useful_regions else layout.get("summary", "")
    focus_summary = summarize_priority_focus(category, useful_lines)

    if category == "editor":
        return f'The visible content is consistent with an editor / IDE surface. The most useful visible regions are {region_snippets}. The ranking prioritizes {focus_summary}. Prioritized visible cues include {line_snippets}.'
    if category == "chat":
        return f'The visible content is consistent with a chat or messaging workspace. The most useful visible regions are {region_snippets}. The ranking prioritizes {focus_summary}. Prioritized visible cues include {line_snippets}.'
    if category == "terminal":
        return f'The visible content is consistent with a terminal / console surface. The most useful visible regions are {region_snippets}. The ranking prioritizes {focus_summary}. Prioritized visible cues include {line_snippets}.'
    if category == "browser-web-app":
        return f'The visible content is consistent with a browser / web app surface. The most useful visible regions are {region_snippets}. The ranking prioritizes {focus_summary}. Prioritized visible cues include {line_snippets}.'
    return f'The visible content remains mixed or generic. The most useful visible regions are {region_snippets}. The ranking prioritizes {focus_summary}. Prioritized visible cues include {line_snippets}.'


def consistency_claim(category: str, app: str, useful_lines: list[dict[str, object]]) -> str:
    joined = " ".join(item["text"] for item in useful_lines).lower()
    if category == "chat":
        if any(marker in joined for marker in ["nuevo chat", "biblioteca", "chatgpt", "compartir"]):
            return "Window metadata and prioritized visible text both support a chat-style reading rather than a generic browser page."
        return "Metadata strongly suggests a chat workspace; the visible text is directionally consistent but still partial."
    if category == "editor":
        if any(marker in joined for marker in ["explorer", "workspace", "repository", ".py", "open file"]):
            return "Window metadata and prioritized visible text both support an editor / IDE reading instead of a generic document view."
        return "Metadata strongly suggests an editor / IDE; the visible text only partially confirms that reading."
    if category == "terminal":
        if any(marker in joined for marker in ["traceback", "failed", "$", "git", "python"]):
            return "Window metadata and prioritized visible text both support a terminal / console reading."
        return "Metadata strongly suggests a terminal; the visible text only partially confirms that reading."
    if category == "browser-web-app":
        return "Window metadata identifies a browser-class surface; prioritized visible text supports a web app reading without proving hidden tabs or off-screen state."
    return f'Window metadata identifies the surface as {app}; prioritized visible text is useful but still not enough to classify it strongly.'


def claim_confidence_from_surface(profile_confidence: str) -> str:
    mapping = {
        "strong": "high",
        "reasonable": "medium",
        "uncertain": "low",
    }
    return mapping.get(profile_confidence, "low")


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
    surface_profile_path = run_dir / "surface-profile.json"
    structured_fields_path = run_dir / "structured-fields.json"
    surface_state_bundle_path = run_dir / "surface-state.json"
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
    surface_profile = classify_surface_profile(app, title, process_info, target_props, merged_lines, layout)
    useful_lines = build_useful_lines(merged_lines, surface_profile["category"])
    useful_regions = build_useful_regions(layout, surface_profile["category"])
    structured_fields = build_structured_fields(
        surface_profile["category"],
        str(surface_profile["label"]),
        str(surface_profile["confidence"]),
        title,
        app,
        merged_lines,
        useful_lines,
        useful_regions,
    )
    surface_state_bundle = build_surface_state_bundle(
        str(surface_profile["category"]),
        str(surface_profile["label"]),
        str(surface_profile["confidence"]),
        structured_fields,
    )
    normalized_excerpts = [str(item["text"]) for item in useful_lines[:8]]
    readable_text_lines = [str(item["text"]) for item in merged_lines[:24]]
    ocr_normalized_text_path.write_text("\n".join(readable_text_lines) + ("\n" if readable_text_lines else ""), encoding="utf-8")
    layout_path.write_text(json.dumps(layout, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    surface_profile_artifact = {
        "surface_kind": surface,
        "surface_classification": surface_profile,
        "useful_lines": useful_lines,
        "useful_regions": useful_regions,
        "approximate": True,
    }
    surface_profile_path.write_text(
        json.dumps(surface_profile_artifact, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    structured_fields_path.write_text(
        json.dumps(structured_fields, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    surface_state_bundle_path.write_text(
        json.dumps(surface_state_bundle, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )

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
    classification_claim = (
        f'Surface classification heuristics read the visible target as {surface_profile["label"]} '
        f'with {surface_profile["confidence"]} confidence. This combines metadata, normalized OCR, '
        f"and layout cues, and remains approximate rather than hidden-state certainty."
    )
    visible_content_claim = describe_surface_specific_content(
        target_kind,
        surface_profile["category"],
        layout,
        useful_lines,
        useful_regions,
    )
    consistency_text = consistency_claim(surface_profile["category"], app, useful_lines)
    classification_claim_confidence = claim_confidence_from_surface(str(surface_profile["confidence"]))

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
                "confidence": classification_claim_confidence,
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": classification_claim,
            }
        )
        claims.append(
            {
                "confidence": classification_claim_confidence if useful_lines else "low",
                "sources": [screenshot_source_id, "ocr_raw", "ocr_enhanced", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": visible_content_claim,
            }
        )
        claims.append(
            {
                "confidence": classification_claim_confidence if useful_lines else "low",
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": consistency_text,
            }
        )
        limits.append("Window metadata can confirm registered surfaces on the current desktop, but it does not prove whether a window is hidden behind another one.")
        limits.append("Layout heuristics are approximate and only describe the captured frame, not off-screen monitors or hidden workspaces.")
        limits.append("OCR normalization improves readability, but stylized text, icons, and non-text imagery can still be missed or distorted.")
        limits.append("Surface classification is heuristic and can be pulled off course by mixed content inside the active window, even when metadata is strong.")
        limits.append("Structured fields are heuristic extracts from visible text and metadata; empty or partial fields are expected when the captured frame lacks a stable signal.")
        limits.append("Surface state bundles consolidate the structured layers into an operational view, but they remain approximate summaries rather than hidden application state.")
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
                "confidence": classification_claim_confidence,
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": classification_claim,
            }
        )
        claims.append(
            {
                "confidence": "medium" if layout["sections"] else "low",
                "sources": [screenshot_source_id, "ocr_enhanced", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": f'{layout["summary"]} This is inferred from OCR line placement on the captured screenshot, not from hidden UI state.',
            }
        )
        claims.append(
            {
                "confidence": classification_claim_confidence if useful_lines else "low",
                "sources": [screenshot_source_id, "ocr_raw", "ocr_enhanced", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": visible_content_claim,
            }
        )
        claims.append(
            {
                "confidence": classification_claim_confidence if useful_lines else "low",
                "sources": ["window_metadata", "ocr_normalized", "layout_heuristics", "surface_classification_heuristics"],
                "inference_strength": "approximate",
                "text": consistency_text,
            }
        )
        limits.append("OCR normalization improves legibility but does not guarantee exact transcription of small text, punctuation, or stylized UI labels.")
        limits.append("Layout sections are heuristic regions derived from OCR geometry; they are useful structure hints, not pixel-perfect segmentation.")
        limits.append("The description only covers the captured target window, not hidden tabs, background windows, or content outside the frame.")
        limits.append("Surface classification is heuristic and can still be uncertain for mixed or unusually dense interfaces.")
        limits.append("Structured fields are heuristic extracts from visible text and metadata; they should support reasoning, not be treated as hidden-state certainty.")
        limits.append("Surface state bundles consolidate structured and contextual cues into a more usable state summary, but they remain heuristic and can stay partial.")

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
        "surface_classification": surface_profile,
        "selection_reason": selection.get("selection_reason"),
        "matched_window_count": selection.get("matched_window_count"),
        "requested": requested,
        "current_desktop": current_desktop,
        "registered_current_desktop_windows": summarize_windows(registered_current_desktop),
        "layout": layout,
        "useful_regions": useful_regions,
        "useful_lines": useful_lines,
        "structured_fields": structured_fields,
        "surface_state_bundle": surface_state_bundle,
        "readable_text": {
            "raw_excerpt": [str(item["text"]) for item in raw_lines[:8]],
            "enhanced_excerpt": [str(item["text"]) for item in enhanced_lines[:8]],
            "normalized_excerpt": normalized_excerpts,
            "normalized_lines_total": len(merged_lines),
            "prioritized_lines_total": len(useful_lines),
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
            "surface_classification_heuristics": "category inference and ranked useful lines/regions derived from metadata, OCR, and layout hints",
            "structured_fields_heuristics": "surface-specific field extraction derived from metadata, normalized OCR, useful lines, and useful regions",
            "contextual_refinement_heuristics": "context-aware refinement that distinguishes active, primary, secondary, visible, and historical candidates from the structured fields",
            "surface_state_bundle_heuristics": "surface-specific operational bundle that consolidates structured, fine, and contextual fields into an auditable state summary",
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
            {
                "id": "surface_classification_heuristics",
                "kind": "heuristic",
                "paths": [str(surface_profile_path)],
                "role": "surface category inference plus ranked useful lines and regions for the final description",
                "certainty": claim_confidence_from_surface(str(surface_profile["confidence"])),
                "notes": "This is an auditable heuristic layer built from metadata, OCR, and layout cues rather than hidden UI state.",
            },
            {
                "id": "structured_fields_heuristics",
                "kind": "heuristic",
                "paths": [str(structured_fields_path)],
                "role": "surface-specific structured field extraction built from metadata, OCR normalization, useful lines, and useful regions",
                "certainty": claim_confidence_from_surface(str(surface_profile["confidence"])),
                "notes": "Structured fields are approximate and intentionally leave gaps when the visible evidence is weak or ambiguous.",
            },
            {
                "id": "contextual_refinement_heuristics",
                "kind": "heuristic",
                "paths": [str(structured_fields_path)],
                "role": "contextual prioritization over fine fields to distinguish active, primary, secondary, visible, and historical candidates",
                "certainty": claim_confidence_from_surface(str(surface_profile["confidence"])),
                "notes": "Contextual refinements stay auditable and can remain empty when the visible evidence does not support a confident distinction.",
            },
            {
                "id": "surface_state_bundle_heuristics",
                "kind": "heuristic",
                "paths": [str(surface_state_bundle_path)],
                "role": "surface-specific operational bundle that consolidates structured, fine, and contextual fields into a compact auditable state view",
                "certainty": claim_confidence_from_surface(str(surface_profile["confidence"])),
                "notes": "The bundle improves usability by consolidating prior heuristics, but it remains approximate and intentionally partial when the visible evidence is weak.",
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
        "surface_profile": str(surface_profile_path),
        "structured_fields": str(structured_fields_path),
        "surface_state_bundle": str(surface_state_bundle_path),
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
        "surface_classification": description["surface_classification"],
        "useful_lines": description["useful_lines"],
        "useful_regions": description["useful_regions"],
        "structured_fields": description["structured_fields"],
        "surface_state_bundle": description["surface_state_bundle"],
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
        f"surface_category: {description['surface_classification']['category']}",
        f"surface_category_label: {description['surface_classification']['label']}",
        f"surface_category_confidence: {description['surface_classification']['confidence']}",
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
    summary_lines.append("useful_lines:")
    summary_lines.extend(
        f"- [{item['priority_kind']}/{item['section_role'] or 'unknown'}/{item['score']}] {item['text']}"
        for item in useful_lines[:8]
    )
    summary_lines.append("useful_regions:")
    summary_lines.extend(
        f"- [{item['role']}/{item['line_count']}] {item['label']} -> {item['reason']}"
        for item in useful_regions[:6]
    )
    summary_lines.append("structured_fields:")
    for field_name in structured_fields["attempted_fields"]:
        entries = structured_fields["fields"].get(field_name) or []
        if not entries:
            summary_lines.append(f"- {field_name}: (none)")
            continue
        summary_lines.append(
            f"- {field_name}: "
            + "; ".join(f"{entry['value']} [{entry['confidence']}]" for entry in entries[:3])
        )
    summary_lines.append("fine_fields:")
    for field_name in structured_fields["attempted_fine_fields"]:
        entries = structured_fields["fine_fields"].get(field_name) or []
        if not entries:
            summary_lines.append(f"- {field_name}: (none)")
            continue
        summary_lines.append(
            f"- {field_name}: "
            + "; ".join(f"{entry['value']} [{entry['confidence']}]" for entry in entries[:3])
        )
    summary_lines.append("contextual_refinements:")
    for field_name in structured_fields["attempted_contextual_refinements"]:
        entries = structured_fields["contextual_refinements"].get(field_name) or []
        if not entries:
            summary_lines.append(f"- {field_name}: (none)")
            continue
        summary_lines.append(
            f"- {field_name}: "
            + "; ".join(
                f"{entry['value']} [{entry['confidence']}/{entry.get('activity_state', 'unknown')}/{entry.get('priority', 'unknown')}]"
                for entry in entries[:3]
            )
        )
    summary_lines.append("surface_state_bundle:")
    for field_name in surface_state_bundle["attempted_fields"]:
        field_value = surface_state_bundle["fields"].get(field_name)
        if not field_value:
            summary_lines.append(f"- {field_name}: (none)")
            continue
        if isinstance(field_value, list):
            summary_lines.append(
                f"- {field_name}: "
                + "; ".join(
                    f"{entry['value']} [{entry['confidence']}/{entry.get('bundle_role', 'unknown')}]"
                    for entry in field_value[:3]
                )
            )
            continue
        summary_lines.append(
            f"- {field_name}: {field_value['value']} [{field_value['confidence']}/{field_value.get('bundle_role', 'unknown')}]"
        )
    summary_lines.append("limits:")
    summary_lines.extend(f"- {line}" for line in limits)
    summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
