#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
command -v /usr/sbin/iw >/dev/null || apt-get install -y iw
install -m 0644 "$SCRIPT_DIR/vesper-wifi.conf" /etc/modprobe.d/vesper-wifi.conf
install -m 0755 "$SCRIPT_DIR/vesper-wifi-powersave-off" /usr/local/sbin/vesper-wifi-powersave-off
install -m 0644 "$SCRIPT_DIR/vesper-wifi-powersave.service" /etc/systemd/system/vesper-wifi-powersave.service
systemctl daemon-reload
systemctl enable --now vesper-wifi-powersave.service
systemctl is-active vesper-wifi-powersave.service
