class_name EnemyBase
extends Node2D
## EnemyBase: shared FSM (PATROL / CHASE) + circle-vs-pixel-terrain movement
## + contact damage for all enemies. Subclasses set stats from balance data
## and override movement flavor. Enemies despawn when far from the player
## (spawn rolls happen once per chunk per session, so cleared areas stay
## cleared).

enum State { PATROL, CHASE }

const CONTACT_RANGE := 44.0
const DESPAWN_RANGE := 1700.0

var world: MineWorld
var player: Player
var speed := 60.0
var damage := 1
var chase_range := 0.0
var uses_gravity := true
var radius := 15.0
## balance.json enemy id ("govt", "crawly_elite", ...). Lets systems that only
## see an EnemyBase -- like the contextual tips -- tell enemies apart.
var kind := ""

var state: int = State.PATROL
var dir := 1
var velocity := Vector2.ZERO
var _sprite: Sprite2D


func setup(enemy_world: MineWorld, target: Player, stats: Dictionary, texture_path: String) -> void:
	world = enemy_world
	player = target
	speed = float(stats["speed"])
	damage = int(stats["damage"])
	chase_range = float(stats["chase_range"])
	dir = 1 if randf() < 0.5 else -1
	_sprite = Sprite2D.new()
	_sprite.texture = load(texture_path)
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if world == null or player == null or not is_instance_valid(player):
		return
	if absf(player.position.y - position.y) > DESPAWN_RANGE:
		queue_free()
		return
	_update_state()
	_move(delta)
	_check_contact()
	if _sprite != null:
		_sprite.flip_h = dir < 0


func _update_state() -> void:
	if chase_range <= 0.0:
		state = State.PATROL
		return
	var dist := position.distance_to(player.position)
	state = State.CHASE if dist < chase_range and player.state != Player.State.BUSTED \
		else State.PATROL


func _move(delta: float) -> void:
	var vx := 0.0
	if state == State.CHASE:
		dir = 1 if player.position.x > position.x else -1
		vx = dir * speed * 1.25
	else:
		vx = dir * speed
	velocity.x = vx
	if uses_gravity:
		velocity.y = minf(velocity.y + 1200.0 * delta, 900.0)
	else:
		# Hovering enemies drift toward the player's height when chasing.
		var target_vy := 0.0
		if state == State.CHASE:
			target_vy = signf(player.position.y - position.y) * speed * 0.8
		velocity.y = lerpf(velocity.y, target_vy, 0.1)
	var res := TerrainBody.move_circle(world, position, radius, velocity * delta, 10.0)
	position = res["pos"]
	if res["hit_x"]:
		dir = -dir
		velocity.x = 0.0
	if res["hit_y"]:
		velocity.y = 0.0
	# Patrollers turn at ledges instead of walking off.
	if uses_gravity and state == State.PATROL and res["on_floor"]:
		var ahead := position + Vector2(dir * (radius + 10.0), radius + 12.0)
		if not world.is_solid_px(ahead):
			dir = -dir


func _check_contact() -> void:
	if player.state == Player.State.BUSTED:
		return
	if position.distance_to(player.position) < CONTACT_RANGE:
		player.take_hit(damage, display_name())


func display_name() -> String:
	return "an enemy"
