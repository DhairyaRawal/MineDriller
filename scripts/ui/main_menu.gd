extends Control
## MainMenu: title screen with Dive / Daily Challenge, plus Codex,
## Achievements, Statistics and Settings panels. The codex carries short
## geology notes per ore/layer — the GDD wants the game to teach a little
## Earth science.
##
## Landscape layout: the menu is one compact centred column, and its panels
## open as an overlay on top rather than in whatever height is left under the
## buttons -- on a 720px-tall screen that was almost nothing.

## All teaching copy lives in data/codex.json (see Balance.ore_facts /
## Balance.layer_facts) so the science can be reviewed and edited without
## touching UI code, and so the codex, Discovery Cards and the quiz can never
## drift out of sync with each other.

const PANEL_SIZE := Vector2(1040, 630)
const MENU_WIDTH := 440

var _panel_holder: Control


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := UIKit.vbox(10)
	col.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	center.add_child(col)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.png")
	icon.custom_minimum_size = Vector2(0, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	col.add_child(icon)
	col.add_child(UIKit.title("MINEDRILLER", 48))
	var tagline := UIKit.label("Drill deep. Stay cool. Get rich.", 17, UIKit.TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tagline)
	col.add_child(_gap(6))

	var dive := UIKit.button("DIVE", 26, true)
	dive.pressed.connect(func() -> void: _start_game(false))
	col.add_child(dive)

	var daily := UIKit.button("DAILY CHALLENGE", 18)
	daily.pressed.connect(func() -> void: _start_game(true))
	col.add_child(daily)

	# DIVE resumes the persistent world (saved position, dug tunnels, cargo,
	# depots) if there is one. NEW DRILLING keeps upgrades/money/stats but
	# re-seeds a fresh world -- distinct from RESET SAVE DATA in Options,
	# which wipes progression too.
	var new_drilling := UIKit.button("NEW DRILLING", 16)
	new_drilling.pressed.connect(_confirm_new_drilling)
	col.add_child(new_drilling)

	# The log sits directly under DIVE, at full width: it is a headline feature
	# of the game, not a menu afterthought buried with Options.
	var log_btn := UIKit.button("GEOLOGIST'S LOG   +ether", 18)
	log_btn.pressed.connect(_show_quiz)
	col.add_child(log_btn)

	var row := UIKit.hbox(8)
	col.add_child(row)
	for entry: Array in [["CODEX", _show_codex], ["AWARDS", _show_achievements],
			["STATS", _show_stats], ["OPTIONS", _show_settings]]:
		var b := UIKit.button(entry[0], 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(entry[1])
		row.add_child(b)

	_panel_holder = Control.new()
	_panel_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_holder)

	GameState.daily_mode = false
	# Arriving here mid-tutorial means the player quit out of it. Put the real
	# state back so the menu's panels don't show sandbox numbers.
	GameState.abandon_ftue()
	AudioManager.play_music()


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _panel_holder.get_child_count() > 0:
		get_viewport().set_input_as_handled()
		_clear_panel()


# ------------------------------------------------------------------ panels

func _clear_panel() -> void:
	for child in _panel_holder.get_children():
		child.queue_free()


## Opens an overlay panel and returns its body, which is sized to fit: every
## panel lays its content out to fit PANEL_SIZE rather than scrolling.
func _open_panel(title_text: String) -> VBoxContainer:
	_clear_panel()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_holder.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.flat_style(UIKit.PANEL, 16, 24, 18))
	panel.custom_minimum_size = PANEL_SIZE
	center.add_child(panel)
	var outer := UIKit.vbox(12)
	panel.add_child(outer)
	var head := UIKit.hbox(10)
	outer.add_child(head)
	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(44, 0)  # balances the X so the title centres
	head.add_child(left_pad)
	var t := UIKit.title(title_text, 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.button("X", 17)
	close.custom_minimum_size = Vector2(44, 40)
	close.pressed.connect(_clear_panel)
	head.add_child(close)
	var body := UIKit.vbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	return body


## List on the left, one page on the right. The codex used to be a single
## scrolling column of every ore and layer at full length; this shows the
## whole index at once and only one page of reading.
func _show_codex() -> void:
	var body := _open_panel("RESOURCE CODEX")
	var split := UIKit.hbox(22)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)

	var index := UIKit.vbox(5)
	index.custom_minimum_size = Vector2(250, 0)
	split.add_child(index)
	var page_panel := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95), 14)
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(page_panel)
	var page := UIKit.vbox(10)
	page_panel.add_child(page)

	var group := ButtonGroup.new()
	var found := GameState.codex_discovered.size()
	var total := Balance.ores.size()
	index.add_child(UIKit.label("ORES   %d / %d found" % [found, total], 15,
		UIKit.GOOD if found == total else UIKit.ACCENT))
	var first: Button = null
	for ore_id: String in Balance.ores:
		var known: bool = ore_id in GameState.codex_discovered
		var ore_name := String(Balance.ore_facts(ore_id).get("title", Balance.ores[ore_id]["name"]))
		var b := UIKit.list_button(ore_name if known else "? ? ?", group)
		b.pressed.connect(func() -> void: _fill_page(page, _codex_ore_page(ore_id)))
		index.add_child(b)
		if first == null:
			first = b

	index.add_child(_gap(4))
	index.add_child(UIKit.label("EARTH'S LAYERS", 15, UIKit.ACCENT))
	var deepest := Balance.layer_id_for_km(float(GameState.stats["deepest_km"]))
	for layer: Dictionary in Balance.layers:
		var lid := int(layer["id"])
		var reached := lid <= deepest
		var layer_name := String(Balance.layer_facts(lid).get("title", layer["name"]))
		var b := UIKit.list_button(layer_name if reached else "Layer %d - not reached" % lid, group)
		b.pressed.connect(func() -> void: _fill_page(page, _codex_layer_page(layer, reached)))
		index.add_child(b)

	first.button_pressed = true
	_fill_page(page, _codex_ore_page(String(Balance.ores.keys()[0])))


func _fill_page(page: VBoxContainer, content: Array[Control]) -> void:
	for child in page.get_children():
		child.queue_free()
	for c in content:
		page.add_child(c)


## One codex page. Undiscovered ores stay silhouetted so there is something
## visibly missing to go and find - an open loop is a better motivator than a
## blank row.
func _codex_ore_page(ore_id: String) -> Array[Control]:
	var ore: Dictionary = Balance.ores[ore_id]
	var facts := Balance.ore_facts(ore_id)
	var known: bool = ore_id in GameState.codex_discovered
	var out: Array[Control] = []

	var head := UIKit.hbox(16)
	out.append(head)
	var art := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/textures/tiles.png")
	atlas.region = Rect2(int(ore["atlas_col"]) * 64, 2 * 64, 64, 64)
	art.texture = atlas
	art.custom_minimum_size = Vector2(72, 72)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not known:
		art.modulate = Color(0.22, 0.20, 0.28)
	head.add_child(art)

	var name_col := UIKit.vbox(2)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(name_col)

	if not known:
		name_col.add_child(UIKit.label("? ? ?", 28, UIKit.TEXT_DIM))
		name_col.add_child(UIKit.wrapped("Somewhere down there. Mine it to unlock this page.",
			16, UIKit.TEXT_DIM))
		return out

	var title_row := UIKit.hbox(12)
	name_col.add_child(title_row)
	title_row.add_child(UIKit.label(String(facts.get("title", ore["name"])), 28, UIKit.ACCENT))
	var symbol := String(facts.get("symbol", ""))
	if symbol != "":
		var sym := UIKit.label(symbol, 16, UIKit.ETHER)
		sym.size_flags_vertical = Control.SIZE_SHRINK_END
		title_row.add_child(sym)
	name_col.add_child(UIKit.label("Sells for %d $" % int(ore["value"]), 16, UIKit.GOOD))

	out.append(UIKit.wrapped(String(facts.get("wow", "")), 19, Color(1.0, 0.90, 0.70)))
	for section: Array in [["HOW IT FORMS", "forms"], ["WHERE ON EARTH", "where"],
			["WHAT WE USE IT FOR", "uses"]]:
		var text := String(facts.get(section[1], ""))
		if text == "":
			continue
		out.append(UIKit.label(String(section[0]), 13, UIKit.ACCENT))
		out.append(UIKit.wrapped(text, 16, UIKit.TEXT_DIM))
	return out


func _codex_layer_page(layer: Dictionary, reached: bool) -> Array[Control]:
	var lid := int(layer["id"])
	var lf := Balance.layer_facts(lid)
	var out: Array[Control] = []
	if not reached:
		out.append(UIKit.label("Layer %d - not reached yet" % lid, 26, UIKit.TEXT_DIM))
		out.append(UIKit.wrapped("Drill down this far to unlock this page.", 17, UIKit.TEXT_DIM))
		return out
	out.append(UIKit.label(String(lf.get("title", layer["name"])), 28, UIKit.ACCENT))
	out.append(UIKit.label("%d - %d km below the surface" % [int(layer["km_start"]),
		int(layer["km_end"])], 16, UIKit.ETHER))
	out.append(UIKit.wrapped(String(lf.get("fact", "")), 19))
	return out


func _show_achievements() -> void:
	var body := _open_panel("ACHIEVEMENTS")
	var unlocked_count := 0
	for id: String in Balance.achievements:
		if id in GameState.achievements_unlocked:
			unlocked_count += 1
	var counter := UIKit.label("%d of %d unlocked" % [unlocked_count, Balance.achievements.size()],
		16, UIKit.TEXT_DIM)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(counter)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for id: String in Balance.achievements:
		var ach: Dictionary = Balance.achievements[id]
		var unlocked: bool = id in GameState.achievements_unlocked
		var cell := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95) if unlocked
			else Color(0.13, 0.12, 0.17, 0.8), 10)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var row := UIKit.hbox(12)
		cell.add_child(row)
		# A drawn dot, not a star glyph: the web build ships only the default
		# font, and a missing glyph renders as an empty box.
		var mark := Panel.new()
		mark.custom_minimum_size = Vector2(14, 14)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.add_theme_stylebox_override("panel", UIKit.flat_style(
			UIKit.ACCENT if unlocked else Color(0.30, 0.28, 0.36), 7, 0, 0))
		row.add_child(mark)
		var info := UIKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label(String(ach["name"]), 17,
			UIKit.TEXT if unlocked else UIKit.TEXT_DIM))
		info.add_child(UIKit.label(String(ach["desc"]), 14, UIKit.TEXT_DIM))


func _show_stats() -> void:
	var body := _open_panel("STATISTICS")
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

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	for entry: Array in rows:
		var cell := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95), 10)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var row := UIKit.hbox(10)
		cell.add_child(row)
		var k := UIKit.label(entry[0], 18, UIKit.TEXT_DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(k)
		row.add_child(UIKit.label(entry[1], 20, UIKit.GOOD))


func _show_settings() -> void:
	var body := _open_panel("OPTIONS")
	var holder := CenterContainer.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(holder)
	var col := UIKit.vbox(18)
	col.custom_minimum_size = Vector2(560, 0)
	holder.add_child(col)
	col.add_child(SettingsPanel.new())
	var reset := UIKit.action_button("RESET SAVE DATA", false, 240, 16)
	reset.pressed.connect(_confirm_reset)
	col.add_child(reset)


func _confirm_reset() -> void:
	var content := UIKit.modal(self, "RESET EVERYTHING?")
	var warn := UIKit.wrapped("All progress, upgrades and money will be wiped.", 18, UIKit.TEXT_DIM)
	warn.custom_minimum_size = Vector2(460, 0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(warn)
	var modal_root: Node = content.get_parent().get_parent().get_parent()
	var buttons := UIKit.footer()
	content.add_child(buttons)
	var yes := UIKit.action_button("YES, RESET", false, 200, 18)
	yes.pressed.connect(func() -> void:
		SaveManager.wipe()
		GameState.from_dict({})
		Events.money_changed.emit(GameState.money)
		modal_root.queue_free()
		_clear_panel())
	buttons.add_child(yes)
	var no := UIKit.action_button("CANCEL", true, 200, 18)
	no.pressed.connect(func() -> void: modal_root.queue_free())
	buttons.add_child(no)


func _confirm_new_drilling() -> void:
	var content := UIKit.modal(self, "START A NEW DRILLING?")
	var warn := UIKit.wrapped(
		"A fresh world will be seeded -- your current dive's position, dug "
		+ "tunnels, cargo and depots will be replaced. Money, upgrades, "
		+ "stats and the codex are kept.", 18, UIKit.TEXT_DIM)
	warn.custom_minimum_size = Vector2(460, 0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(warn)
	var modal_root: Node = content.get_parent().get_parent().get_parent()
	var buttons := UIKit.footer()
	content.add_child(buttons)
	var yes := UIKit.action_button("YES, START FRESH", false, 200, 18)
	yes.pressed.connect(func() -> void:
		GameState.start_new_drilling()
		modal_root.queue_free()
		_start_game(false))
	buttons.add_child(yes)
	var no := UIKit.action_button("CANCEL", true, 200, 18)
	no.pressed.connect(func() -> void: modal_root.queue_free())
	buttons.add_child(no)
