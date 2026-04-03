#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import json
import os
import signal
import time
from collections import OrderedDict, defaultdict
from dataclasses import dataclass
from typing import Dict, Optional, Set, Tuple
from urllib.parse import parse_qs, unquote, urlsplit
from urllib.request import urlopen


HOST = os.environ.get("GOLEM_BROWSER_RELAY_HOST", "127.0.0.1")
PORT = int(os.environ.get("GOLEM_BROWSER_RELAY_PORT", "18792"))
BROWSER_CDP_URL = os.environ.get("GOLEM_BROWSER_RELAY_BROWSER_CDP_URL", "http://127.0.0.1:9222")


def iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class WebSocketClosed(Exception):
    pass


class WebSocketConnection:
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, path: str):
        self.reader = reader
        self.writer = writer
        self.path = path

    async def recv(self) -> Optional[str]:
        first = await self.reader.readexactly(2)
        b1, b2 = first[0], first[1]
        opcode = b1 & 0x0F
        masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
          length = int.from_bytes(await self.reader.readexactly(2), "big")
        elif length == 127:
          length = int.from_bytes(await self.reader.readexactly(8), "big")
        mask = await self.reader.readexactly(4) if masked else b""
        payload = await self.reader.readexactly(length) if length else b""
        if masked:
            payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))

        if opcode == 0x8:
            await self.close()
            raise WebSocketClosed()
        if opcode == 0x9:
            await self._send_frame(payload, opcode=0xA)
            return None
        if opcode == 0xA:
            return None
        if opcode != 0x1:
            return None
        return payload.decode("utf-8", errors="replace")

    async def send_text(self, text: str) -> None:
        await self._send_frame(text.encode("utf-8"), opcode=0x1)

    async def _send_frame(self, payload: bytes, opcode: int) -> None:
        header = bytearray()
        header.append(0x80 | (opcode & 0x0F))
        length = len(payload)
        if length < 126:
            header.append(length)
        elif length < 2**16:
            header.append(126)
            header.extend(length.to_bytes(2, "big"))
        else:
            header.append(127)
            header.extend(length.to_bytes(8, "big"))
        self.writer.write(bytes(header) + payload)
        await self.writer.drain()

    async def close(self) -> None:
        try:
            self.writer.write(b"\x88\x00")
            await self.writer.drain()
        except Exception:
            pass


class OutgoingWebSocketClient:
    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, url: str):
        self.reader = reader
        self.writer = writer
        self.url = url

    @classmethod
    async def connect(cls, ws_url: str) -> "OutgoingWebSocketClient":
        parsed = urlsplit(ws_url)
        if parsed.scheme not in {"ws"}:
            raise RuntimeError(f"unsupported websocket scheme: {parsed.scheme}")

        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        path = parsed.path or "/"
        if parsed.query:
            path = f"{path}?{parsed.query}"

        reader, writer = await asyncio.open_connection(host, port)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        writer.write(request.encode("utf-8"))
        await writer.drain()

        status_line = await reader.readline()
        if not status_line:
            raise RuntimeError(f"websocket handshake failed for {ws_url}")
        if b"101" not in status_line:
            raise RuntimeError(f"websocket handshake rejected for {ws_url}: {status_line.decode('utf-8', errors='replace').strip()}")

        while True:
            line = await reader.readline()
            if line in (b"\r\n", b"\n", b""):
                break

        return cls(reader, writer, ws_url)

    async def recv(self) -> Optional[str]:
        first = await self.reader.readexactly(2)
        b1, b2 = first[0], first[1]
        opcode = b1 & 0x0F
        masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            length = int.from_bytes(await self.reader.readexactly(2), "big")
        elif length == 127:
            length = int.from_bytes(await self.reader.readexactly(8), "big")
        mask = await self.reader.readexactly(4) if masked else b""
        payload = await self.reader.readexactly(length) if length else b""
        if masked:
            payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))

        if opcode == 0x8:
            await self.close()
            raise WebSocketClosed()
        if opcode == 0x9:
            await self._send_frame(payload, opcode=0xA)
            return None
        if opcode == 0xA:
            return None
        if opcode != 0x1:
            return None
        return payload.decode("utf-8", errors="replace")

    async def send_text(self, text: str) -> None:
        await self._send_frame(text.encode("utf-8"), opcode=0x1)

    async def _send_frame(self, payload: bytes, opcode: int) -> None:
        mask = os.urandom(4)
        header = bytearray()
        header.append(0x80 | (opcode & 0x0F))
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 2**16:
            header.append(0x80 | 126)
            header.extend(length.to_bytes(2, "big"))
        else:
            header.append(0x80 | 127)
            header.extend(length.to_bytes(8, "big"))
        header.extend(mask)
        masked_payload = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.writer.write(bytes(header) + masked_payload)
        await self.writer.drain()

    async def close(self) -> None:
        try:
            await self._send_frame(b"", opcode=0x8)
        except Exception:
            pass
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except Exception:
            pass


def load_json_sync(url: str) -> dict | list:
    with urlopen(url) as response:
        return json.load(response)


@dataclass
class PendingRequest:
    client: WebSocketConnection
    original_id: int
    client_kind: str


class RelayState:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.extension: Optional[WebSocketConnection] = None
        self.browser_upstream: Optional[OutgoingWebSocketClient] = None
        self.browser_upstream_task: Optional[asyncio.Task] = None
        self.targets_by_session: "OrderedDict[str, dict]" = OrderedDict()
        self.target_id_to_session: Dict[str, str] = {}
        self.page_clients: Dict[str, Set[WebSocketConnection]] = defaultdict(set)
        self.browser_clients: Set[WebSocketConnection] = set()
        self.pending: Dict[int, PendingRequest] = {}
        self.internal_pending: Dict[int, asyncio.Future] = {}
        self.next_request_id = 1

    def root_headers(self, content_type: str = "application/json; charset=utf-8") -> bytes:
        return (
            "HTTP/1.1 200 OK\r\n"
            f"Content-Type: {content_type}\r\n"
            "Cache-Control: no-store\r\n"
            "Connection: close\r\n"
            "\r\n"
        ).encode("utf-8")

    def websocket_url(self, kind: str, value: str) -> str:
        return f"ws://{self.host}:{self.port}/devtools/{kind}/{value}"

    def version_payload(self) -> dict:
        return {
            "Browser": "OpenClaw Browser Relay/0.1",
            "Protocol-Version": "1.3",
            "User-Agent": "OpenClawBrowserRelay",
            "V8-Version": "",
            "WebKit-Version": "",
            "webSocketDebuggerUrl": self.websocket_url("browser", "relay"),
        }

    def list_payload(self) -> list:
        payload = []
        for session_id, item in self.targets_by_session.items():
            payload.append(
                {
                    "description": "",
                    "devtoolsFrontendUrl": "",
                    "id": item["targetId"],
                    "title": item["title"],
                    "type": item["type"],
                    "url": item["url"],
                    "webSocketDebuggerUrl": self.websocket_url("page", session_id),
                }
            )
        return payload

    def browser_targets(self) -> list:
        items = []
        for session_id, item in self.targets_by_session.items():
            items.append(
                {
                    "targetId": item["targetId"],
                    "type": item["type"],
                    "title": item["title"],
                    "url": item["url"],
                    "attached": True,
                    "canAccessOpener": False,
                    "browserContextId": "golem-browser-relay",
                    "sessionId": session_id,
                }
            )
        return items

    def resolve_session_key(self, raw: str) -> Optional[str]:
        if raw in self.targets_by_session:
            return raw
        return self.target_id_to_session.get(raw)

    def attached_page_entries(self) -> list[tuple[str, dict]]:
        return [
            (session_id, item)
            for session_id, item in self.targets_by_session.items()
            if str(item.get("type") or "") == "page"
        ]

    def register_target(self, session_id: str, target_info: dict) -> dict:
        attached_session = str((target_info.get("sessionId") or session_id or "").strip())
        target_id = str(target_info.get("targetId") or attached_session)
        entry = {
            "sessionId": attached_session,
            "targetId": target_id,
            "title": str(target_info.get("title") or target_info.get("url") or ""),
            "url": str(target_info.get("url") or ""),
            "type": str(target_info.get("type") or "page"),
            "attachedAt": iso_now(),
        }
        self.targets_by_session[attached_session] = entry
        self.target_id_to_session[target_id] = attached_session
        return entry

    def unregister_target(self, session_id: str, target_id: str = "") -> None:
        removed = self.targets_by_session.pop(session_id, None)
        if target_id:
            self.target_id_to_session.pop(target_id, None)
        elif removed:
            self.target_id_to_session.pop(removed["targetId"], None)

    async def reset_runtime_state(self) -> None:
        self.targets_by_session.clear()
        self.target_id_to_session.clear()
        for clients in self.page_clients.values():
            for client in list(clients):
                try:
                    await client.close()
                except Exception:
                    pass
        self.page_clients.clear()

    async def register_extension(self, ws: WebSocketConnection) -> None:
        if self.extension and self.extension is not ws:
            try:
                await self.extension.close()
            except Exception:
                pass
        self.extension = ws

    async def unregister_extension(self, ws: WebSocketConnection) -> None:
        if self.extension is ws:
            self.extension = None
            await self.reset_runtime_state()

    async def drop_browser_upstream(self) -> None:
        upstream = self.browser_upstream
        self.browser_upstream = None
        task = self.browser_upstream_task
        self.browser_upstream_task = None
        if task:
            task.cancel()
        if upstream:
            try:
                await upstream.close()
            except Exception:
                pass
        await self.reset_runtime_state()

    async def fetch_browser_http_json(self, path: str) -> dict | list:
        url = BROWSER_CDP_URL.rstrip("/") + path
        return await asyncio.to_thread(load_json_sync, url)

    async def ensure_browser_upstream(self) -> OutgoingWebSocketClient:
        if self.browser_upstream is not None:
            return self.browser_upstream

        version_payload = await self.fetch_browser_http_json("/json/version")
        browser_ws_url = str((version_payload or {}).get("webSocketDebuggerUrl") or "")
        if not browser_ws_url:
            raise RuntimeError(f"browser websocket missing from {BROWSER_CDP_URL}/json/version")

        self.browser_upstream = await OutgoingWebSocketClient.connect(browser_ws_url)
        self.browser_upstream_task = asyncio.create_task(self.browser_upstream_loop())
        return self.browser_upstream

    async def browser_upstream_loop(self) -> None:
        upstream = self.browser_upstream
        if upstream is None:
            return
        try:
            while True:
                message = await upstream.recv()
                if message is None:
                    continue
                await self.route_browser_upstream_message(message)
        except (asyncio.IncompleteReadError, WebSocketClosed):
            pass
        finally:
            await self.drop_browser_upstream()

    async def browser_upstream_command(self, method: str, params: Optional[dict] = None, session_id: str = "") -> dict:
        upstream = await self.ensure_browser_upstream()
        request_id = self.next_request_id
        self.next_request_id += 1
        loop = asyncio.get_running_loop()
        future = loop.create_future()
        self.internal_pending[request_id] = future
        payload = {"id": request_id, "method": method, "params": params or {}}
        if session_id:
            payload["sessionId"] = session_id
        await upstream.send_text(json.dumps(payload))
        return await future

    async def attach_local_target(self, url_prefix: str = "") -> dict:
        targets_payload = await self.fetch_browser_http_json("/json/list")
        page_targets = [
            item for item in targets_payload
            if isinstance(item, dict) and item.get("type") == "page"
        ]
        if url_prefix:
            page_targets = [item for item in page_targets if str(item.get("url") or "").startswith(url_prefix)]
        if not page_targets:
            raise RuntimeError("no page target available for local attach")

        target = page_targets[0]
        existing_session = self.target_id_to_session.get(str(target.get("id") or ""))
        if existing_session:
            return {
                "ok": True,
                "sessionId": existing_session,
                "targetId": str(target.get("id") or ""),
                "title": str(target.get("title") or ""),
                "url": str(target.get("url") or ""),
                "attached": False,
            }

        attach_result = await self.browser_upstream_command(
            "Target.attachToTarget",
            {"targetId": str(target.get("id") or ""), "flatten": True},
        )
        session_id = str(attach_result.get("sessionId") or "")
        if not session_id:
            raise RuntimeError("Target.attachToTarget returned no sessionId")
        entry = self.register_target(session_id, {
            "targetId": str(target.get("id") or ""),
            "title": str(target.get("title") or ""),
            "url": str(target.get("url") or ""),
            "type": str(target.get("type") or "page"),
        })
        refreshed = await self.wait_for_target_state(str(target.get("id") or ""), expected_url_prefix=str(target.get("url") or ""))
        if refreshed:
            entry = refreshed
        return {
            "ok": True,
            "sessionId": session_id,
            "targetId": str(target.get("id") or ""),
            "title": str(entry.get("title") or ""),
            "url": str(entry.get("url") or ""),
            "attached": True,
        }

    def resolve_attached_target(self, selector: str = "") -> tuple[str, dict, str]:
        entries = self.attached_page_entries()
        if not entries:
            raise RuntimeError("no attached page target available")

        wanted = (selector or "").strip()
        if not wanted or wanted == "active":
            return entries[-1][0], entries[-1][1], "active-attached"

        if wanted in self.targets_by_session:
            return wanted, self.targets_by_session[wanted], "session-id"

        session_from_target = self.target_id_to_session.get(wanted)
        if session_from_target:
            return session_from_target, self.targets_by_session[session_from_target], "target-id"

        if wanted.isdigit():
            index = int(wanted)
            if index < 0 or index >= len(entries):
                raise RuntimeError(f"attached page index out of range: {wanted}")
            return entries[index][0], entries[index][1], "index"

        needle = wanted.lower()
        matches = [
            (session_id, item)
            for session_id, item in entries
            if needle in str(item.get("title") or "").lower() or needle in str(item.get("url") or "").lower()
        ]
        if not matches:
            raise RuntimeError(f'no attached page target matched selector "{wanted}"')
        if len(matches) > 1:
            raise RuntimeError(f'ambiguous attached page selector "{wanted}" matched {len(matches)} tabs')
        return matches[0][0], matches[0][1], "selector-match"

    async def refresh_target_from_browser(self, target_id: str) -> Optional[dict]:
        targets_payload = await self.fetch_browser_http_json("/json/list")
        for item in targets_payload:
            if not isinstance(item, dict):
                continue
            if str(item.get("id") or item.get("targetId") or "") != target_id:
                continue
            session_id = self.target_id_to_session.get(target_id)
            if not session_id:
                return None
            entry = self.targets_by_session.get(session_id)
            if not entry:
                return None
            entry["title"] = str(item.get("title") or item.get("url") or "")
            entry["url"] = str(item.get("url") or "")
            entry["type"] = str(item.get("type") or entry.get("type") or "page")
            return entry
        return None

    async def wait_for_target_state(self, target_id: str, expected_url_prefix: str = "", timeout: float = 8.0) -> Optional[dict]:
        deadline = time.monotonic() + timeout
        last_entry = None
        while time.monotonic() < deadline:
            refreshed = await self.refresh_target_from_browser(target_id)
            if refreshed:
                last_entry = refreshed
                if not expected_url_prefix or str(refreshed.get("url") or "").startswith(expected_url_prefix):
                    return refreshed
            await asyncio.sleep(0.25)
        return last_entry

    async def open_new_tab(self, url: str) -> dict:
        create_result = await self.browser_upstream_command("Target.createTarget", {"url": url})
        target_id = str(create_result.get("targetId") or "")
        if not target_id:
            raise RuntimeError("Target.createTarget returned no targetId")

        attach_result = await self.browser_upstream_command(
            "Target.attachToTarget",
            {"targetId": target_id, "flatten": True},
        )
        session_id = str(attach_result.get("sessionId") or "")
        if not session_id:
            raise RuntimeError("Target.attachToTarget returned no sessionId for new target")

        entry = self.register_target(
            session_id,
            {
                "targetId": target_id,
                "title": url,
                "url": url,
                "type": "page",
            },
        )
        refreshed = await self.wait_for_target_state(target_id, expected_url_prefix=url)
        if refreshed:
            entry = refreshed
        return {
            "ok": True,
            "action": "open",
            "targetMode": "new-tab",
            "requestedUrl": url,
            "sessionId": session_id,
            "targetId": target_id,
            "title": str(entry.get("title") or ""),
            "url": str(entry.get("url") or ""),
            "attached": True,
        }

    async def navigate_attached_target(self, url: str, selector: str = "") -> dict:
        session_id, entry, target_mode = self.resolve_attached_target(selector)
        target_id = str(entry.get("targetId") or "")
        await self.browser_upstream_command("Page.navigate", {"url": url}, session_id=session_id)
        entry["url"] = url
        refreshed = await self.wait_for_target_state(target_id, expected_url_prefix=url)
        if refreshed:
            entry = refreshed
        return {
            "ok": True,
            "action": "navigate",
            "targetMode": target_mode,
            "targetSelector": selector,
            "requestedUrl": url,
            "sessionId": session_id,
            "targetId": target_id,
            "title": str(entry.get("title") or ""),
            "url": str(entry.get("url") or ""),
            "attached": True,
        }

    async def navigate(self, url: str, selector: str = "", new_tab: bool = False) -> dict:
        parsed = urlsplit(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise RuntimeError("navigate requires a full http:// or https:// URL")
        await self.ensure_browser_upstream()
        if new_tab:
            return await self.open_new_tab(url)
        return await self.navigate_attached_target(url, selector=selector)

    async def route_extension_message(self, raw: str) -> None:
        try:
            msg = json.loads(raw)
        except Exception:
            return

        if msg.get("method") == "pong":
            return

        if isinstance(msg.get("id"), int) and ("result" in msg or "error" in msg):
            pending = self.pending.pop(msg["id"], None)
            if not pending:
                return
            outbound = {"id": pending.original_id}
            if "error" in msg:
                outbound["error"] = {"message": str(msg["error"])}
            else:
                outbound["result"] = msg.get("result", {})
            await pending.client.send_text(json.dumps(outbound))
            return

        if msg.get("method") != "forwardCDPEvent":
            return

        params = msg.get("params") or {}
        session_id = str(params.get("sessionId") or "")
        method = str(params.get("method") or "")
        event_params = params.get("params") or {}

        if method == "Target.attachedToTarget":
            self.register_target(str((event_params.get("sessionId") or session_id or "").strip()), event_params.get("targetInfo") or {})
        elif method == "Target.detachedFromTarget":
            self.unregister_target(str((event_params.get("sessionId") or session_id or "").strip()), str(event_params.get("targetId") or ""))

        if session_id:
            for client in list(self.page_clients.get(session_id, set())):
                outbound = {"method": method, "params": event_params}
                if session_id:
                    outbound["sessionId"] = session_id
                await client.send_text(json.dumps(outbound))

    async def route_browser_upstream_message(self, raw: str) -> None:
        try:
            msg = json.loads(raw)
        except Exception:
            return

        if isinstance(msg.get("id"), int) and ("result" in msg or "error" in msg):
            pending = self.pending.pop(msg["id"], None)
            if pending:
                outbound = {"id": pending.original_id}
                if "error" in msg:
                    outbound["error"] = {"message": str(msg["error"])}
                else:
                    outbound["result"] = msg.get("result", {})
                await pending.client.send_text(json.dumps(outbound))
                return

            internal = self.internal_pending.pop(msg["id"], None)
            if internal and not internal.done():
                if "error" in msg:
                    internal.set_exception(RuntimeError(str(msg["error"])))
                else:
                    internal.set_result(msg.get("result", {}))
                return

        method = str(msg.get("method") or "")
        params = msg.get("params") or {}
        session_id = str(msg.get("sessionId") or "")

        if method == "Target.attachedToTarget":
            self.register_target(str((params.get("sessionId") or session_id or "").strip()), params.get("targetInfo") or {})
        elif method == "Target.detachedFromTarget":
            self.unregister_target(str((params.get("sessionId") or session_id or "").strip()), str(params.get("targetId") or ""))

        if session_id:
            for client in list(self.page_clients.get(session_id, set())):
                outbound = {"method": method, "params": params, "sessionId": session_id}
                await client.send_text(json.dumps(outbound))

    async def forward_page_command(self, ws: WebSocketConnection, session_key: str, payload: dict) -> None:
        if self.extension:
            relay_id = self.next_request_id
            self.next_request_id += 1
            self.pending[relay_id] = PendingRequest(client=ws, original_id=int(payload.get("id", 0)), client_kind="page")
            outbound = {
                "id": relay_id,
                "method": "forwardCDPCommand",
                "params": {
                    "sessionId": session_key,
                    "method": payload.get("method"),
                    "params": payload.get("params", {}),
                },
            }
            await self.extension.send_text(json.dumps(outbound))
            return

        if self.browser_upstream is None:
            await ws.send_text(json.dumps({"id": payload.get("id"), "error": {"message": "relay attach not active"}}))
            return

        relay_id = self.next_request_id
        self.next_request_id += 1
        self.pending[relay_id] = PendingRequest(client=ws, original_id=int(payload.get("id", 0)), client_kind="page")
        outbound = {
            "id": relay_id,
            "method": payload.get("method"),
            "params": payload.get("params", {}),
            "sessionId": session_key,
        }
        await self.browser_upstream.send_text(json.dumps(outbound))

    async def handle_browser_command(self, ws: WebSocketConnection, payload: dict) -> None:
        if "id" not in payload:
            return
        request_id = int(payload.get("id", 0))
        method = str(payload.get("method") or "")
        params = payload.get("params") or {}

        if method == "Browser.getVersion":
            await ws.send_text(json.dumps({"id": request_id, "result": self.version_payload()}))
            return

        if method == "Target.getTargets":
            await ws.send_text(json.dumps({"id": request_id, "result": {"targetInfos": self.browser_targets()}}))
            return

        if self.extension:
            relay_id = self.next_request_id
            self.next_request_id += 1
            self.pending[relay_id] = PendingRequest(client=ws, original_id=request_id, client_kind="browser")
            outbound = {
                "id": relay_id,
                "method": "forwardCDPCommand",
                "params": {
                    "method": method,
                    "params": params,
                },
            }
            await self.extension.send_text(json.dumps(outbound))
            return

        if self.browser_upstream is None:
            await ws.send_text(json.dumps({"id": request_id, "error": {"message": "relay attach not active"}}))
            return

        relay_id = self.next_request_id
        self.next_request_id += 1
        self.pending[relay_id] = PendingRequest(client=ws, original_id=request_id, client_kind="browser")
        outbound = {
            "id": relay_id,
            "method": method,
            "params": params,
        }
        await self.browser_upstream.send_text(json.dumps(outbound))


async def websocket_handshake(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, path: str, headers: Dict[str, str]) -> WebSocketConnection:
    key = headers.get("sec-websocket-key", "")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("utf-8")).digest()).decode("ascii")
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n"
        "\r\n"
    )
    writer.write(response.encode("utf-8"))
    await writer.drain()
    return WebSocketConnection(reader, writer, path)


async def handle_extension_socket(state: RelayState, ws: WebSocketConnection) -> None:
    await state.register_extension(ws)
    try:
        while True:
            message = await ws.recv()
            if message is None:
                continue
            await state.route_extension_message(message)
    except (asyncio.IncompleteReadError, WebSocketClosed):
        pass
    finally:
        await state.unregister_extension(ws)


async def handle_page_socket(state: RelayState, ws: WebSocketConnection, key: str) -> None:
    session_key = state.resolve_session_key(key)
    if not session_key:
        await ws.send_text(json.dumps({"id": 0, "error": {"message": f"unknown page session {key}"}}))
        await ws.close()
        return
    state.page_clients[session_key].add(ws)
    try:
        while True:
            message = await ws.recv()
            if message is None:
                continue
            payload = json.loads(message)
            await state.forward_page_command(ws, session_key, payload)
    except (asyncio.IncompleteReadError, WebSocketClosed):
        pass
    finally:
        state.page_clients[session_key].discard(ws)


async def handle_browser_socket(state: RelayState, ws: WebSocketConnection) -> None:
    state.browser_clients.add(ws)
    try:
        while True:
            message = await ws.recv()
            if message is None:
                continue
            payload = json.loads(message)
            await state.handle_browser_command(ws, payload)
    except (asyncio.IncompleteReadError, WebSocketClosed):
        pass
    finally:
        state.browser_clients.discard(ws)


async def write_json(writer: asyncio.StreamWriter, payload: dict | list) -> None:
    body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    headers = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Cache-Control: no-store\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode("utf-8")
    writer.write(headers + body)
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def write_text(writer: asyncio.StreamWriter, body: str = "") -> None:
    payload = body.encode("utf-8")
    headers = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        f"Content-Length: {len(payload)}\r\n"
        "Cache-Control: no-store\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode("utf-8")
    writer.write(headers + payload)
    await writer.drain()
    writer.close()
    await writer.wait_closed()


async def handle_client(state: RelayState, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        request_line = await reader.readline()
        if not request_line:
            writer.close()
            await writer.wait_closed()
            return
        method, raw_path, _ = request_line.decode("utf-8", errors="replace").strip().split(" ", 2)
        headers: Dict[str, str] = {}
        while True:
            line = await reader.readline()
            if line in (b"\r\n", b"\n", b""):
                break
            name, value = line.decode("utf-8", errors="replace").split(":", 1)
            headers[name.strip().lower()] = value.strip()

        path = raw_path.split("?", 1)[0]
        is_upgrade = headers.get("upgrade", "").lower() == "websocket"

        if is_upgrade and path == "/extension":
            ws = await websocket_handshake(reader, writer, path, headers)
            await handle_extension_socket(state, ws)
            return
        if is_upgrade and path.startswith("/devtools/page/"):
            ws = await websocket_handshake(reader, writer, path, headers)
            key = path.rsplit("/", 1)[-1]
            await handle_page_socket(state, ws, key)
            return
        if is_upgrade and path == "/devtools/browser/relay":
            ws = await websocket_handshake(reader, writer, path, headers)
            await handle_browser_socket(state, ws)
            return

        if path == "/json/version":
            await write_json(writer, state.version_payload())
            return
        if path == "/json/list":
            await write_json(writer, state.list_payload())
            return
        if path == "/json/new":
            raw_query = raw_path.split("?", 1)[1] if "?" in raw_path else ""
            navigate_url = ""
            if raw_query and "=" not in raw_query:
                navigate_url = unquote(raw_query)
            if not navigate_url:
                query = parse_qs(raw_query, keep_blank_values=True)
                navigate_url = (query.get("url") or [""])[0]
            try:
                payload = await state.navigate(navigate_url, new_tab=True)
                await write_json(
                    writer,
                    {
                        "description": "",
                        "devtoolsFrontendUrl": "",
                        "id": payload["targetId"],
                        "title": payload["title"],
                        "type": "page",
                        "url": payload["url"],
                        "webSocketDebuggerUrl": state.websocket_url("page", payload["sessionId"]),
                    },
                )
            except Exception as exc:
                await write_json(writer, {"ok": False, "error": str(exc), "url": navigate_url, "browser_cdp_url": BROWSER_CDP_URL})
            return
        if path == "/admin/attach":
            query = parse_qs(raw_path.split("?", 1)[1] if "?" in raw_path else "", keep_blank_values=True)
            url_prefix = (query.get("url_prefix") or [""])[0]
            try:
                payload = await state.attach_local_target(url_prefix=url_prefix)
                await write_json(writer, payload)
            except Exception as exc:
                await write_json(writer, {"ok": False, "error": str(exc), "url_prefix": url_prefix, "browser_cdp_url": BROWSER_CDP_URL})
            return
        if path == "/admin/navigate":
            query = parse_qs(raw_path.split("?", 1)[1] if "?" in raw_path else "", keep_blank_values=True)
            navigate_url = (query.get("url") or [""])[0]
            selector = (query.get("selector") or [""])[0]
            new_tab = (query.get("new_tab") or ["0"])[0].lower() in {"1", "true", "yes", "on"}
            try:
                payload = await state.navigate(navigate_url, selector=selector, new_tab=new_tab)
                await write_json(writer, payload)
            except Exception as exc:
                await write_json(
                    writer,
                    {
                        "ok": False,
                        "error": str(exc),
                        "url": navigate_url,
                        "selector": selector,
                        "new_tab": new_tab,
                        "browser_cdp_url": BROWSER_CDP_URL,
                    },
                )
            return
        if path == "/":
            if method.upper() == "HEAD":
                writer.write(
                    b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                )
                await writer.drain()
                writer.close()
                await writer.wait_closed()
            else:
                await write_text(writer, "OpenClaw Browser Relay\n")
            return

        writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        await writer.drain()
        writer.close()
        await writer.wait_closed()
    except Exception:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def main() -> None:
    state = RelayState(HOST, PORT)
    server = await asyncio.start_server(lambda r, w: handle_client(state, r, w), HOST, PORT)
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()

    def request_stop() -> None:
        stop.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, request_stop)
        except NotImplementedError:
            pass

    async with server:
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
