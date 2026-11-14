#!/usr/bin/env python3
"""Generate the Vesper app icon without external design assets."""
from pathlib import Path
import math
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist" / "AppIcon.iconset"
OUT.mkdir(parents=True, exist_ok=True)

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# macOS-style rounded tile
d.rounded_rectangle((54, 54, 970, 970), radius=210, fill=(11, 11, 12, 255))
d.rounded_rectangle((56, 56, 968, 968), radius=208, outline=(45, 45, 49, 255), width=4)

# warm ambient glow
for radius, alpha in [(360, 15), (280, 18), (200, 22)]:
    d.ellipse((512-radius, 512-radius, 512+radius, 512+radius), fill=(242, 184, 75, alpha))

# outer clock ring
cx = cy = 512
ring_r = 292
for i in range(60):
    angle = math.radians(i * 6 - 90)
    major = i % 5 == 0
    inner = ring_r - (54 if major else 26)
    outer = ring_r
    width = 14 if major else 5
    d.line(
        (cx + inner * math.cos(angle), cy + inner * math.sin(angle),
         cx + outer * math.cos(angle), cy + outer * math.sin(angle)),
        fill=(232, 230, 225, 222 if major else 110),
        width=width,
    )

# hands at ~10:10
def hand(angle_deg, length, tail, width, color):
    a = math.radians(angle_deg - 90)
    d.line(
        (cx - tail * math.cos(a), cy - tail * math.sin(a),
         cx + length * math.cos(a), cy + length * math.sin(a)),
        fill=color, width=width, joint="curve",
    )

hand(305, 160, 34, 34, (232, 230, 225, 255))
hand(60, 224, 42, 25, (232, 230, 225, 255))
hand(150, 240, 52, 13, (242, 184, 75, 255))

d.ellipse((cx-34, cy-34, cx+34, cy+34), fill=(242, 184, 75, 255))

sizes = [16, 32, 128, 256, 512]
for size in sizes:
    for scale in (1, 2):
        actual = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        img.resize((actual, actual), Image.Resampling.LANCZOS).save(OUT / name)

print(OUT)
