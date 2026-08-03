extends Node
## Dev tool: drop the pod deep into a layer and capture it, so the depth
## grading, vignette and parallax backdrop can be reviewed without playing
## down there. Run:
##   godot --path . res://tools/deep_shot.tscn


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://docs/images"))

	GameState.tutorial_done = true
	GameState.upgrade_levels["drill_bit"] = 5
	GameState.upgrade_levels["cooling"] = 4

	var game: Node2D = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	for i in 10:
		await get_tree().physics_frame

	for shot: Array in [["l3", 150], ["l5", 320]]:
		var row: int = shot[1]
		game.world.stream_around(row)
		game.player.position = game.world.cell_to_world(Vector2i(16, row))
		game.camera.position = game.player.position
		for i in 30:
			await get_tree().physics_frame
		# Carve a pocket so tunnel rim shading is visible in the shot.
		game.world.carve_circle(game.player.position, 120.0, 5)
		game.world.carve_circle(game.player.position + Vector2(150, 90), 90.0, 5)
		for i in 10:
			await get_tree().physics_frame
		await _capture("res://docs/images/deep_%s.png" % shot[0])

	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
