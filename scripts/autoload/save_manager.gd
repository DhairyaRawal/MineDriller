extends Node
## SaveManager: versioned JSON persistence with corruption handling and a
## migration hook. Saves are debounced (request_save) so rapid events don't
## thrash storage, and forced on app pause/quit for Android lifecycle safety.

const SAVE_PATH := "user://savegame.json"
const BACKUP_PATH := "user://savegame.bak.json"
const SAVE_VERSION := 2  # v2 adds world_diff/last_position/cargo persistence

## Emitted right before a write, so whoever holds the live MineWorld (game.gd)
## can pull a fresh GameState.world_diff without SaveManager needing a direct
## reference to the world -- keeps this autoload gameplay-agnostic.
signal before_save

var _dirty := false
var _debounce := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()


func _process(delta: float) -> void:
	if _dirty:
		_debounce += delta
		if _debounce >= 1.0:
			save_now()


func _notification(what: int) -> void:
	# Android lifecycle: persist whenever the app is backgrounded or closed.
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_now()
		SettingsManager.save_settings()


func request_save() -> void:
	_dirty = true


func save_now() -> void:
	_dirty = false
	_debounce = 0.0
	before_save.emit()
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"state": GameState.to_dict(),
	}
	# Keep the previous good save as a backup before overwriting.
	if FileAccess.file_exists(SAVE_PATH):
		var old := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if old != null:
			var bak := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if bak != null:
				bak.store_string(old.get_as_text())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: cannot write save file")
		return
	f.store_string(JSON.stringify(payload))


func load_game() -> void:
	var payload := _read_valid(SAVE_PATH)
	if payload.is_empty():
		payload = _read_valid(BACKUP_PATH)
		if not payload.is_empty():
			push_warning("SaveManager: main save corrupt, restored from backup")
	if payload.is_empty():
		return
	var migrated := _migrate(payload)
	GameState.from_dict(migrated.get("state", {}))


func wipe() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))


func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.has("state") and parsed.has("version"):
		return parsed
	return {}


## Migration hook: bump SAVE_VERSION and add steps here when the save format
## changes; each step upgrades one version at a time.
func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 1))
	while version < SAVE_VERSION:
		match version:
			_:
				pass
		version += 1
	payload["version"] = SAVE_VERSION
	return payload
