class_name PlasmaDriller
extends EnemyBase
## Plasma Driller (layer 4+ mini-boss): a hovering Government Driller with a
## longer leash and an audible spin-up, so the instant-bust threat is
## telegraphed well before contact.

var _laser_timer := 0.0


func _ready() -> void:
	radius = 20.0
	uses_gravity = false


func display_name() -> String:
	return "a Plasma Driller"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if world == null or player == null or not is_instance_valid(player):
		return
	_laser_timer -= delta
	if state == State.CHASE and _laser_timer <= 0.0:
		_laser_timer = randf_range(1.1, 2.2)
		AudioManager.play("laser_drill", -4.0, randf_range(0.85, 1.05))
		Events.fx_burst.emit("hit_govt", position, Vector2.ZERO, 5)


func _check_contact() -> void:
	if player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE + 8.0:
		Events.fx_burst.emit("hit_govt", position, Vector2.ZERO, 14)
		Events.fx_shake.emit(1.2)
		player.take_hit(damage, display_name())
