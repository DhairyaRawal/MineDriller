extends Node
## Test runner: headless validation of the game's core systems, plus an
## end-to-end smoke test that actually drills with the real player physics.
## Run:  godot --headless --path . res://tests/test_runner.tscn
## Exits 0 on success, 1 on any failure.

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	_test_balance()
	_test_world_determinism()
	_test_world_diff_roundtrip()
	_test_layer_gating()
	_test_economy()
	_test_depot()
	_test_save_roundtrip()
	_test_heat_model()
	_test_terrain_physics()
	_test_water_sim()
	await _test_end_to_end_drilling()
	_finish()


func _check(condition: bool, test_name: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(test_name)
		printerr("FAIL: " + test_name)
	else:
		print("ok: " + test_name)


func _finish() -> void:
	print("----------------------------------------")
	print("%d checks, %d failures" % [_checks, _failures.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


# ------------------------------------------------------------------- tests

func _test_balance() -> void:
	_check(not Balance.data.is_empty(), "balance loads")
	_check(Balance.layers.size() == 5, "five layers defined")
	_check(Balance.ores.size() == 6, "six ores defined")
	# Upgrade costs must rise with level (economy sanity).
	for id: String in Balance.upgrades:
		var prev := 0
		var ok := true
		for level in range(1, Balance.upgrade_max(id)):
			var cost := Balance.upgrade_cost(id, level)
			if cost <= prev:
				ok = false
			prev = cost
		_check(ok, "upgrade costs monotonic: " + id)
	_check(Balance.upgrade_cost("drill_speed", Balance.upgrade_max("drill_speed")) == -1,
		"maxed upgrade returns -1 cost")
	# Ore values follow GDD ordering: opal > ruby > emerald > gold > silver > iron
	var order := ["iron", "silver", "gold", "emerald", "ruby", "opal"]
	var ascending := true
	for i in range(order.size() - 1):
		if int(Balance.ores[order[i]]["value"]) >= int(Balance.ores[order[i + 1]]["value"]):
			ascending = false
	_check(ascending, "ore values follow GDD rarity order")


func _test_world_determinism() -> void:
	var a := MineWorld.new()
	var b := MineWorld.new()
	add_child(a)
	add_child(b)
	a.setup(12345)
	b.setup(12345)
	var same := true
	for y in range(1, 120, 7):
		for x in range(0, 32, 3):
			var ia := a.cell_info(Vector2i(x, y))
			var ib := b.cell_info(Vector2i(x, y))
			if ia["type"] != ib["type"] or ia["ore_id"] != ib["ore_id"]:
				same = false
	_check(same, "same seed produces identical worlds")
	var c := MineWorld.new()
	add_child(c)
	c.setup(99999)
	var differs := false
	for y in range(1, 120, 3):
		for x in range(0, 32):
			if a.cell_info(Vector2i(x, y))["type"] != c.cell_info(Vector2i(x, y))["type"]:
				differs = true
	_check(differs, "different seed produces different world")
	# Digging persists
	var cell := Vector2i(5, 5)
	a.dig(cell)
	_check(int(a.cell_info(cell)["type"]) == MineWorld.TileType.EMPTY, "dug cell becomes empty")
	_check(int(b.cell_info(cell)["type"]) != MineWorld.TileType.EMPTY
		or b._mined.has(cell) == false, "dig does not leak across instances")
	# Bounds are bedrock
	_check(int(a.cell_info(Vector2i(-1, 10))["type"]) == MineWorld.TileType.BEDROCK,
		"left wall is bedrock")
	_check(int(a.cell_info(Vector2i(0, 9999))["type"]) == MineWorld.TileType.BEDROCK,
		"bottom is bedrock")
	a.queue_free()
	b.queue_free()
	c.queue_free()


## export_diff()/import_diff() must reconstruct a world's mined/carved/visited
## state on a second instance with the same seed -- the "coarse diff" save
## persistence model (see MineWorld's "persistence" section).
func _test_world_diff_roundtrip() -> void:
	var a := MineWorld.new()
	add_child(a)
	a.setup(55555)
	a.stream_around(0)
	# A collected-ore-style dig (whole cell, via the legacy dig() path).
	var mined_cell := Vector2i(3, 3)
	a.dig(mined_cell)
	# A drilled tunnel through plain rock (per-pixel, must cross
	# DUG_THRESHOLD_FRAC to land in _carved_cells).
	var tunnel_cell := Vector2i(16, 4)
	var pos := Vector2(16 * 64 + 32, 4 * 64.0)
	for i in 20:
		a.carve_circle(pos, 26.0, 5)
		pos.y += 3.0
	_check(a._carved_cells.has(tunnel_cell), "enough carving marks a cell as dug")
	var diff := a.export_diff()

	var b := MineWorld.new()
	add_child(b)
	b.setup(55555)
	b.import_diff(diff)
	b.stream_around(0)

	_check(int(b.cell_info(mined_cell)["type"]) == MineWorld.TileType.EMPTY,
		"imported diff restores a dug cell as empty")
	_check(not b.is_solid_px(a.cell_to_world(tunnel_cell)),
		"imported diff restores a carved tunnel as passable")
	_check(b.is_chunk_visited(0), "imported diff restores visited chunks (map fog-of-war)")
	a.queue_free()
	b.queue_free()


func _test_layer_gating() -> void:
	var w := MineWorld.new()
	add_child(w)
	w.setup(777)
	# Transition band under layer 1 (rows 26-27) must be tier-2 hard rock.
	var l1: Dictionary = Balance.layers[0]
	var band_row := int(l1["row_end"]) - 1
	var gated := true
	for x in 32:
		var info := w.cell_info(Vector2i(x, band_row))
		if int(info["type"]) != MineWorld.TileType.HARD or int(info["tier"]) != 2:
			gated = false
	_check(gated, "layer transition is a solid tier-2 wall")
	_check(not w.can_drill(Vector2i(4, band_row), 1), "bit 1 cannot pierce transition")
	_check(w.can_drill(Vector2i(4, band_row), 2), "bit 2 pierces transition")
	w.queue_free()


func _test_economy() -> void:
	GameState.from_dict({})  # reset
	GameState.money = 0
	_check(GameState.try_collect_ore("gold"), "collect ore into empty cargo")
	GameState.cargo = []
	for i in GameState.cargo_capacity():
		GameState.try_collect_ore("iron")
	_check(not GameState.try_collect_ore("iron"), "cargo capacity enforced")
	GameState.cargo = ["gold", "gold", "ruby"]
	var before := GameState.money
	GameState.sell_cargo()
	_check(GameState.money == before + 25 + 25 + 60, "sell math matches GDD prices")
	_check(GameState.ether == 1, "ruby grants 1 ether")
	_check(GameState.cargo.is_empty(), "cargo empties after sale")
	# Upgrade purchase
	GameState.money = 10000
	var cost := GameState.upgrade_cost("drill_speed")
	_check(GameState.buy_upgrade("drill_speed"), "upgrade purchase succeeds")
	_check(GameState.money == 10000 - cost, "upgrade deducts exact cost")
	_check(GameState.upgrade_levels["drill_speed"] == 2, "upgrade level increments")
	GameState.money = 0
	_check(not GameState.buy_upgrade("cooling"), "cannot buy without money")
	# Bust loses cargo but keeps money
	GameState.money = 500
	GameState.cargo = ["opal"]
	GameState.lose_cargo("test")
	_check(GameState.cargo.is_empty() and GameState.money == 500,
		"bust loses cargo, keeps money (GDD penalty)")


## Depots: deposit/withdraw move ore between cargo and a capped per-depot
## bin, and deposited ore must survive lose_cargo() -- that's the entire
## point of a safe-spot depot (Changes.txt).
func _test_depot() -> void:
	GameState.from_dict({})
	var depot_id := "test_depot"
	GameState.cargo = ["iron", "iron", "gold"]
	_check(GameState.deposit_ore(depot_id, "iron"), "deposit succeeds when cargo has the ore")
	_check(GameState.cargo.size() == 2 and GameState.depot_used(depot_id) == 1,
		"deposit moves one ore from cargo into the depot")
	_check(not GameState.deposit_ore(depot_id, "opal"), "deposit fails for an ore not in cargo")
	GameState.lose_cargo("test")
	_check(GameState.cargo.is_empty() and GameState.depot_used(depot_id) == 1,
		"bust clears cargo but never touches deposited ore")
	_check(GameState.withdraw_ore(depot_id, "iron"), "withdraw succeeds when the depot has the ore")
	_check(GameState.cargo == ["iron"] and GameState.depot_used(depot_id) == 0,
		"withdraw moves ore back from the depot into cargo")
	_check(not GameState.withdraw_ore(depot_id, "iron"), "withdraw fails once the depot is empty")
	# Capacity cap
	var cap := GameState.depot_capacity()
	GameState.cargo = []
	for i in cap + 2:
		GameState.cargo.append("iron")
	var deposited := 0
	for i in cap + 2:
		if GameState.deposit_ore(depot_id, "iron"):
			deposited += 1
	_check(deposited == cap, "deposits stop once the depot hits capacity")
	GameState.from_dict({})


func _test_save_roundtrip() -> void:
	GameState.money = 4242
	GameState.ether = 7
	GameState.upgrade_levels["cargo"] = 3
	GameState.codex_discovered = ["iron", "opal"]
	GameState.tutorial_done = true
	GameState.world_diff = {"mined": [[1, 2]], "visited_chunks": [0, 1]}
	GameState.last_position = Vector2(123.0, 456.0)
	GameState.cargo = ["iron", "gold", "gold"]
	GameState.depot_storage = {"L1_1": {"iron": 2}}
	var snapshot := GameState.to_dict()
	GameState.from_dict({})
	_check(GameState.money == 0 and GameState.cargo.is_empty()
		and GameState.last_position == Vector2.ZERO and GameState.depot_storage.is_empty(),
		"reset clears money, cargo, position and depot storage")
	GameState.from_dict(snapshot)
	_check(GameState.money == 4242 and GameState.ether == 7
		and GameState.upgrade_levels["cargo"] == 3
		and "opal" in GameState.codex_discovered
		and GameState.tutorial_done, "save round-trip preserves state")
	_check(GameState.cargo == ["iron", "gold", "gold"]
		and GameState.run_earn_preview == int(Balance.ores["iron"]["value"]) + 2 * int(Balance.ores["gold"]["value"]),
		"save round-trip preserves cargo and recomputes run_earn_preview")
	_check(GameState.last_position == Vector2(123.0, 456.0),
		"save round-trip preserves last_position")
	_check(int((GameState.depot_storage.get("L1_1", {}) as Dictionary).get("iron", 0)) == 2,
		"save round-trip preserves depot_storage")
	# Corrupt-save handling: from_dict with garbage must not crash.
	GameState.from_dict({"money": "not_a_number_but_int_casts", "upgrade_levels": {"cargo": 999}})
	_check(GameState.upgrade_levels["cargo"] <= Balance.upgrade_max("cargo"),
		"corrupt upgrade levels are clamped")
	GameState.from_dict({})


func _test_heat_model() -> void:
	GameState.from_dict({})
	var shallow := GameState.ambient_floor(10)
	var deep := GameState.ambient_floor(300)
	_check(deep > shallow, "ambient heat floor rises with depth (GDD cooldown shrink)")
	GameState.upgrade_levels["cooling"] = 6
	var deep_cooled := GameState.ambient_floor(300)
	_check(deep_cooled < deep, "cooling upgrade lowers the floor")
	GameState.from_dict({})


func _test_terrain_physics() -> void:
	var w := MineWorld.new()
	add_child(w)
	w.setup(31337)
	w.stream_around(0)
	var radius := 18.0
	# Drop a circle from the sky: it must land on the surface and stop.
	var pos := Vector2(16 * 64 + 32, -300.0)
	var landed := false
	for i in 400:
		var res := TerrainBody.move_circle(w, pos, radius, Vector2(0, 12))
		pos = res["pos"]
		if bool(res["on_floor"]):
			landed = true
			break
	_check(landed, "falling circle lands on terrain")
	_check(pos.y < 96.0, "body rests near the surface, not deep inside it")
	# Carving opens terrain: a solid spot must become passable after a carve.
	var target := Vector2(16 * 64 + 32, 6 * 64 + 32)
	for probe in 80:
		if w.is_solid_type(int(w.cell_info(w.world_to_cell(target))["type"])):
			break
		target.y += 64.0
	var before := w.is_solid_px(target)
	w.carve_circle(target, 26.0, 5)
	var after := w.is_solid_px(target)
	_check(before and not after, "drill carves a hole in solid terrain")
	# Bedrock side wall is never passable.
	_check(w.is_solid_px(Vector2(-8.0, 6 * 64 + 32)), "bedrock side wall stays solid")
	w.queue_free()


## Water should fall into an opened space below it instead of sitting fixed
## forever (Changes.txt). Carve both cells open first so the test doesn't
## depend on this seed happening to generate a natural water pocket there.
func _test_water_sim() -> void:
	var w := MineWorld.new()
	add_child(w)
	w.setup(24680)
	w.stream_around(0)
	var top_cell := Vector2i(16, 4)
	var below_cell := Vector2i(16, 5)
	w.carve_circle(w.cell_to_world(top_cell), 30.0, 5)
	w.carve_circle(w.cell_to_world(below_cell), 30.0, 5)
	w._fill_water_cell(top_cell)
	_check(not w._water_cells.has(below_cell), "cell below starts dry")
	for i in 30:
		w.step_water_simulation(w.cell_to_world(top_cell), MineWorld.WATER_SIM_INTERVAL)
	_check(w._water_cells.has(below_cell),
		"water spreads into an opened cell below after simulating (falls, doesn't sit fixed)")
	w.queue_free()


func world_row_of(game: Node2D, player: Player) -> int:
	var w: MineWorld = game.world
	return w.world_to_cell(player.position).y


## Discovery Cards pause the tree so a child can read them. A simulated player
## has to tap "GOT IT!" like a real one, or the dive stalls the first time it
## hits iron.
func _clear_cards(game: Node2D) -> void:
	for child in game.get_children():
		if child is DiscoveryCard:
			(child as DiscoveryCard).dismiss()


func _test_end_to_end_drilling() -> void:
	# Full-stack smoke test: real Game scene, real input, real physics.
	GameState.from_dict({})
	GameState.tutorial_done = true
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await get_tree().physics_frame
	var player: Player = game.player
	var bust_reason := ""
	player.busted.connect(func(reason: String) -> void: bust_reason = reason)
	var start_y := player.position.y
	# Let the pod settle, then drill in bursts with cooling pauses —
	# exactly how the heat mechanic wants you to play.
	for i in 30:
		await get_tree().physics_frame
	var peak_heat := 0.0
	for burst in 8:
		Input.action_press("move_down")
		for i in 50:
			await get_tree().physics_frame
			_clear_cards(game)
			peak_heat = maxf(peak_heat, player.heat)
		Input.action_release("move_down")
		# Cool off like a real player: wait until heat is comfortably low
		# (carryover drilling can eat part of the pause).
		var guard := 0
		while player.heat > 35.0 and guard < 600:
			guard += 1
			await get_tree().physics_frame
			_clear_cards(game)
		for i in 30:
			await get_tree().physics_frame
			_clear_cards(game)
	if player.state == Player.State.BUSTED:
		print("   bust reason: %s | heat=%.1f hull=%d row=%d" % [bust_reason,
			player.heat, player.hull, world_row_of(game, player)])
	_check(player.state != Player.State.BUSTED, "burst drilling stays under overheat")
	_check(player.position.y > start_y + 64.0, "player drilled downward through terrain")
	_check(peak_heat > 0.0, "drilling generated heat")
	var world: MineWorld = game.world
	var depth_row: int = world.world_to_cell(player.position).y
	_check(depth_row >= 2, "reached at least 2 tiles of depth")

	# Cool off fully before the climb.
	var cool_guard := 0
	while player.heat > 20.0 and cool_guard < 400:
		cool_guard += 1
		await get_tree().physics_frame
		_clear_cards(game)

	# Ascent by ROUTE, not flight: hold JUMP + a direction into the shaft wall
	# to carve a rising ramp. Cool proactively so heat never busts the climb.
	var apex := player.position.y
	var highest := apex
	Input.action_press("move_right")
	var up_guard := 0
	while up_guard < 800 and player.state != Player.State.BUSTED:
		up_guard += 1
		if player.heat > 82.0:
			Input.action_release("move_up")
			for i in 40:
				await get_tree().physics_frame
				_clear_cards(game)
			continue
		Input.action_press("move_up")
		await get_tree().physics_frame
		_clear_cards(game)
		highest = minf(highest, player.position.y)
		if highest < apex - 3.0 * 64.0:
			break
	Input.action_release("move_up")
	Input.action_release("move_right")
	_check(player.state != Player.State.BUSTED, "ramp climb stays under overheat")
	_check(highest < apex - 48.0, "carving a ramp lifts the pod back up (no flight)")
	game.queue_free()
	await get_tree().process_frame
