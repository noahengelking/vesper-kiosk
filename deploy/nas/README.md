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
