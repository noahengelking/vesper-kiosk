#!/usr/bin/env bash
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
install -m 0755 /tmp/vesper-bcache-up /usr/local/sbin/vesper-bcache-up

cat > /etc/modules-load.d/vesper-bcache.conf <<'MODULES'
bcache
loop
MODULES

cat > /etc/systemd/system/vesper-bcache.service <<'UNIT'
[Unit]
Description=Vesper NAS bcache writeback cache
DefaultDependencies=no
After=systemd-udevd.service
Before=local-fs.target srv-vesper.mount
Wants=systemd-udevd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/vesper-bcache-up
TimeoutStartSec=120

[Install]
WantedBy=sysinit.target
UNIT

# Add the NAS mount if it is not already present.
python3 - <<'PY'
from pathlib import Path
p = Path('/etc/fstab')
text = p.read_text()
line = 'LABEL=VESPER_NAS /srv/vesper ext4 defaults,noatime,nofail,x-systemd.requires=vesper-bcache.service,x-systemd.after=vesper-bcache.service 0 2\n'
if 'LABEL=VESPER_NAS' not in text:
    if not text.endswith('\n'):
        text += '\n'
    text += line
    p.write_text(text)
PY

mkdir -p /etc/systemd/system/smbd.service.d
cat > /etc/systemd/system/smbd.service.d/vesper-nas.conf <<'UNIT'
[Unit]
RequiresMountsFor=/srv/vesper
After=srv-vesper.mount vesper-bcache.service
UNIT

systemctl daemon-reload
systemctl enable vesper-bcache.service
systemctl enable smbd.service
systemctl disable --now nmbd.service 2>/dev/null || true
systemctl start vesper-bcache.service
mount -a
systemctl restart smbd.service
systemctl restart avahi-daemon.service

echo '=== bcache state ==='
cat /sys/block/bcache0/bcache/cache_mode 2>/dev/null || true
cat /sys/block/bcache0/bcache/state 2>/dev/null || true
cat /sys/block/bcache0/bcache/cache 2>/dev/null || true
echo
echo '=== mount ==='
findmnt /srv/vesper
df -hT /srv/vesper /
echo
echo '=== fstab ==='
tail -5 /etc/fstab
echo
echo '=== services ==='
systemctl is-enabled vesper-bcache.service smbd.service nmbd.service avahi-daemon.service
systemctl is-active vesper-bcache.service smbd.service nmbd.service avahi-daemon.service
