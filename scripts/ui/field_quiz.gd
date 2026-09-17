class_name FieldQuiz
extends CanvasLayer
## The Geologist's Log: retrieval practice disguised as a payday.
##
## Design rationale (see docs/EDUCATION.md):
## - Only asks about things the player has ACTUALLY discovered. Never quizzes
##   content it has not taught, so a wrong answer is always recoverable.
## - Correct answers pay ether. Wrong answers cost nothing and immediately show
##   the right answer plus the reason. Punishing a child for a wrong guess is
##   the fastest way to make them stop opening the log.
## - Entirely optional and player-initiated, which keeps it autonomy-supportive
##   rather than a homework gate on the shop.
##
## Landscape layout: a centred reading column rather than full screen width,
## with the answers side by side instead of a stack of tall buttons.

signal closed

const REWARD_ETHER := 1
const QUESTIONS := 3
const COLUMN_WIDTH := 860

var _pool: Array = []
var _index := 0
var _correct := 0
var _body: VBoxContainer
var _progress: Label


func _ready() -> void:
	layer = 26
	var col := UIKit.screen(self, "GEOLOGIST'S LOG")
	_progress = UIKit.label("", 15, UIKit.TEXT_DIM)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_progress)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(center)
	_body = UIKit.vbox(16)
	_body.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	center.add_child(_body)

	_build_pool()
	if _pool.is_empty():
		_show_empty()
	else:
		_ask()


## Questions come only from discovered ores and reached layers.
func _build_pool() -> void:
	for ore_id: String in GameState.codex_discovered:
		var facts := Balance.ore_facts(String(ore_id))
		for q: Dictionary in facts.get("quiz", []):
			_pool.append({"q": q, "subject": String(facts.get("title", ore_id))})

	var deepest_layer := Balance.layer_id_for_km(float(GameState.stats["deepest_km"]))
	for layer_id in range(1, deepest_layer + 1):
		var lf := Balance.layer_facts(layer_id)
		for q: Dictionary in lf.get("quiz", []):
			_pool.append({"q": q, "subject": String(lf.get("title", "Earth"))})

	_pool.shuffle()
	if _pool.size() > QUESTIONS:
		_pool.resize(QUESTIONS)


func _show_empty() -> void:
	var msg := UIKit.wrapped(
		"Go and mine something first!\n\nEvery new ore you dig up adds pages to your log, and every page is worth ether.",
		20, UIKit.TEXT_DIM)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(msg)
	var back := UIKit.action_button("BACK")
	back.pressed.connect(_close)
	_body.add_child(back)


func _clear_body() -> void:
	for child in _body.get_children():
		child.queue_free()


func _centered(text: String, size: int, color := UIKit.TEXT) -> Label:
	var l := UIKit.wrapped(text, size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _ask() -> void:
	_clear_body()
	_progress.text = "Question %d of %d" % [_index + 1, _pool.size()]

	var entry: Dictionary = _pool[_index]
	var q: Dictionary = entry["q"]

	_body.add_child(_centered(String(entry["subject"]), 16, UIKit.ACCENT))
	_body.add_child(_centered(String(q["q"]), 26))

	var options: Array = q["options"]
	# Shuffle presentation so the answer is never in a predictable slot.
	var order: Array = []
	for i in options.size():
		order.append(i)
	order.shuffle()

	var row := UIKit.hbox(12)
	_body.add_child(row)
	for slot: int in order:
		var btn := UIKit.button(String(options[slot]), 18)
		btn.custom_minimum_size.y = 52
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: _answer(slot == int(q["answer"]), q))
		row.add_child(btn)


func _answer(is_right: bool, q: Dictionary) -> void:
	_clear_body()
	if is_right:
		_correct += 1
		GameState.add_ether(REWARD_ETHER)
		AudioManager.play("upgrade")
		SettingsManager.vibrate(45)
		_body.add_child(_centered("Correct!  +%d ether" % REWARD_ETHER, 30, UIKit.GOOD))
	else:
		AudioManager.play("click", -4.0, 0.7)
		_body.add_child(_centered("Not quite!", 30, UIKit.ACCENT))
		_body.add_child(_centered(
			"Answer: %s" % String(q["options"][int(q["answer"])]), 20))

	# The explanation is the actual teaching, so it shows either way.
	var note := String(q.get("note", ""))
	if note != "":
		var panel := UIKit.panel(Color(0.18, 0.16, 0.24, 1.0), 14)
		_body.add_child(panel)
		panel.add_child(_centered(note, 18))

	var next := UIKit.action_button(
		"NEXT" if _index + 1 < _pool.size() else "FINISH")
	next.pressed.connect(_advance)
	_body.add_child(next)


func _advance() -> void:
	_index += 1
	if _index < _pool.size():
		_ask()
	else:
		_finish()


func _finish() -> void:
	_clear_body()
	_progress.text = ""
	_body.add_child(_centered("%d / %d correct" % [_correct, _pool.size()], 34, UIKit.GOOD))

	# Effort-focused praise, not ability praise ("you are so clever" teaches
	# kids to avoid hard things; "you worked that out" does the opposite).
	var msg := "Great digging. Come back after you find something new!"
	if _correct == _pool.size():
		msg = "Every single one. You have really been paying attention down there!"
	elif _correct == 0:
		msg = "Tricky set! Read the cards in your Codex and try again any time."
	_body.add_child(_centered(msg, 19, UIKit.TEXT_DIM))

	var back := UIKit.action_button("BACK TO THE SURFACE", true, 280)
	back.pressed.connect(_close)
	_body.add_child(back)
	GameState.unlock_achievement("log_keeper")
	if _correct == _pool.size():
		GameState.unlock_achievement("quiz_ace")


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
