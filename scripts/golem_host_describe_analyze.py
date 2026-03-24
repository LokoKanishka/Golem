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
    fields: dict[str, list[dict[str, object]]] = {name: [] for name in attempted_fields}

    if category == "editor":
        fields = build_editor_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)
    elif category == "chat":
        fields = build_chat_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)
    elif category == "terminal":
        fields = build_terminal_structured_fields(surface_confidence, merged_lines, useful_lines)
    elif category == "browser-web-app":
        fields = build_browser_structured_fields(title, app, surface_confidence, merged_lines, useful_lines)

    empty_fields = [name for name in attempted_fields if not fields.get(name)]
    source_refs = {"structured_fields_heuristics", "surface_classification_heuristics"}
    if attempted_fields:
        source_refs.update({"ocr_normalized", "layout_heuristics"})
    if title:
        source_refs.add("window_metadata")

    return {
        "category": category,
        "label": label,
        "surface_confidence": surface_confidence,
        "attempted_fields": attempted_fields,
        "fields": fields,
        "empty_fields": empty_fields,
        "non_empty_fields": [name for name in attempted_fields if fields.get(name)],
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
    summary_lines.append("limits:")
    summary_lines.extend(f"- {line}" for line in limits)
    summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
