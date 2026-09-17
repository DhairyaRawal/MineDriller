class_name FTUE
extends Node
## FTUE: the first-time tutorial level. One small, hand-authored arena that
## walks a new player through the whole core loop once -- drill, collect ore,
## surface, upgrade, drill deeper -- before dropping them into the real world.
##
## It is not a separate game. The level is an authored layout fed through
## MineWorld.cell_info (see use_authored_layout), so the drill, heat bar, cargo
## swap, shop and rockets the player learns here are the real ones.
##
## Steps are DERIVED from game state every frame (derive_step), never chained
## off events. A player who surfaces with too little ore, or busts, or does
## things out of order always sees the correct next instruction instead of
## sitting on a step that has already been skipped past.

enum Step { DRILL, COLLECT, SURFACE, UPGRADE, DEEPER, COMPLETE }

# ---------------------------------------------------------------- the level
#
#   row 0      grass / surface, refinery, spawn above it
#   rows 1-2   soft rock
#   rows 3-4   ORE POCKET   -- enough value for the upgrade, whatever order it's mined in
#   rows 5-7   soft rock
#   rows 8-9   GATE         -- full-width tier-2 rock, only Drill Bit Lv2 cuts it
#   rows 10-11 soft rock
#   rows 12-13 RICH POCKET  -- the visible payoff for upgrading
#   row 14     soft rock; row 15+ is bedrock (the level's depth bound)
#
# Width fits one landscape screen, so the whole arena is visible without
# sideways scrolling.
const WIDTH := 22
const DEPTH := 15
const POCKET_ROWS := [3, 4]
const GATE_ROWS := [8, 9]
const RICH_ROWS := [12, 13]
const POCKET_X_MIN := 9
const POCKET_X_MAX := 13
## The upgrade the level is built around, and the one that carries over.
const TARGET_UPGRADE := "drill_bit"
## How long the player gets to enjoy the rich pocket before the wrap-up card.
const COMPLETE_DELAY_SEC := 1.5

var player: Player

var _step := -1
var _furthest_step := -1
var _heat_warned := false
var _complete_timer := -1.0


## Hand-authored cells for the tutorial arena. Only special cells are listed;
## everything else inside the bounds is soft rock (MineWorld's default).
static func build_layout() -> Dictionary:
	var cells := {}
	var ore := MineWorld.TileType.ORE
	for y: int in POCKET_ROWS:
		for x in range(POCKET_X_MIN, POCKET_X_MAX + 1):
			# Gold down the centre (where a straight bore lands first), silver
			# on the flanks. Mined in ANY order, the best 8 ores the base cargo
			# bay can hold are still worth more than the upgrade -- see
			# _test_ftue, which enforces that rather than trusting this comment.
			var id := "gold" if x in [10, 11, 12] else "silver"
			cells[Vector2i(x, y)] = {"type": ore, "layer_id": 1, "tier": 1, "ore_id": id}
	for y: int in GATE_ROWS:
		for x in WIDTH:
			# layer_id 2 renders it as the next layer's darker rock, so the
			# gate reads as "different, harder" before the player even hits it.
			cells[Vector2i(x, y)] = {"type": MineWorld.TileType.HARD,
				"layer_id": 2, "tier": 2, "ore_id": ""}
	for y: int in RICH_ROWS:
		for x in range(POCKET_X_MIN, POCKET_X_MAX + 1):
			var id := "emerald" if x in [10, 11, 12] else "gold"
			cells[Vector2i(x, y)] = {"type": ore, "layer_id": 1, "tier": 1, "ore_id": id}
	return cells


## The step a player in this state should be working on. Pure, so it can be
## unit-tested without a running scene.
static func derive_step(money: int, cargo_value: int, bit_level: int, row: int,
		upgrade_cost: int) -> int:
	if bit_level >= 2:
		return Step.COMPLETE if row >= RICH_ROWS[0] else Step.DEEPER
	if money >= upgrade_cost:
		return Step.UPGRADE
	if money + cargo_value >= upgrade_cost:
		return Step.SURFACE
	if row >= 2 or cargo_value > 0:
		return Step.COLLECT
	return Step.DRILL


func _ready() -> void:
	Events.heat_changed.connect(_on_heat_changed)


func _process(delta: float) -> void:
	if player == null or player.world == null:
		return
	if _complete_timer >= 0.0:
		_complete_timer -= delta
		if _complete_timer <= 0.0:
			_complete_timer = -1.0
			_show_complete_card()
		return

	var cost := GameState.upgrade_cost(TARGET_UPGRADE)
	var row := player.world.world_to_cell(player.position).y
	var step := derive_step(GameState.money, GameState.run_earn_preview,
		GameState.bit_level(), row, cost)

	if step == Step.COMPLETE:
		Events.ftue_objective.emit("")
		AudioManager.play("upgrade", 0.0, 1.2)
		_complete_timer = COMPLETE_DELAY_SEC
		return

	# Re-emit every frame the collect step is active, since its progress
	# counter moves; other steps only when they change.
	if step != _step or step == Step.COLLECT:
		Events.ftue_objective.emit(_objective_text(step, cost))
	if step != _step:
		if step > _furthest_step and _furthest_step >= 0:
			AudioManager.play("upgrade", -6.0, 1.4)
		_furthest_step = maxi(_furthest_step, step)
		_step = step


func _objective_text(step: int, cost: int) -> String:
	var n := "STEP %d / 5   " % (step + 1)
	match step:
		Step.DRILL:
			if GameState.money > 0:
				return n + "Not enough yet - drill back down for more ore"
			return n + "Hold  S  or  Down  to drill down"
		Step.COLLECT:
			return n + "Collect ore worth %d$     (%d / %d)" % [
				cost, mini(GameState.money + GameState.run_earn_preview, cost), cost]
		Step.SURFACE:
			return n + "Enough ore! Get back up: hold  W + A / D  into a wall to carve a ramp, or press  R  for a rocket"
		Step.UPGRADE:
			# Worded to hold wherever the player is: the SHOP button only shows
			# at the surface, and this text isn't re-rendered as they move.
			return n + "At the surface, click SHOP and buy  Drill Bit Lv 2"
		Step.DEEPER:
			return n + "Your drill cuts the dark rock now - drill down through it"
	return ""


func _on_heat_changed(heat: float, _floor_heat: float, max_heat: float) -> void:
	# The one mechanic that can end a run by surprise gets a single nudge, the
	# first time it starts to matter.
	if not _heat_warned and heat > max_heat * 0.6:
		_heat_warned = true
		Events.toast.emit("Heat is climbing! Stop drilling for a moment to let it cool.")


func _show_complete_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	get_tree().paused = true

	var content := UIKit.modal(layer, "TUTORIAL COMPLETE")
	var body := UIKit.label(
		"That's the whole loop: drill, collect ore, get back to the surface, "
		+ "upgrade, and go deeper.\n\nYour Drill Bit Lv 2 comes with you. The real "
		+ "Earth is far bigger - and the rock gets much harder the deeper you go.",
		18, UIKit.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(480, 0)
	content.add_child(body)

	var go := UIKit.action_button("START DRILLING", true, 260)
	go.pressed.connect(func() -> void:
		GameState.finish_ftue()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/game.tscn"))
	content.add_child(go)
