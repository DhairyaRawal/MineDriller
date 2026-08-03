class_name Tutorial
extends Node
## Tutorial: lightweight, event-driven onboarding. Instead of a modal
## click-through, hints ride the toast system exactly when each mechanic
## first becomes relevant. Marks itself done after the first upgrade and
## never bothers the player again (persisted in the save).

var _shown := {}


func _ready() -> void:
	if GameState.tutorial_done:
		queue_free()
		return
	Events.ore_collected.connect(_on_ore)
	Events.heat_changed.connect(_on_heat)
	Events.cargo_sold.connect(_on_sold)
	Events.upgrade_purchased.connect(_on_upgrade)
	Events.cargo_full.connect(_on_full)
	_step("welcome", "Hold DRILL to dig down. Push into a wall to dig sideways. Find ores, sell on the surface!")


func _step(id: String, text: String) -> void:
	if _shown.has(id):
		return
	_shown[id] = true
	Events.tutorial_step.emit(text)


func _on_ore(_ore_id: String) -> void:
	_step("ore", "Ore collected! You can't drill straight up - hold JUMP + a direction into a wall to carve a ramp back to the surface.")


func _on_heat(heat: float, _floor_heat: float, max_heat: float) -> void:
	if heat > max_heat * 0.6:
		_step("heat", "Heat is climbing! Stop drilling for a moment and let it cool.")


func _on_sold(_money: int, _ether: int, _breakdown: Dictionary) -> void:
	_step("sold", "Cargo sold! Tap SHOP to upgrade your drill and go deeper.")


func _on_full() -> void:
	_step("full", "Cargo bay is full - carve a ramp up and sell before mining more.")


func _on_upgrade(_id: String, _level: int) -> void:
	_step("upgrade", "Upgraded! Deeper layers hide rarer ores - and tougher rock.")
	GameState.tutorial_done = true
	SaveManager.request_save()
	queue_free()
