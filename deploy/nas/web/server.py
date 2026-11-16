#!/usr/bin/env python3
"""Small, dependency-free Vesper NAS dashboard web server."""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SITE_ROOT = Path("/srv/vesper/files/www")
PORT = int(os.environ.get("VESPER_WEB_PORT", "8088"))
BIND = os.environ.get("VESPER_WEB_BIND", "0.0.0.0")
CACHE_SIZE_BYTES = 64 * 1024**3
TM_QUOTA_BYTES = 800 * 1024**3

_state_lock = threading.Lock()
_previous = {"time": 0.0, "net": None, "disk": None}
_battery_lock = threading.Lock()
_mac_battery = {"percent": None, "charging": None, "updated": 0.0}


def read_text(path: str, default: str = "") -> str:
    try:
        return Path(path).read_text().strip()
    except (OSError, PermissionError):
        return default


def read_int(path: str, default: int = 0) -> int:
    try:
        return int(read_text(path))
    except ValueError:
        return default


def parse_size(value: str) -> int:
    value = value.strip()
    if not value:
        return 0
    units = {"K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}
    if value[-1].upper() in units:
        try:
            return int(float(value[:-1]) * units[value[-1].upper()])
        except ValueError:
            return 0
    try:
        return int(value)
    except ValueError:
        return 0


def fs_usage(path: str) -> dict:
    try:
        st = os.statvfs(path)
    except OSError:
        return {"available": False, "total": 0, "used": 0, "free": 0, "percent": 0}
    total = st.f_frsize * st.f_blocks
    free = st.f_frsize * st.f_bavail
    used = max(0, total - free)
    return {
        "available": True,
        "total": total,
        "used": used,
        "free": free,
        "percent": round((used / total * 100) if total else 0, 1),
    }


def net_counters():
    rx = tx = 0
    try:
        lines = Path("/proc/net/dev").read_text().splitlines()[2:]
    except OSError:
        return {"rx": 0, "tx": 0}
    for line in lines:
        if ":" not in line:
            continue
        name, values = line.split(":", 1)
        if name.strip() == "lo":
            continue
        parts = values.split()
        if len(parts) >= 9:
            rx += int(parts[0])
            tx += int(parts[8])
    return {"rx": rx, "tx": tx}


def disk_counters():
    result = {}
    try:
        for line in Path("/proc/diskstats").read_text().splitlines():
            parts = line.split()
            if len(parts) >= 14 and (parts[2] in {"sda", "loop0"} or parts[2].startswith("bcache")):
                result[parts[2]] = {
                    "read_bytes": int(parts[5]) * 512,
                    "write_bytes": int(parts[9]) * 512,
                }
    except OSError:
        pass
    return result


def bcache_sysfs():
    matches = sorted(Path("/sys/block").glob("bcache[0-9]*"))
    return matches[0] if matches else None


def smb_client_count() -> int:
    """Count active SMB sessions from the kernel TCP tables."""
    endpoints = set()
    for filename in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(filename).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue
            local = parts[1].split(":")
            remote = parts[2].split(":")
            if len(local) != 2 or len(remote) != 2:
                continue
            try:
                local_port = int(local[1], 16)
                state = parts[3]
            except ValueError:
                continue
            if local_port == 445 and state == "01" and remote[0] not in {"00000000", "0"}:
                endpoints.add(parts[2])
    return len(endpoints)


def process_running(name: str) -> bool:
    for proc in Path("/proc").glob("[0-9]*/comm"):
        if read_text(str(proc)) == name:
            return True
    return False


def ips():
    try:
        out = subprocess.check_output(["hostname", "-I"], text=True, timeout=2)
        return [x for x in out.split() if ":" not in x]
    except Exception:
        try:
            return [socket.gethostbyname(socket.gethostname())]
        except OSError:
            return []


def memory():
    values = {}
    for line in read_text("/proc/meminfo").splitlines():
        key, _, rest = line.partition(":")
        try:
            values[key] = int(rest.strip().split()[0]) * 1024
        except (ValueError, IndexError):
            pass
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    used = max(0, total - available)
    return {"total": total, "available": available, "used": used, "percent": round(used / total * 100, 1) if total else 0}


def cache_state() -> dict:
    base = bcache_sysfs()
    if base is None:
        return {"available": False, "mode": "unavailable", "state": "unknown", "dirty": 0,
                "written": 0, "available_percent": 0, "used_percent": 0,
                "size": CACHE_SIZE_BYTES, "hits": 0, "misses": 0, "hit_rate": None}
    path = str(base / "bcache")
    mode = read_text(f"{path}/cache_mode") or "unavailable"
    selected = "writeback" if "[writeback]" in mode else ("writethrough" if "[writethrough]" in mode else mode)
    dirty = parse_size(read_text(f"{path}/dirty_data", "0"))
    available = read_int(f"{path}/cache/cache_available_percent", 0)
    written = parse_size(read_text(f"{path}/cache/cache0/written", "0"))
    hits = read_int(f"{path}/stats_total/cache_hits")
    misses = read_int(f"{path}/stats_total/cache_misses")
    total_requests = hits + misses
    return {
        "available": Path(f"{path}/cache_mode").exists(),
        "mode": selected,
        "state": read_text(f"{path}/state", "unknown"),
        "dirty": dirty,
        "written": written,
        "available_percent": available,
        "used_percent": round(max(0, min(100, 100 - available)), 1),
        "size": CACHE_SIZE_BYTES,
        "hits": hits,
        "misses": misses,
        "hit_rate": round(hits / total_requests * 100, 1) if total_requests else None,
    }


def mac_battery_state() -> dict:
    with _battery_lock:
        battery = dict(_mac_battery)
    age = time.time() - battery["updated"] if battery["updated"] else None
    available = battery["percent"] is not None and age is not None and age < 300
    return {
        "available": available,
        "percent": battery["percent"],
        "charging": battery["charging"],
        "age": round(age, 1) if age is not None else None,
    }


def status() -> dict:
    now = time.time()
    net = net_counters()
    disk = disk_counters()
    with _state_lock:
        previous = dict(_previous)
        _previous.update({"time": now, "net": net, "disk": disk})
    dt = now - previous["time"] if previous["time"] else 0
    rx_rate = tx_rate = 0
    if dt > 0 and previous["net"]:
        rx_rate = max(0, (net["rx"] - previous["net"]["rx"]) / dt)
        tx_rate = max(0, (net["tx"] - previous["net"]["tx"]) / dt)
    disk_rates = {}
    if dt > 0 and previous["disk"]:
        for name, current in disk.items():
            old = previous["disk"].get(name)
            if old:
                disk_rates[name] = {
                    "read": max(0, (current["read_bytes"] - old["read_bytes"]) / dt),
                    "write": max(0, (current["write_bytes"] - old["write_bytes"]) / dt),
                }
    uptime = 0.0
    try:
        uptime = float(read_text("/proc/uptime", "0").split()[0])
    except (ValueError, IndexError):
        pass
    try:
        load = [float(x) for x in read_text("/proc/loadavg").split()[:3]]
    except ValueError:
        load = [0, 0, 0]
    return {
        "now": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "host": socket.gethostname(),
        "ips": ips(),
        "uptime": uptime,
        "load": load,
        "memory": memory(),
        "storage": dict(fs_usage("/srv/vesper"), mount="/srv/vesper"),
        "root": fs_usage("/"),
        "cache": cache_state(),
        "net": {"rx": rx_rate, "tx": tx_rate},
        "disk_io": dict(disk_rates, **({"bcache": next((v for k, v in disk_rates.items() if k.startswith("bcache")), {})} if any(k.startswith("bcache") for k in disk_rates) else {})),
        "smb": {
            "clients": smb_client_count(),
            "shares": ["VesperTimeMachine", "VesperFiles"],
        },
        "time_machine": {
            "share": "VesperTimeMachine",
            "quota": TM_QUOTA_BYTES,
            "url": "smb://vesper.local/VesperTimeMachine",
        },
        "services": {
            "smbd": process_running("smbd"),
            "avahi": process_running("avahi-daemon"),
            "bcache": bcache_sysfs() is not None,
            "web": True,
        },
        "site": {
            "available": (SITE_ROOT / "index.html").exists(),
            "url": "/site/",
        },
        "mac_battery": mac_battery_state(),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "VesperNAS/1.0"

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}", flush=True)

    def _client_allowed(self) -> bool:
        ip = self.client_address[0]
        if ip in {"127.0.0.1", "::1"}:
            return True
        return ip.startswith(("192.168.", "10.", "172.16.", "172.17.", "172.18.", "172.19.", "172.2", "172.30.", "172.31.", "fe80:"))

    def _send_json(self, payload: dict, status_code: int = 200):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path: Path):
        if not path.is_file():
            self.send_error(404)
            return
        content_types = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "application/javascript; charset=utf-8",
            ".json": "application/json; charset=utf-8",
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".svg": "image/svg+xml",
            ".ico": "image/x-icon",
            ".txt": "text/plain; charset=utf-8",
        }
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_types.get(path.suffix.lower(), "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self._client_allowed():
            self.send_error(403)
            return
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/api/client/battery":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 4096:
                raise ValueError("invalid length")
            payload = json.loads(self.rfile.read(length).decode())
            percent = float(payload["percent"])
            if not (0 <= percent <= 100):
                raise ValueError("invalid percentage")
            with _battery_lock:
                _mac_battery.update(
                    percent=round(percent, 1),
                    charging=bool(payload.get("charging")),
                    updated=time.time(),
                )
            self._send_json({"ok": True})
        except Exception:
            self._send_json({"ok": False, "error": "invalid battery payload"}, 400)

    def do_GET(self):
        if not self._client_allowed():
            self.send_error(403)
            return
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)
        if path == "/api/status":
            self._send_json(status())
            return
        if path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        if path == "/" or path == "":
            self._send_file(ROOT / "index.html")
            return
        if path.startswith("/site/"):
            rel = path[len("/site/"):]
            target = (SITE_ROOT / rel).resolve()
            try:
                target.relative_to(SITE_ROOT.resolve())
            except ValueError:
                self.send_error(403)
                return
            if target.is_dir():
                target = target / "index.html"
            self._send_file(target)
            return
        if path.startswith("/assets/"):
            target = (ROOT / path.lstrip("/")).resolve()
            try:
                target.relative_to(ROOT.resolve())
            except ValueError:
                self.send_error(403)
                return
            self._send_file(target)
            return
        self.send_error(404)


def main():
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    server.daemon_threads = True
    print(f"Vesper NAS dashboard listening on http://{BIND}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
