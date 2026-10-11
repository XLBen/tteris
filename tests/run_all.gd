extends SceneTree

const LOAD_CHECK_PATHS: Array[String] = [
	"res://scripts/board.gd",
	"res://scripts/tetromino.gd",
	"res://scripts/srs.gd",
	"res://scripts/scoring.gd",
	"res://scripts/main.gd",
	"res://scripts/versus_battle.gd",
	"res://scripts/versus_ai.gd",
	"res://scripts/board_fx.gd",
	"res://scripts/how_to_play.gd",
	"res://scenes/main.tscn",
	"res://scripts/versus.gd",
	"res://scenes/versus/versus.tscn",
]
const MODULE_PATHS: Array[String] = [
	"res://tests/test_rotation.gd",
	"res://tests/test_scoring.gd",
	"res://tests/test_play_flow.gd",
	"res://tests/test_layout.gd",
	"res://tests/test_visual_feedback.gd",
	"res://tests/test_sfx_sync.gd",
	"res://tests/test_music.gd",
	"res://tests/test_input_map.gd",
	"res://tests/test_assets.gd",
	"res://tests/test_menu.gd",
	"res://tests/test_mode_classic.gd",
	"res://tests/test_settings.gd",
	"res://tests/test_localization.gd",
	"res://tests/test_pause_menu.gd",
	"res://tests/test_ui_reference.gd",
	"res://tests/test_ui_fix.gd",
	"res://tests/test_versus_battle.gd",
	"res://tests/test_versus_flow.gd",
	"res://tests/test_versus_difficulty.gd",
	"res://tests/test_ai_tiers.gd",
	"res://tests/test_ai_tspin.gd",
	"res://tests/test_resource_pack.gd",
	"res://tests/test_block_skin.gd",
	"res://tests/test_versus_match.gd",
	"res://tests/test_versus_ai.gd",
	"res://tests/test_debug_duel.gd",
	"res://tests/test_pause_keyboard.gd",
	"res://tests/test_garbage_rules.gd",
	"res://tests/test_versus_bgm.gd",
	"res://tests/test_window_state.gd",
	"res://tests/test_board_fx.gd",
]


func _initialize() -> void:
	for path: String in LOAD_CHECK_PATHS:
		if load(path) == null:
			print("FAILED: load %s" % path)
			quit(1)
			return
	var total: int = 0
	var failed: int = 0
	var lines: Array[String] = []
	# Some modules enable packs the way the pack screen does, which is saved:
	# the player's own choice is put back when the run is over.
	var player_packs: Array[String] = ResourcePack.enabled_ids()
	for path: String in MODULE_PATHS:
		var script: GDScript = load(path) as GDScript
		if script == null:
			print("FAILED: load %s" % path)
			quit(1)
			return
		# Every module starts on the default pack alone, whatever packs the
		# player has enabled in the saved settings.
		ResourcePack.set_enabled([], false)
		var result: Dictionary = await script.run_module()
		total += int(result["total"])
		failed += int(result["failed"])
		for line: String in (result["lines"] as Array):
			lines.append(line)
	ResourcePack.set_enabled(player_packs)
	for line: String in lines:
		print(line)
	if failed > 0:
		print("FAILED: %d of %d cases" % [failed, total])
		quit(1)
		return
	print("ALL TESTS PASSED (%d)" % total)
	quit(0)
