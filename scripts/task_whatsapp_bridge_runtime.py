#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import selectors
import shlex
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Dict, Iterable, Iterator, Optional


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
DEFAULT_BASE_URL = "http://127.0.0.1:8765"
DEFAULT_STATE_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_state.json"
DEFAULT_RUNTIME_STATUS_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_runtime.json"
DEFAULT_LOG_COMMAND = "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"

STOP_REQUESTED = False
LIVE_PROCESS: Optional[subprocess.Popen[str]] = None


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def atomic_write_json(path: pathlib.Path, payload: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)


class RuntimeTracker:
    def __init__(self, path: pathlib.Path, args: argparse.Namespace):
        self.path = path
        self.payload: Dict[str, object] = {
            "status": "starting",
            "pid": os.getpid(),
            "base_url": args.base_url,
            "mode": "replay" if args.replay_file is not None else "live",
            "send_dry_run": args.send_dry_run,
            "log_command": args.log_command if args.replay_file is None else "",
            "replay_file": str(args.replay_file) if args.replay_file is not None else "",
            "started_at": utc_now(),
            "last_heartbeat_at": utc_now(),
            "last_event_at": "",
            "last_command_at": "",
            "last_handled_at": "",
            "last_ignored_at": "",
            "last_error_at": "",
            "last_operation": "",
            "last_from": "",
            "last_task_id": "",
            "last_error": "",
            "handled_count": 0,
            "ignored_count": 0,
            "error_count": 0,
            "restart_count": 0,
            "child_pid": 0,
            "stop_reason": "",
            "heartbeat_note": "boot",
        }
        self.save()

    def save(self) -> None:
        self.payload["last_heartbeat_at"] = utc_now()
        atomic_write_json(self.path, self.payload)

    def heartbeat(self, note: str = "") -> None:
        if note:
            self.payload["heartbeat_note"] = note
        self.save()

    def set_status(self, status: str, note: str = "", stop_reason: str = "") -> None:
        self.payload["status"] = status
        if note:
            self.payload["heartbeat_note"] = note
        if stop_reason:
            self.payload["stop_reason"] = stop_reason
        self.save()

    def set_child_pid(self, pid: int) -> None:
        self.payload["child_pid"] = pid
        self.save()

    def clear_child_pid(self) -> None:
        self.payload["child_pid"] = 0
        self.save()

    def record_restart(self, reason: str) -> None:
        self.payload["restart_count"] = int(self.payload.get("restart_count", 0)) + 1
        self.payload["last_error"] = reason
        self.payload["last_error_at"] = utc_now()
        self.payload["error_count"] = int(self.payload.get("error_count", 0)) + 1
        self.save()

    def record_ignored(self, event: Dict[str, object], reason: str) -> None:
        self.payload["ignored_count"] = int(self.payload.get("ignored_count", 0)) + 1
        self.payload["last_event_at"] = utc_now()
        self.payload["last_ignored_at"] = utc_now()
        self.payload["last_operation"] = f"ignored:{reason}"
        self.payload["last_from"] = str(event.get("from", ""))
        self.save()

    def record_handled(self, event: Dict[str, object], operation: str, task_id: str, had_error: bool) -> None:
        self.payload["handled_count"] = int(self.payload.get("handled_count", 0)) + 1
        self.payload["last_event_at"] = utc_now()
        self.payload["last_command_at"] = utc_now()
        self.payload["last_handled_at"] = utc_now()
        self.payload["last_operation"] = operation
        self.payload["last_from"] = str(event.get("from", ""))
        self.payload["last_task_id"] = task_id
        if had_error:
            self.payload["error_count"] = int(self.payload.get("error_count", 0)) + 1
            self.payload["last_error_at"] = utc_now()
            self.payload["last_error"] = f"operation_error:{operation}"
        self.save()

    def record_runtime_error(self, message: str) -> None:
        self.payload["error_count"] = int(self.payload.get("error_count", 0)) + 1
        self.payload["last_error_at"] = utc_now()
        self.payload["last_error"] = message
        self.save()


def request_stop(signum, _frame) -> None:
    del _frame
    global STOP_REQUESTED
    STOP_REQUESTED = True
    process = LIVE_PROCESS
    if process is not None and process.poll() is None:
        try:
            process.terminate()
        except ProcessLookupError:
            pass


def classify_command(text: str) -> Optional[Dict[str, str]]:
    normalized = " ".join(text.strip().split())
    lowered = normalized.lower()

    if lowered in ("summary", "task summary", "tasks summary"):
        return {"lane": "query", "operation": "summary", "text": normalized}
    if lowered.startswith("tasks list"):
        return {"lane": "query", "operation": "list", "text": normalized}
    if lowered.startswith("task show ") or lowered.startswith("tasks show "):
        return {"lane": "query", "operation": "show", "text": normalized}
    if lowered.startswith("task create "):
        return {"lane": "mutate", "operation": "create", "text": normalized}
    if lowered.startswith("task update "):
        return {"lane": "mutate", "operation": "update", "text": normalized}
    if lowered.startswith("task close "):
        return {"lane": "mutate", "operation": "close", "text": normalized}
    return None


def extract_json_block(text: str) -> Optional[dict]:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


def parse_runtime_log_line(line: str) -> Optional[Dict[str, object]]:
    line = line.strip()
    if not line or not line.startswith("{"):
        return None

    try:
        entry = json.loads(line)
    except json.JSONDecodeError:
        return None

    if entry.get("type") != "log":
        return None
    if entry.get("module") != "web-inbound":
        return None

    raw = entry.get("raw")
    if not isinstance(raw, str):
        return None

    try:
        raw_entry = json.loads(raw)
    except json.JSONDecodeError:
        return None

    if raw_entry.get("2") != "inbound message":
        return None

    payload = raw_entry.get("1")
    if not isinstance(payload, dict):
        return None

    from_number = payload.get("from")
    body = payload.get("body")
    if not isinstance(from_number, str) or not isinstance(body, str):
        return None

    return {
        "from": from_number,
        "to": payload.get("to", ""),
        "body": body,
        "timestamp": payload.get("timestamp"),
        "media_path": payload.get("mediaPath"),
        "media_type": payload.get("mediaType"),
        "raw_log": entry,
    }


def load_state(path: pathlib.Path) -> Dict[str, object]:
    if not path.exists():
        return {"handled_event_keys": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"handled_event_keys": []}
    if not isinstance(data, dict):
        return {"handled_event_keys": []}
    keys = data.get("handled_event_keys")
    if not isinstance(keys, list):
        keys = []
    return {"handled_event_keys": [str(item) for item in keys]}


def save_state(path: pathlib.Path, state: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_json(path, state)


def event_key(event: Dict[str, object]) -> str:
    return json.dumps(
        {
            "from": event.get("from", ""),
            "timestamp": event.get("timestamp", ""),
            "body": event.get("body", ""),
        },
        ensure_ascii=True,
        sort_keys=True,
    )


def parse_response_details(operation: str, text: str) -> Dict[str, str]:
    details: Dict[str, str] = {}
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines:
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        normalized = key.strip().lower().replace(" ", "_")
        details[normalized] = value.strip()
    if operation in {"create", "update", "close"} and "id" in details:
        details["task_id"] = details["id"]
    return details


def run_script(script_name: str, base_url: str, text: str) -> Dict[str, object]:
    command = [sys.executable, str(SCRIPTS_DIR / script_name), "--base-url", base_url, "--text", text]
    completed = subprocess.run(command, capture_output=True, text=True)
    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    return {
        "command": command,
        "returncode": completed.returncode,
        "stdout": stdout,
        "stderr": stderr,
    }


def handle_task_command(base_url: str, command_info: Dict[str, str]) -> Dict[str, object]:
    if command_info["lane"] == "query":
        return run_script("task_whatsapp_query.py", base_url, command_info["text"])
    return run_script("task_whatsapp_mutate.py", base_url, command_info["text"])


def send_whatsapp_reply(target: str, reply_text: str, dry_run: bool) -> Dict[str, object]:
    command = [
        "openclaw",
        "message",
        "send",
        "--channel",
        "whatsapp",
        "--target",
        target,
        "--message",
        reply_text,
        "--json",
    ]
    if dry_run:
        command.append("--dry-run")
    completed = subprocess.run(command, capture_output=True, text=True)
    parsed = extract_json_block(completed.stdout)
    return {
        "command": command,
        "returncode": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
        "parsed": parsed,
        "dry_run": dry_run,
    }


def emit_record(record: Dict[str, object], audit_file: Optional[pathlib.Path]) -> None:
    line = json.dumps(record, ensure_ascii=True)
    print(line, flush=True)
    if audit_file is not None:
        audit_file.parent.mkdir(parents=True, exist_ok=True)
        with audit_file.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")


def iter_replay_lines(path: pathlib.Path, runtime: RuntimeTracker) -> Iterator[str]:
    runtime.set_status("running", note="replay_active")
    for line in path.read_text(encoding="utf-8").splitlines():
        if STOP_REQUESTED:
            break
        runtime.heartbeat(note="replay_line")
        yield line


def terminate_process(process: subprocess.Popen[str], timeout: float) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=timeout)


def iter_live_lines(command_text: str, runtime: RuntimeTracker, restart_delay: float) -> Iterator[str]:
    global LIVE_PROCESS

    while not STOP_REQUESTED:
        process = subprocess.Popen(
            shlex.split(command_text),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        LIVE_PROCESS = process
        runtime.set_child_pid(process.pid)
        runtime.set_status("running", note="log_follow_active")
        assert process.stdout is not None
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while not STOP_REQUESTED:
                    if process.poll() is not None:
                        break
                    events = selector.select(timeout=1.0)
                    if not events:
                        runtime.heartbeat(note="waiting_for_logs")
                        continue
                    for key, _mask in events:
                        line = key.fileobj.readline()
                        if not line:
                            continue
                        runtime.heartbeat(note="log_line")
                        yield line.rstrip("\n")
        finally:
            runtime.clear_child_pid()
            try:
                terminate_process(process, timeout=5)
            except Exception as exc:
                runtime.record_runtime_error(f"live_process_shutdown_failed:{exc}")
            LIVE_PROCESS = None

        if STOP_REQUESTED:
            break

        exit_code = process.returncode if process.returncode is not None else -1
        runtime.record_restart(f"log_command_exited:{exit_code}")
        runtime.set_status("running", note="log_follow_restarting")
        time.sleep(restart_delay)


def process_event(
    event: Dict[str, object],
    args: argparse.Namespace,
    state: Dict[str, object],
    audit_file: Optional[pathlib.Path],
    runtime: RuntimeTracker,
) -> None:
    key = event_key(event)
    handled_keys = state["handled_event_keys"]
    assert isinstance(handled_keys, list)
    if key in handled_keys:
        return

    command_info = classify_command(str(event["body"]))
    if command_info is None:
        emit_record(
            {
                "type": "ignored",
                "reason": "unsupported_command",
                "from": event.get("from", ""),
                "body": event.get("body", ""),
                "timestamp": event.get("timestamp"),
            },
            audit_file,
        )
        runtime.record_ignored(event, "unsupported_command")
        handled_keys.append(key)
        del handled_keys[:-500]
        save_state(args.state_file, state)
        return

    task_result = handle_task_command(args.base_url, command_info)
    response_text = task_result["stdout"] or task_result["stderr"] or "WHATSAPP TASK BRIDGE ERROR"
    send_result = send_whatsapp_reply(str(event["from"]), response_text, args.send_dry_run)
    response_details = parse_response_details(command_info["operation"], response_text)
    had_error = task_result["returncode"] != 0 or send_result["returncode"] != 0

    record = {
        "type": "handled",
        "source": "openclaw-runtime" if args.replay_file is None else "openclaw-runtime-replay",
        "lane": command_info["lane"],
        "operation": command_info["operation"],
        "from": event.get("from", ""),
        "to": event.get("to", ""),
        "timestamp": event.get("timestamp"),
        "body": event.get("body", ""),
        "response_text": response_text,
        "response_details": response_details,
        "task_command": {
            "returncode": task_result["returncode"],
            "stdout": task_result["stdout"],
            "stderr": task_result["stderr"],
        },
        "delivery": {
            "returncode": send_result["returncode"],
            "stdout": send_result["stdout"],
            "stderr": send_result["stderr"],
            "parsed": send_result["parsed"],
            "dry_run": send_result["dry_run"],
        },
    }
    emit_record(record, audit_file)

    runtime.record_handled(
        event,
        command_info["operation"],
        response_details.get("task_id", ""),
        had_error,
    )

    handled_keys.append(key)
    del handled_keys[:-500]
    save_state(args.state_file, state)


def determine_stop_reason(args: argparse.Namespace) -> str:
    if STOP_REQUESTED:
        return "signal"
    if args.replay_file is not None:
        return "replay_complete"
    return "log_stream_stopped"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Runtime WhatsApp bridge over OpenClaw logs and the canonical local task HTTP API."
    )
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--state-file", type=pathlib.Path, default=DEFAULT_STATE_FILE)
    parser.add_argument("--runtime-status-file", type=pathlib.Path, default=DEFAULT_RUNTIME_STATUS_FILE)
    parser.add_argument("--audit-file", type=pathlib.Path)
    parser.add_argument("--log-command", default=DEFAULT_LOG_COMMAND)
    parser.add_argument("--replay-file", type=pathlib.Path)
    parser.add_argument("--send-dry-run", action="store_true")
    parser.add_argument("--live-restart-delay", type=float, default=2.0)
    args = parser.parse_args()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    runtime = RuntimeTracker(args.runtime_status_file, args)
    state = load_state(args.state_file)

    line_iter: Iterable[str]
    if args.replay_file is not None:
        line_iter = iter_replay_lines(args.replay_file, runtime)
    else:
        line_iter = iter_live_lines(args.log_command, runtime, args.live_restart_delay)

    exit_code = 0
    try:
        for line in line_iter:
            if STOP_REQUESTED:
                break
            event = parse_runtime_log_line(line)
            if event is None:
                runtime.heartbeat(note="non_task_log_line")
                continue
            process_event(event, args, state, args.audit_file, runtime)
    except KeyboardInterrupt:
        runtime.record_runtime_error("keyboard_interrupt")
    except Exception as exc:
        runtime.record_runtime_error(f"runtime_exception:{exc}")
        exit_code = 1
    finally:
        runtime.set_status("stopped", note="shutdown_complete", stop_reason=determine_stop_reason(args))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
