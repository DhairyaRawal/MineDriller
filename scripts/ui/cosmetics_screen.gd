class_name CosmeticsScreen
extends CanvasLayer
## CosmeticsScreen: the ether store. Ether is earned from Ruby / Black Opal
## (per the GDD) and spends ONLY here — cosmetics never touch drill stats, so
## the economy stays honest and the shop never becomes pay-to-win.

signal closed

var _ether_label: Label
var _list: VBoxContainer


func _ready() -> void:
	layer = 25
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
	col.add_child(UIKit.title("DRILL WORKSHOP"))

	_ether_label = UIKit.label("", 30, UIKit.ETHER)
	_ether_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_ether_label)

	var hint := UIKit.label("Ether comes from Rubies and Black Opals. Looks only - never stats.",
		18, UIKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = UIKit.vbox(14)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close := UIKit.button("BACK", 30, true)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	col.add_child(close)

	_rebuild()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	_list.add_child(UIKit.label("DRILL SKINS", 24, UIKit.ACCENT))
	for id: String in Balance.cosmetics["drill_skins"]:
		_list.add_child(_make_row("drill_skin", id, Balance.cosmetics["drill_skins"][id]))

	_list.add_child(UIKit.label("DRILL TRAILS", 24, UIKit.ACCENT))
	for id: String in Balance.cosmetics["trails"]:
		_list.add_child(_make_row("trail", id, Balance.cosmetics["trails"][id]))

	_refresh()


func _make_row(category: String, id: String, info: Dictionary) -> PanelContainer:
	var owned := _is_owned(category, id)
	var equipped := _is_equipped(category, id)

	var panel := UIKit.panel()
	var row := UIKit.hbox(16)
	panel.add_child(row)

	# Skins get a live preview of the actual in-game sprite.
	if category == "drill_skin":
		var preview := TextureRect.new()
		var path := "res://assets/textures/player_%s.png" % id
		if ResourceLoader.exists(path):
			preview.texture = load(path)
		preview.custom_minimum_size = Vector2(72, 72)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not owned:
			preview.modulate = Color(0.35, 0.35, 0.40)   # silhouette when locked
		row.add_child(preview)

	var info_col := UIKit.vbox(4)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_col)

	var title_row := UIKit.hbox(12)
	info_col.add_child(title_row)
	title_row.add_child(UIKit.label(String(info["name"]), 28))
	if equipped:
		title_row.add_child(UIKit.label("EQUIPPED", 18, UIKit.GOOD))

	var desc := UIKit.label(String(info["desc"]), 19, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_col.add_child(desc)

	var action := UIKit.button("", 24, not owned)
	action.custom_minimum_size = Vector2(190, 92)
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
	for panel in _list.get_children():
		if panel is not PanelContainer:
			continue
		for button in _find_buttons(panel):
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
