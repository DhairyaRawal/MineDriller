class_name MagmaSlug
extends EnemyBase
## Magma Slug (layer 2+): attacks your HEAT, not your hull.
##
## It is slow enough to outrun trivially, so it is never a reflex test. What it
## does is radiate heat: linger near one and your cooldown budget evaporates,
## which turns a corridor it occupies into a "how long dare I stay here?"
## decision. That makes it the first enemy that punishes greed rather than
## clumsiness, and it teaches the heat system by threatening it directly.

var _heat_per_sec := 22.0
var _aura := 118.0
var _glow: Sprite2D
var _t := 0.0


func _ready() -> void:
	radius = 20.0
	var stats: Dictionary = Balance.enemies.get("magma_slug", {})
	_heat_per_sec = float(stats.get("heat_per_sec", 22.0))
	_aura = float(stats.get("aura_px", 118.0))

	# Soft heat halo so the danger radius is visible before you are inside it.
	_glow = Sprite2D.new()
	_glow.texture = load("res://assets/textures/particle.png")
	_glow.modulate = Color(1.0, 0.42, 0.12, 0.30)
	_glow.scale = Vector2.ONE * (_aura / 8.0)
	_glow.z_index = -1
	add_child(_glow)


func display_name() -> String:
	return "a Magma Slug"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if world == null or player == null or not is_instance_valid(player):
		return

	_t += delta
	if _glow != null:
		_glow.modulate.a = 0.24 + 0.10 * sin(_t * 2.4)

	if player.state == Player.State.BUSTED:
		return
	var dist := position.distance_to(player.position)
	if dist < _aura:
		# Falls off with distance so edging closer feels progressively worse.
		var falloff := 1.0 - (dist / _aura)
		player.heat = minf(player.heat + _heat_per_sec * falloff * delta,
			float(Balance.heat["max"]))
		if randf() < delta * 3.0:
			Events.fx_burst.emit("drill", position + Vector2(0, -18),
				Vector2(0, -1), 1)


func _check_contact() -> void:
	# Damage is 0 by design: the slug's whole threat is thermal.
	pass
