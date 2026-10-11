# Modern Tetris (Godot 4.7)

A modern Tetris in GDScript: SRS rotation, hold, 7-bag, T-spins, Back-to-Back and
combos, a classic mode and a versus mode against a tiered AI, and resource packs
that own the look and the sound. Runs offline.

## Run

Godot 4.7.x on Windows; the project root is the folder with `project.godot`.

```powershell
& "<godot>" --path .
```

Main menu: New Game, Options, How to Play, Resource Packs, Exit. New Game asks
for the mode.

- **Classic**: one level per 10 lines (up to 15), Perfect Clear bonuses.
- **Versus**: you or a CPU against a CPU (Easy / Normal / Hard / Lunatic) on two
  boards, fixed speed or rising speed (one level per 8 lines cleared between the
  two), single match or best of 3. Garbage follows the Puyo Puyo Tetris table,
  attacks cancel incoming garbage first. How to Play has the full rules.

Keys (remappable in Options): `A`/`D` or arrows move, `X`/`W`/`Up` rotate,
`Z` rotate back, `S`/`Down` soft drop, `Space` hard drop, `C`/`Shift` hold,
`P`/`Esc` pause.

## Test

```powershell
& "<godot>" --headless --path . --script res://tests/run_all.gd
```

Expected: `ALL TESTS PASSED (278)`, exit code 0, about three minutes. One module:
`--script res://tests/test_menu.gd`. After editing a script:
`--headless --check-only --script res://scripts/<file>.gd`; after editing scenes
or resources: `--headless --editor --quit`.

## Layout

| Path | What |
|---|---|
| `scripts/main.gd`, `scenes/main.tscn` | the classic game |
| `scripts/versus.gd`, `versus_battle.gd`, `versus_ai.gd` | versus: scene, rules model, AI |
| `scripts/board.gd`, `tetromino.gd`, `srs.gd`, `scoring.gd` | the rules of the game |
| `scripts/board_fx.gd` | board feedback: drawn effects and the pack's sprite effects |
| `scripts/bgm_director.gd` | music that speeds up with the stack |
| `scripts/resource_pack.gd`, `pack_runtime.gd` | resource packs |
| `scripts/ui/` | binding scripts of the pack's screen layouts |
| `scenes/menus/`, `scenes/windows/` | menus and windows from the Maaack template (vendored copies: do not edit) |
| `packs/` | `default` (built in), `pixel`, `pixelfx`; format in `packs/README.md` |
| `tests/` | headless test modules, `run_all.gd` runs them all |
| `tools/` | generators and labs, below |
| `addons/`, `camera-effects/`, `particles/`, `docs/vendor/` | vendored code with its license records |

## Tools

| Tool | Makes |
|---|---|
| `tools/fx_studio/` | the Pixel FX pack: `index.html` is the effect studio, `node tools/fx_studio/export.js` writes the sheets |
| `tools/make_coldwar_bgm.py` | the six BGM tracks (numpy, scipy, ffmpeg) |
| `tools/make_default_sfx.py`, `make_default_blocks.py` | the default pack's sounds and block atlas |
| `tools/build_default_layouts.gd` | the default pack's screen layouts (`--headless --script`) |
| `tools/ai_arena.gd`, `tspin_lab.gd` | AI match statistics and T-spin positions (`--headless --script`) |
| `tools/isolated_delivery_check.py` | imports and tests a clean copy of the project |
| `tools/check_audio_assets.py`, `install_audio_assets.py` | audio records in `assets/assets-*.json` |

After re-rendering the BGM, update its sha256 records in
`assets/assets-measurements.json` (`tests/test_music.gd` checks them).

## Assets and licenses

- Fonts, background, particle textures and the interface sounds: Kenney, CC0.
- Music: the project's own synth arrangement of Korobeiniki (public-domain
  melody), `assets/audio/bgm/LICENSE-bgm-coldwar-synth.txt`.
- Maaack's Godot Game Template and marinho/godot-visual-effects: MIT, records in
  `docs/vendor/` and in each addon.
- Sources and hashes of every asset: `assets/assets-provenance.json`,
  `assets-manifest.json`, `assets-measurements.json`.

## Known limits

- No export package: the delivery is the Godot project.
- A first import without a `.godot/` cache can crash once in Godot 4.7.2 while
  importing Ogg files; running the import again completes it.
- Headless runs may print teardown warnings about leaked instances; the exit
  code stays 0.
- A classic score of 10,000,000 or more runs past its card.
