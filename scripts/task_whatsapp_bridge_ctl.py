#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import shlex
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
DEFAULT_SERVICE_NAME = "golem-whatsapp-bridge.service"
DEFAULT_SERVICE_UNIT_PATH = pathlib.Path.home() / ".config" / "systemd" / "user" / DEFAULT_SERVICE_NAME
SERVICE_TEMPLATE_PATH = REPO_ROOT / "config" / "systemd-user" / "golem-whatsapp-bridge.service.template"

SERVICE_ENV_BASE_URL = "TASK_WHATSAPP_BRIDGE_BASE_URL"
SERVICE_ENV_STATE_FILE = "TASK_WHATSAPP_BRIDGE_STATE_FILE"
SERVICE_ENV_RUNTIME_STATUS_FILE = "TASK_WHATSAPP_BRIDGE_RUNTIME_STATUS_FILE"
SERVICE_ENV_AUDIT_FILE = "TASK_WHATSAPP_BRIDGE_AUDIT_FILE"
SERVICE_ENV_LOG_COMMAND = "TASK_WHATSAPP_BRIDGE_LOG_COMMAND"
SERVICE_ENV_LIVE_RESTART_DELAY = "TASK_WHATSAPP_BRIDGE_LIVE_RESTART_DELAY"
SERVICE_ENV_SEND_DRY_RUN = "TASK_WHATSAPP_BRIDGE_SEND_DRY_RUN"


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


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


def systemd_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_service_unit(args: argparse.Namespace) -> str:
    if not SERVICE_TEMPLATE_PATH.exists():
        raise FileNotFoundError(f"missing service template: {SERVICE_TEMPLATE_PATH}")

    template = SERVICE_TEMPLATE_PATH.read_text(encoding="utf-8")
    values = {
        "description": "Golem WhatsApp Task Bridge",
        "repo_root": str(REPO_ROOT),
        "python_executable": shlex.quote(sys.executable),
        "ctl_script": shlex.quote(str(pathlib.Path(__file__).resolve())),
        "home": systemd_quote(str(pathlib.Path.home())),
        "path": systemd_quote(os.environ.get("PATH", "")),
        "base_url": systemd_quote(args.base_url),
        "state_file": systemd_quote(str(args.state_file)),
        "runtime_status_file": systemd_quote(str(args.runtime_status_file)),
        "audit_file": systemd_quote(str(args.audit_file)) if args.audit_file is not None else systemd_quote(""),
        "log_command": systemd_quote(args.log_command),
        "live_restart_delay": systemd_quote(str(args.live_restart_delay)),
        "send_dry_run": systemd_quote("1" if args.send_dry_run else "0"),
        "base_url_env": SERVICE_ENV_BASE_URL,
        "state_file_env": SERVICE_ENV_STATE_FILE,
        "runtime_status_file_env": SERVICE_ENV_RUNTIME_STATUS_FILE,
        "audit_file_env": SERVICE_ENV_AUDIT_FILE,
        "log_command_env": SERVICE_ENV_LOG_COMMAND,
        "live_restart_delay_env": SERVICE_ENV_LIVE_RESTART_DELAY,
        "send_dry_run_env": SERVICE_ENV_SEND_DRY_RUN,
    }
    return template.format(**values)


def systemctl_user(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        text=True,
    )


def journalctl_user(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["journalctl", "--user", *args],
        capture_output=True,
        text=True,
    )


def load_service_properties(service_name: str) -> Dict[str, str]:
    completed = systemctl_user(
        [
            "show",
            service_name,
            "--property",
            "Id,LoadState,ActiveState,SubState,MainPID,UnitFileState,FragmentPath,Result,ExecMainStatus",
            "--no-page",
        ]
    )
    if completed.returncode != 0:
        return {}

    payload: Dict[str, str] = {}
    for line in completed.stdout.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        payload[key] = value
    return payload


def wait_for_service_state(service_name: str, active_state: str, timeout: float) -> Dict[str, str]:
    deadline = time.time() + timeout
    last = {}
    while time.time() < deadline:
        last = load_service_properties(service_name)
        if last.get("ActiveState") == active_state:
            return last
        time.sleep(0.2)
    return last


def wait_for_service_inactive(service_name: str, timeout: float) -> Dict[str, str]:
    deadline = time.time() + timeout
    last = {}
    while time.time() < deadline:
        last = load_service_properties(service_name)
        if last.get("ActiveState") == "inactive" and last.get("MainPID", "0") in {"", "0"}:
            return last
        time.sleep(0.2)
    return last


def read_status_snapshot(args: argparse.Namespace) -> Dict[str, object]:
    if getattr(args, "service", False):
        return read_service_status_snapshot(args)

    pid = read_pid(args.pid_file)
    runtime = read_json(args.runtime_status_file)
    api_summary = fetch_api_summary(args.base_url, timeout=args.api_timeout)
    snapshot = {
        "service_mode": False,
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


def read_service_status_snapshot(args: argparse.Namespace) -> Dict[str, object]:
    runtime = read_json(args.runtime_status_file)
    api_summary = fetch_api_summary(args.base_url, timeout=args.api_timeout)
    properties = load_service_properties(args.service_name)
    main_pid = int(properties.get("MainPID", "0") or "0")
    active_state = properties.get("ActiveState", "unknown")
    sub_state = properties.get("SubState", "unknown")
    running = active_state == "active" and sub_state in {"running", "listening"} and main_pid > 0 and pid_alive(main_pid)

    return {
        "service_mode": True,
        "service_name": args.service_name,
        "service_unit_path": properties.get("FragmentPath", str(args.service_unit_path)),
        "service_load_state": properties.get("LoadState", "unknown"),
        "service_active_state": active_state,
        "service_sub_state": sub_state,
        "service_enabled": properties.get("UnitFileState", "unknown"),
        "service_result": properties.get("Result", "unknown"),
        "service_exec_main_status": properties.get("ExecMainStatus", ""),
        "pid_file": str(args.pid_file),
        "pid": main_pid,
        "running": running,
        "log_file": "journalctl --user -u " + args.service_name,
        "runtime_status_file": str(args.runtime_status_file),
        "state_file": str(args.state_file),
        "audit_file": str(args.audit_file) if args.audit_file is not None else "",
        "base_url": args.base_url,
        "runtime": runtime,
        "api_ready": api_summary is not None,
        "api_summary_total": api_summary.get("total") if isinstance(api_summary, dict) else None,
        "stale_pid": False,
    }


def print_status(snapshot: Dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(snapshot, ensure_ascii=True, indent=2))
        return
    runtime = snapshot.get("runtime", {})
    if not isinstance(runtime, dict):
        runtime = {}
    print(f"service_mode: {'yes' if snapshot.get('service_mode') else 'no'}")
    if snapshot.get("service_mode"):
        print(f"service_name: {snapshot.get('service_name')}")
        print(f"service_active_state: {snapshot.get('service_active_state')}")
        print(f"service_sub_state: {snapshot.get('service_sub_state')}")
        print(f"service_enabled: {snapshot.get('service_enabled')}")
        print(f"service_result: {snapshot.get('service_result')}")
        print(f"service_unit_path: {snapshot.get('service_unit_path')}")
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


def wait_for_runtime_pid(path: pathlib.Path, pid: int, timeout: float) -> Dict[str, object]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        data = read_json(path)
        if data.get("status") == "running" and int(data.get("pid", 0) or 0) == pid:
            return data
        time.sleep(0.2)
    return read_json(path)


def command_start(args: argparse.Namespace) -> int:
    if getattr(args, "service", False):
        return command_service_start(args)

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
    if getattr(args, "service", False):
        return command_service_stop(args)

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
    if snapshot.get("stale_pid") and not snapshot.get("service_mode"):
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


def command_restart(args: argparse.Namespace) -> int:
    if getattr(args, "service", False):
        completed = systemctl_user(["restart", args.service_name])
        if completed.returncode != 0:
            print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: service restart failed", file=sys.stderr)
            return 1
        properties = wait_for_service_state(args.service_name, "active", args.start_timeout)
        main_pid = int(properties.get("MainPID", "0") or "0")
        runtime = wait_for_runtime_pid(args.runtime_status_file, main_pid, args.start_timeout) if main_pid > 0 else {}
        if properties.get("ActiveState") != "active" or runtime.get("status") != "running":
            print("FAIL: service did not come back after restart", file=sys.stderr)
            return 1
        print(f"TASK_WHATSAPP_BRIDGE_SERVICE_RESTARTED service={args.service_name} pid={main_pid}")
        return 0

    stop_code = command_stop(args)
    if stop_code != 0:
        return stop_code
    return command_start(args)


def command_logs(args: argparse.Namespace) -> int:
    if getattr(args, "service", False):
        journal_args = ["-u", args.service_name, "--no-pager", "--output", "short-iso", "-n", str(args.lines)]
        if args.follow:
            journal_args.append("--follow")
        completed = journalctl_user(journal_args)
        if completed.returncode != 0:
            print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: journalctl failed", file=sys.stderr)
            return 1
        output = completed.stdout.rstrip()
        if output:
            print(output)
        return 0

    if not args.log_file.exists():
        print(f"FAIL: log file not found: {args.log_file}", file=sys.stderr)
        return 1

    command = ["tail", "-n", str(args.lines)]
    if args.follow:
        command.append("-f")
    command.append(str(args.log_file))
    completed = subprocess.run(command, text=True)
    return completed.returncode


def command_service_install(args: argparse.Namespace) -> int:
    if args.service_unit_path.name != args.service_name:
        print("FAIL: service unit path must end with the requested service name", file=sys.stderr)
        return 1

    ensure_parent(args.service_unit_path)
    unit_text = render_service_unit(args)
    args.service_unit_path.write_text(unit_text, encoding="utf-8")

    completed = systemctl_user(["daemon-reload"])
    if completed.returncode != 0:
        print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: daemon-reload failed", file=sys.stderr)
        return 1

    if args.enable:
        completed = systemctl_user(["enable", args.service_name])
        if completed.returncode != 0:
            print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: enable failed", file=sys.stderr)
            return 1

    if args.start_service:
        start_code = command_service_start(args)
        if start_code != 0:
            return start_code

    print(f"TASK_WHATSAPP_BRIDGE_SERVICE_INSTALLED service={args.service_name} unit={args.service_unit_path}")
    return 0


def command_service_uninstall(args: argparse.Namespace) -> int:
    systemctl_user(["stop", args.service_name])
    systemctl_user(["disable", args.service_name])
    if args.service_unit_path.exists():
        args.service_unit_path.unlink()
    systemctl_user(["daemon-reload"])
    systemctl_user(["reset-failed", args.service_name])
    print(f"TASK_WHATSAPP_BRIDGE_SERVICE_UNINSTALLED service={args.service_name}")
    return 0


def command_service_start(args: argparse.Namespace) -> int:
    completed = systemctl_user(["start", args.service_name])
    if completed.returncode != 0:
        print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: service start failed", file=sys.stderr)
        return 1

    properties = wait_for_service_state(args.service_name, "active", args.start_timeout)
    main_pid = int(properties.get("MainPID", "0") or "0")
    runtime = wait_for_runtime_pid(args.runtime_status_file, main_pid, args.start_timeout) if main_pid > 0 else {}
    if properties.get("ActiveState") != "active" or runtime.get("status") != "running":
        print("FAIL: service did not report running state", file=sys.stderr)
        return 1

    print(f"TASK_WHATSAPP_BRIDGE_SERVICE_STARTED service={args.service_name} pid={main_pid}")
    return 0


def command_service_stop(args: argparse.Namespace) -> int:
    completed = systemctl_user(["stop", args.service_name])
    if completed.returncode != 0:
        print(completed.stderr.strip() or completed.stdout.strip() or "FAIL: service stop failed", file=sys.stderr)
        return 1

    properties = wait_for_service_inactive(args.service_name, args.stop_timeout)
    runtime = read_json(args.runtime_status_file)
    if properties.get("ActiveState") != "inactive":
        print("FAIL: service did not stop cleanly", file=sys.stderr)
        return 1
    if runtime and runtime.get("status") not in {"stopped", ""}:
        print("FAIL: runtime status did not settle to stopped", file=sys.stderr)
        return 1

    print(f"TASK_WHATSAPP_BRIDGE_SERVICE_STOPPED service={args.service_name}")
    return 0


def command_service_preflight(args: argparse.Namespace) -> int:
    ensure_parent(args.state_file)
    ensure_parent(args.runtime_status_file)
    if args.audit_file is not None:
        ensure_parent(args.audit_file)

    api_summary = fetch_api_summary(args.base_url, timeout=args.api_timeout)
    if api_summary is None:
        print("FAIL: local task API is not ready", file=sys.stderr)
        return 1

    if not os.environ.get("PATH"):
        print("FAIL: PATH is empty", file=sys.stderr)
        return 1

    print("TASK_WHATSAPP_BRIDGE_SERVICE_PREFLIGHT_OK")
    return 0


def command_run_service(args: argparse.Namespace) -> int:
    if args.audit_file is not None:
        ensure_parent(args.audit_file)
    ensure_parent(args.state_file)
    ensure_parent(args.runtime_status_file)
    remove_pid_file(args.pid_file)
    command = build_runtime_command(args)
    os.execvp(command[0], command)
    return 1


def datetime_from_iso(value: str) -> float:
    normalized = value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized).timestamp()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Operational control surface for the WhatsApp runtime bridge.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_common_flags(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--base-url", default=os.environ.get(SERVICE_ENV_BASE_URL, DEFAULT_BASE_URL))
        subparser.add_argument("--pid-file", type=pathlib.Path, default=DEFAULT_PID_FILE)
        subparser.add_argument("--log-file", type=pathlib.Path, default=DEFAULT_LOG_FILE)
        subparser.add_argument(
            "--state-file",
            type=pathlib.Path,
            default=pathlib.Path(os.environ.get(SERVICE_ENV_STATE_FILE, str(DEFAULT_STATE_FILE))),
        )
        subparser.add_argument(
            "--runtime-status-file",
            type=pathlib.Path,
            default=pathlib.Path(os.environ.get(SERVICE_ENV_RUNTIME_STATUS_FILE, str(DEFAULT_RUNTIME_STATUS_FILE))),
        )
        subparser.add_argument(
            "--audit-file",
            type=pathlib.Path,
            default=pathlib.Path(os.environ.get(SERVICE_ENV_AUDIT_FILE, str(DEFAULT_AUDIT_FILE))),
        )
        subparser.add_argument("--api-timeout", type=float, default=2.0)

    def add_service_flags(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--service", action="store_true")
        subparser.add_argument("--service-name", default=DEFAULT_SERVICE_NAME)
        subparser.add_argument("--service-unit-path", type=pathlib.Path, default=DEFAULT_SERVICE_UNIT_PATH)

    start = subparsers.add_parser("start")
    add_common_flags(start)
    add_service_flags(start)
    start.add_argument(
        "--log-command",
        default=os.environ.get(SERVICE_ENV_LOG_COMMAND, "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"),
    )
    start.add_argument("--replay-file", type=pathlib.Path)
    start.add_argument("--send-dry-run", action="store_true", default=env_flag(SERVICE_ENV_SEND_DRY_RUN, False))
    start.add_argument(
        "--live-restart-delay",
        type=float,
        default=float(os.environ.get(SERVICE_ENV_LIVE_RESTART_DELAY, "2.0")),
    )
    start.add_argument("--start-timeout", type=float, default=10.0)
    start.set_defaults(func=command_start)

    stop = subparsers.add_parser("stop")
    add_common_flags(stop)
    add_service_flags(stop)
    stop.add_argument("--stop-timeout", type=float, default=10.0)
    stop.set_defaults(func=command_stop)

    restart = subparsers.add_parser("restart")
    add_common_flags(restart)
    add_service_flags(restart)
    restart.add_argument(
        "--log-command",
        default=os.environ.get(SERVICE_ENV_LOG_COMMAND, "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"),
    )
    restart.add_argument("--replay-file", type=pathlib.Path)
    restart.add_argument("--send-dry-run", action="store_true", default=env_flag(SERVICE_ENV_SEND_DRY_RUN, False))
    restart.add_argument(
        "--live-restart-delay",
        type=float,
        default=float(os.environ.get(SERVICE_ENV_LIVE_RESTART_DELAY, "2.0")),
    )
    restart.add_argument("--start-timeout", type=float, default=10.0)
    restart.add_argument("--stop-timeout", type=float, default=10.0)
    restart.set_defaults(func=command_restart)

    status = subparsers.add_parser("status")
    add_common_flags(status)
    add_service_flags(status)
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=command_status)

    healthcheck = subparsers.add_parser("healthcheck")
    add_common_flags(healthcheck)
    add_service_flags(healthcheck)
    healthcheck.add_argument("--json", action="store_true")
    healthcheck.add_argument("--max-heartbeat-age", type=float, default=15.0)
    healthcheck.set_defaults(func=command_healthcheck)

    logs = subparsers.add_parser("logs")
    add_common_flags(logs)
    add_service_flags(logs)
    logs.add_argument("--lines", type=int, default=100)
    logs.add_argument("--follow", action="store_true")
    logs.set_defaults(func=command_logs)

    service_install = subparsers.add_parser("service-install")
    add_common_flags(service_install)
    add_service_flags(service_install)
    service_install.add_argument(
        "--log-command",
        default=os.environ.get(SERVICE_ENV_LOG_COMMAND, "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"),
    )
    service_install.add_argument("--send-dry-run", action="store_true", default=env_flag(SERVICE_ENV_SEND_DRY_RUN, False))
    service_install.add_argument(
        "--live-restart-delay",
        type=float,
        default=float(os.environ.get(SERVICE_ENV_LIVE_RESTART_DELAY, "2.0")),
    )
    service_install.add_argument("--enable", action="store_true")
    service_install.add_argument("--start-service", action="store_true")
    service_install.set_defaults(func=command_service_install, service=True)

    service_uninstall = subparsers.add_parser("service-uninstall")
    add_common_flags(service_uninstall)
    add_service_flags(service_uninstall)
    service_uninstall.set_defaults(func=command_service_uninstall, service=True)

    service_preflight = subparsers.add_parser("service-preflight")
    add_common_flags(service_preflight)
    add_service_flags(service_preflight)
    service_preflight.set_defaults(func=command_service_preflight, service=True)

    run_service = subparsers.add_parser("run-service")
    add_common_flags(run_service)
    add_service_flags(run_service)
    run_service.add_argument(
        "--log-command",
        default=os.environ.get(SERVICE_ENV_LOG_COMMAND, "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"),
    )
    run_service.add_argument("--replay-file", type=pathlib.Path)
    run_service.add_argument("--send-dry-run", action="store_true", default=env_flag(SERVICE_ENV_SEND_DRY_RUN, False))
    run_service.add_argument(
        "--live-restart-delay",
        type=float,
        default=float(os.environ.get(SERVICE_ENV_LIVE_RESTART_DELAY, "2.0")),
    )
    run_service.set_defaults(func=command_run_service, service=True)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
