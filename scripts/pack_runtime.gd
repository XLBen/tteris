extends Node
## Applies the active resource pack (scripts/resource_pack.gd) to everything
## that outlives a single scene. Registered as the PackRuntime autoload.
##
## - the Control styling of the whole game (menus, windows, buttons),
## - a backdrop behind the menu scenes (the game scenes cover it with their
##   own background layer),
## - the interface sounds of the template's UI sound controller,
## - the game's own entries of the main menu (scripts/ui/main_menu_entries.gd)
##   and the pack's animated title (scripts/ui/pack_title.gd), added whenever
##   a menu scene appears.
## apply() runs at startup and again after the pack was switched.

const BACKDROP_LAYER: int = -100
const UI_SOUND_CONTROLLER: NodePath = ^"/root/ProjectUISoundController"

var _backdrop: CanvasLayer
var _gradient: TextureRect
var _image: TextureRect


func _ready() -> void:
	_build_backdrop()
	apply()
	# The sound controller builds its players in its own _ready.
	_apply_ui_sounds.call_deferred()
	get_tree().node_added.connect(_on_node_added)
	# The first scene entered the tree before this autoload was ready.
	for child: Node in get_tree().root.get_children():
		if child is MainMenu:
			_dress_menu.call_deferred(child)


func _on_node_added(node: Node) -> void:
	if node is MainMenu:
		node.ready.connect(_dress_menu.bind(node), CONNECT_ONE_SHOT)


## Every menu built on the template's main menu gets the animated title; the
## main menu itself also gets the game's entries.
func _dress_menu(menu: Node) -> void:
	PackTitle.attach(menu)
	if MainMenuEntries.is_main_menu(menu):
		MainMenuEntries.attach(menu)


func apply() -> void:
	ResourcePack.ensure_loaded()
	ResourcePack.style_theme(ThemeDB.get_default_theme())
	RenderingServer.set_default_clear_color(ResourcePack.color("menu_bottom"))
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, ResourcePack.color("menu_top"))
	gradient.set_color(1, ResourcePack.color("menu_bottom"))
	var fill: GradientTexture2D = GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	fill.width = 8
	fill.height = 128
	_gradient.texture = fill
	_image.texture = ResourcePack.texture("background")
	_image.modulate = Color(ResourcePack.color("background_tint"), 0.5)
	_apply_ui_sounds()


func _build_backdrop() -> void:
	_backdrop = CanvasLayer.new()
	_backdrop.name = "Backdrop"
	_backdrop.layer = BACKDROP_LAYER
	add_child(_backdrop)
	_gradient = _full_rect()
	_gradient.stretch_mode = TextureRect.STRETCH_SCALE
	_image = _full_rect()
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


func _full_rect() -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(rect)
	return rect


## Focus / hover tick and press blip of every button in the game.
func _apply_ui_sounds() -> void:
	var controller: Node = get_node_or_null(UI_SOUND_CONTROLLER)
	if controller == null:
		return
	for pair: Array in [["button_hovered_player", "ui_focus"], ["button_focused_player", "ui_focus"], ["button_pressed_player", "ui_press"]]:
		var player: AudioStreamPlayer = controller.get(pair[0]) as AudioStreamPlayer
		var stream: AudioStream = ResourcePack.sound(pair[1])
		if player != null and stream != null:
			player.stream = stream
			player.volume_db = ResourcePack.sound_volume(pair[1])
