class_name DiscoveryCard
extends CanvasLayer
## The teaching moment: shown once, the first time a player mines a given ore.
##
## Design rationale (see docs/EDUCATION.md):
## - The fact is EARNED, not browsed. Curiosity is opened by finding something
##   new and closed by the card, which is when a fact is most likely to stick.
## - The "wow" line is largest, because a single surprising fact is what gets
##   retold at the dinner table. Formation and uses sit underneath for the
##   kids who want more.
## - One button, no quiz here, no fail state. Pressure would turn a reward into
##   homework. Recall is tested later in the Geologist's Log, when it is
##   spaced out and pays ether.
##
## Landscape layout: the three detail sections sit side by side under the wow
## line instead of stacked, so the whole card fits the 720px-tall web canvas
## with room to spare and nothing ever needs scrolling.

signal dismissed

const ORE_ATLAS_ROW := 2
const CARD_WIDTH := 940

var _ore_id: String
var _card: Control


func _init(ore_id: String) -> void:
	_ore_id = ore_id


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var facts := Balance.ore_facts(_ore_id)
	var ore: Dictionary = Balance.ores.get(_ore_id, {})

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.78, 0.25)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel",
		UIKit.flat_style(Color(0.13, 0.11, 0.19, 0.99), 20, 28, 22))
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	center.add_child(_card)

	var col := UIKit.vbox(14)
	_card.add_child(col)

	# ---- gem art + name, banner on the right ----
	var head := UIKit.hbox(18)
	col.add_child(head)

	var art := TextureRect.new()
	art.texture = _ore_icon()
	art.custom_minimum_size = Vector2(84, 84)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(art)

	var name_col := UIKit.vbox(2)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(name_col)
	var title := String(facts.get("title", ore.get("name", _ore_id)))
	name_col.add_child(UIKit.label(title, 36))
	var sub := UIKit.hbox(12)
	name_col.add_child(sub)
	var symbol := String(facts.get("symbol", ""))
	if symbol != "":
		sub.add_child(UIKit.label(symbol, 17, UIKit.ETHER))
	var tagline := String(facts.get("tagline", ""))
	if tagline != "":
		sub.add_child(UIKit.label(tagline, 17, UIKit.TEXT_DIM))

	var banner := UIKit.label("NEW DISCOVERY!", 20, UIKit.ACCENT)
	banner.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(banner)

	# ---- the hook, biggest text on the card ----
	var wow := String(facts.get("wow", ""))
	if wow != "":
		var wow_panel := PanelContainer.new()
		wow_panel.add_theme_stylebox_override("panel",
			UIKit.flat_style(Color(0.24, 0.16, 0.06, 1.0), 14, 22, 14))
		col.add_child(wow_panel)
		var wow_label := UIKit.wrapped(wow, 23, Color(1.0, 0.92, 0.72))
		wow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wow_panel.add_child(wow_label)

	# ---- supporting detail, side by side ----
	var details := UIKit.hbox(26)
	col.add_child(details)
	# Formation is by far the longest text, so it gets the widest column; the
	# other two are a line or two each.
	for row: Array in [
		["HOW IT FORMS", facts.get("forms", ""), 1.7],
		["WHERE ON EARTH", facts.get("where", ""), 1.0],
		["WHAT WE USE IT FOR", facts.get("uses", ""), 1.0],
	]:
		var body := String(row[1])
		if body == "":
			continue
		var section := UIKit.vbox(4)
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.size_flags_stretch_ratio = float(row[2])
		details.add_child(section)
		section.add_child(UIKit.label(String(row[0]), 14, UIKit.ACCENT))
		section.add_child(UIKit.wrapped(body, 16))

	# ---- value + the one button ----
	var foot := UIKit.hbox(16)
	col.add_child(foot)
	var value := int(ore.get("value", 0))
	var value_label := UIKit.label("Sells for %d $ each" % value if value > 0 else "", 18, UIKit.GOOD)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(value_label)
	var close := UIKit.action_button("GOT IT!", true, 220, 22)
	close.pressed.connect(_dismiss)
	foot.add_child(close)

	# Pop-in so the card feels like a prize, not a dialog box. The card has no
	# size until the first layout pass, so keep the pivot centred as it resizes.
	_card.resized.connect(func() -> void: _card.pivot_offset = _card.size * 0.5)
	_card.scale = Vector2(0.82, 0.82)
	_card.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_card, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_card, "modulate:a", 1.0, 0.20)

	AudioManager.play("sell", -2.0, 1.15)
	SettingsManager.vibrate(60)


func _ore_icon() -> Texture2D:
	# Crop this ore's gems straight out of the tile atlas so the card always
	# shows exactly what the player just dug up.
	var atlas_tex: Texture2D = load("res://assets/textures/tiles.png")
	var col := int(Balance.ores.get(_ore_id, {}).get("atlas_col", 0))
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_tex
	atlas.region = Rect2(col * 64, ORE_ATLAS_ROW * 64, 64, 64)
	return atlas


## Public so automated tests can act like a player tapping "GOT IT!".
func dismiss() -> void:
	_dismiss()


func _dismiss() -> void:
	get_tree().paused = false
	dismissed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_dismiss()
