class_name ShopScreen
extends CanvasLayer
## ShopScreen: the surface shop. One row per upgrade track with level pips,
## description, and a buy button; refreshes live as money changes. Selling
## happens automatically on surfacing (see Game), so the shop is purely for
## spending.

signal closed

var _money_label: Label
var _rows := {}  # upgrade id -> {level_label, pips, buy_button, desc}


func _ready() -> void:
	layer = 20
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
	col.add_child(UIKit.title("SURFACE SHOP"))
	_money_label = UIKit.label("", 34, UIKit.GOOD)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_money_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := UIKit.vbox(14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for id: String in GameState.upgrade_levels:
		list.add_child(_make_row(id))

	# Cosmetics section
	var cosmetics_sep := HSeparator.new()
	cosmetics_sep.add_theme_constant_override("separation", 12)
	col.add_child(cosmetics_sep)

	var cosmetics_label := UIKit.label("Cosmetics (Ether Currency)", 20, UIKit.ACCENT)
	cosmetics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cosmetics_label)

	var cosmetics_btn := UIKit.button("CUSTOMIZE DRILL", 28, true)
	cosmetics_btn.pressed.connect(_open_cosmetics)
	col.add_child(cosmetics_btn)

	var close := UIKit.button("BACK TO MINING", 32, true)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	col.add_child(close)

	Events.money_changed.connect(func(_m: int) -> void: _refresh())
	Events.upgrade_purchased.connect(func(_id: String, _lvl: int) -> void: _refresh())
	_refresh()


func _make_row(id: String) -> PanelContainer:
	var u: Dictionary = Balance.upgrades[id]
	var panel := UIKit.panel()
	var row := UIKit.hbox(16)
	panel.add_child(row)

	# Per-track icon (generated in tools/generate_assets.py).
	var icon := TextureRect.new()
	var icon_path := "res://assets/textures/icon_%s.png" % id
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(72, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var info := UIKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_row := UIKit.hbox(12)
	info.add_child(name_row)
	name_row.add_child(UIKit.label(String(u["name"]), 30))
	var level_label := UIKit.label("", 24, UIKit.TEXT_DIM)
	name_row.add_child(level_label)

	var pips := UIKit.hbox(6)
	info.add_child(pips)
	var desc := UIKit.label(String(u["desc"]), 20, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)

	var buy := UIKit.button("", 26, true)
	buy.custom_minimum_size = Vector2(190, 92)
	buy.pressed.connect(func() -> void: _buy(id))
	row.add_child(buy)

	_rows[id] = {"level": level_label, "pips": pips, "buy": buy}
	return panel


func _buy(id: String) -> void:
	if GameState.buy_upgrade(id):
		AudioManager.play("upgrade")
		SettingsManager.vibrate(40)
	else:
		AudioManager.play("click", -4.0, 0.6)


func _refresh() -> void:
	_money_label.text = "%d $   |   %d ether" % [GameState.money, GameState.ether]
	for id: String in _rows:
		var widgets: Dictionary = _rows[id]
		var level := int(GameState.upgrade_levels[id])
		var max_level := Balance.upgrade_max(id)
		var cost := GameState.upgrade_cost(id)
		var level_label: Label = widgets["level"]
		level_label.text = "Lv %d/%d" % [level, max_level]
		var pips: HBoxContainer = widgets["pips"]
		for child in pips.get_children():
			child.queue_free()
		for i in max_level:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(30, 10)
			pip.color = UIKit.ACCENT if i < level else Color(0.28, 0.26, 0.32)
			pips.add_child(pip)
		var buy: Button = widgets["buy"]
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "%d $" % cost
			buy.disabled = GameState.money < cost


func _open_cosmetics() -> void:
	var screen := CosmeticsScreen.new()
	screen.closed.connect(_refresh)
	add_child(screen)
