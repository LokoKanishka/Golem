#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/golem_browser_relay_common.sh"

OUTPUT_JSON="0"
if [ "${1:-}" = "--json" ]; then
  OUTPUT_JSON="1"
  shift
fi

selector="${1:-}"
if [ "$#" -gt 1 ]; then
  browser_relay_fail "uso: ./scripts/golem_browser_relay_read.sh [--json] [selector]"
fi

browser_relay_require_tools

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

snapshot_file="$tmp_dir/snapshot.txt"
snapshot_err_file="$tmp_dir/snapshot.err"
snapshot_exit=0
set +e
GOLEM_BROWSER_CDP_URL="$GOLEM_BROWSER_RELAY_URL" "$SCRIPT_DIR/browser_cdp_tool.sh" snapshot "$selector" >"$snapshot_file" 2>"$snapshot_err_file"
snapshot_exit="$?"
set -e

python3 - "$OUTPUT_JSON" "$snapshot_exit" "$selector" "$snapshot_file" "$snapshot_err_file" "$GOLEM_BROWSER_RELAY_URL" <<'PY'
import json
import pathlib
import sys

output_json, snapshot_exit, selector, snapshot_file, snapshot_err_file, relay_url = sys.argv[1:7]
snapshot_exit = int(snapshot_exit)

def read_text(path):
    p = pathlib.Path(path)
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

raw = read_text(snapshot_file)
err = read_text(snapshot_err_file).strip()

if snapshot_exit != 0:
    payload = {
        "ok": False,
        "relay_url": relay_url,
        "selector": selector,
        "error": err or raw.strip(),
    }
    if output_json == "1":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"relay_read: blocked")
        print(f"relay_url: {relay_url}")
        if selector:
            print(f"selector: {selector}")
        if payload["error"]:
            print(f"error: {payload['error']}")
        print("RELAY_READ_BLOCKED")
    raise SystemExit(1)

title = ""
url = ""
lines = []
mode = ""
for line in raw.splitlines():
    if line.startswith("title: "):
        title = line[len("title: "):]
    elif line.startswith("url: "):
        url = line[len("url: "):]
    elif line == "## Text":
        mode = "text"
    elif line.startswith("## "):
        mode = ""
    elif mode == "text" and line.startswith("- "):
        lines.append(line[2:])

payload = {
    "ok": True,
    "relay_url": relay_url,
    "selector": selector,
    "title": title,
    "url": url,
    "content_line_count": len(lines),
    "content_preview": lines[:5],
    "raw_snapshot": raw,
}

if output_json == "1":
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0)

print("relay_read: ok")
print(f"title: {title}")
print(f"url: {url}")
if selector:
    print(f"selector: {selector}")
print(f"content_line_count: {len(lines)}")
if lines:
    print(f"content_preview: {' | '.join(lines[:3])}")
else:
    print("content_preview: (sin texto visible)")
print("RELAY_READ_OK")
PY
