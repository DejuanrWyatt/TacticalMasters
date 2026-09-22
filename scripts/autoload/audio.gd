extends Node
## Sound effects and music (CC0; see assets/audio/CREDITS.txt).
##   Audio.play("click")                 a 2D sound (UI)
##   Audio.play_at("hit_metal", pos)     a positional sound in the 3D world
##   Audio.play_music(Audio.BATTLE_MUSIC) / Audio.stop_music()
## A name picks a random variant when numbered files exist (hit_metal_1,
## hit_metal_2, ... for "hit_metal"). Every button in the game clicks.
## Volumes come from the Settings autoload (Master / Music / SFX buses).

const SFX_DIR := "res://assets/audio/sfx/"
const BATTLE_MUSIC := "res://assets/audio/music/battle_theme.mp3"
const MAX_2D_VOICES := 8

## When false (e.g. fast-forwarded replays), sound effects are skipped.
var sfx_enabled := true
var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load_sounds()
	print("Audio: %d sounds loaded" % _streams.size())
	for i in MAX_2D_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	# Every button anywhere gets a click.
	get_tree().node_added.connect(_on_node_added)


## Groups sound files by name, with numbered files as variants of one sound.
func _load_sounds() -> void:
	for file in _list_files(SFX_DIR):
		if not file.ends_with(".ogg"):
			continue
		var base := file.get_basename()
		var parts := base.rsplit("_", true, 1)
		var sound_name := parts[0] if parts.size() == 2 and parts[1].is_valid_int() else base
		if not _streams.has(sound_name):
			_streams[sound_name] = []
		_streams[sound_name].append(load(SFX_DIR + file))


## Files in a folder, also in exported builds (where they're import remaps).
static func _list_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in ResourceLoader.list_directory(dir):
		out.append(file)
	return out


func has_sound(name: String) -> bool:
	return _streams.has(name)


func _pick(name: String) -> AudioStream:
	var list: Array = _streams.get(name, [])
	return list[_rng.randi_range(0, list.size() - 1)] if not list.is_empty() else null


func play(name: String, volume_db := 0.0) -> void:
	if not sfx_enabled:
		return
	var stream := _pick(name)
	if stream == null:
		return
	# Use a free voice, or cut off the oldest one.
	var voice: AudioStreamPlayer = _voices[0]
	for v in _voices:
		if not v.playing:
			voice = v
			break
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = _rng.randf_range(0.95, 1.05)
	voice.play()


func play_at(name: String, position: Vector3, volume_db := 0.0) -> void:
	if not sfx_enabled:
		return
	var stream := _pick(name)
	var scene := get_tree().current_scene
	if stream == null or scene == null or not scene is Node3D:
		play(name, volume_db)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.unit_size = 12.0
	p.max_distance = 90.0
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	scene.add_child(p)
	p.global_position = position
	p.finished.connect(p.queue_free)
	p.play()


func play_music(path: String) -> void:
	if _music.playing and _music.stream != null and _music.stream.resource_path == path:
		return
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.volume_db = -6.0
	_music.play()


func stop_music() -> void:
	_music.stop()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("click", -6.0))
