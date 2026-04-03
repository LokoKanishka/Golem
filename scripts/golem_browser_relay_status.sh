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
  browser_relay_fail "uso: ./scripts/golem_browser_relay_status.sh [--json]"
fi

browser_relay_require_tools
browser_relay_ensure_root
browser_relay_cleanup_stale_pidfile

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

gateway_file="$tmp_dir/gateway.json"
gateway_err_file="$tmp_dir/gateway.err"
version_file="$tmp_dir/version.json"
version_err_file="$tmp_dir/version.err"
tabs_file="$tmp_dir/tabs.json"
tabs_err_file="$tmp_dir/tabs.err"
browser_status_file="$tmp_dir/browser_status.json"
browser_status_err_file="$tmp_dir/browser_status.err"
port_probe_file="$tmp_dir/port_probe.txt"
port_probe_err_file="$tmp_dir/port_probe.err"
extension_manifest_file="$tmp_dir/extension_manifest.json"
extension_manifest_err_file="$tmp_dir/extension_manifest.err"

gateway_exit=0
version_exit=0
tabs_exit=0
browser_status_exit=0
port_probe_exit=0
extension_manifest_exit=0

set +e
browser_relay_gateway_probe >"$gateway_file" 2>"$gateway_err_file"
gateway_exit="$?"
browser_relay_version_probe >"$version_file" 2>"$version_err_file"
version_exit="$?"
browser_relay_tabs_probe >"$tabs_file" 2>"$tabs_err_file"
tabs_exit="$?"
browser_relay_port_probe >"$port_probe_file" 2>"$port_probe_err_file"
port_probe_exit="$?"
browser_relay_extension_manifest_probe >"$extension_manifest_file" 2>"$extension_manifest_err_file"
extension_manifest_exit="$?"
set -e

if [ "$gateway_exit" -eq 0 ]; then
  set +e
  openclaw browser --json --browser-profile "$GOLEM_BROWSER_RELAY_PROFILE" status >"$browser_status_file" 2>"$browser_status_err_file"
  browser_status_exit="$?"
  set -e
fi

python3 - "$OUTPUT_JSON" "$gateway_exit" "$version_exit" "$tabs_exit" "$browser_status_exit" \
  "$port_probe_exit" "$extension_manifest_exit" \
  "$gateway_file" "$gateway_err_file" "$version_file" "$version_err_file" "$tabs_file" "$tabs_err_file" \
  "$browser_status_file" "$browser_status_err_file" "$port_probe_file" "$port_probe_err_file" \
  "$extension_manifest_file" "$extension_manifest_err_file" \
  "$GOLEM_BROWSER_RELAY_HOST" "$GOLEM_BROWSER_RELAY_PORT" "$GOLEM_BROWSER_RELAY_URL" \
  "$GOLEM_BROWSER_RELAY_GATEWAY_URL" "$GOLEM_BROWSER_RELAY_PROFILE" \
  "$GOLEM_BROWSER_RELAY_PROFILE_DRIVER" "$GOLEM_BROWSER_RELAY_PROFILE_ATTACH_ONLY" \
  "$GOLEM_BROWSER_RELAY_PROFILE_USER_DATA_DIR" "$GOLEM_BROWSER_RELAY_CONFIG_PRESENT" \
  "$GOLEM_BROWSER_RELAY_CONFIG_DEFAULT_PROFILE" "$GOLEM_BROWSER_RELAY_SERVER_PIDFILE" \
  "$GOLEM_BROWSER_RELAY_SERVER_LOGFILE" "$GOLEM_BROWSER_RELAY_SERVICE_GATE_FILE" \
  "$GOLEM_BROWSER_RELAY_EXTENSION_PATH" "$GOLEM_BROWSER_RELAY_EXTENSION_MANIFEST_PATH" <<'PY'
import json
import pathlib
import sys

(
    output_json,
    gateway_exit,
    version_exit,
    tabs_exit,
    browser_status_exit,
    port_probe_exit,
    extension_manifest_exit,
    gateway_file,
    gateway_err_file,
    version_file,
    version_err_file,
    tabs_file,
    tabs_err_file,
    browser_status_file,
    browser_status_err_file,
    port_probe_file,
    port_probe_err_file,
    extension_manifest_file,
    extension_manifest_err_file,
    relay_host,
    relay_port,
    relay_url,
    gateway_url,
    browser_profile,
    profile_driver,
    profile_attach_only,
    profile_user_data_dir,
    config_present,
    config_default_profile,
    pidfile_path,
    logfile_path,
    service_gate_file,
    extension_path,
    extension_manifest_path,
) = sys.argv[1:35]

def read_text(path):
    p = pathlib.Path(path)
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace").strip()

def load_json(path):
    text = read_text(path)
    if not text:
        return None
    try:
        return json.loads(text)
    except Exception:
        return None

gateway_payload = load_json(gateway_file)
version_payload = load_json(version_file)
tabs_payload = load_json(tabs_file)
browser_status_payload = load_json(browser_status_file)
extension_manifest_payload = load_json(extension_manifest_file)

gateway_err = read_text(gateway_err_file)
version_err = read_text(version_err_file)
tabs_err = read_text(tabs_err_file)
browser_status_err = read_text(browser_status_err_file)
port_probe = read_text(port_probe_file)
port_probe_err = read_text(port_probe_err_file)
extension_manifest_err = read_text(extension_manifest_err_file)

gateway_targets = (gateway_payload or {}).get("targets") or []
gateway_target = gateway_targets[0] if gateway_targets else {}
gateway_connect = gateway_target.get("connect") or {}
gateway_reachable = bool(gateway_connect.get("ok") and gateway_connect.get("rpcOk"))
gateway_error = gateway_connect.get("error") or gateway_err

relay_reachable = int(version_exit) == 0 and isinstance(version_payload, dict)
relay_error = version_err or tabs_err

port_probe_lines = [line for line in port_probe.splitlines() if line.strip()]
relay_port_listener_present = False
if port_probe_lines:
    relay_port_listener_present = any(not line.startswith("State ") for line in port_probe_lines)

extension_dir_present = pathlib.Path(extension_path).is_dir()
extension_manifest_present = pathlib.Path(extension_manifest_path).is_file()
extension_installed = int(extension_manifest_exit) == 0 and isinstance(extension_manifest_payload, dict)
extension_error = extension_manifest_err
if not extension_error and not extension_manifest_present:
    extension_error = "extension manifest not found"

page_tabs = []
if isinstance(tabs_payload, list):
    for item in tabs_payload:
        if isinstance(item, dict) and item.get("type") == "page":
            page_tabs.append(item)

attach_count = len(page_tabs) if int(tabs_exit) == 0 else 0
active_tab = page_tabs[-1] if page_tabs else {}

if relay_reachable and attach_count > 0:
    relay_state = "relay_up_with_attach"
    diagnosis = "relay browser reachable with at least one attached page tab"
elif relay_reachable:
    relay_state = "relay_up_without_attach"
    diagnosis = "relay browser reachable but no attached page tab is exposed"
else:
    relay_state = "relay_down"
    if relay_port_listener_present:
        diagnosis = "a listener exists on the relay port but it is not serving the expected CDP relay surface"
    elif gateway_reachable and extension_installed:
        diagnosis = "extension installed and gateway reachable, but the relay port is not reachable"
    elif extension_installed:
        diagnosis = "extension installed but both gateway and relay are unavailable from the current probe"
    elif gateway_reachable:
        diagnosis = "gateway responds but the browser relay port is not reachable"
    else:
        diagnosis = "gateway and relay are both unavailable from the current probe"

pidfile = pathlib.Path(pidfile_path)
managed_pid = ""
managed_running = False
if pidfile.exists():
    managed_pid = pidfile.read_text(encoding="utf-8", errors="replace").strip()
    if managed_pid.isdigit():
        managed_running = pathlib.Path(f"/proc/{managed_pid}").exists()

if managed_running:
    control_mode = "repo-managed"
elif gateway_reachable:
    control_mode = "external"
else:
    control_mode = "none"

service_gate_present = pathlib.Path(service_gate_file).exists()

payload = {
    "relay_state": relay_state,
    "relay_reachable": relay_reachable,
    "relay_attach_count": attach_count,
    "relay_host": relay_host,
    "relay_port": int(relay_port),
    "relay_url": relay_url,
    "relay_port_listener_present": relay_port_listener_present,
    "relay_port_probe": port_probe,
    "relay_port_probe_error": port_probe_err,
    "relay_error": relay_error,
    "relay_version": version_payload or None,
    "gateway_reachable": gateway_reachable,
    "gateway_url": gateway_url,
    "gateway_error": gateway_error,
    "gateway_probe": gateway_payload or None,
    "browser_profile": browser_profile,
    "profile_driver": profile_driver,
    "profile_attach_only": profile_attach_only == "true",
    "profile_user_data_dir": profile_user_data_dir,
    "config_present": config_present == "true",
    "config_default_profile": config_default_profile,
    "browser_status_available": int(browser_status_exit) == 0 and browser_status_payload is not None,
    "browser_status": browser_status_payload,
    "browser_status_error": browser_status_err,
    "extension_installed": extension_installed,
    "extension_dir_present": extension_dir_present,
    "extension_path": extension_path,
    "extension_manifest_present": extension_manifest_present,
    "extension_manifest_path": extension_manifest_path,
    "extension_name": (extension_manifest_payload or {}).get("name") or "",
    "extension_version": (extension_manifest_payload or {}).get("version") or "",
    "extension_error": extension_error,
    "control_mode": control_mode,
    "repo_managed_relay_pid": managed_pid,
    "repo_managed_relay_log": logfile_path,
    "service_gate_file": service_gate_file,
    "service_gate_present": service_gate_present,
    "active_tab_title": active_tab.get("title") or "",
    "active_tab_url": active_tab.get("url") or "",
    "active_tab_id": active_tab.get("id") or active_tab.get("targetId") or "",
    "diagnosis": diagnosis,
}

if output_json == "1":
    print(json.dumps(payload, indent=2, sort_keys=True))
    raise SystemExit(0 if relay_reachable else 1)

print(f"relay_state: {payload['relay_state']}")
print(f"relay_reachable: {'true' if payload['relay_reachable'] else 'false'}")
print(f"relay_host: {payload['relay_host']}")
print(f"relay_port: {payload['relay_port']}")
print(f"relay_url: {payload['relay_url']}")
print(f"relay_port_listener_present: {'true' if payload['relay_port_listener_present'] else 'false'}")
print(f"relay_attach_count: {payload['relay_attach_count']}")
print(f"active_tab_title: {payload['active_tab_title']}")
print(f"active_tab_url: {payload['active_tab_url']}")
print(f"gateway_reachable: {'true' if payload['gateway_reachable'] else 'false'}")
print(f"extension_installed: {'true' if payload['extension_installed'] else 'false'}")
print(f"extension_name: {payload['extension_name'] or '(unknown)'}")
print(f"extension_version: {payload['extension_version'] or '(unknown)'}")
print(f"browser_profile: {payload['browser_profile']}")
print(f"profile_driver: {payload['profile_driver'] or '(unknown)'}")
print(f"profile_attach_only: {'true' if payload['profile_attach_only'] else 'false'}")
print(f"control_mode: {payload['control_mode']}")
print(f"service_gate_present: {'true' if payload['service_gate_present'] else 'false'}")
print(f"diagnosis: {payload['diagnosis']}")
if payload["relay_error"]:
    print(f"relay_error: {payload['relay_error']}")
if payload["relay_port_probe"]:
    print(f"relay_port_probe: {payload['relay_port_probe']}")
if payload["gateway_error"]:
    print(f"gateway_error: {payload['gateway_error']}")
if payload["extension_error"]:
    print(f"extension_error: {payload['extension_error']}")
print("RELAY_STATUS_" + ("UP" if relay_reachable else "DOWN"))
raise SystemExit(0 if relay_reachable else 1)
PY
