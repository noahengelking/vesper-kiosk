# Vesper NAS / Time Machine mode

This describes the setup used on the live headless Vesper box.

## Layout

- 1 TB USB HDD: formatted as a whole-disk bcache backing device
- 64 GiB `bcache` writeback cache file on the internal SSD
- ext4 NAS volume on `/dev/bcache0`, mounted at `/srv/vesper`
- `VesperTimeMachine` SMB share with a 800 GiB Time Machine quota
- `VesperFiles` general SMB share using the remaining space
- SMB user: `vesper`

## Files

| File | Purpose |
| --- | --- |
| `setup-bcache.sh` | One-time destructive formatting of the HDD |
| `vesper-bcache-up` | Reattaches the cache and sets writeback mode at boot |
| `vesper-bcache.service` | Runs the cache setup before the NAS mount |
| `fstab.example` | Mounts `LABEL=VESPER_NAS` at `/srv/vesper` |
| `smbd-vesper-nas.conf` | Orders Samba after the NAS mount |
| `smb.conf` | Samba shares and Time Machine/quota settings |

## Install steps

```bash
sudo apt install samba bcache-tools avahi-daemon
sudo ./setup-bcache.sh --yes-wipe /dev/sdX
sudo install -m 0755 vesper-bcache-up /usr/local/sbin/
sudo install -m 0644 vesper-bcache.service /etc/systemd/system/
sudo install -m 0644 smb.conf /etc/samba/smb.conf
sudo install -D -m 0644 smbd-vesper-nas.conf /etc/systemd/system/smbd.service.d/vesper-nas.conf
# append fstab.example to /etc/fstab
sudo systemctl enable --now vesper-bcache.service smbd.service
sudo useradd --system --home-dir /srv/vesper --shell /usr/sbin/nologin --user-group vesper
sudo smbpasswd -a vesper
```

Then, on macOS:

1. Open **System Settings → General → Time Machine → Add Backup Disk**.
2. Select **VESPER** / `VesperTimeMachine`.
3. Use SMB username `vesper` and the password set with `smbpasswd`.
4. `VesperFiles` can be mounted with Finder via `smb://vesper.local/VesperFiles`.

## Warning

The cache is **writeback**, which improves small-write performance but can lose
recently cached writes on power loss. Use a UPS if the data is important. The
cache file also wears the eMMC; monitor it over time.

## macOS Time Machine destination

The live Mac can use either **System Settings → General → Time Machine →
Add Backup Disk…**, selecting the advertised **VESPER** share, or this command:

```bash
sudo tmutil setdestination -a \
  "smb://vesper@vesper.local/VesperTimeMachine"
```

Use the SMB password set with `smbpasswd -a vesper`. The share reports an
800 GiB Time Machine quota and is advertised over Bonjour by Samba's built-in
`fruit:time machine` support.

## Browser dashboard and static websites

The `web/` directory contains a small, read-only dashboard served at:

```
http://vesper.local:8088
```

It shows NAS space, bcache write-cache health, Time Machine share status, SMB
clients, uptime, network and disk throughput. It is LAN-only and runs as the
`vesper` user; it does not expose the kiosk's privileged control endpoints.

A static site can be hosted from `VesperFiles/www`. Anything placed there is
served at `http://vesper.local:8088/site/`.

## Wi-Fi tuning

`install-wifi-tuning.sh` disables the RTL8821CU adapter's deep low-power state
and runtime power saving. This modestly improves latency and receive throughput
on the USB Wi-Fi adapter. The NAS has no built-in Ethernet and the adapter is a
1x1 RTL8821CU; a USB 3 Ethernet adapter is the best way to significantly
increase Time Machine throughput.

## Important: HDD removal

**Never unplug the USB HDD while the NAS is mounted or a backup is running.**
The HDD is the backing device for the live ext4 filesystem and bcache cache.
Removing it mid-write causes bcache and ext4 I/O errors.

Before moving the HDD or changing USB ports:

```bash
sudo systemctl stop smbd vesper-web
sudo umount /srv/vesper
sudo systemctl stop vesper-bcache
sudo poweroff
```

Power down first, move the cable, then boot and verify `/srv/vesper` is mounted
before starting Time Machine again.

## Safe shutdown before moving the HDD

Run this on the Mac first:

```bash
tmutil stopbackup
```

Then, on the NAS:

```bash
sudo vesper-safe-poweroff
```

The script stops SMB and the dashboard, drains bcache dirty data, syncs and
unmounts `/srv/vesper`, stops bcache, and powers off. Do not move the HDD until
the NAS is fully powered off.

The dashboard's battery card reads the server's `BAT0` power supply and AC
state directly. It does not depend on the Mac.
