extends Node
## Balance: single source of truth for all tuning data.
## Loads data/balance.json once at startup; every system reads through here
## so designers can rebalance the game without touching code.

var data: Dictionary = {}

# Convenience caches
var world: Dictionary
var layers: Array
var ores: Dictionary
var heat: Dictionary
var player: Dictionary
var upgrades: Dictionary
var enemies: Dictionary
var enemy_spawn: Dictionary
var treasure: Dictionary
var depot: Dictionary
var achievements: Dictionary
var cosmetics: Dictionary

# Educational content lives in its own file so tuning numbers and teaching
# copy can be edited independently (a designer and a science reviewer are
# rarely the same person).
var codex: Dictionary = {}
var codex_ores: Dictionary = {}
var codex_layers: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
	assert(f != null, "balance.json missing")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "balance.json is not valid JSON")
	data = parsed
	_load_codex()
	world = data["world"]
	layers = data["layers"]
	ores = data["ores"]
	heat = data["heat"]
	player = data["player"]
	upgrades = data["upgrades"]
	enemies = data["enemies"]
	enemy_spawn = data["enemy_spawn"]
	treasure = data["treasure"]
	depot = data["depot"]
	achievements = data["achievements"]
	cosmetics = data["cosmetics"]


func _load_codex() -> void:
	var f := FileAccess.open("res://data/codex.json", FileAccess.READ)
	if f == null:
		push_warning("codex.json missing - educational content disabled")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is not Dictionary:
		push_warning("codex.json is not valid JSON")
		return
	codex = parsed
	codex_ores = codex.get("ores", {})
	codex_layers = codex.get("layers", {})


## Educational entry for an ore, or {} if none is authored.
func ore_facts(ore_id: String) -> Dictionary:
	return codex_ores.get(ore_id, {})


## Educational entry for an Earth layer (1-5), or {} if none.
func layer_facts(layer_id: int) -> Dictionary:
	return codex_layers.get(str(layer_id), {})


## Layer dictionary for a world row (1-based rows below the surface).
func layer_for_row(row: int) -> Dictionary:
	for layer: Dictionary in layers:
		if row >= int(layer["row_start"]) and row < int(layer["row_end"]):
			return layer
	if row >= int(layers[layers.size() - 1]["row_end"]):
		return layers[layers.size() - 1]
	return layers[0]


func layer_id_for_row(row: int) -> int:
	return int(layer_for_row(row)["id"])


## Depth in km shown on the HUD for a given row.
func km_for_row(row: int) -> float:
	return maxf(0.0, row * float(world["km_per_tile"]))


## Deepest layer id reached for a recorded depth in km. Used by the codex and
## the quiz, which only ever teach or test layers the player has actually seen.
func layer_id_for_km(km: float) -> int:
	if km <= 0.0:
		return 1
	return layer_id_for_row(int(km / maxf(float(world["km_per_tile"]), 0.001)))


## Cost of buying the NEXT level when currently at `level` (levels start at 1).
func upgrade_cost(id: String, level: int) -> int:
	var u: Dictionary = upgrades[id]
	if level >= int(u["max_level"]):
		return -1
	if u.has("costs"):
		var costs: Array = u["costs"]
		return int(costs[level - 1])
	return int(round(float(u["base_cost"]) * pow(float(u["cost_mult"]), level - 1)))


func upgrade_max(id: String) -> int:
	return int(upgrades[id]["max_level"])


## Weighted random ore id for a layer. `rare_shift` (0..1) boosts rare ores
## near the bottom of a layer, per the GDD's ore distribution rule.
func pick_ore(layer: Dictionary, rare_shift: float, rand: float) -> String:
	var weights: Dictionary = layer["ore_weights"]
	var total := 0.0
	var adjusted := {}
	for ore_id: String in weights:
		var rarity := float(ores[ore_id]["rarity"])
		var w := float(weights[ore_id]) * (1.0 + rare_shift * rarity * 0.35)
		adjusted[ore_id] = w
		total += w
	var roll := rand * total
	for ore_id: String in adjusted:
		roll -= adjusted[ore_id]
		if roll <= 0.0:
			return ore_id
	return adjusted.keys()[0]
