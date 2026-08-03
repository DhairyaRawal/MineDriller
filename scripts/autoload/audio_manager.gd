extends Node
## AudioManager: creates the Music/SFX buses in code, preloads every stream,
## and plays sounds through a small pool of players (no allocations during
## gameplay). Looping streams (drill, jet, music) get dedicated players.

const SFX_POOL_SIZE := 8

var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _music: AudioStreamPlayer
var _drill: AudioStreamPlayer
var _jet: AudioStreamPlayer
var _ambient_layers: Array[AudioStreamPlayer] = []  # one per layer for depth-specific ambience
var _current_ambient_layer := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	_load_streams()
	_make_players()
	SettingsManager.apply_audio()
	Events.depth_changed.connect(func(_row: int, _km: float, layer_id: int) -> void:
		set_ambient_layer(layer_id))


func _make_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _load_streams() -> void:
	var names := ["click", "pickup", "sell", "upgrade", "explosion", "hurt",
		"warning", "splash", "bust", "drill_loop", "jet_loop", "music_loop",
		"impact_rock", "impact_ore", "enemy_alert", "laser_drill", "layer_transition"]
	for n: String in names:
		var stream: AudioStream = load("res://assets/audio/%s.wav" % n)
		if stream == null:
			push_warning("AudioManager: missing stream %s" % n)
			continue
		if n.ends_with("_loop") and stream is AudioStreamWAV:
			stream = stream.duplicate()
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / 2  # 16-bit mono: 2 bytes per frame
		_sfx[n] = stream

	# Load layer-specific ambient audio
	for layer in range(1, 6):
		var ambient_name := "ambient_layer%d" % layer
		var stream: AudioStream = load("res://assets/audio/%s.wav" % ambient_name)
		if stream == null:
			push_warning("AudioManager: missing stream %s" % ambient_name)
			continue
		if stream is AudioStreamWAV:
			stream = stream.duplicate()
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / 2
		_sfx[ambient_name] = stream


func _make_players() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_drill = AudioStreamPlayer.new()
	_drill.bus = "SFX"
	_drill.volume_db = -6.0
	if _sfx.has("drill_loop"):
		_drill.stream = _sfx["drill_loop"]
	add_child(_drill)
	_jet = AudioStreamPlayer.new()
	_jet.bus = "SFX"
	_jet.volume_db = -10.0
	if _sfx.has("jet_loop"):
		_jet.stream = _sfx["jet_loop"]
	add_child(_jet)

	# Create layer-specific ambient players (subtle background atmosphere)
	for layer in range(1, 6):
		var ambient_player := AudioStreamPlayer.new()
		ambient_player.bus = "Music"
		ambient_player.volume_db = -18.0  # very quiet background layer
		var ambient_name := "ambient_layer%d" % layer
		if _sfx.has(ambient_name):
			ambient_player.stream = _sfx[ambient_name]
		add_child(ambient_player)
		_ambient_layers.append(ambient_player)


func play(sfx_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sfx.has(sfx_name):
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % SFX_POOL_SIZE
	p.stream = _sfx[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_music() -> void:
	if _music.playing or not _sfx.has("music_loop"):
		return
	_music.stream = _sfx["music_loop"]
	_music.play()


func stop_music() -> void:
	_music.stop()


func set_ambient_layer(layer_id: int) -> void:
	"""Switch to layer-specific ambient audio."""
	if layer_id < 1 or layer_id > 5:
		return
	if _current_ambient_layer == layer_id:
		return
	_current_ambient_layer = layer_id
	# Fade out all layers except the current one
	for i in range(_ambient_layers.size()):
		if i == layer_id - 1:
			if not _ambient_layers[i].playing:
				_ambient_layers[i].play()
		else:
			_ambient_layers[i].stop()


func set_drilling(active: bool) -> void:
	if active and not _drill.playing:
		_drill.play()
	elif not active and _drill.playing:
		_drill.stop()


func set_jet(active: bool) -> void:
	if active and not _jet.playing:
		_jet.play()
	elif not active and _jet.playing:
		_jet.stop()


func stop_loops() -> void:
	set_drilling(false)
	set_jet(false)
