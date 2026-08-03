class_name CrystalBat
extends EnemyBase
## Crystal Bat (layer 3+): attacks your HULL, and your composure.
##
## It flies, ignores terrain footing, and has the longest detection range in
## the game, so it is the enemy that finds YOU. The sine-wave flight path makes
## it genuinely awkward to dodge in a tight shaft, which pushes players to carve
## wider rooms -- a real tactical choice rather than "hold the run button".

var _phase := 0.0
var _swoop := 0.0


func _ready() -> void:
	radius = 15.0
	uses_gravity = false
	_phase = randf() * TAU


func display_name() -> String:
	return "a Crystal Bat"


func _move(delta: float) -> void:
	_phase += delta * 6.5

	if state == State.CHASE:
		dir = 1 if player.position.x > position.x else -1
		var to_player := (player.position - position).normalized()
		velocity.x = to_player.x * speed
		# Erratic vertical weave layered on top of the pursuit vector.
		velocity.y = to_player.y * speed * 0.75 + sin(_phase) * 150.0
		_swoop = 1.0
	else:
		velocity.x = dir * speed * 0.55
		velocity.y = sin(_phase * 0.5) * 90.0

	var res := TerrainBody.move_circle(world, position, radius,
		velocity * delta, 6.0)
	position = res["pos"]
	if res["hit_x"]:
		dir = -dir
		velocity.x = 0.0
	if res["hit_y"]:
		velocity.y = 0.0


func _check_contact() -> void:
	if player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE:
		Events.fx_burst.emit("ether", position, Vector2.ZERO, 6)
		Events.fx_shake.emit(0.5)
		player.take_hit(damage, display_name())
