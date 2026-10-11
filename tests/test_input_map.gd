extends SceneTree

const MODULE_NAME: String = "input_map"

# korobeiniki-hud-input freeze (binding record §C + contract P-03): the full
# expected gameplay InputMap, frozen from the CURRENT project.godot with the
# two swapped arrow keycodes corrected — rotate = X (88) + W (87) + Up-arrow
# (4194320), soft_drop = S (83) + Down-arrow (4194322). Every other action is
# frozen exactly as it stands today (baseline BEFORE the implementation edit).
# G-PAUSE-KBD-FIX (owner report 2026-09-17): restart's Enter binding was
# removed so Enter in the pause UI executes the focused action instead of
# restarting; restart is R (82) only.
const EXPECTED_ACTIONS: Dictionary = {
	"move_left": [65, 4194319],
	"move_right": [68, 4194321],
	"soft_drop": [83, 4194322],
	"rotate": [88, 87, 4194320],
	"rotate_ccw": [90],
	"hard_drop": [32],
	"hold": [67, 4194325],
	"pause": [80, 4194305],
	"restart": [82],
}


func _initialize() -> void:
	var result: Dictionary = await run_module()
	for line: String in (result["lines"] as Array):
		print(line)
	if int(result["failed"]) > 0:
		print("FAILED: %d of %d input-map cases" % [int(result["failed"]), int(result["total"])])
		quit(1)
		return
	print("INPUT MAP TESTS PASSED (%d)" % int(result["total"]))
	quit(0)


static func run_module() -> Dictionary:
	var ctx: Dictionary = {"total": 0, "failed": 0, "lines": []}
	for action: String in EXPECTED_ACTIONS:
		_case_action_exact(ctx, action, EXPECTED_ACTIONS[action])
	_case_no_extra_gameplay_actions(ctx)
	return ctx


static func _case(ctx: Dictionary, case_name: String, ok: bool) -> void:
	ctx["total"] = int(ctx["total"]) + 1
	if ok:
		(ctx["lines"] as Array).append("PASS %s" % case_name)
	else:
		ctx["failed"] = int(ctx["failed"]) + 1
		(ctx["lines"] as Array).append("FAILED: %s" % case_name)


static func _physical_keycodes(action: String) -> Array:
	var found: Array = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			found.append(int((event as InputEventKey).physical_keycode))
		else:
			found.append(-1)
	found.sort()
	return found


static func _case_action_exact(ctx: Dictionary, action: String, expected: Array) -> void:
	var ok: bool = InputMap.has_action(action)
	if ok:
		var actual: Array = _physical_keycodes(action)
		var expected_sorted: Array = (expected as Array).duplicate()
		expected_sorted.sort()
		ok = actual.size() == expected_sorted.size()
		if ok:
			for i: int in range(actual.size()):
				if int(actual[i]) != int(expected_sorted[i]):
					ok = false
					break
	_case(ctx, "input_map_%s_exact" % action, ok)


static func _case_no_extra_gameplay_actions(ctx: Dictionary) -> void:
	var expected_names: Array = EXPECTED_ACTIONS.keys()
	expected_names.sort()
	var custom: Array = []
	for action: String in InputMap.get_actions():
		if not action.begins_with("ui_"):
			custom.append(action)
	custom.sort()
	var ok: bool = custom.size() == expected_names.size()
	if ok:
		for i: int in range(custom.size()):
			if String(custom[i]) != String(expected_names[i]):
				ok = false
				break
	_case(ctx, "input_map_no_extra_or_missing_gameplay_actions", ok)
