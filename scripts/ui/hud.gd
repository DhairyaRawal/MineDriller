class_name HUD
extends CanvasLayer
## HUD: in-run interface. Top status cluster (money, ether, depth, cargo,
## hull, rockets, next-upgrade target), the heat/cooldown bar with its
## ambient-floor marker (the GDD's shrinking cooldown bar made visible),
## contextual Shop/Depot buttons, pause button, and toast messages.
##
## Web build: input is keyboard/mouse, so there are no on-screen D-pads.

signal pause_pressed
signal shop_pressed
signal depot_pressed
signal map_pressed

var _money_label: Label
var _ether_label: Label
var _depth_label: Label
var _layer_label: Label
var _cargo_label: Label
var _target_label: Label
var _target_bar: ProgressBar
var _hull_box: HBoxContainer
var _heat_bar: HeatBar
var _heat_caption: Label
var _top: PanelContainer
var _toast_label: Label
var _warning_rect: ColorRect
var _shop_button: Button
var _depot_button: Button
var _rocket_label: Label
var _objective_panel: PanelContainer
var _objective_label: Label
var _toast_queue: Array[String] = []
var _toast_busy := false


class HeatBar:
	extends Control
	## The GDD's cooldown bar, and the loudest thing on screen by design:
	## overheating is the primary way you lose a run, so it gets the strongest
	## contrast and a pulse once it crosses the warning threshold.
	##
	## Reads left to right: the dim red zone is the ambient floor you physically
	## cannot cool below at this depth (that is the "bar shrinks with depth"
	## rule made visible), the bright fill is current heat, the notch is the
	## warning line, and everything past it is the margin before the drill blows.
	var heat := 0.0
	var floor_heat := 0.0
	var max_heat := 100.0
	var warning := 80.0
	var _pulse := 0.0

	func _process(delta: float) -> void:
		if heat >= warning:
			_pulse = fmod(_pulse + delta * 4.0, TAU)
			queue_redraw()
		elif _pulse != 0.0:
			_pulse = 0.0
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var radius := h * 0.5

		# Track
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.045, 0.07, 0.92), true)

		# Ambient floor: the part of the bar depth has already eaten.
		var floor_w := size.x * clampf(floor_heat / max_heat, 0.0, 1.0)
		if floor_w > 0.0:
			draw_rect(Rect2(0, 0, floor_w, h), Color(0.36, 0.13, 0.09, 0.95))
			for x in range(0, int(floor_w), 10):
				draw_line(Vector2(x, h), Vector2(x + h, 0.0),
					Color(0.62, 0.24, 0.14, 0.55), 2.0)

		# Current heat, ramped cool -> hot so colour alone conveys danger.
		var frac := clampf(heat / max_heat, 0.0, 1.0)
		var heat_w := size.x * frac
		if heat_w > 0.0:
			var col := Color(0.98, 0.62, 0.16).lerp(Color(1.0, 0.16, 0.10),
				clampf(frac * 1.35, 0.0, 1.0))
			if heat >= warning:
				col = col.lightened(0.16 + 0.16 * sin(_pulse))
			draw_rect(Rect2(0, 0, heat_w, h), col)
			# Specular sheen along the top edge.
			draw_rect(Rect2(0, 0, heat_w, maxf(h * 0.30, 2.0)),
				Color(1, 1, 1, 0.20))
			# Leading edge glow.
			draw_rect(Rect2(maxf(heat_w - 3.0, 0.0), 0, 3, h),
				Color(1, 1, 1, 0.55))

		# Warning notch
		var wx := size.x * warning / max_heat
		draw_rect(Rect2(wx - 1.5, -2.0, 3, h + 4.0), Color(1, 1, 1, 0.85))

		# Frame
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55), false, 2.0)

	func update_values(h: float, f: float, m: float) -> void:
		heat = h
		floor_heat = f
		max_heat = m
		queue_redraw()


func _ready() -> void:
	layer = 10
	_build_top()
	_build_heat()
	_build_context_buttons()
	_build_toast()
	_connect_events()


func _build_top() -> void:
	# Hierarchy by urgency: hull and cargo (things that end or cap a run) sit
	# right of centre at full contrast; money and ether are progress readouts,
	# so they stay quiet. Positions never move -- only values animate.
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel",
		UIKit.flat_style(Color(0.055, 0.05, 0.085, 0.88), 0, 16, 6))
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_top)
	# Everything below the strip is placed from its real height, so resizing
	# the strip can never leave the heat bar overlapping it or floating off.
	_top.resized.connect(_place_below_top)
	var col := UIKit.vbox(3)
	_top.add_child(col)

	var row1 := UIKit.hbox(16)
	col.add_child(row1)
	_money_label = UIKit.legible(UIKit.label("0 $", 24, UIKit.GOOD))
	row1.add_child(_money_label)
	_ether_label = UIKit.legible(UIKit.label("0 ether", 17, UIKit.ETHER), 3)
	_ether_label.modulate.a = 0.85
	_ether_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_ether_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(spacer)
	_cargo_label = UIKit.legible(UIKit.label("Cargo 0/8", 19))
	_cargo_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_cargo_label)
	_hull_box = UIKit.hbox(4)
	_hull_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_hull_box)
	# Rocket ammo lives in the status strip now that the firing pad is gone:
	# on web it's fired with R/Q, so this is a readout, not a control.
	_rocket_label = UIKit.legible(UIKit.label("↗ 5", 19, UIKit.ETHER))
	_rocket_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_rocket_label)
	# Always available (unlike SHOP/DEPOT, which only appear in context) --
	# checking where you've been shouldn't require being somewhere specific.
	var map_btn := UIKit.button("MAP", 15)
	map_btn.focus_mode = Control.FOCUS_NONE  # see _build_context_buttons
	map_btn.custom_minimum_size = Vector2(60, 34)
	map_btn.pressed.connect(func() -> void: map_pressed.emit())
	row1.add_child(map_btn)
	var pause_btn := UIKit.button("II", 16)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.custom_minimum_size = Vector2(44, 34)
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	row1.add_child(pause_btn)

	var row2 := UIKit.hbox(14)
	col.add_child(row2)
	_depth_label = UIKit.legible(UIKit.label("0 km", 18))
	row2.add_child(_depth_label)
	_layer_label = UIKit.legible(UIKit.label("Surface", 16, UIKit.TEXT_DIM), 3)
	_layer_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(_layer_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer2)
	_target_label = UIKit.legible(UIKit.label("", 15, UIKit.TEXT_DIM), 3)
	_target_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2.add_child(_target_label)

	_target_bar = UIKit.progress(UIKit.ACCENT)
	_target_bar.custom_minimum_size = Vector2(0, 6)
	col.add_child(_target_bar)


func _build_heat() -> void:
	_heat_bar = HeatBar.new()
	_heat_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heat_bar.offset_top = 86.0  # provisional; _place_below_top sets the real spot
	_heat_bar.offset_left = 16.0
	_heat_bar.offset_right = -16.0
	_heat_bar.offset_bottom = 104.0
	add_child(_heat_bar)
	_heat_caption = UIKit.legible(UIKit.label("DRILL HEAT", 12, UIKit.TEXT_DIM), 3)
	_heat_caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heat_caption.offset_top = 106.0
	_heat_caption.offset_left = 16.0
	add_child(_heat_caption)

	_warning_rect = ColorRect.new()
	_warning_rect.color = Color(1, 0, 0, 0)
	_warning_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_warning_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_warning_rect)


## Heat bar, its caption and the toast line hang off the bottom of the status
## strip, wherever that ends up.
func _place_below_top() -> void:
	if _heat_bar == null or _toast_label == null or _top.size.y <= 0.0:
		return  # not laid out yet, or laid out before the rest of the HUD existed
	var y := _top.size.y + 6.0
	_heat_bar.offset_top = y
	_heat_bar.offset_bottom = y + 18.0
	_heat_caption.offset_top = y + 20.0
	_toast_label.offset_top = y + 52.0


## Web build: keyboard/mouse only, so there are no on-screen D-pads or rocket
## pad. What remains is the two contextual buttons, which are genuine mouse
## targets rather than thumb controls, parked in the bottom-right corner so
## nothing overlaps the play area.
func _build_context_buttons() -> void:
	_shop_button = UIKit.button("SHOP", 20, true)
	# In-game buttons must never take keyboard focus. A focused Button fires on
	# ui_accept, which includes Space -- and Space is also jump. So clicking
	# SHOP (or MAP, or pause) and then jumping would reopen that screen.
	_shop_button.focus_mode = Control.FOCUS_NONE
	_shop_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_shop_button.offset_left = -184.0
	_shop_button.offset_right = -20.0
	_shop_button.offset_top = -66.0
	_shop_button.offset_bottom = -20.0
	_shop_button.visible = false
	_shop_button.pressed.connect(func() -> void: shop_pressed.emit())
	add_child(_shop_button)

	# Stacked directly above SHOP; the two are never relevant at the same time,
	# but stacking keeps either from jumping position when both are possible.
	_depot_button = UIKit.button("DEPOT", 20, true)
	_depot_button.focus_mode = Control.FOCUS_NONE
	_depot_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_depot_button.offset_left = -184.0
	_depot_button.offset_right = -20.0
	_depot_button.offset_top = -122.0
	_depot_button.offset_bottom = -76.0
	_depot_button.visible = false
	_depot_button.pressed.connect(func() -> void: depot_pressed.emit())
	add_child(_depot_button)

	# Tutorial objective. Bottom-centre rather than near the top: toasts already
	# own the top of the screen, and a quest tracker that a toast can cover is
	# useless. Clear of the SHOP/DEPOT stack in the bottom-right corner.
	_objective_panel = UIKit.panel(Color(0.10, 0.08, 0.16, 0.92), 12)
	_objective_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_objective_panel.offset_left = -330.0
	_objective_panel.offset_right = 330.0
	_objective_panel.offset_top = -66.0
	_objective_panel.offset_bottom = -20.0
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_panel.visible = false
	_objective_label = UIKit.legible(UIKit.label("", 17, UIKit.ACCENT), 3)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_panel.add_child(_objective_label)
	add_child(_objective_panel)


func _build_toast() -> void:
	_toast_label = UIKit.legible(UIKit.label("", 21, Color.WHITE), 5)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_top = 150.0  # provisional; _place_below_top sets the real spot
	_toast_label.offset_left = -340.0
	_toast_label.offset_right = 340.0
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)


func _connect_events() -> void:
	Events.money_changed.connect(func(m: int) -> void:
		_money_label.text = "%d $" % m
		_refresh_target())
	Events.ether_changed.connect(func(e: int) -> void:
		_ether_label.text = "%d ether" % e)
	Events.cargo_changed.connect(func(used: int, cap: int) -> void:
		_cargo_label.text = "Cargo %d/%d" % [used, cap])
	Events.hull_changed.connect(_on_hull_changed)
	Events.heat_changed.connect(_on_heat_changed)
	Events.depth_changed.connect(_on_depth_changed)
	Events.toast.connect(show_toast)
	Events.upgrade_purchased.connect(func(_id: String, _lvl: int) -> void: _refresh_target())
	Events.depot_proximity.connect(set_depot_nearby)
	Events.rockets_changed.connect(_on_rockets_changed)
	Events.ftue_objective.connect(func(text: String) -> void:
		_objective_label.text = text
		_objective_panel.visible = text != "")
	_on_rockets_changed(GameState.rockets, GameState.max_rockets())
	# Initial values
	_money_label.text = "%d $" % GameState.money
	_ether_label.text = "%d ether" % GameState.ether
	_cargo_label.text = "Cargo %d/%d" % [GameState.cargo.size(), GameState.cargo_capacity()]
	_on_hull_changed(GameState.max_hull(), GameState.max_hull())
	_refresh_target()


func _on_hull_changed(hp: int, max_hp: int) -> void:
	for child in _hull_box.get_children():
		child.queue_free()
	for i in max_hp:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(12, 18)
		seg.color = UIKit.BAD if i < hp else Color(0.25, 0.22, 0.26)
		_hull_box.add_child(seg)


func _on_heat_changed(heat: float, floor_heat: float, max_heat: float) -> void:
	_heat_bar.update_values(heat, floor_heat, max_heat)
	var warn := float(Balance.heat["warning_at"])
	if heat >= warn:
		var intensity := clampf((heat - warn) / (max_heat - warn), 0.0, 1.0)
		_warning_rect.color = Color(1, 0, 0, 0.10 + 0.18 * intensity
			* (0.6 + 0.4 * sin(Time.get_ticks_msec() / 90.0)))
	else:
		_warning_rect.color = Color(1, 0, 0, 0)


func _on_depth_changed(row: int, km: float, _layer_id: int) -> void:
	_depth_label.text = "%d km" % int(km)
	if km <= 0.0:
		_layer_label.text = "Surface"
	else:
		_layer_label.text = String(Balance.layer_for_row(row)["name"])


func set_at_surface(at_surface: bool) -> void:
	_shop_button.visible = at_surface


## Greys out at zero so an empty bay reads at a glance rather than only when a
## press fails.
func _on_rockets_changed(count: int, max_count: int) -> void:
	_rocket_label.text = "↗ %d/%d" % [count, max_count]
	_rocket_label.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.45)


func set_depot_nearby(depot_id: String) -> void:
	_depot_button.visible = depot_id != ""


func _refresh_target() -> void:
	var target := GameState.next_upgrade_target()
	if target.is_empty():
		_target_label.text = "All upgrades maxed!"
		_target_bar.value = 100.0
		return
	var upgrade_name := String(Balance.upgrades[target["id"]]["name"])
	var cost := int(target["cost"])
	var have := GameState.money + GameState.run_earn_preview
	_target_label.text = "Next: %s  %d/%d $" % [upgrade_name, mini(have, cost), cost]
	_target_bar.max_value = float(cost)
	_target_bar.value = clampf(float(have), 0.0, float(cost))


func show_toast(text: String) -> void:
	_toast_queue.append(text)
	if not _toast_busy:
		_next_toast()


func _next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	_toast_label.text = _toast_queue.pop_front()
	var tween := create_tween()
	tween.tween_property(_toast_label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.2)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_next_toast)
