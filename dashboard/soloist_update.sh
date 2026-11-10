#!/usr/bin/env bash
# Keep the Soloist build fresh: Spotify builds expire 90 days after their build date.
set -eu
URL=https://soloist-builds.spotifycdn.com/soloist_release_x86_64.tar.gz
BIN="$HOME/.local/bin/soloist"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl --fail --location --silent --show-error -o "$tmp/soloist.tar.gz" "$URL"
mkdir "$tmp/x"
tar -xzf "$tmp/soloist.tar.gz" -C "$tmp/x"
test -x "$tmp/x/soloist"
new=$("$tmp/x/soloist" --version 2>&1)
old=$("$BIN" --version 2>&1 || true)
echo "installed: $old"
echo "published: $new"
if [ "$new" = "$old" ]; then echo "already up to date"; exit 0; fi

[ -x "$BIN" ] && cp -f "$BIN" "$BIN.prev"
install -m 755 "$tmp/x/soloist" "$BIN.new"
mv -f "$BIN.new" "$BIN"
systemctl --user restart soloist
sleep 8
if systemctl --user is-active --quiet soloist; then
  echo "updated and running"
else
  echo "new build did not start; restoring previous"
  [ -x "$BIN.prev" ] && cp -f "$BIN.prev" "$BIN" && systemctl --user restart soloist
  exit 1
fi
