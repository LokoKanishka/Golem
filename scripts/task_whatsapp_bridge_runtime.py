#!/usr/bin/env python3
import argparse
import json
import pathlib
import shlex
import subprocess
import sys
from typing import Dict, Iterable, Iterator, Optional


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
DEFAULT_BASE_URL = "http://127.0.0.1:8765"
DEFAULT_STATE_FILE = REPO_ROOT / "state" / "tmp" / "whatsapp_task_bridge_runtime_state.json"
DEFAULT_LOG_COMMAND = "openclaw logs --json --follow --interval 1000 --limit 50 --max-bytes 250000"


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
    path.write_text(json.dumps(state, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


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
        result = run_script("task_whatsapp_query.py", base_url, command_info["text"])
    else:
        result = run_script("task_whatsapp_mutate.py", base_url, command_info["text"])
    return result


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


def iter_replay_lines(path: pathlib.Path) -> Iterator[str]:
    for line in path.read_text(encoding="utf-8").splitlines():
        yield line


def iter_live_lines(command_text: str) -> Iterator[str]:
    process = subprocess.Popen(
        shlex.split(command_text),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    try:
        for line in process.stdout:
            yield line.rstrip("\n")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def process_event(
    event: Dict[str, object],
    args: argparse.Namespace,
    state: Dict[str, object],
    audit_file: Optional[pathlib.Path],
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
        handled_keys.append(key)
        del handled_keys[:-500]
        save_state(args.state_file, state)
        return

    task_result = handle_task_command(args.base_url, command_info)
    response_text = task_result["stdout"] or task_result["stderr"] or "WHATSAPP TASK BRIDGE ERROR"

    send_result = send_whatsapp_reply(str(event["from"]), response_text, args.send_dry_run)

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
        "response_details": parse_response_details(command_info["operation"], response_text),
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

    handled_keys.append(key)
    del handled_keys[:-500]
    save_state(args.state_file, state)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Runtime WhatsApp bridge over OpenClaw logs and the canonical local task HTTP API."
    )
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--state-file", type=pathlib.Path, default=DEFAULT_STATE_FILE)
    parser.add_argument("--audit-file", type=pathlib.Path)
    parser.add_argument("--log-command", default=DEFAULT_LOG_COMMAND)
    parser.add_argument("--replay-file", type=pathlib.Path)
    parser.add_argument("--send-dry-run", action="store_true")
    args = parser.parse_args()

    state = load_state(args.state_file)

    line_iter: Iterable[str]
    if args.replay_file is not None:
        line_iter = iter_replay_lines(args.replay_file)
    else:
        line_iter = iter_live_lines(args.log_command)

    try:
        for line in line_iter:
            event = parse_runtime_log_line(line)
            if event is None:
                continue
            process_event(event, args, state, args.audit_file)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
