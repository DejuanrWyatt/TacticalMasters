extends Node
## Player settings, saved to SAVE_PATH: audio volumes, UI scale, fullscreen,
## camera speed and colorblind-friendly team colors. Key bindings live in
## Keybinds. Change a value with set_value() so it's applied and saved.

signal changed

const SAVE_PATH := "user://settings.cfg"
const KEYS := ["master_volume", "music_volume", "sfx_volume", "ui_scale", "fullscreen", "camera_speed", "colorblind"]
## Team colors: normal blue/red, or blue/orange for red-green colorblindness.
const TEAM_COLORS := [Color(0.25, 0.5, 0.9), Color(0.85, 0.25, 0.22)]
const COLORBLIND_COLORS := [Color(0.25, 0.5, 0.9), Color(0.95, 0.6, 0.1)]

var master_volume := 0.8
var music_volume := 0.5
var sfx_volume := 0.8
var ui_scale := 1.0
var fullscreen := false
var camera_speed := 1.0
var colorblind := false


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_load()
	apply()


func team_colors() -> Array:
	return COLORBLIND_COLORS if colorblind else TEAM_COLORS


func set_value(key: String, value) -> void:
	set(key, value)
	apply()
	_save()
	changed.emit()


func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	get_tree().root.content_scale_factor = ui_scale
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


static func _set_bus_volume(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in KEYS:
		cfg.set_value("settings", key, get(key))
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in KEYS:
		var value = cfg.get_value("settings", key, get(key))
		if typeof(value) == typeof(get(key)):
			set(key, value)
