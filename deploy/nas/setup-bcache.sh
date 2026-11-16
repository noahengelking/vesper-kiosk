#!/usr/bin/env bash
# Destructive one-time HDD setup for Vesper NAS.
# Run only after replacing the backing device and confirming that any data on
# it has been backed up elsewhere.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

BACKING="${2:-}"
CACHE_IMG="${CACHE_IMG:-/var/lib/vesper/bcache-cache.img}"
CACHE_SIZE="${CACHE_SIZE:-64G}"
MOUNT="${MOUNT:-/srv/vesper}"

if [ "${1:-}" != "--yes-wipe" ] || [ -z "$BACKING" ] || [ "${3:-}" != "" ]; then
  echo "Usage: $0 --yes-wipe /dev/sdX" >&2
  exit 2
fi
if [ ! -b "$BACKING" ]; then
  echo "Not a block device: $BACKING" >&2
  exit 2
fi

echo "WARNING: this will erase $BACKING"
echo "Press Ctrl-C within 10 seconds to abort."
sleep 10

umount "$MOUNT" 2>/dev/null || true
wipefs -a "$BACKING" || true
dd if=/dev/zero of="$BACKING" bs=1M count=16 conv=fsync status=none
sync

install -d -m 0755 /var/lib/vesper
[ -f "$CACHE_IMG" ] || fallocate -l "$CACHE_SIZE" "$CACHE_IMG"
chmod 600 "$CACHE_IMG"

modprobe bcache
make-bcache -B --block 4096 "$BACKING"
udevadm settle

LOOP=$(losetup -j "$CACHE_IMG" | awk -F: 'NR==1{print $1}')
[ -n "$LOOP" ] || LOOP=$(losetup --find --show "$CACHE_IMG")
make-bcache -C --writeback "$LOOP"
CACHE_UUID=$(bcache-super-show "$LOOP" | awk '/cset.uuid/{print $2}' | head -1)
echo "$CACHE_UUID" > /var/lib/vesper/cache.uuid

for _ in $(seq 1 30); do
  [ -b /dev/bcache0 ] && break
  udevadm settle
  sleep 1
done
[ -b /dev/bcache0 ] || { echo "bcache0 did not appear" >&2; exit 1; }
[ -d "/sys/fs/bcache/$CACHE_UUID" ] || echo "$LOOP" > /sys/fs/bcache/register
[ -d "/sys/block/bcache0/bcache/cache/cache0" ] || echo "$CACHE_UUID" > /sys/block/bcache0/bcache/attach
echo writeback > /sys/block/bcache0/bcache/cache_mode
echo 20 > /sys/block/bcache0/bcache/writeback_percent || true
echo 10 > /sys/block/bcache0/bcache/writeback_delay || true
echo 0 > /sys/block/bcache0/bcache/sequential_cutoff || true
udevadm settle

mkfs.ext4 -F -L VESPER_NAS -m 1 /dev/bcache0
install -d -m 0755 "$MOUNT"
mount -o noatime /dev/bcache0 "$MOUNT"
install -d -o vesper -g vesper -m 0770 "$MOUNT/time-machine"
install -d -o vesper -g vesper -m 0770 "$MOUNT/files"
echo "Created $MOUNT and shares; install the systemd/fstab/Samba files next."
