#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
install -m 0755 "$SCRIPT_DIR/vesper-bcache-up" /usr/local/sbin/vesper-bcache-up
install -m 0644 "$SCRIPT_DIR/vesper-bcache.service" /etc/systemd/system/vesper-bcache.service

cat > /etc/modules-load.d/vesper-bcache.conf <<'MODULES'
bcache
loop
MODULES

if ! grep -q 'LABEL=VESPER_NAS' /etc/fstab; then
    cat "$SCRIPT_DIR/fstab.example" >> /etc/fstab
fi

install -d -m 0755 /etc/systemd/system/smbd.service.d
install -m 0644 "$SCRIPT_DIR/smbd-vesper-nas.conf" /etc/systemd/system/smbd.service.d/vesper-nas.conf

systemctl daemon-reload
systemctl enable vesper-bcache.service smbd.service
systemctl disable --now nmbd.service 2>/dev/null || true
systemctl start vesper-bcache.service
mount -a
systemctl restart smbd.service
systemctl restart avahi-daemon.service

echo '=== bcache state ==='
cat /sys/block/bcache0/bcache/cache_mode 2>/dev/null || true
cat /sys/block/bcache0/bcache/state 2>/dev/null || true
echo
echo '=== mount ==='
findmnt /srv/vesper
df -hT /srv/vesper /
echo
echo '=== services ==='
systemctl is-enabled vesper-bcache.service smbd.service nmbd.service avahi-daemon.service
systemctl is-active vesper-bcache.service smbd.service nmbd.service avahi-daemon.service
