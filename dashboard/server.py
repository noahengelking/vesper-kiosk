#!/usr/bin/env python3
import json, os, re, shutil, subprocess, threading, time, urllib.error, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(os.path.expanduser("~"), ".config", "desk-dashboard")
TOKEN_FILE = os.path.join(CONF, "spotify.json")
with open(os.path.join(HERE, "config.json")) as f:
    CLIENT_ID = json.load(f)["client_id"]
LOCK = threading.Lock()
SP_LOCK = threading.Lock()
SP_CACHE = {}
SP_INFLIGHT = {}
SP_CACHE_TTL = 1.25
SP_ERROR_TTL = 5.0
SP_INFLIGHT_WAIT = 15.0
LYRICS_LOCK = threading.Lock()
LYRICS_CACHE = {}


class _SpotifyFlight:
    __slots__ = ("event", "result")

    def __init__(self):
        self.event = threading.Event()
        self.result = None


def _sp_cache_key(path, params):
    return path, tuple(sorted((params or {}).items()))


def load_tokens():
    try:
        with open(TOKEN_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def save_tokens(t):
    os.makedirs(CONF, exist_ok=True)
    tmp = TOKEN_FILE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(t, f)
    os.replace(tmp, TOKEN_FILE)


def refresh(t):
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "refresh_token": t["refresh_token"],
        "client_id": CLIENT_ID,
    }).encode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token", data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=10) as r:
        j = json.load(r)
    t["access_token"] = j["access_token"]
    t["expires_at"] = time.time() + j.get("expires_in", 3600) - 60
    if j.get("refresh_token"):
        t["refresh_token"] = j["refresh_token"]
    save_tokens(t)
    return t


def access_token():
    with LOCK:
        t = load_tokens()
        if not t:
            return None
        if time.time() >= t.get("expires_at", 0):
            t = refresh(t)
        return t["access_token"]


def _j(b):
    try:
        return json.loads(b) if b else None
    except Exception:
        return None


def _sp_uncached(method, path, params=None):
    try:
        tok = access_token()
    except Exception:
        return 0, None
    if tok is None:
        return -1, None
    url = "https://api.spotify.com/v1" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = b"" if method in ("PUT", "POST") else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            body = r.read()
            return r.status, _j(body)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, None
    except Exception as e:
        print("spotify request failed:", method, path, type(e).__name__, e, flush=True)
        return 0, None


def sp(method, path, params=None):
    # Spotify GETs can be slow. Let concurrent callers share one in-flight
    # request, then briefly cache the result so polls cannot pile up.
    if method != "GET":
        return _sp_uncached(method, path, params)

    key = _sp_cache_key(path, params)
    with SP_LOCK:
        cached = SP_CACHE.get(key)
        if cached and cached[0] > time.monotonic():
            return cached[1]
        flight = SP_INFLIGHT.get(key)
        owner = flight is None
        if owner:
            flight = _SpotifyFlight()
            SP_INFLIGHT[key] = flight

    if not owner:
        if not flight.event.wait(SP_INFLIGHT_WAIT):
            return 0, None
        return flight.result if flight.result is not None else (0, None)

    try:
        result = _sp_uncached(method, path, params)
    except Exception as e:
        print("spotify request failed:", method, path, type(e).__name__, e, flush=True)
        result = (0, None)

    ttl = SP_CACHE_TTL if result[0] in (200, 204) else SP_ERROR_TTL
    with SP_LOCK:
        SP_CACHE[key] = (time.monotonic() + ttl, result)
        if len(SP_CACHE) > 256:
            expiry = time.monotonic()
            for old_key in [k for k, v in SP_CACHE.items() if v[0] <= expiry]:
                SP_CACHE.pop(old_key, None)
        SP_INFLIGHT.pop(key, None)
    flight.result = result
    flight.event.set()
    return result


def now():
    s, j = sp("GET", "/me/player")
    if s == -1:
        return {"state": "login"}
    if s == 200 and j and j.get("item"):
        it = j["item"]
        imgs = (it.get("album") or {}).get("images") or []
        art = imgs[0]["url"] if imgs else None
        for im in imgs:
            if (im.get("width") or 9999) <= 400:
                art = im["url"]
                break
        names = ", ".join(a.get("name", "") for a in (it.get("artists") or []))
        if not names:
            names = (it.get("show") or {}).get("name", "")
        dev = j.get("device") or {}
        return {"state": "ok", "title": it.get("name", ""), "artist": names,
                "art": art, "playing": bool(j.get("is_playing")),
                "progress": j.get("progress_ms") or 0,
                "duration": it.get("duration_ms") or 1,
                "volume": dev.get("volume_percent"), "device": dev.get("name", ""),
                "shuffle": bool(j.get("shuffle_state")), "repeat": j.get("repeat_state", "off")}
    if s in (200, 204):
        return {"state": "idle"}
    return {"state": "error", "code": s}



def lyrics_lookup(title, artist, duration):
    title = (title or "").strip()[:180]
    artist = (artist or "").strip()[:180]
    key = (title.lower(), artist.lower(), int(duration or 0))
    if not title:
        return {"found": False, "error": "missing-title"}
    now = time.monotonic()
    with LYRICS_LOCK:
        hit = LYRICS_CACHE.get(key)
        if hit and hit[0] > now:
            return hit[1]
    q = urllib.parse.urlencode({
        "track_name": title,
        "artist_name": artist.split(",")[0].strip(),
        "duration": int(duration or 0),
    })
    req = urllib.request.Request(
        "https://lrclib.net/api/get?" + q,
        headers={"User-Agent": "VesperKiosk/1.0 (local dashboard)"})
    ttl = 3600.0
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            j = json.loads(r.read() or b"{}")
        result = {
            "found": bool(j.get("syncedLyrics") or j.get("plainLyrics")),
            "synced": j.get("syncedLyrics") or "",
            "plain": j.get("plainLyrics") or "",
            "title": j.get("trackName") or title,
            "artist": j.get("artistName") or artist,
            "instrumental": bool(j.get("instrumental")),
        }
        if not result["found"]:
            result["error"] = "not-found"
    except urllib.error.HTTPError as e:
        result = {"found": False, "error": "not-found" if e.code == 404 else "http-%s" % e.code}
        ttl = 120.0 if e.code == 404 else 60.0
    except Exception as e:
        result = {"found": False, "error": type(e).__name__}
        ttl = 60.0
    with LYRICS_LOCK:
        LYRICS_CACHE[key] = (time.monotonic() + ttl, result)
        if len(LYRICS_CACHE) > 128:
            cutoff = time.monotonic()
            for k in [k for k, v in LYRICS_CACHE.items() if v[0] <= cutoff]:
                LYRICS_CACHE.pop(k, None)
    return result


def _read_first(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return None


def _run_short(args, env=None, timeout=4):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)
        return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
    except Exception as e:
        return -1, "", type(e).__name__


def _user_systemctl_env():
    env = dict(os.environ)
    env["XDG_RUNTIME_DIR"] = "/run/user/%d" % os.getuid()
    env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/run/user/%d/bus" % os.getuid()
    return env


def health_info():
    load = list(os.getloadavg()) if hasattr(os, "getloadavg") else [0, 0, 0]
    mem = {}
    try:
        for line in open("/proc/meminfo"):
            parts = line.split()
            if len(parts) >= 2:
                mem[parts[0].rstrip(":")] = int(parts[1])
    except Exception:
        pass
    total_kb = mem.get("MemTotal", 0) or 0
    avail_kb = mem.get("MemAvailable", 0) or 0
    used_kb = max(0, total_kb - avail_kb)
    disk = shutil.disk_usage("/")
    temp = None
    try:
        for name in os.listdir("/sys/class/thermal"):
            if not name.startswith("thermal_zone"):
                continue
            val = _read_first("/sys/class/thermal/%s/temp" % name)
            if val is None:
                continue
            v = int(val) / 1000.0
            if v > 0 and (temp is None or v > temp):
                temp = round(v, 1)
    except Exception:
        pass
    uptime = None
    try:
        uptime = round(float(_read_first("/proc/uptime").split()[0]))
    except Exception:
        pass
    chromium_count = 0
    chromium_rss = 0
    code, ps_out, _ = _run_short(["ps", "-eo", "rss=,args="], timeout=4)
    for line in ps_out.splitlines():
        if "/usr/lib/chromium/chromium" in line:
            chromium_count += 1
            try:
                chromium_rss += int(line.strip().split(None, 1)[0])
            except Exception:
                pass
    uenv = _user_systemctl_env()
    _, kiosk_state, _ = _run_short(["systemctl", "--user", "is-active", "vesper-kiosk.service"], env=uenv)
    _, kiosk_restarts, _ = _run_short(["systemctl", "--user", "show", "-p", "NRestarts", "--value", "vesper-kiosk.service"], env=uenv)
    _, dash_state, _ = _run_short(["systemctl", "is-active", "desk-dashboard.service"])
    return {
        "ok": True,
        "uptime": uptime,
        "load": [round(x, 2) for x in load],
        "memory": {"total_mb": round(total_kb / 1024), "used_mb": round(used_kb / 1024),
                   "percent": round(100 * used_kb / total_kb, 1) if total_kb else None},
        "disk": {"total_gb": round(disk.total / 1e9, 1), "used_gb": round(disk.used / 1e9, 1),
                 "percent": round(100 * disk.used / disk.total, 1) if disk.total else None},
        "temperature_c": temp,
        "chromium": {"processes": chromium_count, "rss_mb": round(chromium_rss / 1024)},
        "services": {"kiosk": kiosk_state or "unknown", "kiosk_restarts": int(kiosk_restarts or 0),
                     "dashboard": dash_state or "unknown"},
        "hostname": socket.gethostname(),
    }


def restart_kiosk():
    code, out, err = _run_short(["systemctl", "--user", "restart", "vesper-kiosk.service"],
                                env=_user_systemctl_env(), timeout=12)
    return {"ok": code == 0, "error": (err or out) if code != 0 else ""}


import socket


def sp2(method, path, params=None, body=None):
    try:
        tok = access_token()
    except Exception:
        return 0, None
    if tok is None:
        return -1, None
    url = "https://api.spotify.com/v1" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    if body is not None:
        data = json.dumps(body).encode()
    else:
        data = b"" if method in ("PUT", "POST") else None
    headers = {"Authorization": "Bearer " + tok}
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read()
            return r.status, _j(raw)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, None
    except Exception:
        return 0, None


def devices():
    s, j = sp("GET", "/me/player/devices")
    if s != 200 or not j:
        return {"devices": [], "code": s}
    return {"devices": [{"id": d.get("id"), "name": d.get("name", ""), "type": d.get("type", ""),
                         "active": bool(d.get("is_active"))}
                        for d in j.get("devices", []) if d.get("id")]}


# ---- Wi-Fi: scan and join through wpa_supplicant's control socket (needs the netdev group)
import json as _json
import re as _re
import threading as _th
import time as _time

WPA_CLI = "/usr/sbin/wpa_cli"
_SECURE_TAGS = ("WPA", "RSN", "WEP", "SAE", "PSK")
_wifi_scan_at = [0.0]
_wifi_lock = _th.Lock()
_wifi_job = {"state": "idle", "ssid": "", "msg": ""}


def _wifi_iface():
    try:
        for n in sorted(os.listdir("/sys/class/net")):
            if os.path.isdir("/sys/class/net/%s/wireless" % n):
                return n
    except Exception:
        pass
    return None


def _current_wifi_ssid(iface):
    if not iface:
        return None
    code, out, _ = _run_short(["/usr/sbin/wpa_cli", "-i", iface, "status"], timeout=3)
    if code != 0:
        return None
    for line in out.splitlines():
        if line.startswith("ssid="):
            return line[5:].strip() or None
    return None


def _saved_wifi_psk(ssid):
    """Read the local wpa_supplicant config for the current network.

    wpa_cli masks saved passphrases for unprivileged callers, but the
    Vesper config contains the plaintext psk. This is only served over the
    kiosk's localhost HTTP endpoint for the guest QR code.
    """
    if not ssid:
        return None
    try:
        names = sorted(os.listdir("/etc/wpa_supplicant"))
    except Exception:
        return None
    for name in names:
        if not name.endswith(".conf"):
            continue
        path = os.path.join("/etc/wpa_supplicant", name)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        for block in re.findall(r"network\s*=\s*\{(.*?)\}", text, re.S):
            m = re.search(r'ssid\s*=\s*"((?:\\.|[^"])*)"', block)
            if not m:
                continue
            found = m.group(1).replace('\\"', '"').replace('\\\\', '\\')
            if found != ssid:
                continue
            pm = re.search(r'psk\s*=\s*"((?:\\.|[^"])*)"', block)
            if not pm:
                pm = re.search(r'psk\s*=\s*([0-9a-fA-F]{64})', block)
            if pm:
                return pm.group(1)
    return None


def wifi_credentials():
    iface = _wifi_iface()
    ssid = _current_wifi_ssid(iface)
    psk = _saved_wifi_psk(ssid)
    return {"ssid": ssid, "password": psk, "security": "WPA2" if psk else "saved"}


def _wpa(iface, *args):
    try:
        r = subprocess.run([WPA_CLI, "-i", iface] + list(args),
                           capture_output=True, text=True, timeout=8)
        return (r.stdout + r.stderr).strip()
    except Exception as e:
        return "ERROR %s" % e


def _wpa_denied(out):
    return "Permission denied" in out or "Failed to connect" in out or out.startswith("ERROR")


def _wpa_ok(out):
    return bool(out) and out.splitlines()[-1].strip() == "OK"


def _ssid_text(s):
    try:
        raw = _re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), s)
        return raw.encode("latin-1", "replace").decode("utf-8", "replace")
    except Exception:
        return s


def _wifi_rows(iface):
    best = {}
    for line in _wpa(iface, "scan_results").splitlines()[1:]:
        p = line.split("\t")
        if len(p) < 5 or not p[4].strip():
            continue
        try:
            freq, sig = int(p[1]), int(p[2])
        except ValueError:
            continue
        ssid = _ssid_text(p[4])
        if not ssid.strip("\x00"):
            continue
        if ssid not in best or sig > best[ssid]["signal"]:
            best[ssid] = {"ssid": ssid, "signal": sig, "freq": freq, "flags": p[3]}
    return best


def _wifi_saved(iface):
    saved = {}
    for line in _wpa(iface, "list_networks").splitlines()[1:]:
        p = line.split("\t")
        if len(p) >= 2:
            saved[_ssid_text(p[1])] = p[0]
    return saved


def _wifi_status(iface):
    st = {}
    for line in _wpa(iface, "status").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            st[k] = v
    return st


def wifi_scan():
    iface = _wifi_iface()
    if not iface:
        return {"error": "no-wifi", "networks": []}
    now = _time.time()
    if now - _wifi_scan_at[0] > 3:
        _wifi_scan_at[0] = now
        if _wpa_denied(_wpa(iface, "scan")):
            return {"error": "no-access", "networks": []}
    saved = _wifi_saved(iface)
    cur = _wifi_status(iface).get("ssid")
    nets = []
    for r in _wifi_rows(iface).values():
        f = r["flags"]
        nets.append({"ssid": r["ssid"], "signal": r["signal"],
                     "band": "6 GHz" if r["freq"] >= 5925 else ("5 GHz" if r["freq"] >= 4900 else "2.4 GHz"),
                     "secure": any(t in f for t in _SECURE_TAGS),
                     "saved": r["ssid"] in saved, "current": r["ssid"] == cur})
    nets.sort(key=lambda n: (not n["current"], -n["signal"]))
    return {"networks": nets[:30], "current": cur}


def _wifi_set(state, ssid="", msg=""):
    with _wifi_lock:
        _wifi_job.update(state=state, ssid=ssid, msg=msg)


def wifi_job_state():
    with _wifi_lock:
        return dict(_wifi_job)


def _wifi_join_worker(iface, ssid, psk):
    nid = None
    created = False
    try:
        if _wpa_denied(_wpa(iface, "status")):
            return _wifi_set("fail", ssid, "no-access")
        flags = _wifi_rows(iface).get(ssid, {}).get("flags", "")
        secure = any(t in flags for t in _SECURE_TAGS)
        saved = _wifi_saved(iface)
        nid = saved.get(ssid)
        steps = []
        if nid is None:
            if secure and not psk:
                return _wifi_set("fail", ssid, "need-password")
            out = _wpa(iface, "add_network")
            nid = out.splitlines()[-1].strip() if out else ""
            if not nid.isdigit():
                return _wifi_set("fail", ssid, "add-failed")
            created = True
            steps += [("ssid", ssid.encode("utf-8").hex()), ("id_str", '"default"')]
            if not secure:
                steps.append(("key_mgmt", "NONE"))
            else:
                sae, wpa = "SAE" in flags, "PSK" in flags
                if sae and not wpa:
                    steps += [("key_mgmt", "SAE"), ("ieee80211w", "2")]
                elif sae:
                    steps += [("key_mgmt", "WPA-PSK SAE"), ("ieee80211w", "1")]
        if psk:
            steps.append(("psk", '"%s"' % psk))
        prios = [0]
        for i in saved.values():
            v = _wpa(iface, "get_network", i, "priority")
            if v.lstrip("-").isdigit():
                prios.append(int(v))
        steps.append(("priority", str(max(prios) + 1)))  # the network you choose wins
        for k, v in steps:
            if not _wpa_ok(_wpa(iface, "set_network", nid, k, v)):
                raise RuntimeError("set_network %s failed" % k)
        _wpa(iface, "select_network", nid)
        end = _time.time() + 25
        while _time.time() < end:
            st = _wifi_status(iface)
            if st.get("wpa_state") == "COMPLETED" and st.get("id") == nid:
                _wpa(iface, "enable_network", "all")
                _wpa(iface, "save_config")
                return _wifi_set("ok", ssid)
            _time.sleep(1)
        raise RuntimeError("timeout")
    except Exception:
        pass
    # failed: forget a network we just added and let wpa_supplicant go back to the others
    if created and nid:
        _wpa(iface, "remove_network", nid)
    _wpa(iface, "enable_network", "all")
    _wifi_set("fail", ssid, "no-connection")


def wifi_join_request(handler):
    try:
        n = int(handler.headers.get("Content-Length", 0) or 0)
        body = _json.loads(handler.rfile.read(min(n, 4096)) or b"{}")
        ssid = str(body.get("ssid", ""))
        psk = body.get("psk")
        psk = None if psk in (None, "") else str(psk)
    except Exception:
        return {"ok": False, "error": "bad-request"}, 400
    if not ssid or len(ssid.encode("utf-8")) > 32 or "\x00" in ssid:
        return {"ok": False, "error": "bad-ssid"}, 400
    if psk is not None and not (8 <= len(psk) <= 63 and all(32 <= ord(c) <= 126 for c in psk)):
        return {"ok": False, "error": "bad-password"}, 400
    iface = _wifi_iface()
    if not iface:
        return {"ok": False, "error": "no-wifi"}, 400
    with _wifi_lock:
        if _wifi_job["state"] == "working":
            return {"ok": False, "error": "busy"}, 409
        _wifi_job.update(state="working", ssid=ssid, msg="")
    _th.Thread(target=_wifi_join_worker, args=(iface, ssid, psk), daemon=True).start()
    return {"ok": True}, 200


def net_info():
    out = {"iface": None, "ssid": None, "signal": None, "band": None, "ip": None, "online": False}
    try:
        for n in sorted(os.listdir("/sys/class/net")):
            if os.path.isdir("/sys/class/net/%s/wireless" % n):
                out["iface"] = n
                break
    except Exception:
        pass
    if out["iface"]:
        try:
            t = subprocess.run(["/usr/sbin/iw", "dev", out["iface"], "link"],
                               capture_output=True, text=True, timeout=3).stdout
            for line in t.splitlines():
                line = line.strip()
                if line.startswith("SSID:"):
                    out["ssid"] = line[5:].strip()
                elif line.startswith("signal:"):
                    out["signal"] = int(float(line.split()[1]))
                elif line.startswith("freq:"):
                    f = float(line.split()[1])
                    out["band"] = "6 GHz" if f >= 5925 else ("5 GHz" if f >= 4900 else "2.4 GHz")
        except Exception:
            pass
        if out["signal"] is None:
            try:
                with open("/proc/net/wireless") as f:
                    for line in f.read().splitlines()[2:]:
                        parts = line.split()
                        if parts and parts[0].rstrip(":") == out["iface"]:
                            v = int(float(parts[3].rstrip(".")))
                            if v < 0:
                                out["signal"] = v
            except Exception:
                pass
    try:
        so = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        so.connect(("1.1.1.1", 80))
        out["ip"] = so.getsockname()[0]
        so.close()
    except Exception:
        pass
    try:
        c = socket.create_connection(("1.1.1.1", 443), timeout=2)
        c.close()
        out["online"] = True
    except Exception:
        pass
    return out


def _bl(*args):
    return subprocess.run(["brightnessctl", "-c", "backlight"] + list(args),
                          capture_output=True, text=True, timeout=3)


def bright_get():
    try:
        f = _bl("-m").stdout.strip().splitlines()[0].split(",")
        return {"ok": True, "percent": int(f[3].rstrip("%"))}
    except Exception:
        return {"ok": False, "percent": None}


def bright_set(pct):
    try:
        r = _bl("set", "%d%%" % max(5, min(100, pct)))
        return (200 if r.returncode == 0 else 500), None
    except Exception:
        return 500, None


def power_ok():
    try:
        r = subprocess.run(["sudo", "-n", "-l", "/usr/bin/systemctl", "poweroff"],
                           capture_output=True, text=True, timeout=3)
        return r.returncode == 0
    except Exception:
        return False


def ssh_info():
    out = {"listening": False, "sessions": 0, "enabled": None}
    try:
        c = socket.create_connection(("127.0.0.1", 22), timeout=1)
        c.close()
        out["listening"] = True
    except Exception:
        pass
    try:
        t = subprocess.run(["ss", "-Htn", "state", "established", "sport", "=", ":22"],
                           capture_output=True, text=True, timeout=3).stdout
        out["sessions"] = len([l for l in t.splitlines() if l.strip()])
    except Exception:
        pass
    try:
        t = subprocess.run(["systemctl", "is-enabled", "ssh"],
                           capture_output=True, text=True, timeout=3).stdout.strip()
        out["enabled"] = t == "enabled"
    except Exception:
        pass
    return out


def battery_info():
    base = "/sys/class/power_supply"
    try:
        for n in sorted(os.listdir(base)):
            d = os.path.join(base, n)
            try:
                if open(os.path.join(d, "type")).read().strip() != "Battery":
                    continue
                cap = int(open(os.path.join(d, "capacity")).read().strip())
                status = open(os.path.join(d, "status")).read().strip()
                return {"present": True, "percent": cap, "status": status}
            except Exception:
                continue
    except Exception:
        pass
    return {"present": False}


def playlists():
    s, j = sp("GET", "/me/playlists", {"limit": 50})
    if s in (401, 403):
        return {"error": "scope", "code": s, "playlists": []}
    if s != 200 or not j:
        return {"error": "api", "code": s, "playlists": []}
    out = []
    for p in j.get("items") or []:
        if not p:
            continue
        t = p.get("items") or p.get("tracks") or {}
        out.append({"uri": p.get("uri"), "name": p.get("name", ""), "tracks": t.get("total")})
    order = []
    s2, cur_ = sp("GET", "/me/player")
    if s2 == 200 and cur_ and (cur_.get("context") or {}).get("type") == "playlist":
        order.append(cur_["context"].get("uri"))
    s3, rec = sp("GET", "/me/player/recently-played", {"limit": 50})
    if s3 == 200 and rec:
        for it in rec.get("items") or []:
            c = it.get("context") or {}
            if c.get("type") == "playlist" and c.get("uri") not in order:
                order.append(c.get("uri"))
    rank = {u: i for i, u in enumerate(order)}
    out.sort(key=lambda x: rank.get(x["uri"], len(rank)))
    uid = me_id()
    if uid:
        total = None
        sl, jl = sp("GET", "/me/tracks", {"limit": 1})
        if sl == 200 and jl:
            total = jl.get("total")
        out.insert(0, {"uri": "spotify:user:%s:collection" % uid, "name": "Liked Songs", "tracks": total, "liked": True})
    return {"playlists": out, "recent": s3 == 200}


def queue():
    s, j = sp("GET", "/me/player/queue")
    if s != 200 or not j:
        return {"error": s, "now": None, "queue": []}

    def one(t):
        if not t:
            return None
        who = ", ".join(a.get("name", "") for a in (t.get("artists") or []))
        if not who:
            who = (t.get("show") or {}).get("name", "")
        return {"title": t.get("name", ""), "artist": who}

    items = [one(t) for t in (j.get("queue") or [])[:25]]
    return {"now": one(j.get("currently_playing")), "queue": [x for x in items if x]}


def cur_id():
    s_, j_ = sp("GET", "/me/player")
    if s_ == 200 and j_ and j_.get("item"):
        return j_["item"].get("id")
    return None


import re


def playlist_items(uri, offset):
    if re.fullmatch(r"spotify:user:[^:\s]{1,60}:collection", uri):
        s, j = sp("GET", "/me/tracks", {"limit": 50, "offset": offset})
        if s in (401, 403):
            return {"error": "scope", "code": s, "items": []}
        if s != 200 or not j:
            return {"error": "api", "code": s, "items": []}
        raw = j.get("items") or []
        out = []
        for e in raw:
            e = e or {}
            t = e.get("track") or e.get("item") or {}
            u = t.get("uri") or ""
            if not u.startswith("spotify:track:"):
                continue
            who = ", ".join(a.get("name", "") for a in (t.get("artists") or []))
            out.append({"title": t.get("name", ""), "artist": who, "tu": u})
        return {"items": out, "total": j.get("total", offset + len(raw)), "next": offset + len(raw)}
    parts = uri.split(":")
    if len(parts) != 3 or parts[0] != "spotify" or parts[1] != "playlist" or not re.fullmatch(r"[A-Za-z0-9]{1,40}", parts[2]):
        return {"error": "bad", "items": []}
    s, j = sp("GET", "/playlists/%s/items" % parts[2], {"limit": 50, "offset": offset})
    if s in (403, 404):
        return {"error": "denied", "code": s, "items": []}
    if s != 200 or not j:
        return {"error": "api", "code": s, "items": []}
    raw = j.get("items") or []
    out = []
    for i, e in enumerate(raw):
        e = e or {}
        t = e.get("item") or e.get("track") or {}
        u = t.get("uri") or ""
        if not (u.startswith("spotify:track:") or u.startswith("spotify:episode:")):
            continue
        who = ", ".join(a.get("name", "") for a in (t.get("artists") or [])) or (t.get("show") or {}).get("name", "")
        out.append({"title": t.get("name", ""), "artist": who, "pos": offset + i})
    return {"items": out, "total": j.get("total", offset + len(raw)), "next": offset + len(raw)}


_ME = {"id": None}


def me_id():
    if _ME["id"]:
        return _ME["id"]
    s, j = sp("GET", "/me")
    if s == 200 and j and j.get("id"):
        _ME["id"] = j["id"]
    return _ME["id"]


def ok_ctx(uri):
    if len(uri) > 100:
        return False
    if uri.startswith("spotify:playlist:"):
        return re.fullmatch(r"spotify:playlist:[A-Za-z0-9]{1,40}", uri) is not None
    return re.fullmatch(r"spotify:user:[^:\s]{1,60}:collection", uri) is not None


def control(action, q):
    if action == "play":
        return sp("PUT", "/me/player/play")
    if action == "pause":
        return sp("PUT", "/me/player/pause")
    if action == "next":
        return sp("POST", "/me/player/next")
    if action == "prev":
        return sp("POST", "/me/player/previous")
    if action == "volume":
        try:
            pct = max(0, min(100, int(q.get("percent", ["0"])[0])))
        except ValueError:
            return 400, None
        return sp("PUT", "/me/player/volume", {"volume_percent": pct})
    if action == "brightness":
        try:
            return bright_set(int(q.get("percent", ["100"])[0]))
        except ValueError:
            return 400, None
    if action == "poweroff":
        try:
            subprocess.Popen(["sh", "-c", "sleep 1; sudo -n /usr/bin/systemctl poweroff"])
            return 200, None
        except Exception:
            return 500, None
    if action == "playlist":
        uri = q.get("uri", [""])[0]
        if not ok_ctx(uri):
            return 400, None
        return sp2("PUT", "/me/player/play", None, {"context_uri": uri})
    if action == "skipto":
        try:
            n = max(1, min(25, int(q.get("n", ["1"])[0])))
        except ValueError:
            return 400, None
        results = []
        for _ in range(n):
            before = cur_id()
            r = sp("POST", "/me/player/next")
            results.append(r[0])
            if r[0] >= 400 or r[0] <= 0:
                break
            for _w in range(12):
                time.sleep(0.35)
                if cur_id() != before:
                    break
        print("skipto n=%d results=%s" % (n, results), flush=True)
        return (results[-1] if results else 0), None
    if action == "playfrom":
        uri = q.get("uri", [""])[0]
        try:
            pos = max(0, int(q.get("pos", ["0"])[0]))
        except ValueError:
            return 400, None
        if not ok_ctx(uri):
            return 400, None
        tr = q.get("track", [""])[0]
        if tr:
            if not re.fullmatch(r"spotify:(track|episode):[A-Za-z0-9]{1,40}", tr):
                return 400, None
            return sp2("PUT", "/me/player/play", None, {"context_uri": uri, "offset": {"uri": tr}})
        return sp2("PUT", "/me/player/play", None, {"context_uri": uri, "offset": {"position": pos}})
    if action == "shuffle":
        on = q.get("state", ["false"])[0] == "true"
        return sp("PUT", "/me/player/shuffle", {"state": "true" if on else "false"})
    if action == "repeat":
        r = q.get("state", ["off"])[0]
        return sp("PUT", "/me/player/repeat", {"state": r if r in ("off", "context", "track") else "off"})
    if action == "transfer":
        did = q.get("id", [""])[0]
        if not did:
            return 400, None
        return sp2("PUT", "/me/player", None, {"device_ids": [did]})
    if action == "seek":
        try:
            ms = max(0, int(q.get("ms", ["0"])[0]))
        except ValueError:
            return 400, None
        return sp("PUT", "/me/player/seek", {"position_ms": ms})
    return 404, None


from datetime import date, datetime, timedelta, timezone

CAL_FILE = os.path.join(CONF, "calendar.urls")
CAL = {"cals": [], "updated": 0, "error": None}
CAL_LOCK = threading.Lock()


def cal_urls():
    try:
        with open(CAL_FILE) as f:
            return [l.strip() for l in f if l.strip()]
    except Exception:
        return []


def cal_refresh():
    import icalendar
    urls = cal_urls()
    cals, err = [], None
    for u in urls:
        try:
            with urllib.request.urlopen(u, timeout=30) as r:
                cals.append(icalendar.Calendar.from_ical(r.read()))
        except Exception as e:
            err = getattr(e, "code", type(e).__name__)
    with CAL_LOCK:
        if cals or not urls:
            CAL["cals"] = cals
        CAL["updated"] = time.time()
        CAL["error"] = err
        if err is None:
            CAL["ok"] = time.time()


def cal_loop():
    while True:
        try:
            cal_refresh()
        except Exception:
            CAL["error"] = "refresh"
        time.sleep(60 if CAL["error"] else 600)


def utc(dt):
    if dt.tzinfo is None:
        dt = dt.astimezone()
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def cal_events(start, end):
    import recurring_ical_events
    with CAL_LOCK:
        cals = list(CAL["cals"])
    out = []
    for cal in cals:
        try:
            found = recurring_ical_events.of(cal).between(start, end)
        except Exception:
            continue
        for e in found:
            try:
                if str(e.get("STATUS", "")).upper() == "CANCELLED":
                    continue
                s = e.get("DTSTART").dt
                if e.get("DTEND") is not None:
                    en = e.get("DTEND").dt
                elif e.get("DURATION") is not None:
                    en = s + e.get("DURATION").dt
                else:
                    en = None
                title = str(e.get("SUMMARY", "")) or "(no title)"
                if isinstance(s, datetime):
                    out.append({"s": utc(s), "e": utc(en if isinstance(en, datetime) else s),
                                "allday": False, "title": title})
                else:
                    if en is None:
                        en = s + timedelta(days=1)
                    out.append({"s": s.isoformat(), "e": en.isoformat(),
                                "allday": True, "title": title})
            except Exception:
                continue
    out.sort(key=lambda x: x["s"])
    return out


def cal_payload(start, end):
    urls = cal_urls()
    with CAL_LOCK:
        ready, err = CAL["updated"] > 0, CAL["error"]
        ok = CAL.get("ok", 0)
    return {"configured": bool(urls), "ready": ready, "error": err, "ok": ok,
            "events": cal_events(start, end) if urls and ready else []}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _safe_write(self, data):
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def send_json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self._safe_write(b)

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == "/api/now":
            return self.send_json(now())
        if p == "/api/lyrics":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            return self.send_json(lyrics_lookup(
                q.get("title", [""])[0], q.get("artist", [""])[0],
                q.get("duration", ["0"])[0]))
        if p == "/api/health":
            return self.send_json(health_info())
        if p == "/api/calendar":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                a = date.fromisoformat(q["start"][0])
                b = date.fromisoformat(q["end"][0])
            except Exception:
                return self.send_json({"error": "bad range"}, 400)
            return self.send_json(cal_payload(a, b))
        if p == "/api/brightness":
            return self.send_json(bright_get())
        if p == "/api/power":
            return self.send_json({"ok": power_ok()})
        if p == "/api/ssh":
            return self.send_json(ssh_info())
        if p == "/api/battery":
            return self.send_json(battery_info())
        if p == "/api/playlists":
            return self.send_json(playlists())
        if p == "/api/queue":
            return self.send_json(queue())
        if p == "/api/playlist-items":
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            try:
                off = max(0, int(q.get("offset", ["0"])[0]))
            except ValueError:
                off = 0
            return self.send_json(playlist_items(q.get("uri", [""])[0], off))
        if p == "/api/devices":
            return self.send_json(devices())
        if p == "/api/wifi-scan":
            return self.send_json(wifi_scan())
        if p == "/api/wifi-job":
            return self.send_json(wifi_job_state())
        if p == "/api/net":
            return self.send_json(net_info())
        if p == "/api/wifi-credentials":
            return self.send_json(wifi_credentials())
        if p in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                b = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self._safe_write(b)
            return
        self.send_error(404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/api/wifi-join":
            obj, code = wifi_join_request(self)
            return self.send_json(obj, code)
        if u.path == "/api/refresh-calendar":
            try:
                cal_refresh()
            except Exception:
                CAL["error"] = "refresh"
            return self.send_json({"ok": True, "error": CAL["error"]})
        if u.path == "/api/restart-kiosk":
            return self.send_json(restart_kiosk())
        if u.path.startswith("/api/"):
            s, _ = control(u.path[5:], urllib.parse.parse_qs(u.query))
            return self.send_json({"status": s})
        self.send_error(404)


if __name__ == "__main__":
    threading.Thread(target=cal_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8080), H).serve_forever()
