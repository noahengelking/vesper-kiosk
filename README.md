# Vesper Kiosk

A touch-first, always-on dashboard for a Sway/Wayland kiosk. Vesper brings a
clock, Spotify, calendar, weather, synced lyrics, focus and sleep timers,
meeting awareness, guest mode, Wi-Fi onboarding and local system health into
one wall-panel interface.

The interface is designed for a touchpad or touchscreen kiosk rather than a
desktop mouse. It uses large UI targets, gesture-driven navigation and a
full-screen Chromium app window.

## Highlights

- Three-zone analog clock with optional smooth, ticking or hidden second hand
- Spotify playback, playlists, devices, queue, volume and synced lyrics
- Album-colour ambience across the whole display
- Calendar month/agenda views with automatic meeting mode
- Weather, hourly forecast, rain chance, sunrise/sunset and air quality
- Focus timer, sleep timer with volume fade and optional wake routine
- Morning brief with local fun fact of the day
- Optional full-width top-edge day ribbon
- Guest mode with animated background and locally generated Wi-Fi QR
- TV-style German QWERTZ Wi-Fi keyboard:
  swipe to highlight, tap to select
- Hidden system-health panel and safe Chromium restart
- Main and lyric progress bars rendered with requestAnimationFrame and
  GPU-friendly scaleX transforms
- Local fast-path audio controls through a small PipeWire helper

## Architecture

```
┌───────────────────────────────┐
│ Chromium kiosk                │
│ http://127.0.0.1:8080         │
└──────────┬────────────────────┘
           │ HTTP
           ▼
┌───────────────────────────────┐     ┌────────────────────────────┐
│ dashboard/server.py :8080     │────▶│ Spotify Web API            │
│                               │────▶│ LRCLIB                     │
│                               │────▶│ Open-Meteo                 │
│                               │────▶│ Calendar ICS sources       │
└──────────┬────────────────────┘     └────────────────────────────┘
           │
           │ localhost only
           ▼
┌───────────────────────────────┐
│ local system tools:           │
│ wpa_cli, brightnessctl,       │
│ systemctl, /proc, /sys, ps    │
└───────────────────────────────┘

┌───────────────────────────────┐
│ trackpad.py :8099             │
│ evdev gestures ── SSE ────────┼──▶ Chromium gesture layer
└───────────────────────────────┘

┌───────────────────────────────┐
│ audio_server.py :8081         │
│ PipeWire/PulseAudio sinks     │◀──▶ Chromium
└───────────────────────────────┘
```

A more detailed plain-text architecture and component reference is in
[`docs/ARCHITECTURE.txt`](docs/ARCHITECTURE.txt).

## Repository layout

```text
dashboard/
  index.html            UI, CSS, client-side logic, bundled QR encoder
  server.py             main HTTP backend
  audio_server.py       local PipeWire/PulseAudio helper
  auto_output.py        prefers 3.5 mm jack when connected
  trackpad.py           raw evdev gesture daemon
  spotify_login.py      local Spotify OAuth PKCE login helper
  soloist_update.sh     optional Spotify Connect helper updater
  config.example.json   Spotify client ID template
config/
  calendar.urls.example
  soloist.env.example
deploy/systemd/         systemd unit examples
deploy/sway/config      example Sway config
docs/ARCHITECTURE.txt   detailed component and data-flow reference
```

## Requirements

Tested on Debian 13 with:

- Sway/Wayland
- Chromium
- Python 3
- PipeWire + WirePlumber
- `brightnessctl`
- `wpa_supplicant` / `wpa_cli`
- Optional: `soloist` Spotify Connect device

Python dependencies:

```bash
python3 -m pip install -r requirements.txt
```

## Quick start

1. Clone the repository on the kiosk:

   ```bash
   git clone https://github.com/noahengelking/vesper-kiosk.git
   cd vesper-kiosk
   ```

2. Install Python dependencies:

   ```bash
   python3 -m pip install -r requirements.txt
   ```

3. Create your private configuration:

   ```bash
   cp dashboard/config.example.json dashboard/config.json
   ```

   Edit `dashboard/config.json` and set your Spotify application client ID.
   Do not commit this file.

4. Authenticate Spotify:

   ```bash
   python3 dashboard/spotify_login.py
   ```

   On a headless kiosk, run an SSH tunnel from your Mac first:

   ```bash
   ssh -L 8888:127.0.0.1:8888 <kiosk-user>@<kiosk-ip>
   ```

   Then run `spotify_login.py` on the kiosk and open the URL it prints.
   Tokens are stored at `~/.config/desk-dashboard/spotify.json`.

5. Configure calendar sources:

   ```bash
   mkdir -p ~/.config/desk-dashboard
   cp config/calendar.urls.example ~/.config/desk-dashboard/calendar.urls
   ```

   Add one ICS URL per line.

6. Optional: configure the Spotify Connect helper:

   ```bash
   cp config/soloist.env.example ~/.config/desk-dashboard/soloist.env
   chmod 600 ~/.config/desk-dashboard/soloist.env
   ```

   Fill in the API key required by your Soloist installation.

7. Install the system services. Edit the placeholders in
   `deploy/systemd/desk-dashboard.service` first, replacing
   `<kiosk-user>` with the kiosk account name:

   ```bash
   sudo cp deploy/systemd/desk-dashboard.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now desk-dashboard.service
   ```

8. Install the user services:

   ```bash
   mkdir -p ~/.config/systemd/user
   cp deploy/systemd/desk-audio.service \
      deploy/systemd/auto-output.service \
      deploy/systemd/vesper-kiosk.service \
      deploy/systemd/soloist.service \
      deploy/systemd/soloist-update.service \
      deploy/systemd/soloist-update.timer \
      ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now desk-audio.service auto-output.service
   systemctl --user enable --now vesper-kiosk.service
   ```

   The Soloist services are optional. Enable them only if `soloist` is
   installed and configured.

9. Merge `deploy/sway/config` into your Sway setup:

   ```bash
   mkdir -p ~/.config/sway
   cp deploy/sway/config ~/.config/sway/config
   ```

   Review the keyboard layout and maintenance keybindings first. The example
   starts the trackpad daemon and the Chromium kiosk service.

10. Open the dashboard locally:

    ```bash
    curl -I http://127.0.0.1:8080/
    ```

## Configuration and secrets

The following files are intentionally excluded from Git and must be supplied
locally:

| File | Purpose |
| --- | --- |
| `dashboard/config.json` | Spotify client ID |
| `~/.config/desk-dashboard/spotify.json` | Spotify OAuth tokens |
| `~/.config/desk-dashboard/calendar.urls` | Private calendar URLs |
| `~/.config/desk-dashboard/soloist.env` | Soloist API key |
| `/etc/wpa_supplicant/*.conf` | Wi-Fi credentials |

Never commit real credentials, OAuth tokens, calendar URLs, Wi-Fi passwords,
private IP addresses or personal device configuration.

The guest Wi-Fi QR feature reads the current SSID's PSK from the local
`wpa_supplicant` configuration and serves the resulting QR data only through
the localhost dashboard. Review [`SECURITY.md`](SECURITY.md) before deploying
it on a shared network.

## Gestures

The exact gesture map depends on the touchpad daemon. The default assumptions
in `trackpad.py` are:

- Three-finger swipe: move dashboard tile focus
- Four-finger swipe down: open Settings
- Four-finger swipe up: close overlay / exit guest mode
- Two-finger tap: play/pause (also works in Lyrics)
- Top edge: brightness; in Lyrics, seek
- Right edge: Spotify volume
- Left edge: local device volume
- Corners: previous/next track
- One-finger swipes: list navigation, calendar movement and lyric scrolling

The `trackpad.py` device name may need to be changed for your touchpad. Set
`TP_NAME` to match the touchpad in `/proc/bus/input/devices`.

## License

MIT. See [`LICENSE`](LICENSE).

The bundled QR encoder is qrcode-generator 1.4.4 by Kazuhiko Arase, also MIT
licensed. See [`NOTICE.md`](NOTICE.md).

## AI disclaimer

This project was built with substantial AI assistance. Review the code,
systemd units, network exposure, credentials handling and security assumptions
before using it on your own hardware. See [`AI_DISCLAIMER.md`](AI_DISCLAIMER.md).
