#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"
DEST="/Applications/Vesper.app"

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi
ditto "$ROOT/dist/Vesper.app" "$DEST"
xattr -cr "$DEST"
codesign --force --deep --sign - "$DEST" >/dev/null
open "$DEST"
echo "Installed $DEST"
echo "To launch at login, add Vesper under System Settings → General → Login Items."
