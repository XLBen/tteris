"""Builds the pack template for artists: packs/template/, a complete working
resource pack that names every part a pack can replace (blocks, interface
boxes, colors, effects, title, backdrop, background), each as a file to paint
over, with a guide in Chinese (说明.md) - and zips it for sending.

    python tools/make_pack_template.py

Writes packs/template/ (copies of the stock art under the names the guide
uses, plain nine-patch boxes, pack.json) and dist/材质包样板.zip (the folder
as it should be handed over). Run it again after the stock art or the pack
format changes. Deterministic apart from the zip's timestamps.
"""
import json
import os
import shutil
import zipfile

from make_default_blocks import mix, rgb, write_png
from make_icon_pack import box

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PACKS = os.path.join(ROOT, "packs")
OUT = os.path.join(PACKS, "template")

EVENTS = [
    ("lock", "方块落定"), ("hard_drop", "硬降落地"), ("line_clear", "消 1–3 行"), ("tetris", "消 4 行"),
    ("tspin", "T 旋"), ("perfect_clear", "全消"), ("garbage", "垃圾行升起"), ("ko", "一方被击败"),
]
COLOR_GROUPS = [
    ("方块", ["piece_i", "piece_o", "piece_t", "piece_s", "piece_z", "piece_j", "piece_l", "garbage"]),
    ("背景与棋盘", ["background_base", "background_tint", "menu_top", "menu_bottom", "area_fill", "area_border", "board_fill", "board_border", "grid", "panel_fill", "panel_border", "veil"]),
    ("文字", ["text_title", "text_value", "text_dim", "accent", "highlight", "good", "bad", "lamp_off"]),
    ("对战", ["player", "opponent", "warning", "warning_queued", "cancel", "tier_easy", "tier_normal", "tier_hard", "tier_lunatic"]),
    ("特效与喊话", ["fx_flash", "fx_garbage", "fx_danger", "fx_ko_veil", "fx_ko_text", "callout_perfect", "callout_tspin", "callout_tetris", "callout_clear"]),
    ("按钮与窗口", ["button_fill", "button_hover", "button_pressed", "button_disabled", "button_border", "button_focus", "button_text", "button_text_disabled", "window_fill", "window_border"]),
]


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def guide(colors, effects, title, backdrop):
    lines = [
        "# 材质包样板",
        "",
        "这个文件夹本身就是一个能用的材质包：里面每个文件都是游戏现在的默认美术，",
        "照着同样的文件名、同样的尺寸规则重画，就是你自己的材质包。",
        "",
        "## 怎么试",
        "",
        "1. 把整个文件夹改个名字（英文小写，例如 `mypack`），放进游戏项目的 `packs/` 文件夹。",
        "   游戏里所有材质包都在这一个文件夹里，启用和没启用的都在。",
        "2. 打开 `pack.json`，把 `name`、`author`、`description` 改成你的。",
        "3. 进游戏：主菜单 → 材质包，勾选你的包。可以同时勾多个，排在上面的优先。",
        "4. 改了图片后重新进一次游戏就能看到。",
        "",
        "不想改的部分直接删掉对应的文件和 `pack.json` 里那一段，游戏会用默认的顶上。",
        "所以只画方块、或者只画背景，也是一个合法的材质包。",
        "",
        "## 文件一览",
        "",
        "| 文件 | 是什么 | 规格 |",
        "|---|---|---|",
        "| `pack.png` | 材质包列表里的图标 | 64×64 |",
        "| `blocks.png` | 方块 | 一行 9 个正方形格子，见下 |",
        "| `ui/*.png` | 面板和按钮的边框 | 九宫格图，见下 |",
        "| `background.png` | 静态背景底图 | 任意尺寸，会铺满窗口（1152×648） |",
        "| `backdrop.png` | 动态背景 | 序列帧，见下 |",
        "| `title.png` | 主菜单的动态标题 | 序列帧，见下 |",
        "| `fx/*.png` | 棋盘特效，每个事件一张 | 序列帧，见下 |",
        "| `pack.json` | 清单：上面每个文件的参数，以及全部颜色 | 文本，UTF-8 |",
        "",
        "图片一律 PNG，带透明通道。像素风的图在 `pack.json` 里写 `\"filter\": \"nearest\"`（方块段里有例子）。",
        "",
        "## 方块 `blocks.png`",
        "",
        "一行 9 格，每格是正方形，边长随意（样板是 32 像素；像素风可以用 8 或 16）。从左到右：",
        "",
        "`I` `O` `T` `S` `Z` `J` `L` `垃圾块` `落点虚影`",
        "",
        "- 前 8 格画什么颜色就显示什么颜色。",
        "- 最后一格（虚影）请画成白色加透明度，游戏会把它染成当前方块的颜色。",
        "  `ghost_alpha` 是它的整体不透明度（0–1）。",
        "- 棋盘上一格显示为 22×22 像素，预览区更小，细节别画太碎。",
        "",
        "## 面板和按钮 `ui/`",
        "",
        "九宫格图：四个角原样显示，四条边和中间会被拉伸。`margin` 是角的宽度（像素）。",
        "",
        "| 文件 | 用在哪 |",
        "|---|---|",
        "| `panel.png` | 窗口、弹出面板 |",
        "| `card.png` | 对局里的信息卡片（暂存、下一个……） |",
        "| `button.png` | 按钮平时 |",
        "| `button_hover.png` | 鼠标悬停 |",
        "| `button_pressed.png` | 按下 |",
        "| `button_focus.png` | 键盘选中时套在外面的框（中间请留透明） |",
        "",
        "## 序列帧（特效、标题、动态背景）",
        "",
        "一张图里从左到右、从上到下排列各帧，每帧一样大。`pack.json` 里对应的参数：",
        "",
        "- `frame`：一帧的宽和高（图里的像素）",
        "- `frames`：总帧数；`fps`：每秒播放几帧",
        "- `scale`：图里 1 像素在屏幕上占几像素（样板的特效是 2，即按 11 像素一格来画）",
        "- `anchor`：`center` 以事件位置为中心；`bottom` 以底边中点对齐（适合从地面升起的效果）",
        "- `glow`：0–1，额外叠一层发光；`replace`：`true` 表示完全替换游戏自带的简单特效",
        "",
        "### 特效 `fx/`",
        "",
        "最后一帧必须是全透明的（特效播完要消失干净）。样板里各事件的画布大小可以直接沿用：",
        "",
        "| 文件 | 什么时候播 | 一帧大小 | 帧数 | 帧率 | 对齐 |",
        "|---|---|---|---|---|---|",
    ]
    for key, when in EVENTS:
        entry = effects[key]
        lines.append("| `fx/%s.png` | %s | %d×%d | %d | %d | %s |" % (key, when, entry["frame"][0], entry["frame"][1], entry["frames"], entry["fps"], entry["anchor"]))
    lines += [
        "",
        "消行类特效的中心是被消掉的那几行的中心，棋盘宽 10 格（按 11 像素一格就是 110 像素宽）。",
        "",
        "### 标题 `title.png`",
        "",
        "一帧 %d×%d，共 %d 帧，%d 帧/秒，屏幕上放大 %d 倍。" % (title["frame"][0], title["frame"][1], title["frames"], title["fps"], title["scale"]),
        "先完整播一遍入场，然后从第 `loop_from`（%d）帧到最后一帧循环，所以最后一帧要能接回第 %d 帧。" % (title["loop_from"], title["loop_from"]),
        "",
        "### 动态背景 `backdrop.png`",
        "",
        "一帧 %d×%d，共 %d 帧，%d 帧/秒。整段是一个无缝循环：最后一帧要能接回第一帧。" % (backdrop["frame"][0], backdrop["frame"][1], backdrop["frames"], backdrop["fps"]),
        "它会被放大铺满窗口，盖在静态背景上。棋盘和菜单都叠在它上面，所以请偏暗、偏安静。",
        "",
        "## 颜色",
        "",
        "`pack.json` 的 `colors` 段。写法是 `#rrggbb`，或带透明度的 `#rrggbbaa`。下面是全部名字和样板里的值：",
        "",
    ]
    for group, keys in COLOR_GROUPS:
        lines.append("**%s**" % group)
        lines.append("")
        lines.append("| 名字 | 样板值 |")
        lines.append("|---|---|")
        for key in keys:
            lines.append("| `%s` | `%s` |" % (key, colors.get(key, "")))
        lines.append("")
    lines += [
        "方块的 7 个颜色和垃圾块的颜色也用于界面上的小预览和特效，请和 `blocks.png` 里画的颜色保持一致。",
        "",
        "## 这份样板里没有的",
        "",
        "字体（`fonts`：.ttf / .otf）、音效（`sounds`：.wav / .ogg）和音乐（`playlist`）也可以放进材质包，",
        "写法见游戏项目里的 `packs/README.md`。只做美术的话不用管，游戏会用默认的。",
        "",
        "## 参考",
        "",
        "游戏项目的 `packs/` 里有几个做好的包可以对照：`pixel`（只换方块和颜色的最小例子）、",
        "`pixelfx`（只有特效）、`icon` 和 `iconfx`（一整套主题：方块、界面、背景，加配套特效）。",
        "",
    ]
    return "\n".join(lines)


def main():
    default = load(os.path.join(PACKS, "default", "pack.json"))
    stock_fx = load(os.path.join(PACKS, "pixelfx", "pack.json"))["effects"]
    colors = default["colors"]
    if os.path.isdir(OUT):
        for name in os.listdir(OUT):
            path = os.path.join(OUT, name)
            # (The .import files Godot wrote stay: they keep the files' ids.)
            if os.path.isdir(path):
                for inner in os.listdir(path):
                    if not inner.endswith(".import"):
                        os.remove(os.path.join(path, inner))
            elif not name.endswith(".import"):
                os.remove(path)
    os.makedirs(os.path.join(OUT, "fx"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "ui"), exist_ok=True)
    for source, name in (
        (os.path.join(PACKS, "default", "blocks.png"), "blocks.png"),
        (os.path.join(PACKS, "default", "pack.png"), "pack.png"),
        (os.path.join(PACKS, "default", "title.png"), "title.png"),
        (os.path.join(PACKS, "default", "backdrop.png"), "backdrop.png"),
        (os.path.join(ROOT, "assets", "visuals", "background.png"), "background.png"),
    ):
        shutil.copyfile(source, os.path.join(OUT, name))
    for key, _ in EVENTS:
        shutil.copyfile(os.path.join(PACKS, "pixelfx", "fx", key + ".png"), os.path.join(OUT, "fx", key + ".png"))
    # Plain boxes in the stock colors: the shapes to paint over.
    fill, border = rgb(colors["button_fill"]), rgb(colors["button_border"])
    boxes = {
        "panel": box(32, 8, rgb(colors["window_fill"][:7]), rgb(colors["window_border"]), None),
        "card": box(32, 8, rgb(colors["panel_fill"][:7]), mix(rgb(colors["panel_border"][:7]), (0, 0, 0), 0.3), None),
        "button": box(24, 6, fill, border, None, studs=False),
        "button_hover": box(24, 6, rgb(colors["button_hover"]), border, None, studs=False),
        "button_pressed": box(24, 6, rgb(colors["button_pressed"]), border, None, studs=False),
        "button_focus": box(24, 6, fill, rgb(colors["button_focus"]), None, studs=False, hollow=True),
    }
    for name, rows in boxes.items():
        write_png(os.path.join(OUT, "ui", name + ".png"), len(rows), len(rows), rows)
    effects = {key: stock_fx[key] for key, _ in EVENTS}
    manifest = {
        "format": 1,
        "name": "Template",
        "author": "Your name",
        "description": "The pack template: every part a pack can replace, as files to paint over. See 说明.md.",
        "icon": "pack.png",
        "blocks": {"atlas": "blocks.png", "filter": "linear", "ghost_alpha": 0.35},
        "ui": {name: {"file": "ui/%s.png" % name, "margin": 8 if name in ("panel", "card") else 6} for name in boxes},
        "textures": {"background": "background.png"},
        "backdrop": default["backdrop"],
        "title": default["title"],
        "effects": effects,
        "colors": colors,
    }
    text = json.dumps(manifest, indent="\t", ensure_ascii=False)
    # Short lists on one line, as in the other packs.
    import re
    text = re.sub(r"\[\n\t+(\d+),\n\t+(\d+)\n\t+\]", r"[\1, \2]", text)
    with open(os.path.join(OUT, "pack.json"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + "\n")
    with open(os.path.join(OUT, "说明.md"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(guide(colors, effects, default["title"], default["backdrop"]))
    # The folder as it is handed over (without Godot's own files).
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    target = os.path.join(ROOT, "dist", "材质包样板.zip")
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for folder, _, files in os.walk(OUT):
            for name in sorted(files):
                if name.endswith((".import", ".uid")):
                    continue
                path = os.path.join(folder, name)
                archive.write(path, os.path.join("template", os.path.relpath(path, OUT)))
    print("packs/template/ and dist/材质包样板.zip (%d KB)" % (os.path.getsize(target) // 1024))


if __name__ == "__main__":
    main()
