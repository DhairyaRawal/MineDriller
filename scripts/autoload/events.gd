extends Node
## Events: global signal bus. Systems communicate through these signals so
## gameplay, UI and audio stay decoupled (no hard references between them).

# Economy / cargo
signal money_changed(money: int)
signal ether_changed(ether: int)
signal cargo_changed(used: int, capacity: int)
signal ore_collected(ore_id: String)
## A full cargo bay upgraded itself: `added_id` displaced `removed_id`,
## which is erased rather than dropped.
signal ore_swapped(added_id: String, removed_id: String)
signal cargo_sold(total_money: int, total_ether: int, breakdown: Dictionary)
signal cargo_full()

# Player / run state
signal heat_changed(heat: float, ambient_floor: float, max_heat: float)
signal hull_changed(hp: int, max_hp: int)
signal rockets_changed(count: int, max_count: int)
signal depth_changed(row: int, km: float, layer_id: int)
signal layer_reached(layer_id: int)
signal player_busted(reason: String)
signal dive_completed(earned: int)
signal treasure_opened(money: int, ores: Array)

# Depots
signal depot_proximity(depot_id: String)  # "" = none nearby
signal depot_changed(depot_id: String)

# Meta
signal upgrade_purchased(id: String, new_level: int)
signal achievement_unlocked(id: String)
signal codex_discovered(ore_id: String)
## The tutorial's current objective. Persistent (unlike a toast) until the next
## step replaces it; an empty string hides it.
signal ftue_objective(text: String)
signal toast(text: String)

# Cosmetics
signal cosmetic_selected(category: String, item_id: String)

# Presentation (gameplay emits; the FX layer and camera listen). Keeping these
# on the bus means the player and enemies never hold a reference to the camera
# or the particle layer.
signal fx_burst(kind: String, world_pos: Vector2, dir: Vector2, count: int)
signal fx_shake(strength: float)
