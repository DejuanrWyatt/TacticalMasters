extends Control
## Options screen. "Game": volumes, UI scale, fullscreen, camera speed and
## colorblind team colors (saved by the Settings autoload). "Controls":
## rebind every keyboard control; click an action's key, then press the new
## key (Esc cancels). A key that another action already uses is swapped
## between the two. Used from the main menu and in battle.

signal closed

var _buttons := {}
## Action id waiting for a key press, or "".
var _capturing := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://scripts/ui/ui_theme.gd").build()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var reset := _button("Reset to defaults", _on_reset)
	header.add_child(reset)
	var close := _button("Close", close_menu)
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	content.add_child(_section("Game"))
	var game := GridContainer.new()
	game.columns = 4
	game.add_theme_constant_override("h_separation", 24)
	game.add_theme_constant_override("v_separation", 8)
	content.add_child(game)
	_slider(game, "Master volume", "master_volume", 0.0, 1.0)
	_slider(game, "Music volume", "music_volume", 0.0, 1.0)
	_slider(game, "Sound effects volume", "sfx_volume", 0.0, 1.0)
	_slider(game, "Camera speed", "camera_speed", 0.5, 2.0)
	_choice(game, "UI scale", "ui_scale", [0.9, 1.0, 1.15, 1.3], ["90%", "100%", "115%", "130%"])
	_toggle(game, "Fullscreen", "fullscreen")
	_toggle(game, "Colorblind team colors (blue / orange)", "colorblind")
	_toggle(game, "Turn order as fixed squares instead of sliding bars", "turn_icons")

	content.add_child(_section("Controls"))
	var help := Label.new()
	help.text = "Click a key, then press the new key (Esc cancels). A key already used by another action is swapped between the two."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.7)
	content.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for entry in Keybinds.ACTIONS:
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size.x = 210
		grid.add_child(label)
		var b := _button("", _start_capture.bind(entry[0]))
		b.custom_minimum_size.x = 200
		grid.add_child(b)
		_buttons[entry[0]] = b

	var mouse := Label.new()
	mouse.text = "Mouse (fixed): left-click select / move / target · right-drag rotate and tilt camera · middle-drag pan · wheel zoom"
	mouse.modulate = Color(1, 1, 1, 0.6)
	column.add_child(mouse)

	Keybinds.changed.connect(_refresh)
	_refresh()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	return l


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 210
	parent.add_child(l)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float) -> void:
	_label(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = Settings.get(key)
	s.custom_minimum_size = Vector2(200, 32)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float): Settings.set_value(key, v))
	parent.add_child(s)


func _toggle(parent: Control, text: String, key: String) -> void:
	_label(parent, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get(key)
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool): Settings.set_value(key, on))
	parent.add_child(c)


func _choice(parent: Control, text: String, key: String, values: Array, labels: Array) -> void:
	_label(parent, text)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for l in labels:
		o.add_item(l)
	var current = Settings.get(key)
	var best := 0
	for i in values.size():
		if absf(values[i] - current) < absf(values[best] - current):
			best = i
	o.select(best)
	o.item_selected.connect(func(i: int): Settings.set_value(key, values[i]))
	parent.add_child(o)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(action)
	return b


func _refresh() -> void:
	for id in _buttons:
		var names: Array[String] = []
		for k in Keybinds.keys(id):
			names.append(Keybinds.key_label(k))
		var b: Button = _buttons[id]
		b.text = "Press a key..." if id == _capturing else " / ".join(names)
		b.modulate = Color(1, 0.85, 0.4) if id == _capturing else Color.WHITE


func _start_capture(id: String) -> void:
	_capturing = id
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _capturing != "":
			if event.keycode != KEY_ESCAPE or _capturing == "cancel":
				Keybinds.rebind(_capturing, event.keycode)
			_capturing = ""
			_refresh()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close_menu()
			get_viewport().set_input_as_handled()


func _on_reset() -> void:
	_capturing = ""
	Keybinds.reset_defaults()


func close_menu() -> void:
	_capturing = ""
	visible = false
	closed.emit()
