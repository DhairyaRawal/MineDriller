class_name ShopScreen
extends CanvasLayer
## ShopScreen: the surface shop. One card per upgrade track with level pips,
## description, and a buy button; refreshes live as money changes. Selling
## happens automatically on surfacing (see Game), so the shop is purely for
## spending.
##
## Landscape layout: the tracks sit in a two-column grid of compact cards, so
## all seven are visible at once on the 720px-tall web canvas -- no scrolling
## to find the one you can afford.

signal closed

var _money_label: Label
var _rows := {}  # upgrade id -> {level_label, pips, buy_button, desc}


func _ready() -> void:
	layer = 20
	var col := UIKit.screen(self, "SURFACE SHOP")
	_money_label = UIKit.label("", 22, UIKit.GOOD)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_money_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	for id: String in GameState.upgrade_levels:
		grid.add_child(_make_row(id))

	var foot := UIKit.footer()
	col.add_child(foot)
	# Cosmetics spend ether, not money -- say so on the button itself rather
	# than in a separate caption that costs a row.
	var cosmetics_btn := UIKit.action_button("CUSTOMIZE DRILL  (ether)", false, 280, 18)
	cosmetics_btn.pressed.connect(_open_cosmetics)
	foot.add_child(cosmetics_btn)
	var close := UIKit.action_button("BACK TO MINING", true, 280, 20)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	foot.add_child(close)

	Events.money_changed.connect(func(_m: int) -> void: _refresh())
	Events.upgrade_purchased.connect(func(_id: String, _lvl: int) -> void: _refresh())
	_refresh()


func _make_row(id: String) -> PanelContainer:
	var u: Dictionary = Balance.upgrades[id]
	var panel := UIKit.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UIKit.hbox(14)
	panel.add_child(row)

	# Per-track icon (generated in tools/generate_assets.py).
	var icon := TextureRect.new()
	var icon_path := "res://assets/textures/icon_%s.png" % id
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var info := UIKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_row := UIKit.hbox(10)
	info.add_child(name_row)
	name_row.add_child(UIKit.label(String(u["name"]), 19))
	var level_label := UIKit.label("", 14, UIKit.TEXT_DIM)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(level_label)

	var pips := UIKit.hbox(4)
	info.add_child(pips)
	info.add_child(UIKit.wrapped(String(u["desc"]), 14, UIKit.TEXT_DIM))

	var buy := UIKit.button("", 17, true)
	buy.custom_minimum_size = Vector2(112, 40)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
			pip.custom_minimum_size = Vector2(20, 6)
			pip.color = UIKit.ACCENT if i < level else Color(0.28, 0.26, 0.32)
			pips.add_child(pip)
		var buy: Button = widgets["buy"]
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		elif GameState.ftue_mode and id != FTUE.TARGET_UPGRADE:
			# The tutorial level holds a fixed amount of ore, worth only a little
			# more than the upgrade it teaches. Spending it on anything else would
			# leave the player unable to ever afford the Drill Bit -- a softlock.
			buy.text = "LATER"
			buy.disabled = true
		else:
			buy.text = "%d $" % cost
			buy.disabled = GameState.money < cost


func _open_cosmetics() -> void:
	var screen := CosmeticsScreen.new()
	screen.closed.connect(_refresh)
	add_child(screen)
