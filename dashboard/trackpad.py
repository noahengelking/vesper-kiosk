#!/usr/bin/env python3
"""Reads the touchpad straight from evdev and streams edge slides, corner
taps, taps, two-finger taps, one-finger slides and 3/4-finger swipes to the
dashboard over server-sent events."""
import fcntl, json, os, queue, re, struct, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = os.environ.get('TP_NAME', 'TM3510')
PORT = 8099
EDGE = 0.08      # width of the edge bands, as a fraction of the pad
CORNER = 0.20    # top-left / top-right corner squares
SWIPE = 0.15     # multi-finger travel needed to count as a swipe
SLIDE = 0.12     # one-finger sideways travel needed to count as a slide
TAP_S = 0.30     # longest touch that still counts as a tap
TAP_MOVE = 0.04  # furthest a tap may drift

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_LEFT = 0x110
SLOT, TRACK, POS_X, POS_Y = 0x2f, 0x39, 0x35, 0x36
EDGES, CORNERS = ('top', 'left', 'right'), ('tl', 'tr')

clients, lock = [], threading.Lock()


def send(obj):
    data = json.dumps(obj, separators=(',', ':'))
    with lock:
        for q in clients:
            q.put(data)


class Events(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path != '/events':
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        q = queue.Queue()
        with lock:
            clients.append(q)
        try:
            while True:
                try:
                    self.wfile.write(('data: %s\n\n' % q.get(timeout=15)).encode())
                except queue.Empty:
                    self.wfile.write(b': ping\n\n')
                self.wfile.flush()
        except OSError:
            pass
        finally:
            with lock:
                clients.remove(q)


def find_device():
    for block in open('/proc/bus/input/devices').read().split('\n\n'):
        if NAME in block:
            m = re.search(r'Handlers=.*?\b(event\d+)', block)
            if m:
                return '/dev/input/' + m.group(1)
    sys.exit('touchpad matching "%s" not found' % NAME)


def abs_range(fd, code):
    buf = bytearray(24)  # struct input_absinfo: six s32
    fcntl.ioctl(fd, (2 << 30) | (24 << 16) | (ord('E') << 8) | (0x40 + code), buf)
    _, lo, hi, _, _, _ = struct.unpack('6i', buf)
    return lo, hi


class Pad:
    def __init__(self, fd):
        self.x0, x1 = abs_range(fd, POS_X)
        self.y0, y1 = abs_range(fd, POS_Y)
        self.w, self.h = x1 - self.x0, y1 - self.y0
        self.slots, self.cur = {}, 0
        self.touch = None  # the live single-finger touch
        self.dead = False  # ignore this touch until every finger lifts
        self.sw = None     # multi-finger swipe: [start x, start y, fired, fingers]
        self.tw = None     # two-finger tap candidate

    def norm(self, s):
        return (s['x'] - self.x0) / self.w, (s['y'] - self.y0) / self.h

    def event(self, t, c, v):
        if t == EV_ABS:
            if c == SLOT:
                self.cur = v
            elif c == TRACK:
                if v == -1:
                    self.slots.pop(self.cur, None)
                else:
                    self.slots[self.cur] = {'x': None, 'y': None, 'new': True}
            elif c in (POS_X, POS_Y) and self.cur in self.slots:
                self.slots[self.cur]['x' if c == POS_X else 'y'] = v
        elif t == EV_KEY and c == BTN_LEFT and v == 1:
            self.press()
        elif t == EV_SYN and c == 0:
            self.frame()

    def frame(self):
        f = [s for s in self.slots.values() if s['x'] is not None and s['y'] is not None]
        n = len(f)
        if n == 0:
            self.lift()
            self.finish_tap2()
            self.touch, self.dead, self.sw, self.tw = None, False, None, None
            return
        if n > 1:
            if self.touch:
                self.cancel()
            self.dead = True
            self.track_tap2(f)
        elif self.touch:
            self.track(f[0])
        elif not self.dead and f[0]['new']:
            self.begin(f[0])
        if n >= 3:
            self.swipe(f)
        else:
            self.sw = None
        for s in f:
            s['new'] = False

    def begin(self, s):
        nx, ny = self.norm(s)
        if ny < CORNER and nx < CORNER:
            kind = 'tl'
        elif ny < CORNER and nx > 1 - CORNER:
            kind = 'tr'
        elif ny < EDGE:
            kind = 'top'
        elif nx < EDGE:
            kind = 'left'
        elif nx > 1 - EDGE:
            kind = 'right'
        else:
            kind = 'free'
        self.touch = {'kind': kind, 't0': time.monotonic(), 'p0': (nx, ny),
                      'last': nx if kind == 'top' else ny, 'moved': 0.0, 'used': False,
                      'pos': (nx, ny)}
        if kind in CORNERS:
            send({'t': 'corner', 'p': 'down', 'c': kind})
        elif kind in EDGES:
            send({'t': 'edge', 'z': kind, 'p': 'start'})

    def track(self, s):
        tc = self.touch
        nx, ny = self.norm(s)
        dx, dy = nx - tc['p0'][0], ny - tc['p0'][1]
        tc['moved'] = max(tc['moved'], abs(dx), abs(dy))
        tc['pos'] = (nx, ny)
        k = tc['kind']
        if k in EDGES:
            pos = nx if k == 'top' else ny
            d = pos - tc['last']
            if d:
                tc['last'] = pos
                send({'t': 'edge', 'z': k, 'p': 'move', 'd': round(d if k == 'top' else -d, 4)})
        elif k == 'free' and not tc['used'] and abs(dy) > SLIDE and abs(dy) > 2 * abs(dx):
            tc['used'] = True
            send({'t': 'slide', 'dir': 'down' if dy > 0 else 'up'})
        elif k == 'free' and not tc['used'] and abs(dx) > SLIDE and abs(dx) > 2 * abs(dy):
            tc['used'] = True
            send({'t': 'slide', 'dir': 'right' if dx > 0 else 'left'})

    def tap_msg(self, tc, at='p0'):
        x, y = tc['p0'] if at == 'p0' else tc['pos']
        return {'t': 'tap', 'k': tc['kind'], 'x': round(x, 3), 'y': round(y, 3)}

    def press(self):
        tc = self.touch
        if not tc or tc['used'] or tc['moved'] > 0.1:
            return
        tc['used'] = True
        if tc['kind'] in CORNERS:
            send({'t': 'corner', 'p': 'press', 'c': tc['kind']})
        send(self.tap_msg(tc, 'pos'))
    def lift(self):
        tc = self.touch
        if not tc:
            return
        k = tc['kind']
        tap = (not tc['used'] and tc['moved'] < TAP_MOVE
               and time.monotonic() - tc['t0'] < TAP_S)
        if k in EDGES:
            send({'t': 'edge', 'z': k, 'p': 'end'})
        elif k in CORNERS:
            send({'t': 'corner', 'p': 'up', 'c': k, 'tap': tap})
        if tap:
            send(self.tap_msg(tc))
    def cancel(self):
        k = self.touch['kind']
        if k in EDGES:
            send({'t': 'edge', 'z': k, 'p': 'end'})
        elif k in CORNERS:
            send({'t': 'corner', 'p': 'up', 'c': k, 'tap': False})
        self.touch = None

    def track_tap2(self, f):
        n = len(f)
        pts = [self.norm(s) for s in f]
        cx = sum(p[0] for p in pts) / n
        cy = sum(p[1] for p in pts) / n
        if self.tw is None:
            self.tw = {'t0': time.monotonic(), 'p0': (cx, cy), 'moved': 0.0, 'ok': True}
        tw = self.tw
        tw['moved'] = max(tw['moved'], abs(cx - tw['p0'][0]), abs(cy - tw['p0'][1]))
        if n > 2:
            tw['ok'] = False

    def finish_tap2(self):
        tw = self.tw
        if tw and tw['ok'] and tw['moved'] < TAP_MOVE and time.monotonic() - tw['t0'] < TAP_S:
            send({'t': 'tap2'})

    def swipe(self, f):
        n = len(f)
        pts = [self.norm(s) for s in f]
        cx = sum(p[0] for p in pts) / n
        cy = sum(p[1] for p in pts) / n
        if self.sw is None or self.sw[3] != n:
            self.sw = [cx, cy, self.sw[2] if self.sw else False, n]
            return
        if self.sw[2]:
            return
        dx, dy = cx - self.sw[0], cy - self.sw[1]
        if max(abs(dx), abs(dy)) < SWIPE:
            return
        self.sw[2] = True
        if abs(dx) >= abs(dy):
            d = 'right' if dx > 0 else 'left'
        else:
            d = 'down' if dy > 0 else 'up'
        send({'t': 'swipe' if n == 3 else 'swipe4', 'dir': d})


def main():
    path = find_device()
    fd = os.open(path, os.O_RDONLY)
    pad = Pad(fd)
    srv = ThreadingHTTPServer(('127.0.0.1', PORT), Events)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print('reading %s, serving http://127.0.0.1:%d/events' % (path, PORT), flush=True)
    ev = struct.Struct('llHHi')
    while True:
        data = os.read(fd, ev.size * 64)
        for off in range(0, len(data) - ev.size + 1, ev.size):
            _, _, t, c, v = ev.unpack_from(data, off)
            pad.event(t, c, v)


if __name__ == '__main__':
    main()
