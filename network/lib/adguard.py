#!/usr/bin/env python3
"""Small AdGuard Home client for the smart-TV list scripts.

AdGuard Home's HTTP API lives under /control/ and uses HTTP basic auth.
Adding a filter is POST /control/filtering/add_url. User rules are replaced
as a whole by POST /control/filtering/set_rules, so the caller must read
/control/filtering/status first and send the previous rules back.

The query log is GET /control/querylog. It is a log search, not Pi-hole's
long-term database.
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class AdGuardError(Exception):
    """A problem the user can act on. The message is safe to print."""


def _check_url(url: str) -> str:
    url = url.rstrip("/")
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise AdGuardError("ADGUARD_URL must look like http://192.168.1.3:3000")
    if parsed.username or parsed.password or "@" in parsed.netloc:
        raise AdGuardError("Put the password in ADGUARD_PASSWORD, not in the URL.")
    if parsed.path not in ("", "/"):
        raise AdGuardError("ADGUARD_URL should be the AdGuard Home origin, without /control.")
    return url


def _password() -> str | None:
    inline = os.environ.get("ADGUARD_PASSWORD")
    if inline:
        return inline
    path = os.environ.get("ADGUARD_PASSWORD_FILE")
    if not path:
        return None
    file = Path(path)
    if not file.is_file():
        raise AdGuardError(f"ADGUARD_PASSWORD_FILE does not exist: {path}")
    text = file.read_text(encoding="utf-8")
    if text.endswith("\n"):
        text = text[:-1]
    if text.endswith("\r"):
        text = text[:-1]
    return text or None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ARG002
        raise AdGuardError(f"Refusing to follow a redirect from AdGuard Home to {newurl}.")


class AdGuard:
    """One AdGuard Home the user administers. Reads and, when asked, adds filters."""

    def __init__(self, base: str) -> None:
        self.base = _check_url(base)
        user = os.environ.get("ADGUARD_USER") or "admin"
        password = _password()
        if not password:
            raise AdGuardError("Set ADGUARD_PASSWORD or ADGUARD_PASSWORD_FILE. The password was not read from the URL.")
        token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
        self._basic = f"Basic {token}"
        insecure = os.environ.get("ADGUARD_INSECURE", "") in ("1", "true", "yes")
        context = ssl._create_unverified_context() if insecure else ssl.create_default_context()
        if insecure:
            print("ADGUARD_INSECURE is set: TLS certificate checks are off for this run.", flush=True)
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPSHandler(context=context),
            _NoRedirect(),
        )

    def _request(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict | list]:
        url = self.base + path
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": self._basic,
            "User-Agent": "privacy-sweep",
        }
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
            raise AdGuardError(f"Could not reach {self.base}: {exc.reason}") from exc
        if not raw:
            return status, {}
        try:
            body = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            body = {"_raw": raw[:300].decode("utf-8", "replace")}
        return status, body

    def status(self) -> dict:
        code, body = self._request("GET", "/control/filtering/status")
        if code != 200 or not isinstance(body, dict):
            raise AdGuardError(f"GET /control/filtering/status failed (HTTP {code}).")
        return body

    def filters(self) -> list[dict]:
        rows = self.status().get("filters") or []
        if not isinstance(rows, list):
            raise AdGuardError("AdGuard Home did not return a filters array.")
        return [row for row in rows if isinstance(row, dict)]

    def add_filter(self, url: str, name: str) -> None:
        code, body = self._request(
            "POST",
            "/control/filtering/add_url",
            {"name": name[:180], "url": url, "whitelist": False},
        )
        if code != 200:
            raise AdGuardError(f"Could not add {url} (HTTP {code}): {json.dumps(body)[:400]}")

    def user_rules(self) -> list[str]:
        rules = self.status().get("user_rules") or []
        if not isinstance(rules, list):
            raise AdGuardError("AdGuard Home did not return user_rules. Refusing to replace them.")
        return [str(rule) for rule in rules]

    def set_user_rules(self, rules: list[str]) -> None:
        """Replace user rules with this full list. The caller must have read the old ones."""
        code, body = self._request("POST", "/control/filtering/set_rules", {"rules": rules})
        if code != 200:
            raise AdGuardError(
                "Could not update AdGuard user rules "
                f"(HTTP {code}): {json.dumps(body)[:400]}"
            )

    def refresh(self) -> None:
        code, body = self._request("POST", "/control/filtering/refresh", {"whitelist": False})
        if code != 200:
            raise AdGuardError(
                "Filters were saved, but AdGuard did not reload them "
                f"(HTTP {code}): {json.dumps(body)[:300]}. Reload filters in the web UI."
            )

    def querylog(self, search: str, limit: int = 500) -> list[dict]:
        query = urllib.parse.urlencode({"search": search, "limit": str(limit)})
        code, body = self._request("GET", "/control/querylog?" + query)
        if code != 200 or not isinstance(body, dict):
            raise AdGuardError(f"GET /control/querylog failed while searching {search} (HTTP {code}).")
        rows = body.get("data") or []
        if not isinstance(rows, list):
            raise AdGuardError("AdGuard Home query log did not return a data array.")
        return [row for row in rows if isinstance(row, dict)]
