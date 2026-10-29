#!/usr/bin/env python3
"""Pi-hole helper for the privacy-sweep network scripts.

The shell scripts in network/ are the interface (dry-run, ask, --yes). This
file talks to Pi-hole and reads the long-term query database. It never
deletes queries. The only write it performs is adding a blocklist (and an
optional regex) when the shell script has already decided to apply.

Pi-hole v6 is the supported API. v5 api.php can answer a few read-only
questions and is documented in the pihole-tv README; adding a list on v5 is
done by inserting into a local gravity database when you point
PIHOLE_GRAVITY_DB at one.

A --fixture directory stands in for the server so the scripts can be tried
with no Pi-hole on the network.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import adguard

BLOCKED_STATUSES = (1, 4, 5, 6, 7, 8, 9, 10, 11, 15, 16, 18)
ALPHONSO_REGEX = r"(^|\.)alphonso\.tv$"
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_LISTS = REPO / "network" / "pihole-tv" / "lists.txt"
DEFAULT_KEEPS = REPO / "network" / "pihole-tv" / "keep.txt"
DEFAULT_SUFFIXES = REPO / "network" / "pihole-tv" / "acr-suffixes.txt"
KNOWN_BRANDS = ("samsung", "lg", "roku", "firetv", "vizio", "hisense")
BRANDS_WITH_LISTS = ("samsung", "lg", "roku", "firetv")
NO_NATIVE_LIST = {
    "vizio": (
        "Vizio has no HaGeZi native list. native.vizio.txt returned HTTP 404 on 2026-10-27. "
        "Coverage is the combined lists (tvinteractive.tv / Inscape)."
    ),
    "hisense": (
        "Hisense VIDAA has no HaGeZi native list. native.vidaa.txt and native.hisense.txt "
        "returned HTTP 404 on 2026-10-27. Do not block all of vidaahub.com or hismarttv.com. "
        "The combined lists carry the Hisense names they know about."
    ),
}
DOMAIN_RE = re.compile(
    r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$"
)
DEFAULT_DB = Path("/etc/pihole/pihole-FTL.db")
DEFAULT_GRAVITY = Path("/etc/pihole/gravity.db")


class PiHoleError(Exception):
    """A problem the user can act on. The message is safe to print."""


def _safe_ident(name: str) -> str:
    """Column names come from the database itself. Keep them plain."""
    if not name or not name.replace("_", "").isalnum():
        raise PiHoleError(f"Refusing unexpected column name {name!r} in the Pi-hole database.")
    return name


def _password() -> str | None:
    """Read the Pi-hole password from the environment, never from argv."""
    inline = os.environ.get("PIHOLE_PASSWORD")
    if inline:
        return inline
    path = os.environ.get("PIHOLE_PASSWORD_FILE")
    if not path:
        return None
    file = Path(path)
    if not file.is_file():
        raise PiHoleError(f"PIHOLE_PASSWORD_FILE does not exist: {path}")
    text = file.read_text(encoding="utf-8")
    if text.endswith("\n"):
        text = text[:-1]
    if text.endswith("\r"):
        text = text[:-1]
    return text or None


def _check_url(url: str) -> str:
    url = url.rstrip("/")
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise PiHoleError("PIHOLE_URL must look like http://192.168.1.2 or http://pi.hole")
    if parsed.username or parsed.password or "@" in parsed.netloc:
        raise PiHoleError("Put the password in PIHOLE_PASSWORD, not in the URL.")
    # People paste the admin page. The API lives at the origin.
    if parsed.path.rstrip("/") == "/admin":
        url = urllib.parse.urlunparse(parsed._replace(path="", query="", fragment=""))
        url = url.rstrip("/")
    elif parsed.path not in ("", "/"):
        raise PiHoleError("PIHOLE_URL should be the Pi-hole origin, without /admin or /api.")
    return url


def parse_brands(values: list[str], vendor: bool) -> set[str]:
    """Brand ids whose HaGeZi list should be added. Empty means the combined lists only."""
    chosen: list[str] = []
    for value in values:
        for part in value.split(","):
            part = part.strip().lower()
            if part:
                chosen.append(part)
    if chosen:
        bad = [brand for brand in chosen if brand not in KNOWN_BRANDS]
        if bad:
            known = ", ".join(KNOWN_BRANDS)
            raise PiHoleError(f"Unknown brand {', '.join(bad)}. Known brands: {known}.")
        return set(chosen)
    if vendor:
        return set(BRANDS_WITH_LISTS)
    return set()


def load_lists(path: Path, brands: set[str]) -> list[dict]:
    """Read lists.txt. Lines are: tier|brand|name|note|url.

    Default rows are always included. A brand row is included when its brand
    was selected. ``brands`` empty means the combined lists only.
    """
    rows = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 5:
            raise PiHoleError(f"{path}:{lineno}: expected tier|brand|name|note|url")
        tier, brand, name, note, url = (part.strip() for part in parts)
        if tier not in ("default", "brand"):
            raise PiHoleError(f"{path}:{lineno}: tier must be default or brand")
        if tier == "default":
            if brand != "*":
                raise PiHoleError(f"{path}:{lineno}: a default list uses brand *")
        elif brand not in KNOWN_BRANDS:
            raise PiHoleError(f"{path}:{lineno}: unknown brand {brand}")
        elif brand not in brands:
            continue
        if not url.startswith("https://"):
            raise PiHoleError(f"{path}:{lineno}: refusing a non-https list URL")
        rows.append({"tier": tier, "brand": brand, "name": name, "note": note, "url": url})
    if not rows:
        raise PiHoleError(f"No lists selected in {path}")
    return rows


def load_keeps(path: Path) -> list[dict]:
    """Read keep.txt. Lines are: action|brand|domain|scope|note."""
    rows = []
    seen: set[tuple[str, str]] = set()
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) != 5:
            raise PiHoleError(f"{path}:{lineno}: expected action|brand|domain|scope|note")
        action, brand, domain, scope, note = (part.strip() for part in parts)
        if action not in ("allow", "watch"):
            raise PiHoleError(f"{path}:{lineno}: action must be allow or watch")
        if brand not in KNOWN_BRANDS:
            raise PiHoleError(f"{path}:{lineno}: unknown brand {brand}")
        if scope not in ("exact", "tree"):
            raise PiHoleError(f"{path}:{lineno}: scope must be exact or tree")
        domain = domain.lower().rstrip(".")
        if not DOMAIN_RE.match(domain):
            raise PiHoleError(f"{path}:{lineno}: domain looks unsafe: {domain}")
        key = (action, domain)
        if key in seen:
            raise PiHoleError(f"{path}:{lineno}: duplicate {action} domain {domain}")
        seen.add(key)
        rows.append(
            {"action": action, "brand": brand, "domain": domain, "scope": scope, "note": note}
        )
    if not rows:
        raise PiHoleError(f"No keep-list rows in {path}")
    return rows


def allow_rows(keeps: list[dict]) -> list[dict]:
    return [row for row in keeps if row["action"] == "allow"]


def watch_rows(keeps: list[dict]) -> list[dict]:
    return [row for row in keeps if row["action"] == "watch"]


def tree_regex(domain: str) -> str:
    """Pi-hole POSIX regex: this name and its subdomains, not a lookalike."""
    return r"(^|\.)" + domain.replace(".", r"\.") + "$"


def adguard_rule(row: dict) -> str:
    """Exception rule. Exact names stay exact so a child ad host stays blocked."""
    if row["scope"] == "tree":
        return f"@@||{row['domain']}^"
    return f"@@{row['domain']}"


def protected_domains(allows: list[dict]) -> set[str]:
    return {row["domain"] for row in allows}


def load_suffixes(path: Path) -> list[tuple[str, str]]:
    """Return (suffix, label) pairs. A suffix is a DNS name, not a regex."""
    rows = []
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            raise PiHoleError(f"{path}:{lineno}: expected 'suffix label'")
        suffix, label = parts[0].lower().rstrip("."), parts[1]
        if not suffix or any(c in suffix for c in " /\\*?|\"'"):
            raise PiHoleError(f"{path}:{lineno}: suffix looks unsafe: {suffix}")
        rows.append((suffix, label))
    return rows


def domain_matches(domain: str, suffix: str) -> bool:
    name = domain.lower().rstrip(".")
    return name == suffix or name.endswith("." + suffix)


def matching_suffix(domain: str, suffixes: list[tuple[str, str]]) -> tuple[str, str] | None:
    for suffix, label in suffixes:
        if domain_matches(domain, suffix):
            return suffix, label
    return None


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME")
    root = Path(base) if base else Path.home() / ".local" / "state"
    return root / "privacy-sweep"


def _write_private(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)


def _connect_ro(path: Path) -> sqlite3.Connection:
    uri = "file:" + urllib.parse.quote(str(path)) + "?mode=ro"
    try:
        con = sqlite3.connect(uri, uri=True, timeout=5)
    except sqlite3.Error as exc:
        raise PiHoleError(
            f"Could not read {path}: {exc}. "
            "If Pi-hole has the file open, copy it with: "
            'sqlite3 /etc/pihole/pihole-FTL.db ".backup ~/pihole-FTL.db.backup"'
        ) from exc
    con.row_factory = sqlite3.Row
    return con


def _table_exists(con: sqlite3.Connection, name: str) -> bool:
    row = con.execute(
        "SELECT 1 FROM sqlite_master WHERE name = ? AND type IN ('table', 'view')",
        (name,),
    ).fetchone()
    return row is not None


def _client_names(con: sqlite3.Connection) -> dict[str, str]:
    if not _table_exists(con, "client_by_id"):
        return {}
    names: dict[str, str] = {}
    for row in con.execute("SELECT ip, name FROM client_by_id"):
        ip = row["ip"] or ""
        name = (row["name"] or "").strip()
        if ip and name and ip not in names:
            names[ip] = name
    return names


def _build_v6_memory(spec: dict) -> sqlite3.Connection:
    """Build the same view the report SQL uses, from a fixture description."""
    now = int(spec.get("now") or time.time())
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.executescript(
        """
        CREATE TABLE domain_by_id (id INTEGER PRIMARY KEY, domain TEXT);
        CREATE TABLE client_by_id (id INTEGER PRIMARY KEY, ip TEXT, name TEXT);
        CREATE TABLE query_storage (
            id INTEGER PRIMARY KEY,
            timestamp INTEGER,
            type INTEGER,
            status INTEGER,
            domain INTEGER,
            client INTEGER
        );
        CREATE VIEW queries AS
          SELECT q.id, q.timestamp, q.status,
                 d.domain AS domain, c.ip AS client
          FROM query_storage q
          JOIN domain_by_id d ON d.id = q.domain
          JOIN client_by_id c ON c.id = q.client;
        """
    )
    clients = {}
    domains = {}
    for item in spec.get("clients") or []:
        ip = item["ip"]
        if ip not in clients:
            clients[ip] = (len(clients) + 1, item.get("name") or "")
            con.execute(
                "INSERT INTO client_by_id (id, ip, name) VALUES (?, ?, ?)",
                (clients[ip][0], ip, clients[ip][1]),
            )
    qid = 1
    for item in spec.get("queries") or []:
        if "timestamp" in item:
            stamp = int(item["timestamp"])
        else:
            stamp = now - int(item.get("age", 0))
        domain = item["domain"]
        ip = item["client"]
        if ip not in clients:
            clients[ip] = (len(clients) + 1, "")
            con.execute(
                "INSERT INTO client_by_id (id, ip, name) VALUES (?, ?, ?)",
                (clients[ip][0], ip, ""),
            )
        if domain not in domains:
            domains[domain] = len(domains) + 1
            con.execute(
                "INSERT INTO domain_by_id (id, domain) VALUES (?, ?)",
                (domains[domain], domain),
            )
        con.execute(
            "INSERT INTO query_storage (id, timestamp, type, status, domain, client) "
            "VALUES (?, ?, 1, ?, ?, ?)",
            (qid, stamp, int(item.get("status", 2)), domains[domain], clients[ip][0]),
        )
        qid += 1
    con.commit()
    return con


class Report:
    def __init__(self) -> None:
        self.source = ""
        self.note = ""
        self.start = 0
        self.end = 0
        self.total = 0
        self.blocked = 0
        self.clients: list[dict] = []
        self.blocked_domains: list[dict] = []
        self.acr: list[dict] = []
        self.truncated = False
        self.all_client_ips: list[tuple[str, str]] = []


def _report_from_db(
    con: sqlite3.Connection,
    start: int,
    end: int,
    suffixes: list[tuple[str, str]],
    top: int,
) -> Report:
    if not _table_exists(con, "queries"):
        raise PiHoleError("This database has no queries table or view.")
    report = Report()
    report.start = start
    report.end = end
    names = _client_names(con)
    report.total = con.execute(
        "SELECT COUNT(*) FROM queries WHERE timestamp >= ? AND timestamp <= ?",
        (start, end),
    ).fetchone()[0]
    placeholders = ",".join("?" * len(BLOCKED_STATUSES))
    report.blocked = con.execute(
        f"SELECT COUNT(*) FROM queries WHERE timestamp >= ? AND timestamp <= ? "
        f"AND status IN ({placeholders})",
        (start, end, *BLOCKED_STATUSES),
    ).fetchone()[0]
    rows = con.execute(
        "SELECT client, COUNT(*) AS n FROM queries "
        "WHERE timestamp >= ? AND timestamp <= ? "
        "GROUP BY client ORDER BY n DESC",
        (start, end),
    ).fetchall()
    for row in rows:
        ip = row["client"] or ""
        report.all_client_ips.append((ip, names.get(ip, "")))
    report.clients = []
    for row in rows[:top]:
        ip = row["client"] or ""
        report.clients.append({"ip": ip, "name": names.get(ip, ""), "count": row["n"]})
    domain_rows = con.execute(
        f"SELECT domain, COUNT(*) AS n FROM queries "
        f"WHERE timestamp >= ? AND timestamp <= ? AND status IN ({placeholders}) "
        f"GROUP BY domain ORDER BY n DESC LIMIT ?",
        (start, end, *BLOCKED_STATUSES, top),
    ).fetchall()
    report.blocked_domains = [{"domain": r["domain"], "count": r["n"]} for r in domain_rows]
    hits: dict[tuple[str, str, str], dict] = {}
    for row in con.execute(
        "SELECT client, domain, status, COUNT(*) AS n FROM queries "
        "WHERE timestamp >= ? AND timestamp <= ? GROUP BY client, domain, status",
        (start, end),
    ):
        matched = matching_suffix(row["domain"] or "", suffixes)
        if not matched:
            continue
        suffix, label = matched
        ip = row["client"] or ""
        key = (ip, row["domain"], suffix)
        item = hits.get(key)
        if item is None:
            item = {
                "ip": ip,
                "name": names.get(ip, ""),
                "domain": row["domain"],
                "suffix": suffix,
                "label": label,
                "count": 0,
                "blocked": 0,
            }
            hits[key] = item
        item["count"] += row["n"]
        if row["status"] in BLOCKED_STATUSES:
            item["blocked"] += row["n"]
    report.acr = sorted(hits.values(), key=lambda item: (-item["count"], item["domain"]))
    return report


def render_markdown(report: Report, suffixes_path: Path, new_clients: list[tuple[str, str]], baseline: bool) -> str:
    def esc(value: object) -> str:
        return str(value).replace("|", "\\|").replace("\n", " ")

    start = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(report.start))
    end = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(report.end))
    lines = [
        "# Pi-hole privacy report",
        "",
        f"- Generated: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime())}",
        f"- Window: {start} through {end}",
        f"- Source: {report.source}",
        "",
        "This is a read-only summary of DNS lookups your Pi-hole already stored.",
        "It does not change blocklists and it does not delete the query log.",
        "",
        "## Summary",
        "",
        f"- Queries in the window: {report.total}",
        f"- Blocked: {report.blocked}",
        f"- Distinct clients: {len(report.all_client_ips)}",
        "",
    ]
    if report.note:
        lines.extend([report.note, ""])
    lines.extend(["## Top clients", ""])
    if report.clients:
        lines.extend(["| Client | Name | Queries |", "| --- | --- | --- |"])
        for row in report.clients:
            lines.append(f"| {esc(row['ip'])} | {esc(row['name'])} | {row['count']} |")
    else:
        lines.append("No queries in this window.")
    lines.extend(["", "## Top blocked domains", ""])
    if report.blocked_domains:
        lines.extend(["| Domain | Blocked queries |", "| --- | --- |"])
        for row in report.blocked_domains:
            lines.append(f"| {esc(row['domain'])} | {row['count']} |")
    else:
        lines.append("No blocked queries in this window.")
    lines.extend(["", "## New clients since last run", ""])
    if baseline:
        lines.append(
            "No earlier client list was found. This run is the baseline. "
            "The clients seen here are not marked as new. They are remembered "
            "only when you save the report."
        )
    elif not new_clients:
        lines.append("No client IP in this window was absent from the saved list.")
    else:
        lines.extend(["| Client | Name |", "| --- | --- |"])
        for ip, name in new_clients:
            lines.append(f"| {esc(ip)} | {esc(name)} |")
    lines.extend(
        [
            "",
            "## ACR and smart-TV telemetry",
            "",
            "A row here means some device looked up a name ending in one of the",
            f"suffixes in `{suffixes_path.name}`. That is a lead, not proof the",
            "TV recorded the picture on screen. Blocked and allowed lookups both count.",
            "",
        ]
    )
    if report.acr:
        lines.extend(
            [
                "| Client | Name | Domain | Label | Queries | Of which blocked |",
                "| --- | --- | --- | --- | --- | --- |",
            ]
        )
        for row in report.acr[:200]:
            lines.append(
                f"| {esc(row['ip'])} | {esc(row['name'])} | {esc(row['domain'])} "
                f"| {esc(row['label'])} | {row['count']} | {row['blocked']} |"
            )
        if len(report.acr) > 200:
            lines.append("")
            lines.append(f"{len(report.acr) - 200} further rows were omitted.")
    else:
        lines.append("No query in this window matched the ACR suffix list.")
    if report.truncated:
        lines.extend(["", "The API result was capped. A local copy of pihole-FTL.db is complete."])
    lines.append("")
    return "\n".join(lines)


def load_known(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    known = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        known.add(line.split()[0])
    return known


def save_known(path: Path, clients: list[tuple[str, str]], previous: set[str]) -> None:
    ips = set(previous)
    named = {ip: name for ip, name in clients}
    for ip, _name in clients:
        ips.add(ip)
    lines = ["# IP addresses this report has already seen. One per line.", ""]
    for ip in sorted(ips):
        name = named.get(ip, "")
        lines.append(f"{ip} {name}".rstrip())
    _write_private(path, "\n".join(lines) + "\n")


def diff_clients(known: set[str], clients: list[tuple[str, str]]) -> list[tuple[str, str]]:
    return [(ip, name) for ip, name in clients if ip and ip not in known]


class Api:
    """Minimal Pi-hole HTTP client. v6 session auth, with a v5 read fallback."""

    def __init__(self, base: str) -> None:
        self.base = _check_url(base)
        self.sid = ""
        self.kind = ""
        insecure = os.environ.get("PIHOLE_INSECURE", "") in ("1", "true", "yes")
        context = ssl._create_unverified_context() if insecure else ssl.create_default_context()
        if insecure:
            print("PIHOLE_INSECURE is set: TLS certificate checks are off for this run.", file=sys.stderr)
        handlers: list[urllib.request.BaseHandler] = [
            urllib.request.HTTPSHandler(context=context),
            _NoRedirect(),
        ]
        self.opener = urllib.request.build_opener(*handlers)

    def close(self) -> None:
        if self.sid:
            try:
                self._request("DELETE", "/api/auth")
            except PiHoleError:
                pass
            self.sid = ""

    def login(self, password: str | None, token: str | None) -> None:
        probe = self._raw("GET", "/api/info/version")
        if probe is not None and probe[0] == 200:
            self.kind = "v6"
            if not password:
                raise PiHoleError(
                    "This looks like Pi-hole v6. Set PIHOLE_PASSWORD or PIHOLE_PASSWORD_FILE "
                    "(an application password is the right value)."
                )
            status, body = self._exchange("POST", "/api/auth", {"password": password})
            if status != 200:
                raise PiHoleError(f"Pi-hole refused the login (HTTP {status}). The password was not printed.")
            session = body.get("session") or {}
            if not session.get("valid") or not session.get("sid"):
                raise PiHoleError("Pi-hole did not return a session. Check the password.")
            self.sid = str(session["sid"])
            return
        # v5 api.php answers without a version endpoint we can trust.
        self.kind = "v5"
        if not token:
            raise PiHoleError(
                "No Pi-hole v6 API at this URL. For v5, set PIHOLE_API_TOKEN. "
                "v5 has no supported HTTP call to add a blocklist; set PIHOLE_GRAVITY_DB "
                "to a gravity.db on this machine if you need to add lists."
            )
        status, body = self._exchange("GET", "/admin/api.php?summaryRaw&auth=" + urllib.parse.quote(token))
        if status != 200 or not isinstance(body, dict):
            raise PiHoleError(f"Pi-hole v5 API did not answer (HTTP {status}).")
        self._v5_token = token

    def _raw(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict] | None:
        try:
            return self._exchange(method, path, payload)
        except PiHoleError as exc:
            if "Could not reach" in str(exc):
                raise
            return None

    def _exchange(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict]:
        return self._request(method, path, payload)

    def _request(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict]:
        url = self.base + path
        data = None
        headers = {"Accept": "application/json", "User-Agent": "privacy-sweep"}
        if self.sid:
            headers["X-FTL-SID"] = self.sid
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=30) as resp:
                raw = resp.read(2_000_000)
                status = resp.status
        except urllib.error.HTTPError as exc:
            raw = exc.read(200_000)
            status = exc.code
        except urllib.error.URLError as exc:
            raise PiHoleError(f"Could not reach {self.base}: {exc.reason}") from exc
        if not raw:
            return status, {}
        try:
            body = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            body = {"_raw": raw[:300].decode("utf-8", "replace")}
        if not isinstance(body, dict):
            body = {"_value": body}
        return status, body

    def get_lists(self) -> list[dict]:
        if self.kind != "v6":
            raise PiHoleError("Listing adlists over HTTP is implemented for Pi-hole v6.")
        status, body = self._request("GET", "/api/lists")
        if status != 200:
            raise PiHoleError(f"GET /api/lists failed (HTTP {status}).")
        lists = body.get("lists")
        if not isinstance(lists, list):
            raise PiHoleError("Pi-hole /api/lists did not return a lists array.")
        return lists

    def add_list(self, address: str, comment: str) -> dict:
        """POST /api/lists?type=block. Retry once with type in the JSON body.

        Current v6 wants type as a query parameter. Early v6 wanted it in the
        body. Both are tried so a slightly older v6 still works.
        """
        body = {"address": address, "comment": comment, "groups": [0], "enabled": True}
        status, payload = self._request("POST", "/api/lists?type=block", body)
        if status in (200, 201):
            return payload
        message = json.dumps(payload)[:400]
        if status == 400 and "type" in message.lower():
            legacy = dict(body)
            legacy["type"] = "block"
            status, payload = self._request("POST", "/api/lists", legacy)
            if status in (200, 201):
                return payload
            message = json.dumps(payload)[:400]
        raise PiHoleError(f"Could not add {address} (HTTP {status}): {message}")

    def add_regex(self, pattern: str, comment: str) -> None:
        status, payload = self._request("GET", "/api/domains/deny/regex")
        if status == 200:
            for row in payload.get("domains") or []:
                if isinstance(row, dict) and row.get("domain") == pattern:
                    print(f"Regex already present: {pattern}")
                    return
        body = {"domain": pattern, "comment": comment, "groups": [0], "enabled": True}
        status, payload = self._request("POST", "/api/domains/deny/regex", body)
        if status not in (200, 201):
            raise PiHoleError(
                "Could not add the Alphonso regex "
                f"(HTTP {status}): {json.dumps(payload)[:400]}"
            )
        print(f"Added regex deny: {pattern}")

    def _domain_present(self, kind_path: str, domain: str) -> bool:
        status, payload = self._request("GET", kind_path)
        if status != 200:
            raise PiHoleError(f"GET {kind_path} failed (HTTP {status}). Allow rules were not changed.")
        for row in payload.get("domains") or []:
            if isinstance(row, dict) and row.get("domain") == domain:
                return True
        return False

    def add_allow(self, domain: str, kind: str, comment: str) -> None:
        """kind is exact or regex. Exact allow does not cover subdomains."""
        if kind not in ("exact", "regex"):
            raise PiHoleError(f"Refusing allow kind {kind}.")
        path = f"/api/domains/allow/{kind}"
        if self._domain_present(path, domain):
            print(f"Allow already present ({kind}): {domain}")
            return
        body = {"domain": domain, "comment": comment, "groups": [0], "enabled": True}
        status, payload = self._request("POST", path, body)
        if status not in (200, 201):
            raise PiHoleError(
                f"Could not allow {domain} ({kind}) "
                f"(HTTP {status}): {json.dumps(payload)[:400]}"
            )
        print(f"Allowed ({kind}): {domain}")

    def gravity(self) -> None:
        status, payload = self._request("POST", "/api/action/gravity", {})
        if status not in (200, 201, 202):
            raise PiHoleError(
                "Lists were saved, but gravity did not run "
                f"(HTTP {status}): {json.dumps(payload)[:300]}. "
                "Update gravity from the Pi-hole web page."
            )
        print("Gravity update requested. Pi-hole is rebuilding its block database.")

    def report_via_api(self, start: int, end: int, suffixes: list[tuple[str, str]], top: int) -> Report:
        if self.kind == "v5":
            return self._report_v5(top)
        report = Report()
        report.source = f"Pi-hole v6 API {self.base}"
        report.start, report.end = start, end
        status, summary = self._request(
            "GET",
            f"/api/stats/database/summary?from={start}&until={end}",
        )
        if status != 200:
            raise PiHoleError(
                f"GET /api/stats/database/summary failed (HTTP {status}). "
                "The v6 database stats API wants both from and until."
            )
        report.total = int(summary.get("sum_queries") or 0)
        report.blocked = int(summary.get("sum_blocked") or 0)
        status, history = self._request(
            "GET",
            f"/api/history/database/clients?from={start}&until={end}",
        )
        if status != 200:
            raise PiHoleError(f"GET /api/history/database/clients failed (HTTP {status}).")
        clients_map = history.get("clients") or {}
        ranked = []
        if isinstance(clients_map, dict):
            for ip, info in clients_map.items():
                if not isinstance(info, dict):
                    continue
                name = info.get("name") or ""
                count = int(info.get("total") or 0)
                ranked.append({"ip": ip, "name": name, "count": count})
                report.all_client_ips.append((ip, name))
        elif isinstance(clients_map, list):
            for info in clients_map:
                if not isinstance(info, dict):
                    continue
                ip = str(info.get("ip") or "")
                name = info.get("name") or ""
                count = int(info.get("count") or info.get("total") or 0)
                ranked.append({"ip": ip, "name": name, "count": count})
                report.all_client_ips.append((ip, name))
        ranked.sort(key=lambda row: -row["count"])
        report.clients = ranked[:top]
        status, domains = self._request(
            "GET",
            f"/api/stats/database/top_domains?blocked=true&from={start}&until={end}&count={top}",
        )
        if status != 200:
            raise PiHoleError(f"GET /api/stats/database/top_domains failed (HTTP {status}).")
        report.blocked_domains = []
        for row in domains.get("domains") or []:
            if isinstance(row, dict) and row.get("domain"):
                report.blocked_domains.append({"domain": row["domain"], "count": int(row.get("count") or 0)})
        report.acr, report.truncated = self._acr_via_queries(start, end, suffixes)
        return report

    def _acr_via_queries(self, start: int, end: int, suffixes: list[tuple[str, str]]) -> tuple[list[dict], bool]:
        """Search the v6 query log per suffix, then keep real suffix matches.

        The domain= parameter treats '*' as a literal in LIKE. The query-log
        column search is the one that wraps the term in SQL wildcards, so
        that is what we send. Results are filtered again locally.
        """
        found: dict[tuple[str, str], dict] = {}
        truncated = False
        # until is exclusive on /api/queries
        until = end + 1
        for suffix, label in suffixes:
            cursor = None
            pages = 0
            while pages < 20:
                qs = (
                    f"/api/queries?disk=true&length=500&from={start}&until={until}"
                    "&columns%5B3%5D%5Bdata%5D=domain"
                    "&columns%5B3%5D%5Bsearch%5D%5Bvalue%5D=" + urllib.parse.quote(suffix)
                )
                if cursor:
                    qs += "&cursor=" + urllib.parse.quote(str(cursor))
                status, body = self._request("GET", qs)
                if status != 200:
                    raise PiHoleError(
                        f"GET /api/queries failed while searching {suffix} (HTTP {status}). "
                        "Set PIHOLE_FTL_DB to a copy of pihole-FTL.db to use SQL instead."
                    )
                queries = body.get("queries") or []
                if not isinstance(queries, list):
                    break
                for item in queries:
                    if not isinstance(item, dict):
                        continue
                    domain = str(item.get("domain") or "")
                    if not domain_matches(domain, suffix):
                        continue
                    client = item.get("client") or {}
                    if isinstance(client, str):
                        ip, name = client, ""
                    else:
                        ip = str(client.get("ip") or "")
                        name = str(client.get("name") or "")
                    key = (ip, domain)
                    row = found.get(key)
                    if row is None:
                        row = {
                            "ip": ip,
                            "name": name,
                            "domain": domain,
                            "suffix": suffix,
                            "label": label,
                            "count": 0,
                            "blocked": 0,
                        }
                        found[key] = row
                    row["count"] += 1
                    status_name = str(item.get("status") or "")
                    if _status_blocked(status_name):
                        row["blocked"] += 1
                pages += 1
                cursor = body.get("cursor")
                if not cursor or not queries:
                    break
            else:
                truncated = True
        rows = sorted(found.values(), key=lambda item: (-item["count"], item["domain"]))
        return rows, truncated

    def _report_v5(self, top: int) -> Report:
        token = urllib.parse.quote(getattr(self, "_v5_token", ""))
        report = Report()
        report.source = f"Pi-hole v5 api.php {self.base}"
        report.end = int(time.time())
        report.start = report.end - 86400
        report.note = (
            "v5 api.php returns the rolling top lists (about the last 24 hours), "
            "not an arbitrary week, and it does not say which client looked up an ACR name. "
            "For a weekly report and per-client ACR hits, copy pihole-FTL.db and set PIHOLE_FTL_DB. "
            "Adding a blocklist is not a v5 HTTP feature; use PIHOLE_GRAVITY_DB on the Pi-hole itself."
        )
        status, summary = self._request("GET", f"/admin/api.php?summaryRaw&auth={token}")
        if status == 200:
            report.total = int(summary.get("dns_queries_today") or 0)
            report.blocked = int(summary.get("ads_blocked_today") or 0)
        status, tops = self._request("GET", f"/admin/api.php?topClients={top}&auth={token}")
        if status == 200:
            for key, count in (tops.get("top_sources") or {}).items():
                name, ip = _split_v5_client(str(key))
                report.clients.append({"ip": ip, "name": name, "count": int(count)})
                report.all_client_ips.append((ip, name))
        status, items = self._request("GET", f"/admin/api.php?topItems={top}&auth={token}")
        if status == 200:
            for domain, count in (items.get("top_ads") or {}).items():
                report.blocked_domains.append({"domain": domain, "count": int(count)})
        report.acr = []
        return report

    def device_names(self) -> dict[str, dict]:
        if self.kind != "v6":
            return {}
        status, body = self._request("GET", "/api/network/devices")
        if status != 200:
            raise PiHoleError(f"GET /api/network/devices failed (HTTP {status}).")
        return parse_network_devices(body)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ARG002
        raise PiHoleError(f"Refusing to follow a redirect from Pi-hole to {newurl}.")


def _status_blocked(name: str) -> bool:
    blocked = {
        "GRAVITY",
        "REGEX",
        "DENYLIST",
        "GRAVITY_CNAME",
        "REGEX_CNAME",
        "DENYLIST_CNAME",
        "EXTERNAL_BLOCKED_IP",
        "EXTERNAL_BLOCKED_NULL",
        "EXTERNAL_BLOCKED_NXRA",
        "EXTERNAL_BLOCKED_EDE15",
        "DBBUSY",
        "SPECIAL_DOMAIN",
    }
    return name.upper() in blocked


def _split_v5_client(key: str) -> tuple[str, str]:
    """v5 top_sources keys look like '192.0.2.10' or 'laptop|192.0.2.10'."""
    if "|" in key:
        name, ip = key.split("|", 1)
        return name, ip
    return "", key


def parse_network_devices(payload: dict) -> dict[str, dict]:
    """Pull ip -> {name, mac, vendor} out of GET /api/network/devices.

    The shape has moved between v6 releases, so a few layouts are accepted.
    """
    found: dict[str, dict] = {}
    devices = payload.get("devices")
    if devices is None:
        devices = payload.get("network") or []
    if isinstance(devices, dict):
        devices = list(devices.values())
    if not isinstance(devices, list):
        return found
    for dev in devices:
        if not isinstance(dev, dict):
            continue
        vendor = str(dev.get("macVendor") or dev.get("vendor") or "")
        mac = str(dev.get("hwaddr") or dev.get("mac") or "")
        ips = dev.get("ips") or []
        if isinstance(ips, dict):
            normalized = []
            for ip, info in ips.items():
                if isinstance(info, dict):
                    normalized.append({"ip": ip, "name": info.get("name") or ""})
                else:
                    normalized.append({"ip": ip, "name": ""})
            ips = normalized
        for info in ips:
            if isinstance(info, str):
                ip, name = info, ""
            elif isinstance(info, dict):
                ip = str(info.get("ip") or "")
                name = str(info.get("name") or "")
            else:
                continue
            if not ip:
                continue
            current = found.get(ip)
            if current is None or (name and not current.get("name")):
                found[ip] = {"name": name, "mac": mac, "vendor": vendor}
    return found


def _fixture_lists(path: Path) -> list[dict]:
    file = path / "lists.json"
    if not file.is_file():
        return []
    payload = json.loads(file.read_text(encoding="utf-8"))
    lists = payload.get("lists") if isinstance(payload, dict) else payload
    return list(lists or [])


def _fixture_clock(path: Path) -> int:
    file = path / "queries.json"
    if not file.is_file():
        return int(time.time())
    payload = json.loads(file.read_text(encoding="utf-8"))
    return int(payload.get("now") or time.time())


def _fixture_db(path: Path) -> sqlite3.Connection:
    file = path / "queries.json"
    if not file.is_file():
        raise PiHoleError(f"Fixture {path} has no queries.json")
    return _build_v6_memory(json.loads(file.read_text(encoding="utf-8")))


def plan_lists(catalog: list[dict], existing: list[dict]) -> dict:
    have = set()
    for row in existing:
        if isinstance(row, dict) and row.get("address"):
            have.add(str(row["address"]).rstrip("/"))
    add, present = [], []
    for row in catalog:
        if row["url"].rstrip("/") in have:
            present.append(row)
        else:
            add.append(row)
    return {"add": add, "present": present}


def print_plan(
    plan: dict,
    regex: bool,
    gravity: bool,
    connected: str,
    brands: set[str],
    allows: list[dict],
    watches: list[dict],
    refresh_word: str,
) -> None:
    print(f"== Smart-TV / ACR blocklists ({connected}) ==")
    if brands:
        print("Brands selected: " + ", ".join(sorted(brands)))
        for brand in sorted(brands):
            if brand in NO_NATIVE_LIST and not any(row["brand"] == brand for row in plan["add"] + plan["present"]):
                print(f"  {NO_NATIVE_LIST[brand]}")
    else:
        print("No brand list selected. Pass --brand samsung,lg,roku,firetv,vizio,hisense or --vendor.")
    print(
        "Vizio and Hisense VIDAA have no HaGeZi native list (those URLs returned HTTP 404 on 2026-10-27). "
        "They rely on the combined lists."
    )
    if plan["present"]:
        print("Already installed:")
        for row in plan["present"]:
            print(f"  {row['name']}")
            print(f"    {row['url']}")
    else:
        print("None of the selected lists are installed yet.")
    if plan["add"]:
        print("Would add:")
        for row in plan["add"]:
            label = row["tier"] if row["brand"] == "*" else f"{row['tier']}:{row['brand']}"
            print(f"  {row['name']} [{label}]")
            print(f"    {row['url']}")
            print(f"    {row['note']}")
    else:
        print("Nothing new to add.")
    if allows:
        print("Would allow (keep-list; these are never added as blocks):")
        for row in allows:
            scope = "this name and its subdomains" if row["scope"] == "tree" else "this name only"
            print(f"  {row['domain']} [{row['brand']}, {scope}]")
            print(f"    {row['note']}")
    if watches:
        print("Not allowlisted:")
        for row in watches:
            print(f"  {row['domain']} [{row['brand']}]")
            print(f"    {row['note']}")
    regex_live = regex and "alphonso.tv" not in protected_domains(allows)
    if regex_live:
        print(f"Would add regex deny: {ALPHONSO_REGEX}")
        print("  Covers rotating Alphonso hosts (tkacrNNN.alphonso.tv) that a fixed list misses.")
        print("  On AdGuard Home this is the adblock rule ||alphonso.tv^.")
    elif regex:
        print("Alphonso regex skipped: alphonso.tv is on the keep-list.")
    if gravity and (plan["add"] or allows or regex_live):
        print(f"Would ask the resolver to {refresh_word} so the changes take effect.")
    print("No change is made in a dry run.")


def apply_lists_api(api: Api, plan: dict, regex: bool, gravity: bool, allows: list[dict]) -> None:
    for row in plan["add"]:
        comment = f"privacy-sweep: {row['name']}"[:180]
        api.add_list(row["url"], comment)
        print(f"Added: {row['name']}")
    for row in allows:
        comment = f"privacy-sweep keep: {row['brand']} {row['domain']}"[:180]
        if row["scope"] == "tree":
            api.add_allow(tree_regex(row["domain"]), "regex", comment)
        else:
            api.add_allow(row["domain"], "exact", comment)
    if regex and "alphonso.tv" not in protected_domains(allows):
        api.add_regex(ALPHONSO_REGEX, "privacy-sweep: Alphonso ACR suffix")
    if gravity and (plan["add"] or allows or regex):
        api.gravity()
    if not plan["add"] and not allows and not regex:
        print("Nothing to add.")


def _insert_domain(con: sqlite3.Connection, dcols: list[str], kind: int, domain: str, comment: str) -> bool:
    have = con.execute(
        "SELECT id FROM domainlist WHERE domain = ? AND type = ?",
        (domain, kind),
    ).fetchone()
    if have:
        print(f"Already present (type {kind}): {domain}")
        return False
    fields = ["type", "domain"]
    values: list[object] = [kind, domain]
    if "enabled" in dcols:
        fields.append("enabled")
        values.append(1)
    if "comment" in dcols:
        fields.append("comment")
        values.append(comment[:180])
    marks = ",".join("?" * len(fields))
    con.execute(
        f"INSERT INTO domainlist ({','.join(fields)}) VALUES ({marks})",
        values,
    )
    return True


def apply_gravity_file(
    db_path: Path,
    plan: dict,
    regex: bool,
    run_gravity: bool,
    allows: list[dict] | None = None,
) -> None:
    """Insert rows into a local gravity.db. Used for Pi-hole v5, which has no add-list HTTP API.

    Allow rows use domainlist type 0 (exact) or type 2 (regex). The Alphonso
    deny stays type 3. ``allows`` defaults to empty so older callers keep the
    previous behavior.
    """
    allows = list(allows or [])
    con = sqlite3.connect(str(db_path), timeout=5)
    try:
        cols = [_safe_ident(row[1]) for row in con.execute("PRAGMA table_info(adlist)")]
        if "address" not in cols:
            raise PiHoleError(f"{db_path} has no adlist table. Is this a Pi-hole gravity.db?")
        now = int(time.time())
        for row in plan["add"]:
            have = con.execute("SELECT id FROM adlist WHERE address = ?", (row["url"],)).fetchone()
            if have:
                print(f"Already present: {row['name']}")
                continue
            fields = ["address"]
            values: list[object] = [row["url"]]
            comment = f"privacy-sweep: {row['name']}"[:180]
            if "enabled" in cols:
                fields.append("enabled")
                values.append(1)
            if "comment" in cols:
                fields.append("comment")
                values.append(comment)
            for column in ("date_added", "date_modified"):
                if column in cols:
                    fields.append(column)
                    values.append(now)
            marks = ",".join("?" * len(fields))
            con.execute(
                f"INSERT INTO adlist ({','.join(fields)}) VALUES ({marks})",
                values,
            )
            print(f"Inserted into {db_path}: {row['name']}")
        regex_live = regex and "alphonso.tv" not in protected_domains(allows)
        if allows or regex_live:
            dcols = [_safe_ident(row[1]) for row in con.execute("PRAGMA table_info(domainlist)")]
            if "domain" not in dcols or "type" not in dcols:
                raise PiHoleError(f"{db_path} has no domainlist table for allow or regex rows.")
            for row in allows:
                stored = tree_regex(row["domain"]) if row["scope"] == "tree" else row["domain"]
                kind = 2 if row["scope"] == "tree" else 0
                if _insert_domain(
                    con,
                    dcols,
                    kind,
                    stored,
                    f"privacy-sweep keep: {row['brand']} {row['domain']}",
                ):
                    print(f"Inserted allow ({row['scope']}): {row['domain']}")
            if regex_live:
                if _insert_domain(con, dcols, 3, ALPHONSO_REGEX, "privacy-sweep: Alphonso ACR suffix"):
                    print(f"Inserted regex deny: {ALPHONSO_REGEX}")
        con.commit()
    finally:
        con.close()
    changed = bool(plan["add"] or allows or (regex and "alphonso.tv" not in protected_domains(allows)))
    if run_gravity and db_path.resolve() == DEFAULT_GRAVITY.resolve() and changed:
        print("gravity.db is the live file. Run `pihole -g` on this machine to rebuild gravity.")
    elif changed:
        print("This is not the live /etc/pihole/gravity.db, so gravity was not started.")
        print("Copy the rows across, or run the script on the Pi-hole against the live database, then `pihole -g`.")


def _open_report_db(args: argparse.Namespace) -> tuple[sqlite3.Connection, str, int] | None:
    if args.fixture:
        path = Path(args.fixture)
        return _fixture_db(path), f"fixture {path}", _fixture_clock(path)
    db = args.ftl_db or os.environ.get("PIHOLE_FTL_DB")
    if db:
        file = Path(db)
        if not file.is_file():
            raise PiHoleError(f"PIHOLE_FTL_DB is not a file: {file}")
        return _connect_ro(file), f"FTL database {file}", int(time.time())
    return None


def _names_from_db(con: sqlite3.Connection) -> dict[str, dict]:
    return {ip: {"name": name, "mac": "", "vendor": ""} for ip, name in _client_names(con).items()}


def _selection(args: argparse.Namespace) -> tuple[set[str], list[dict], list[dict], list[dict]]:
    brands = parse_brands(list(args.brand or []), bool(args.vendor))
    catalog = load_lists(Path(args.lists), brands)
    keeps = load_keeps(Path(args.keeps))
    return brands, catalog, allow_rows(keeps), watch_rows(keeps)


def _resolver(args: argparse.Namespace) -> str:
    """Pi-hole unless the caller passed --resolver adguard. ADGUARD_URL alone does not switch."""
    return args.resolver or "pihole"


def _regex_live(regex: bool, allows: list[dict]) -> bool:
    return bool(regex) and "alphonso.tv" not in protected_domains(allows)


def _refresh_word(resolver: str) -> str:
    return "reload filters" if resolver == "adguard" else "update gravity"


def _adguard_client() -> adguard.AdGuard:
    base = os.environ.get("ADGUARD_URL", "").strip()
    if not base:
        raise PiHoleError("Set ADGUARD_URL (for example http://192.168.1.3:3000).")
    try:
        return adguard.AdGuard(base)
    except adguard.AdGuardError as exc:
        raise PiHoleError(str(exc)) from exc


def _apply_adguard(client: adguard.AdGuard, plan: dict, regex: bool, gravity: bool, allows: list[dict]) -> None:
    """Add missing filters, then append keep-list exceptions without dropping other user rules."""
    try:
        have = {str(row.get("url") or "").rstrip("/") for row in client.filters()}
        added = False
        for row in plan["add"]:
            if row["url"].rstrip("/") in have:
                print(f"Already present: {row['name']}")
                continue
            client.add_filter(row["url"], f"privacy-sweep: {row['name']}")
            print(f"Added: {row['name']}")
            added = True
        existing = client.user_rules()
        merged = list(existing)
        changed = False
        for row in allows:
            rule = adguard_rule(row)
            if rule in merged:
                print(f"Allow rule already present: {rule}")
                continue
            merged.append(rule)
            changed = True
            print(f"Allow rule: {rule}")
        if _regex_live(regex, allows):
            rule = "||alphonso.tv^"
            if rule not in merged:
                merged.append(rule)
                changed = True
                print(f"Added block rule: {rule}")
            else:
                print(f"Block rule already present: {rule}")
        if changed:
            client.set_user_rules(merged)
        if gravity and (added or changed):
            client.refresh()
            print("Asked AdGuard Home to reload filters.")
        if not added and not changed:
            print("Nothing to add.")
    except adguard.AdGuardError as exc:
        raise PiHoleError(str(exc)) from exc


def _ag_domain(row: dict) -> str:
    question = row.get("question")
    if isinstance(question, dict):
        name = question.get("name") or question.get("host") or ""
    elif isinstance(question, str):
        name = question
    else:
        name = row.get("domain") or ""
    return str(name).lower().rstrip(".")


def _ag_client(row: dict) -> tuple[str, str]:
    info = row.get("client_info") if isinstance(row.get("client_info"), dict) else {}
    ip = str(row.get("client") or info.get("ip") or "")
    name = str(info.get("name") or row.get("client_name") or "")
    return ip, name


def _ag_time(value: object) -> int | None:
    if isinstance(value, (int, float)):
        return int(value)
    if not isinstance(value, str) or not value:
        return None
    text = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def report_from_adguard(
    client: adguard.AdGuard,
    start: int,
    end: int,
    suffixes: list[tuple[str, str]],
    top: int,
) -> Report:
    """ACR rows from /control/querylog. Totals cover only the rows that search returned."""
    report = Report()
    report.source = f"AdGuard Home query log {client.base}"
    report.start, report.end = start, end
    report.note = (
        "AdGuard Home's query log is a search, not Pi-hole's long-term database. "
        "Counts below are the rows /control/querylog returned for the ACR suffixes, inside the window."
    )
    seen: set[tuple[int, str, str]] = set()
    hits: dict[tuple[str, str, str], dict] = {}
    client_counts: dict[str, dict] = {}
    blocked_counts: dict[str, int] = {}
    try:
        for suffix, label in suffixes:
            rows = client.querylog(suffix, limit=500)
            if len(rows) >= 500:
                report.truncated = True
            for row in rows:
                domain = _ag_domain(row)
                if not domain or not domain_matches(domain, suffix):
                    continue
                stamp = _ag_time(row.get("time"))
                if stamp is None or stamp < start or stamp > end:
                    continue
                ip, name = _ag_client(row)
                key = (stamp, ip, domain)
                if key in seen:
                    continue
                seen.add(key)
                reason = str(row.get("reason") or "")
                blocked = reason.startswith("Filtered")
                report.total += 1
                if blocked:
                    report.blocked += 1
                    blocked_counts[domain] = blocked_counts.get(domain, 0) + 1
                slot = client_counts.get(ip)
                if slot is None:
                    slot = {"ip": ip, "name": name, "count": 0}
                    client_counts[ip] = slot
                    report.all_client_ips.append((ip, name))
                elif name and not slot["name"]:
                    slot["name"] = name
                slot["count"] += 1
                hit_key = (ip, domain, suffix)
                item = hits.get(hit_key)
                if item is None:
                    item = {
                        "ip": ip,
                        "name": name,
                        "domain": domain,
                        "suffix": suffix,
                        "label": label,
                        "count": 0,
                        "blocked": 0,
                    }
                    hits[hit_key] = item
                item["count"] += 1
                if blocked:
                    item["blocked"] += 1
                if name and not item["name"]:
                    item["name"] = name
    except adguard.AdGuardError as exc:
        raise PiHoleError(str(exc)) from exc
    ranked = sorted(client_counts.values(), key=lambda row: -row["count"])
    report.clients = ranked[:top]
    report.blocked_domains = [
        {"domain": domain, "count": count}
        for domain, count in sorted(blocked_counts.items(), key=lambda pair: -pair[1])[:top]
    ]
    report.acr = sorted(hits.values(), key=lambda item: (-item["count"], item["domain"]))
    return report


def cmd_plan(args: argparse.Namespace) -> int:
    brands, catalog, allows, watches = _selection(args)
    resolver = _resolver(args)
    connected = "not connected"
    existing: list[dict] = []
    if args.fixture:
        existing = _fixture_lists(Path(args.fixture))
        connected = f"fixture {args.fixture}"
    elif resolver == "adguard":
        if adguard._password():
            client = _adguard_client()
            try:
                existing = [{"address": str(row.get("url") or "")} for row in client.filters()]
            except adguard.AdGuardError as exc:
                raise PiHoleError(str(exc)) from exc
            connected = f"AdGuard Home {client.base}"
        else:
            print("No AdGuard Home password set, so this preview did not contact a server.")
            print("Set ADGUARD_URL and ADGUARD_PASSWORD to compare against the filters already installed.")
    elif os.environ.get("PIHOLE_PASSWORD") or os.environ.get("PIHOLE_PASSWORD_FILE"):
        api = Api(os.environ.get("PIHOLE_URL", "http://pi.hole"))
        try:
            api.login(_password(), os.environ.get("PIHOLE_API_TOKEN"))
            if api.kind != "v6":
                print(api._report_v5(1).note)
                connected = "v5 API (cannot list adlists over HTTP)"
            else:
                existing = api.get_lists()
                connected = f"v6 {api.base}"
        finally:
            api.close()
    else:
        print("No Pi-hole password set, so this preview did not contact a server.")
        print("Set PIHOLE_URL and PIHOLE_PASSWORD to compare against the lists already installed.")
    plan = plan_lists(catalog, existing)
    print_plan(
        plan,
        args.alphonso_regex,
        not args.no_gravity,
        connected,
        brands,
        allows,
        watches,
        _refresh_word(resolver),
    )
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    brands, catalog, allows, watches = _selection(args)
    del brands, watches
    resolver = _resolver(args)
    regex_live = _regex_live(args.alphonso_regex, allows)
    log_path = Path(args.apply_log) if args.apply_log else None
    if args.fixture:
        existing = _fixture_lists(Path(args.fixture))
        plan = plan_lists(catalog, existing)
        record = {
            "added": [row["url"] for row in plan["add"]],
            "allow": [row["domain"] for row in allows],
            "regex": [ALPHONSO_REGEX] if regex_live else [],
            "gravity": (not args.no_gravity) and bool(plan["add"] or allows or regex_live),
        }
        if log_path:
            _write_private(log_path, json.dumps(record, indent=2) + "\n")
        for row in plan["add"]:
            print(f"Fixture apply: would have added {row['name']}")
        for row in allows:
            print(f"Fixture apply: would allow {row['domain']} ({row['scope']})")
        print("Fixture mode does not contact a resolver.")
        return 0
    if resolver == "adguard":
        client = _adguard_client()
        try:
            existing = [{"address": str(row.get("url") or "")} for row in client.filters()]
        except adguard.AdGuardError as exc:
            raise PiHoleError(str(exc)) from exc
        plan = plan_lists(catalog, existing)
        _apply_adguard(client, plan, args.alphonso_regex, not args.no_gravity, allows)
        return 0
    gravity_db = os.environ.get("PIHOLE_GRAVITY_DB")
    password = _password()
    if password:
        api = Api(os.environ.get("PIHOLE_URL", "http://pi.hole"))
        try:
            api.login(password, os.environ.get("PIHOLE_API_TOKEN"))
            if api.kind != "v6":
                raise PiHoleError(
                    "This URL is not Pi-hole v6, so lists were not added over HTTP. "
                    "On a v5 Pi-hole, set PIHOLE_GRAVITY_DB to /etc/pihole/gravity.db and re-run."
                )
            plan = plan_lists(catalog, api.get_lists())
            apply_lists_api(api, plan, args.alphonso_regex, not args.no_gravity, allows)
        finally:
            api.close()
        return 0
    if gravity_db:
        con = sqlite3.connect(gravity_db)
        try:
            existing = [{"address": row[0]} for row in con.execute("SELECT address FROM adlist")]
        finally:
            con.close()
        plan = plan_lists(catalog, existing)
        apply_gravity_file(Path(gravity_db), plan, args.alphonso_regex, not args.no_gravity, allows)
        return 0
    raise PiHoleError(
        "Nothing to talk to. Set PIHOLE_URL and PIHOLE_PASSWORD for Pi-hole v6, "
        "PIHOLE_GRAVITY_DB for a v5 gravity database on this machine, "
        "or pass --resolver adguard with ADGUARD_URL and ADGUARD_PASSWORD."
    )


def _collect_report(args: argparse.Namespace) -> tuple[Report, int]:
    suffixes = load_suffixes(Path(args.suffixes))
    opened = _open_report_db(args)
    if opened is not None:
        con, source, now = opened
        try:
            start = now - int(args.days) * 86400
            report = _report_from_db(con, start, now, suffixes, args.top)
        finally:
            con.close()
        report.source = source
        return report, now
    if _resolver(args) == "adguard":
        client = _adguard_client()
        now = int(time.time())
        start = now - int(args.days) * 86400
        return report_from_adguard(client, start, now, suffixes, args.top), now
    api = Api(os.environ.get("PIHOLE_URL", "http://pi.hole"))
    try:
        api.login(_password(), os.environ.get("PIHOLE_API_TOKEN"))
        now = int(time.time())
        start = now - int(args.days) * 86400
        report = api.report_via_api(start, now, suffixes, args.top)
        return report, now
    finally:
        api.close()


def cmd_report(args: argparse.Namespace) -> int:
    report, _now = _collect_report(args)
    known_path = Path(args.state) if args.state else state_dir() / "pihole-known-clients.txt"
    known = load_known(known_path)
    baseline = not known_path.is_file()
    new_clients = [] if baseline else diff_clients(known, report.all_client_ips)
    text = render_markdown(report, Path(args.suffixes), new_clients, baseline)
    if args.section == "acr":
        # Keep the ACR section available on its own for acr-clients.sh.
        marker = "## ACR and smart-TV telemetry"
        text = text[text.index(marker) :] if marker in text else text
        print(f"Source: {report.source}")
        print(f"Window ends: {time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime(report.end))}")
        print()
    sys.stdout.write(text)
    if args.save:
        if args.output:
            dest = Path(args.output)
        else:
            dest = state_dir() / "pihole-privacy-report.md"
        _write_private(dest, text)
        save_known(known_path, report.all_client_ips, known)
        print(f"Wrote {dest}", file=sys.stderr)
        print(f"Updated known clients: {known_path}", file=sys.stderr)
    return 0


def cmd_names(args: argparse.Namespace) -> int:
    if not args.fixture and not (args.ftl_db or os.environ.get("PIHOLE_FTL_DB")) and not (
        _password() or os.environ.get("PIHOLE_API_TOKEN")
    ):
        print(
            "Pi-hole names skipped. Set PIHOLE_URL and PIHOLE_PASSWORD, or PIHOLE_FTL_DB, to label clients.",
            file=sys.stderr,
        )
        json.dump({}, sys.stdout)
        print()
        return 0
    opened = _open_report_db(args)
    if opened is not None:
        con, _source, _now = opened
        try:
            payload = _names_from_db(con)
        finally:
            con.close()
        if args.fixture:
            devices = Path(args.fixture) / "devices.json"
            if devices.is_file():
                payload.update(parse_network_devices(json.loads(devices.read_text(encoding="utf-8"))))
        json.dump(payload, sys.stdout)
        print()
        return 0
    if not (_password() or os.environ.get("PIHOLE_API_TOKEN")):
        raise PiHoleError("No Pi-hole credentials and no PIHOLE_FTL_DB, so client names were not looked up.")
    api = Api(os.environ.get("PIHOLE_URL", "http://pi.hole"))
    try:
        api.login(_password(), os.environ.get("PIHOLE_API_TOKEN"))
        json.dump(api.device_names(), sys.stdout)
        print()
    finally:
        api.close()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Pi-hole helper for privacy-sweep. Prefer the shell scripts.")
    parser.add_argument("--fixture", help="Directory of JSON stand-ins. No network calls.")
    parser.add_argument("--ftl-db", help="Path to a pihole-FTL.db copy. Reads only.")
    parser.add_argument("--lists", default=str(DEFAULT_LISTS))
    parser.add_argument("--keeps", default=str(DEFAULT_KEEPS))
    parser.add_argument("--suffixes", default=str(DEFAULT_SUFFIXES))
    parser.add_argument(
        "--brand",
        action="append",
        default=[],
        help="Brand id, or a comma-separated list. Repeatable. Overrides --vendor.",
    )
    parser.add_argument(
        "--vendor",
        action="store_true",
        help="Samsung, LG, Roku, and Fire TV HaGeZi lists. Ignored when --brand is set.",
    )
    parser.add_argument(
        "--resolver",
        choices=("pihole", "adguard"),
        default="pihole",
        help="Which resolver to talk to. The default stays Pi-hole.",
    )
    parser.add_argument("--alphonso-regex", action="store_true")
    parser.add_argument("--no-gravity", action="store_true")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--state", help="Known-client file. Default is under $XDG_STATE_HOME.")
    parser.add_argument("--output", help="Where to write the markdown report.")
    parser.add_argument("--apply-log", help="Fixture apply writes the intended change here.")
    parser.add_argument("--section", choices=("full", "acr"), default="full")
    parser.add_argument("--save", action="store_true", help="Write the report and update known clients.")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("plan")
    sub.add_parser("apply")
    sub.add_parser("report")
    sub.add_parser("names")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.days < 1 or args.days > 366:
        raise PiHoleError("--days must be between 1 and 366.")
    if args.top < 1 or args.top > 100:
        raise PiHoleError("--top must be between 1 and 100.")
    commands = {"plan": cmd_plan, "apply": cmd_apply, "report": cmd_report, "names": cmd_names}
    return commands[args.cmd](args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PiHoleError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
    except BrokenPipeError:
        sys.exit(0)
