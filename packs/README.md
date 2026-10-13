# Resource packs

A resource pack decides how the game looks and sounds: the blocks, the screen
layouts, sound effects, music, fonts, the background image and every color.
The game code names no asset file; it asks the enabled packs.

## Where packs live

| Folder | Use |
|---|---|
| `packs/<id>/` (this folder) | packs shipped with the project: `default` (the built-in one) and `pixel` (a small example) |
| `user://packs/<id>/` | packs added later, next to the save data (on Windows: `%APPDATA%\Godot\app_userdata\<project name>\packs\<id>\`) |

Open **Resource Packs** from the main menu or the pause menu. Packs on
the left are available, packs on the right are enabled; the enabled list is a
priority order - the top pack wins, the default pack at the bottom fills in
whatever the others leave out. Nothing changes until **Done**. The choice is
remembered. A pack in `user://packs` with the same id as a bundled one
replaces it.

## Making a pack

1. Copy `packs/pixel` (small) or `packs/default` (everything) to a new folder.
2. Edit its `pack.json`: change `name`, then keep only what you replace.
3. Put your files in the folder and point the entries at them.

Anything a pack leaves out (or names but cannot be loaded) comes from the next
enabled pack and finally from the default pack, entry by entry, so a pack can
be a single sound, a block skin or a handful of colors:

```json
{
	"format": 1,
	"name": "Neon",
	"blocks": {"atlas": "blocks.png", "filter": "nearest"},
	"sounds": {"hard_drop": {"file": "sounds/thump.ogg", "volume_db": -6}},
	"textures": {"background": "bg.png"},
	"colors": {"piece_i": "#00ffee", "accent": "#ff40c0"}
}
```

`pack.png` (any square image) is the pack's icon in the pack list.

## pack.json

- **sounds** / **music** — `"event": "file"` or `"event": {"file": ..., "volume_db": ...}`.
  Formats: `.wav`, `.ogg`, `.mp3`.
- **fonts** — `main` (titles, numbers), `mini` (small labels), `mono` (key hints): `.ttf` / `.otf`.
  Menus keep the project font so Chinese text always renders.
- **textures** — `background` (behind the game and the menus), `orb` (attack particles): `.png` / `.jpg` / `.webp`.
- **colors** — `"#rrggbb"` or `"#rrggbbaa"`.

A file is a path inside the pack folder, or a full `res://` path (the default
pack uses those for the music, fonts and background that stay under `assets/`).

### Blocks

```json
"blocks": {"atlas": "blocks.png", "order": ["i","o","t","s","z","j","l","garbage","ghost"]}
```

- **atlas** - one row of square tiles (the tile size is the image height).
  `order` says what each tile is, left to right; the list above is the default
  and may be shorter or in another order, so a strip drawn for another game
  only needs its `order` written down. Tiles keep their own colors. The
  `ghost` tile should be neutral (white / grey): it is tinted with the piece
  color.
- **tile** - instead of an atlas, one grey tile tinted with `colors.piece_*`.
- `"filter": "nearest"` keeps pixel art crisp (default `"linear"`);
  `"ghost_alpha"` (0..1) sets how solid the landing preview is.

Without a `blocks` section the next pack's blocks are used.
`tools/make_default_blocks.py` draws the two bundled atlases.

### Layouts

The screens themselves are scenes of the pack:

| Layout | Screen | Binding script |
|---|---|---|
| `classic_hud` | single-player HUD | `scripts/ui/classic_hud.gd` |
| `versus_hud`, `versus_side` | versus screen, one player's half | `scripts/ui/versus_hud.gd`, `versus_side.gd` |
| `result_panel` | game over / round / match result | `scripts/ui/result_panel.gd` |
| `versus_setup` | versus setup page | `scripts/ui/versus_setup.gd` |
| `pack_select`, `pack_row` | this pack screen and one row of it | `scripts/ui/pack_select.gd`, `pack_row.gd` |

```json
"layouts": {"classic_hud": "ui/classic_hud.tscn"}
```

To change a layout, open `packs/default/ui/<name>.tscn` in the Godot editor
(or copy it into your pack first) and move, resize, restyle, add or remove
nodes freely. Two things must stay:

- the root node keeps its binding script, and
- the nodes that script lists in `REQUIRED_NODES` keep their names and stay
  "unique name in owner" (the `%` nodes). Each script's header says what every
  required node is for. The game puts the board into the node called
  `BoardSlot`: its size is the board's size (10 columns wide).

A layout that misses a required node, or does not load, is skipped with a
warning in the log and the next pack's layout is used. Layouts of packs in
`user://packs` are also refused when they embed a script or reference one
outside the game's own `res://scripts/` - a scene file can carry code, and a
resource pack must not. `tools/build_default_layouts.gd` regenerates the stock
layouts (it overwrites `packs/default/ui/`).

Menus use the project theme (`assets/ui/base_theme.tres`), which the enabled
packs restyle at run time through their colors, and optionally through
nine-patch images:

```json
"ui": {"panel": {"file": "ui/panel.png", "margin": 8}, "button": {"file": "ui/button.png", "margin": 6}}
```

Names: `panel` (windows), `card` (HUD cards), `button`, `button_hover`,
`button_pressed`, `button_focus`.

### Music

The music is a playlist: songs played one after another in random order, each
as often as the others (every song once before any comes again).

```json
"playlist": [
	{"title": "Theme", "beats": 4, "bars": 34, "volume_db": -13, "tracks": [
		{"file": "music/theme_120.ogg", "bpm": 120},
		{"file": "music/theme_150.ogg", "bpm": 150},
		{"file": "music/theme_180.ogg", "bpm": 180}
	]},
	{"title": "Waltz", "beats": 3, "bars": 52, "volume_db": -12, "tracks": [{"file": "music/waltz.ogg", "bpm": 120}]}
]
```

- `tracks` is the song at rising tempos, the calm one first (one track is
  enough). The tallest stack (rows, incoming garbage included) picks one - the
  first up to 8 rows, the last from 16, the others spread evenly between - and
  the music walks there one track per bar: each step is taken on a bar line
  and lands on the same point of the tune in the next track. So all tracks of
  a song must hold the same bars and name their `bpm`. Small tempo steps sound
  like a gradual speed-up; one big step sounds like a jump.
- `bars` (of `beats` beats each) is how long the song is. A file may go on
  past them - let its reverb ring out there: where the bars end the next song
  starts in time, on the same rung of its own ladder, while the old file
  plays to its end over it. Start every song on its first beat, with no
  silence before it.
- A pack with a playlist replaces the whole playlist; songs of different
  packs are never mixed.

The older form still works - one stream that loops by itself, with optional
faster versions (`loop_offset`: seconds where it starts again after its first
pass, so an intro before it is heard once):

```json
"music": {
	"game": {"file": "music/theme.ogg", "volume_db": -13, "bpm": 120, "loop_offset": 8.0},
	"game_rise_1": {"file": "music/theme_130.ogg", "bpm": 130},
	"game_danger": {"file": "music/theme_fast.ogg", "bpm": 150}
}
```

The default pack's songs are rendered by `tools/make_bgm.py`: adding a tune
there is a line of notes and a line of chords.

### Sound events

| Event | Plays when |
|---|---|
| `move`, `rotate`, `hold` | the piece is moved, rotated, swapped with Hold |
| `lock`, `hard_drop` | a piece locks by itself / is hard dropped |
| `clear` | 1-3 lines cleared (pitched up with the line count) |
| `tetris`, `perfect_clear` | four lines at once / the board emptied |
| `tspin_mini`, `tspin`, `tspin_double`, `tspin_triple` | a T-spin mini / a T-spin with 0-1 lines / with 2 / with 3 |
| `b2b` | on top of a clear that keeps a Back-to-Back chain going |
| `combo` | every clear of a running combo (pitched up with the combo) |
| `level_up`, `game_over` | classic mode |
| `attack`, `garbage` | versus: rows sent / rows received |
| `countdown`, `go`, `ko`, `win`, `lose` | versus: round start, a board topping out, the match result |
| `pause`, `resume` | the pause menu |
| `ui_focus`, `ui_press` | menu buttons |

`music.game` is the looping track of both modes.

The default sounds are generated by `tools/make_default_sfx.py`; edit a recipe
there and rerun it to retune them.

### Colors

Pieces: `piece_i` `piece_o` `piece_t` `piece_s` `piece_z` `piece_j` `piece_l`, `garbage`.
Backgrounds: `background_base`, `background_tint` (tint of the background image),
`menu_top` / `menu_bottom` (menu gradient), `area_fill`, `area_border`,
`board_fill`, `board_border`, `grid`, `panel_fill`, `panel_border`, `veil`.
Text and accents: `text_title`, `text_value`, `text_dim`, `accent`, `highlight`,
`good`, `bad`, `lamp_off`, `player`, `opponent`, `warning`, `warning_queued`,
`cancel`, `tier_easy` `tier_normal` `tier_hard` `tier_lunatic` `tier_extra`.
Menus: `button_fill`, `button_hover`, `button_pressed`, `button_disabled`,
`button_border`, `button_focus`, `button_text`, `button_text_disabled`,
`window_fill`, `window_border`.

Effects: `fx_flash` (lock flash, line sweep), `fx_garbage` (flash of rows that
came in), `fx_danger` (danger border), `fx_ko_veil`, `fx_ko_text`, and the
call-out text `callout_clear`, `callout_tetris`, `callout_tspin`,
`callout_perfect`.

### Effects

The board's feedback is drawn by the game (sweeps, shards, flashes, trails).
A pack changes it in two ways.

Tune what is drawn, with numbers:

```json
"fx": {"shake": 1.0, "shards_per_cell": 2, "sparks_per_drop": 10}
```

`shake` scales every board shake (0 turns it off), the other two are particle
counts.

Or give an event its own animation, a sprite sheet:

```json
"effects": {
	"line_clear": {"sheet": "fx/line_clear.png", "frame": [144, 40], "frames": 18, "fps": 30,
		"scale": 2, "anchor": "center", "glow": 0.35, "replace": true}
}
```

| Event | Played | Where |
|---|---|---|
| `lock` | a piece locks | the piece's center |
| `hard_drop` | a hard drop lands | under the piece (use `"anchor": "bottom"`) |
| `line_clear` | once per cleared row | the row's center |
| `tetris` | four rows at once, instead of four `line_clear` | the middle of the four rows |
| `tspin` | a T-spin that clears lines | the cleared rows |
| `perfect_clear` | the board is emptied | the board's center |
| `garbage` | garbage rows come in | the board's bottom edge (`"anchor": "bottom"`) |
| `ko` | the board is lost | the board's center |

- `sheet`: the frames, left to right and top to bottom, each `frame` pixels.
- `scale`: screen pixels per sheet pixel at the 22-pixel cell (a 10-cell row
  is 110 sheet pixels at scale 2). Sheets are drawn unfiltered.
- `glow`: 0..1, an extra additive pass of the same frame.
- `replace`: leave out the game's own drawn effect for this event. Shake, the
  garbage shove, the danger border, the K.O. veil and the call-out text stay.

### Title

The menus' title is an animation too, a sprite sheet like the effects:

```json
"title": {"sheet": "title.png", "frame": [224, 60], "frames": 156, "fps": 30, "scale": 2, "loop_from": 66, "glow": 0.3}
```

The frames before `loop_from` play once when a menu opens, the rest repeat
for ever (make the last frame lead back into frame `loop_from`). It is drawn
centered at the top of the menu, `scale` screen pixels per sheet pixel. A
pack without a title falls back to the next pack's, ending at the default
pack's 俄罗斯方块, which is rendered by `tools/fx_studio` (the `title`
effect; its characters come from `make_title_glyphs.py`).

### Backdrop

The background of the menus and the game can be an animation as well:

```json
"backdrop": {"sheet": "backdrop.png", "frame": [192, 108], "frames": 72, "fps": 12}
```

All frames are one loop (the last must lead back into the first). It is
drawn unfiltered and scaled up to cover the window, so a small sheet is
enough: 192 x 108 is a sixth of the 1152 x 648 window. A pack without a
backdrop uses the next pack's; with none at all the still `background`
texture shows. The default pack's night sky is the `backdrop` effect of
`tools/fx_studio`.

`packs/icon/` is a whole theme - blocks with a little saint on each,
nine-patch panels and buttons, its own colors and a backdrop of domes and
figures: `python tools/make_icon_pack.py` draws the still parts,
`node tools/fx_studio/export.js --pack icon` the backdrop. `packs/iconfx/`
holds the effects that go with it (`export.js --pack iconfx`): enable both.

`packs/pixelfx/` is a pack made only of effects. Its sheets are rendered by
`tools/fx_studio`: open `tools/fx_studio/index.html` in a browser to play,
scrub and take apart every effect (timeline phases, layers, particle counts),
edit `effects.js`, then run `node tools/fx_studio/export.js` to write the
sheets and the pack's `pack.json`.

## Not covered by packs (yet)

Blocks do not connect into one shape (each cell is its own tile), and the
template's main menu, options and pause windows only take the theme, not a
layout.
