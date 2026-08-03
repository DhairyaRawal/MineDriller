extends Node
## Dev tool: capture the education and menu screens without playing to them.
##   godot --path . res://tools/ui_shot.tscn


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://docs/images"))

	# Pretend this player has been mining for a while.
	GameState.tutorial_done = true
	GameState.ether = 6
	GameState.money = 940
	GameState.stats["deepest_km"] = 4200.0
	GameState.codex_discovered = ["iron", "silver", "gold", "ruby"]

	# 1) Discovery Card, the first-find teaching moment.
	var card := DiscoveryCard.new("ruby")
	add_child(card)
	for i in 30:
		await get_tree().process_frame
	await _capture("res://docs/images/discovery_card.png")
	card.dismiss()
	await get_tree().process_frame

	# 2) Geologist's Log.
	var quiz := FieldQuiz.new()
	add_child(quiz)
	for i in 20:
		await get_tree().process_frame
	await _capture("res://docs/images/quiz.png")
	quiz.queue_free()
	await get_tree().process_frame

	# 3) Codex.
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	for i in 15:
		await get_tree().process_frame
	menu._show_codex()
	for i in 15:
		await get_tree().process_frame
	await _capture("res://docs/images/codex.png")

	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
