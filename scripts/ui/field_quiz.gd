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

signal closed

const REWARD_ETHER := 1
const QUESTIONS := 3

var _pool: Array = []
var _index := 0
var _correct := 0
var _body: VBoxContainer
var _progress: Label


func _ready() -> void:
	layer = 26
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var col := UIKit.vbox(16)
	margin.add_child(col)
	col.add_child(UIKit.title("GEOLOGIST'S LOG"))
	_progress = UIKit.label("", 20, UIKit.TEXT_DIM)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_progress)

	_body = UIKit.vbox(14)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	_build_pool()
	if _pool.is_empty():
		_show_empty(col)
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


func _show_empty(col: VBoxContainer) -> void:
	var msg := UIKit.label(
		"Go and mine something first!\n\nEvery new ore you dig up adds pages to your log, and every page is worth ether.",
		24, UIKit.TEXT_DIM)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(msg)
	var back := UIKit.button("BACK", 30, true)
	back.pressed.connect(_close)
	col.add_child(back)


func _clear_body() -> void:
	for child in _body.get_children():
		child.queue_free()


func _ask() -> void:
	_clear_body()
	_progress.text = "Question %d of %d" % [_index + 1, _pool.size()]

	var entry: Dictionary = _pool[_index]
	var q: Dictionary = entry["q"]

	_body.add_child(UIKit.label(String(entry["subject"]), 20, UIKit.ACCENT))
	var prompt := UIKit.label(String(q["q"]), 30)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(prompt)

	var options: Array = q["options"]
	# Shuffle presentation so the answer is never in a predictable slot.
	var order: Array = []
	for i in options.size():
		order.append(i)
	order.shuffle()

	for slot: int in order:
		var btn := UIKit.button(String(options[slot]), 26)
		btn.pressed.connect(func() -> void: _answer(slot == int(q["answer"]), q))
		_body.add_child(btn)


func _answer(is_right: bool, q: Dictionary) -> void:
	_clear_body()
	if is_right:
		_correct += 1
		GameState.add_ether(REWARD_ETHER)
		AudioManager.play("upgrade")
		SettingsManager.vibrate(45)
		var head := UIKit.label("Correct!  +%d ether" % REWARD_ETHER, 34, UIKit.GOOD)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(head)
	else:
		AudioManager.play("click", -4.0, 0.7)
		var head := UIKit.label("Not quite!", 34, UIKit.ACCENT)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(head)
		var right := UIKit.label(
			"Answer: %s" % String(q["options"][int(q["answer"])]), 26)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(right)

	# The explanation is the actual teaching, so it shows either way.
	var note := String(q.get("note", ""))
	if note != "":
		var panel := UIKit.panel(Color(0.18, 0.16, 0.24, 1.0), 14)
		_body.add_child(panel)
		var note_label := UIKit.label(note, 22, UIKit.TEXT)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(note_label)

	var next := UIKit.button(
		"NEXT" if _index + 1 < _pool.size() else "FINISH", 30, true)
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
	var head := UIKit.label("%d / %d correct" % [_correct, _pool.size()], 40, UIKit.GOOD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(head)

	# Effort-focused praise, not ability praise ("you are so clever" teaches
	# kids to avoid hard things; "you worked that out" does the opposite).
	var msg := "Great digging. Come back after you find something new!"
	if _correct == _pool.size():
		msg = "Every single one. You have really been paying attention down there!"
	elif _correct == 0:
		msg = "Tricky set! Read the cards in your Codex and try again any time."
	var body := UIKit.label(msg, 24, UIKit.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(body)

	var back := UIKit.button("BACK TO THE SURFACE", 28, true)
	back.pressed.connect(_close)
	_body.add_child(back)
	GameState.unlock_achievement("log_keeper")
	if _correct == _pool.size():
		GameState.unlock_achievement("quiz_ace")


func _close() -> void:
	closed.emit()
	queue_free()
