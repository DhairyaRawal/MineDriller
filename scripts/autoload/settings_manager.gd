extends Node
## SettingsManager: player settings (audio volumes, haptics, screen shake)
## persisted separately from the save game, plus programmatic input map setup
## so the project needs no hand-edited input configuration.

const SETTINGS_PATH := "user://settings.json"

var music_volume := 0.8
var sfx_volume := 1.0
var haptics_enabled := true
var screen_shake_enabled := true
var left_handed := false


func _ready() -> void:
	_setup_input_actions()
	load_settings()


func _setup_input_actions() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP, KEY_SPACE],
		"move_down": [KEY_S, KEY_DOWN],
		"pause": [KEY_ESCAPE, KEY_P],
		"interact": [KEY_E, KEY_F],
		"fire_rocket": [KEY_R, KEY_Q],
		"show_tip": [KEY_H],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)


func vibrate(ms: int) -> void:
	if haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func apply_audio() -> void:
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(maxf(music_volume, 0.0001)))
		AudioServer.set_bus_mute(music_idx, music_volume <= 0.001)
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_volume, 0.0001)))
		AudioServer.set_bus_mute(sfx_idx, sfx_volume <= 0.001)


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write settings")
		return
	f.store_string(JSON.stringify({
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"haptics_enabled": haptics_enabled,
		"screen_shake_enabled": screen_shake_enabled,
		"left_handed": left_handed,
	}))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		music_volume = float(parsed.get("music_volume", music_volume))
		sfx_volume = float(parsed.get("sfx_volume", sfx_volume))
		haptics_enabled = bool(parsed.get("haptics_enabled", haptics_enabled))
		screen_shake_enabled = bool(parsed.get("screen_shake_enabled", screen_shake_enabled))
		left_handed = bool(parsed.get("left_handed", left_handed))
