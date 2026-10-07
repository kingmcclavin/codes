#!/usr/bin/env python3
"""Draws the web app icons (PNG) with no dependencies.

A spruce-green tile with a light Reel frame and a play mark, cut short by a
bar: one Reel, then a stop. Usage: scripts/make-web-icons.py
"""
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Web" / "icons"
BG = (0x2E, 0x6A, 0x57)
FG = (0xF8, 0xFA, 0xF6)
SS = 4  # supersampling per axis


def rounded_rect(x, y, x0, y0, x1, y1, r):
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def triangle(x, y, a, b, c):
    def side(p, q, r):
        return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
    d1, d2, d3 = side((x, y), a, b), side((x, y), b, c), side((x, y), c, a)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def shade(u, v, inset, tile_radius):
    """Colour at unit coordinates (0..1). `inset` shrinks the artwork for maskable icons."""
    if tile_radius and not rounded_rect(u, v, 0, 0, 1, 1, tile_radius):
        return None  # transparent corner
    s = 1 - 2 * inset
    x, y = (u - inset) / s, (v - inset) / s
    # Reel frame (outline)
    outer = rounded_rect(x, y, 0.31, 0.17, 0.69, 0.83, 0.07)
    inner = rounded_rect(x, y, 0.355, 0.215, 0.645, 0.785, 0.035)
    if outer and not inner:
        return FG
    # Play mark
    if triangle(x, y, (0.45, 0.38), (0.45, 0.58), (0.58, 0.48)):
        return FG
    # Stop bar under the frame
    if rounded_rect(x, y, 0.38, 0.88, 0.62, 0.92, 0.02):
        return FG
    return BG


def render(size, inset=0.0, tile_radius=0.0):
    rows = []
    for py in range(size):
        row = bytearray([0])
        for px in range(size):
            acc = [0, 0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    c = shade((px + (sx + 0.5) / SS) / size, (py + (sy + 0.5) / SS) / size, inset, tile_radius)
                    if c is not None:
                        acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 255
            n = SS * SS
            a = acc[3] // n
            if a:
                covered = acc[3] // 255
                row += bytes([acc[0] // covered, acc[1] // covered, acc[2] // covered, a])
            else:
                row += bytes([0, 0, 0, 0])
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "icon-192.png").write_bytes(render(192, tile_radius=0.2))
    (OUT / "icon-512.png").write_bytes(render(512, tile_radius=0.2))
    (OUT / "icon-maskable-512.png").write_bytes(render(512, inset=0.1))
    (OUT / "apple-touch-icon.png").write_bytes(render(180))  # iOS rounds the corners itself
    print("Wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
