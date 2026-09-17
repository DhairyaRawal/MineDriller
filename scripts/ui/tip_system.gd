class_name TipSystem
extends CanvasLayer
## TipSystem: contextual '?' tips that float over whatever they're about -- an
## enemy, a water pocket, a depot -- or over the pod for states like heat.
## Hover a '?' for the tip, click it (or press H) to open it properly.
##
## Once read, a '?' retires for good -- for every instance of that tip, so
## reading about water once clears the '?' from every water pocket (see
## GameState.mark_tip_seen). Nothing is lost: the pause menu's GUIDE keeps
## every tip readable forever. Content lives in data/tips.json.
##
## Why a CanvasLayer and not bubbles placed in the world: the vignette layer
## (5) darkens the world more and more with depth. World-space bubbles would
## fade out in exactly the deep, dangerous places they matter most. So the
## bubbles live on their own layer, between the vignette and the HUD (10), and
## are re-projected onto their world targets every frame.

## How far from the pod something can be and still earn a '?'.
const RANGE_PX := 420.0
## Cell scan radius around the pod, in tiles.
const CELL_SCAN_RADIUS := 5
## More than this and the play area turns into a field of question marks; the
## most urgent win (tips.json 'priority').
const MAX_BUBBLES := 3
## Relevance is re-evaluated a few times a second, not every frame -- the scan
## is ~120 cells plus enemies, and this also keeps bubbles from flickering.
const RESCAN_INTERVAL := 0.15
const BUBBLE_SIZE := 36.0
## How long the cursor has to rest on a '?' before hovering counts as reading
## it. Tips float over moving enemies, so the cursor brushes across bubbles by
## accident all the time; without a threshold they'd retire unread.
const HOVER_READ_SEC := 1.2
const RETIRE_FADE_SEC := 0.3

var world: MineWorld
var player: Player
var enemies: Node
## World position over the refinery, for the shop tip.
var shop_anchor := Vector2.ZERO
## Set by game.gd while a menu/popup owns the screen.
var suppressed := false

var _active: Array = []          # [{id, node, pos, dist}] currently shown, most urgent first
var _bubbles := {}               # tip id -> Button
var _scan_accum := RESCAN_INTERVAL  # scan on the very first frame
var _heat := 0.0
var _max_heat := 100.0
var _time := 0.0
var _hovered_id := ""
var _hover_time := 0.0
var _hover_panel: PanelContainer
var _hover_title: Label
var _hover_body: Label


func _ready() -> void:
	layer = 8
	Events.heat_changed.connect(func(h: float, _floor: float, m: float) -> void:
		_heat = h
		_max_heat = m)
	_build_hover_panel()


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	visible = not suppressed
	if suppressed:
		# A menu opened over a hovered '?'. Drop the hover outright rather than
		# trusting mouse_exited to fire for a hidden bubble -- otherwise the read
		# timer resumes afterwards and retires a tip nobody finished reading.
		if _hovered_id != "":
			_set_hover("")
		return
	_time += delta
	if _hovered_id != "":
		_hover_time += delta
		if _hover_time >= HOVER_READ_SEC:
			# Counts as read, but the bubble stays up until the cursor leaves
			# (see _rescan), so the tooltip isn't pulled away mid-sentence.
			GameState.mark_tip_seen(_hovered_id)
	_scan_accum += delta
	if _scan_accum >= RESCAN_INTERVAL:
		_scan_accum = 0.0
		_rescan()
	_position_bubbles()


func _unhandled_input(event: InputEvent) -> void:
	if suppressed or _active.is_empty():
		return
	if event.is_action_pressed("show_tip"):
		get_viewport().set_input_as_handled()
		_open(String(_active[0]["id"]))


# ---------------------------------------------------------------- relevance

func _rescan() -> void:
	var found := {}
	var ppos := player.global_position
	var pcell := world.world_to_cell(ppos)

	if enemies != null:
		for e in enemies.get_children():
			if not (e is EnemyBase):
				continue
			var d := ppos.distance_to(e.global_position)
			if d <= RANGE_PX:
				_offer(found, Balance.tip_for_enemy(e.kind), e, e.global_position, d)

	var bit := GameState.bit_level()
	for dy in range(-CELL_SCAN_RADIUS, CELL_SCAN_RADIUS + 1):
		for dx in range(-CELL_SCAN_RADIUS, CELL_SCAN_RADIUS + 1):
			var cell := pcell + Vector2i(dx, dy)
			if cell.y < 1 or cell.x < 0 or cell.x >= world.width or cell.y >= world.max_depth_row:
				continue
			var cpos := world.cell_to_world(cell)
			var d := ppos.distance_to(cpos)
			if world.cell_has_water(cell):
				_offer(found, "water", null, cpos, d)
			var info := world.cell_info(cell)
			var type := int(info["type"])
			if type == MineWorld.TileType.MAGMA:
				_offer(found, "magma", null, cpos, d)
			elif type == MineWorld.TileType.CHEST:
				_offer(found, "chest", null, cpos, d)
			elif type == MineWorld.TileType.HARD and int(info["tier"]) > bit:
				# Only rock this bit can't cut. Rock it can cut is just rock.
				_offer(found, "hard_rock", null, cpos, d)

	for depot: Dictionary in world.depot_positions():
		var d := ppos.distance_to(depot["center"])
		if d <= RANGE_PX:
			_offer(found, "depot", null, depot["center"], d)

	if pcell.y <= 0:
		_offer(found, "shop", null, shop_anchor, ppos.distance_to(shop_anchor))

	# States of the pod itself float over the pod.
	if GameState.cargo.size() >= GameState.cargo_capacity():
		_offer(found, "cargo_full", player, ppos, 0.0)
	if _heat > _max_heat * 0.6:
		_offer(found, "heat", player, ppos, 0.0)
	if pcell.y >= 2 and not player.drilling and _in_shaft(ppos):
		_offer(found, "climb", player, ppos, 0.0)

	# Read tips drop out before ranking, so a retired tip frees its slot for the
	# next most urgent unread one. The exception is the tip under the cursor:
	# it keeps its bubble until the cursor leaves, however long they read.
	var ranked := []
	for entry: Dictionary in found.values():
		if GameState.is_tip_seen(entry["id"]) and entry["id"] != _hovered_id:
			continue
		ranked.append(entry)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(Balance.tips[a["id"]]["priority"]) < int(Balance.tips[b["id"]]["priority"]))
	_active = ranked.slice(0, MAX_BUBBLES)
	_sync_bubbles()


## Keep the nearest instance of each tip: one '?' per kind of thing, pointing
## at the closest one, rather than a '?' over every water cell in a lake.
func _offer(found: Dictionary, id: String, node: Node2D, pos: Vector2, dist: float) -> void:
	if id == "" or not Balance.tips.has(id):
		return
	if found.has(id) and float(found[id]["dist"]) <= dist:
		return
	found[id] = {"id": id, "node": node, "pos": pos, "dist": dist}


## Walls hard against both sides of the pod: stranded in a vertical shaft,
## which is exactly when "how do I get back up?" is the question. Checked only
## while not drilling, or it would nag on every single descent.
func _in_shaft(pos: Vector2) -> bool:
	var reach := float(Balance.player["radius"]) + 14.0
	return world.is_solid_px(pos + Vector2(-reach, 0.0)) \
		and world.is_solid_px(pos + Vector2(reach, 0.0))


# ------------------------------------------------------------------ bubbles

func _sync_bubbles() -> void:
	var wanted := {}
	for entry: Dictionary in _active:
		wanted[entry["id"]] = true
	for id: String in _bubbles.keys():
		if not wanted.has(id):
			var btn: Button = _bubbles[id]
			_bubbles.erase(id)
			if _hovered_id == id:
				_set_hover("")
			if GameState.is_tip_seen(id):
				_retire(btn)
			else:
				btn.queue_free()  # just out of range; it'll be back
	for id: String in wanted:
		if not _bubbles.has(id):
			_bubbles[id] = _make_bubble(id)


## A read tip shrinks away instead of vanishing, so its disappearance reads as
## "learned it" rather than as a glitch. Out-of-range bubbles simply go.
func _retire(btn: Button) -> void:
	btn.disabled = true
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := btn.create_tween().set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(0.2, 0.2), RETIRE_FADE_SEC) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(btn, "modulate:a", 0.0, RETIRE_FADE_SEC)
	tween.chain().tween_callback(btn.queue_free)


func _make_bubble(id: String) -> Button:
	var danger: bool = Balance.tips[id].get("category", "") == "Dangers"
	var fill := UIKit.BAD if danger else UIKit.ACCENT
	var r := int(BUBBLE_SIZE * 0.5)
	var btn := Button.new()
	btn.text = "?"
	btn.focus_mode = Control.FOCUS_NONE  # never steal keyboard focus from steering
	btn.size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
	btn.custom_minimum_size = btn.size
	btn.pivot_offset = btn.size * 0.5  # retire shrink collapses to the centre, not a corner
	btn.add_theme_font_size_override("font_size", 21)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	var idle := UIKit.flat_style(fill, r)
	idle.set_content_margin_all(0)
	idle.border_color = Color(1, 1, 1, 0.85)
	idle.set_border_width_all(2)
	var hover := idle.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.2)
	btn.add_theme_stylebox_override("normal", idle)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.mouse_entered.connect(func() -> void: _set_hover(id))
	btn.mouse_exited.connect(func() -> void:
		if _hovered_id == id:
			_set_hover(""))
	btn.pressed.connect(func() -> void: _open(id))
	add_child(btn)
	return btn


func _position_bubbles() -> void:
	var to_screen := get_viewport().get_canvas_transform()
	var bob := sin(_time * 3.2) * 3.0
	# Several pod states can be active at once; fan them out side by side
	# instead of stacking them all on the same spot above the pod.
	var on_pod := 0
	for entry: Dictionary in _active:
		if entry["node"] == player:
			on_pod += 1
	var pod_slot := 0
	for entry: Dictionary in _active:
		var btn: Button = _bubbles.get(entry["id"])
		if btn == null:
			continue
		# Untyped on purpose: an enemy can despawn between rescans, and assigning
		# a freed object to a typed Node2D variable is itself a runtime error.
		var node = entry["node"]
		var world_pos: Vector2 = entry["pos"]
		var lift := 44.0
		var fan := 0.0
		if is_instance_valid(node):
			world_pos = node.global_position  # follow things that move
			lift = 60.0
			if node == player:
				fan = (pod_slot - (on_pod - 1) * 0.5) * (BUBBLE_SIZE + 8.0)
				pod_slot += 1
		var screen := to_screen * (world_pos + Vector2(0.0, -lift))
		btn.position = screen + Vector2(fan, bob) - btn.size * 0.5

	if _hovered_id != "" and _bubbles.has(_hovered_id):
		var anchor: Button = _bubbles[_hovered_id]
		var view := get_viewport().get_visible_rect().size
		var p := anchor.position + Vector2(BUBBLE_SIZE + 10.0, -8.0)
		# Flip to the left of the bubble near the right edge of the screen.
		if p.x + _hover_panel.size.x > view.x - 8.0:
			p.x = anchor.position.x - _hover_panel.size.x - 10.0
		p.y = clampf(p.y, 8.0, maxf(view.y - _hover_panel.size.y - 8.0, 8.0))
		_hover_panel.position = p


# ---------------------------------------------------------------- tooltips

func _build_hover_panel() -> void:
	_hover_panel = UIKit.panel(Color(0.10, 0.08, 0.16, 0.96), 12)
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never block the bubble
	_hover_panel.custom_minimum_size = Vector2(300, 0)
	_hover_panel.visible = false
	var col := UIKit.vbox(6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_child(col)
	_hover_title = UIKit.label("", 17, UIKit.ACCENT)
	_hover_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hover_title)
	_hover_body = UIKit.label("", 15)
	_hover_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_body.custom_minimum_size = Vector2(276, 0)
	_hover_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hover_body)
	# Say up front that the '?' goes away, and where the tip lives afterwards --
	# otherwise a vanished bubble looks like a bug.
	var hint := UIKit.label(
		"This ? won't show again once read. Re-read it any time: pause > GUIDE.",
		12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(276, 0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)
	add_child(_hover_panel)


func _set_hover(id: String) -> void:
	_hovered_id = id
	_hover_time = 0.0
	if id == "":
		_hover_panel.visible = false
		return
	var tip: Dictionary = Balance.tips[id]
	_hover_title.text = String(tip["title"])
	_hover_title.add_theme_color_override("font_color",
		UIKit.BAD if tip.get("category", "") == "Dangers" else UIKit.ACCENT)
	_hover_body.text = String(tip["body"])
	_hover_panel.reset_size()  # shrink back after a longer tip
	_hover_panel.visible = true


## Opening a tip is a deliberate read, so it retires immediately -- no dwell.
## The card pauses the tree; when it closes, the next rescan retires the '?'.
func _open(id: String) -> void:
	_set_hover("")
	GameState.mark_tip_seen(id)
	get_parent().add_child(TipCard.new(id))
