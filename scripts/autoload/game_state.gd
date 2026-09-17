extends Node
## GameState: all persistent player progress plus the state of the current
## run (cargo). Derived stats (drill speed, cooling, cargo capacity...) are
## computed here from upgrade levels so gameplay code never does math on
## raw balance data.

# ---- persistent ----
var money := 0
var ether := 0
var upgrade_levels := {
	"drill_speed": 1, "drill_bit": 1, "cooling": 1,
	"cargo": 1, "hull": 1, "mobility": 1, "rockets": 1,
}
var stats := {
	"total_earned": 0, "dives": 0, "busts": 0, "ores_mined": 0,
	"deepest_km": 0.0, "playtime_sec": 0.0, "treasures_found": 0,
	"enemies_escaped": 0, "clean_dive_streak": 0,
}
var codex_discovered: Array = []       # ore ids seen at least once
var tips_seen: Array = []              # tip ids whose floating '?' the player has already read
var achievements_unlocked: Array = []  # achievement ids
var tutorial_done := false
var daily_best := {}                   # date string -> best money in one dive
var world_seed := 0
var world_diff := {}                   # opaque MineWorld.export_diff() payload
var last_position := Vector2.ZERO      # ZERO = no save yet, spawn at the fixed surface point
var depot_storage := {}                # depot_id -> {ore_id: count}, bust-proof mid-dive storage

# ---- cosmetics (ether currency cosmetics) ----
var drill_skin_owned: Array = ["standard"]  # unlock skins with ether
var drill_skin_selected := "standard"
var trail_effect_owned: Array = ["default"]  # particle trail cosmetics
var trail_effect_selected := "default"

# ---- current run ----
var cargo: Array = []                  # array of ore id strings
var run_earn_preview := 0              # $ value of current cargo
var rockets := 0                       # escape rockets left this dive; refilled at the surface
var daily_mode := false

# ---- first-time user experience ----
## True while the tutorial level is running. The tutorial plays on a SANDBOX
## copy of the player's state, never the real one: see begin_ftue().
var ftue_mode := false
var _ftue_restore := {}                # the real state, snapshotted on entry


func _ready() -> void:
	if world_seed == 0:
		world_seed = randi()
	# Autoload order puts Balance ahead of GameState, so this is safe here.
	# A save loading afterwards overwrites it in from_dict().
	rockets = max_rockets()
	set_process(true)


func _process(delta: float) -> void:
	stats["playtime_sec"] = float(stats["playtime_sec"]) + delta


# ------------------------------------------------------------- derived stats

func drill_tiles_per_sec() -> float:
	var p := Balance.player
	return float(p["drill_speed_base"]) \
		+ float(p["drill_speed_per_level"]) * float(int(upgrade_levels["drill_speed"]) - 1)


func bit_level() -> int:
	return int(upgrade_levels["drill_bit"])


func move_speed() -> float:
	var p := Balance.player
	return float(p["move_speed_base"]) \
		+ float(p["move_speed_per_level"]) * float(int(upgrade_levels["mobility"]) - 1)


func cargo_capacity() -> int:
	var p := Balance.player
	return int(p["cargo_base"]) + int(p["cargo_per_level"]) * (int(upgrade_levels["cargo"]) - 1)


func max_hull() -> int:
	var p := Balance.player
	return int(p["hull_base"]) + int(p["hull_per_level"]) * (int(upgrade_levels["hull"]) - 1)


func max_rockets() -> int:
	var p := Balance.player
	return int(p["rockets_base"]) \
		+ int(p["rockets_per_level"]) * (int(upgrade_levels["rockets"]) - 1)


## Spend one escape rocket. False if the bay is empty.
func use_rocket() -> bool:
	if rockets <= 0:
		return false
	rockets -= 1
	Events.rockets_changed.emit(rockets, max_rockets())
	SaveManager.request_save()
	return true


## Rockets are a per-dive resource, not a purchase: surfacing refills them.
func refill_rockets() -> void:
	var cap := max_rockets()
	if rockets >= cap:
		rockets = cap
		return
	rockets = cap
	Events.rockets_changed.emit(rockets, cap)
	SaveManager.request_save()


func cool_rate() -> float:
	var h := Balance.heat
	return float(h["cool_per_sec_base"]) \
		+ float(h["cool_per_sec_per_level"]) * float(int(upgrade_levels["cooling"]) - 1)


## Ambient heat floor for a depth row: the cooldown bar effectively shrinks
## with depth (per the GDD), softened by the cooling upgrade.
func ambient_floor(row: int) -> float:
	var h := Balance.heat
	var depth_frac := clampf(float(row) / float(Balance.world["max_depth_row"]), 0.0, 1.0)
	var floor_heat := float(h["ambient_floor_max"]) * depth_frac
	var reduction := float(h["ambient_floor_reduction_per_level"]) * float(int(upgrade_levels["cooling"]) - 1)
	return floor_heat * maxf(0.0, 1.0 - reduction)


# ------------------------------------------------------------------ economy

func add_money(amount: int) -> void:
	money += amount
	if amount > 0:
		stats["total_earned"] = int(stats["total_earned"]) + amount
		if int(stats["total_earned"]) >= 1000:
			unlock_achievement("rich_1k")
		if int(stats["total_earned"]) >= 10000:
			unlock_achievement("rich_10k")
	Events.money_changed.emit(money)


func add_ether(amount: int) -> void:
	ether += amount
	Events.ether_changed.emit(ether)


## Collect an ore. With room in the bay it is simply added. With a FULL bay
## the ore replaces the least valuable thing aboard, provided it actually
## beats it -- so a full cargo keeps upgrading itself instead of locking the
## player out of every vein they find. The ore that loses the comparison is
## erased, not dropped. Returns whether the ore ended up in the bay.
func try_collect_ore(ore_id: String) -> bool:
	var value := int(Balance.ores[ore_id]["value"])
	if cargo.size() >= cargo_capacity():
		var worst_idx := _cheapest_cargo_index()
		# Ties don't swap: trading iron for iron is pure churn.
		if worst_idx < 0 or int(Balance.ores[String(cargo[worst_idx])]["value"]) >= value:
			Events.cargo_full.emit()
			return false
		var removed_id := String(cargo[worst_idx])
		cargo.remove_at(worst_idx)
		run_earn_preview -= int(Balance.ores[removed_id]["value"])
		Events.ore_swapped.emit(ore_id, removed_id)
	cargo.append(ore_id)
	run_earn_preview += value
	stats["ores_mined"] = int(stats["ores_mined"]) + 1
	unlock_achievement("first_ore")
	if ore_id == "opal":
		unlock_achievement("opal_found")
	discover_ore(ore_id)
	Events.ore_collected.emit(ore_id)
	Events.cargo_changed.emit(cargo.size(), cargo_capacity())
	return true


## Index of the least valuable ore currently aboard, or -1 if the bay is empty.
func _cheapest_cargo_index() -> int:
	var best := -1
	var best_value := 0
	for i in cargo.size():
		var v := int(Balance.ores[String(cargo[i])]["value"])
		if best < 0 or v < best_value:
			best = i
			best_value = v
	return best


func sell_cargo() -> void:
	if cargo.is_empty():
		return
	var breakdown := {}
	var total_money := 0
	var total_ether := 0
	for ore_id: String in cargo:
		var ore: Dictionary = Balance.ores[ore_id]
		total_money += int(ore["value"])
		total_ether += int(ore["ether"])
		breakdown[ore_id] = int(breakdown.get(ore_id, 0)) + 1
	cargo.clear()
	run_earn_preview = 0
	add_money(total_money)
	if total_ether > 0:
		add_ether(total_ether)
	if daily_mode:
		_record_daily(total_money)
	Events.cargo_sold.emit(total_money, total_ether, breakdown)
	Events.cargo_changed.emit(0, cargo_capacity())
	Events.dive_completed.emit(total_money)
	stats["dives"] = int(stats["dives"]) + 1
	stats["clean_dive_streak"] = int(stats["clean_dive_streak"]) + 1
	if int(stats["clean_dive_streak"]) >= 5:
		unlock_achievement("survivor_5")
	SaveManager.request_save()


## Bust: the GDD lose condition. All cargo is lost; money is kept.
func lose_cargo(reason: String) -> void:
	cargo.clear()
	run_earn_preview = 0
	stats["busts"] = int(stats["busts"]) + 1
	stats["clean_dive_streak"] = 0
	Events.cargo_changed.emit(0, cargo_capacity())
	Events.player_busted.emit(reason)
	SaveManager.request_save()


# ----------------------------------------------------------------- upgrades

func upgrade_cost(id: String) -> int:
	return Balance.upgrade_cost(id, int(upgrade_levels[id]))


func can_buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	return cost > 0 and money >= cost


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or money < cost:
		return false
	money -= cost
	upgrade_levels[id] = int(upgrade_levels[id]) + 1
	Events.money_changed.emit(money)
	Events.upgrade_purchased.emit(id, upgrade_levels[id])
	SaveManager.request_save()
	return true


## The cheapest affordable-or-not next upgrade: shown on the HUD as the
## current $ target (per the GDD's "target highlighted on the HUD").
func next_upgrade_target() -> Dictionary:
	var best_id := ""
	var best_cost := -1
	for id: String in upgrade_levels:
		var cost := upgrade_cost(id)
		if cost > 0 and (best_cost < 0 or cost < best_cost):
			best_cost = cost
			best_id = id
	if best_id == "":
		return {}
	return {"id": best_id, "cost": best_cost}


# ------------------------------------------------------------------- depots

## Deposited ore lives here, not in `cargo`, so lose_cargo() (bust) never
## touches it -- that's the entire point of a depot. It's still not money:
## the player has to withdraw it back into cargo and carry it to the surface
## to sell, same as any other ore.

func depot_capacity() -> int:
	return int(Balance.depot["capacity"])


func depot_used(depot_id: String) -> int:
	var bin: Dictionary = depot_storage.get(depot_id, {})
	var total := 0
	for count in bin.values():
		total += int(count)
	return total


func deposit_ore(depot_id: String, ore_id: String) -> bool:
	var idx := cargo.find(ore_id)
	if idx < 0 or depot_used(depot_id) >= depot_capacity():
		return false
	cargo.remove_at(idx)
	run_earn_preview -= int(Balance.ores[ore_id]["value"])
	if not depot_storage.has(depot_id):
		depot_storage[depot_id] = {}
	var bin: Dictionary = depot_storage[depot_id]
	bin[ore_id] = int(bin.get(ore_id, 0)) + 1
	Events.cargo_changed.emit(cargo.size(), cargo_capacity())
	Events.depot_changed.emit(depot_id)
	SaveManager.request_save()
	return true


func withdraw_ore(depot_id: String, ore_id: String) -> bool:
	var bin: Dictionary = depot_storage.get(depot_id, {})
	if int(bin.get(ore_id, 0)) <= 0 or cargo.size() >= cargo_capacity():
		return false
	bin[ore_id] = int(bin[ore_id]) - 1
	if int(bin[ore_id]) <= 0:
		bin.erase(ore_id)
	cargo.append(ore_id)
	run_earn_preview += int(Balance.ores[ore_id]["value"])
	Events.cargo_changed.emit(cargo.size(), cargo_capacity())
	Events.depot_changed.emit(depot_id)
	SaveManager.request_save()
	return true


# --------------------------------------------------------- cosmetics

func buy_drill_skin(skin_id: String) -> bool:
	if skin_id in drill_skin_owned:
		return false
	var cost := int(Balance.cosmetics["drill_skins"][skin_id]["cost"])
	if ether < cost:
		return false
	ether -= cost
	drill_skin_owned.append(skin_id)
	Events.ether_changed.emit(ether)
	SaveManager.request_save()
	return true


func select_drill_skin(skin_id: String) -> bool:
	if skin_id not in drill_skin_owned:
		return false
	drill_skin_selected = skin_id
	Events.cosmetic_selected.emit("drill_skin", skin_id)
	SaveManager.request_save()
	return true


func buy_trail_effect(trail_id: String) -> bool:
	if trail_id in trail_effect_owned:
		return false
	var cost := int(Balance.cosmetics["trails"][trail_id]["cost"])
	if ether < cost:
		return false
	ether -= cost
	trail_effect_owned.append(trail_id)
	Events.ether_changed.emit(ether)
	SaveManager.request_save()
	return true


func select_trail_effect(trail_id: String) -> bool:
	if trail_id not in trail_effect_owned:
		return false
	trail_effect_selected = trail_id
	Events.cosmetic_selected.emit("trail", trail_id)
	SaveManager.request_save()
	return true


# --------------------------------------------------------- codex & progress

func discover_ore(ore_id: String) -> void:
	if ore_id in codex_discovered:
		return
	codex_discovered.append(ore_id)
	Events.codex_discovered.emit(ore_id)
	if codex_discovered.size() >= Balance.ores.size():
		unlock_achievement("codex_full")


func unlock_achievement(id: String) -> void:
	if id in achievements_unlocked or not Balance.achievements.has(id):
		return
	achievements_unlocked.append(id)
	Events.achievement_unlocked.emit(id)
	Events.toast.emit("Achievement: %s" % Balance.achievements[id]["name"])
	SaveManager.request_save()


func note_depth(row: int) -> void:
	var km := Balance.km_for_row(row)
	if km > float(stats["deepest_km"]):
		stats["deepest_km"] = km
	var layer_id := Balance.layer_id_for_row(row)
	if layer_id >= 2:
		unlock_achievement("reach_l2")
	if layer_id >= 3:
		unlock_achievement("reach_l3")
	if layer_id >= 4:
		unlock_achievement("reach_l4")
	if layer_id >= 5:
		unlock_achievement("reach_l5")


# ------------------------------------------------------------- daily runs

func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func daily_seed() -> int:
	return hash(today_key())


func _record_daily(earned: int) -> void:
	var key := today_key()
	if earned > int(daily_best.get(key, 0)):
		daily_best[key] = earned
		Events.toast.emit("New daily best: %d $" % earned)


# --------------------------------------------------------- new drilling

## Start a fresh world while keeping meta-progression (money, ether, upgrade
## levels, stats, codex, achievements, cosmetics). Distinct from a full save
## wipe (SaveManager.wipe() + from_dict({}), used by "Reset Save Data") --
## this is "new world, same career," not "start over."
func start_new_drilling() -> void:
	world_seed = randi()
	world_diff = {}
	last_position = Vector2.ZERO
	cargo.clear()
	run_earn_preview = 0
	depot_storage = {}
	rockets = max_rockets()
	SaveManager.request_save()


# ---------------------------------------------------------- contextual tips

## Retire a tip's floating '?'. Keyed by tip id, not by instance, so reading the
## water tip once retires the '?' over every water pocket in the world -- and
## reading an enemy's tip also covers its elite variant, which shares the id.
## The tip itself stays readable in the pause menu's GUIDE.
func mark_tip_seen(id: String) -> void:
	if id == "" or id in tips_seen:
		return
	tips_seen.append(id)
	SaveManager.request_save()


func is_tip_seen(id: String) -> bool:
	return id in tips_seen


# ------------------------------------------------ first-time user experience

## Whether this run's world state (dug tunnels, position) should be saved.
## Daily Challenges and the tutorial are both throwaway worlds.
func persists_world() -> bool:
	return not daily_mode and not ftue_mode


## Enter the tutorial on a sandbox copy of the player's state.
##
## The real state is snapshotted first and restored in finish_ftue(). This is
## what makes a MANDATORY tutorial safe: a returning player whose save predates
## the tutorial (tutorial_done == false, but real money or a dive in progress)
## would otherwise have that progress overwritten by the tutorial's 0$ start.
func begin_ftue() -> void:
	_ftue_restore = to_dict()
	ftue_mode = true
	daily_mode = false
	money = 0
	cargo.clear()
	run_earn_preview = 0
	for id: String in upgrade_levels:
		upgrade_levels[id] = 1
	rockets = max_rockets()


## Walk away from an unfinished tutorial (quit to menu). Restores the real
## state and grants nothing; the next run starts the tutorial over.
func abandon_ftue() -> void:
	if not ftue_mode:
		return
	var restore := _ftue_restore
	ftue_mode = false
	_ftue_restore = {}
	from_dict(restore)


## Leave the tutorial: restore the real state, then apply what it earns.
##
## Carried over: the Drill Bit Lv2 the tutorial is built around, plus anything
## *learned* -- codex entries, achievements and tips already read -- so a
## Discovery Card or a '?' seen in the tutorial doesn't pop up a second time
## in the real game. Everything economic from the sandbox (money, cargo,
## stats) is discarded.
func finish_ftue() -> void:
	if not ftue_mode:
		return
	var learned_codex := codex_discovered.duplicate()
	var learned_awards := achievements_unlocked.duplicate()
	var learned_tips := tips_seen.duplicate()
	var restore := _ftue_restore
	ftue_mode = false
	_ftue_restore = {}
	from_dict(restore)

	upgrade_levels["drill_bit"] = maxi(int(upgrade_levels["drill_bit"]), 2)
	for ore_id in learned_codex:
		if ore_id not in codex_discovered:
			codex_discovered.append(ore_id)
	for award_id in learned_awards:
		if award_id not in achievements_unlocked:
			achievements_unlocked.append(award_id)
	for tip_id in learned_tips:
		if tip_id not in tips_seen:
			tips_seen.append(tip_id)
	tutorial_done = true
	rockets = max_rockets()
	SaveManager.request_save()


# ------------------------------------------------------------ serialization

func to_dict() -> Dictionary:
	# Mid-tutorial, the live fields are a sandbox. SaveManager autosaves on a
	# timer and on app backgrounding, so without this, quitting during the
	# tutorial would persist 0$ over the player's real progress.
	if ftue_mode:
		return _ftue_restore.duplicate(true)
	# Deep-duplicate containers so the snapshot can never be mutated by
	# later changes to live state (or vice versa).
	return {
		"money": money,
		"ether": ether,
		"upgrade_levels": upgrade_levels.duplicate(true),
		"stats": stats.duplicate(true),
		"codex_discovered": codex_discovered.duplicate(true),
		"tips_seen": tips_seen.duplicate(),
		"achievements_unlocked": achievements_unlocked.duplicate(true),
		"tutorial_done": tutorial_done,
		"daily_best": daily_best.duplicate(true),
		"world_seed": world_seed,
		"world_diff": world_diff.duplicate(true),
		"last_position": [last_position.x, last_position.y],
		"cargo": cargo.duplicate(),
		"rockets": rockets,
		"depot_storage": depot_storage.duplicate(true),
		"drill_skin_owned": drill_skin_owned.duplicate(),
		"drill_skin_selected": drill_skin_selected,
		"trail_effect_owned": trail_effect_owned.duplicate(),
		"trail_effect_selected": trail_effect_selected,
	}


func from_dict(d: Dictionary) -> void:
	money = int(d.get("money", 0))
	ether = int(d.get("ether", 0))
	var levels: Dictionary = d.get("upgrade_levels", {})
	for id: String in upgrade_levels:
		upgrade_levels[id] = clampi(int(levels.get(id, 1)), 1, Balance.upgrade_max(id))
	var s: Dictionary = d.get("stats", {})
	for key: String in stats:
		if s.has(key):
			stats[key] = s[key]
	codex_discovered = (d.get("codex_discovered", []) as Array).duplicate()
	tips_seen = (d.get("tips_seen", []) as Array).duplicate()
	achievements_unlocked = (d.get("achievements_unlocked", []) as Array).duplicate()
	tutorial_done = bool(d.get("tutorial_done", false))
	daily_best = (d.get("daily_best", {}) as Dictionary).duplicate()
	world_seed = int(d.get("world_seed", randi()))
	if world_seed == 0:
		world_seed = randi()
	world_diff = (d.get("world_diff", {}) as Dictionary).duplicate(true)
	var pos_arr: Array = d.get("last_position", [])
	last_position = Vector2(float(pos_arr[0]), float(pos_arr[1])) if pos_arr.size() >= 2 else Vector2.ZERO
	cargo = (d.get("cargo", []) as Array).duplicate()
	# Clamped in case a Rocket Bay level was lost to a reset or an older save.
	rockets = clampi(int(d.get("rockets", max_rockets())), 0, max_rockets())
	depot_storage = (d.get("depot_storage", {}) as Dictionary).duplicate(true)
	# Recomputed rather than saved separately, so it can never drift from cargo.
	run_earn_preview = 0
	for ore_id: String in cargo:
		run_earn_preview += int((Balance.ores.get(ore_id, {}) as Dictionary).get("value", 0))
	drill_skin_owned = (d.get("drill_skin_owned", ["standard"]) as Array).duplicate()
	drill_skin_selected = d.get("drill_skin_selected", "standard") as String
	trail_effect_owned = (d.get("trail_effect_owned", ["default"]) as Array).duplicate()
	trail_effect_selected = d.get("trail_effect_selected", "default") as String
