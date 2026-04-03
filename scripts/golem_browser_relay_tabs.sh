#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/golem_browser_relay_common.sh"

OUTPUT_JSON="0"
if [ "${1:-}" = "--json" ]; then
  OUTPUT_JSON="1"
  shift
fi
if [ "$#" -ne 0 ]; then
  browser_relay_fail "uso: ./scripts/golem_browser_relay_tabs.sh [--json]"
fi

browser_relay_require_tools

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tabs_file="$tmp_dir/tabs.json"
tabs_err_file="$tmp_dir/tabs.err"
tabs_exit=0
set +e
browser_relay_tabs_probe >"$tabs_file" 2>"$tabs_err_file"
tabs_exit="$?"
set -e

python3 - "$OUTPUT_JSON" "$tabs_exit" "$tabs_file" "$tabs_err_file" "$GOLEM_BROWSER_RELAY_URL" <<'PY'
import json
import pathlib
import sys

output_json, tabs_exit, tabs_file, tabs_err_file, relay_url = sys.argv[1:6]
tabs_exit = int(tabs_exit)

def read_text(path):
    p = pathlib.Path(path)
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace").strip()

if tabs_exit != 0:
    payload = {
        "ok": False,
        "relay_url": relay_url,
        "relay_state": "relay_down",
        "error": read_text(tabs_err_file),
        "tabs": [],
        "page_tabs": [],
        "attach_count": 0,
    }
    if output_json == "1":
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"relay_state: {payload['relay_state']}")
        print(f"relay_url: {payload['relay_url']}")
        print(f"attach_count: 0")
        if payload["error"]:
            print(f"error: {payload['error']}")
        print("RELAY_ATTACH_UNAVAILABLE")
    raise SystemExit(1)

payload = json.loads(read_text(tabs_file) or "[]")
page_tabs = [item for item in payload if isinstance(item, dict) and item.get("type") == "page"]
result = {
    "ok": True,
    "relay_url": relay_url,
    "relay_state": "relay_up_with_attach" if page_tabs else "relay_up_without_attach",
    "tabs": payload,
    "page_tabs": page_tabs,
    "attach_count": len(page_tabs),
}

if output_json == "1":
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0)

print(f"relay_state: {result['relay_state']}")
print(f"relay_url: {result['relay_url']}")
print(f"attach_count: {result['attach_count']}")
if not page_tabs:
    print("RELAY_ATTACH_NONE")
    raise SystemExit(0)

for index, item in enumerate(page_tabs):
    title = item.get("title") or "(sin titulo)"
    url = item.get("url") or "(sin url)"
    target_id = item.get("id") or item.get("targetId") or ""
    print(f"{index}. {title}")
    print(f"   url: {url}")
    print(f"   id: {target_id}")

print("RELAY_ATTACH_OK")
PY
