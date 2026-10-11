extends MainMenu
## Main menu extension that adds options and animates the title and menu fading in.
## The animation can be skipped by the player with any input.
##
## Adapted for this project from the vendored Maaack template variant: the
## template's example gameplay-state hooks (Continue / Level Select) are not
## used this round, so those buttons stay hidden. 'New Game' opens the mode
## select menu through the exported game_scene_path override. Template
## structure and animations are kept unchanged.

## Optional scene to open when the player clicks a 'Level Select' button.
@export var level_select_packed_scene: PackedScene
## If true, have the player confirm before starting a new game if a game is in progress.
@export var confirm_new_game : bool = true

var animation_state_machine : AnimationNodeStateMachinePlayback

@onready var continue_game_button = %ContinueGameButton
@onready var level_select_button = %LevelSelectButton
@onready var new_game_confirmation = %NewGameConfirmation

func new_game() -> void:
	if confirm_new_game and continue_game_button.visible:
		new_game_confirmation.show()
	else:
		load_game_scene()

func intro_done() -> void:
	animation_state_machine.travel("OpenMainMenu")
	menu_buttons_box_container.lock = false

func _is_in_intro() -> bool:
	return animation_state_machine.get_current_node() == "Intro"

func _event_skips_intro(event : InputEvent) -> bool:
	return event.is_action_released("ui_accept") or \
		event.is_action_released("ui_select") or \
		event.is_action_released("ui_cancel") or \
		_event_is_mouse_button_released(event)

func _open_sub_menu(menu : PackedScene) -> Node:
	animation_state_machine.travel("OpenSubMenu")
	return super._open_sub_menu(menu)

func _close_sub_menu() -> void:
	super._close_sub_menu()
	animation_state_machine.travel("OpenMainMenu")

func _input(event : InputEvent) -> void:
	if _is_in_intro() and _event_skips_intro(event):
		intro_done()
		return
	super._input(event)

func _show_level_select_if_set() -> void:
	level_select_button.visible = level_select_packed_scene != null

func _show_continue_if_set() -> void:
	continue_game_button.visible = false

func _ready() -> void:
	super._ready()
	_show_level_select_if_set()
	_show_continue_if_set()
	animation_state_machine = $MenuAnimationTree.get("parameters/playback")

func _on_continue_game_button_pressed() -> void:
	load_game_scene()

func _on_level_select_button_pressed() -> void:
	if level_select_packed_scene == null:
		return
	var level_select_scene := _open_sub_menu(level_select_packed_scene)
	if level_select_scene.has_signal("level_selected"):
		level_select_scene.connect("level_selected", load_game_scene)

func _on_new_game_confirmation_confirmed() -> void:
	load_game_scene()
