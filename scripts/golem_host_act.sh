#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/golem_host_capability_common.sh
source "${SCRIPT_DIR}/golem_host_capability_common.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/golem_host_act.sh command --label <label> -- <command...> [--json]
  ./scripts/golem_host_act.sh open --label <label> -- <command...> [--json]
  ./scripts/golem_host_act.sh wait-window --title <substring> [--timeout seconds] [--json]
  ./scripts/golem_host_act.sh focus (--title <substring> | --window-id <id>) [--json]
  ./scripts/golem_host_act.sh type --text <text> [--delay ms] [--window-id <id>] [--json]
  ./scripts/golem_host_act.sh key --key <keyspec> [--window-id <id>] [--json]
  ./scripts/golem_host_act.sh path
  ./scripts/golem_host_act.sh json

Env overrides:
  GOLEM_HOST_CAPABILITIES_ROOT
EOF
}

emit_run() {
  local format="$1"
  local run_dir="$2"
  golem_host_capabilities_emit "$format" "${run_dir}/summary.txt" "${run_dir}/manifest.json" "GOLEM HOST ACTION"
}

latest() {
  local run_dir
  run_dir="$(golem_host_capabilities_latest_dir act)"
  [ -n "$run_dir" ] || {
    printf 'FAIL: no host action runs found under %s\n' "$GOLEM_HOST_CAPABILITIES_ROOT" >&2
    exit 1
  }
  emit_run "$1" "$run_dir"
}

write_manifest() {
  python3 - "$@" <<'PY'
import json
import pathlib
import sys

run_dir = pathlib.Path(sys.argv[1])
summary_path = pathlib.Path(sys.argv[2])
manifest_path = pathlib.Path(sys.argv[3])
payload = json.loads(sys.argv[4])

summary_lines = [
    "GOLEM HOST ACTION",
    "",
]
for key, value in payload.get("summary_pairs", []):
    summary_lines.append(f"{key}: {value}")
summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

manifest = payload["manifest"]
manifest["run_dir"] = str(run_dir)
manifest["artifacts"] = manifest.get("artifacts", {})
manifest["artifacts"]["summary"] = str(summary_path)
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY
}

parse_wait_window() {
  python3 - "$@" <<'PY'
import json
import subprocess
import sys
import time

title = sys.argv[1]
timeout = float(sys.argv[2])

def collect_wmctrl_matches(title_value):
    result = subprocess.run(["wmctrl", "-lp"], text=True, capture_output=True, check=False)
    matches_local = []
    for line in result.stdout.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5:
            continue
        window_id, desktop, pid, host, window_title = parts
        if title_value in window_title:
            matches_local.append(
                {
                    "window_id": window_id,
                    "desktop": desktop,
                    "pid": pid,
                    "host": host,
                    "title": window_title,
                    "source": "wmctrl",
                }
            )
    return matches_local

def collect_xdotool_matches(title_value):
    search = subprocess.run(["xdotool", "search", "--name", title_value], text=True, capture_output=True, check=False)
    matches_local = []
    for raw_window_id in search.stdout.splitlines():
        window_id = raw_window_id.strip()
        if not window_id:
            continue
        name_result = subprocess.run(["xdotool", "getwindowname", window_id], text=True, capture_output=True, check=False)
        window_title = name_result.stdout.strip()
        if title_value not in window_title:
            continue
        pid_result = subprocess.run(["xdotool", "getwindowpid", window_id], text=True, capture_output=True, check=False)
        matches_local.append(
            {
                "window_id": window_id,
                "desktop": "",
                "pid": pid_result.stdout.strip(),
                "host": "",
                "title": window_title,
                "source": "xdotool",
            }
        )
    return matches_local

deadline = time.time() + timeout
matches = []
while time.time() < deadline:
    matches = collect_wmctrl_matches(title)
    if not matches:
        matches = collect_xdotool_matches(title)
    if matches:
        print(json.dumps(matches[0], ensure_ascii=True))
        sys.exit(0)
    time.sleep(0.2)

sys.exit(1)
PY
}

capture_active_window() {
  local id title
  id="$(xdotool getactivewindow 2>/dev/null || true)"
  title=""
  if [ -n "$id" ]; then
    title="$(xdotool getwindowname "$id" 2>/dev/null || true)"
  fi
  python3 - "$id" "$title" <<'PY'
import json
import sys
print(json.dumps({"window_id": sys.argv[1], "title": sys.argv[2]}, ensure_ascii=True))
PY
}

main() {
  local mode="${1:-}"
  local format="text"

  [ -n "$mode" ] || {
    usage >&2
    exit 2
  }

  case "$mode" in
    path)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest path
      return 0
      ;;
    json)
      [ "$#" -eq 1 ] || { usage >&2; exit 2; }
      latest json
      return 0
      ;;
  esac

  shift
  if [ "${!#:-}" = "--json" ]; then
    format="json"
    set -- "${@:1:$(($#-1))}"
  fi

  local run_dir summary_path manifest_path
  run_dir="$(golem_host_capabilities_create_dir act)"
  summary_path="${run_dir}/summary.txt"
  manifest_path="${run_dir}/manifest.json"

  case "$mode" in
    command)
      local label="${1:-}" stdout_path stderr_path exit_code payload_json
      [ "$label" = "--label" ] || { usage >&2; exit 2; }
      shift
      label="${1:-}"
      shift
      [ "${1:-}" = "--" ] || { usage >&2; exit 2; }
      shift
      [ "$#" -gt 0 ] || { usage >&2; exit 2; }
      stdout_path="${run_dir}/stdout.txt"
      stderr_path="${run_dir}/stderr.txt"
      set +e
      "$@" >"$stdout_path" 2>"$stderr_path"
      exit_code=$?
      set -e
      payload_json="$(python3 - "$label" "$exit_code" "$stdout_path" "$stderr_path" "$*" <<'PY'
import json
import pathlib
import sys

label = sys.argv[1]
exit_code = int(sys.argv[2])
stdout_path = pathlib.Path(sys.argv[3])
stderr_path = pathlib.Path(sys.argv[4])
command = sys.argv[5]
stdout = stdout_path.read_text(encoding="utf-8")

payload = {
    "summary_pairs": [
        ["action", "command"],
        ["label", label],
        ["exit_code", str(exit_code)],
        ["command", command],
        ["stdout_excerpt", stdout.strip() or "(none)"],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "command",
        "label": label,
        "exit_code": exit_code,
        "command": command,
        "stdout_excerpt": stdout.strip(),
        "artifacts": {
            "stdout": str(stdout_path),
            "stderr": str(stderr_path),
        },
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      [ "$exit_code" -eq 0 ] || {
        emit_run "$format" "$run_dir"
        exit "$exit_code"
      }
      ;;
    open)
      local label="${1:-}" stdout_path stderr_path pid payload_json command_display
      [ "$label" = "--label" ] || { usage >&2; exit 2; }
      shift
      label="${1:-}"
      shift
      [ "${1:-}" = "--" ] || { usage >&2; exit 2; }
      shift
      [ "$#" -gt 0 ] || { usage >&2; exit 2; }
      golem_host_capabilities_require_tools nohup
      stdout_path="${run_dir}/stdout.txt"
      stderr_path="${run_dir}/stderr.txt"
      command_display="$*"
      nohup "$@" >"$stdout_path" 2>"$stderr_path" &
      pid="$!"
      payload_json="$(python3 - "$label" "$pid" "$stdout_path" "$stderr_path" "$command_display" <<'PY'
import json
import sys

payload = {
    "summary_pairs": [
        ["action", "open"],
        ["label", sys.argv[1]],
        ["pid", sys.argv[2]],
        ["command", sys.argv[5]],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "open",
        "label": sys.argv[1],
        "pid": int(sys.argv[2]),
        "command": sys.argv[5],
        "artifacts": {
            "stdout": sys.argv[3],
            "stderr": sys.argv[4],
        },
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      ;;
    wait-window)
      local title="" timeout="10" match_json payload_json
      golem_host_capabilities_require_tools wmctrl xdotool python3
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --title)
            title="${2:-}"
            shift 2
            ;;
          --timeout)
            timeout="${2:-}"
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done
      [ -n "$title" ] || { usage >&2; exit 2; }
      match_json="$(parse_wait_window "$title" "$timeout")" || {
        printf 'FAIL: window with title containing "%s" was not found within %ss\n' "$title" "$timeout" >&2
        exit 1
      }
      payload_json="$(python3 - "$title" "$timeout" "$match_json" <<'PY'
import json
import sys

match = json.loads(sys.argv[3])
payload = {
    "summary_pairs": [
        ["action", "wait-window"],
        ["title_match", sys.argv[1]],
        ["window_id", match.get("window_id", "")],
        ["window_title", match.get("title", "")],
        ["timeout_seconds", sys.argv[2]],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "wait-window",
        "title_match": sys.argv[1],
        "timeout_seconds": float(sys.argv[2]),
        "window": match,
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      ;;
    focus)
      local title="" window_id="" before_json after_json payload_json
      local focus_attempt=0 active_after_window_id="" active_after_title=""
      golem_host_capabilities_require_tools wmctrl xdotool python3
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --title)
            title="${2:-}"
            shift 2
            ;;
          --window-id)
            window_id="${2:-}"
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done
      if [ -n "$title" ]; then
        window_id="$(parse_wait_window "$title" "1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["window_id"])')"
      fi
      [ -n "$window_id" ] || { usage >&2; exit 2; }
      before_json="$(capture_active_window)"
      for focus_attempt in $(seq 1 20); do
        wmctrl -i -a "$window_id" >/dev/null 2>&1 || true
        xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
        xdotool windowfocus --sync "$window_id" >/dev/null 2>&1 || true
        after_json="$(capture_active_window)"
        readarray -t focus_meta < <(python3 - "$after_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
print(payload.get("window_id", ""))
print(payload.get("title", ""))
PY
)
        active_after_window_id="${focus_meta[0]}"
        active_after_title="${focus_meta[1]}"
        if [ "$active_after_window_id" = "$window_id" ]; then
          break
        fi
        if [ -n "$title" ] && [ "$active_after_title" = "$title" ]; then
          break
        fi
        sleep 0.1
      done
      payload_json="$(python3 - "$window_id" "$before_json" "$after_json" "$title" <<'PY'
import json
import sys

payload = {
    "summary_pairs": [
        ["action", "focus"],
        ["window_id", sys.argv[1]],
        ["title_match", sys.argv[4] or "(none)"],
        ["before_active", json.loads(sys.argv[2]).get("title", "") or "(none)"],
        ["after_active", json.loads(sys.argv[3]).get("title", "") or "(none)"],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "focus",
        "window_id": sys.argv[1],
        "title_match": sys.argv[4],
        "before_active_window": json.loads(sys.argv[2]),
        "after_active_window": json.loads(sys.argv[3]),
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      ;;
    type)
      local text="" delay="20" window_id="" before_json after_json payload_json
      golem_host_capabilities_require_tools xdotool python3
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --text)
            text="${2:-}"
            shift 2
            ;;
          --delay)
            delay="${2:-}"
            shift 2
            ;;
          --window-id)
            window_id="${2:-}"
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done
      [ -n "$text" ] || { usage >&2; exit 2; }
      before_json="$(capture_active_window)"
      if [ -n "$window_id" ]; then
        wmctrl -i -a "$window_id" >/dev/null 2>&1 || true
        xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
        xdotool windowfocus --sync "$window_id" >/dev/null 2>&1 || true
        sleep 0.2
        xdotool type --clearmodifiers --delay "$delay" -- "$text" >/dev/null 2>&1
      else
        xdotool type --clearmodifiers --delay "$delay" -- "$text" >/dev/null 2>&1
      fi
      after_json="$(capture_active_window)"
      payload_json="$(python3 - "$text" "$delay" "$before_json" "$after_json" "$window_id" <<'PY'
import json
import sys

payload = {
    "summary_pairs": [
        ["action", "type"],
        ["text", sys.argv[1]],
        ["delay_ms", sys.argv[2]],
        ["window_id", sys.argv[5] or "(active-window)"],
        ["active_window", json.loads(sys.argv[4]).get("title", "") or "(none)"],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "type",
        "text": sys.argv[1],
        "delay_ms": int(sys.argv[2]),
        "window_id": sys.argv[5],
        "before_active_window": json.loads(sys.argv[3]),
        "after_active_window": json.loads(sys.argv[4]),
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      ;;
    key)
      local keyspec="" window_id="" before_json after_json payload_json
      golem_host_capabilities_require_tools xdotool python3
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --key)
            keyspec="${2:-}"
            shift 2
            ;;
          --window-id)
            window_id="${2:-}"
            shift 2
            ;;
          *)
            usage >&2
            exit 2
            ;;
        esac
      done
      [ -n "$keyspec" ] || { usage >&2; exit 2; }
      before_json="$(capture_active_window)"
      if [ -n "$window_id" ]; then
        wmctrl -i -a "$window_id" >/dev/null 2>&1 || true
        xdotool windowactivate --sync "$window_id" >/dev/null 2>&1 || true
        xdotool windowfocus --sync "$window_id" >/dev/null 2>&1 || true
        sleep 0.2
        xdotool key --clearmodifiers "$keyspec" >/dev/null 2>&1
      else
        xdotool key --clearmodifiers "$keyspec" >/dev/null 2>&1
      fi
      after_json="$(capture_active_window)"
      payload_json="$(python3 - "$keyspec" "$before_json" "$after_json" "$window_id" <<'PY'
import json
import sys

payload = {
    "summary_pairs": [
        ["action", "key"],
        ["key", sys.argv[1]],
        ["window_id", sys.argv[4] or "(active-window)"],
        ["before_active", json.loads(sys.argv[2]).get("title", "") or "(none)"],
        ["after_active", json.loads(sys.argv[3]).get("title", "") or "(none)"],
    ],
    "manifest": {
        "kind": "golem_host_act",
        "action": "key",
        "key": sys.argv[1],
        "window_id": sys.argv[4],
        "before_active_window": json.loads(sys.argv[2]),
        "after_active_window": json.loads(sys.argv[3]),
    },
}
print(json.dumps(payload, ensure_ascii=True))
PY
)"
      write_manifest "$run_dir" "$summary_path" "$manifest_path" "$payload_json"
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  emit_run "$format" "$run_dir"
}

main "$@"
