"""Draws the still parts of the "Icon" resource pack (stdlib only): gilded,
enamelled blocks, panels and buttons in the manner of an Orthodox icon's
cover - gold leaf, vermilion, lapis and dark wood - and its pack.json.

    python tools/make_icon_pack.py
    node tools/fx_studio/export.js --pack icon

The first writes blocks.png (9 tiles of 32 px), pack.png, ui/*.png (nine-patch
boxes) and pack.json; the second adds the backdrop of domes under a nimbus
and its entry in pack.json (which this script keeps when it is run again).
The effects that go with it are a pack of their own, "Icon FX"
(node tools/fx_studio/export.js --pack iconfx). Deterministic.
"""
import json
import math
import os

from make_default_blocks import mix, rgb, strip, write_png

PACK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "packs", "icon")

GOLD = rgb("#e8b83a")
GOLD_LIGHT = rgb("#fff0a8")
GOLD_DARK = rgb("#8a5a14")
WOOD = rgb("#241008")
WOOD_DARK = rgb("#120804")
VERMILION = rgb("#b02a1a")
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
# i o t s z j l garbage: lapis, gold, purple, malachite, vermilion, ultramarine, ochre, stone.
ENAMELS = ["#3aa6cc", "#f0c040", "#8e44a8", "#3c9c62", "#cc3a22", "#2c50b0", "#dc7e28", "#7a6c5c"]

COLORS = {
    "piece_i": ENAMELS[0], "piece_o": ENAMELS[1], "piece_t": ENAMELS[2], "piece_s": ENAMELS[3],
    "piece_z": ENAMELS[4], "piece_j": ENAMELS[5], "piece_l": ENAMELS[6], "garbage": ENAMELS[7],
    "background_base": "#0c0604", "background_tint": "#6a4a2a",
    "menu_top": "#2a1208", "menu_bottom": "#0c0604",
    "area_fill": "#180a06eb", "area_border": "#c8962ea6",
    "board_fill": "#0a0503f0", "board_border": "#e8b83ad9",
    "grid": "#f0c0400f",
    "panel_fill": "#1c0c06e6", "panel_border": "#c8962e99",
    "veil": "#0c0604a6",
    "text_title": "#e8b83a", "text_value": "#fff0c8", "text_dim": "#a08458",
    "accent": "#f0c040", "highlight": "#ffe27a",
    "good": "#8ccc7a", "bad": "#e8584a", "lamp_off": "#5a4630",
    "player": "#f0c040", "opponent": "#d8503a",
    "warning": "#e03a22", "warning_queued": "#8a3a1c", "cancel": "#fff0c8",
    "tier_easy": "#8ccc7a", "tier_normal": "#6cb4dc", "tier_hard": "#f0a040", "tier_lunatic": "#e8483a",
    "fx_flash": "#fff0c8", "fx_garbage": "#d8c8a8", "fx_danger": "#e03a22",
    "fx_ko_veil": "#1c0806c2", "fx_ko_text": "#f0c040",
    "callout_perfect": "#fff0a8", "callout_tspin": "#d08ae0", "callout_tetris": "#f0c040", "callout_clear": "#ffe27a",
    "button_fill": "#5a1a10", "button_hover": "#7a2416", "button_pressed": "#3a100a", "button_disabled": "#2a1810",
    "button_border": "#c8962e", "button_focus": "#ffe27a",
    "button_text": "#fff0c8", "button_text_disabled": "#8a7458",
    "window_fill": "#1c0c06f7", "window_border": "#e8b83a",
}


def gold_at(x, y, size):
    """Gold leaf lit from the top left, with a fine hammered grain."""
    lit = 1.0 - (x + y) / (2.0 * (size - 1))
    grain = ((x * 7 + y * 13) % 5 - 2) * 0.03
    tone = max(0.0, min(1.0, 0.25 + 0.6 * lit + grain))
    return mix(GOLD_DARK, GOLD, tone * 1.6) if tone < 0.625 else mix(GOLD, GOLD_LIGHT, (tone - 0.625) / 0.375)


FLESH = (rgb("#e0b084"), rgb("#b88458"), rgb("#7a4e30"))
HAIRS = (rgb("#3a2010"), rgb("#6a4a2a"), rgb("#c8c0b0"))
# Per piece (i o t s z j l): hair (dark, brown, grey), a beard, a veil over the head.
FIGURES = [(0, True, False), (1, False, True), (2, True, False), (1, False, False), (0, False, True), (0, True, False), (1, True, False)]


def figure_pixel(x, y, color, figure):
    """The little icon on a tile, or None where the enamel shows: a haloed
    head and shoulders - each piece its own saint (hair, beard or veil)."""
    hair, beard, veil = figure
    cx, cy = 15.5, 13.5
    dx, dy = x - cx, y - cy
    # Shoulders in the robe's color, a gold collar.
    if y >= 20 and abs(dx) <= 3.0 + (y - 20) * 1.6:
        if y == 20 and abs(dx) <= 2.5:
            return GOLD
        if abs(dx) > 2.0 + (y - 20) * 1.6:
            return mix(color, WHITE, 0.2)
        return mix(color, BLACK, 0.68 if dx > 2 else 0.52)
    face = (dx / 3.4) ** 2 + ((dy - 1.0) / 4.4) ** 2
    if face <= 1.0:
        if veil and (dy < -1.6 or abs(dx) > 2.4):
            return mix(color, BLACK, 0.35)
        if dy < -2.2 or (abs(dx) > 2.6 and dy < 2):
            return HAIRS[hair]
        if beard and dy > 3.0:
            return mix(HAIRS[hair], BLACK, 0.15)
        if y == 14 and x in (14, 17):
            return rgb("#2a160c")
        if y == 17 and x in (15, 16) and not beard:
            return rgb("#a04030")
        return FLESH[2] if dx > 1.6 else FLESH[0] if dx < -1.2 else FLESH[1]
    reach = math.hypot(dx, dy * 1.02)
    if reach <= 7.6:
        # The halo: bright leaf with a darker rim line.
        return GOLD_DARK if reach > 6.7 else mix(GOLD, GOLD_LIGHT, 0.55 - 0.05 * (dx + dy))
    return None


def enamel_tile(color, size=32, stone=False, figure=None):
    """A cabochon of enamel in a gold setting: dark outline, a bevelled gold
    frame, the domed color, and on it a little icon (`figure`) - or, for the
    stone of a garbage block, a cut cross."""
    rows = []
    half = (size - 1) / 2.0
    for y in range(size):
        row = []
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            corner = abs(x - half) + abs(y - half) > size - 4.5
            if edge < 1 or corner:
                shade = mix(WOOD_DARK, GOLD_DARK, 0.25)
            elif edge < 5:
                # Setting: bright on the top and left faces, deep on the others.
                upper = (x < 5 and x <= y and x <= size - 1 - y) or (y < 5 and y <= x and y <= size - 1 - x)
                shade = gold_at(x, y, size)
                shade = mix(shade, GOLD_LIGHT, 0.35) if upper else mix(shade, GOLD_DARK, 0.45)
                if edge == 4:
                    shade = mix(shade, BLACK, 0.45)
            else:
                # The dome of enamel: lighter toward the top left, darker at the rim.
                dx, dy = (x - half) / (half - 5), (y - half) / (half - 5)
                rim = min(1.0, math.hypot(dx, dy))
                shade = mix(mix(color, WHITE, 0.3), mix(color, BLACK, 0.45), min(1.0, 0.5 + 0.35 * (dx + dy) + 0.25 * rim * rim))
                if stone:
                    # Rough stone, and a three-barred cross cut into it.
                    if (x + 2 * y) % 11 == 0:
                        shade = mix(shade, BLACK, 0.3)
                    cut = x in (15, 16) and 8 <= y <= 24
                    cut = cut or (y in (10, 11) and 13 <= x <= 18) or (y in (14, 15) and 11 <= x <= 20)
                    cut = cut or (13 <= x <= 18 and y == 20 + (x - 13) // 2)
                    if cut:
                        shade = mix(shade, BLACK, 0.55)
                    elif (x in (17, 21) and 8 <= y <= 24 and x == 17) or (y == 16 and 11 <= x <= 20):
                        shade = mix(shade, WHITE, 0.25)
                else:
                    painted = figure_pixel(x, y, color, figure)
                    if painted is not None:
                        shade = painted
            row.append((shade[0], shade[1], shade[2], 255))
        rows.append(row)
    return rows


def ghost_tile(size=32):
    """Neutral outline with corner studs; the game tints it with the piece color."""
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            stud = (x < 6 or x >= size - 6) and (y < 6 or y >= size - 6)
            alpha = 240 if edge < 2 else (200 if stud and edge < 5 else (90 if edge < 4 else 34))
            row.append((255, 255, 255, alpha))
        rows.append(row)
    return rows


def box(size, margin, fill, border, inner=None, studs=True, hollow=False):
    """A nine-patch box: a gold band around a fill, a thin second line inside
    it, and a stud in each corner."""
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            edge = min(x, y, size - 1 - x, size - 1 - y)
            alpha = 255
            if edge < 1:
                shade = mix(border, BLACK, 0.55)
            elif edge < 3:
                shade = gold_at(x, y, size) if border == GOLD else border
            elif edge == 3:
                shade = mix(fill, BLACK, 0.5)
            elif inner is not None and edge == 5:
                shade = inner
            else:
                # Fill: a little lighter at the top, like varnished wood.
                shade = mix(mix(fill, WHITE, 0.06), mix(fill, BLACK, 0.2), y / (size - 1))
                if hollow:
                    alpha = 0
            if studs and max(min(x, size - 1 - x), min(y, size - 1 - y)) < margin - 1 and edge >= 1:
                cx = 3.5 if x < size / 2 else size - 4.5
                cy = 3.5 if y < size / 2 else size - 4.5
                reach = math.hypot(x - cx, y - cy)
                if reach < 2.6:
                    shade = mix(GOLD_LIGHT, GOLD_DARK, reach / 2.6)
                    alpha = 255
            row.append((shade[0], shade[1], shade[2], alpha))
        rows.append(row)
    return rows


def pack_icon(tile, size=64):
    """A gold-framed panel with a three-barred cross of enamel tiles on it."""
    rows = box(size, 8, WOOD, GOLD, GOLD_DARK)
    cell = 10
    left, top = (size - 3 * cell) // 2, (size - 5 * cell) // 2
    for cx, cy in ((1, 0), (0, 1), (1, 1), (2, 1), (1, 2), (1, 3), (1, 4)):
        for y in range(cell):
            for x in range(cell):
                rows[top + cy * cell + y][left + cx * cell + x] = tile[y * len(tile) // cell][x * len(tile) // cell]
    return rows


def main():
    tiles = [enamel_tile(rgb(c), stone=index == 7, figure=FIGURES[index] if index < 7 else None) for index, c in enumerate(ENAMELS)] + [ghost_tile()]
    write_png(os.path.join(PACK, "blocks.png"), 32 * 9, 32, strip(tiles))
    write_png(os.path.join(PACK, "pack.png"), 64, 64, pack_icon(tiles[1]))
    ui = {
        "panel": box(32, 8, WOOD, GOLD, GOLD_DARK),
        "card": box(32, 8, mix(WOOD, BLACK, 0.25), GOLD, None),
        "button": box(24, 6, rgb("#5a1a10"), GOLD, None, studs=False),
        "button_hover": box(24, 6, rgb("#7e2616"), GOLD, GOLD_DARK, studs=False),
        "button_pressed": box(24, 6, rgb("#36100a"), GOLD_DARK, None, studs=False),
        "button_focus": box(24, 6, VERMILION, GOLD_LIGHT, None, studs=False, hollow=True),
    }
    for name, rows in ui.items():
        write_png(os.path.join(PACK, "ui", name + ".png"), len(rows), len(rows), rows)
    path = os.path.join(PACK, "pack.json")
    kept = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            old = json.load(handle)
        kept = {key: old[key] for key in ("backdrop",) if key in old}
    manifest = {
        "format": 1,
        "name": "Icon",
        "author": "Project",
        "description": "Gold leaf, vermilion and lapis in the manner of an Orthodox icon: a little saint on every block, gilded panels, and domes under a slowly turning nimbus. Its effects are the Icon FX pack.",
        "icon": "pack.png",
        "blocks": {"atlas": "blocks.png", "ghost_alpha": 0.55},
        "ui": {name: {"file": "ui/%s.png" % name, "margin": 8 if name in ("panel", "card") else 6} for name in ui},
        "colors": COLORS,
    }
    manifest.update(kept)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent="\t", ensure_ascii=False)
        handle.write("\n")
    print("packs/icon/pack.json")


if __name__ == "__main__":
    main()
