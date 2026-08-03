class_name RockGolem
extends EnemyBase
## Rock Golem (layer 2+): attacks your ROUTE.
##
## Slow, heavy, and it only wakes when you come close. The point is not the
## damage -- it is that a golem parked in a narrow shaft forces you to spend
## heat carving around it. It converts "enemy in the way" into an actual
## resource decision, which is the competitive edge the other chasers lack.
##
## It telegraphs clearly: a wake-up shudder and a colour shift, so a child can
## see the state change and learn the rule rather than being ambushed.

enum Mode { DORMANT, AWAKE }

var mode: int = Mode.DORMANT
var _wake_timer := 0.0


func _ready() -> void:
	radius = 22.0


func display_name() -> String:
	return "a Rock Golem"


func _update_state() -> void:
	var dist := position.distance_to(player.position)
	if mode == Mode.DORMANT:
		if dist < chase_range and player.state != Player.State.BUSTED:
			mode = Mode.AWAKE
			_wake_timer = 0.55
			AudioManager.play("impact_rock", -4.0, 0.7)
			Events.fx_burst.emit("drill", position, Vector2(0, -1), 8)
			Events.fx_shake.emit(0.45)
		state = State.PATROL
		return
	state = State.CHASE if dist < chase_range * 1.6 else State.PATROL


func _move(delta: float) -> void:
	if mode == Mode.DORMANT:
		# Rooted until woken: it reads as scenery you can choose to disturb.
		velocity.x = 0.0
		velocity.y = minf(velocity.y + 1200.0 * delta, 900.0)
		var res := TerrainBody.move_circle(world, position, radius,
			velocity * delta, 10.0)
		position = res["pos"]
		if res["hit_y"]:
			velocity.y = 0.0
		return

	if _wake_timer > 0.0:
		# Standing-up animation window; it cannot move yet, so there is a real
		# chance to run past instead of fighting for space.
		_wake_timer -= delta
		modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.4, 1.1, 0.9),
			sin(_wake_timer * 22.0) * 0.5 + 0.5)
		velocity.x = 0.0
		super._move(delta)
		return

	modulate = Color.WHITE
	super._move(delta)


func _check_contact() -> void:
	if mode == Mode.DORMANT or player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE + 6.0:
		Events.fx_burst.emit("impact", position, Vector2.ZERO, 10)
		Events.fx_shake.emit(0.8)
		player.take_hit(damage, display_name())
