class_name CrawlyElite
extends EnemyBase
## Elite Creepy Crawly (layer 3+): the patroller learns to chase. Bigger,
## faster and worth two hull, so late-layer caves stop being free real estate.

func _ready() -> void:
	radius = 18.0


func display_name() -> String:
	return "an Elite Crawly"


func _check_contact() -> void:
	if player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE:
		Events.fx_burst.emit("hit_crawly", position, Vector2.ZERO, 8)
		player.take_hit(damage, display_name())
