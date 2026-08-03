extends Node
## Screenshot runner (dev tool, excluded from export): boots the real game,
## simulates a little play, and saves PNG captures to docs/images/.
## Run:  godot --path . res://tools/screenshot_runner.tscn


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/images"))

	# 1) Main menu
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	for i in 20:
		await get_tree().process_frame
	await _capture("res://docs/images/menu.png")
	menu.queue_free()
	await get_tree().process_frame

	# 2) In-game: drill down a few tiles first
	GameState.tutorial_done = true
	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	for i in 40:
		await get_tree().physics_frame
	# Drill down in bursts (cooling between) to open an organic shaft.
	for burst in 4:
		Input.action_press("move_down")
		for i in 55:
			await get_tree().physics_frame
		Input.action_release("move_down")
		for i in 45:
			await get_tree().physics_frame
	# Carve a rising ramp so the shot shows the diagonal route back up.
	Input.action_press("move_right")
	Input.action_press("move_up")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("move_up")
	Input.action_release("move_right")
	for i in 10:
		await get_tree().physics_frame
	await _capture("res://docs/images/gameplay.png")

	# 3) Shop screen
	var shop := ShopScreen.new()
	add_child(shop)
	for i in 15:
		await get_tree().process_frame
	await _capture("res://docs/images/shop.png")

	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
