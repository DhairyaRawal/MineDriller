class_name TerrainBody
## TerrainBody: circle-vs-pixel-terrain movement shared by the player and
## all enemies. The world is a carved pixel field (see MineWorld), so bodies
## are circles that sample solidity at points around their perimeter.
## `step_up` lets a body walk up gentle carved slopes and ramps.

const SAMPLES := 12


## True if a circle at `pos` overlaps no solid terrain.
static func is_free(world: MineWorld, pos: Vector2, radius: float) -> bool:
	if world.is_solid_px(pos):
		return false
	for i in SAMPLES:
		var a := TAU * i / SAMPLES
		if world.is_solid_px(pos + Vector2(cos(a), sin(a)) * radius):
			return false
	# Mid-ring catches thin spikes bigger than the gap between edge samples.
	for i in 4:
		var a2 := TAU * i / 4.0 + 0.4
		if world.is_solid_px(pos + Vector2(cos(a2), sin(a2)) * radius * 0.55):
			return false
	return true


## Move a circle by `motion`, resolving against terrain.
## Returns {pos, hit_x, hit_y, on_floor}.
static func move_circle(world: MineWorld, pos: Vector2, radius: float,
		motion: Vector2, step_up := 0.0) -> Dictionary:
	var p := pos
	var hit_x := false
	var hit_y := false

	# Horizontal, in sub-steps no larger than half the radius.
	var remaining_x := motion.x
	while absf(remaining_x) > 0.001 and not hit_x:
		var dx := clampf(remaining_x, -radius * 0.5, radius * 0.5)
		remaining_x -= dx
		var candidate := p + Vector2(dx, 0)
		if is_free(world, candidate, radius):
			p = candidate
		else:
			# Try stepping up a slope.
			var stepped := false
			if step_up > 0.0:
				var h := 4.0
				while h <= step_up:
					var lifted := candidate + Vector2(0, -h)
					if is_free(world, lifted, radius):
						p = lifted
						stepped = true
						break
					h += 4.0
			if not stepped:
				# Close the remaining gap so the body sits flush to the wall.
				p.x += _approach(world, p, radius, Vector2(dx, 0))
				hit_x = true

	# Vertical.
	var remaining_y := motion.y
	while absf(remaining_y) > 0.001 and not hit_y:
		var dy := clampf(remaining_y, -radius * 0.5, radius * 0.5)
		remaining_y -= dy
		var candidate_y := p + Vector2(0, dy)
		if is_free(world, candidate_y, radius):
			p = candidate_y
		else:
			# Close the remaining gap so the body sits flush on the floor.
			p.y += _approach(world, p, radius, Vector2(0, dy))
			hit_y = true

	var on_floor := not is_free(world, p + Vector2(0, 3.0), radius)
	return {"pos": p, "hit_x": hit_x, "hit_y": hit_y, "on_floor": on_floor}


## Binary-search the largest fraction of `blocked_motion` (a single-axis
## vector) the body can still take from `p`, so it ends flush against the
## obstacle instead of up to one sub-step short. Returns the signed distance
## to add on that axis.
static func _approach(world: MineWorld, p: Vector2, radius: float,
		blocked_motion: Vector2) -> float:
	var best := 0.0
	var step := blocked_motion
	for _i in 5:
		step *= 0.5
		var candidate := p + Vector2(best, 0) + step if blocked_motion.x != 0.0 \
			else p + Vector2(0, best) + step
		if is_free(world, candidate, radius):
			best += (step.x if blocked_motion.x != 0.0 else step.y)
	return best
