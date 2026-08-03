class_name ZombieElite
extends EnemyBase
## Elite Zombie Miner (layer 4+): outruns the pod at low Treads levels, so
## deep dives with an unupgraded drill become a routing problem.

func _ready() -> void:
	radius = 16.0


func display_name() -> String:
	return "an Elite Miner"


func _check_contact() -> void:
	if player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE:
		Events.fx_burst.emit("hit_zombie", position, Vector2.ZERO, 8)
		player.take_hit(damage, display_name())
