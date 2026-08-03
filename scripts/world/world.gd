class_name MineWorld
extends Node2D
## MineWorld: seeded procedural terrain rendered as CARVED PIXELS, not grid
## blocks. Cell content (layers, ores, hard rock, caves, gates) is still a
## pure function of (x, y, seed) — but destruction is per-pixel: the drill
## carves smooth round tunnels through the material, and cave pockets get
## organically rounded edges at generation time.
##
## Each 32x16-tile chunk owns a half-resolution Image (1 image px = 2 world
## px) built from the tile atlas; carving erases pixels. Images persist for
## the whole session (carved tunnels never reset), sprites exist only for
## streamed-in chunks.

signal chunk_spawns_ready(spawns: Array)  # [{type, cell: Vector2i}]

enum TileType { EMPTY, SOFT, HARD, ORE, MAGMA, WATER, BEDROCK, GRASS, CHEST }

const TILE := 64
const SCALE := 2                      # world px per image px
const CELL_IMG := TILE / SCALE        # 32 image px per tile
const ORE_COLLECT_FRAC := 0.40        # carve this much of an ore cell to collect it
const CHEST_COLLECT_FRAC := 0.25
const DUG_THRESHOLD_FRAC := 0.50      # carve this much of a plain rock cell to mark it "dug" for save persistence
const WATER_COLOR := Color(0.25, 0.48, 0.85, 0.85)
const WATER_SIM_INTERVAL := 0.05      # simulate at 20Hz, not every render frame
const WATER_SIM_REACH_CELLS := 7      # ~ one screen's worth of tiles each direction
const WATER_SIM_BUDGET := 260         # water pixels actually moved per simulation tick

var seed_value := 0
var width := 32
var max_depth_row := 360
var chunk_h := 16

var _noise: FastNoiseLite
var _atlas: Image                     # half-res tile atlas (RGBA8)
var _images := {}                     # chunk -> Image (persists all session)
var _sprites := {}                    # chunk -> Sprite2D (loaded chunks only)
var _dirty := {}                      # chunk -> true (texture needs re-upload)
var _loaded_chunks := {}
var _spawned_chunks := {}
var _chunk_specials := {}
var _depot_defs: Array = []           # cached depot_positions(), built once per world
var _mined := {}                      # Vector2i -> true (collected ore/chest cells)
var _opened_chests := {}
var _erosion := {}                    # Vector2i -> carved px count (ore/chest/soft/hard cells)
var _carved_cells := {}               # Vector2i -> true (plain rock dug past DUG_THRESHOLD_FRAC)
var _visited_chunks := {}             # int -> true (ever streamed in, for save + map fog-of-war)
var _info_cache := {}                 # Vector2i -> cell info Dictionary
var _terrain_shader: Shader           # rim shading + depth grading (see terrain.gdshader)

# ---- water simulation (see "water simulation" section near the bottom) ----
var _water_images := {}               # chunk -> Image, same half-res grid as _images
var _water_sprites := {}              # chunk -> Sprite2D (loaded chunks only)
var _water_dirty := {}                # chunk -> true (water texture needs re-upload)
var _water_seeded_chunks := {}        # chunk -> true (initial water placed once)
var _water_cells := {}                # Vector2i cell -> true (coarse index: has water pixels)
var _water_sim_accum := 0.0


func setup(world_seed: int) -> void:
	seed_value = world_seed
	width = int(Balance.world["width_tiles"])
	max_depth_row = int(Balance.world["max_depth_row"])
	chunk_h = int(Balance.world["chunk_h"])
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.08
	var atlas_tex: Texture2D = load("res://assets/textures/tiles_32.png")
	_atlas = atlas_tex.get_image()
	_atlas.convert(Image.FORMAT_RGBA8)
	_terrain_shader = load("res://assets/shaders/terrain.gdshader")
	_build_backdrop()
	for d in [_images, _sprites, _dirty, _loaded_chunks, _spawned_chunks,
			_chunk_specials, _mined, _opened_chests, _erosion, _info_cache,
			_carved_cells, _visited_chunks, _depot_defs,
			_water_images, _water_sprites, _water_dirty, _water_seeded_chunks, _water_cells]:
		d.clear()
	_water_sim_accum = 0.0


func _process(_delta: float) -> void:
	# Re-upload carved chunk textures (only when something changed).
	for chunk: int in _dirty.keys():
		if _sprites.has(chunk):
			var tex: ImageTexture = _sprites[chunk].texture
			tex.update(_images[chunk])
	_dirty.clear()
	for chunk: int in _water_dirty.keys():
		if _water_sprites.has(chunk):
			var tex: ImageTexture = _water_sprites[chunk].texture
			tex.update(_water_images[chunk])
	_water_dirty.clear()


## Shade behind the terrain so carved tunnels read as "inside the earth".
##
## Deliberately TRANSLUCENT: the parallax strata drawn by backdrop.gdshader sit
## further back, and letting them show through a carved tunnel is what makes
## the hole look like it has depth behind it rather than being a flat black
## cut-out. Fully opaque here would hide the parallax entirely.
func _build_backdrop() -> void:
	var old := get_node_or_null("Backdrop")
	if old != null:
		old.queue_free()
	var backdrop := Polygon2D.new()
	backdrop.name = "Backdrop"
	var w := width * TILE
	var h := max_depth_row * TILE
	backdrop.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	backdrop.color = Color(0.05, 0.032, 0.028, 0.55)
	backdrop.z_index = -1
	add_child(backdrop)


# --------------------------------------------------------------- streaming

func stream_around(center_row: int) -> void:
	var center_chunk := floori(center_row / float(chunk_h))
	var keep_min := center_chunk - 2
	var keep_max := center_chunk + 3
	for chunk: int in _loaded_chunks.keys():
		if chunk < keep_min or chunk > keep_max:
			_unload_chunk(chunk)
	for chunk in range(maxi(keep_min, 0), keep_max + 1):
		if not _loaded_chunks.has(chunk) and chunk * chunk_h < max_depth_row:
			_load_chunk(chunk)


func _load_chunk(chunk: int) -> void:
	_loaded_chunks[chunk] = true
	_visited_chunks[chunk] = true
	var img := _ensure_image(chunk)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(0, chunk * chunk_h * TILE)
	sprite.scale = Vector2(SCALE, SCALE)
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _terrain_shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = _terrain_shader
		# Depth is graded per chunk (one uniform write per load, not per frame).
		var mid_row := float(chunk * chunk_h + chunk_h * 0.5)
		mat.set_shader_parameter("depth_frac",
			clampf(mid_row / float(max_depth_row), 0.0, 1.0))
		mat.set_shader_parameter("cell_uv",
			Vector2(1.0 / float(width), 1.0 / float(chunk_h)))
		mat.set_shader_parameter("chunk_id", float(chunk))
		sprite.material = mat
	add_child(sprite)
	_sprites[chunk] = sprite

	_ensure_water_seeded(chunk)
	var wimg := _ensure_water_image(chunk)
	var wsprite := Sprite2D.new()
	wsprite.centered = false
	wsprite.position = Vector2(0, chunk * chunk_h * TILE)
	wsprite.scale = Vector2(SCALE, SCALE)
	wsprite.texture = ImageTexture.create_from_image(wimg)
	wsprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(wsprite)
	_water_sprites[chunk] = wsprite

	_roll_spawns(chunk)


func _unload_chunk(chunk: int) -> void:
	_loaded_chunks.erase(chunk)
	if _sprites.has(chunk):
		_sprites[chunk].queue_free()
		_sprites.erase(chunk)
	if _water_sprites.has(chunk):
		_water_sprites[chunk].queue_free()
		_water_sprites.erase(chunk)


func _roll_spawns(chunk: int) -> void:
	if _spawned_chunks.has(chunk):
		return
	_spawned_chunks[chunk] = true
	var row_start := chunk * chunk_h
	var spawns: Array = []
	var spawn_budget := 5
	for y in range(row_start, row_start + chunk_h):
		if spawn_budget <= 0:
			break
		for x in width:
			if spawn_budget <= 0:
				break
			var cell := Vector2i(x, y)
			if int(cell_info(cell)["type"]) != TileType.EMPTY or y <= 4:
				continue
			var layer_id: int = Balance.layer_id_for_row(y)
			var table: Dictionary = Balance.enemy_spawn.get(str(layer_id), {})
			for enemy_type: String in table:
				if _cell_rand(x, y, 900 + enemy_type.hash() % 97) < float(table[enemy_type]):
					spawns.append({"type": enemy_type, "cell": cell})
					spawn_budget -= 1
					break
	if not spawns.is_empty():
		chunk_spawns_ready.emit(spawns)


# ------------------------------------------------------- chunk image build

func _ensure_image(chunk: int) -> Image:
	if _images.has(chunk):
		return _images[chunk]
	var img := Image.create(width * CELL_IMG, chunk_h * CELL_IMG, false, Image.FORMAT_RGBA8)
	var row_start := chunk * chunk_h
	for y in chunk_h:
		for x in width:
			var cell := Vector2i(x, row_start + y)
			var info := cell_info(cell)
			var atlas_coords := _atlas_for(info)
			if atlas_coords.x < 0:
				continue
			var dst := Vector2i(x * CELL_IMG, y * CELL_IMG)
			# Ore tiles are transparent gem overlays: lay the layer's own rock
			# down first and blend the gems on top, so ore never paints a
			# hard-edged square of its own background colour.
			if int(info["type"]) == TileType.ORE:
				var rock := Vector2i(clampi(int(info["layer_id"]), 1, 5) - 1, 0)
				img.blit_rect(_atlas,
					Rect2i(rock.x * CELL_IMG, rock.y * CELL_IMG, CELL_IMG, CELL_IMG), dst)
				img.blend_rect(_atlas,
					Rect2i(atlas_coords.x * CELL_IMG, atlas_coords.y * CELL_IMG,
						CELL_IMG, CELL_IMG), dst)
			else:
				img.blit_rect(_atlas,
					Rect2i(atlas_coords.x * CELL_IMG, atlas_coords.y * CELL_IMG,
						CELL_IMG, CELL_IMG), dst)
	_images[chunk] = img
	_round_cave_edges(chunk, img)
	return img


## Organic caves: erase soft-rock pixels in rounded blobs around every cave
## cell that borders solid ground. Hard rock, ores and bedrock are left
## intact, so gates and loot are never eaten by the rounding.
func _round_cave_edges(chunk: int, img: Image) -> void:
	var row_start := chunk * chunk_h
	for y in chunk_h:
		for x in width:
			var cell := Vector2i(x, row_start + y)
			if int(cell_info(cell)["type"]) != TileType.EMPTY or cell.y <= 1:
				continue
			var has_solid_neighbor := false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := cell_info(cell + offset)
				if int(n["type"]) == TileType.SOFT:
					has_solid_neighbor = true
					break
			if not has_solid_neighbor:
				continue
			var radius := (0.55 + 0.25 * _cell_rand(cell.x, cell.y, 41)) * CELL_IMG
			_erase_soft_circle(img, row_start,
				Vector2((cell.x + 0.5) * CELL_IMG, (cell.y - row_start + 0.5) * CELL_IMG), radius)


func _erase_soft_circle(img: Image, row_start: int, center: Vector2, radius: float) -> void:
	var r := int(ceilf(radius))
	var cx := int(center.x)
	var cy := int(center.y)
	var r2 := radius * radius
	for py in range(maxi(cy - r, 0), mini(cy + r, img.get_height() - 1) + 1):
		for px in range(maxi(cx - r, 0), mini(cx + r, img.get_width() - 1) + 1):
			var dx := px - center.x
			var dy := py - center.y
			if dx * dx + dy * dy > r2:
				continue
			if img.get_pixel(px, py).a <= 0.05:
				continue
			var cell := Vector2i(px * SCALE / TILE, row_start + py * SCALE / TILE)
			var type := int(cell_info(cell)["type"])
			if type == TileType.SOFT or type == TileType.GRASS:
				img.set_pixel(px, py, Color(0, 0, 0, 0))


func _atlas_for(info: Dictionary) -> Vector2i:
	match int(info["type"]):
		TileType.SOFT:
			return Vector2i(int(info["layer_id"]) - 1, 0)
		TileType.HARD:
			return Vector2i(clampi(int(info["layer_id"]), 1, 5) - 1, 1)
		TileType.ORE:
			return Vector2i(int(Balance.ores[info["ore_id"]]["atlas_col"]), 2)
		TileType.MAGMA:
			return Vector2i(5, 1)
		TileType.WATER:
			return Vector2i(6, 1)
		TileType.BEDROCK:
			return Vector2i(5, 0)
		TileType.GRASS:
			return Vector2i(6, 0)
		TileType.CHEST:
			return Vector2i(7, 0)
	return Vector2i(-1, -1)


# ----------------------------------------------------------------- carving

## Carve a circle of terrain at world position `center`. Pixels of cells the
## current bit can't cut (and bedrock) are left standing. `can_collect_ore`
## lets the caller withhold ore cells specifically (e.g. cargo is full) while
## still carving every other pixel in the circle normally -- an ore left
## standing this way is untouched and can be finished later. Returns:
## {removed: int, hard: bool, blocked_tier: int, cargo_full_blocked: bool,
##  ores: Array[String], chests: Array[Vector2i]}
func carve_circle(center: Vector2, radius: float, bit: int, can_collect_ore: bool = true) -> Dictionary:
	var removed := 0
	var hard := false
	var blocked_tier := 0
	var cargo_full_blocked := false
	var ores: Array = []
	var chests: Array = []
	var r2 := radius * radius
	var min_px := Vector2i(int(center.x - radius) >> 1, int(center.y - radius) >> 1)
	var max_px := Vector2i(int(center.x + radius) >> 1, int(center.y + radius) >> 1)
	var px_min := maxi(min_px.x, 0)
	var px_max := mini(max_px.x, width * CELL_IMG - 1)
	var cell_cache := {}
	for py in range(min_px.y, max_px.y + 1):
		var wy := py * SCALE + 1
		if wy < 0:
			continue
		for px in range(px_min, px_max + 1):
			var wx := px * SCALE + 1
			var dx := wx - center.x
			var dy := wy - center.y
			if dx * dx + dy * dy > r2:
				continue
			var cell := Vector2i(floori(wx / float(TILE)), floori(wy / float(TILE)))
			var info: Dictionary
			if cell_cache.has(cell):
				info = cell_cache[cell]
			else:
				info = cell_info(cell)
				cell_cache[cell] = info
			var type := int(info["type"])
			if type == TileType.EMPTY or type == TileType.WATER or type == TileType.MAGMA:
				continue
			if type == TileType.BEDROCK:
				blocked_tier = 99 if blocked_tier < 99 else blocked_tier
				continue
			if type == TileType.HARD and int(info["tier"]) > bit:
				blocked_tier = maxi(blocked_tier, int(info["tier"]))
				continue
			if type == TileType.ORE and not can_collect_ore:
				cargo_full_blocked = true
				continue
			var chunk := floori(cell.y / float(chunk_h))
			var img := _ensure_image(chunk)
			var ipy := py - chunk * chunk_h * CELL_IMG
			if ipy < 0 or ipy >= img.get_height():
				continue
			if img.get_pixel(px, ipy).a <= 0.05:
				continue
			img.set_pixel(px, ipy, Color(0, 0, 0, 0))
			removed += 1
			_dirty[chunk] = true
			if type == TileType.HARD:
				hard = true
			if type == TileType.ORE or type == TileType.CHEST:
				_erosion[cell] = int(_erosion.get(cell, 0)) + 1
				var cell_area := CELL_IMG * CELL_IMG
				var frac := ORE_COLLECT_FRAC if type == TileType.ORE else CHEST_COLLECT_FRAC
				if _erosion[cell] >= int(cell_area * frac):
					if type == TileType.ORE:
						ores.append(String(info["ore_id"]))
					else:
						chests.append(cell)
						_opened_chests[cell] = true
					_mined[cell] = true
					_info_cache.erase(cell)
					_clear_cell_pixels(cell)
			elif not _carved_cells.has(cell):
				# Plain rock (soft or hard): mark the cell "dug" once enough
				# of it is carved away, so a save/reload can coarsely restore
				# this tunnel (cell granularity, not pixel-perfect -- see
				# MineWorld.export_diff).
				_erosion[cell] = int(_erosion.get(cell, 0)) + 1
				if _erosion[cell] >= int(CELL_IMG * CELL_IMG * DUG_THRESHOLD_FRAC):
					_carved_cells[cell] = true
	return {"removed": removed, "hard": hard, "blocked_tier": blocked_tier,
		"cargo_full_blocked": cargo_full_blocked, "ores": ores, "chests": chests}


func _clear_cell_pixels(cell: Vector2i) -> void:
	var chunk := floori(cell.y / float(chunk_h))
	var img := _ensure_image(chunk)
	var x0 := cell.x * CELL_IMG
	var y0 := (cell.y - chunk * chunk_h) * CELL_IMG
	for py in range(y0, y0 + CELL_IMG):
		for px in range(x0, x0 + CELL_IMG):
			img.set_pixel(px, py, Color(0, 0, 0, 0))
	_dirty[chunk] = true


# ------------------------------------------------------------ cell content

func _cell_rand(x: int, y: int, salt: int) -> float:
	var h := hash(Vector3i(x, y, salt)) ^ hash(seed_value)
	return float(absi(h) % 1000003) / 1000003.0


func _chunk_special(chunk: int) -> Dictionary:
	if _chunk_specials.has(chunk):
		return _chunk_specials[chunk]
	var special := {}
	var row_start := chunk * chunk_h
	if row_start > 8 and row_start < max_depth_row - chunk_h:
		if _cell_rand(0, chunk, 777) < float(Balance.world["treasure_room_chance_per_chunk"]):
			var rx := 2 + int(_cell_rand(1, chunk, 778) * (width - 10))
			var ry := row_start + 3 + int(_cell_rand(2, chunk, 779) * (chunk_h - 8))
			var room := Rect2i(rx, ry, 6, 4)
			special = {"room": room, "chest": Vector2i(rx + 3, ry + 3)}
	_chunk_specials[chunk] = special
	return special


## 3 fixed, deterministic safe-spot depots per layer (15 total), evenly
## spread through each layer's depth range -- same seed-determinism guarantee
## as everything else here, but a fixed count per layer rather than a
## per-chunk chance roll (unlike treasure vaults), since the design calls for
## a reliable number of banks, not a random find. Cached after first call.
func depot_positions() -> Array:
	if not _depot_defs.is_empty():
		return _depot_defs
	for layer: Dictionary in Balance.layers:
		var layer_id := int(layer["id"])
		var row_start := int(layer["row_start"])
		var row_end := int(layer["row_end"])
		var span := row_end - row_start
		for i in 3:
			var frac := 0.2 + 0.3 * float(i)  # 20%, 50%, 80% down the layer
			var row := clampi(row_start + int(span * frac), row_start + 2, row_end - 6)
			var rx := 2 + int(_cell_rand(layer_id, i, 501) * (width - 10))
			var rect := Rect2i(rx, row, 6, 4)
			_depot_defs.append({
				"id": "L%d_%d" % [layer_id, i + 1],
				"layer_id": layer_id,
				"rect": rect,
				"center": Vector2((rx + 3) * TILE, (row + 2) * TILE),
			})
	return _depot_defs


## Cell content: pure function of position (plus mined/opened diffs).
## Cached per cell — this is on the hot path of pixel collision sampling.
func cell_info(cell: Vector2i) -> Dictionary:
	var cached: Variant = _info_cache.get(cell)
	if cached != null:
		return cached
	var info := _compute_cell_info(cell)
	_info_cache[cell] = info
	return info


func _compute_cell_info(cell: Vector2i) -> Dictionary:
	var x := cell.x
	var y := cell.y
	# Horizontal bounds first: side walls extend above the surface too.
	if x < 0 or x >= width or y >= max_depth_row:
		return {"type": TileType.BEDROCK, "layer_id": 0, "tier": 99, "ore_id": ""}
	if y < 0:
		return {"type": TileType.EMPTY, "layer_id": 0, "tier": 0, "ore_id": ""}
	if _mined.has(cell) or _carved_cells.has(cell):
		return {"type": TileType.EMPTY, "layer_id": 0, "tier": 0, "ore_id": ""}
	if y == 0:
		return {"type": TileType.GRASS, "layer_id": 1, "tier": 1, "ore_id": ""}

	var layer: Dictionary = Balance.layer_for_row(y)
	var layer_id := int(layer["id"])
	var row_end := int(layer["row_end"])

	var special := _chunk_special(floori(y / float(chunk_h)))
	if not special.is_empty():
		var room: Rect2i = special["room"]
		if room.has_point(cell):
			if cell == special["chest"] and not _opened_chests.has(cell):
				return {"type": TileType.CHEST, "layer_id": layer_id, "tier": 1, "ore_id": ""}
			return {"type": TileType.EMPTY, "layer_id": layer_id, "tier": 0, "ore_id": ""}

	# Depot safe-spot rooms: pre-hollowed like treasure vaults, but walk-in --
	# there's no chest to drill open, interaction is proximity-based (game.gd).
	for depot: Dictionary in depot_positions():
		if int(depot["layer_id"]) == layer_id and (depot["rect"] as Rect2i).has_point(cell):
			return {"type": TileType.EMPTY, "layer_id": layer_id, "tier": 0, "ore_id": ""}

	# Layer transition band: solid wall of next-tier hard rock (the gate).
	var in_transition := y >= row_end - 2 and y < row_end and layer_id < 5
	if in_transition:
		return {"type": TileType.HARD, "layer_id": layer_id + 1,
				"tier": layer_id + 1, "ore_id": ""}

	var n := (_noise.get_noise_2d(x, y) + 1.0) * 0.5
	var depth_frac := float(y) / float(max_depth_row)
	var threshold := float(Balance.world["cave_threshold"]) \
		- float(Balance.world["cave_depth_bonus"]) * depth_frac
	if y > 2 and n > threshold:
		if layer_id <= 2 and _cell_rand(x, y, 11) < float(Balance.world["water_chance"]):
			return {"type": TileType.WATER, "layer_id": layer_id, "tier": 0, "ore_id": ""}
		if layer_id >= 3 and _cell_rand(x, y, 12) < float(Balance.world["magma_chance"]):
			return {"type": TileType.MAGMA, "layer_id": layer_id, "tier": 0, "ore_id": ""}
		return {"type": TileType.EMPTY, "layer_id": layer_id, "tier": 0, "ore_id": ""}

	if _cell_rand(x, y, 21) < float(layer["ore_chance"]):
		var row_start := int(layer["row_start"])
		var local_frac := clampf(
			float(y - row_start) / maxf(1.0, float(row_end - row_start)), 0.0, 1.0)
		var ore_id := Balance.pick_ore(layer, local_frac, _cell_rand(x, y, 22))
		return {"type": TileType.ORE, "layer_id": layer_id, "tier": layer_id, "ore_id": ore_id}

	if _cell_rand(x, y, 31) < float(layer["hard_chance"]):
		return {"type": TileType.HARD, "layer_id": layer_id, "tier": layer_id, "ore_id": ""}

	return {"type": TileType.SOFT, "layer_id": layer_id, "tier": layer_id, "ore_id": ""}


# ----------------------------------------------------------------- queries

func is_solid_type(type: int) -> bool:
	return type == TileType.SOFT or type == TileType.HARD or type == TileType.ORE \
		or type == TileType.BEDROCK or type == TileType.GRASS or type == TileType.CHEST


## Pixel-accurate solidity at a world position: content decides the material,
## the carve mask decides whether it's still there.
func is_solid_px(pos: Vector2) -> bool:
	var cell := Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))
	var info := cell_info(cell)
	var type := int(info["type"])
	if type == TileType.EMPTY or type == TileType.WATER or type == TileType.MAGMA:
		return false
	if type == TileType.BEDROCK:
		return true
	var chunk := floori(cell.y / float(chunk_h))
	var img: Image = _images.get(chunk)
	if img == null:
		return true
	var px := clampi(int(pos.x) >> 1, 0, img.get_width() - 1)
	var py := clampi((int(pos.y) - chunk * chunk_h * TILE) >> 1, 0, img.get_height() - 1)
	return img.get_pixel(px, py).a > 0.05


## Coarse cell-level solidity (enemy ledge checks, legacy tests).
func is_solid_at(cell: Vector2i) -> bool:
	return is_solid_px(cell_to_world(cell))


func can_drill(cell: Vector2i, bit: int) -> bool:
	var info := cell_info(cell)
	var type := int(info["type"])
	if type == TileType.BEDROCK:
		return false
	if type == TileType.HARD:
		return bit >= int(info["tier"])
	return is_solid_type(type)


## Legacy whole-cell removal (tests, scripted events).
func dig(cell: Vector2i) -> Dictionary:
	var info := cell_info(cell)
	if int(info["type"]) == TileType.CHEST:
		_opened_chests[cell] = true
	_mined[cell] = true
	_info_cache.erase(cell)
	if cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < max_depth_row:
		_clear_cell_pixels(cell)
	return info


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


# --------------------------------------------------------------- persistence

## Whether any part of this chunk has ever been streamed in this world.
## Backs both save persistence and the map screen's fog-of-war.
func is_chunk_visited(chunk: int) -> bool:
	return _visited_chunks.has(chunk)


## Export a coarse diff of dug/collected/visited state for save persistence.
## Deliberately NOT exact pixel data: reconstructing from this diff on load
## regenerates tunnels as fully-cleared cells (rounded carve edges reset to
## plain empty rectangles), which is mechanically and visually equivalent to
## the original dig but not pixel-identical. See docs/ARCHITECTURE.md.
func export_diff() -> Dictionary:
	var mined: Array = []
	for cell: Vector2i in _mined:
		mined.append([cell.x, cell.y])
	var carved: Array = []
	for cell: Vector2i in _carved_cells:
		carved.append([cell.x, cell.y])
	var opened: Array = []
	for cell: Vector2i in _opened_chests:
		opened.append([cell.x, cell.y])
	return {
		"mined": mined,
		"carved": carved,
		"opened_chests": opened,
		"visited_chunks": _visited_chunks.keys(),
	}


## Repopulate the diff dictionaries above from a saved export_diff() payload.
## Call after setup() and before the first stream_around(), so cell_info
## reflects the diff from the very first chunk build.
func import_diff(diff: Dictionary) -> void:
	for pair in diff.get("mined", []):
		_mined[Vector2i(int(pair[0]), int(pair[1]))] = true
	for pair in diff.get("carved", []):
		_carved_cells[Vector2i(int(pair[0]), int(pair[1]))] = true
	for pair in diff.get("opened_chests", []):
		_opened_chests[Vector2i(int(pair[0]), int(pair[1]))] = true
	for chunk in diff.get("visited_chunks", []):
		_visited_chunks[int(chunk)] = true
	_info_cache.clear()


# ----------------------------------------------------------- water simulation

## Water is a second per-pixel layer at the same half-resolution grid as the
## terrain carve mask (a separate Image/Sprite2D pair, not packed into the
## terrain image itself -- terrain.gdshader zeroes color wherever alpha is
## near zero, so any data hidden in a carved pixel's RGB would never reach a
## fragment shader that could render it). Water starts wherever generation
## placed a WATER cell, then actually falls/spreads once drilling opens a
## path, instead of sitting fixed forever.
##
## Per-pixel movement, but indexed at cell granularity (_water_cells) so a
## simulation tick only scans cells known to hold water rather than an entire
## screen-sized pixel window every frame -- the "active radius" is which
## cells get scanned, not a reduction in simulation fidelity.
## Water state is intentionally session-only: it is not part of export_diff()
## and re-seeds from the static generation cells on every load, same spirit
## as the rest of the "coarse diff" persistence choice for terrain.

func _ensure_water_image(chunk: int) -> Image:
	if _water_images.has(chunk):
		return _water_images[chunk]
	var img := Image.create(width * CELL_IMG, chunk_h * CELL_IMG, false, Image.FORMAT_RGBA8)
	_water_images[chunk] = img
	return img


func _ensure_water_seeded(chunk: int) -> void:
	if _water_seeded_chunks.has(chunk):
		return
	_water_seeded_chunks[chunk] = true
	var row_start := chunk * chunk_h
	for y in chunk_h:
		for x in width:
			var cell := Vector2i(x, row_start + y)
			if int(cell_info(cell)["type"]) == TileType.WATER:
				_fill_water_cell(cell)


func _fill_water_cell(cell: Vector2i) -> void:
	var chunk := floori(cell.y / float(chunk_h))
	var img := _ensure_water_image(chunk)
	var x0 := cell.x * CELL_IMG
	var y0 := (cell.y - chunk * chunk_h) * CELL_IMG
	for py in range(y0, y0 + CELL_IMG):
		for px in range(x0, x0 + CELL_IMG):
			img.set_pixel(px, py, WATER_COLOR)
	_water_dirty[chunk] = true
	_water_cells[cell] = true


## gpx/gpy are GLOBAL image-px coordinates (gpx spans the whole world width
## already, like the terrain carve loop; gpy spans the whole world depth and
## is resolved to a chunk + local row here).
func _has_water_px(gpx: int, gpy: int) -> bool:
	if gpx < 0 or gpx >= width * CELL_IMG or gpy < 0 or gpy >= max_depth_row * CELL_IMG:
		return false
	var chunk := floori(gpy / float(chunk_h * CELL_IMG))
	var img: Image = _water_images.get(chunk)
	if img == null:
		return false  # chunk not loaded: treat as frozen/no water, not an error
	var local_py := gpy - chunk * chunk_h * CELL_IMG
	return img.get_pixel(gpx, local_py).a > 0.05


func _set_water_px(gpx: int, gpy: int, present: bool) -> void:
	var chunk := floori(gpy / float(chunk_h * CELL_IMG))
	var img: Image = _water_images.get(chunk)
	if img == null:
		return
	var local_py := gpy - chunk * chunk_h * CELL_IMG
	img.set_pixel(gpx, local_py, WATER_COLOR if present else Color(0, 0, 0, 0))
	_water_dirty[chunk] = true


## A pixel water can move into: not solid rock, and not already water there.
func _open_for_water(gpx: int, gpy: int) -> bool:
	if gpx < 0 or gpx >= width * CELL_IMG or gpy < 0 or gpy >= max_depth_row * CELL_IMG:
		return false
	if is_solid_px(Vector2(gpx * SCALE + 1, gpy * SCALE + 1)):
		return false
	return not _has_water_px(gpx, gpy)


func _move_water_px(fx: int, fy: int, tx: int, ty: int) -> void:
	_set_water_px(fx, fy, false)
	_set_water_px(tx, ty, true)
	var tcell := Vector2i(floori(tx / float(CELL_IMG)), floori(ty / float(CELL_IMG)))
	_water_cells[tcell] = true


## Falling-sand rule for one pixel: straight down, else diagonal down, else a
## slow sideways spread if fully blocked below. Returns where it ended up
## (same position if it couldn't move).
func _flow_water_px(gpx: int, gpy: int) -> Vector2i:
	if _open_for_water(gpx, gpy + 1):
		_move_water_px(gpx, gpy, gpx, gpy + 1)
		return Vector2i(gpx, gpy + 1)
	var order := [-1, 1] if randi() % 2 == 0 else [1, -1]
	for d in order:
		if _open_for_water(gpx + d, gpy + 1):
			_move_water_px(gpx, gpy, gpx + d, gpy + 1)
			return Vector2i(gpx + d, gpy + 1)
	if randf() < 0.35:  # slow spread, not instant leveling
		for d in order:
			if _open_for_water(gpx + d, gpy):
				_move_water_px(gpx, gpy, gpx + d, gpy)
				return Vector2i(gpx + d, gpy)
	return Vector2i(gpx, gpy)


## Simulates one cell's worth of water pixels (bottom row first, so a pixel
## that falls doesn't get reprocessed as "new" water further down the same
## tick). `moved` tracks destinations already touched this tick across the
## whole step_water_simulation() call. Returns the remaining budget.
func _simulate_water_cell(cell: Vector2i, budget: int, moved: Dictionary) -> int:
	var x0 := cell.x * CELL_IMG
	var y0 := cell.y * CELL_IMG
	var any_water := false
	var fully_scanned := true
	for ly in range(CELL_IMG - 1, -1, -1):
		var gpy := y0 + ly
		for lx in range(CELL_IMG):
			var gpx := x0 + lx
			var key := Vector2i(gpx, gpy)
			if moved.has(key):
				any_water = true
				continue
			if not _has_water_px(gpx, gpy):
				continue
			if budget <= 0:
				fully_scanned = false
				any_water = true
				continue
			budget -= 1
			moved[_flow_water_px(gpx, gpy)] = true
			any_water = true
	if fully_scanned and not any_water:
		_water_cells.erase(cell)
	return budget


## Advance the water simulation near `center` (the player's world position).
## Throttled to WATER_SIM_INTERVAL and budget-capped so a large flooded area
## opening at once spreads its cost over several ticks instead of spiking.
## Called externally (from game.gd, alongside stream_around) rather than from
## MineWorld's own _process, since MineWorld deliberately holds no reference
## to the player.
func step_water_simulation(center: Vector2, delta: float) -> void:
	_water_sim_accum += delta
	if _water_sim_accum < WATER_SIM_INTERVAL:
		return
	_water_sim_accum = 0.0
	var ccell := world_to_cell(center)
	var budget := WATER_SIM_BUDGET
	var moved := {}
	# Bottom of the window first, same reasoning as within a single cell.
	for dy in range(WATER_SIM_REACH_CELLS, -WATER_SIM_REACH_CELLS - 1, -1):
		if budget <= 0:
			break
		var y := ccell.y + dy
		if y < 0 or y >= max_depth_row:
			continue
		for dx in range(-WATER_SIM_REACH_CELLS, WATER_SIM_REACH_CELLS + 1):
			if budget <= 0:
				break
			var cell := Vector2i(ccell.x + dx, y)
			if _water_cells.has(cell):
				budget = _simulate_water_cell(cell, budget, moved)


## Pixel-accurate "is there water physically here right now" -- wherever the
## simulation has actually moved it, not just the original generated cell.
func is_water_px(pos: Vector2) -> bool:
	return _has_water_px(int(pos.x) >> 1, int(pos.y) >> 1)
