extends Node
## Keeps mouse hover and keyboard focus on the same button.
##
## Project-authored autoload (ui-fx-hud-fix): a Button highlights on hover while
## keyboard/joypad focus stays wherever it was, so the highlighted button and
## the focused one can differ. This node connects every Button's mouse_entered
## to a handler that grabs focus, making hover and keyboard focus the same
## button. CheckBox/CheckButton extend Button, so they are covered too.
##
## Popup windows keep their exclusive behavior: the Maaack PopupWindowPanel
## sets other controls' focus_mode to FOCUS_NONE while a window is open, and
## the handler only acts on buttons that are inside the tree, visible in it,
## and not FOCUS_NONE. Nothing here touches the mouse or the OS, so it is safe
## under --headless.
##
## Pause-menu confirmations (G-PAUSE-KBD-FIX): a Maaack
## ConfirmationPopupWindowPanel focuses its first focusable button, which is
## its Cancel/Close button, so Enter would cancel instead of confirming. For
## the pause menu's confirmations only (gated by the parent script), this node
## also grabs confirm_button once the window is shown. The options menu's
## KeyAssignmentWindow extends the same class but must keep focusing its own
## InputTextEdit, so it is deliberately excluded by that gate.

const MAX_DEPTH: int = 16
const PAUSE_MENU_SCRIPT_PATH: String = "res://scenes/windows/pause_menu.gd"


func _ready() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	# Existing tree: node_added only covers nodes added after this autoload
	# finished _ready().
	_scan_existing(tree.root, 0)


func _scan_existing(node: Node, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	_wire_button(node)
	_wire_confirmation(node)
	for child: Node in node.get_children():
		_scan_existing(child, depth + 1)


func _on_node_added(node: Node) -> void:
	_wire_button(node)
	_wire_confirmation(node)


func _wire_confirmation(node: Node) -> void:
	var confirmation: ConfirmationPopupWindowPanel = node as ConfirmationPopupWindowPanel
	if confirmation == null:
		return
	var parent: Node = confirmation.get_parent()
	if parent == null:
		return
	var parent_script: Script = parent.get_script() as Script
	if parent_script == null or parent_script.resource_path != PAUSE_MENU_SCRIPT_PATH:
		return
	var handler: Callable = _on_confirmation_visibility_changed.bind(confirmation)
	if not confirmation.visibility_changed.is_connected(handler):
		confirmation.visibility_changed.connect(handler)


func _on_confirmation_visibility_changed(confirmation: ConfirmationPopupWindowPanel) -> void:
	# Only the pause menu's three confirmations reach this handler: their first
	# focusable button is Cancel, so Enter would cancel instead of executing
	# the selected action. Wait one frame so the window's own focus handling
	# settles, then put the focus on Confirm. Options' KeyAssignmentWindow
	# extends the same class but keeps its own InputTextEdit focus because
	# _wire_confirmation only wires children of the pause menu script.
	if not is_instance_valid(confirmation) or not confirmation.is_visible_in_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(confirmation) or not confirmation.is_visible_in_tree():
		return
	var confirm_button: Button = confirmation.confirm_button
	if confirm_button != null and confirm_button.is_visible_in_tree():
		confirm_button.grab_focus()


func _wire_button(node: Node) -> void:
	var button: Button = node as Button
	if button == null:
		return
	var handler: Callable = _on_button_mouse_entered.bind(button)
	if not button.mouse_entered.is_connected(handler):
		button.mouse_entered.connect(handler)


func _on_button_mouse_entered(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	if not button.is_visible_in_tree():
		return
	if button.focus_mode == Control.FOCUS_NONE:
		return
	if button.get_viewport().gui_get_focus_owner() == button:
		return
	button.grab_focus()
