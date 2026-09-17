class_name PauseMenu
extends CanvasLayer
## PauseMenu: pause overlay with inline settings, a controls reference, the
## GUIDE, and a quit-to-menu path. Runs while the tree is paused.
##
## Two columns, not one: the landscape viewport is 720px tall but 1280px wide.
## Stacking the controls under the settings would overflow the height, while a
## CONTROLS button would bury them behind a click -- side by side, they're
## visible the moment the game is paused.

signal resumed
signal quit_to_menu

## Each row is [what it does, how]. "How" is either a list of InputMap actions,
## whose keys are read from the live bindings -- so this panel can never
## disagree with what the keys actually do -- or, for combos and mouse actions
## that aren't a single binding, a literal string.
## Two-action rows (left/right) are paired by binding order: "A / D  or  ← / →".
const CONTROLS := [
	["Move", ["move_left", "move_right"]],
	["Drill down", ["move_down"]],
	["Jump", ["move_up"]],
	["Drill sideways", "push into a wall"],
	["Carve a ramp up", "hold  ↑  + a direction into a wall"],
	["Escape rocket", ["fire_rocket"]],
	["Open a depot", ["interact"]],
	["Read nearest tip", ["show_tip"]],
	["Pause / resume", ["pause"]],
	["Map, Shop, Depot", "click the buttons"],
]


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	var content := UIKit.modal(self, "PAUSED")

	var columns := UIKit.hbox(32)
	content.add_child(columns)

	var left := UIKit.vbox(18)
	left.custom_minimum_size = Vector2(460, 0)
	columns.add_child(left)
	left.add_child(SettingsPanel.new())

	var resume := UIKit.button("RESUME", 32, true)
	resume.pressed.connect(_on_resume)
	left.add_child(resume)

	var row := UIKit.hbox(12)
	left.add_child(row)
	var guide := UIKit.button("GUIDE", 26)
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide.pressed.connect(func() -> void: add_child(GuideScreen.new()))
	row.add_child(guide)
	var quit := UIKit.button("QUIT TO MENU", 26)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void:
		get_tree().paused = false
		quit_to_menu.emit())
	row.add_child(quit)

	columns.add_child(VSeparator.new())
	columns.add_child(_controls_column())


func _controls_column() -> Control:
	var col := UIKit.vbox(10)
	col.custom_minimum_size = Vector2(420, 0)
	col.add_child(UIKit.label("CONTROLS", 26, UIKit.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 9)
	col.add_child(grid)

	for entry: Array in CONTROLS:
		grid.add_child(UIKit.label(String(entry[0]), 20, UIKit.TEXT_DIM))
		var how: Variant = entry[1]
		var keys := keys_text(how) if how is Array else String(how)
		grid.add_child(UIKit.label(keys, 20))
	return col


## Human-readable keys for one or two actions, read from the live InputMap.
## Public and static so the test suite can check every row resolves.
static func keys_text(actions: Array) -> String:
	if actions.size() == 2:
		var a := _action_keys(String(actions[0]))
		var b := _action_keys(String(actions[1]))
		var pairs: Array[String] = []
		for i in mini(a.size(), b.size()):
			pairs.append("%s / %s" % [a[i], b[i]])
		return "   or   ".join(PackedStringArray(pairs))
	var parts: Array[String] = []
	for action in actions:
		parts.append_array(_action_keys(String(action)))
	return " / ".join(PackedStringArray(parts))


static func _action_keys(action: String) -> Array[String]:
	var names: Array[String] = []
	if not InputMap.has_action(action):
		return names
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			names.append(_key_name((ev as InputEventKey).physical_keycode))
	return names


static func _key_name(code: Key) -> String:
	match code:
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_ESCAPE:
			return "Esc"
	return OS.get_keycode_string(code)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_resume()


func _on_resume() -> void:
	get_tree().paused = false
	resumed.emit()
	queue_free()
