class_name GuideScreen
extends CanvasLayer
## GuideScreen: every contextual tip in one place, opened from the pause menu.
## The floating '?' tips only appear near their situation; this lets a player
## look something up before they've run into it, or re-read one afterwards.
## Same data as the '?' bubbles (data/tips.json), grouped by category in file
## order.
##
## Landscape layout: every tip title is visible at once on the left, grouped by
## category, and the selected tip reads on the right. Sixteen full tips in one
## column was a long scroll; this is one click.

signal closed

var _page_title: Label
var _page_category: Label
var _page_body: Label


func _ready() -> void:
	layer = 32
	# Opened from the pause menu, so the tree is already paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var col := UIKit.screen(self, "GUIDE")
	# Deliberately does NOT mark anything read: this screen shows every tip at
	# once, so treating it as reading would silently retire every '?' in the
	# game, including ones for things the player hasn't met yet.
	var sub := UIKit.label(
		"Each of these first appears as a ? over the thing itself when you're near it, "
		+ "and retires once you've read it. They all stay here for good.", 14, UIKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var split := UIKit.hbox(24)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	var index := UIKit.vbox(6)
	index.custom_minimum_size = Vector2(560, 0)
	split.add_child(index)

	var page_panel := UIKit.panel(Color(0.15, 0.13, 0.20, 0.95), 14)
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(page_panel)
	var page := UIKit.vbox(10)
	page_panel.add_child(page)
	_page_category = UIKit.label("", 14, UIKit.TEXT_DIM)
	page.add_child(_page_category)
	_page_title = UIKit.label("", 30, UIKit.ACCENT)
	page.add_child(_page_title)
	_page_body = UIKit.wrapped("", 20)
	page.add_child(_page_body)

	var group := ButtonGroup.new()
	var first := ""
	for category in Balance.tip_categories:
		index.add_child(UIKit.label(String(category).to_upper(), 15,
			UIKit.BAD if category == "Dangers" else UIKit.ACCENT))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		index.add_child(flow)
		for id: String in Balance.tips:
			var tip: Dictionary = Balance.tips[id]
			if tip.get("category", "") != category:
				continue
			var b := UIKit.list_button(String(tip["title"]), group)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.pressed.connect(func() -> void: _show(id))
			flow.add_child(b)
			if first == "":
				first = id
				b.button_pressed = true
		index.add_child(_gap(4))

	if first != "":
		_show(first)

	var foot := UIKit.footer()
	col.add_child(foot)
	var back := UIKit.action_button("BACK")
	back.pressed.connect(_close)
	foot.add_child(back)


func _gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _show(id: String) -> void:
	var tip: Dictionary = Balance.tips[id]
	var category := String(tip.get("category", ""))
	_page_category.text = category.to_upper()
	_page_category.add_theme_color_override("font_color",
		UIKit.BAD if category == "Dangers" else UIKit.TEXT_DIM)
	_page_title.text = String(tip["title"])
	_page_body.text = String(tip["body"])


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Consume Esc here. The pause menu underneath also listens for it, and would
	# otherwise resume the game straight out from under the guide.
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
