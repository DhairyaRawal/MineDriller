class_name Crawly
extends EnemyBase
## Creepy Crawly: dumb cave patroller. Walks back and forth along the floor
## of its pocket, turning at walls and ledges. Early-game threat you can
## route around — the GDD wants initial layers to have ways past enemies.


func _ready() -> void:
	uses_gravity = true
	radius = 13.0
	# Slight wobble so groups don't move in lockstep.
	speed *= randf_range(0.85, 1.15)


func display_name() -> String:
	return "a Creepy Crawly"
