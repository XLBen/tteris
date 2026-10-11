"""Draws the block atlases and pack icons of the bundled resource packs
(stdlib only).

    python tools/make_default_blocks.py

Writes, deterministically:
  packs/default/blocks.png   9 tiles of 32 px: i o t s z j l garbage ghost
  packs/default/pack.png     64 px pack icon
  packs/pixel/blocks.png     9 tiles of 8 px (pixel art, drawn with "nearest")
  packs/pixel/pack.png       64 px pack icon
Tile order matches BlockSkin.DEFAULT_ORDER (scripts/block_skin.gd).
"""
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "packs")

# i o t s z j l garbage
DEFAULT_COLORS = ["#33d9f2", "#f2cc40", "#bf66f2", "#66e680", "#f27373", "#598cf2", "#f29e47", "#8c949e"]
PIXEL_COLORS = ["#3cbcfc", "#f8d820", "#b848f8", "#58d854", "#f83800", "#0058f8", "#fc9838", "#7c7c7c"]
# The T tetromino, for the pack icons.
ICON_CELLS = [(1, 0), (0, 1), (1, 1), (2, 1)]


def rgb(text):
    return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, k):
    return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(3))


def write_png(path, width, height, pixels):
    """pixels: rows of (r, g, b, a)."""
    raw = b"".join(b"\x00" + b"".join(struct.pack("4B", *p) for p in row) for row in pixels)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))
    print("%s  %dx%d" % (os.path.relpath(path, os.path.join(ROOT, "..")), width, height))


def smooth_tile(color, size=32):
    """Glossy tile: dark outline, bevel, top-lit body, a soft highlight."""
    white, black = (255, 255, 255), (0, 0, 0)
    radius = size * 0.16
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            # Rounded-rectangle coverage (distance to the corner circles).
            cx = min(max(x + 0.5, radius), size - radius)
            cy = min(max(y + 0.5, radius), size - radius)
            dist = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            alpha = max(0.0, min(1.0, radius - dist + 0.5))
            edge = min(x, y, size - 1 - x, size - 1 - y)
            body = mix(mix(color, white, 0.22), mix(color, black, 0.18), y / (size - 1))
            if edge < 1:
                shade = mix(color, black, 0.62)
            elif edge < 4:
                # Bevel: light from the top-left.
                lit = (x < 4 and x <= y and x <= size - 1 - y) or (y < 4 and y <= x and y <= size - 1 - x)
                shade = mix(color, white, 0.45) if lit else mix(color, black, 0.38)
            else:
                shade = body
                # Highlight band across the upper third.
                if size * 0.2 <= y < size * 0.34 and size * 0.2 <= x < size * 0.8:
                    shade = mix(shade, white, 0.28)
            row.append((shade[0], shade[1], shade[2], int(round(alpha * 255))))
        rows.append(row)
    return rows


def smooth_ghost(size=32):
    """Neutral outline tile; the game tints it with the piece color."""
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            alpha = 235 if edge < 2 else (110 if edge < 4 else 46)
            row.append((255, 255, 255, alpha))
        rows.append(row)
    return rows


def pixel_tile(color, size=8):
    """Chunky tile: 1 px light top/left, dark bottom/right, a 2 px glint."""
    white, black = (255, 255, 255), (0, 0, 0)
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            if x == size - 1 or y == size - 1:
                shade = mix(color, black, 0.55)
            elif x == 0 or y == 0:
                shade = mix(color, white, 0.6)
            elif (x, y) in ((2, 2), (3, 2), (2, 3)):
                shade = mix(color, white, 0.75)
            else:
                shade = color
            row.append((shade[0], shade[1], shade[2], 255))
        rows.append(row)
    return rows


def pixel_ghost(size=8):
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            row.append((255, 255, 255, 255 if edge < 1 else 40))
        rows.append(row)
    return rows


def strip(tiles):
    size = len(tiles[0])
    return [sum((tile[y] for tile in tiles), []) for y in range(size)]


def icon(tile, background, size=64):
    """The T piece built from `tile`, centered on a flat background."""
    side = len(tile)
    cell = size // 4
    rows = [[background + (255,) for _ in range(size)] for _ in range(size)]
    left = (size - 3 * cell) // 2
    top = (size - 2 * cell) // 2
    for cx, cy in ICON_CELLS:
        for y in range(cell):
            for x in range(cell):
                r, g, b, a = tile[y * side // cell][x * side // cell]
                under = rows[top + cy * cell + y][left + cx * cell + x]
                k = a / 255.0
                rows[top + cy * cell + y][left + cx * cell + x] = (
                    int(under[0] + (r - under[0]) * k), int(under[1] + (g - under[1]) * k),
                    int(under[2] + (b - under[2]) * k), 255)
    return rows


def main():
    smooth = [smooth_tile(rgb(c)) for c in DEFAULT_COLORS] + [smooth_ghost()]
    write_png(os.path.join(ROOT, "default", "blocks.png"), 32 * 9, 32, strip(smooth))
    write_png(os.path.join(ROOT, "default", "pack.png"), 64, 64, icon(smooth[2], rgb("#141a2e")))
    pixel = [pixel_tile(rgb(c)) for c in PIXEL_COLORS] + [pixel_ghost()]
    write_png(os.path.join(ROOT, "pixel", "blocks.png"), 8 * 9, 8, strip(pixel))
    write_png(os.path.join(ROOT, "pixel", "pack.png"), 64, 64, icon(pixel[2], rgb("#101010")))


if __name__ == "__main__":
    main()
