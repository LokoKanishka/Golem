#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Uso:
  ./scripts/resolve_user_visible_destination.sh <desktop|downloads> [filename] [--json]
USAGE
}

target="${1:-}"
if [ -z "$target" ]; then
  usage
  exit 1
fi
shift || true

filename=""
output_json="0"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      output_json="1"
      ;;
    *)
      if [ -n "$filename" ]; then
        usage
        printf 'ERROR: argumento no soportado: %s\n' "$1" >&2
        exit 1
      fi
      filename="$1"
      ;;
  esac
  shift
done

python3 - "$target" "$filename" "$output_json" <<'PY'
import json
import os
import pathlib
import subprocess
import sys

target = sys.argv[1].strip().lower()
filename = sys.argv[2].strip()
output_json = sys.argv[3] == "1"

if target not in {"desktop", "downloads"}:
    print("ERROR: target invalido. Usar desktop o downloads", file=sys.stderr)
    raise SystemExit(1)

home = pathlib.Path.home()
forced_dir = os.environ.get("GOLEM_VISIBLE_DESTINATION_FORCE_DIR", "").strip()

target_map = {
    "desktop": {
        "xdg": "DESKTOP",
        "candidates": [
            ("Desktop", home / "Desktop"),
            ("Escritorio", home / "Escritorio"),
        ],
    },
    "downloads": {
        "xdg": "DOWNLOAD",
        "candidates": [
            ("Downloads", home / "Downloads"),
            ("Descargas", home / "Descargas"),
        ],
    },
}

payload = {
    "requested_target": target,
    "requested_filename": filename,
    "selected_label": "",
    "selected_source": "",
    "selected_directory": "",
    "absolute_directory": "",
    "resolved_path": "",
    "path_normalized": "",
    "resolution_reason": "",
    "candidates": [],
}

selected_path = None
selected_label = ""
selected_source = ""

def candidate_payload(label, path, source):
    return {
        "label": label,
        "path": str(path),
        "exists": path.exists(),
        "readable": os.access(path, os.R_OK),
        "writable": os.access(path, os.W_OK),
        "source": source,
    }

def usable_directory(path):
    return path.exists() and path.is_dir() and os.access(path, os.R_OK) and os.access(path, os.W_OK)

if forced_dir:
    forced_path = pathlib.Path(forced_dir).expanduser()
    payload["candidates"].append(candidate_payload("forced-dir", forced_path, "env"))
    if usable_directory(forced_path):
        selected_path = forced_path
        selected_label = forced_path.name or forced_path.as_posix()
        selected_source = "env"
        payload["resolution_reason"] = "selected forced visible destination from GOLEM_VISIBLE_DESTINATION_FORCE_DIR"

xdg_name = target_map[target]["xdg"]
xdg_dir = ""
try:
    xdg_cmd = subprocess.run(
        ["xdg-user-dir", xdg_name],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    xdg_dir = (xdg_cmd.stdout or "").strip()
except FileNotFoundError:
    xdg_dir = ""

if xdg_dir:
    path = pathlib.Path(xdg_dir).expanduser()
    payload["candidates"].append(candidate_payload(path.name or xdg_name.lower(), path, "xdg-user-dir"))
    if selected_path is None and usable_directory(path):
        selected_path = path
        selected_label = path.name or xdg_name.lower()
        selected_source = "xdg-user-dir"
        payload["resolution_reason"] = f"selected existing {target} directory from xdg-user-dir"

for label, path in target_map[target]["candidates"]:
    payload["candidates"].append(candidate_payload(label, path, "fallback"))
    if selected_path is None and usable_directory(path):
        selected_path = path
        selected_label = label
        selected_source = "fallback"
        payload["resolution_reason"] = f"selected first existing localized {target} directory fallback"

if selected_path is None:
    payload["resolution_reason"] = f"no readable and writable visible {target} directory could be resolved"
    if output_json:
      print(json.dumps(payload, ensure_ascii=True))
    else:
      print("# Visible Destination Resolution")
      print(f"requested_target: {target}")
      print("resolution_result: BLOCKED")
      print(f"resolution_reason: {payload['resolution_reason']}")
      print("candidate | path | exists | readable | writable | source")
      for candidate in payload["candidates"]:
          print(
              f"{candidate['label']} | {candidate['path']} | "
              f"{'yes' if candidate['exists'] else 'no'} | {'yes' if candidate['readable'] else 'no'} | "
              f"{'yes' if candidate['writable'] else 'no'} | {candidate['source']}"
          )
    raise SystemExit(2)

selected_path = selected_path.resolve()
resolved_path = selected_path / filename if filename else selected_path

payload["selected_label"] = selected_label
payload["selected_source"] = selected_source
payload["selected_directory"] = str(selected_path)
payload["absolute_directory"] = str(selected_path)
payload["resolved_path"] = str(resolved_path)
payload["path_normalized"] = str(resolved_path.resolve(strict=False))

if output_json:
    print(json.dumps(payload, ensure_ascii=True))
else:
    print("# Visible Destination Resolution")
    print(f"requested_target: {target}")
    print(f"selected_label: {selected_label}")
    print(f"selected_source: {selected_source}")
    print(f"absolute_directory: {payload['absolute_directory']}")
    if filename:
        print(f"resolved_path: {payload['resolved_path']}")
        print(f"path_normalized: {payload['path_normalized']}")
    print(f"resolution_reason: {payload['resolution_reason']}")
    print("candidate | path | exists | readable | writable | source")
    for candidate in payload["candidates"]:
        print(
            f"{candidate['label']} | {candidate['path']} | "
            f"{'yes' if candidate['exists'] else 'no'} | {'yes' if candidate['readable'] else 'no'} | "
            f"{'yes' if candidate['writable'] else 'no'} | {candidate['source']}"
        )
PY
