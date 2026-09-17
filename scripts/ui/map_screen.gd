class_name MapScreen
extends CanvasLayer
## MapScreen: the world map, revealed one chunk at a time -- the same
## granularity MineWorld._visited_chunks tracks for save persistence, so
## there's no false precision here. Unvisited chunks stay under fog of war,
## and depot markers only show up once their chunk has actually been seen.
## Pauses the tree while open, like DiscoveryCard: reading the map shouldn't
## cost heat or let an enemy close the distance.

signal closed

var _world: MineWorld
var _player_pos: Vector2


func _init(world: MineWorld, player_pos: Vector2) -> void:
	_world = world
	_player_pos = player_pos


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS

	var col := UIKit.screen(self, "MAP")
	var legend := UIKit.label(
		"Green = you.  Cyan = a discovered safe-spot depot.  Fog = unexplored.",
		14, UIKit.TEXT_DIM)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(legend)

	var canvas := MapCanvas.new()
	canvas.world = _world
	canvas.player_pos = _player_pos
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(canvas)
	# The canvas has no size yet at add_child time -- the container assigns
	# it one on the next layout pass, so redraw once that actually happens.
	canvas.resized.connect(canvas.queue_redraw)

	var foot := UIKit.footer()
	col.add_child(foot)
	var close := UIKit.action_button("CLOSE")
	close.pressed.connect(_close)
	foot.add_child(close)

	get_tree().paused = true


func _close() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the map rather than falling through to the pause menu.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()


class MapCanvas:
	extends Control
	## Draws the world as stacked horizontal chunk bands -- matches the
	## visited-chunk tracking granularity exactly. Fog for unvisited chunks,
	## a per-layer tint for visited ones, markers for the player and any
	## depot inside an already-visited chunk.

	var world: MineWorld
	var player_pos: Vector2

	const LAYER_COLORS := [
		Color(0.42, 0.30, 0.20), Color(0.55, 0.42, 0.30), Color(0.45, 0.30, 0.28),
		Color(0.60, 0.38, 0.32), Color(0.85, 0.35, 0.20),
	]

	func _draw() -> void:
		if world == null or size.y <= 0.0:
			return
		var chunk_h := world.chunk_h
		var total_chunks := ceili(float(world.max_depth_row) / float(chunk_h))
		var band_h := size.y / float(total_chunks)
		for chunk in total_chunks:
			var rect := Rect2(0, chunk * band_h, size.x, band_h + 1.0)
			if world.is_chunk_visited(chunk):
				var mid_row := chunk * chunk_h + chunk_h * 0.5
				var layer_id := Balance.layer_id_for_row(int(mid_row))
				draw_rect(rect, LAYER_COLORS[clampi(layer_id - 1, 0, LAYER_COLORS.size() - 1)])
			else:
				draw_rect(rect, Color(0.03, 0.03, 0.04))
		draw_line(Vector2(0, 1), Vector2(size.x, 1), UIKit.ACCENT, 2.0)  # surface

		for depot: Dictionary in world.depot_positions():
			var row := int((depot["rect"] as Rect2i).position.y)
			var chunk := floori(row / float(chunk_h))
			if not world.is_chunk_visited(chunk):
				continue
			var frac := float(row) / float(world.max_depth_row)
			draw_circle(Vector2(size.x * 0.85, frac * size.y), 5.0, UIKit.ETHER)

		var player_frac := clampf(
			player_pos.y / float(world.max_depth_row * MineWorld.TILE), 0.0, 1.0)
		draw_circle(Vector2(size.x * 0.5, player_frac * size.y), 7.0, UIKit.GOOD)
