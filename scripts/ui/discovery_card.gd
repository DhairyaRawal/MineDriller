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

signal dismissed

const ORE_ATLAS_ROW := 2

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

	_card = UIKit.panel(Color(0.13, 0.11, 0.19, 0.99), 26)
	_card.custom_minimum_size = Vector2(640, 0)
	center.add_child(_card)

	var col := UIKit.vbox(14)
	_card.add_child(col)

	# ---- banner ----
	var banner := UIKit.label("NEW DISCOVERY!", 26, UIKit.ACCENT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(banner)

	# ---- gem art + name ----
	var head := UIKit.hbox(18)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(head)

	var art := TextureRect.new()
	art.texture = _ore_icon()
	art.custom_minimum_size = Vector2(104, 104)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(art)

	var name_col := UIKit.vbox(2)
	head.add_child(name_col)
	var title := String(facts.get("title", ore.get("name", _ore_id)))
	name_col.add_child(UIKit.label(title, 46))
	var symbol := String(facts.get("symbol", ""))
	if symbol != "":
		name_col.add_child(UIKit.label(symbol, 22, UIKit.ETHER))
	var tagline := String(facts.get("tagline", ""))
	if tagline != "":
		var tag := UIKit.label(tagline, 20, UIKit.TEXT_DIM)
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.custom_minimum_size = Vector2(330, 0)
		name_col.add_child(tag)

	# ---- the hook, biggest thing on the card ----
	var wow := String(facts.get("wow", ""))
	if wow != "":
		var wow_panel := UIKit.panel(Color(0.24, 0.16, 0.06, 1.0), 16)
		col.add_child(wow_panel)
		var wow_label := UIKit.label(wow, 27, Color(1.0, 0.92, 0.72))
		wow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wow_panel.add_child(wow_label)

	# ---- supporting detail ----
	for row: Array in [
		["HOW IT FORMS", facts.get("forms", "")],
		["WHERE ON EARTH", facts.get("where", "")],
		["WHAT WE USE IT FOR", facts.get("uses", "")],
	]:
		var body := String(row[1])
		if body == "":
			continue
		col.add_child(UIKit.label(String(row[0]), 17, UIKit.ACCENT))
		var text := UIKit.label(body, 21)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(text)

	var value := int(ore.get("value", 0))
	if value > 0:
		col.add_child(UIKit.label("Sells for %d $ each" % value, 20, UIKit.GOOD))

	var close := UIKit.button("GOT IT!", 32, true)
	close.pressed.connect(_dismiss)
	col.add_child(close)

	# Pop-in so the card feels like a prize, not a dialog box.
	_card.pivot_offset = _card.size * 0.5
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
