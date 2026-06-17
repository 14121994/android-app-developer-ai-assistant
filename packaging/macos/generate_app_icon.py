#!/usr/bin/env python3
"""Generate Android Dev Agent macOS iconset PNGs using only the standard library."""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path


ICON_SLOTS = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
]


def clamp(value: float, lower: int = 0, upper: int = 255) -> int:
    return max(lower, min(upper, int(round(value))))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1: tuple[int, int, int, int], c2: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    return tuple(clamp(lerp(c1[i], c2[i], t)) for i in range(4))


def blend(dst: list[int], src: tuple[int, int, int, int]) -> None:
    src_alpha = src[3] / 255.0
    inv = 1.0 - src_alpha
    dst_alpha = dst[3] / 255.0
    out_alpha = src_alpha + dst_alpha * inv
    if out_alpha <= 0:
        dst[:] = [0, 0, 0, 0]
        return
    for i in range(3):
        dst[i] = clamp((src[i] * src_alpha + dst[i] * dst_alpha * inv) / out_alpha)
    dst[3] = clamp(out_alpha * 255)


def rounded_rect_coverage(px: float, py: float, x: float, y: float, w: float, h: float, r: float) -> float:
    cx = min(max(px, x + r), x + w - r)
    cy = min(max(py, y + r), y + h - r)
    distance = math.hypot(px - cx, py - cy)
    return max(0.0, min(1.0, r + 0.5 - distance))


def draw_round_rect(
    pixels: list[list[int]],
    size: int,
    rect: tuple[float, float, float, float],
    radius: float,
    color: tuple[int, int, int, int],
) -> None:
    x, y, w, h = rect
    x0 = max(0, int(math.floor(x - 1)))
    y0 = max(0, int(math.floor(y - 1)))
    x1 = min(size, int(math.ceil(x + w + 1)))
    y1 = min(size, int(math.ceil(y + h + 1)))
    for row in range(y0, y1):
        for col in range(x0, x1):
            coverage = rounded_rect_coverage(col + 0.5, row + 0.5, x, y, w, h, radius)
            if coverage > 0:
                blend(pixels[row * size + col], (*color[:3], clamp(color[3] * coverage)))


def distance_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx = bx - ax
    dy = by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def draw_line(
    pixels: list[list[int]],
    size: int,
    a: tuple[float, float],
    b: tuple[float, float],
    width: float,
    color: tuple[int, int, int, int],
) -> None:
    ax, ay = a
    bx, by = b
    pad = width + 1
    x0 = max(0, int(math.floor(min(ax, bx) - pad)))
    y0 = max(0, int(math.floor(min(ay, by) - pad)))
    x1 = min(size, int(math.ceil(max(ax, bx) + pad)))
    y1 = min(size, int(math.ceil(max(ay, by) + pad)))
    radius = width / 2.0
    for row in range(y0, y1):
        for col in range(x0, x1):
            distance = distance_to_segment(col + 0.5, row + 0.5, ax, ay, bx, by)
            coverage = max(0.0, min(1.0, radius + 0.5 - distance))
            if coverage > 0:
                blend(pixels[row * size + col], (*color[:3], clamp(color[3] * coverage)))


def draw_icon(size: int) -> list[list[int]]:
    pixels = [[0, 0, 0, 0] for _ in range(size * size)]

    outer = size * 0.055
    radius = size * 0.22
    base_rect = (outer, outer, size - outer * 2, size - outer * 2)
    shadow_rect = (outer, outer + size * 0.018, size - outer * 2, size - outer * 2)

    draw_round_rect(pixels, size, shadow_rect, radius, (2, 8, 23, 76))

    for row in range(size):
        t = row / max(1, size - 1)
        color = mix((12, 35, 54, 255), (12, 106, 110, 255), t)
        for col in range(size):
            coverage = rounded_rect_coverage(col + 0.5, row + 0.5, *base_rect, radius)
            if coverage > 0:
                blend(pixels[row * size + col], (*color[:3], clamp(255 * coverage)))

    draw_round_rect(
        pixels,
        size,
        (size * 0.16, size * 0.18, size * 0.68, size * 0.48),
        size * 0.07,
        (238, 247, 245, 242),
    )
    draw_round_rect(
        pixels,
        size,
        (size * 0.19, size * 0.25, size * 0.62, size * 0.35),
        size * 0.035,
        (8, 23, 35, 236),
    )

    draw_line(
        pixels,
        size,
        (size * 0.31, size * 0.36),
        (size * 0.39, size * 0.43),
        max(1.4, size * 0.032),
        (69, 230, 162, 255),
    )
    draw_line(
        pixels,
        size,
        (size * 0.39, size * 0.43),
        (size * 0.31, size * 0.50),
        max(1.4, size * 0.032),
        (69, 230, 162, 255),
    )
    draw_line(
        pixels,
        size,
        (size * 0.47, size * 0.50),
        (size * 0.66, size * 0.50),
        max(1.2, size * 0.026),
        (178, 224, 218, 235),
    )

    phone_shadow = (size * 0.58, size * 0.48, size * 0.23, size * 0.35)
    draw_round_rect(pixels, size, phone_shadow, size * 0.055, (1, 12, 19, 96))
    draw_round_rect(
        pixels,
        size,
        (size * 0.56, size * 0.45, size * 0.23, size * 0.35),
        size * 0.052,
        (241, 248, 246, 255),
    )
    draw_round_rect(
        pixels,
        size,
        (size * 0.585, size * 0.495, size * 0.18, size * 0.25),
        size * 0.025,
        (30, 96, 101, 255),
    )
    draw_round_rect(
        pixels,
        size,
        (size * 0.64, size * 0.765, size * 0.06, size * 0.012),
        size * 0.006,
        (31, 41, 55, 200),
    )

    for col in range(size):
        highlight = rounded_rect_coverage(col + 0.5, size * 0.17, *base_rect, radius)
        if highlight > 0:
            for row in range(int(size * 0.08), int(size * 0.42)):
                alpha = 36 * (1.0 - row / (size * 0.5))
                blend(pixels[row * size + col], (255, 255, 255, clamp(alpha * highlight)))

    return pixels


def png_chunk(kind: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(data, crc)
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc & 0xFFFFFFFF)


def write_png(path: Path, size: int, pixels: list[list[int]]) -> None:
    raw = bytearray()
    for row in range(size):
        raw.append(0)
        for col in range(size):
            raw.extend(pixels[row * size + col])

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n"
    data += png_chunk(b"IHDR", ihdr)
    data += png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += png_chunk(b"IEND", b"")
    path.write_bytes(data)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: generate_app_icon.py <output.iconset>", file=sys.stderr)
        return 2

    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)

    for points, scale in ICON_SLOTS:
        pixel_size = points * scale
        suffix = "" if scale == 1 else "@2x"
        path = output / f"icon_{points}x{points}{suffix}.png"
        write_png(path, pixel_size, draw_icon(pixel_size))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
