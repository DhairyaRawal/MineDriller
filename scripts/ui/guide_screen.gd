class_name GuideScreen
extends CanvasLayer
## GuideScreen: every contextual tip in one place, opened from the pause menu.
## The floating '?' tips only appear near their situation; this lets a player
## look something up before they've run into it, or re-read one afterwards.
## Same data as the '?' bubbles (data/tips.json), grouped by category in file
## order.

signal closed


func _ready() -> void:
	layer = 32
	# Opened from the pause menu, so the tree is already paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 80)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var col := UIKit.vbox(14)
	margin.add_child(col)
	col.add_child(UIKit.title("GUIDE", 40))
	# Deliberately does NOT mark anything read: this screen shows every tip at
	# once, so treating it as reading would silently retire every '?' in the
	# game, including ones for things the player hasn't met yet.
	var sub := UIKit.label(
		"Each of these first appears as a ? over the thing itself when you're near it, "
		+ "and retires once you've read it. They all stay here for good.", 18, UIKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := UIKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for category in Balance.tip_categories:
		var header := UIKit.label(String(category).to_upper(), 24,
			UIKit.BAD if category == "Dangers" else UIKit.ACCENT)
		list.add_child(header)
		for id: String in Balance.tips:
			var tip: Dictionary = Balance.tips[id]
			if tip.get("category", "") == category:
				list.add_child(_row(tip))

	var back := UIKit.button("BACK", 28, true)
	back.pressed.connect(_close)
	col.add_child(back)


func _row(tip: Dictionary) -> PanelContainer:
	var panel := UIKit.panel()
	var box := UIKit.vbox(4)
	panel.add_child(box)
	box.add_child(UIKit.label(String(tip["title"]), 24))
	var body := UIKit.label(String(tip["body"]), 19, UIKit.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	return panel


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Consume Esc here. The pause menu underneath also listens for it, and would
	# otherwise resume the game straight out from under the guide.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
