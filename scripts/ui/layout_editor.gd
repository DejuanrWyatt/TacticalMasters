extends Control
## Lets the player rearrange the battle's panels: turn on Edit layout (the
## game menu), drag anything with a handle over it, and it stays there for
## every battle after (user://layout.cfg).
##
## Each panel keeps its own anchors: what is saved is how far it has been
## nudged from where it normally sits, so it still follows the edge or corner
## it is anchored to when the window changes size.

signal changed

const SAVE_PATH := "user://layout.cfg"
const HANDLE_COLOR := Color(0.25, 0.65, 1.0, 0.18)
const HANDLE_BORDER := Color(0.45, 0.8, 1.0, 0.9)

## id -> {"control": Control, "label": String, "handle": Panel, "moved": Vector2}
var _panels := {}
var _editing := false
## While dragging: the panel's id and where the mouse took hold of it.
var _dragging := ""
var _grab := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_load()


## Adds a panel the player may move. `label` is what its handle says.
func register(id: String, control: Control, label: String) -> void:
	if control == null or _panels.has(id):
		return
	var handle := Panel.new()
	handle.visible = false
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	var style := StyleBoxFlat.new()
	style.bg_color = HANDLE_COLOR
	style.border_color = HANDLE_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	handle.add_theme_stylebox_override("panel", style)
	var name_label := Label.new()
	name_label.text = label
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", HANDLE_BORDER)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.add_child(name_label)
	handle.gui_input.connect(_on_handle_input.bind(id))
	add_child(handle)
	_panels[id] = {"control": control, "label": label, "handle": handle, "moved": Vector2.ZERO}
	# Whatever was saved for it before this battle.
	var saved: Vector2 = _saved.get(id, Vector2.ZERO)
	if saved != Vector2.ZERO:
		_nudge(id, saved)


## Turns the handles on or off.
func set_editing(on: bool) -> void:
	_editing = on
	set_process(on)
	for id in _panels:
		(_panels[id].handle as Panel).visible = on
	if on:
		_follow_panels()


func is_editing() -> bool:
	return _editing


## Puts every panel back where the game itself would have it, and forgets
## anything else that was arranged (the order of the turn cards).
func reset() -> void:
	for id in _panels:
		_nudge(id, -_panels[id].moved)
	_saved.clear()
	_extra.clear()
	_save()
	changed.emit()


## Anything else about the layout worth keeping, by name: the turn cards use
## it for the order the player put them in.
func set_extra(key: String, value) -> void:
	_extra[key] = value
	_save()


func get_extra(key: String, fallback = null):
	return _extra.get(key, fallback)


func _process(_delta: float) -> void:
	_follow_panels()


## Keeps each handle over the panel it belongs to.
func _follow_panels() -> void:
	for id in _panels:
		var entry: Dictionary = _panels[id]
		var control: Control = entry.control
		var handle: Panel = entry.handle
		if not is_instance_valid(control) or not control.is_visible_in_tree():
			handle.visible = false
			continue
		handle.visible = _editing
		handle.global_position = control.global_position
		handle.size = control.size


## Moves a panel by this much, keeping its anchors, and remembers it.
func _nudge(id: String, by: Vector2) -> void:
	var entry: Dictionary = _panels[id]
	var control: Control = entry.control
	control.offset_left += by.x
	control.offset_right += by.x
	control.offset_top += by.y
	control.offset_bottom += by.y
	entry.moved += by
	_saved[id] = entry.moved


func _on_handle_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = id
			_grab = event.global_position
		elif _dragging == id:
			_dragging = ""
			_save()
			changed.emit()
	elif event is InputEventMouseMotion and _dragging == id:
		_nudge(id, event.global_position - _grab)
		_grab = event.global_position


# --- Saving -----------------------------------------------------------------

var _saved := {}
var _extra := {}


func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _saved:
		if _saved[id] != Vector2.ZERO:
			cfg.set_value("panels", id, _saved[id])
	for key in _extra:
		cfg.set_value("extra", key, _extra[key])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section("panels"):
		if cfg.has_section("extra"):
			for key in cfg.get_section_keys("extra"):
				_extra[key] = cfg.get_value("extra", key)
		return
	for id in cfg.get_section_keys("panels"):
		var value = cfg.get_value("panels", id, Vector2.ZERO)
		if value is Vector2:
			_saved[id] = value
	if cfg.has_section("extra"):
		for key in cfg.get_section_keys("extra"):
			_extra[key] = cfg.get_value("extra", key)
