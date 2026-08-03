class_name PauseMenu
extends CanvasLayer
## PauseMenu: full-screen pause overlay with inline settings and a
## quit-to-menu path. Runs while the tree is paused.

signal resumed
signal quit_to_menu


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	var content := UIKit.modal(self, "PAUSED")
	content.add_child(SettingsPanel.new())

	var resume := UIKit.button("RESUME", 32, true)
	resume.pressed.connect(_on_resume)
	content.add_child(resume)

	var quit := UIKit.button("QUIT TO MENU", 26)
	quit.pressed.connect(func() -> void:
		get_tree().paused = false
		quit_to_menu.emit())
	content.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_resume()


func _on_resume() -> void:
	get_tree().paused = false
	resumed.emit()
	queue_free()
