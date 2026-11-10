#!/usr/bin/env python3
"""Make the 3.5mm jack the default output while something is plugged in,
and the built-in speakers otherwise. Acts only when the plug state changes."""
import os, select, subprocess, time

HEAD, SPK = 'HiFi__Headphones__sink', 'HiFi__Speaker__sink'


def pactl(*args):
    r = subprocess.run(['pactl', *args], capture_output=True, text=True, timeout=5)
    return r.stdout


def read():
    """Returns (jack plugged in?, headphones sink name, speaker sink name)."""
    plugged, head, spk, cur = None, None, None, None
    for line in pactl('list', 'sinks').splitlines():
        s = line.strip()
        if s.startswith('Name: '):
            cur = s[6:]
            if cur.endswith(HEAD):
                head = cur
            elif cur.endswith(SPK):
                spk = cur
        elif cur and cur.endswith(HEAD) and s.startswith('[Out] Headphones:'):
            plugged = ', available)' in s and 'not available' not in s
    return plugged, head, spk


last = None


def check():
    global last
    plugged, head, spk = read()
    if plugged is None or not head or not spk or plugged == last:
        return
    last = plugged
    target = head if plugged else spk
    pactl('set-default-sink', target)
    print('jack %s -> %s' % ('plugged' if plugged else 'unplugged', target), flush=True)


def main():
    check()
    p = subprocess.Popen(['pactl', 'subscribe'], stdout=subprocess.PIPE)
    fd = p.stdout.fileno()
    dirty = False
    while True:
        # after an event, wait for it to settle; otherwise re-check every 3 seconds
        ready, _, _ = select.select([fd], [], [], 0.4 if dirty else 3.0)
        if ready:
            if not os.read(fd, 4096):
                raise SystemExit('pactl subscribe ended')
            dirty = True
            continue
        dirty = False
        check()


if __name__ == '__main__':
    main()
