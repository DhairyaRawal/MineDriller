class_name ZombieMiner
extends EnemyBase
## Zombie Miner: shambles in its cave until the player gets close, then
## lurches after them. Grounded, so vertical escape works — but in narrow
## tunnels it blocks the way, matching the GDD's "later layers have enemies
## blocking the way".

var _lurch_timer := 0.0


func _ready() -> void:
	uses_gravity = true
	radius = 16.0


func _move(delta: float) -> void:
	# Lurching gait: brief pauses between steps when patrolling.
	if state == State.PATROL:
		_lurch_timer -= delta
		if _lurch_timer <= 0.0:
			_lurch_timer = randf_range(0.6, 1.4)
			if randf() < 0.3:
				dir = -dir
		if fmod(_lurch_timer, 0.8) > 0.45:
			velocity.x = 0.0
			velocity.y = minf(velocity.y + 1200.0 * delta, 900.0)
			var res := TerrainBody.move_circle(world, position, radius, velocity * delta)
			position = res["pos"]
			if res["hit_y"]:
				velocity.y = 0.0
			return
	super._move(delta)


func display_name() -> String:
	return "a Zombie Miner"
