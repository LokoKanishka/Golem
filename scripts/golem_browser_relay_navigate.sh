#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/golem_browser_relay_common.sh"

OUTPUT_JSON="0"
TARGET_SELECTOR=""
NEW_TAB="0"

while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --json)
      OUTPUT_JSON="1"
      shift
      ;;
    --target)
      TARGET_SELECTOR="${2:-}"
      [ -n "$TARGET_SELECTOR" ] || browser_relay_fail "faltante --target"
      shift 2
      ;;
    --new-tab)
      NEW_TAB="1"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Uso:
  ./scripts/golem_browser_relay_navigate.sh [--json] [--target <selector>] <url>
  ./scripts/golem_browser_relay_navigate.sh [--json] --new-tab <url>

Convencion de target:
  - sin --target: usa la tab adjunta activa (ultima page tab adjunta)
  - --target <n>: indice de attached page tab
  - --target <sessionId|targetId>: identificador exacto
  - --target <texto>: match unico por title/url
  - --new-tab: abre una tab nueva y la adjunta en el relay
EOF
      exit 0
      ;;
    --*)
      browser_relay_fail "argumento no soportado: $1"
      ;;
    *)
      break
      ;;
  esac
done

URL="${1:-}"
if [ "$#" -ne 1 ] || [ -z "$URL" ]; then
  browser_relay_fail "uso: ./scripts/golem_browser_relay_navigate.sh [--json] [--target <selector>] [--new-tab] <url>"
fi

case "$URL" in
  http://*|https://*)
    ;;
  *)
    browser_relay_fail "la URL debe empezar con http:// o https://"
    ;;
esac

browser_relay_require_tools

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

result_file="$tmp_dir/navigate.json"
error_file="$tmp_dir/navigate.err"
navigate_exit=0

curl_args=(
  -fsS
  --max-time 15
  --get
  --data-urlencode "url=$URL"
)

if [ -n "$TARGET_SELECTOR" ]; then
  curl_args+=(--data-urlencode "selector=$TARGET_SELECTOR")
fi

if [ "$NEW_TAB" = "1" ]; then
  curl_args+=(--data "new_tab=1")
fi

set +e
curl "${curl_args[@]}" "${GOLEM_BROWSER_RELAY_URL}/admin/navigate" >"$result_file" 2>"$error_file"
navigate_exit="$?"
set -e

python3 - "$OUTPUT_JSON" "$navigate_exit" "$URL" "$TARGET_SELECTOR" "$NEW_TAB" "$result_file" "$error_file" "$GOLEM_BROWSER_RELAY_URL" <<'PY'
import json
import pathlib
import sys

output_json, navigate_exit, requested_url, target_selector, new_tab, result_file, error_file, relay_url = sys.argv[1:9]
navigate_exit = int(navigate_exit)

def read_text(path):
    p = pathlib.Path(path)
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace").strip()

raw = read_text(result_file)
err = read_text(error_file)
payload = {}
if raw:
    try:
        payload = json.loads(raw)
    except Exception:
        payload = {}

ok = navigate_exit == 0 and bool(payload.get("ok"))
result = {
    "ok": ok,
    "relay_url": relay_url,
    "requested_url": requested_url,
    "target_selector": target_selector,
    "new_tab": new_tab == "1",
    "action": str(payload.get("action") or ("open" if new_tab == "1" else "navigate")),
    "target_mode": str(payload.get("targetMode") or ""),
    "session_id": str(payload.get("sessionId") or ""),
    "target_id": str(payload.get("targetId") or ""),
    "title": str(payload.get("title") or ""),
    "url": str(payload.get("url") or ""),
    "attached": bool(payload.get("attached")),
    "error": str(payload.get("error") or err or raw or ""),
    "result": payload,
}

if output_json == "1":
    print(json.dumps(result, indent=2, sort_keys=True))
    raise SystemExit(0 if ok else 1)

if not ok:
    print("relay_navigate: blocked")
    print(f"relay_url: {relay_url}")
    print(f"requested_url: {requested_url}")
    if target_selector:
        print(f"target_selector: {target_selector}")
    print(f"new_tab: {'true' if result['new_tab'] else 'false'}")
    if result["error"]:
        print(f"error: {result['error']}")
    print("RELAY_NAVIGATE_BLOCKED")
    raise SystemExit(1)

print("relay_navigate: ok")
print(f"relay_url: {relay_url}")
print(f"action: {result['action']}")
print(f"target_mode: {result['target_mode']}")
print(f"requested_url: {requested_url}")
if target_selector:
    print(f"target_selector: {target_selector}")
print(f"resolved_target_id: {result['target_id']}")
print(f"resolved_session_id: {result['session_id']}")
print(f"resolved_title: {result['title']}")
print(f"resolved_url: {result['url']}")
print("RELAY_NAVIGATE_OK")
PY
