class_name CosmeticsScreen
extends CanvasLayer
## CosmeticsScreen: the ether store. Ether is earned from Ruby / Black Opal
## (per the GDD) and spends ONLY here — cosmetics never touch drill stats, so
## the economy stays honest and the shop never becomes pay-to-win.
##
## Landscape layout: skins and trails side by side, so both lists are fully
## visible without scrolling.

signal closed

var _ether_label: Label
var _list: HBoxContainer


func _ready() -> void:
	layer = 25
	var col := UIKit.screen(self, "DRILL WORKSHOP")

	_ether_label = UIKit.label("", 22, UIKit.ETHER)
	_ether_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_ether_label)

	var hint := UIKit.label("Ether comes from Rubies and Black Opals. Looks only - never stats.",
		14, UIKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

	_list = UIKit.hbox(24)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_list)

	var foot := UIKit.footer()
	col.add_child(foot)
	var close := UIKit.action_button("BACK")
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	foot.add_child(close)

	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	for section: Array in [["DRILL SKINS", "drill_skin", "drill_skins"],
			["DRILL TRAILS", "trail", "trails"]]:
		var column := UIKit.vbox(8)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(column)
		column.add_child(UIKit.label(String(section[0]), UIKit.FONT_HEADING, UIKit.ACCENT))
		var table: Dictionary = Balance.cosmetics[section[2]]
		for id: String in table:
			column.add_child(_make_row(String(section[1]), id, table[id]))

	_refresh()


func _make_row(category: String, id: String, info: Dictionary) -> PanelContainer:
	var owned := _is_owned(category, id)
	var equipped := _is_equipped(category, id)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.flat_style(UIKit.PANEL, 10, 14, 7))
	var row := UIKit.hbox(12)
	panel.add_child(row)

	# Skins get a live preview of the actual in-game sprite.
	if category == "drill_skin":
		var preview := TextureRect.new()
		var path := "res://assets/textures/player_%s.png" % id
		if ResourceLoader.exists(path):
			preview.texture = load(path)
		preview.custom_minimum_size = Vector2(44, 44)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not owned:
			preview.modulate = Color(0.35, 0.35, 0.40)   # silhouette when locked
		row.add_child(preview)

	var info_col := UIKit.vbox(0)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info_col)

	var title_row := UIKit.hbox(10)
	info_col.add_child(title_row)
	title_row.add_child(UIKit.label(String(info["name"]), 18))
	if equipped:
		var tag := UIKit.label("EQUIPPED", 13, UIKit.GOOD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tag)

	info_col.add_child(UIKit.wrapped(String(info["desc"]), 14, UIKit.TEXT_DIM))

	var action := UIKit.button("", 16, not owned)
	action.custom_minimum_size = Vector2(104, 38)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.pressed.connect(func() -> void: _on_row_pressed(category, id))
	action.set_meta("category", category)
	action.set_meta("id", id)
	row.add_child(action)
	return panel


func _on_row_pressed(category: String, id: String) -> void:
	if _is_owned(category, id):
		if _is_equipped(category, id):
			return
		var ok := GameState.select_drill_skin(id) if category == "drill_skin" \
			else GameState.select_trail_effect(id)
		if ok:
			AudioManager.play("click")
			SettingsManager.vibrate(25)
			_rebuild()
		return

	var bought := GameState.buy_drill_skin(id) if category == "drill_skin" \
		else GameState.buy_trail_effect(id)
	if bought:
		# Buying equips immediately - nobody wants a two-tap purchase.
		if category == "drill_skin":
			GameState.select_drill_skin(id)
		else:
			GameState.select_trail_effect(id)
		AudioManager.play("upgrade")
		SettingsManager.vibrate(45)
		Events.toast.emit("Unlocked: %s" % _info(category, id)["name"])
		_rebuild()
	else:
		AudioManager.play("click", -4.0, 0.6)


func _refresh() -> void:
	_ether_label.text = "%d ether" % GameState.ether
	for button in _find_buttons(_list):
		var category := String(button.get_meta("category"))
		var id := String(button.get_meta("id"))
		var info := _info(category, id)
		var cost := int(info["cost"])
		if _is_equipped(category, id):
			button.text = "ON"
			button.disabled = true
		elif _is_owned(category, id):
			button.text = "EQUIP"
			button.disabled = false
		else:
			button.text = "%d E" % cost
			button.disabled = GameState.ether < cost


func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		# Rows queued for deletion by _rebuild are still children this frame.
		if child.is_queued_for_deletion():
			continue
		if child is Button and child.has_meta("id"):
			out.append(child)
		else:
			out.append_array(_find_buttons(child))
	return out


func _info(category: String, id: String) -> Dictionary:
	var table := "drill_skins" if category == "drill_skin" else "trails"
	return Balance.cosmetics[table][id]


func _is_owned(category: String, id: String) -> bool:
	return id in (GameState.drill_skin_owned if category == "drill_skin"
		else GameState.trail_effect_owned)


func _is_equipped(category: String, id: String) -> bool:
	return id == (GameState.drill_skin_selected if category == "drill_skin"
		else GameState.trail_effect_selected)
