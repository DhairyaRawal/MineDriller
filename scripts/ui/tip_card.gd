class_name TipCard
extends CanvasLayer
## TipCard: one contextual tip, opened by clicking a floating '?' or pressing
## H. Pauses the tree so the tip can be read without taking heat or a hit --
## which matters, because the most useful tips appear right next to danger.

signal dismissed

var _tip_id: String
var _was_paused := false


func _init(tip_id: String) -> void:
	_tip_id = tip_id


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tip: Dictionary = Balance.tips.get(_tip_id, {})
	var content := UIKit.modal(self, String(tip.get("title", "Tip")))

	var category := UIKit.label(String(tip.get("category", "")).to_upper(), 14,
		UIKit.BAD if tip.get("category", "") == "Dangers" else UIKit.TEXT_DIM)
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(category)

	var body := UIKit.wrapped(String(tip.get("body", "")), 18)
	body.custom_minimum_size = Vector2(480, 0)
	content.add_child(body)

	# TipCard only ever opens from a floating '?', which retires once read.
	var note := UIKit.label(
		"You won't see this ? again. Re-read it any time from the pause menu's GUIDE.",
		13, UIKit.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(480, 0)
	content.add_child(note)

	var ok := UIKit.action_button("GOT IT")
	ok.pressed.connect(dismiss)
	content.add_child(ok)

	# Remember rather than assume: restoring blindly to "unpaused" would break
	# anything that had the tree paused before this card opened.
	_was_paused = get_tree().paused
	get_tree().paused = true


func dismiss() -> void:
	get_tree().paused = _was_paused
	dismissed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("show_tip") \
			or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		dismiss()
