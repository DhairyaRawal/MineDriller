extends Control
## MainMenu: title screen with Dive / Daily Challenge, plus Codex,
## Achievements, Statistics and Settings panels. The codex carries short
## geology notes per ore/layer — the GDD wants the game to teach a little
## Earth science.

## All teaching copy lives in data/codex.json (see Balance.ore_facts /
## Balance.layer_facts) so the science can be reviewed and edited without
## touching UI code, and so the codex, Discovery Cards and the quiz can never
## drift out of sync with each other.

var _panel_holder: Control


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 40)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var col := UIKit.vbox(16)
	margin.add_child(col)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.png")
	icon.custom_minimum_size = Vector2(0, 170)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(icon)
	col.add_child(UIKit.title("MINEDRILLER", 60))
	var tagline := UIKit.label("Drill deep. Stay cool. Get rich.", 24, UIKit.TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tagline)

	var dive := UIKit.button("DIVE", 40, true)
	dive.pressed.connect(func() -> void: _start_game(false))
	col.add_child(dive)

	var daily := UIKit.button("DAILY CHALLENGE", 28)
	daily.pressed.connect(func() -> void: _start_game(true))
	col.add_child(daily)

	# DIVE resumes the persistent world (saved position, dug tunnels, cargo,
	# depots) if there is one. NEW DRILLING keeps upgrades/money/stats but
	# re-seeds a fresh world -- distinct from RESET SAVE DATA in Options,
	# which wipes progression too.
	var new_drilling := UIKit.button("NEW DRILLING", 22)
	new_drilling.pressed.connect(_confirm_new_drilling)
	col.add_child(new_drilling)

	# The log sits directly under DIVE, at full width: it is a headline feature
	# of the game, not a menu afterthought buried with Options.
	var log_btn := UIKit.button("GEOLOGIST'S LOG   +ether", 26)
	log_btn.pressed.connect(_show_quiz)
	col.add_child(log_btn)

	var row := UIKit.hbox(12)
	col.add_child(row)
	for entry: Array in [["CODEX", _show_codex], ["AWARDS", _show_achievements],
			["STATS", _show_stats], ["OPTIONS", _show_settings]]:
		var b := UIKit.button(entry[0], 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(entry[1])
		row.add_child(b)

	_panel_holder = Control.new()
	_panel_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_panel_holder)

	GameState.daily_mode = false
	# Arriving here mid-tutorial means the player quit out of it. Put the real
	# state back so the menu's panels don't show sandbox numbers.
	GameState.abandon_ftue()
	AudioManager.play_music()


func _start_game(daily: bool) -> void:
	# The tutorial is mandatory on a player's first run. Every way into a run
	# (DIVE, DAILY CHALLENGE, NEW DRILLING) comes through here, so this is the
	# single gate -- there is no way to reach the real world around it.
	if not GameState.tutorial_done:
		GameState.begin_ftue()
	else:
		GameState.daily_mode = daily
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_quiz() -> void:
	add_child(FieldQuiz.new())


# ------------------------------------------------------------------ panels

func _clear_panel() -> void:
	for child in _panel_holder.get_children():
		child.queue_free()


func _open_panel(title_text: String) -> VBoxContainer:
	_clear_panel()
	var panel := UIKit.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_holder.add_child(panel)
	var outer := UIKit.vbox(10)
	panel.add_child(outer)
	var head := UIKit.hbox(10)
	outer.add_child(head)
	var t := UIKit.title(title_text, 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.button("X", 24)
	close.custom_minimum_size = Vector2(72, 60)
	close.pressed.connect(_clear_panel)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := UIKit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _show_codex() -> void:
	var list := _open_panel("RESOURCE CODEX")
	var found := GameState.codex_discovered.size()
	var total := Balance.ores.size()
	var counter := UIKit.label("%d of %d ores discovered" % [found, total],
		22, UIKit.GOOD if found == total else UIKit.TEXT_DIM)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(counter)

	for ore_id: String in Balance.ores:
		list.add_child(_codex_ore_entry(ore_id))

	list.add_child(UIKit.label("EARTH'S LAYERS", 28, UIKit.ACCENT))
	var deepest := Balance.layer_id_for_km(float(GameState.stats["deepest_km"]))
	for layer: Dictionary in Balance.layers:
		var lid := int(layer["id"])
		var lf := Balance.layer_facts(lid)
		var panel := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95), 14)
		list.add_child(panel)
		var col := UIKit.vbox(6)
		panel.add_child(col)
		if lid > deepest:
			col.add_child(UIKit.label("Layer %d - not reached yet" % lid, 22,
				UIKit.TEXT_DIM))
			col.add_child(_wrapped("Drill down this far to unlock this page.",
				19, UIKit.TEXT_DIM))
			continue
		col.add_child(UIKit.label(String(lf.get("title", layer["name"])), 26,
			UIKit.ACCENT))
		col.add_child(UIKit.label("%d - %d km" % [int(layer["km_start"]),
			int(layer["km_end"])], 18, UIKit.ETHER))
		col.add_child(_wrapped(String(lf.get("fact", "")), 20))


## One codex page. Undiscovered ores stay silhouetted so there is something
## visibly missing to go and find - an open loop is a better motivator than a
## blank row.
func _codex_ore_entry(ore_id: String) -> PanelContainer:
	var ore: Dictionary = Balance.ores[ore_id]
	var facts := Balance.ore_facts(ore_id)
	var known: bool = ore_id in GameState.codex_discovered

	var panel := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95), 14)
	var row := UIKit.hbox(14)
	panel.add_child(row)

	var art := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/textures/tiles.png")
	atlas.region = Rect2(int(ore["atlas_col"]) * 64, 2 * 64, 64, 64)
	art.texture = atlas
	art.custom_minimum_size = Vector2(76, 76)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not known:
		art.modulate = Color(0.22, 0.20, 0.28)
	row.add_child(art)

	var col := UIKit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	if not known:
		col.add_child(UIKit.label("? ? ?", 26, UIKit.TEXT_DIM))
		col.add_child(_wrapped("Somewhere down there. Mine it to unlock this page.",
			19, UIKit.TEXT_DIM))
		return panel

	var head := UIKit.hbox(10)
	col.add_child(head)
	var title := UIKit.label(String(facts.get("title", ore["name"])), 27, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.label("%d $" % int(ore["value"]), 23, UIKit.GOOD))

	var symbol := String(facts.get("symbol", ""))
	if symbol != "":
		col.add_child(UIKit.label(symbol, 18, UIKit.ETHER))

	col.add_child(_wrapped(String(facts.get("wow", "")), 21,
		Color(1.0, 0.90, 0.70)))
	for key: String in ["forms", "where", "uses"]:
		var body := String(facts.get(key, ""))
		if body != "":
			col.add_child(_wrapped(body, 19, UIKit.TEXT_DIM))
	return panel


func _wrapped(text: String, size: int, color := UIKit.TEXT) -> Label:
	var l := UIKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _show_achievements() -> void:
	var list := _open_panel("ACHIEVEMENTS")
	for id: String in Balance.achievements:
		var ach: Dictionary = Balance.achievements[id]
		var unlocked: bool = id in GameState.achievements_unlocked
		var row := UIKit.hbox(12)
		list.add_child(row)
		var mark := UIKit.label("[x]" if unlocked else "[ ]", 24,
			UIKit.GOOD if unlocked else UIKit.TEXT_DIM)
		row.add_child(mark)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label(String(ach["name"]), 24,
			UIKit.TEXT if unlocked else UIKit.TEXT_DIM))
		info.add_child(UIKit.label(String(ach["desc"]), 18, UIKit.TEXT_DIM))


func _show_stats() -> void:
	var list := _open_panel("STATISTICS")
	var s := GameState.stats
	var rows := [
		["Total earned", "%d $" % int(s["total_earned"])],
		["Dives completed", str(int(s["dives"]))],
		["Busts", str(int(s["busts"]))],
		["Ores mined", str(int(s["ores_mined"]))],
		["Deepest depth", "%d km" % int(float(s["deepest_km"]))],
		["Treasure vaults found", str(int(s["treasures_found"]))],
		["Play time", "%d min" % int(float(s["playtime_sec"]) / 60.0)],
	]
	var today_best := int(GameState.daily_best.get(GameState.today_key(), 0))
	rows.append(["Today's daily best", "%d $" % today_best])
	for entry: Array in rows:
		var row := UIKit.hbox(10)
		list.add_child(row)
		var k := UIKit.label(entry[0], 24)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(k)
		row.add_child(UIKit.label(entry[1], 24, UIKit.GOOD))


func _show_settings() -> void:
	var list := _open_panel("OPTIONS")
	list.add_child(SettingsPanel.new())
	var reset := UIKit.button("RESET SAVE DATA", 22)
	reset.pressed.connect(_confirm_reset)
	list.add_child(reset)


func _confirm_reset() -> void:
	var content := UIKit.modal(self, "RESET EVERYTHING?")
	var warn := UIKit.label("All progress, upgrades and money will be wiped.", 24, UIKit.TEXT_DIM)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(500, 0)
	content.add_child(warn)
	var modal_root: Node = content.get_parent().get_parent().get_parent()
	var yes := UIKit.button("YES, RESET", 26)
	yes.pressed.connect(func() -> void:
		SaveManager.wipe()
		GameState.from_dict({})
		Events.money_changed.emit(GameState.money)
		modal_root.queue_free()
		_clear_panel())
	content.add_child(yes)
	var no := UIKit.button("CANCEL", 26, true)
	no.pressed.connect(func() -> void: modal_root.queue_free())
	content.add_child(no)


func _confirm_new_drilling() -> void:
	var content := UIKit.modal(self, "START A NEW DRILLING?")
	var warn := UIKit.label(
		"A fresh world will be seeded -- your current dive's position, dug "
		+ "tunnels, cargo and depots will be replaced. Money, upgrades, "
		+ "stats and the codex are kept.", 24, UIKit.TEXT_DIM)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(500, 0)
	content.add_child(warn)
	var modal_root: Node = content.get_parent().get_parent().get_parent()
	var yes := UIKit.button("YES, START FRESH", 26)
	yes.pressed.connect(func() -> void:
		GameState.start_new_drilling()
		modal_root.queue_free()
		_start_game(false))
	content.add_child(yes)
	var no := UIKit.button("CANCEL", 26, true)
	no.pressed.connect(func() -> void: modal_root.queue_free())
	content.add_child(no)
