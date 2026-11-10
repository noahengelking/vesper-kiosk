#!/usr/bin/env python3
import base64, hashlib, json, os, secrets, sys, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(os.path.expanduser("~"), ".config", "desk-dashboard")
TOKEN_FILE = os.path.join(CONF, "spotify.json")
with open(os.path.join(HERE, "config.json")) as f:
    CLIENT_ID = json.load(f)["client_id"]
PORT = 8888
REDIRECT = "http://127.0.0.1:%d/callback" % PORT
SCOPE = "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-read-recently-played user-library-read"

verifier = secrets.token_urlsafe(64)
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
state = secrets.token_urlsafe(16)
url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
    "response_type": "code", "client_id": CLIENT_ID, "scope": SCOPE,
    "code_challenge_method": "S256", "code_challenge": challenge,
    "redirect_uri": REDIRECT, "state": state})

result = {}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path != "/callback":
            self.send_error(404)
            return
        q = urllib.parse.parse_qs(u.query)
        result["code"] = q.get("code", [None])[0]
        result["state"] = q.get("state", [None])[0]
        result["error"] = q.get("error", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"Done. You can close this tab.")


print("\nOpen this URL in the browser on your Mac and approve access:\n\n" + url + "\n")
print("Waiting for approval (this needs the SSH tunnel on port %d)..." % PORT)
srv = HTTPServer(("127.0.0.1", PORT), H)
while not result:
    srv.handle_request()

if result.get("error") or not result.get("code") or result.get("state") != state:
    sys.exit("Login failed: %s" % (result.get("error") or "bad response"))

data = urllib.parse.urlencode({
    "client_id": CLIENT_ID, "grant_type": "authorization_code",
    "code": result["code"], "redirect_uri": REDIRECT,
    "code_verifier": verifier}).encode()
req = urllib.request.Request(
    "https://accounts.spotify.com/api/token", data=data,
    headers={"Content-Type": "application/x-www-form-urlencoded"})
with urllib.request.urlopen(req, timeout=15) as r:
    j = json.load(r)

os.makedirs(CONF, exist_ok=True)
fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump({"access_token": j["access_token"], "refresh_token": j["refresh_token"],
               "expires_at": time.time() + j.get("expires_in", 3600) - 60}, f)
print("Connected. The dashboard will pick it up within a few seconds.")
