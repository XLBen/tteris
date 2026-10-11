class_name NowPlaying
extends Control
## The music player in the bottom right corner of a game, laid out like the
## one of a grand strategy game: a bar that is always there and a window that
## opens over it.
##   The bar: three bars bouncing with the beat, the song's title (translated
##   when the language has it) and tempo, and three buttons - pause / play,
##   next song, open / close the window.
##   The window: "MUSIC PLAYER" and the song's place in the playlist, the
##   whole playlist as a list (the song that plays is marked; a click plays
##   another), and under it the play order (random, or as listed) and the
##   volume.
## Everything goes through BgmDirector (set_paused, next_song, play_song,
## set_shuffle, set_volume); order and volume are remembered. The buttons take
## the mouse only: they never hold the keyboard focus the game is played with.

const BAR_SIZE: Vector2 = Vector2(300.0, 36.0)
const MARGIN: float = 10.0
const BUTTON: float = 24.0
const ROW_HEIGHT: float = 20.0
const HEADER_HEIGHT: float = 24.0
const FOOTER_HEIGHT: float = 30.0
const EQ_WIDTH: float = 3.0
const EQ_GAP: float = 2.0
const EQ_HEIGHT: float = 16.0
## A new song's title lights up and settles over this long.
const FLASH_SECONDS: float = 1.2

var _director: BgmDirector
var _title: Label
var _tempo: Label
var _pause: Button
var _next: Button
var _open: Button
var _window: Control
var _place: Label
var _rows: Array[Button] = []
var _order: Button
var _volume: HSlider
var _song: int = -1
var _bpm: int = 0
var _time: float = 0.0
var _flash: float = 0.0


## A player in the bottom right corner of `parent` that follows `director`.
static func add_to(parent: Node, director: BgmDirector) -> NowPlaying:
	var shown: NowPlaying = NowPlaying.new()
	shown.name = "NowPlaying"
	shown._director = director
	parent.add_child(shown)
	return shown


## The title on show, the order button's text, whether the window is open,
## and the titles listed in it (tests).
func title() -> String:
	return _title.text


func order_text() -> String:
	return _order.text


func window_open() -> bool:
	return _window.visible


func listed() -> PackedStringArray:
	var titles: PackedStringArray = []
	for row: Button in _rows:
		titles.append(row.text)
	return titles


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -BAR_SIZE.x - MARGIN
	offset_top = -BAR_SIZE.y - MARGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	var text_width: float = BAR_SIZE.x - 34.0 - 3.0 * (BUTTON + 4.0)
	_title = _label(self, 13, ResourcePack.color("text_value"), Vector2(30.0, 3.0), Vector2(text_width, 16.0))
	_tempo = _label(self, 10, ResourcePack.color("text_dim"), Vector2(30.0, 20.0), Vector2(text_width, 12.0))
	_pause = _icon_button(self, "PauseButton", 3, _draw_pause_icon, _on_pause_pressed)
	_next = _icon_button(self, "NextButton", 2, _draw_next_icon, _on_next_pressed)
	_open = _icon_button(self, "OpenButton", 1, _draw_open_icon, _on_open_pressed)
	# The window, over the bar.
	_window = Control.new()
	_window.name = "Window"
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.visible = false
	_window.draw.connect(_draw_window)
	add_child(_window)
	_label(_window, 12, ResourcePack.color("text_title"), Vector2(8.0, 4.0), Vector2(180.0, 16.0)).text = tr("MUSIC PLAYER")
	_place = _label(_window, 11, ResourcePack.color("text_dim"), Vector2(BAR_SIZE.x - 78.0, 5.0), Vector2(70.0, 14.0))
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_order = Button.new()
	_order.name = "OrderButton"
	_order.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_order.focus_mode = Control.FOCUS_NONE
	_order.size = Vector2(92.0, FOOTER_HEIGHT - 8.0)
	_order.add_theme_font_override("font", ResourcePack.font("mini"))
	_order.add_theme_font_size_override("font_size", 11)
	_order.pressed.connect(_on_order_pressed)
	_window.add_child(_order)
	_volume = HSlider.new()
	_volume.name = "VolumeSlider"
	_volume.focus_mode = Control.FOCUS_NONE
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.size = Vector2(BAR_SIZE.x - 92.0 - 70.0, 16.0)
	_volume.value_changed.connect(_on_volume_changed)
	_window.add_child(_volume)
	var volume_label: Label = _label(_window, 10, ResourcePack.color("text_dim"), Vector2.ZERO, Vector2(44.0, 14.0))
	volume_label.name = "VolumeLabel"
	volume_label.text = tr("VOLUME")
	_refresh()


func _label(parent: Control, font_size: int, color: Color, at: Vector2, extent: Vector2) -> Label:
	var label: Label = Label.new()
	# Translated here, by hand: the texts change while the labels live.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ResourcePack.font("mini"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = at
	label.size = extent
	label.clip_text = true
	parent.add_child(label)
	return label


## A square button of the bar, `slot` places from its right end, that draws
## its own sign.
func _icon_button(parent: Control, button_name: String, slot: int, sign: Callable, pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.position = Vector2(BAR_SIZE.x - float(slot) * (BUTTON + 4.0) - 2.0, (BAR_SIZE.y - BUTTON) / 2.0)
	button.size = Vector2(BUTTON, BUTTON)
	button.draw.connect(func() -> void:
		var color: Color = ResourcePack.color("highlight") if button.is_hovered() else ResourcePack.color("accent")
		button.draw_rect(Rect2(Vector2.ZERO, button.size), Color(ResourcePack.color("panel_border"), 0.9), false, 1.0)
		sign.call(button, color))
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _draw_pause_icon(button: Button, color: Color) -> void:
	if _director != null and is_instance_valid(_director) and _director.paused():
		button.draw_colored_polygon(PackedVector2Array([Vector2(8, 6), Vector2(18, 12), Vector2(8, 18)]), color)
	else:
		button.draw_rect(Rect2(7, 6, 4, 12), color)
		button.draw_rect(Rect2(13, 6, 4, 12), color)


func _draw_next_icon(button: Button, color: Color) -> void:
	button.draw_colored_polygon(PackedVector2Array([Vector2(5, 6), Vector2(12, 12), Vector2(5, 18)]), color)
	button.draw_colored_polygon(PackedVector2Array([Vector2(11, 6), Vector2(18, 12), Vector2(11, 18)]), color)
	button.draw_rect(Rect2(18, 6, 2, 12), color)


func _draw_open_icon(button: Button, color: Color) -> void:
	for line: int in 3:
		button.draw_rect(Rect2(6, 7 + line * 4, 12, 2), color)


func _draw_window() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, _window.size)
	_window.draw_rect(box, Color(ResourcePack.color("panel_fill"), 0.97))
	_window.draw_rect(Rect2(0, 0, box.size.x, HEADER_HEIGHT), Color(ResourcePack.color("panel_border"), 0.25))
	_window.draw_rect(box, ResourcePack.color("panel_border"), false, 1.0)
	_window.draw_line(Vector2(0, HEADER_HEIGHT), Vector2(box.size.x, HEADER_HEIGHT), ResourcePack.color("panel_border"))
	_window.draw_line(Vector2(0, box.size.y - FOOTER_HEIGHT), Vector2(box.size.x, box.size.y - FOOTER_HEIGHT), ResourcePack.color("panel_border"))
	if _song >= 0 and _song < _rows.size():
		_window.draw_rect(Rect2(2, HEADER_HEIGHT + 2 + float(_song) * ROW_HEIGHT, box.size.x - 4, ROW_HEIGHT), Color(ResourcePack.color("accent"), 0.18))


func _on_pause_pressed() -> void:
	if _director != null and is_instance_valid(_director):
		_director.set_paused(not _director.paused())
		_pause.queue_redraw()


func _on_next_pressed() -> void:
	if _director != null and is_instance_valid(_director):
		_director.next_song()
		_refresh()


func _on_open_pressed() -> void:
	_window.visible = not _window.visible
	_refresh()


func _on_order_pressed() -> void:
	if _director != null and is_instance_valid(_director):
		_director.set_shuffle(not _director.shuffled())
		_refresh()


func _on_volume_changed(value: float) -> void:
	if _director != null and is_instance_valid(_director) and not is_equal_approx(value, _director.volume()):
		_director.set_volume(value)


func _on_row_pressed(index: int) -> void:
	if _director != null and is_instance_valid(_director):
		_director.play_song(index)
		_refresh()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_SECONDS)
	_refresh()
	queue_redraw()


## One row per song of the playlist.
func _list_songs() -> void:
	var titles: PackedStringArray = _director.song_titles()
	for row: Button in _rows:
		row.queue_free()
	_rows = []
	for index: int in titles.size():
		var row: Button = Button.new()
		row.name = "Song%d" % index
		row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.flat = true
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text = "%d  %s" % [index + 1, tr(titles[index]) if titles[index] != "" else tr("Music")]
		row.position = Vector2(4.0, HEADER_HEIGHT + 2.0 + float(index) * ROW_HEIGHT)
		row.size = Vector2(BAR_SIZE.x - 8.0, ROW_HEIGHT)
		row.add_theme_font_override("font", ResourcePack.font("mini"))
		row.add_theme_font_size_override("font_size", 12)
		row.add_theme_color_override("font_color", ResourcePack.color("text_value"))
		row.add_theme_color_override("font_hover_color", ResourcePack.color("highlight"))
		for box: String in ["normal", "hover", "pressed"]:
			row.add_theme_stylebox_override(box, StyleBoxEmpty.new())
		row.pressed.connect(_on_row_pressed.bind(index))
		_window.add_child(row)
		_rows.append(row)
	var height: float = HEADER_HEIGHT + 4.0 + float(_rows.size()) * ROW_HEIGHT + FOOTER_HEIGHT
	_window.position = Vector2(0.0, -height - 4.0)
	_window.size = Vector2(BAR_SIZE.x, height)
	_order.position = Vector2(6.0, height - FOOTER_HEIGHT + 4.0)
	_volume.position = Vector2(BAR_SIZE.x - _volume.size.x - 8.0, height - FOOTER_HEIGHT + 7.0)
	(_window.get_node(^"VolumeLabel") as Label).position = Vector2(_volume.position.x - 48.0, height - FOOTER_HEIGHT + 8.0)


func _refresh() -> void:
	visible = _director != null and is_instance_valid(_director) and _director.song() >= 0
	if not visible:
		return
	if _rows.size() != _director.song_count():
		_list_songs()
	_order.text = tr("SHUFFLE") if _director.shuffled() else tr("IN ORDER")
	_volume.set_value_no_signal(_director.volume())
	var bpm: int = roundi(_director.tempo())
	if _director.song() == _song and bpm == _bpm:
		return
	if _director.song() != _song:
		_flash = 1.0
	_song = _director.song()
	_bpm = bpm
	var name_shown: String = _director.song_title()
	_title.text = tr(name_shown) if name_shown != "" else tr("Music")
	_tempo.text = "%s  %d BPM" % [tr("NOW PLAYING"), bpm]
	_place.text = "%d / %d" % [_song + 1, _director.song_count()]
	for index: int in _rows.size():
		_rows[index].add_theme_color_override("font_color", ResourcePack.color("accent") if index == _song else ResourcePack.color("text_value"))
	_window.queue_redraw()
	_pause.queue_redraw()


func _draw() -> void:
	var panel: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(panel, ResourcePack.color("panel_fill"))
	draw_rect(panel, ResourcePack.color("panel_border").lerp(ResourcePack.color("accent"), _flash), false, 1.0)
	# Three bars, each on its own share of the beat (still while paused).
	var beat: float = _time * float(_bpm) / 60.0
	var still: bool = _director != null and is_instance_valid(_director) and _director.paused()
	var color: Color = ResourcePack.color("accent").lerp(ResourcePack.color("highlight"), _flash)
	for index: int in 3:
		var swing: float = 0.15 if still else absf(sin((beat + float(index) * 0.37) * PI))
		var height: float = roundf(4.0 + (EQ_HEIGHT - 4.0) * swing * (1.0 - 0.25 * float(index % 2)))
		var x: float = 9.0 + float(index) * (EQ_WIDTH + EQ_GAP)
		draw_rect(Rect2(x, (size.y + EQ_HEIGHT) / 2.0 - height, EQ_WIDTH, height), color)
