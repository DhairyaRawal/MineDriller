extends Node2D
## Game: the in-run orchestrator. Owns the world, player, camera, enemies
## and run-scoped UI (HUD, shop, popups). Implements the surface loop:
## arrive -> auto-sell -> shop -> dive again. Everything is constructed in
## code; game.tscn is just this script on a Node2D.

const MAX_LIVE_ENEMIES := 24
const DEPOT_RADIUS := 90.0

var world: MineWorld
var player: Player
var camera: Camera2D
var hud: HUD

var _enemies: Node2D
var _bg: ColorRect
var _vignette: ColorRect
var _last_stream_row := -99999
var _was_at_surface := true
var _shake := 0.0
var _busy_ui := false
var _nearby_depot_id := ""
var _tips: TipSystem
var _shop_anchor := Vector2.ZERO
## Captured once at _ready rather than read live. finish_ftue() flips
## GameState.ftue_mode off a frame or two BEFORE this scene is torn down, and
## in that window a live check would let the tutorial world's dig state and
## position leak into the real save.
var _persists_world := true
var _is_ftue := false


## Where a dive starts: horizontally centred, one row above the grass. Derived
## from world width rather than fixed, so widening the world doesn't strand the
## player and the refinery off to one side.
func _spawn_cell() -> Vector2i:
	return Vector2i(world.width / 2, -1)


func _ready() -> void:
	_build_background()
	world = MineWorld.new()
	add_child(world)
	_is_ftue = GameState.ftue_mode
	_persists_world = GameState.persists_world()
	var seed_value := GameState.daily_seed() if GameState.daily_mode else GameState.world_seed
	world.setup(seed_value)
	if _is_ftue:
		world.use_authored_layout(FTUE.build_layout(), FTUE.WIDTH, FTUE.DEPTH)
	# Daily Challenge and the tutorial are fresh throwaway worlds every time,
	# so the persistent world diff/position only apply to a normal dive.
	var resuming := _persists_world and GameState.last_position != Vector2.ZERO
	if _persists_world:
		world.import_diff(GameState.world_diff)

	_build_surface_decor()

	_enemies = Node2D.new()
	_enemies.name = "Enemies"
	add_child(_enemies)

	player = Player.new()
	player.world = world
	player.position = GameState.last_position if resuming else world.cell_to_world(_spawn_cell())
	player.busted.connect(_on_busted)
	player.chest_opened.connect(_on_chest_opened)
	add_child(player)

	world.chunk_spawns_ready.connect(_on_chunk_spawns)
	# Stream around wherever the player actually starts -- a resumed dive can
	# start far from row 0, and unstreamed chunks read as solid (is_solid_px
	# defaults to "solid" until a chunk's image has been built).
	var start_row := world.world_to_cell(player.position).y
	world.stream_around(start_row)
	_last_stream_row = start_row

	SaveManager.before_save.connect(_sync_world_diff)

	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.limit_left = 0
	camera.limit_right = world.width * MineWorld.TILE
	camera.limit_top = -720
	camera.limit_bottom = world.max_depth_row * MineWorld.TILE
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.position = player.position
	add_child(camera)
	camera.make_current()

	var fx := FXLayer.new()
	fx.name = "FX"
	add_child(fx)

	hud = HUD.new()
	hud.pause_pressed.connect(_open_pause)
	hud.shop_pressed.connect(_open_shop)
	hud.depot_pressed.connect(_open_depot)
	hud.map_pressed.connect(_open_map)
	add_child(hud)

	# Contextual '?' tips run everywhere, the tutorial included -- it's a good
	# place to first meet the '?' itself. They replace the old one-shot toast
	# tutorial, whose hints now live in data/tips.json and never retire.
	_tips = TipSystem.new()
	_tips.world = world
	_tips.player = player
	_tips.enemies = _enemies
	_tips.shop_anchor = _shop_anchor
	add_child(_tips)

	if _is_ftue:
		var ftue := FTUE.new()
		ftue.player = player
		add_child(ftue)
	Events.codex_discovered.connect(_on_ore_discovered)
	Events.fx_shake.connect(func(strength: float) -> void:
		_shake = maxf(_shake, strength))
	Events.cargo_sold.connect(_on_cargo_sold)
	Events.upgrade_purchased.connect(func(id: String, _lvl: int) -> void:
		player.refresh_hull_after_upgrade()
		# Buying the bay at the surface should hand you the new capacity now,
		# not on the next surfacing.
		if id == "rockets":
			GameState.refill_rockets())

	AudioManager.play_music()
	if GameState.daily_mode:
		Events.toast.emit("Daily Challenge: %s - earn as much as you can in one dive!"
			% GameState.today_key())


func _build_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	_bg = ColorRect.new()
	_bg.color = Color(0.45, 0.68, 0.85)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = load("res://assets/shaders/backdrop.gdshader")
	_bg.material = bg_mat
	bg_layer.add_child(_bg)

	# Vignette sits above the world but below the HUD (layer 10).
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 5
	add_child(fx_layer)
	_vignette = ColorRect.new()
	_vignette.color = Color.WHITE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_mat := ShaderMaterial.new()
	vig_mat.shader = load("res://assets/shaders/vignette.gdshader")
	_vignette.material = vig_mat
	fx_layer.add_child(_vignette)


func _build_surface_decor() -> void:
	# The refinery is the surface landmark: ore in, metal out. Its base is
	# pinned to ground level (row 0) so it sits ON the grass, not floating.
	var shop_sprite := Sprite2D.new()
	shop_sprite.texture = load("res://assets/textures/shop.png")
	shop_sprite.centered = false
	var art_h := float(shop_sprite.texture.get_height())
	shop_sprite.position = Vector2(
		_spawn_cell().x * MineWorld.TILE - 330.0, -art_h + 6.0)
	add_child(shop_sprite)
	# The shop tip's '?' floats over the refinery's roof.
	_shop_anchor = shop_sprite.position + Vector2(shop_sprite.texture.get_width() * 0.5, 0.0)


func _process(delta: float) -> void:
	# Camera follow + shake
	_shake = maxf(0.0, _shake - delta * 3.0)
	var offset := Vector2.ZERO
	if _shake > 0.0 and SettingsManager.screen_shake_enabled:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 14.0
	camera.position = player.position + Vector2(0, -80) + offset

	# Backdrop + vignette follow the camera and deepen with depth.
	var row := world.world_to_cell(player.position).y
	var depth_frac := clampf(float(row) / float(world.max_depth_row), 0.0, 1.0)
	var view := get_viewport_rect().size
	var bg_mat := _bg.material as ShaderMaterial
	if bg_mat != null:
		bg_mat.set_shader_parameter("cam_y", camera.position.y)
		bg_mat.set_shader_parameter("view_h", view.y)
		bg_mat.set_shader_parameter("depth_frac", depth_frac)
	var vig_mat := _vignette.material as ShaderMaterial
	if vig_mat != null:
		# Project the pod into screen UV so the light pool tracks it.
		var rel := (player.position - camera.position) / view
		vig_mat.set_shader_parameter("light_uv", Vector2(0.5, 0.5) + rel)
		vig_mat.set_shader_parameter("aspect", view.x / maxf(view.y, 1.0))
		vig_mat.set_shader_parameter("strength",
			clampf(depth_frac * 2.2, 0.0, 1.0) * 0.82)
		vig_mat.set_shader_parameter("radius", lerpf(1.25, 0.62, depth_frac))

	# Tip bubbles hide while a shop, depot or map screen owns the display. Those
	# don't all pause the tree, so the tips can't rely on pausing to stop.
	_tips.suppressed = _busy_ui

	# Chunk streaming
	if absi(row - _last_stream_row) >= 8:
		_last_stream_row = row
		world.stream_around(row)

	world.step_water_simulation(player.position, delta)

	# Surface arrival: auto-sell and reveal the shop
	var at_surface := player.position.y < MineWorld.TILE * 0.5
	if at_surface and not _was_at_surface:
		hud.set_at_surface(true)
		if not GameState.cargo.is_empty():
			GameState.sell_cargo()
			AudioManager.play("sell")
			SettingsManager.vibrate(50)
		# The mine closes up behind you: narrow shafts and ramps refill, wide
		# chambers stay. Done here rather than on a timer so it can only ever
		# happen while the player is safely above ground.
		GameState.refill_rockets()
		# No healing in the tutorial: it isn't one of the mechanics being taught,
		# and a shaft vanishing mid-lesson would just read as a bug.
		if not _is_ftue and world.heal_narrow_tunnels() > 0:
			Events.toast.emit("The mine has collapsed behind you - your shafts are gone.")
	elif not at_surface and _was_at_surface:
		hud.set_at_surface(false)
	_was_at_surface = at_surface

	# Depot proximity: cheap (15 fixed points), only re-emit on change so the
	# HUD isn't toggling visibility every frame for no reason.
	var found_id := ""
	for depot: Dictionary in world.depot_positions():
		if player.position.distance_to(depot["center"]) < DEPOT_RADIUS:
			found_id = String(depot["id"])
			break
	if found_id != _nearby_depot_id:
		_nearby_depot_id = found_id
		Events.depot_proximity.emit(_nearby_depot_id)
		# Depots double as supply caches: simply reaching one restocks rockets,
		# no menu required. Fires on arrival only, not every frame in range.
		if found_id != "" and GameState.rockets < GameState.max_rockets():
			GameState.refill_rockets()
			AudioManager.play("pickup", -2.0, 0.8)
			Events.toast.emit("Depot resupply - rockets restocked.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _busy_ui and not get_tree().paused:
		_open_pause()
	elif event.is_action_pressed("interact") and not _busy_ui and not get_tree().paused:
		_open_depot()


func _notification(what: int) -> void:
	# Android back button always pauses. OS focus loss only pauses on mobile:
	# on desktop the window loses focus while the scene is still being built
	# (and on every alt-tab), which would pause the tree before the menu can
	# attach and strand the player on a frozen screen.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_request_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("mobile"):
		_request_pause()


func _request_pause() -> void:
	# Never open mid-setup: add_child() fails while the parent is still
	# building its children, which used to leave the tree paused with no menu.
	if not is_inside_tree() or not is_node_ready():
		return
	if get_tree().paused or _busy_ui:
		return
	_open_pause.call_deferred()


# ------------------------------------------------------------------ enemies

func _on_chunk_spawns(spawns: Array) -> void:
	for spawn: Dictionary in spawns:
		if _enemies.get_child_count() >= MAX_LIVE_ENEMIES:
			return
		var type: String = spawn["type"]
		var enemy: EnemyBase
		match type:
			"crawly":
				enemy = Crawly.new()
			"crawly_elite":
				enemy = CrawlyElite.new()
			"zombie":
				enemy = ZombieMiner.new()
			"zombie_elite":
				enemy = ZombieElite.new()
			"govt":
				enemy = GovtDriller.new()
			"govt_boss":
				enemy = PlasmaDriller.new()
			"magma_slug":
				enemy = MagmaSlug.new()
			"crystal_bat":
				enemy = CrystalBat.new()
			"rock_golem":
				enemy = RockGolem.new()
			_:
				continue
		enemy.setup(world, player, Balance.enemies[type], "res://assets/textures/%s.png" % type)
		enemy.kind = type
		enemy.position = world.cell_to_world(spawn["cell"])
		_enemies.add_child(enemy)


# ----------------------------------------------------------------- treasure

func _on_chest_opened(cell: Vector2i) -> void:
	var t := Balance.treasure
	var layer: Dictionary = Balance.layer_for_row(cell.y)
	var count := randi_range(int(t["min_ores"]), int(t["max_ores"]))
	var collected := 0
	var overflow_money := 0
	for i in count:
		var ore_id := Balance.pick_ore(layer, 0.6, randf())
		GameState.discover_ore(ore_id)
		if GameState.try_collect_ore(ore_id):
			collected += 1
		else:
			overflow_money += int(Balance.ores[ore_id]["value"])
	var bonus := randi_range(int(t["bonus_money_min"]), int(t["bonus_money_max"]))
	bonus += overflow_money
	GameState.add_money(bonus)
	var msg := "Treasure vault! +%d $ and %d ores" % [bonus, collected]
	if randf() < float(t["ether_chance"]):
		GameState.add_ether(1)
		msg += " +1 ether"
	GameState.stats["treasures_found"] = int(GameState.stats["treasures_found"]) + 1
	Events.toast.emit(msg)
	AudioManager.play("sell", 0.0, 1.2)
	SettingsManager.vibrate(60)


# ------------------------------------------------------------- persistence

## Pulled by SaveManager right before it writes to disk, so the save always
## carries a fresh world diff without exporting it every frame.
func _sync_world_diff() -> void:
	if _persists_world:
		GameState.world_diff = world.export_diff()


# ---------------------------------------------------------------- run flow

func _on_busted(reason: String) -> void:
	_shake = 1.0
	_busy_ui = true
	var screen := BustScreen.new(reason)
	screen.respawn_requested.connect(_respawn)
	add_child(screen)


func _respawn() -> void:
	# The tutorial's ore supply is finite and hand-placed. A bust empties the
	# cargo, and the ore it held is already mined out of the level -- so a
	# normal respawn could leave the player unable to ever afford the upgrade.
	# Rebuilding the scene restores every ore cell. Money and the Drill Bit are
	# GameState, not world state, so any progress already banked survives.
	if _is_ftue:
		get_tree().reload_current_scene()
		return
	_busy_ui = false
	player.respawn(world.cell_to_world(_spawn_cell()))
	world.stream_around(0)
	_last_stream_row = 0
	camera.position = player.position


## First time an ore is ever mined, teach it. Queued through call_deferred so
## the card never tries to attach while the world is mid-carve.
func _on_ore_discovered(ore_id: String) -> void:
	if Balance.ore_facts(ore_id).is_empty():
		return
	_show_discovery.call_deferred(ore_id)


func _show_discovery(ore_id: String) -> void:
	if not is_inside_tree():
		return
	_busy_ui = true
	var card := DiscoveryCard.new(ore_id)
	card.dismissed.connect(func() -> void: _busy_ui = false)
	add_child(card)


func _on_cargo_sold(total_money: int, total_ether: int, breakdown: Dictionary) -> void:
	_busy_ui = true
	var popup := SellPopup.new(total_money, total_ether, breakdown)
	popup.dismissed.connect(func() -> void: _busy_ui = false)
	add_child(popup)


func _open_shop() -> void:
	if _busy_ui:
		return
	_busy_ui = true
	var shop := ShopScreen.new()
	shop.closed.connect(func() -> void: _busy_ui = false)
	add_child(shop)


func _open_depot() -> void:
	if _busy_ui or _nearby_depot_id == "":
		return
	_busy_ui = true
	var depot := DepotScreen.new(_nearby_depot_id)
	depot.closed.connect(func() -> void: _busy_ui = false)
	add_child(depot)


func _open_map() -> void:
	if _busy_ui:
		return
	_busy_ui = true
	var map := MapScreen.new(world, player.position)
	map.closed.connect(func() -> void: _busy_ui = false)
	add_child(map)


func _open_pause() -> void:
	if _busy_ui or not is_inside_tree() or get_tree().paused:
		return
	var menu := PauseMenu.new()
	menu.quit_to_menu.connect(func() -> void:
		get_tree().paused = false
		SaveManager.save_now()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	# Attach first, pause second: if the menu can't attach we must not be
	# left with a paused tree and no way to resume.
	add_child(menu)
	get_tree().paused = true
	AudioManager.stop_loops()
