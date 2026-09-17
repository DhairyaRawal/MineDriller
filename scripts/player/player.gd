class_name Player
extends Node2D
## Player: the drill pod, now a circle body carving organic tunnels through
## pixel terrain (see MineWorld.carve_circle / TerrainBody).
##
## Movement rules (from playtest feedback on the first build):
## - NO free flight. On the ground you walk, jump (UP), and drill.
## - DRILL (down) carves straight down. Pushing into a wall carves sideways.
## - Holding UP + a direction carves a rising diagonal ramp you walk up —
##   so the way back to the surface is a ROUTE you plan and carve, not an
##   elevator. Straight-up drilling is impossible; vertical shafts are
##   one-way drops.
## - Heat, hull, bust rules unchanged from the GDD model.

signal chest_opened(cell: Vector2i)
signal busted(reason: String)

enum State { DRIVE, BUSTED }

var world: MineWorld
var state: int = State.DRIVE
var velocity := Vector2.ZERO
var heat := 0.0
var hull := 3
var facing := 1
var drilling := false          # actively removing terrain this frame

var _radius := 18.0
var _invuln := 0.0
var _last_row := -9999
var _in_water := false
var _wet_cells := {}
var _bit_toast_cooldown := 0.0
var _cargo_toast_cooldown := 0.0
var _rocket_toast_cooldown := 0.0
## Fixed for this player's lifetime. Read live, it would flip the moment the
## tutorial finishes -- a frame before the scene swaps -- and write the
## tutorial arena's coordinates into the real game's resume point.
var _persists_world := true
var _warned := false
var _drill_was_hard := false
var _coyote := 0.0
var _fx_accum := 0.0

var _sprite: Sprite2D
var _dust: CPUParticles2D


func _ready() -> void:
	hull = GameState.max_hull()
	_radius = float(Balance.player["radius"])
	_sprite = Sprite2D.new()
	# Load selected drill skin cosmetic
	var skin_name := GameState.drill_skin_selected
	var skin_path := "res://assets/textures/player_%s.png" % skin_name
	_sprite.texture = load(skin_path)
	add_child(_sprite)
	_dust = CPUParticles2D.new()
	_dust.texture = load("res://assets/textures/particle.png")
	_dust.emitting = false
	_dust.amount = 14
	_dust.lifetime = 0.5
	_dust.spread = 40.0
	_dust.initial_velocity_min = 60.0
	_dust.initial_velocity_max = 140.0
	_dust.gravity = Vector2(0, 300)
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 1.0
	_dust.position = Vector2(0, 24)
	add_child(_dust)
	Events.hull_changed.emit(hull, GameState.max_hull())
	Events.ore_swapped.connect(_on_ore_swapped)
	_persists_world = GameState.persists_world()


func _physics_process(delta: float) -> void:
	if world == null or state == State.BUSTED:
		return
	_invuln = maxf(0.0, _invuln - delta)
	_bit_toast_cooldown = maxf(0.0, _bit_toast_cooldown - delta)
	_cargo_toast_cooldown = maxf(0.0, _cargo_toast_cooldown - delta)
	_rocket_toast_cooldown = maxf(0.0, _rocket_toast_cooldown - delta)
	_coyote = maxf(0.0, _coyote - delta)
	if Input.is_action_just_pressed("fire_rocket"):
		_fire_rocket()
	_process_move_and_drill(delta)
	_process_heat(delta)
	_process_environment()
	_report_depth()
	# Daily Challenge and the tutorial are throwaway worlds; never let them
	# clobber the persistent dive's saved resume point.
	if _persists_world:
		GameState.last_position = position


# --------------------------------------------------------- move + drill

func _process_move_and_drill(delta: float) -> void:
	var p := Balance.player
	var dir_x := Input.get_axis("move_left", "move_right")
	var up := Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("move_down")

	if dir_x != 0.0:
		facing = 1 if dir_x > 0.0 else -1
		_sprite.flip_h = facing < 0

	var speed := GameState.move_speed()
	if _in_water:
		speed *= 0.6
	var on_floor_now := not TerrainBody.is_free(world, position + Vector2(0, 3), _radius)
	if on_floor_now:
		_coyote = 0.12

	# "Grounded-ish": solid within reach below. Used for ramp/side drilling so
	# it stays engaged while riding a freshly carved slope (unlike a strict
	# floor check, which flickers as the pod rises).
	var grounded_ish := on_floor_now \
		or not TerrainBody.is_free(world, position + Vector2(0, _radius * 0.9), 6.0)

	# ---- carve intent ----
	# Priority: down > up-ramp > sideways. There is deliberately NO way to
	# drill straight up: to ascend you carve a diagonal ramp and walk it, so
	# the route home is something you plan and dig (playtest feedback #2).
	var carve_dir := Vector2.ZERO
	var drill_px_speed := GameState.drill_tiles_per_sec() * MineWorld.TILE
	if down and (on_floor_now or velocity.y >= 0.0):
		carve_dir = Vector2(0, 1)
	elif up and dir_x != 0.0 and grounded_ish \
			and not TerrainBody.is_free(world,
				position + Vector2(dir_x * (_radius + 6.0), -_radius * 0.6), 5.0):
		# Ramp carving: bore a rising diagonal tunnel in the facing direction.
		# A shallower angle (ratio > 1) makes the climb an easier grade to
		# walk without touching ramp_speed_mult -- geometry, not a speed buff.
		carve_dir = Vector2(dir_x * float(p["ramp_angle_ratio"]), -1).normalized()
		drill_px_speed *= float(p["ramp_speed_mult"])
	elif dir_x != 0.0 and grounded_ish \
			and not TerrainBody.is_free(world,
				position + Vector2(dir_x * (_radius + 6.0), 0), 5.0):
		carve_dir = Vector2(dir_x, 0)

	drilling = false
	_drill_was_hard = false
	if carve_dir != Vector2.ZERO:
		var carve_center := position + carve_dir * (_radius + 8.0)
		var carve_radius_used := float(p["carve_radius"])
		if carve_dir.y < 0.0:  # ramp: a bit more generous so the climb feels smoother
			carve_radius_used *= float(p["ramp_carve_radius_mult"])
		var result := world.carve_circle(carve_center,
			carve_radius_used, GameState.bit_level())
		if int(result["removed"]) > 0:
			drilling = true
			_drill_was_hard = bool(result["hard"])
			_handle_pickups(result)
			_fx_accum += delta
			if _fx_accum >= 0.05:      # ~20 bursts/sec, not one per frame
				_fx_accum = 0.0
				Events.fx_burst.emit("drill", carve_center, carve_dir,
					3 if _drill_was_hard else 2)
				Events.fx_shake.emit(0.16 if _drill_was_hard else 0.10)
		elif int(result["blocked_tier"]) > 0:
			_notify_blocked(int(result["blocked_tier"]))

	# ---- velocities ----
	if drilling:
		var advance := drill_px_speed
		if _drill_was_hard:
			advance *= float(p["hard_rock_drill_mult"])
		velocity.x = carve_dir.x * advance
		if carve_dir.y > 0.0:
			velocity.y = advance          # boring downward
		elif carve_dir.y < 0.0:
			velocity.y = carve_dir.y * advance * 0.9   # riding the ramp up
		else:
			velocity.y += float(p["gravity"]) * delta
	else:
		velocity.x = dir_x * speed
		velocity.y += float(p["gravity"]) * delta
		# Jump: UP while grounded (with a little coyote time). No flight.
		if up and _coyote > 0.0 and velocity.y >= -10.0 and carve_dir == Vector2.ZERO:
			velocity.y = -float(p["jump_velocity"])
			_coyote = 0.0
	if _in_water:
		velocity.y = minf(velocity.y, 260.0)
	velocity.y = minf(velocity.y, 1300.0)

	# ---- integrate ----
	var prev_vy := velocity.y
	var step_up := float(p["step_up_px"]) if not drilling else float(p["step_up_px"]) + 8.0
	var res := TerrainBody.move_circle(world, position, _radius, velocity * delta, step_up)
	position = res["pos"]
	if res["hit_y"]:
		if prev_vy > float(p["fall_damage_speed"]) and not _in_water:
			take_hit(1, "a hard landing")
		velocity.y = 0.0
	if res["hit_x"] and not drilling:
		velocity.x = 0.0

	AudioManager.set_drilling(drilling)
	_dust.emitting = drilling
	if drilling:
		_sprite.offset = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	else:
		_sprite.offset = Vector2.ZERO

	# Bank the sprite toward the drill/travel direction. Clamped, not a full
	# spin: the art reads nose-down with treads at the base, so rotating past
	# roughly +/-30 degrees would start to look upside-down.
	var target_rot := 0.0
	if drilling:
		target_rot = clampf(carve_dir.x * 0.55, -0.55, 0.55)
	elif speed > 0.0:
		target_rot = clampf(velocity.x / speed * 0.15, -0.15, 0.15)
	_sprite.rotation = lerp_angle(_sprite.rotation, target_rot, delta * 10.0)


## Escape rocket: blasts a diagonal shaft up-left or up-right, aimed with the
## movement input (or the way the pod is facing). This is the only way to open
## a route straight upward -- drilling deliberately can't -- so it's the answer
## to being stranded at the bottom of a shaft with no ramp carved.
##
## It respects the current Drill Bit: a rocket stops dead at rock the drill
## couldn't cut, so it can never blast through a layer gate and skip the
## upgrade ladder.
func _fire_rocket() -> void:
	if state == State.BUSTED or world == null:
		return
	if not GameState.use_rocket():
		if _rocket_toast_cooldown <= 0.0:
			_rocket_toast_cooldown = 2.0
			AudioManager.play("click", -6.0, 0.6)
			Events.toast.emit("No rockets left - surface to refill the bay.")
		return

	var p := Balance.player
	var dir_x := Input.get_axis("move_left", "move_right")
	var aim := float(facing) if is_zero_approx(dir_x) else signf(dir_x)
	var dir := Vector2(aim, -1.0).normalized()

	var step := float(p["rocket_step_px"])
	var steps := int(float(p["rocket_range_tiles"]) * float(MineWorld.TILE) / step)
	var blast := position
	for i in steps:
		blast += dir * step
		var res := world.carve_circle(blast, float(p["rocket_carve_radius"]),
			GameState.bit_level())
		_handle_pickups(res)
		# Nothing cut and something in the way: the rocket detonates here.
		if int(res["removed"]) == 0 and int(res["blocked_tier"]) > 0:
			break

	AudioManager.play("explosion", -3.0, 1.15)
	SettingsManager.vibrate(90)
	Events.fx_burst.emit("impact", blast, dir, 16)
	Events.fx_shake.emit(0.85)


func _handle_pickups(result: Dictionary) -> void:
	for ore_id: String in result["ores"]:
		if GameState.try_collect_ore(ore_id):
			AudioManager.play("pickup", 0.0, 1.0 + float(Balance.ores[ore_id]["rarity"]) * 0.06)
			SettingsManager.vibrate(35)
			var gives_ether := int(Balance.ores[ore_id]["ether"]) > 0
			Events.fx_burst.emit("ether" if gives_ether else "ore",
				position, Vector2.ZERO, 6 if gives_ether else 4)
		else:
			_notify_cargo_full(ore_id)
	for cell: Vector2i in result["chests"]:
		chest_opened.emit(cell)


## A full bay upgraded itself. Only the toast lives here: try_collect_ore
## returns true for a swap, so _handle_pickups already plays the pickup sound,
## haptic and particles -- duplicating them here would double-buzz the phone.
func _on_ore_swapped(added_id: String, removed_id: String) -> void:
	if _cargo_toast_cooldown > 0.0:
		return
	_cargo_toast_cooldown = 2.5
	Events.toast.emit("Cargo full - traded %s for %s" % [
		String(Balance.ores[removed_id]["name"]),
		String(Balance.ores[added_id]["name"])])


## Cargo is full and this ore wasn't worth more than the cheapest thing
## aboard, so it is mined out and lost. The block breaks either way.
func _notify_cargo_full(ore_id: String) -> void:
	if _cargo_toast_cooldown > 0.0:
		return
	_cargo_toast_cooldown = 2.5
	AudioManager.play("click", -6.0, 0.6)
	Events.toast.emit("Cargo full - %s left behind. Sell or deposit to make room."
		% String(Balance.ores[ore_id]["name"]))


func _notify_blocked(tier: int) -> void:
	if _bit_toast_cooldown > 0.0:
		return
	_bit_toast_cooldown = 2.5
	AudioManager.play("click", -6.0, 0.6)
	if tier >= 99:
		Events.toast.emit("Bedrock. Nothing drills through this.")
	else:
		var layer_name := String(Balance.layers[tier - 1]["name"])
		Events.toast.emit("%s rock is too hard - buy Drill Bit Lv %d at the SHOP!"
			% [layer_name, tier])


# -------------------------------------------------------------------- heat

func _process_heat(delta: float) -> void:
	var h := Balance.heat
	var row := world.world_to_cell(position).y
	var floor_heat := GameState.ambient_floor(row)
	if drilling:
		var rate := float(h["drill_heat_per_sec"])
		if _drill_was_hard:
			rate *= float(h["hard_rock_heat_mult"])
		heat += rate * delta
	else:
		var cool := GameState.cool_rate()
		if _in_water:
			cool *= 2.0
		heat = maxf(heat - cool * delta, floor_heat)
	heat = maxf(heat, floor_heat)

	var max_heat := float(h["max"])
	if heat >= float(h["warning_at"]) and not _warned:
		_warned = true
		AudioManager.play("warning")
		SettingsManager.vibrate(60)
	elif heat < float(h["warning_at"]) - 5.0:
		_warned = false
	Events.heat_changed.emit(heat, floor_heat, max_heat)
	if heat >= max_heat:
		bust("Your drill got too hot and shut down.")


# ------------------------------------------------------------- environment

func _process_environment() -> void:
	var cell := world.world_to_cell(position)
	var type := int(world.cell_info(cell)["type"])
	var was_in_water := _in_water
	# Dynamic per-pixel check, not the static generation-time cell type:
	# water now actually flows, so cooling should trigger wherever it's
	# physically ended up, not just its original spot.
	_in_water = world.is_water_px(position)
	if _in_water and not was_in_water:
		AudioManager.play("splash")
		Events.fx_burst.emit("splash", position, Vector2.UP, 5)
		if not _wet_cells.has(cell):
			_wet_cells[cell] = true
			heat = maxf(heat - float(Balance.heat["water_cool_instant"]), 0.0)
			Events.toast.emit("Water pocket! Drill cooled down.")
	if type == MineWorld.TileType.MAGMA and _invuln <= 0.0:
		heat += float(Balance.heat["magma_heat_instant"])
		take_hit(1, "magma")
		velocity.y = -420.0


func _report_depth() -> void:
	var row := world.world_to_cell(position).y
	if row != _last_row:
		_last_row = row
		GameState.note_depth(row)
		Events.depth_changed.emit(row, Balance.km_for_row(row), Balance.layer_id_for_row(row))


# ------------------------------------------------------------------ damage

func take_hit(damage: int, source: String) -> void:
	if _invuln > 0.0 or state == State.BUSTED:
		return
	if damage >= 99:
		bust("A Government Driller caught you and took the ore.")
		return
	hull -= damage
	_invuln = float(Balance.player["invuln_after_hit_sec"])
	AudioManager.play("hurt")
	SettingsManager.vibrate(80)
	Events.hull_changed.emit(hull, GameState.max_hull())
	_flash()
	Events.fx_burst.emit("impact", position, Vector2.ZERO, 8)
	Events.fx_shake.emit(0.7)
	if hull <= 0:
		bust("Your hull gave out after a run-in with %s." % source)


func _flash() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color(1, 0.4, 0.4), 0.08)
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.3)


func bust(reason: String) -> void:
	if state == State.BUSTED:
		return
	state = State.BUSTED
	drilling = false
	AudioManager.stop_loops()
	AudioManager.play("explosion")
	SettingsManager.vibrate(200)
	_dust.emitting = false
	Events.fx_burst.emit("impact", position, Vector2.ZERO, 24)
	Events.fx_shake.emit(1.6)
	GameState.lose_cargo(reason)
	busted.emit(reason)


func respawn(spawn_pos: Vector2) -> void:
	position = spawn_pos
	velocity = Vector2.ZERO
	heat = 0.0
	hull = GameState.max_hull()
	state = State.DRIVE
	_invuln = 2.0
	_sprite.modulate = Color.WHITE
	Events.hull_changed.emit(hull, GameState.max_hull())


func refresh_hull_after_upgrade() -> void:
	hull = GameState.max_hull()
	Events.hull_changed.emit(hull, GameState.max_hull())
