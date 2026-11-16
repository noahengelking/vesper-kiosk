#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

install -m 0644 "$SCRIPT_DIR/smb.conf" /etc/samba/smb.conf
testparm -s >/tmp/vesper-testparm.out 2>&1
cat /tmp/vesper-testparm.out
systemctl restart smbd.service
sleep 1
systemctl is-active smbd.service
echo "Samba is configured. Create/update the SMB user with: sudo smbpasswd -a vesper"
