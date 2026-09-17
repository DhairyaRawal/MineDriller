class_name SettingsPanel
extends VBoxContainer
## SettingsPanel: reusable settings block (volume sliders, haptics, screen
## shake, left-handed controls). Embedded by both the main menu and the
## pause menu; persists via SettingsManager on every change.


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_slider_row("Music", SettingsManager.music_volume,
		func(v: float) -> void:
			SettingsManager.music_volume = v
			SettingsManager.apply_audio()
			SettingsManager.save_settings()))
	add_child(_slider_row("Sound FX", SettingsManager.sfx_volume,
		func(v: float) -> void:
			SettingsManager.sfx_volume = v
			SettingsManager.apply_audio()
			SettingsManager.save_settings()))
	add_child(_toggle_row("Haptics", SettingsManager.haptics_enabled,
		func(on: bool) -> void:
			SettingsManager.haptics_enabled = on
			SettingsManager.save_settings()
			if on:
				SettingsManager.vibrate(40)))
	add_child(_toggle_row("Screen shake", SettingsManager.screen_shake_enabled,
		func(on: bool) -> void:
			SettingsManager.screen_shake_enabled = on
			SettingsManager.save_settings()))
	# No left-handed toggle on the web build: it existed to mirror the on-screen
	# thumb clusters, and input is keyboard/mouse now. The setting itself is
	# still persisted, so it survives if a touch build is ever revived.


func _slider_row(label_text: String, initial: float, on_change: Callable) -> Control:
	var row := UIKit.hbox(16)
	var lbl := UIKit.label(label_text, 17)
	lbl.custom_minimum_size = Vector2(130, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(200, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	return row


func _toggle_row(label_text: String, initial: bool, on_change: Callable) -> Control:
	var row := UIKit.hbox(16)
	var lbl := UIKit.label(label_text, 17)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var check := CheckButton.new()
	check.button_pressed = initial
	check.custom_minimum_size = Vector2(60, 32)
	check.toggled.connect(on_change)
	row.add_child(check)
	return row
