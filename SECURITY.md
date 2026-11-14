# Security notes

Vesper Kiosk is designed for a trusted local device and a trusted local
network. It is not a hardened multi-user web application.

## Localhost-only services

The dashboard, audio helper and gesture service bind to `127.0.0.1` by
default. Do not expose ports 8080, 8081 or 8099 to the LAN or the internet.

The dashboard includes controls that can:

- change Spotify playback
- control local audio
- connect the device to Wi-Fi
- change brightness
- request a system shutdown or Chromium restart
- read system health information

## Guest Wi-Fi QR

`/api/wifi-credentials` reads the current SSID's saved PSK from the local
`wpa_supplicant` configuration and serves it to the local dashboard for the
guest QR code. Treat the kiosk as holding a copy of that Wi-Fi password.

If that behavior is unacceptable for your deployment, disable the guest QR
feature or change the endpoint in `dashboard/server.py`.

## Credentials that must never be committed

- Spotify client secrets, access tokens or refresh tokens
- Soloist API keys
- private calendar URLs
- Wi-Fi SSIDs/passwords if you consider them sensitive
- SSH private keys
- personal IP addresses, hostnames or usernames
- local device backups

Use environment files with restrictive permissions and keep them outside the
repository.

## Native macOS app

The `macos/` app is intentionally different from the kiosk: it runs no HTTP
server and does not read Wi-Fi credentials. It uses:

- Apple Events / AppleScript to read and control the local Spotify app
- EventKit for calendar events, only after you grant access
- Open-Meteo for weather at the coordinates configured in Settings
- LRCLIB for lyrics, using the current track title/artist/duration

Vesper does not store Spotify OAuth tokens on macOS. The app requires no
Accessibility or Input Monitoring permission for its own Magic Trackpad gesture
handling. Automation and Calendar permissions can be revoked at any time in
System Settings → Privacy & Security.

The package is ad-hoc signed for local use. If you redistribute a build, sign and
notarize it with your own Apple Developer identity and review the permissions
before publishing.
