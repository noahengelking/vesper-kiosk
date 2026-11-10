#!/usr/bin/env python3
"""Board audio control: lists PipeWire outputs, switches the default, sets volume.
Runs as a user service so it can reach the user's PipeWire session."""
import json, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ORIGIN = "http://127.0.0.1:8080"
MAXV = 100


def pactl(*args):
    r = subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=3)
    return r.returncode, r.stdout


def pct(sink):
    vals = [int(c["value_percent"].rstrip("%")) for c in sink.get("volume", {}).values()]
    return max(vals) if vals else 0


def sinks():
    rc, out = pactl("--format=json", "list", "sinks")
    if rc != 0:
        return []
    default = pactl("get-default-sink")[1].strip()
    res = []
    for s in json.loads(out):
        name = s["name"]
        low = name.lower()
        if "hdmi" in low:
            continue
        desc = s.get("description") or name
        if name.startswith("bluez"):
            kind, label = "bluetooth", desc
        elif "headphone" in low:
            kind, label = "aux", "Headphones / Aux"
        elif "speaker" in low:
            kind, label = "speaker", "Speakers"
        else:
            kind, label = "other", desc
        avail = True
        for p in s.get("ports") or []:
            if p.get("name") == s.get("active_port"):
                avail = p.get("availability") != "not available"
        res.append({"name": name, "label": label, "kind": kind, "volume": pct(s),
                    "default": name == default, "avail": avail})
    return res


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", ORIGIN)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        o = self.headers.get("Origin")
        if o and o != ORIGIN:
            return self._send(403, {"error": "origin"})
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/audio":
                return self._send(200, {"sinks": sinks()})
            if self.command == "POST" and u.path in ("/audio/default", "/audio/volume"):
                name = q.get("name", [""])[0]
                if name not in [s["name"] for s in sinks()]:
                    return self._send(404, {"error": "unknown output"})
                if u.path == "/audio/default":
                    pactl("set-default-sink", name)
                    for line in pactl("list", "short", "sink-inputs")[1].splitlines():
                        pactl("move-sink-input", line.split()[0], name)
                else:
                    n = max(0, min(MAXV, int(q["percent"][0])))
                    pactl("set-sink-volume", name, f"{n}%")
                return self._send(200, {"ok": True})
        except Exception as e:
            print("audio request failed:", e, flush=True)
            return self._send(500, {"error": "failed"})
        self._send(404, {"error": "not found"})

    do_GET = do_POST = _handle


ThreadingHTTPServer(("127.0.0.1", 8081), H).serve_forever()
