#!/usr/bin/env python3
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


DEFAULT_BASE_URL = "http://127.0.0.1:8765"


def fetch_json(base_url, path):
    request = urllib.request.Request(base_url.rstrip("/") + path, method="GET")
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_text_query(text):
    tokens = text.strip().split()
    if not tokens:
        raise ValueError("empty query")

    lowered = [token.lower() for token in tokens]

    if lowered in (["summary"], ["task", "summary"], ["tasks", "summary"]):
        return ("summary", {})

    if len(lowered) >= 2 and lowered[:2] == ["tasks", "list"]:
        status = ""
        limit = ""
        idx = 2
        while idx < len(tokens):
            key = lowered[idx]
            if key == "status" and idx + 1 < len(tokens):
                status = tokens[idx + 1]
                idx += 2
                continue
            if key == "limit" and idx + 1 < len(tokens):
                limit = tokens[idx + 1]
                idx += 2
                continue
            idx += 1
        return ("list", {"status": status, "limit": limit})

    if len(lowered) >= 3 and lowered[:2] in (["task", "show"], ["tasks", "show"]):
        return ("show", {"task_id": tokens[2]})

    raise ValueError("unsupported WhatsApp task query")


def format_summary(payload):
    inventory = payload["inventory"]
    lines = ["TASKS SUMMARY", f"total: {inventory['total']}"]
    for status, count in sorted(inventory["status_counts"].items()):
        lines.append(f"- {status}: {count}")
    lines.append(f"latest_updated_at: {inventory['latest_updated_at'] or '(none)'}")
    return "\n".join(lines)


def format_list(payload):
    lines = ["TASKS LIST", f"returned: {payload['meta']['returned']}"]
    for item in payload["tasks"]:
        title = item["title"]
        lines.append(f"- {item['id']} | {item['status']} | {title}")
    return "\n".join(lines)


def format_show(payload):
    task = payload["task"]
    delivery = task.get("delivery") or {}
    lines = [
        "TASK DETAIL",
        f"id: {task['id']}",
        f"status: {task['status']}",
        f"title: {task['title']}",
        f"owner: {task['owner']}",
        f"source_channel: {task['source_channel']}",
        f"updated_at: {task['updated_at']}",
        f"delivery_state: {delivery.get('current_state') or '(none)'}",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Minimal WhatsApp-style task queries via the local panel HTTP API.")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--text", help="WhatsApp-like inbound text query")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("summary")

    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--status", default="")
    list_parser.add_argument("--limit", default="")

    show_parser = subparsers.add_parser("show")
    show_parser.add_argument("task_id")

    args = parser.parse_args()

    if args.text:
        command, payload = parse_text_query(args.text)
    elif args.command == "summary":
        command, payload = "summary", {}
    elif args.command == "list":
        command, payload = "list", {"status": args.status, "limit": args.limit}
    elif args.command == "show":
        command, payload = "show", {"task_id": args.task_id}
    else:
        parser.print_help(sys.stderr)
        raise SystemExit(1)

    try:
        if command == "summary":
            response = fetch_json(args.base_url, "/tasks/summary")
            print(format_summary(response))
        elif command == "list":
            query = {}
            if payload.get("status"):
                query["status"] = payload["status"]
            if payload.get("limit"):
                query["limit"] = payload["limit"]
            suffix = "?" + urllib.parse.urlencode(query) if query else ""
            response = fetch_json(args.base_url, "/tasks" + suffix)
            print(format_list(response))
        elif command == "show":
            response = fetch_json(args.base_url, "/tasks/" + urllib.parse.quote(payload["task_id"]))
            print(format_show(response))
        else:
            raise SystemExit("unsupported command")
    except urllib.error.HTTPError as exc:
        error_payload = json.loads(exc.read().decode("utf-8"))
        print(f"WHATSAPP_TASK_QUERY_FAIL status={exc.code} error={error_payload.get('error', 'unknown')}", file=sys.stderr)
        raise SystemExit(1)
    except urllib.error.URLError as exc:
        print(f"WHATSAPP_TASK_QUERY_FAIL transport={exc.reason}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
