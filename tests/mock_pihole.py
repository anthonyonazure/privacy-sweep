#!/usr/bin/env python3
"""A tiny Pi-hole v6 stand-in for local tests. Not a Pi-hole.

Listens on 127.0.0.1. Prints the chosen port on stdout, then serves until killed.
Password is test-secret. Records every request in the process; tests inspect
behavior through the HTTP API itself (lists persist in memory).
"""

from __future__ import annotations

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests" / "fixtures" / "pihole"
PASSWORD = "test-secret"
SID = "test-sid"

BLP = "https://raw.githubusercontent.com/blocklistproject/Lists/master/smart-tv.txt"


def load_queries() -> dict:
    return json.loads((FIXTURE / "queries.json").read_text(encoding="utf-8"))


SPEC = load_queries()


def item_stamp(item: dict) -> int:
    """Ages in the fixture are relative to 'now' so a live API window still hits them."""
    return int(time.time()) - int(item.get("age", 0))


def in_window(item: dict, start: int, end: int) -> bool:
    stamp = item_stamp(item)
    return start <= stamp <= end


class State:
    def __init__(self) -> None:
        self.lists = [{"address": BLP, "enabled": True, "type": "block", "comment": "already installed"}]
        self.regexes: list[str] = []
        self.gravity = 0
        self.posts: list[str] = []


STATE = State()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        return

    def _read(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def _send(self, code: int, payload: dict | None) -> None:
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth_ok(self) -> bool:
        return self.headers.get("X-FTL-SID") == SID

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)
        if path == "/api/info/version":
            self._send(200, {"version": {"core": "v6", "ftl": "v6"}})
            return
        if path == "/api/lists":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            self._send(200, {"lists": STATE.lists})
            return
        if path == "/api/domains/deny/regex":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            self._send(200, {"domains": [{"domain": item, "type": "deny", "kind": "regex"} for item in STATE.regexes]})
            return
        if path == "/api/stats/database/summary":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            start, end = int(float(qs["from"][0])), int(float(qs["until"][0]))
            rows = [item for item in SPEC["queries"] if in_window(item, start, end)]
            blocked = sum(1 for item in rows if int(item["status"]) in (1, 4, 5, 6, 7, 8, 9, 10, 11, 15, 16, 18))
            self._send(200, {"sum_queries": len(rows), "sum_blocked": blocked, "total_clients": len({i["client"] for i in rows})})
            return
        if path == "/api/history/database/clients":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            start, end = int(float(qs["from"][0])), int(float(qs["until"][0]))
            names = {item["ip"]: item.get("name") or "" for item in SPEC["clients"]}
            totals: dict[str, int] = {}
            for item in SPEC["queries"]:
                if in_window(item, start, end):
                    totals[item["client"]] = totals.get(item["client"], 0) + 1
            clients = {ip: {"name": names.get(ip, ""), "total": count} for ip, count in totals.items()}
            self._send(200, {"clients": clients, "history": []})
            return
        if path == "/api/stats/database/top_domains":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            start, end = int(float(qs["from"][0])), int(float(qs["until"][0]))
            counts: dict[str, int] = {}
            for item in SPEC["queries"]:
                if in_window(item, start, end) and int(item["status"]) == 1:
                    counts[item["domain"]] = counts.get(item["domain"], 0) + 1
            domains = [{"domain": name, "count": count} for name, count in sorted(counts.items(), key=lambda pair: -pair[1])]
            self._send(200, {"domains": domains, "total_queries": 0, "blocked_queries": sum(counts.values())})
            return
        if path == "/api/queries":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            needle = ""
            for key, values in qs.items():
                if "search" in key and values:
                    needle = values[0].lower()
            start = int(float(qs.get("from", ["0"])[0]))
            end = int(float(qs.get("until", ["0"])[0]))
            names = {item["ip"]: item.get("name") or "" for item in SPEC["clients"]}
            found = []
            for item in SPEC["queries"]:
                stamp = item_stamp(item)
                # /api/queries treats `until` as exclusive
                if stamp < start or stamp >= end:
                    continue
                if needle and needle not in item["domain"].lower():
                    continue
                status = "GRAVITY" if int(item["status"]) == 1 else "FORWARDED"
                found.append(
                    {
                        "domain": item["domain"],
                        "status": status,
                        "time": stamp,
                        "client": {"ip": item["client"], "name": names.get(item["client"], "")},
                    }
                )
            self._send(200, {"queries": found, "cursor": None})
            return
        if path == "/api/network/devices":
            if not self._auth_ok():
                self._send(401, {"error": "unauthorized"})
                return
            payload = json.loads((FIXTURE / "devices.json").read_text(encoding="utf-8"))
            self._send(200, payload)
            return
        self._send(404, {"error": "not found", "path": path})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)
        body = self._read()
        STATE.posts.append(path + ("?" + parsed.query if parsed.query else ""))
        if path == "/api/auth":
            if body.get("password") != PASSWORD:
                self._send(401, {"session": {"valid": False}})
                return
            self._send(200, {"session": {"valid": True, "sid": SID, "csrf": "csrf", "validity": 1800}})
            return
        if not self._auth_ok():
            self._send(401, {"error": "unauthorized"})
            return
        if path == "/api/lists":
            if qs.get("type", [None])[0] != "block" and body.get("type") != "block":
                self._send(400, {"key": "bad_request", "message": "Specify type parameter (should be either \"allow\" or \"block\")"})
                return
            address = body.get("address")
            if not address:
                self._send(400, {"message": "address required"})
                return
            STATE.lists.append({"address": address, "enabled": True, "type": "block", "comment": body.get("comment")})
            self._send(201, {"lists": [STATE.lists[-1]]})
            return
        if path == "/api/domains/deny/regex":
            domain = body.get("domain")
            if domain and domain not in STATE.regexes:
                STATE.regexes.append(domain)
            self._send(201, {"domains": [{"domain": domain}]})
            return
        if path == "/api/action/gravity":
            STATE.gravity += 1
            self._send(200, {"status": "ok"})
            return
        self._send(404, {"error": "not found", "path": path})

    def do_DELETE(self) -> None:  # noqa: N802
        if urlparse(self.path).path == "/api/auth":
            self._send(204, None)
            return
        self._send(404, {"error": "not found"})


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
