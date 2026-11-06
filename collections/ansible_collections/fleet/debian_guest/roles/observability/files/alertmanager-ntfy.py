#!/usr/bin/env python3
"""One ntfy post per Alertmanager group.

alertmanager-ntfy templates the Alert struct and emits one push per firing
series. This webhook consumes the group payload instead: title from
groupLabels plus firing count, body from every member's description.
"""

from __future__ import annotations

import base64
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

NTFY_BASE = os.environ.get("NTFY_BASE", "http://127.0.0.1:2586")
NTFY_TOPIC = os.environ.get("NTFY_TOPIC", "alerts")
NTFY_USER = os.environ.get("NTFY_USER", "alertmanager")
NTFY_PASSWORD = os.environ.get("NTFY_PASSWORD", "")
LISTEN = os.environ.get("NTFY_GROUP_LISTEN", "127.0.0.1:8095")

# ntfy JSON publish unmarshals priority as int (1=min … 5=urgent). Strings
# are header-only; a JSON string is 40024 "request body must be valid JSON".
_PRIORITY = {
    "critical": 5,
    "warning": 4,
    "info": 2,
}


def _label(labels: dict, *keys: str) -> str:
    for key in keys:
        value = labels.get(key)
        if value:
            return str(value)
    return ""


def _priority(status: str, severity: str) -> int:
    if status == "resolved":
        return 3
    return _PRIORITY.get(severity, 3)


def _tags(status: str, severity: str) -> str:
    if status == "resolved":
        return "white_check_mark"
    return {
        "critical": "rotating_light",
        "warning": "warning",
        "info": "information_source",
    }.get(severity, "warning")


def render(payload: dict) -> tuple[str, str, int, str, str]:
    status = payload.get("status") or "firing"
    group = payload.get("groupLabels") or {}
    common = payload.get("commonLabels") or {}
    alerts = payload.get("alerts") or []
    severity = _label(common, "severity") or _label(group, "severity")

    name = _label(group, "alertname") or "alerts"
    where = _label(group, "host", "instance")
    device = _label(group, "device")
    bits = [name]
    if where:
        bits.append(f"on {where}")
    if device:
        bits.append(device)
    title = " ".join(bits) + f" ({len(alerts)})"
    if status == "resolved":
        title = f"Resolved: {title}"

    lines = []
    for alert in alerts:
        annotations = alert.get("annotations") or {}
        labels = alert.get("labels") or {}
        summary = annotations.get("summary") or labels.get("alertname") or ""
        description = annotations.get("description") or ""
        inst = labels.get("instance") or labels.get("host") or ""
        dev = labels.get("device") or labels.get("mountpoint") or ""
        prefix = " ".join(p for p in (inst, dev) if p)
        if prefix and summary:
            lines.append(f"{prefix}: {summary}")
        elif summary:
            lines.append(str(summary))
        if description and description != summary:
            lines.append(str(description))
    body = "\n".join(lines) if lines else title
    click = ""
    if alerts:
        click = str(alerts[0].get("generatorURL") or "")
    # ntfy click must be an absolute http(s) URL. Mimir ruler emits /graph?...
    if not click.startswith(("http://", "https://")):
        click = ""
    return title, body, _priority(status, severity), _tags(status, severity), click


def post_ntfy(title: str, body: str, priority: int, tags: str, click: str) -> None:
    if not NTFY_PASSWORD:
        raise RuntimeError("NTFY_PASSWORD is not set")
    token = base64.b64encode(f"{NTFY_USER}:{NTFY_PASSWORD}".encode()).decode()
    payload = {
        "topic": NTFY_TOPIC,
        "title": title,
        "message": body,
        "priority": priority,
        "tags": [tags],
    }
    if click:
        payload["click"] = click
    request = Request(
        NTFY_BASE,
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=15) as response:
            response.read()
    except HTTPError as err:
        detail = err.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"ntfy HTTP {err.code}: {detail}") from err


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode())
            title, body, priority, tags, click = render(payload)
            post_ntfy(title, body, priority, tags, click)
        except (json.JSONDecodeError, HTTPError, URLError, RuntimeError, OSError) as err:
            sys.stderr.write(f"forward failed: {err}\n")
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(err).encode())
            return
        self.send_response(204)
        self.end_headers()

    def do_GET(self) -> None:
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")


def main() -> None:
    host, port_s = LISTEN.rsplit(":", 1)
    server = HTTPServer((host, int(port_s)), Handler)
    sys.stderr.write(f"alertmanager group webhook on {LISTEN} -> {NTFY_BASE}/{NTFY_TOPIC}\n")
    server.serve_forever()


if __name__ == "__main__":
    main()
