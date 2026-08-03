class_name FXLayer
extends Node2D
## FXLayer: world-space particle bursts driven entirely by `Events.fx_burst`.
##
## This is a Node2D (NOT a CanvasLayer) on purpose: bursts are emitted at world
## coordinates, so the layer has to share the world's transform or every spark
## would draw at the wrong place once the camera moves.
##
## Particles are plain structs in a fixed-capacity pool drawn in one _draw()
## pass, so a heavy drilling burst costs no allocations and one draw call.

const MAX_PARTICLES := 220
const GRAVITY := 900.0

class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var life_max := 1.0
	var size := 1.0
	var spin := 0.0
	var angle := 0.0
	var color := Color.WHITE
	var tex: Texture2D
	var alive := false

var _pool: Array[Particle] = []
var _next := 0
var _tex := {}


func _ready() -> void:
	z_index = 60
	for name in ["particle", "sparkle_ore", "sparkle_ether", "impact"]:
		var path := "res://assets/textures/%s.png" % name
		if ResourceLoader.exists(path):
			_tex[name] = load(path)
	for i in MAX_PARTICLES:
		_pool.append(Particle.new())
	Events.fx_burst.connect(_on_burst)


func _process(delta: float) -> void:
	var any := false
	for p in _pool:
		if not p.alive:
			continue
		p.life -= delta
		if p.life <= 0.0:
			p.alive = false
			continue
		p.vel.y += GRAVITY * delta
		p.vel *= 1.0 - minf(delta * 1.4, 0.9)   # air drag, keeps bursts tight
		p.pos += p.vel * delta
		p.angle += p.spin * delta
		any = true
	if any or _dirty:
		_dirty = any
		queue_redraw()

var _dirty := false


func _draw() -> void:
	for p in _pool:
		if not p.alive or p.tex == null:
			continue
		var fade := clampf(p.life / p.life_max, 0.0, 1.0)
		var col := Color(p.color.r, p.color.g, p.color.b, p.color.a * fade)
		var half := p.tex.get_size() * 0.5 * p.size
		draw_set_transform(p.pos, p.angle, Vector2(p.size, p.size))
		draw_texture(p.tex, -p.tex.get_size() * 0.5, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ emission

func _on_burst(kind: String, world_pos: Vector2, dir: Vector2, count: int) -> void:
	match kind:
		"drill":
			_spawn(count, world_pos, dir, 0.85, 70.0, 170.0,
				Color(0.85, 0.74, 0.60), "particle", 0.5, 0.95, 0.30, 0.55)
		"ore":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 90.0, 200.0,
				Color(1.0, 0.86, 0.42), "sparkle_ore", 0.7, 1.15, 0.45, 0.8)
		"ether":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 80.0, 180.0,
				Color(0.55, 0.95, 1.0), "sparkle_ether", 0.8, 1.3, 0.6, 1.0)
		"impact":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 120.0, 260.0,
				Color(1.0, 0.97, 0.85), "impact", 0.6, 1.0, 0.22, 0.42)
		"hit_crawly":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 90.0, 190.0,
				Color(0.78, 0.42, 1.0), "particle", 0.5, 0.9, 0.3, 0.55)
		"hit_zombie":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 90.0, 190.0,
				Color(0.52, 0.95, 0.48), "particle", 0.5, 0.9, 0.3, 0.55)
		"hit_govt":
			_spawn(count, world_pos, Vector2.ZERO, TAU, 110.0, 230.0,
				Color(1.0, 0.35, 0.32), "particle", 0.55, 1.0, 0.3, 0.6)
		"splash":
			_spawn(count, world_pos, dir, 1.1, 60.0, 140.0,
				Color(0.45, 0.68, 0.95), "particle", 0.4, 0.8, 0.25, 0.5)


func _spawn(count: int, origin: Vector2, dir: Vector2, spread: float,
		vmin: float, vmax: float, tint: Color, tex_name: String,
		smin: float, smax: float, lmin: float, lmax: float) -> void:
	if not _tex.has(tex_name):
		return
	var base := dir.angle() if dir != Vector2.ZERO else 0.0
	for i in count:
		var p := _pool[_next]
		_next = (_next + 1) % MAX_PARTICLES
		var a := base + randf_range(-spread, spread) if dir != Vector2.ZERO \
			else randf() * TAU
		p.pos = origin + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 6.0)
		p.vel = Vector2.from_angle(a) * randf_range(vmin, vmax)
		p.life_max = randf_range(lmin, lmax)
		p.life = p.life_max
		p.size = randf_range(smin, smax)
		p.spin = randf_range(-7.0, 7.0)
		p.angle = randf() * TAU
		p.color = tint
		p.tex = _tex[tex_name]
		p.alive = true
	_dirty = true
	queue_redraw()
