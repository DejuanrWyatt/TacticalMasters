extends Node
## Rebindable keyboard controls. Every action is registered in the InputMap
## as "tm_<id>" (for example "tm_move"), so game code checks
## `event.is_action_pressed("tm_move")` instead of specific keys.
##
## An action can have several keys. The first one is shown in the UI and is
## the one the Options menu changes. Assigning a key that another action
## already uses swaps the two, so no action is ever left without a key.
## Bindings are saved to SAVE_PATH.

signal changed

const SAVE_PATH := "user://keybinds.cfg"

## [id, label, default keys]
const ACTIONS := [
	["move", "Move", [KEY_SPACE]],
	["sprint", "Sprint (further, no ability)", [KEY_SHIFT]],
	["ability_1", "Ability 1", [KEY_1]],
	["ability_2", "Ability 2", [KEY_2]],
	["ability_3", "Ability 3", [KEY_3]],
	["ability_4", "Ability 4 (Ultimate)", [KEY_4]],
	["end_turn", "End turn", [KEY_ENTER, KEY_KP_ENTER]],
	["cancel", "Cancel", [KEY_ESCAPE]],
	["next_unit", "Next ready unit", [KEY_TAB]],
	["pause", "Pause", [KEY_P]],
	["unit_guide", "Unit Guide", [KEY_U]],
	["chat", "Chat (online)", [KEY_T]],
	["log", "Show / hide combat log", [KEY_L]],
	["center_camera", "Center camera on unit", [KEY_C]],
	["cam_forward", "Camera forward", [KEY_W, KEY_UP]],
	["cam_back", "Camera back", [KEY_S, KEY_DOWN]],
	["cam_left", "Camera left", [KEY_A, KEY_LEFT]],
	["cam_right", "Camera right", [KEY_D, KEY_RIGHT]],
	["cam_up", "Camera up", [KEY_R]],
	["cam_down", "Camera down", [KEY_F]],
	["cam_rotate_left", "Rotate camera left", [KEY_Q]],
	["cam_rotate_right", "Rotate camera right", [KEY_E]],
]

## action id -> Array of keycodes
var _keys := {}


func _ready() -> void:
	_set_defaults()
	_load()
	_apply()


func action(id: String) -> StringName:
	return StringName("tm_" + id)


func keys(id: String) -> Array:
	return _keys[id]


## Short display name of the action's main key, e.g. "Space" or "1".
func key_name(id: String) -> String:
	return key_label(_keys[id][0])


static func key_label(keycode: int) -> String:
	match keycode:
		KEY_ESCAPE:
			return "Esc"
		KEY_ENTER:
			return "Enter"
	return OS.get_keycode_string(keycode)


## Makes `keycode` the main key of `id`. If another action uses that key, it
## gets this action's old main key instead (a swap).
func rebind(id: String, keycode: int) -> void:
	var old: int = _keys[id][0]
	if old == keycode:
		return
	for other in _keys:
		if other == id:
			continue
		var i: int = _keys[other].find(keycode)
		if i != -1:
			_keys[other][i] = old
			_keys[other] = _unique(_keys[other])
	_keys[id][0] = keycode
	_keys[id] = _unique(_keys[id])
	_apply()
	_save()
	changed.emit()


func reset_defaults() -> void:
	_set_defaults()
	_apply()
	_save()
	changed.emit()


func _set_defaults() -> void:
	_keys.clear()
	for entry in ACTIONS:
		_keys[entry[0]] = (entry[2] as Array).duplicate()


static func _unique(list: Array) -> Array:
	var out := []
	for k in list:
		if not out.has(k):
			out.append(k)
	return out


func _apply() -> void:
	for id in _keys:
		var name := action(id)
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for keycode in _keys[id]:
			var ev := InputEventKey.new()
			ev.keycode = keycode
			InputMap.action_add_event(name, ev)


func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _keys:
		cfg.set_value("keys", id, _keys[id])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in _keys:
		# Actions added in newer versions aren't in older save files: keep their defaults.
		if not cfg.has_section_key("keys", id):
			continue
		var saved = cfg.get_value("keys", id)
		if saved is Array and not saved.is_empty():
			_keys[id] = saved
