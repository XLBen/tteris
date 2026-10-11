class_name HudLayout
extends RefCounted
## Helpers shared by the layout binding scripts.


## Runs the container layout of `root`'s subtree right now instead of on the
## next frame, so positions read just after a layout was added are final.
static func settle(root: Control) -> void:
	# Parents place their children, so two top-down passes settle nested
	# containers whose minimum size depends on their children.
	for i: int in 2:
		_sort(root)


static func _sort(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child: Node in node.get_children():
		_sort(child)


## Fits a full-screen layout to the viewport it is shown in and keeps it so.
static func fill_viewport(root: Control) -> void:
	var viewport: Viewport = root.get_viewport()
	if viewport == null:
		return
	root.position = Vector2.ZERO
	root.size = viewport.get_visible_rect().size
	settle(root)


## Adds a BoardView sized to `slot` (a 10-column playfield) inside it.
static func add_board(slot: Control) -> BoardView:
	var board: BoardView = BoardView.new()
	board.name = "Board"
	board.cell_size = floorf(slot.size.x / 10.0)
	slot.add_child(board)
	return board
