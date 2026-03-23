#!/usr/bin/env python3
import argparse
import json
import mimetypes
import pathlib
import subprocess
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
READ_SCRIPT = REPO_ROOT / "scripts" / "task_panel_read.sh"
MUTATE_SCRIPT = REPO_ROOT / "scripts" / "task_panel_mutate.sh"
PANEL_DIR = REPO_ROOT / "panel"


def build_error_payload(code, message, details=None):
    payload = {"error": code, "message": message}
    if details:
        payload["details"] = details
    return payload


def parse_process_json(stdout, stderr):
    for candidate in (stdout, stderr):
        candidate = candidate.strip()
        if not candidate:
            continue
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    return None


def run_command(args):
    completed = subprocess.run(
        [str(arg) for arg in args],
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    payload = parse_process_json(completed.stdout, completed.stderr)
    return completed, payload


def map_failure(command, completed, payload):
    if isinstance(payload, dict):
        error_code = payload.get("error", "")
        if error_code == "task_not_found":
            return HTTPStatus.NOT_FOUND, payload
        if error_code in {"invalid_limit", "task_not_canonical"}:
            return HTTPStatus.BAD_REQUEST, payload

    status = HTTPStatus.BAD_REQUEST if completed.returncode == 2 else HTTPStatus.INTERNAL_SERVER_ERROR
    return status, build_error_payload(
        "panel_http_command_failed",
        f"{command} failed",
        {
            "exit_code": completed.returncode,
            "stdout": completed.stdout.strip(),
            "stderr": completed.stderr.strip(),
        },
    )


class TaskPanelHandler(BaseHTTPRequestHandler):
    server_version = "GolemTaskPanelHTTP/1.0"

    def log_message(self, format, *args):
        return

    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=True, indent=2).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_redirect(self, location):
        self.send_response(int(HTTPStatus.FOUND))
        self.send_header("Location", location)
        self.end_headers()

    def send_file(self, path):
        if not path.is_file():
            self.send_json(
                HTTPStatus.NOT_FOUND,
                build_error_payload("route_not_found", f"Unknown route: {self.path}"),
            )
            return

        content_type, _ = mimetypes.guess_type(str(path))
        if not content_type:
            content_type = "application/octet-stream"
        body = path.read_bytes()
        self.send_response(int(HTTPStatus.OK))
        self.send_header("Content-Type", f"{content_type}; charset=utf-8" if content_type.startswith("text/") or content_type == "application/javascript" else content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b""
        if not raw:
            return {}
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSON body: {exc}") from exc

    def do_GET(self):
        parsed = urlparse(self.path)
        parts = [part for part in parsed.path.split("/") if part]
        query = parse_qs(parsed.query)

        if parsed.path == "/":
            self.send_redirect("/panel/")
            return
        if parsed.path in {"/panel", "/panel/"}:
            self.send_file(PANEL_DIR / "index.html")
            return
        if parsed.path.startswith("/panel/") and len(parts) == 2:
            asset = parts[1]
            if asset in {"app.js", "styles.css"}:
                self.send_file(PANEL_DIR / asset)
                return
        if parsed.path == "/tasks":
            args = [READ_SCRIPT, "list"]
            status_filter = query.get("status", [""])[0]
            limit = query.get("limit", [""])[0]
            if status_filter:
                args.extend(["--status", status_filter])
            if limit:
                args.extend(["--limit", limit])
            completed, payload = run_command(args)
        elif parsed.path == "/tasks/summary":
            completed, payload = run_command([READ_SCRIPT, "summary"])
        elif len(parts) == 2 and parts[0] == "tasks":
            completed, payload = run_command([READ_SCRIPT, "show", unquote(parts[1])])
        else:
            self.send_json(
                HTTPStatus.NOT_FOUND,
                build_error_payload("route_not_found", f"Unknown route: {parsed.path}"),
            )
            return

        if completed.returncode != 0:
            status, error_payload = map_failure("read", completed, payload)
            self.send_json(status, error_payload)
            return

        self.send_json(HTTPStatus.OK, payload)

    def do_POST(self):
        parsed = urlparse(self.path)
        parts = [part for part in parsed.path.split("/") if part]

        try:
            body = self.read_json_body()
        except ValueError as exc:
            self.send_json(
                HTTPStatus.BAD_REQUEST,
                build_error_payload("invalid_json", str(exc)),
            )
            return

        if parsed.path == "/tasks":
            args = [MUTATE_SCRIPT, "create"]
            title = body.get("title", "")
            objective = body.get("objective", "")
            if not title or not objective:
                self.send_json(
                    HTTPStatus.BAD_REQUEST,
                    build_error_payload("missing_fields", "title and objective are required"),
                )
                return
            args.extend(["--title", title, "--objective", objective])
            if body.get("type"):
                args.extend(["--type", body["type"]])
            if body.get("owner"):
                args.extend(["--owner", body["owner"]])
            if body.get("source"):
                args.extend(["--source", body["source"]])
            if body.get("canonical_session"):
                args.extend(["--canonical-session", body["canonical_session"]])
            if body.get("origin"):
                args.extend(["--origin", body["origin"]])
            for criterion in body.get("accept", []):
                args.extend(["--accept", str(criterion)])
            expected_status = HTTPStatus.CREATED
        elif len(parts) == 3 and parts[0] == "tasks" and parts[2] == "update":
            task_id = unquote(parts[1])
            args = [MUTATE_SCRIPT, "update", task_id]
            if body.get("status"):
                args.extend(["--status", body["status"]])
            if body.get("owner"):
                args.extend(["--owner", body["owner"]])
            if body.get("title"):
                args.extend(["--title", body["title"]])
            if body.get("objective"):
                args.extend(["--objective", body["objective"]])
            if body.get("source"):
                args.extend(["--source", body["source"]])
            if body.get("note"):
                args.extend(["--note", body["note"]])
            if body.get("actor"):
                args.extend(["--actor", body["actor"]])
            for criterion in body.get("append_accept", []):
                args.extend(["--append-accept", str(criterion)])
            expected_status = HTTPStatus.OK
        elif len(parts) == 3 and parts[0] == "tasks" and parts[2] == "close":
            task_id = unquote(parts[1])
            status_value = body.get("status", "")
            note = body.get("note", "")
            if not status_value or not note:
                self.send_json(
                    HTTPStatus.BAD_REQUEST,
                    build_error_payload("missing_fields", "status and note are required"),
                )
                return
            args = [MUTATE_SCRIPT, "close", task_id, "--status", status_value, "--note", note]
            if body.get("owner"):
                args.extend(["--owner", body["owner"]])
            if body.get("actor"):
                args.extend(["--actor", body["actor"]])
            if body.get("source"):
                args.extend(["--source", body["source"]])
            expected_status = HTTPStatus.OK
        else:
            self.send_json(
                HTTPStatus.NOT_FOUND,
                build_error_payload("route_not_found", f"Unknown route: {parsed.path}"),
            )
            return

        completed, payload = run_command(args)
        if completed.returncode != 0:
            status, error_payload = map_failure("mutate", completed, payload)
            self.send_json(status, error_payload)
            return

        self.send_json(expected_status, payload)


def main():
    parser = argparse.ArgumentParser(description="Local HTTP wrapper for canonical panel task paths.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), TaskPanelHandler)
    print(f"TASK_PANEL_HTTP_SERVER_OK http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
