class_name GovtDriller
extends EnemyBase
## Government Driller: the GDD's signature threat. Hovers through caverns on
## patrol; when it spots you it locks on with a siren and closes in slowly.
## Contact means instant bust — cargo confiscated, back to the surface.
## Slow but relentless: the counter-play is spotting it early and routing
## around, which rewards map awareness over reflexes.

var _siren_on := false
var _beacon: Polygon2D


func _ready() -> void:
	uses_gravity = false
	radius = 22.0
	_beacon = Polygon2D.new()
	_beacon.polygon = PackedVector2Array([
		Vector2(-6, -30), Vector2(6, -30), Vector2(6, -22), Vector2(-6, -22)])
	_beacon.color = Color(0.9, 0.2, 0.2)
	add_child(_beacon)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var chasing := state == State.CHASE
	if chasing and not _siren_on:
		AudioManager.play("warning", -4.0, 0.7)
		Events.toast.emit("Government Driller has spotted you!")
	_siren_on = chasing
	if _beacon != null:
		_beacon.color = Color(1.0, 0.1, 0.1) if chasing and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 \
			else Color(0.6, 0.15, 0.15)


func display_name() -> String:
	return "a Government Driller"
