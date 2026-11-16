#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
install -d -m 0755 /opt/vesper-web
install -m 0644 "$SCRIPT_DIR/server.py" /opt/vesper-web/server.py
install -m 0644 "$SCRIPT_DIR/index.html" /opt/vesper-web/index.html
install -m 0644 "$SCRIPT_DIR/vesper-web.service" /etc/systemd/system/vesper-web.service
install -m 0644 "$SCRIPT_DIR/vesper-web.avahi.service" /etc/avahi/services/vesper-web.service
install -d -o vesper -g vesper -m 0770 /srv/vesper/files/www
if [ ! -f /srv/vesper/files/www/index.html ]; then
  cat > /srv/vesper/files/www/index.html <<'SITE'
<!doctype html><meta charset="utf-8"><title>Vesper site</title>
<style>body{background:#08080a;color:#e9e6df;font:18px system-ui;padding:10vw}h1{font-weight:300;font-size:48px}code{color:#f1b84a}</style>
<h1>Your website lives here.</h1>
<p>Drop files into <code>VesperFiles/www</code> on the NAS. The dashboard will link to them at <code>/site/</code>.</p>
SITE
  chown vesper:vesper /srv/vesper/files/www/index.html
fi
systemctl daemon-reload
systemctl enable --now vesper-web.service
systemctl restart avahi-daemon.service
sleep 1
systemctl is-active vesper-web.service
systemctl is-active avahi-daemon.service
