extends SceneTree
## Pack-driven blocks and layouts: BlockSkin reads the block look from the
## enabled packs (atlas with a tile order, single tinted tile, fallbacks), the
## boards follow a pack switch, and a pack can replace a screen layout - but
## only with a scene that keeps the required nodes and carries no code.

const MODULE_NAME: String = "block_skin"

const PACK_ID: String = "zz_skin_pack"
const PACK_DIR: String = "user://packs/zz_skin_pack"
const DEFAULT_HUD: String = "res://packs/default/ui/classic_hud.tscn"


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d block skin cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("BLOCK SKIN TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	await _tree().process_frame
	var saved: Array[String] = ResourcePack.enabled_ids()
	_case_bundled_packs_use_their_atlases(ctx)
	_case_order_tile_and_fallback(ctx)
	await _case_board_follows_pack_switch(ctx)
	await _case_pack_layout_replaces_the_hud(ctx)
	_case_broken_or_unsafe_layouts_fall_back(ctx)
	_remove_pack()
	ResourcePack.set_enabled(saved, false)
	await _tree().process_frame
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Writes the test pack: `manifest` plus named text/binary files.
static func _write_pack(manifest: Dictionary, files: Dictionary = {}) -> void:
	_remove_pack()
	DirAccess.make_dir_recursive_absolute(PACK_DIR + "/ui")
	for file_name: String in files:
		var out: FileAccess = FileAccess.open(PACK_DIR + "/" + file_name, FileAccess.WRITE)
		if files[file_name] is PackedByteArray:
			out.store_buffer(files[file_name])
		else:
			out.store_string(String(files[file_name]))
		out.close()
	manifest["name"] = "Skin Test"
	var out_manifest: FileAccess = FileAccess.open(PACK_DIR + "/pack.json", FileAccess.WRITE)
	out_manifest.store_string(JSON.stringify(manifest))
	out_manifest.close()
	ResourcePack.set_enabled([PACK_ID], false)


static func _remove_pack() -> void:
	for dir: String in [PACK_DIR + "/ui", PACK_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file_name: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + "/" + file_name)
		DirAccess.remove_absolute(dir)


static func _case_bundled_packs_use_their_atlases(ctx: Dictionary) -> void:
	ResourcePack.set_enabled([], false)
	var ok: bool = BlockSkin.mode() == BlockSkin.Mode.ATLAS and BlockSkin._regions.size() == 9
	ok = ok and BlockSkin.texture_filter() == CanvasItem.TEXTURE_FILTER_LINEAR
	# Nine square tiles in the documented order.
	for i: int in BlockSkin.DEFAULT_ORDER.size():
		var region: Rect2 = BlockSkin._regions[BlockSkin.DEFAULT_ORDER[i]]
		ok = ok and region.size.x == region.size.y and is_equal_approx(region.position.x, region.size.x * float(i))
	ResourcePack.set_enabled(["pixel"], false)
	ok = ok and BlockSkin.mode() == BlockSkin.Mode.ATLAS and BlockSkin.texture_filter() == CanvasItem.TEXTURE_FILTER_NEAREST
	ok = ok and (BlockSkin._regions["i"] as Rect2).size == Vector2(8, 8)
	# The pixel pack restyles blocks and colors but brings no sounds or layouts.
	ok = ok and ResourcePack.sound("move") != null and ResourcePack.layout("classic_hud") != null
	ResourcePack.set_enabled([], false)
	_case(ctx, "bundled_packs_draw_blocks_from_their_atlases", ok)


static func _case_order_tile_and_fallback(ctx: Dictionary) -> void:
	var strip: PackedByteArray = FileAccess.get_file_as_bytes("res://packs/pixel/blocks.png")
	# A strip drawn in another order: only `order` has to say so.
	_write_pack({"blocks": {"atlas": "strip.png", "order": ["ghost", "garbage", "l", "j", "z", "s", "t", "o", "i"]}}, {"strip.png": strip})
	var ok: bool = BlockSkin.mode() == BlockSkin.Mode.ATLAS
	ok = ok and (BlockSkin._regions["i"] as Rect2).position.x == 64.0 and (BlockSkin._regions["ghost"] as Rect2).position.x == 0.0
	# One tile, tinted with the piece colors.
	_write_pack({"blocks": {"tile": "tile.png"}, "colors": {"piece_t": "#123456"}}, {"tile.png": FileAccess.get_file_as_bytes("res://packs/pixel/pack.png")})
	ok = ok and BlockSkin.mode() == BlockSkin.Mode.TILE and ResourcePack.cell_color(Tetromino.PieceType.T) == Color.html("#123456")
	# A pack whose block file is missing does not break the blocks: the next
	# pack down (here the default) supplies them.
	_write_pack({"blocks": {"atlas": "nowhere.png"}})
	ok = ok and BlockSkin.mode() == BlockSkin.Mode.ATLAS and BlockSkin._regions.size() == 9
	ok = ok and BlockSkin.texture_filter() == CanvasItem.TEXTURE_FILTER_LINEAR
	ResourcePack.set_enabled([], false)
	_case(ctx, "atlas_order_single_tile_and_fallback_to_the_next_pack", ok)


static func _case_board_follows_pack_switch(ctx: Dictionary) -> void:
	ResourcePack.set_enabled([], false)
	var view: BoardView = BoardView.new()
	_tree().root.add_child(view)
	var board: Board = Board.new()
	board.set_cell(Vector2i(3, Board.BOARD_HEIGHT - 1), Tetromino.PieceType.S)
	board.set_cell(Vector2i(4, Board.BOARD_HEIGHT - 1), Board.GARBAGE)
	var piece: Array[Vector2i] = [Vector2i(4, -1), Vector2i(4, 0), Vector2i(5, 0)]
	view.show_board(board, piece, Tetromino.PieceType.T, [Vector2i(4, 18)])
	var ok: bool = view.cell_at(3, 19) == Tetromino.PieceType.S and view.cell_at(4, 19) == Board.GARBAGE
	ok = ok and view.cell_at(0, 0) == Board.EMPTY and view.piece_cells().size() == 3 and view.ghost_cells().size() == 1
	ok = ok and view.board_size() == Vector2(240, 480) and view.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR
	# Same data, other packs: the view notices and takes the pack's filter.
	ResourcePack.set_enabled(["pixel"], false)
	view.show_board(board, piece, Tetromino.PieceType.T, [Vector2i(4, 18)])
	ok = ok and view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
	var preview: PiecePreview = PiecePreview.new()
	preview.piece_type = Tetromino.PieceType.I
	_tree().root.add_child(preview)
	await _tree().process_frame
	ok = ok and preview.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and preview.get_minimum_size().x >= 4.0 * preview.cell_size
	preview.free()
	view.free()
	ResourcePack.set_enabled([], false)
	_case(ctx, "board_and_previews_follow_a_pack_switch", ok)


## A pack's own layout scene: the default HUD with a smaller board slot.
static func _case_pack_layout_replaces_the_hud(ctx: Dictionary) -> void:
	var scene_text: String = FileAccess.get_file_as_string(DEFAULT_HUD)
	var ok: bool = scene_text.contains("custom_minimum_size = Vector2(240, 480)")
	_write_pack({"layouts": {"classic_hud": "ui/classic_hud.tscn"}},
		{"ui/classic_hud.tscn": scene_text.replace("custom_minimum_size = Vector2(240, 480)", "custom_minimum_size = Vector2(200, 400)")})
	var layout: PackedScene = ResourcePack.layout("classic_hud")
	ok = ok and layout != null and layout.resource_path.begins_with(PACK_DIR)
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	_tree().root.add_child(main)
	await _tree().process_frame
	# The game put its board onto the pack layout's slot.
	ok = ok and main._hud.board_slot.size == Vector2(200, 400)
	ok = ok and main._board_view.cell_size == 20.0 and main._board_view.board_size() == Vector2(200, 400)
	ok = ok and main._board_view.global_position.is_equal_approx(main._hud.board_slot.global_position)
	main.free()
	await _tree().process_frame
	ResourcePack.set_enabled([], false)
	ok = ok and ResourcePack.layout("classic_hud").resource_path == DEFAULT_HUD
	_case(ctx, "pack_layout_scene_replaces_the_hud", ok)


static func _case_broken_or_unsafe_layouts_fall_back(ctx: Dictionary) -> void:
	var scene_text: String = FileAccess.get_file_as_string(DEFAULT_HUD)
	# A layout that dropped a required node.
	_write_pack({"layouts": {"classic_hud": "ui/classic_hud.tscn"}},
		{"ui/classic_hud.tscn": scene_text.replace("[node name=\"ScoreValue\"", "[node name=\"Renamed\"")})
	var ok: bool = ResourcePack.layout("classic_hud").resource_path == DEFAULT_HUD
	# A layout that smuggles in a script of its own.
	var embedded: String = scene_text.replace("[node name=\"ClassicHud\"",
		"[sub_resource type=\"GDScript\" id=\"evil\"]\nscript/source = \"extends Node\"\n\n[node name=\"ClassicHud\"")
	_write_pack({"layouts": {"classic_hud": "ui/classic_hud.tscn"}}, {"ui/classic_hud.tscn": embedded})
	ok = ok and ResourcePack._scene_text_problem(PACK_DIR + "/ui/classic_hud.tscn", 0) == "embedded script"
	ok = ok and ResourcePack.layout("classic_hud").resource_path == DEFAULT_HUD
	# A layout that points at a script outside the game.
	var foreign: String = scene_text.replace("res://scripts/ui/classic_hud.gd", PACK_DIR + "/ui/own.gd")
	_write_pack({"layouts": {"classic_hud": "ui/classic_hud.tscn"}}, {"ui/classic_hud.tscn": foreign, "ui/own.gd": "extends Control\n"})
	ok = ok and ResourcePack._scene_text_problem(PACK_DIR + "/ui/classic_hud.tscn", 0).begins_with("script outside the game")
	ok = ok and ResourcePack.layout("classic_hud").resource_path == DEFAULT_HUD
	# A file that is not there at all.
	_write_pack({"layouts": {"classic_hud": "ui/missing.tscn"}})
	ok = ok and ResourcePack.layout("classic_hud").resource_path == DEFAULT_HUD
	ResourcePack.set_enabled([], false)
	_case(ctx, "broken_or_unsafe_layouts_fall_back_to_the_default", ok)
