#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Library/Application Support/Vesper"
AGENT="$APP_DIR/vesper-battery-agent.sh"
PLIST="$HOME/Library/LaunchAgents/com.vesper.battery.plist"
mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"
install -m 0755 "$SCRIPT_DIR/vesper-battery-agent.sh" "$AGENT"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.vesper.battery</string>
  <key>ProgramArguments</key>
  <array><string>${AGENT}</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>/tmp/vesper-battery.log</string>
  <key>StandardErrorPath</key><string>/tmp/vesper-battery.err</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.vesper.battery"
echo "Installed and started $PLIST"
