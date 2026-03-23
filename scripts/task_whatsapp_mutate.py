#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_BASE_URL = "http://127.0.0.1:8765"


def request_json(base_url, path, method, payload):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=body,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_key_values(fragment):
    values = {}
    for part in fragment.split(";"):
        chunk = part.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            raise ValueError(f"invalid segment: {chunk}")
        key, value = chunk.split("=", 1)
        key = key.strip().lower().replace("-", "_")
        value = value.strip()
        if not value:
            raise ValueError(f"empty value for: {key}")
        values.setdefault(key, []).append(value)
    return values


def first_value(values, key):
    items = values.get(key, [])
    return items[0] if items else ""


def parse_text_command(text):
    raw = text.strip()
    if not raw:
        raise ValueError("empty command")

    lowered = raw.lower()
    if lowered.startswith("task create "):
        values = parse_key_values(raw[len("task create "):])
        return (
            "create",
            {
                "title": first_value(values, "title"),
                "objective": first_value(values, "objective"),
                "type": first_value(values, "type"),
                "owner": first_value(values, "owner"),
                "accept": values.get("accept", []),
            },
        )

    if lowered.startswith("task update "):
        rest = raw[len("task update "):].strip()
        task_id, sep, fragment = rest.partition(" ")
        if not task_id or not sep:
            raise ValueError("task update requires task id and fields")
        values = parse_key_values(fragment)
        return (
            "update",
            {
                "task_id": task_id,
                "status": first_value(values, "status"),
                "owner": first_value(values, "owner"),
                "title": first_value(values, "title"),
                "objective": first_value(values, "objective"),
                "note": first_value(values, "note"),
                "append_accept": values.get("append_accept", []),
            },
        )

    if lowered.startswith("task close "):
        rest = raw[len("task close "):].strip()
        task_id, sep, fragment = rest.partition(" ")
        if not task_id or not sep:
            raise ValueError("task close requires task id and fields")
        values = parse_key_values(fragment)
        return (
            "close",
            {
                "task_id": task_id,
                "status": first_value(values, "status"),
                "note": first_value(values, "note"),
                "owner": first_value(values, "owner"),
            },
        )

    raise ValueError("unsupported WhatsApp task mutation")


def format_create(payload):
    task = payload["task"]
    lines = [
        "TASK CREATED",
        f"id: {task['id']}",
        f"status: {task['status']}",
        f"title: {task['title']}",
        f"owner: {task['owner']}",
        f"source_channel: {task['source_channel']}",
    ]
    return "\n".join(lines)


def format_update(payload):
    task = payload["task"]
    lines = [
        "TASK UPDATED",
        f"id: {task['id']}",
        f"status: {task['status']}",
        f"title: {task['title']}",
        f"owner: {task['owner']}",
        f"source_channel: {task['source_channel']}",
    ]
    return "\n".join(lines)


def format_close(payload):
    task = payload["task"]
    lines = [
        "TASK CLOSED",
        f"id: {task['id']}",
        f"status: {task['status']}",
        f"owner: {task['owner']}",
        f"source_channel: {task['source_channel']}",
        f"closure_note: {task['closure_note']}",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Minimal WhatsApp-style task mutations via the local panel HTTP API.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--text", help="WhatsApp-like inbound text mutation")
    subparsers = parser.add_subparsers(dest="command")

    create_parser = subparsers.add_parser("create")
    create_parser.add_argument("--title", required=True)
    create_parser.add_argument("--objective", required=True)
    create_parser.add_argument("--type", default="")
    create_parser.add_argument("--owner", default="")
    create_parser.add_argument("--accept", action="append", default=[])

    update_parser = subparsers.add_parser("update")
    update_parser.add_argument("task_id")
    update_parser.add_argument("--status", default="")
    update_parser.add_argument("--owner", default="")
    update_parser.add_argument("--title", default="")
    update_parser.add_argument("--objective", default="")
    update_parser.add_argument("--note", default="")
    update_parser.add_argument("--append-accept", action="append", default=[])

    close_parser = subparsers.add_parser("close")
    close_parser.add_argument("task_id")
    close_parser.add_argument("--status", required=True)
    close_parser.add_argument("--note", required=True)
    close_parser.add_argument("--owner", default="")

    args = parser.parse_args()

    if args.text:
        command, payload = parse_text_command(args.text)
    elif args.command == "create":
        command = "create"
        payload = {
            "title": args.title,
            "objective": args.objective,
            "type": args.type,
            "owner": args.owner,
            "accept": args.accept,
        }
    elif args.command == "update":
        command = "update"
        payload = {
            "task_id": args.task_id,
            "status": args.status,
            "owner": args.owner,
            "title": args.title,
            "objective": args.objective,
            "note": args.note,
            "append_accept": args.append_accept,
        }
    elif args.command == "close":
        command = "close"
        payload = {
            "task_id": args.task_id,
            "status": args.status,
            "note": args.note,
            "owner": args.owner,
        }
    else:
        parser.print_help(sys.stderr)
        raise SystemExit(1)

    try:
        if command == "create":
            request_payload = {
                "title": payload["title"],
                "objective": payload["objective"],
                "source": "whatsapp",
                "origin": "whatsapp",
                "canonical_session": "whatsapp-http-local",
            }
            if payload.get("type"):
                request_payload["type"] = payload["type"]
            if payload.get("owner"):
                request_payload["owner"] = payload["owner"]
            if payload.get("accept"):
                request_payload["accept"] = payload["accept"]
            response = request_json(args.base_url, "/tasks", "POST", request_payload)
            print(format_create(response))
        elif command == "update":
            request_payload = {"source": "whatsapp", "actor": "whatsapp"}
            if payload.get("status"):
                request_payload["status"] = payload["status"]
            if payload.get("owner"):
                request_payload["owner"] = payload["owner"]
            if payload.get("title"):
                request_payload["title"] = payload["title"]
            if payload.get("objective"):
                request_payload["objective"] = payload["objective"]
            if payload.get("note"):
                request_payload["note"] = payload["note"]
            if payload.get("append_accept"):
                request_payload["append_accept"] = payload["append_accept"]
            response = request_json(
                args.base_url,
                "/tasks/" + urllib.parse.quote(payload["task_id"]) + "/update",
                "POST",
                request_payload,
            )
            print(format_update(response))
        elif command == "close":
            request_payload = {
                "status": payload["status"],
                "note": payload["note"],
                "actor": "whatsapp",
                "source": "whatsapp",
            }
            if payload.get("owner"):
                request_payload["owner"] = payload["owner"]
            response = request_json(
                args.base_url,
                "/tasks/" + urllib.parse.quote(payload["task_id"]) + "/close",
                "POST",
                request_payload,
            )
            print(format_close(response))
        else:
            raise SystemExit("unsupported command")
    except urllib.error.HTTPError as exc:
        error_payload = json.loads(exc.read().decode("utf-8"))
        print(f"WHATSAPP_TASK_MUTATE_FAIL status={exc.code} error={error_payload.get('error', 'unknown')}", file=sys.stderr)
        raise SystemExit(1)
    except urllib.error.URLError as exc:
        print(f"WHATSAPP_TASK_MUTATE_FAIL transport={exc.reason}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
