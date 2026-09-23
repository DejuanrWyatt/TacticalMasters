extends PanelContainer
## Combat log window: every battle message, newest at the bottom. Drag the
## title bar to move it, drag the corner grip to resize it, "–" collapses it
## to its title bar and "×" hides it (the Log button or L shows it again).
## The cog opens its options: text size, background opacity, and the color of
## each kind of message (damage, healing, buffs, and so on). Each line carries
## the icon of the unit it is about.
## Where it is, its size, whether it's shown and its options are saved
## between battles.

signal visibility_toggled(shown: bool)

const SAVE_PATH := "user://log_window.cfg"
const MIN_SIZE := Vector2(220, 90)
const DEFAULT_RECT := Rect2(12, 104, 380, 170)
const MAX_LINES := 300
const TITLE_HEIGHT := 24.0
const TEXT := Color(0.92, 0.94, 1.0)
const DEFAULT_FONT_SIZE := 12
const FONT_SIZES := Vector2i(8, 28)
const DEFAULT_OPACITY := 0.72
## How tall the window grows to when its options are opened.
const OPTIONS_HEIGHT := 330.0
const DIM := Color(0.92, 0.94, 1.0, 0.55)

## What each kind of message is called in the options, and the color it is
## written in until the player picks another.
const KIND_NAMES := {
	"damage": "Damage", "heal": "Healing", "buff": "Buffs", "debuff": "Debuffs",
	"status": "Statuses", "ko": "Knock-outs", "cast": "Casting",
	"ability": "Ability names", "filler": "Plain text",
}
const DEFAULT_KIND_COLORS := {
	"damage": Color(1.0, 0.42, 0.36),
	"heal": Color(0.45, 0.95, 0.5),
	"buff": Color(0.45, 0.95, 0.5),
	"debuff": Color(0.85, 0.55, 1.0),
	"status": Color(1.0, 0.85, 0.35),
	"ko": Color(1.0, 0.3, 0.25),
	"cast": Color(0.75, 0.5, 1.0),
	"ability": Color(0.95, 0.9, 0.7),
	"filler": Color(0.66, 0.69, 0.75),
	"move": Color(0.66, 0.69, 0.75),
	"system": Color(0.66, 0.69, 0.75),
}

var _scroll: ScrollContainer
var _lines: VBoxContainer
var _body: Control
var _collapse: Button
var _collapsed := false
var _full_height := DEFAULT_RECT.size.y
## "move" or "resize" while dragging, else "".
var _dragging := ""
var _drag_from := Vector2.ZERO
var _rect_from := Rect2()
## Options (the cog): text size, text color, background opacity.
var font_size := DEFAULT_FONT_SIZE
var text_color := TEXT
var opacity := DEFAULT_OPACITY
## The color each kind of message is written in.
var kind_colors := DEFAULT_KIND_COLORS.duplicate()
var _kind_buttons := {}
var _style: StyleBoxFlat
var _options: HFlowContainer
var _size_box: SpinBox
var _color_button: ColorPickerButton
var _opacity_slider: HSlider


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.03, 0.04, 0.07, DEFAULT_OPACITY)
	_style.border_color = Color(1, 1, 1, 0.08)
	_style.set_border_width_all(1)
	_style.set_corner_radius_all(8)
	_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	# Title bar: drag to move.
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = TITLE_HEIGHT - 6
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	column.add_child(bar)
	var title := Label.new()
	title.text = "Combat Log"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(title)
	var cog := _title_button(bar, "", "Log options: text size, color and background", toggle_options)
	cog.icon = load("res://assets/icons/cog.svg")
	cog.add_theme_constant_override("icon_max_width", 14)
	cog.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cog.custom_minimum_size = Vector2(22, 18)
	_collapse = _title_button(bar, "–", "Collapse", toggle_collapsed)
	_title_button(bar, "×", "Hide (L or the Log button shows it again)", hide_log)
	_build_options(column)

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 1)
	_scroll.add_child(_lines)

	# Corner grip: drag to resize.
	var grip := Label.new()
	grip.text = "◢"
	grip.add_theme_font_size_override("font_size", 12)
	grip.add_theme_color_override("font_color", DIM)
	grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.tooltip_text = "Drag to resize"
	grip.gui_input.connect(_on_grip_input)
	_body.add_child(grip)

	_load()
	get_viewport().size_changed.connect(_keep_on_screen)


## Adds a message at the bottom (keeps the view at the bottom unless the
## player scrolled up to read older ones).
func add_message(entry) -> void:
	var text: String = entry.get("text", "") if entry is Dictionary else str(entry)
	var kind: String = entry.get("kind", "system") if entry is Dictionary else "system"
	var parts: Array = entry.get("parts", []) if entry is Dictionary else []
	var at_bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y) - 4
	# A line is laid out as its pieces: a unit shows as its icon (its name is
	# in the tooltip) and each piece of text takes the color of what it says.
	# Pieces flow onto the next line when the window is narrow.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 0)
	row.add_theme_constant_override("v_separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("kind", kind)
	if parts.is_empty():
		parts = [{"text": text, "kind": kind}]
	for part in parts:
		if part.has("unit"):
			row.add_child(_unit_piece(part))
		else:
			_add_words(row, str(part.get("text", "")), str(part.get("kind", kind)))
	_lines.add_child(row)
	while _lines.get_child_count() > MAX_LINES:
		var oldest := _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()
	# Older lines fade a little so the newest stand out.
	var count := _lines.get_child_count()
	for i in count:
		(_lines.get_child(i) as Control).modulate.a = 1.0 if i >= count - 3 else 0.7
	if at_bottom:
		_scroll_to_bottom.call_deferred()


## A unit in a line: its icon, with its name to hover over.
func _unit_piece(part: Dictionary) -> Control:
	var who := TextureRect.new()
	who.name = "Unit"
	who.custom_minimum_size = Vector2(font_size + 4, font_size + 4)
	who.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	who.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.tooltip_text = str(part.get("name", ""))
	who.mouse_filter = Control.MOUSE_FILTER_STOP
	var path: String = str(part.get("icon", ""))
	if path != "" and ResourceLoader.exists(path):
		who.texture = load(path)
	else:
		# Nothing to show it with (a unit out of sight): its name does instead.
		return _text_piece(str(part.get("name", "?")), "filler")
	return who


## One word of a line, in the color of what that part of the line says.
func _text_piece(text: String, kind: String) -> Label:
	var piece := Label.new()
	piece.name = "Text"
	piece.text = text
	piece.set_meta("kind", kind)
	piece.add_theme_font_size_override("font_size", font_size)
	piece.add_theme_color_override("font_color", color_for(kind))
	return piece


## Adds a piece of text to a line as one label per word, so the line can wrap
## between words while every word keeps its own color.
func _add_words(row: Control, text: String, kind: String) -> void:
	if text == "":
		return
	var words := text.split(" ", true)
	for i in words.size():
		var word: String = words[i] if i == 0 else " " + words[i]
		if word != "":
			row.add_child(_text_piece(word, kind))


## The options row (shown by the cog): text size, text color, opacity.
func _build_options(column: VBoxContainer) -> void:
	_options = HFlowContainer.new()
	_options.visible = false
	_options.add_theme_constant_override("h_separation", 6)
	_options.add_theme_constant_override("v_separation", 4)
	column.add_child(_options)
	_option_label("Size")
	_size_box = SpinBox.new()
	_size_box.min_value = FONT_SIZES.x
	_size_box.max_value = FONT_SIZES.y
	_size_box.step = 1
	_size_box.tooltip_text = "Text size (%d-%d)" % [FONT_SIZES.x, FONT_SIZES.y]
	_size_box.value_changed.connect(func(v: float): set_options(roundi(v), text_color, opacity))
	_options.add_child(_size_box)
	_option_label("Color")
	_color_button = ColorPickerButton.new()
	_color_button.edit_alpha = false
	_color_button.custom_minimum_size = Vector2(36, 24)
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.tooltip_text = "Text color"
	_color_button.color_changed.connect(func(c: Color): set_options(font_size, c, opacity))
	_options.add_child(_color_button)
	_option_label("Background")
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.custom_minimum_size = Vector2(80, 24)
	_opacity_slider.focus_mode = Control.FOCUS_NONE
	_opacity_slider.tooltip_text = "Background opacity"
	_opacity_slider.value_changed.connect(func(v: float): set_options(font_size, text_color, v))
	_options.add_child(_opacity_slider)
	# One picker per kind of message, so damage, healing and the rest can be
	# told apart at a glance in whatever colors suit.
	for kind in KIND_NAMES:
		_option_label(KIND_NAMES[kind])
		var picker := ColorPickerButton.new()
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(30, 22)
		picker.focus_mode = Control.FOCUS_NONE
		picker.tooltip_text = "Color of %s messages" % KIND_NAMES[kind].to_lower()
		picker.color = color_for(kind)
		picker.color_changed.connect(func(c: Color): set_kind_color(kind, c))
		_options.add_child(picker)
		_kind_buttons[kind] = picker
	var reset := _title_button(_options, "Reset", "Default size, colors and background", _reset_options)
	reset.custom_minimum_size = Vector2(44, 22)


## Changes the color one kind of message is written in, and saves it.
func set_kind_color(kind: String, color: Color) -> void:
	kind_colors[kind] = Color(color, 1.0)
	_apply_options()
	_save()


func _reset_options() -> void:
	kind_colors = DEFAULT_KIND_COLORS.duplicate()
	for kind in _kind_buttons:
		(_kind_buttons[kind] as ColorPickerButton).color = color_for(kind)
	set_options(DEFAULT_FONT_SIZE, TEXT, DEFAULT_OPACITY)


func _option_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_options.add_child(l)


func toggle_options() -> void:
	_options.visible = not _options.visible
	if _options.visible and _collapsed:
		toggle_collapsed()
	if _options.visible:
		# The options take up room: grow the window so messages are still
		# readable behind them, and stay on screen after growing.
		size.y = maxf(size.y, OPTIONS_HEIGHT)
		_full_height = size.y
		_keep_on_screen()


## Changes the text size, text color and background opacity, applies them to
## every line and saves them.
func set_options(p_font_size: int, p_color: Color, p_opacity: float) -> void:
	font_size = clampi(p_font_size, FONT_SIZES.x, FONT_SIZES.y)
	text_color = Color(p_color, 1.0)
	opacity = clampf(p_opacity, 0.0, 1.0)
	_apply_options()
	_save()


## The color a kind of line is written in: its own, or the plain text color
## for anything without one of its own.
func color_for(kind: String) -> Color:
	return kind_colors.get(kind, text_color)


func _apply_options() -> void:
	_style.bg_color.a = opacity
	for row in _lines.get_children():
		for piece in row.get_children():
			if piece is Label:
				piece.add_theme_font_size_override("font_size", font_size)
				piece.add_theme_color_override("font_color", color_for(piece.get_meta("kind", "filler")))
			elif piece is TextureRect:
				piece.custom_minimum_size = Vector2(font_size + 4, font_size + 4)
	# Show the values without re-triggering their change signals.
	_size_box.set_value_no_signal(font_size)
	_color_button.color = text_color
	_opacity_slider.set_value_no_signal(opacity)


func line_count() -> int:
	return _lines.get_child_count()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame  # after the new line is laid out
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_apply_collapsed()
	_save()


func _apply_collapsed() -> void:
	_body.visible = not _collapsed
	_collapse.text = "+" if _collapsed else "–"
	_collapse.tooltip_text = "Expand" if _collapsed else "Collapse"
	if _collapsed:
		size.y = TITLE_HEIGHT + 8
	else:
		size.y = _full_height


func hide_log() -> void:
	visible = false
	_save()
	visibility_toggled.emit(false)


func toggle_shown() -> void:
	visible = not visible
	if visible:
		_keep_on_screen()
	_save()
	visibility_toggled.emit(visible)


func _on_bar_input(event: InputEvent) -> void:
	_drag_input(event, "move")


func _on_grip_input(event: InputEvent) -> void:
	_drag_input(event, "resize")


func _drag_input(event: InputEvent, kind: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = kind
			_drag_from = event.global_position
			_rect_from = Rect2(position, size)
		elif _dragging != "":
			_dragging = ""
			_save()
		accept_event()
	elif event is InputEventMouseMotion and _dragging != "":
		var moved: Vector2 = event.global_position - _drag_from
		if _dragging == "move":
			position = _rect_from.position + moved
		else:
			size = (_rect_from.size + moved).max(MIN_SIZE)
			_collapsed = false
			_body.visible = true
			_full_height = size.y
		_keep_on_screen()
		accept_event()


## Keeps the window inside the screen (e.g. after the window was resized).
func _keep_on_screen() -> void:
	var screen := get_viewport_rect().size
	size = size.min(screen - Vector2(8, 8))
	position = position.clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))


func _title_button(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(22, 18)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _save() -> void:
	var cfg := ConfigFile.new()
	for kind in kind_colors:
		cfg.set_value("colors", kind, kind_colors[kind])
	cfg.set_value("log", "rect", Rect2(position, Vector2(size.x, _full_height)))
	cfg.set_value("log", "collapsed", _collapsed)
	cfg.set_value("log", "visible", visible)
	cfg.set_value("log", "font_size", font_size)
	cfg.set_value("log", "text_color", text_color)
	cfg.set_value("log", "opacity", opacity)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	var rect := DEFAULT_RECT
	if cfg.load(SAVE_PATH) == OK:
		var saved = cfg.get_value("log", "rect", DEFAULT_RECT)
		if saved is Rect2:
			rect = saved
		_collapsed = cfg.get_value("log", "collapsed", false) == true
		visible = cfg.get_value("log", "visible", true) != false
		var size_value = cfg.get_value("log", "font_size", DEFAULT_FONT_SIZE)
		font_size = clampi(int(size_value), FONT_SIZES.x, FONT_SIZES.y) if (size_value is int or size_value is float) else DEFAULT_FONT_SIZE
		var color_value = cfg.get_value("log", "text_color", TEXT)
		text_color = color_value if color_value is Color else TEXT
		var opacity_value = cfg.get_value("log", "opacity", DEFAULT_OPACITY)
		opacity = clampf(float(opacity_value), 0.0, 1.0) if (opacity_value is int or opacity_value is float) else DEFAULT_OPACITY
		for kind in kind_colors:
			var saved_color = cfg.get_value("colors", kind, kind_colors[kind])
			if saved_color is Color:
				kind_colors[kind] = saved_color
	position = rect.position
	size = rect.size.max(MIN_SIZE)
	_full_height = size.y
	_apply_collapsed()
	_apply_options()
	_keep_on_screen.call_deferred()
