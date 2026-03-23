#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from typing import Dict, Optional


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME_SCRIPT = REPO_ROOT / "scripts" / "task_whatsapp_bridge_runtime.py"
DEFAULT_BASE_URL = "http://127.0.0.1:8765"
DEFAULT_PID_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime.pid"
DEFAULT_LOG_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime.log"
DEFAULT_STATE_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_state.json"
DEFAULT_RUNTIME_STATUS_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_runtime.json"
DEFAULT_AUDIT_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_audit.jsonl"


def ensure_parent(path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def read_json(path: pathlib.Path) -> Dict[str, object]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    if isinstance(data, dict):
        return data
    return {}


def read_pid(pid_file: pathlib.Path) -> int:
    if not pid_file.exists():
        return 0
    try:
        return int(pid_file.read_text(encoding="utf-8").strip())
    except Exception:
        return 0


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def remove_pid_file(pid_file: pathlib.Path) -> None:
    if pid_file.exists():
        pid_file.unlink()


def fetch_api_summary(base_url: str, timeout: float) -> Optional[Dict[str, object]]:
    url = base_url.rstrip("/") + "/tasks/summary"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
            if isinstance(payload, dict):
                return payload
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return None
    return None


def build_runtime_command(args: argparse.Namespace) -> list[str]:
    command = [
        sys.executable,
        str(RUNTIME_SCRIPT),
        "--base-url",
        args.base_url,
        "--state-file",
        str(args.state_file),
        "--runtime-status-file",
        str(args.runtime_status_file),
        "--live-restart-delay",
        str(args.live_restart_delay),
    ]
    if args.audit_file is not None:
        command.extend(["--audit-file", str(args.audit_file)])
    if args.log_command:
        command.extend(["--log-command", args.log_command])
    if args.replay_file is not None:
        command.extend(["--replay-file", str(args.replay_file)])
    if args.send_dry_run:
        command.append("--send-dry-run")
    return command


def read_status_snapshot(args: argparse.Namespace) -> Dict[str, object]:
    pid = read_pid(args.pid_file)
    runtime = read_json(args.runtime_status_file)
    api_summary = fetch_api_summary(args.base_url, timeout=args.api_timeout)
    snapshot = {
        "pid_file": str(args.pid_file),
        "pid": pid,
        "running": pid_alive(pid),
        "log_file": str(args.log_file),
        "runtime_status_file": str(args.runtime_status_file),
        "state_file": str(args.state_file),
        "audit_file": str(args.audit_file) if args.audit_file is not None else "",
        "base_url": args.base_url,
        "runtime": runtime,
        "api_ready": api_summary is not None,
        "api_summary_total": api_summary.get("total") if isinstance(api_summary, dict) else None,
    }
    if pid and not snapshot["running"]:
        snapshot["stale_pid"] = True
    else:
        snapshot["stale_pid"] = False
    return snapshot


def print_status(snapshot: Dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(snapshot, ensure_ascii=True, indent=2))
        return
    runtime = snapshot.get("runtime", {})
    if not isinstance(runtime, dict):
        runtime = {}
    print(f"bridge_running: {'yes' if snapshot.get('running') else 'no'}")
    print(f"pid: {snapshot.get('pid') or '(none)'}")
    print(f"stale_pid: {'yes' if snapshot.get('stale_pid') else 'no'}")
    print(f"bridge_status: {runtime.get('status', '(none)')}")
    print(f"api_ready: {'yes' if snapshot.get('api_ready') else 'no'}")
    print(f"handled_count: {runtime.get('handled_count', 0)}")
    print(f"ignored_count: {runtime.get('ignored_count', 0)}")
    print(f"error_count: {runtime.get('error_count', 0)}")
    print(f"restart_count: {runtime.get('restart_count', 0)}")
    print(f"last_operation: {runtime.get('last_operation', '(none)')}")
    print(f"last_error: {runtime.get('last_error', '(none)') or '(none)'}")
    print(f"last_heartbeat_at: {runtime.get('last_heartbeat_at', '(none)')}")
    print(f"log_file: {snapshot.get('log_file')}")


def wait_for_runtime_status(path: pathlib.Path, timeout: float) -> Dict[str, object]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = read_json(path)
        if data.get("status") == "running":
            return data
        time.sleep(0.2)
    return read_json(path)


def command_start(args: argparse.Namespace) -> int:
    pid = read_pid(args.pid_file)
    if pid_alive(pid):
        print(f"bridge already running with pid {pid}", file=sys.stderr)
        return 1
    if pid and not pid_alive(pid):
        remove_pid_file(args.pid_file)

    api_summary = fetch_api_summary(args.base_url, timeout=args.api_timeout)
    if api_summary is None:
        print("FAIL: local task API is not ready", file=sys.stderr)
        return 1

    ensure_parent(args.pid_file)
    ensure_parent(args.log_file)
    ensure_parent(args.runtime_status_file)
    ensure_parent(args.state_file)
    if args.audit_file is not None:
        ensure_parent(args.audit_file)

    command = build_runtime_command(args)
    with args.log_file.open("a", encoding="utf-8") as handle:
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=handle,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            text=True,
        )

    args.pid_file.write_text(f"{process.pid}\n", encoding="utf-8")
    runtime = wait_for_runtime_status(args.runtime_status_file, args.start_timeout)
    if not pid_alive(process.pid):
        print("FAIL: bridge process exited during startup", file=sys.stderr)
        remove_pid_file(args.pid_file)
        return 1
    if runtime.get("status") != "running":
        try:
            os.kill(process.pid, signal.SIGTERM)
        except OSError:
            pass
        print("FAIL: bridge did not report running status", file=sys.stderr)
        return 1

    print(f"TASK_WHATSAPP_BRIDGE_STARTED pid={process.pid}")
    return 0


def command_stop(args: argparse.Namespace) -> int:
    pid = read_pid(args.pid_file)
    if pid <= 0:
        print("TASK_WHATSAPP_BRIDGE_STOPPED already_not_running")
        return 0
    if not pid_alive(pid):
        remove_pid_file(args.pid_file)
        print("TASK_WHATSAPP_BRIDGE_STOPPED stale_pid_removed")
        return 0

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + args.stop_timeout
    while time.time() < deadline:
        if not pid_alive(pid):
            remove_pid_file(args.pid_file)
            print(f"TASK_WHATSAPP_BRIDGE_STOPPED pid={pid}")
            return 0
        time.sleep(0.2)

    os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 5
    while time.time() < deadline:
        if not pid_alive(pid):
            remove_pid_file(args.pid_file)
            print(f"TASK_WHATSAPP_BRIDGE_STOPPED pid={pid} killed=yes")
            return 0
        time.sleep(0.2)

    print(f"FAIL: bridge pid {pid} did not stop", file=sys.stderr)
    return 1


def command_status(args: argparse.Namespace) -> int:
    snapshot = read_status_snapshot(args)
    if snapshot.get("stale_pid"):
        remove_pid_file(args.pid_file)
    print_status(snapshot, args.json)
    return 0


def command_healthcheck(args: argparse.Namespace) -> int:
    snapshot = read_status_snapshot(args)
    runtime = snapshot.get("runtime", {})
    if not isinstance(runtime, dict):
        runtime = {}

    healthy = True
    reasons = []

    if not snapshot.get("running"):
        healthy = False
        reasons.append("bridge_not_running")
    if runtime.get("status") != "running":
        healthy = False
        reasons.append("runtime_not_running")
    if not snapshot.get("api_ready"):
        healthy = False
        reasons.append("api_not_ready")

    heartbeat = runtime.get("last_heartbeat_at")
    if isinstance(heartbeat, str) and heartbeat:
        try:
            dt = datetime_from_iso(heartbeat)
            age = time.time() - dt
            snapshot["heartbeat_age_seconds"] = round(age, 2)
            if age > args.max_heartbeat_age:
                healthy = False
                reasons.append("heartbeat_stale")
        except ValueError:
            healthy = False
            reasons.append("heartbeat_invalid")
    else:
        healthy = False
        reasons.append("heartbeat_missing")

    snapshot["healthy"] = healthy
    snapshot["reasons"] = reasons
    print_status(snapshot, args.json)
    return 0 if healthy else 1


def datetime_from_iso(value: str) -> float:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized).timestamp()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Operational control surface for the WhatsApp runtime bridge.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common_flags(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--base-url", default=DEFAULT_BASE_URL)
        subparser.add_argument("--pid-file", type=pathlib.Path, default=DEFAULT_PID_FILE)
        subparser.add_argument("--log-file", type=pathlib.Path, default=DEFAULT_LOG_FILE)
        subparser.add_argument("--state-file", type=pathlib.Path, default=DEFAULT_STATE_FILE)
        subparser.add_argument("--runtime-status-file", type=pathlib.Path, default=DEFAULT_RUNTIME_STATUS_FILE)
        subparser.add_argument("--audit-file", type=pathlib.Path, default=DEFAULT_AUDIT_FILE)
        subparser.add_argument("--api-timeout", type=float, default=2.0)

    start = subparsers.add_parser("start")
    add_common_flags(start)
    start.add_argument("--log-command", default="openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000")
    start.add_argument("--replay-file", type=pathlib.Path)
    start.add_argument("--send-dry-run", action="store_true")
    start.add_argument("--live-restart-delay", type=float, default=2.0)
    start.add_argument("--start-timeout", type=float, default=10.0)
    start.set_defaults(func=command_start)

    stop = subparsers.add_parser("stop")
    add_common_flags(stop)
    stop.add_argument("--stop-timeout", type=float, default=10.0)
    stop.set_defaults(func=command_stop)

    status = subparsers.add_parser("status")
    add_common_flags(status)
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=command_status)

    healthcheck = subparsers.add_parser("healthcheck")
    add_common_flags(healthcheck)
    healthcheck.add_argument("--json", action="store_true")
    healthcheck.add_argument("--max-heartbeat-age", type=float, default=15.0)
    healthcheck.set_defaults(func=command_healthcheck)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
