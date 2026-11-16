#!/bin/bash
# Post the MacBook battery percentage to the Vesper NAS dashboard.
set -u
BATT=$(/usr/bin/pmset -g batt 2>/dev/null) || exit 0
PCT=$(printf '%s\n' "$BATT" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
[ -n "${PCT:-}" ] || exit 0
LINE=$(printf '%s\n' "$BATT" | sed -n '2p')
STATE=$(printf '%s\n' "$LINE" | awk -F';' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
CHARGING=false
case "$STATE" in
    *"not charging"*|*discharging*|*"AC attached"*) CHARGING=false ;;
    *charging*|*"finishing charge"*) CHARGING=true ;;
esac
for HOST in vesper.local 192.168.0.78; do
    if /usr/bin/curl -fsS --max-time 3 \
        -X POST "http://${HOST}:8088/api/client/battery" \
        -H 'Content-Type: application/json' \
        -d "{\"percent\":${PCT},\"charging\":${CHARGING}}" >/dev/null 2>&1; then
        exit 0
    fi
done
exit 0
