class_name DepotScreen
extends CanvasLayer
## DepotScreen: bank ore at a safe-spot depot. Deposited ore leaves `cargo`
## (so a bust can never touch it -- lose_cargo() only ever clears `cargo`)
## but isn't money yet: it has to be withdrawn back into cargo and carried to
## the surface to sell, same as any other ore. Pauses the tree while open,
## like MapScreen/DiscoveryCard -- a menu shouldn't run enemies/heat in the
## background mid-dive.

signal closed

var _depot_id: String
var _capacity_label: Label
var _cargo_list: VBoxContainer
var _depot_list: VBoxContainer


func _init(depot_id: String) -> void:
	_depot_id = depot_id


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var col := UIKit.vbox(16)
	margin.add_child(col)
	col.add_child(UIKit.title("SAFE-SPOT DEPOT"))
	_capacity_label = UIKit.label("", 22, UIKit.TEXT_DIM)
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_capacity_label)
	var hint := UIKit.label(
		"Deposited ore is safe here even if you bust -- withdraw it and carry it "
		+ "to the surface to sell.", 18, UIKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var outer := UIKit.vbox(18)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	outer.add_child(UIKit.label("CARGO → deposit", 24, UIKit.ACCENT))
	_cargo_list = UIKit.vbox(10)
	_cargo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_cargo_list)

	outer.add_child(HSeparator.new())

	outer.add_child(UIKit.label("DEPOT → withdraw", 24, UIKit.ACCENT))
	_depot_list = UIKit.vbox(10)
	_depot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_depot_list)

	var close := UIKit.button("DONE", 32, true)
	close.pressed.connect(func() -> void:
		get_tree().paused = false
		closed.emit()
		queue_free())
	col.add_child(close)

	get_tree().paused = true
	_refresh()


func _cargo_counts() -> Dictionary:
	var counts := {}
	for ore_id: String in GameState.cargo:
		counts[ore_id] = int(counts.get(ore_id, 0)) + 1
	return counts


func _refresh() -> void:
	_capacity_label.text = "Cargo %d/%d    Depot %d/%d" % [
		GameState.cargo.size(), GameState.cargo_capacity(),
		GameState.depot_used(_depot_id), GameState.depot_capacity()]

	for child in _cargo_list.get_children():
		child.queue_free()
	var cargo_counts := _cargo_counts()
	if cargo_counts.is_empty():
		_cargo_list.add_child(UIKit.label("Nothing in cargo.", 20, UIKit.TEXT_DIM))
	for ore_id: String in cargo_counts:
		_cargo_list.add_child(_make_row(ore_id, int(cargo_counts[ore_id]), true))

	for child in _depot_list.get_children():
		child.queue_free()
	var bin: Dictionary = GameState.depot_storage.get(_depot_id, {})
	if bin.is_empty():
		_depot_list.add_child(UIKit.label("Nothing banked here yet.", 20, UIKit.TEXT_DIM))
	for ore_id: String in bin:
		_depot_list.add_child(_make_row(ore_id, int(bin[ore_id]), false))


func _make_row(ore_id: String, count: int, is_cargo: bool) -> HBoxContainer:
	var ore: Dictionary = Balance.ores[ore_id]
	var row := UIKit.hbox(12)
	var name_label := UIKit.label("%s x%d" % [String(ore["name"]), count], 24)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var btn := UIKit.button("DEPOSIT" if is_cargo else "WITHDRAW", 20)
	btn.custom_minimum_size = Vector2(160, 76)
	btn.pressed.connect(func() -> void:
		var ok := GameState.deposit_ore(_depot_id, ore_id) if is_cargo \
			else GameState.withdraw_ore(_depot_id, ore_id)
		if ok:
			SettingsManager.vibrate(25)
			_refresh()
		else:
			AudioManager.play("click", -6.0, 0.6))
	row.add_child(btn)
	return row
