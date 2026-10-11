class_name NowPlaying
extends Control
## The small player in the bottom right corner of a game: which song of the
## playlist is on (BgmDirector.song_title(), translated when the language has
## the title) and at what tempo, beside three bars that bounce with the beat.
## It only shows; nothing on it can be clicked.

const PANEL_SIZE: Vector2 = Vector2(232.0, 36.0)
const MARGIN: float = 10.0
const BAR_WIDTH: float = 3.0
const BAR_GAP: float = 2.0
const BAR_HEIGHT: float = 16.0
## A new song's title lights up and settles over this long.
const FLASH_SECONDS: float = 1.2

var _director: BgmDirector
var _title: Label
var _tempo: Label
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


## The title on show (tests).
func title() -> String:
	return _title.text


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -PANEL_SIZE.x - MARGIN
	offset_top = -PANEL_SIZE.y - MARGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	_title = _label(13, ResourcePack.color("text_value"))
	_title.position = Vector2(30.0, 3.0)
	_title.size = Vector2(PANEL_SIZE.x - 36.0, 16.0)
	_title.clip_text = true
	_tempo = _label(10, ResourcePack.color("text_dim"))
	_tempo.position = Vector2(30.0, 20.0)
	_tempo.size = Vector2(PANEL_SIZE.x - 36.0, 12.0)
	_refresh()


func _label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	# The title is translated here, by hand: it changes while the label lives.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ResourcePack.font("mini"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta / FLASH_SECONDS)
	_refresh()
	queue_redraw()


func _refresh() -> void:
	visible = _director != null and is_instance_valid(_director) and _director.song() >= 0
	if not visible:
		return
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


func _draw() -> void:
	var panel: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(panel, ResourcePack.color("panel_fill"))
	draw_rect(panel, ResourcePack.color("panel_border").lerp(ResourcePack.color("accent"), _flash), false, 1.0)
	# Three bars, each on its own share of the beat.
	var beat: float = _time * float(_bpm) / 60.0
	var color: Color = ResourcePack.color("accent").lerp(ResourcePack.color("highlight"), _flash)
	for index: int in 3:
		var swing: float = absf(sin((beat + float(index) * 0.37) * PI))
		var height: float = roundf(4.0 + (BAR_HEIGHT - 4.0) * swing * (1.0 - 0.25 * float(index % 2)))
		var x: float = 9.0 + float(index) * (BAR_WIDTH + BAR_GAP)
		draw_rect(Rect2(x, (size.y + BAR_HEIGHT) / 2.0 - height, BAR_WIDTH, height), color)
