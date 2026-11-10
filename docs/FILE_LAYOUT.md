# File layout

This document explains what every important file does, where it lives, and
which files are generated locally rather than committed to Git.

## Repository tree

```text
vesper-kiosk/
├── README.md                     Project overview, features and quick start
├── LICENSE                       MIT license
├── NOTICE.md                     Third-party notices
├── SECURITY.md                   Localhost-only service and secrets guidance
├── AI_DISCLAIMER.md              AI-assistance disclaimer
├── requirements.txt              Python dependencies
├── .gitignore                    Credentials, caches and local backups
│
├── dashboard/
│   ├── index.html                Complete kiosk UI: HTML, CSS, JavaScript,
│   │                             gesture handling and bundled local QR encoder
│   ├── server.py                 Main Python HTTP API, static-file server,
│   │                             Spotify integration, calendar engine,
│   │                             lyrics lookup, Wi-Fi controls and health metrics
│   ├── audio_server.py           Local PipeWire/PulseAudio sink and volume helper
│   ├── auto_output.py            Selects the 3.5 mm output when a jack is plugged in
│   ├── trackpad.py               Raw evdev touchpad/gesture daemon on port 8099
│   ├── spotify_login.py          One-time Spotify OAuth PKCE login helper
│   ├── soloist_update.sh         Optional updater for a Soloist Spotify Connect binary
│   └── config.example.json       Template for the Spotify Client ID
│
├── config/
│   ├── calendar.urls.example     Template for private calendar ICS URLs
│   └── soloist.env.example       Template for the optional Soloist API key
│
├── deploy/
│   ├── systemd/
│   │   ├── desk-dashboard.service System service example for the main server
│   │   ├── vesper-kiosk.service    User service example for Chromium kiosk mode
│   │   ├── desk-audio.service      User service for the local audio helper
│   │   ├── auto-output.service     User service for the jack preference helper
│   │   ├── soloist.service         Optional Spotify Connect device service
│   │   ├── soloist-update.service  Optional Soloist updater service
│   │   └── soloist-update.timer    Weekly timer for the optional updater
│   └── sway/
│       └── config                 Example Sway session and trackpad launch config
│
├── docs/
│   ├── ARCHITECTURE.txt           Detailed component and data-flow reference
│   ├── FILE_LAYOUT.md             This file
│   └── SPOTIFY_SETUP.md           Spotify developer app and OAuth walkthrough
│
└── .github/
    └── workflows/
        └── ci.yml                 Python syntax check workflow
```

## Main source files

### `dashboard/index.html`

The entire frontend is one HTML document. It contains:

- the 2 x 2 dashboard layout
- clock, Spotify, calendar and weather tiles
- full-screen overlays for lyrics, focus, guest mode, health and morning brief
- settings pages
- the TV-style German QWERTZ Wi-Fi keyboard
- the main progress renderer using `requestAnimationFrame`
- the gesture integration code that consumes the trackpad SSE stream
- a locally bundled qrcode-generator library, so no external QR service is used

The file loads its data from the local backend at `127.0.0.1:8080`, the
gesture stream at `127.0.0.1:8099`, and the audio helper at `127.0.0.1:8081`.

### `dashboard/server.py`

The main backend process. It:

- serves `index.html`
- provides the `/api/...` endpoints
- refreshes Spotify access tokens
- wraps Spotify Web API calls with single-flight request coalescing and short caching
- fetches lyrics from LRCLIB
- refreshes and expands calendar events
- performs Wi-Fi scan/join operations through `wpa_cli`
- reads the current Wi-Fi PSK from `wpa_supplicant` for the guest QR
- handles brightness, battery, SSH and network information
- collects local system health metrics
- restarts the user-level Chromium kiosk service

### `dashboard/trackpad.py`

Reads the raw touchpad event device from `/dev/input/event*` and classifies:

- taps
- two-finger taps
- one-finger slides
- three- and four-finger swipes
- edge drags
- corner actions

It streams JSON events over Server-Sent Events on port 8099. The frontend's
gesture layer turns those events into navigation and control actions.

### `dashboard/audio_server.py`

A small local HTTP server on `127.0.0.1:8081`. It lists PipeWire/PulseAudio
sinks, changes the default output and adjusts volume for the on-screen audio
controls.

### `dashboard/auto_output.py`

Watches the audio jacks and prefers the 3.5 mm output when it is connected.

### `dashboard/spotify_login.py`

Runs the one-time Spotify Authorization Code with PKCE flow. It opens a local
callback listener on `127.0.0.1:8888` and writes the resulting OAuth tokens to
`~/.config/desk-dashboard/spotify.json`.

### `dashboard/soloist_update.sh`

Optional helper for users who install Soloist as a Spotify Connect device. It
downloads the current Soloist release, validates it, installs it, and restarts
the user service.

## Runtime files outside the repository

These files are part of a running installation but are not part of this repo:

```text
/etc/systemd/system/desk-dashboard.service
    Installed copy of the main dashboard system service.

~/.config/systemd/user/vesper-kiosk.service
    Installed Chromium kiosk user service.

~/.config/systemd/user/desk-audio.service
~/.config/systemd/user/auto-output.service
    Installed user services for local audio helpers.

~/.config/systemd/user/soloist.service
~/.config/systemd/user/soloist-update.service
~/.config/systemd/user/soloist-update.timer
    Installed optional Spotify Connect helper services.

~/.config/sway/config
    Installed Sway session config. It starts the kiosk service and trackpad loop.

~/.config/desk-dashboard/spotify.json
    Private Spotify OAuth access and refresh tokens.

~/.config/desk-dashboard/calendar.urls
    Private calendar ICS URLs.

~/.config/desk-dashboard/soloist.env
    Private optional Soloist API key.

/etc/wpa_supplicant/*.conf
    System Wi-Fi configuration. The guest QR can read the current SSID's PSK.

~/.config/chromium/
    Chromium profile, local storage, cache and kiosk session state.

~/.local/bin/soloist
    Optional Spotify Connect binary.
```

## Generated and ignored files

The repository ignores local-only data such as:

- `dashboard/config.json` (your real Spotify Client ID)
- `spotify.json` (OAuth tokens)
- `calendar.urls`
- `soloist.env`
- Python `__pycache__` and `.pyc` files
- screenshots, logs, tarballs and local backups
- `.DS_Store` and other platform junk

## How files interact

```text
Chromium loads dashboard/index.html
        │
        ├── HTTP :8080 ──> dashboard/server.py
        │                       ├── Spotify Web API
        │                       ├── LRCLIB lyrics API
        │                       ├── Open-Meteo weather API
        │                       ├── calendar ICS sources
        │                       ├── wpa_cli / wpa_supplicant
        │                       └── system tools + /proc + /sys
        │
        ├── SSE :8099 ───> dashboard/trackpad.py
        │                       └── raw touchpad evdev events
        │
        └── HTTP :8081 ──> dashboard/audio_server.py
                                └── PipeWire/PulseAudio
```

## Where to make changes

- Dashboard behavior and UI: `dashboard/index.html`
- Main API and backend integrations: `dashboard/server.py`
- Gesture recognition: `dashboard/trackpad.py`
- Audio behavior: `dashboard/audio_server.py` and `dashboard/auto_output.py`
- Spotify login: `dashboard/spotify_login.py`
- Service definitions: `deploy/systemd/`
- Kiosk session setup: `deploy/sway/config`
- Setup instructions: `README.md`, `docs/SPOTIFY_SETUP.md`
- System architecture: `docs/ARCHITECTURE.txt`
