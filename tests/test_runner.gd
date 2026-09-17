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
	_test_rockets()
	_test_ftue()
	_test_tips()
	_test_controls()
	_test_save_roundtrip()
	_test_heat_model()
	_test_terrain_physics()
	_test_tunnel_healing()
	_test_water_sim()
	await _test_ui_fits_screen()
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
		for x in range(0, a.width, 3):
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
		for x in range(0, a.width):
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
	for x in w.width:
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
	# A full bay upgrades itself: richer ore displaces the cheapest thing
	# aboard, and the loser is erased rather than dropped.
	var cap := GameState.cargo_capacity()
	GameState.cargo = []
	for i in cap:
		GameState.try_collect_ore("iron")
	var preview_before := GameState.run_earn_preview
	_check(GameState.try_collect_ore("gold"), "richer ore swaps into a full bay")
	_check(GameState.cargo.size() == cap, "swap keeps the bay at capacity")
	_check(GameState.cargo.count("gold") == 1 and GameState.cargo.count("iron") == cap - 1,
		"swap erases exactly one of the cheapest ore")
	_check(GameState.run_earn_preview == preview_before - 2 + 25,
		"swap adjusts cargo value by the net difference")
	_check(not GameState.try_collect_ore("iron"),
		"cheaper ore is refused by a full bay (no churn)")
	GameState.cargo = []
	for i in cap:
		GameState.try_collect_ore("opal")
	_check(not GameState.try_collect_ore("opal"),
		"equal-value ore does not swap (ties are not an upgrade)")
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


## Escape rockets: a per-dive consumable that the Rocket Bay upgrade grows and
## surfacing refills for free.
func _test_rockets() -> void:
	GameState.from_dict({})
	var base := int(Balance.player["rockets_base"])
	var per_level := int(Balance.player["rockets_per_level"])
	_check(GameState.max_rockets() == base, "rocket bay starts at the base capacity")
	_check(GameState.rockets == base, "a fresh run starts with a full bay")

	_check(GameState.use_rocket(), "firing spends a rocket")
	_check(GameState.rockets == base - 1, "firing decrements the count")
	for i in base:
		GameState.use_rocket()
	_check(GameState.rockets == 0, "the bay empties")
	_check(not GameState.use_rocket(), "an empty bay refuses to fire")

	GameState.refill_rockets()
	_check(GameState.rockets == base, "surfacing refills the bay")

	GameState.upgrade_levels["rockets"] = 3
	_check(GameState.max_rockets() == base + per_level * 2,
		"each Rocket Bay level adds capacity")
	GameState.refill_rockets()
	_check(GameState.rockets == GameState.max_rockets(),
		"refill tops up to the upgraded capacity")

	# Rockets survive a save, clamped to whatever the bay can actually hold.
	GameState.use_rocket()
	var snapshot := GameState.to_dict()
	var expected := GameState.rockets
	GameState.from_dict({})
	GameState.from_dict(snapshot)
	_check(GameState.rockets == expected, "rocket count round-trips through a save")
	GameState.from_dict({})


## The tutorial: an authored level that can't softlock, step logic that always
## points at the right next action, and a sandbox that can never damage the
## player's real save.
func _test_ftue() -> void:
	GameState.from_dict({})
	var bit_cost := Balance.upgrade_cost(FTUE.TARGET_UPGRADE, 1)

	# --- level economy: the pocket must pay for the upgrade in ONE trip, even
	# if the player happens to mine its cheapest ores first. Hence "worst N".
	var layout := FTUE.build_layout()
	var pocket_values: Array[int] = []
	for y: int in FTUE.POCKET_ROWS:
		for x in range(FTUE.POCKET_X_MIN, FTUE.POCKET_X_MAX + 1):
			var cell: Dictionary = layout[Vector2i(x, y)]
			pocket_values.append(int(Balance.ores[cell["ore_id"]]["value"]))
	pocket_values.sort()
	var bay := int(Balance.player["cargo_base"])
	var worst_trip := 0
	for i in mini(bay, pocket_values.size()):
		worst_trip += pocket_values[i]
	_check(worst_trip >= bit_cost,
		"tutorial pocket pays for the upgrade in one trip even mined worst-first (%d >= %d)"
			% [worst_trip, bit_cost])

	# --- the gate: blocks the starting bit, opens to the upgrade, no way around.
	var w := MineWorld.new()
	add_child(w)
	w.setup(1)
	w.use_authored_layout(layout, FTUE.WIDTH, FTUE.DEPTH)
	var gate_row: int = FTUE.GATE_ROWS[0]
	var sealed := true
	for x in w.width:
		if w.can_drill(Vector2i(x, gate_row), 1):
			sealed = false
	_check(sealed, "tutorial gate spans the full width, so it can't be walked around")
	_check(w.can_drill(Vector2i(FTUE.WIDTH / 2, gate_row), 2), "Drill Bit Lv2 cuts the tutorial gate")
	_check(w.depot_positions().is_empty(), "authored level has no depots")
	_check(int(w.cell_info(Vector2i(FTUE.WIDTH / 2, 1))["type"]) == MineWorld.TileType.SOFT,
		"unlisted authored cells default to soft rock")
	w.queue_free()

	# --- step derivation: every state maps to the right next instruction.
	_check(FTUE.derive_step(0, 0, 1, -1, bit_cost) == FTUE.Step.DRILL, "step: fresh start is DRILL")
	_check(FTUE.derive_step(0, 30, 1, 3, bit_cost) == FTUE.Step.COLLECT, "step: some ore is COLLECT")
	_check(FTUE.derive_step(0, bit_cost, 1, 4, bit_cost) == FTUE.Step.SURFACE, "step: enough ore is SURFACE")
	_check(FTUE.derive_step(40, 0, 1, -1, bit_cost) == FTUE.Step.DRILL,
		"step: surfacing short of the target sends the player back down")
	_check(FTUE.derive_step(40, 60, 1, 4, bit_cost) == FTUE.Step.SURFACE,
		"step: banked money counts toward the target")
	_check(FTUE.derive_step(bit_cost, 0, 1, -1, bit_cost) == FTUE.Step.UPGRADE, "step: sold is UPGRADE")
	_check(FTUE.derive_step(0, 0, 2, -1, bit_cost) == FTUE.Step.DEEPER, "step: upgraded is DEEPER")
	_check(FTUE.derive_step(0, 0, 2, FTUE.RICH_ROWS[0], bit_cost) == FTUE.Step.COMPLETE,
		"step: reaching the rich pocket COMPLETES")

	# --- sandbox: real progress in, real progress out.
	GameState.from_dict({})
	GameState.money = 777
	GameState.last_position = Vector2(50, 900)
	GameState.upgrade_levels["cargo"] = 3
	GameState.begin_ftue()
	_check(GameState.ftue_mode and GameState.money == 0, "tutorial starts from a 0$ sandbox")
	_check(GameState.upgrade_levels["cargo"] == 1, "tutorial sandbox starts with no upgrades")
	GameState.money = 5000  # sandbox spending spree
	_check(int(GameState.to_dict()["money"]) == 777,
		"a save during the tutorial writes the REAL state, not the sandbox")

	GameState.abandon_ftue()
	_check(not GameState.ftue_mode and GameState.money == 777 and not GameState.tutorial_done,
		"quitting the tutorial restores real state and grants nothing")

	GameState.begin_ftue()
	GameState.money = 5000
	GameState.discover_ore("gold")
	GameState.finish_ftue()
	_check(not GameState.ftue_mode and GameState.tutorial_done, "finishing marks the tutorial done")
	_check(GameState.money == 777, "finishing discards sandbox money and restores real money")
	_check(GameState.last_position == Vector2(50, 900), "finishing restores the real resume point")
	_check(GameState.upgrade_levels["cargo"] == 3, "finishing keeps real upgrades")
	_check(GameState.bit_level() == 2, "finishing carries the Drill Bit Lv2 over")
	_check("gold" in GameState.codex_discovered,
		"ores learned in the tutorial stay in the codex (no repeat Discovery Card)")
	GameState.from_dict({})


## Contextual tips are pure data, so the likely bug isn't in code -- it's
## someone adding an enemy to balance.json and forgetting to write its tip.
func _test_tips() -> void:
	_check(not Balance.tips.is_empty(), "tips.json loads")

	var well_formed := true
	var bad := ""
	for id: String in Balance.tips:
		var tip: Dictionary = Balance.tips[id]
		for field in ["title", "body", "category", "priority"]:
			if not tip.has(field):
				well_formed = false
				bad = "%s missing %s" % [id, field]
		if tip.get("category", "") not in Balance.tip_categories:
			well_formed = false
			bad = "%s has unknown category %s" % [id, tip.get("category", "")]
	_check(well_formed, "every tip has a title, body, known category and priority " + bad)

	var priorities := {}
	for id: String in Balance.tips:
		priorities[int(Balance.tips[id]["priority"])] = true
	_check(priorities.size() == Balance.tips.size(),
		"tip priorities are unique, so ranking nearby tips is never a coin flip")

	var uncovered := []
	for kind: String in Balance.enemies:
		if Balance.tip_for_enemy(kind) == "":
			uncovered.append(kind)
	_check(uncovered.is_empty(),
		"every enemy in balance.json has a tip (directly or via alias) %s" % str(uncovered))

	var dangling := []
	for kind: String in Balance.tip_aliases:
		if not Balance.tips.has(String(Balance.tip_aliases[kind])):
			dangling.append(kind)
	_check(dangling.is_empty(), "every tip alias points at a real tip %s" % str(dangling))

	for category in Balance.tip_categories:
		var any := false
		for id: String in Balance.tips:
			if Balance.tips[id].get("category", "") == category:
				any = true
		_check(any, "GUIDE category '%s' isn't empty" % category)

	# --- retirement: a read tip's '?' goes away for good, keyed by tip id.
	GameState.from_dict({})
	_check(not GameState.is_tip_seen("water"), "tips start unread")
	GameState.mark_tip_seen("water")
	GameState.mark_tip_seen("water")
	_check(GameState.is_tip_seen("water") and GameState.tips_seen.count("water") == 1,
		"reading a tip retires it once (marking twice doesn't duplicate)")
	_check(not GameState.is_tip_seen("magma"), "reading one tip doesn't retire others")
	# Elite variants share their base enemy's tip id, so one read covers both.
	GameState.mark_tip_seen(Balance.tip_for_enemy("crawly"))
	_check(GameState.is_tip_seen(Balance.tip_for_enemy("crawly_elite")),
		"reading an enemy's tip also retires it for that enemy's elite variant")

	var snapshot := GameState.to_dict()
	GameState.from_dict({})
	_check(GameState.tips_seen.is_empty(), "resetting save data brings every tip back")
	GameState.from_dict(snapshot)
	_check(GameState.is_tip_seen("water"), "read tips survive a save round-trip")

	# Tutorial: tips read there carry over on finish, but not on quitting out.
	GameState.from_dict({})
	GameState.begin_ftue()
	GameState.mark_tip_seen("heat")
	GameState.abandon_ftue()
	_check(not GameState.is_tip_seen("heat"),
		"tips read in an abandoned tutorial don't carry over")
	GameState.begin_ftue()
	GameState.mark_tip_seen("heat")
	GameState.finish_ftue()
	_check(GameState.is_tip_seen("heat"),
		"tips read in a finished tutorial stay retired in the real game")
	GameState.from_dict({})


## The pause menu's controls panel reads keys from the live InputMap. If an
## action is renamed or dropped, that row would silently render blank -- so
## every row must resolve to real keys.
func _test_controls() -> void:
	var blank := []
	for entry: Array in PauseMenu.CONTROLS:
		if entry[1] is Array:
			for action in entry[1]:
				if not InputMap.has_action(String(action)):
					blank.append(action)
			if PauseMenu.keys_text(entry[1]) == "":
				blank.append(entry[0])
	_check(blank.is_empty(), "every controls-panel row resolves to real keys %s" % str(blank))

	var pause_keys := PauseMenu.keys_text(["pause"])
	_check("P" in pause_keys and "Esc" in pause_keys,
		"pause is on both P and Esc (P matters on web, where Esc can exit fullscreen): '%s'"
			% pause_keys)
	_check(PauseMenu.keys_text(["move_left", "move_right"]) == "A / D   or   ← / →",
		"left/right bindings are paired, not dumped as one list")


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


## Surfacing reseals narrow shafts but leaves wide chambers open, so every
## dive starts through fresh rock while deliberate rooms persist.
func _test_tunnel_healing() -> void:
	var w := MineWorld.new()
	add_child(w)
	w.setup(4242)
	w.stream_around(0)

	# A 1-wide vertical shaft, built only from cells this seed generated as
	# solid rock, so "it went back to solid" is a meaningful assertion.
	var shaft: Array[Vector2i] = []
	var natural_type := {}
	for y in range(5, 20):
		var cell := Vector2i(4, y)
		var t := int(w.cell_info(cell)["type"])
		if w.is_solid_type(t):
			natural_type[cell] = t
			shaft.append(cell)
	_check(shaft.size() >= 4, "test seed provides solid rock to dig a shaft through")

	# A 4x3 chamber comfortably contains a 3x2 block in either orientation.
	var chamber: Array[Vector2i] = []
	for x in range(20, 24):
		for y in range(5, 8):
			chamber.append(Vector2i(x, y))

	for cell: Vector2i in shaft + chamber:
		w._carved_cells[cell] = true
		w._info_cache.erase(cell)
	_check(int(w.cell_info(shaft[0])["type"]) == MineWorld.TileType.EMPTY,
		"carved shaft reads as empty before healing")

	var healed := w.heal_narrow_tunnels()
	_check(healed == shaft.size(), "healing refills exactly the narrow shaft")

	var shaft_restored := true
	for cell: Vector2i in shaft:
		if w._carved_cells.has(cell) or int(w.cell_info(cell)["type"]) != int(natural_type[cell]):
			shaft_restored = false
	_check(shaft_restored, "every shaft cell is solid rock again")

	var chamber_intact := true
	for cell: Vector2i in chamber:
		if not w._carved_cells.has(cell) or int(w.cell_info(cell)["type"]) != MineWorld.TileType.EMPTY:
			chamber_intact = false
	_check(chamber_intact, "the wide chamber survives healing and stays open")
	_check(w.heal_narrow_tunnels() == 0, "healing again is a no-op")
	w.queue_free()


## Water must fall into space drilled beneath it (Changes.txt) -- including
## while a big resting pool sits elsewhere in view. That pool used to spend the
## whole per-tick budget just being looked at, so the scan never reached the
## water you'd actually drilled under and it hung in the air forever. Authored
## layout, so none of this depends on what a seed happens to generate.
func _test_water_sim() -> void:
	var w := MineWorld.new()
	add_child(w)
	w.setup(24680)
	var water := {"type": MineWorld.TileType.WATER, "layer_id": 1, "tier": 0, "ore_id": ""}
	var empty := {"type": MineWorld.TileType.EMPTY, "layer_id": 1, "tier": 0, "ore_id": ""}
	var cells := {}
	var pool: Array[Vector2i] = []
	for y in [12, 13]:
		for x in range(4, 10):
			cells[Vector2i(x, y)] = water
			pool.append(Vector2i(x, y))
	var top_cell := Vector2i(15, 4)
	var below_cell := Vector2i(15, 5)
	cells[top_cell] = water
	cells[below_cell] = empty
	cells[Vector2i(15, 6)] = empty
	w.use_authored_layout(cells, 22, 30)
	w.stream_around(0)
	var center := w.cell_to_world(Vector2i(11, 8))  # both in simulation reach
	_check(w.cell_has_water(top_cell) and w.cell_has_water(pool[0]), "authored water is seeded")
	_check(not w.cell_has_water(below_cell), "cell below the pocket starts dry")

	var fell := false
	var settled := false
	var ticks := 0
	var t0 := Time.get_ticks_usec()
	while ticks < 1500 and not (fell and settled):
		w.step_water_simulation(center, MineWorld.WATER_SIM_INTERVAL)
		ticks += 1
		fell = fell or w.cell_has_water(below_cell)
		settled = true
		for c in pool:
			if w.cell_has_water(c) and not w._water_settled.has(c):
				settled = false
				break
	# Not a check: a number to watch, since this runs every 50ms in the browser.
	print("  water sim: %d ticks, %.2f ms per tick" % [
		ticks, (Time.get_ticks_usec() - t0) / 1000.0 / ticks])
	_check(fell, "water falls into space opened below it, even with a resting pool in view")
	_check(settled, "a pool with nowhere to go falls asleep")

	# Drill down from the pool's floor. Asleep, the pool must still notice.
	# Row 15 is the check, not 14: the rounded cave edge already lets a little
	# water into the top of row 14 before any drilling.
	var shaft_cell := Vector2i(6, 15)
	_check(not w.cell_has_water(shaft_cell), "rock under the pool starts dry")
	var p := w.cell_to_world(Vector2i(6, 13))
	while p.y <= w.cell_to_world(Vector2i(6, 16)).y:
		w.carve_circle(p, 26.0, 5)
		p.y += 8.0
	_check(not w._water_settled.has(Vector2i(6, 13)), "drilling beneath still water wakes it")
	var drained := false
	for i in 600:
		w.step_water_simulation(center, MineWorld.WATER_SIM_INTERVAL)
		if w.cell_has_water(shaft_cell):
			drained = true
			break
	_check(drained, "woken water pours down the new shaft")
	w.queue_free()


## The web layout's promise: every page fits a 1280x720 screen with nothing to
## scroll. Builds each screen for real, filled with the longest content it can
## show (every ore discovered, every layer reached, a full cargo bay, every
## tip), and checks that no control lands off-screen. Pages the player flips
## through (codex, guide) are checked on every page.
func _test_ui_fits_screen() -> void:
	GameState.from_dict({})
	GameState.tutorial_done = true
	GameState.codex_discovered = Balance.ores.keys()
	GameState.stats["deepest_km"] = 99999.0
	var view := get_viewport().get_visible_rect().size
	print("  ui fit check at %dx%d" % [view.x, view.y])

	var problems: Array[String] = []
	for ore_id: String in Balance.ores:
		var card := DiscoveryCard.new(ore_id)
		add_child(card)
		# Let the pop-in finish: mid-tween the card is scaled down and would
		# look like it fits when it doesn't.
		await get_tree().create_timer(0.4, true).timeout
		_note_offscreen(card, "card " + ore_id, problems)
		card.dismiss()
	_check(problems.is_empty(), "every Discovery Card fits the screen " + ", ".join(PackedStringArray(problems)))

	problems.clear()
	for tip_id: String in Balance.tips:
		var tip := TipCard.new(tip_id)
		add_child(tip)
		await _frames(3)
		_note_offscreen(tip, "tip " + tip_id, problems)
		tip.dismiss()
	_check(problems.is_empty(), "every tip card fits the screen " + ", ".join(PackedStringArray(problems)))

	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(3)
	problems.clear()
	_note_offscreen(menu, "menu", problems)
	for panel: String in ["_show_codex", "_show_achievements", "_show_stats", "_show_settings"]:
		menu.call(panel)
		await _frames(3)
		_note_offscreen(menu, panel, problems)
		if panel == "_show_codex":
			await _flip_pages(menu, "codex", problems)
	_check(problems.is_empty(), "main menu and its panels fit the screen " + ", ".join(PackedStringArray(problems)))
	menu.queue_free()

	GameState.cargo.clear()
	var bin := {}
	for ore_id: String in Balance.ores:
		GameState.cargo.append(ore_id)
		bin[ore_id] = 3
	GameState.depot_storage["fit_test"] = bin
	var world := MineWorld.new()
	add_child(world)
	world.setup(1)
	var breakdown := {}
	for ore_id: String in Balance.ores:
		breakdown[ore_id] = 4
	problems.clear()
	var screens: Array = [
		["shop", ShopScreen.new()], ["workshop", CosmeticsScreen.new()],
		["depot", DepotScreen.new("fit_test")], ["map", MapScreen.new(world, Vector2.ZERO)],
		["pause", PauseMenu.new()], ["quiz", FieldQuiz.new()],
		["bust", BustScreen.new("Your drill overheated and blew apart!")],
		["sell", SellPopup.new(9999, 12, breakdown)], ["guide", GuideScreen.new()],
	]
	for entry: Array in screens:
		var screen: Node = entry[1]
		add_child(screen)
		await _frames(3)
		_note_offscreen(screen, String(entry[0]), problems)
		if entry[0] == "guide":
			await _flip_pages(screen, "guide", problems)
		elif entry[0] == "quiz":
			var quiz := screen as FieldQuiz
			quiz._answer(false, quiz._pool[0]["q"])  # the explanation view is the tallest
			await _frames(3)
			_note_offscreen(screen, "quiz answer", problems)
		screen.queue_free()
		get_tree().paused = false  # depot and map pause the game while open
	_check(problems.is_empty(), "shop, depot, map, pause, quiz and popups fit the screen "
		+ ", ".join(PackedStringArray(problems)))
	world.queue_free()
	GameState.from_dict({})
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Click through every page of a list-and-detail screen, checking each page.
func _flip_pages(root: Node, what: String, problems: Array[String]) -> void:
	var pages := 0
	for b: Button in _all_of(root, "Button"):
		if not b.toggle_mode:
			continue
		b.button_pressed = true
		b.pressed.emit()
		await _frames(2)
		_note_offscreen(root, "%s page '%s'" % [what, b.text], problems)
		pages += 1
	if pages == 0:
		problems.append("%s has no pages to flip" % what)


func _note_offscreen(root: Node, what: String, problems: Array[String]) -> void:
	var view := get_viewport().get_visible_rect().grow(1.0)
	for c: Control in _all_of(root, "Control"):
		if not c.is_visible_in_tree() or c.size == Vector2.ZERO:
			continue
		var r := c.get_global_rect()
		if not view.encloses(r):
			problems.append("%s: %s at %s" % [what, c.get_class(), r])
			return


func _all_of(root: Node, type: String) -> Array:
	var out := []
	for child in root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child.is_class(type):
			out.append(child)
		out.append_array(_all_of(child, type))
	return out


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
