# Vesper for macOS

A native macOS menu-bar port of Vesper. Click the menu-bar item to take over one
display with the dashboard; press `Esc` or use the close button to get your Mac
back. No web server, Python process, browser kiosk, or external gesture daemon is
required.

The Linux kiosk remains in the repository root. This folder is the native Swift
implementation for macOS.

## Highlights

- Native Swift/AppKit + SwiftUI menu-bar app with no Dock icon
- Full-display takeover on the screen under the pointer, or a remembered display
- Smooth analog clocks with three configurable time zones
- Spotify now playing, artwork, album-colour ambience, native controls, seeking,
  shuffle/repeat and synced LRCLIB lyrics
- EventKit calendar month/agenda views with permission-only access
- Open-Meteo current, hourly and daily forecasts plus air quality
- Focus sessions, sleep-timer volume fade, morning brief and optional day ribbon
- Automatic day/night palette; manual dark/light override in Settings
- Floating bottom-centre Spotify volume pill
- Magic Trackpad gestures handled as native `NSEvent` touches

## Magic Trackpad controls

| Gesture | Action |
| --- | --- |
| Two-finger tap | Play / pause Spotify |
| Two-finger swipe left / right | Move between dashboard and lyrics |
| Two-finger swipe up / down at the right edge | Adjust Spotify volume; the bottom pill appears for 2.2 seconds |
| Three-finger swipe left / right | Move between views |
| Three-finger swipe up / down | Start focus / close Vesper |
| Mouse, keyboard, taps | Normal SwiftUI controls |

Keyboard shortcuts inside the takeover view: `Esc` closes, `Space` toggles
playback, `←`/`→` switch views, `F` starts/ends focus, `L` opens lyrics, and
`-`/`=` change volume.

Vesper's trackpad handling does not need Accessibility or Input Monitoring
permission: touches are read from the app's own native event stream. The
standard macOS "swipe between pages" event is also used as a fallback.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 16 / Swift 6 toolchain, or compatible Command Line Tools with the macOS
  SDK and Swift compiler

## Build and run

```bash
cd macos
./scripts/build-app.sh
open dist/Vesper.app
```

The build script produces an ad-hoc-signed `dist/Vesper.app`. To keep it in
Applications:

```bash
./scripts/install.sh
```

This copies the app to `/Applications/Vesper.app` and launches it. Then add
Vesper under **System Settings → General → Login Items** if you want it to be
available after every login.

The app is a menu-bar accessory (`LSUIElement`), so it intentionally does not
show a Dock icon. Click the Vesper item in the menu bar to open the dashboard.

For development, `swift build` also works. The debug app supports
`--show-dashboard`, `--mode dashboard|lyrics|focus|brief`, and
`--screenshot <path>` for local UI verification.

## Permissions and privacy

- **Spotify automation**: macOS asks for Automation permission the first time
  Vesper reads or controls Spotify. Approve it under System Settings → Privacy &
  Security → Automation. Spotify must be running on the same Mac.
- **Calendar**: optional. Vesper only asks when you press **Connect** in the
  calendar tile or Settings, and reads events through EventKit locally.
- **Weather and lyrics**: requests go to Open-Meteo and LRCLIB. No account or API
  key is needed. Location is a pair of coordinates you configure in Settings;
  there is no background location tracking.
- Vesper stores preferences in `UserDefaults`. It does not store Spotify tokens,
  calendar URLs, Wi-Fi credentials, or device backups. The public repository
  contains only example/default configuration.

## Architecture

```text
Vesper.app (Swift)
├── AppDelegate / NSStatusItem       menu bar and screen selection
├── TakeoverWindow                   borderless per-screen kiosk window
├── DashboardRootView                SwiftUI dashboard + overlays
├── NSEvent touch router             Magic Trackpad gestures
├── SpotifyService                   AppleScript bridge to Spotify
├── CalendarService                  EventKit agenda
├── WeatherService                   Open-Meteo
├── LyricsService                    LRCLIB + LRC parser
└── ImageColors                      album ambience via Core Image
```

Efficiency notes:

- Spotify is polled only while the takeover view is open, every 2 seconds;
  playback position animates locally at 30fps between polls.
- Weather refreshes every 15 minutes. Calendar refreshes every 3 minutes only
  after access has been granted.
- Artwork colour extraction runs once per track, not per frame.
- The UI is rendered natively with SwiftUI/Core Animation; no embedded browser or
  local HTTP server is used.

## Why Swift rather than Rust?

The expensive integration points on macOS are AppKit's event/window APIs,
EventKit and Apple Events. A Rust rewrite would still need Objective-C/AppKit
bridging for those, adding complexity without a meaningful efficiency gain for
this workload. The native Swift app keeps the hot input/render path in the OS
framework and avoids a second runtime.

## Repository layout

```text
macos/
  Package.swift
  Sources/VesperMac/
    AppDelegate.swift
    Models/
    Services/
    Support/
    Views/
  Resources/Info.plist
  scripts/build-app.sh
  scripts/install.sh
  scripts/make-icon.py
```

## Troubleshooting

- **Spotify shows idle**: open Spotify and start a track. Check Automation
  permission in System Settings.
- **Calendar is empty**: press Connect in Vesper and allow Calendars access.
- **Trackpad edge volume does not react**: try a two-finger vertical swipe that
  starts within the right quarter of the trackpad. The keyboard `-`/`=` keys and
  the system volume keys also work.
- **App won't open after downloading**: ad-hoc builds may need
  right-click → Open once, or `xattr -cr /Applications/Vesper.app`.

## License

MIT. See [`../LICENSE`](../LICENSE).
