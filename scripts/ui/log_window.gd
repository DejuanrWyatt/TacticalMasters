extends PanelContainer
## Combat log window: every battle message, newest at the bottom. Drag the
## title bar to move it, drag the corner grip to resize it, "–" collapses it
## to its title bar and "×" hides it (the Log button or L shows it again).
## Where it is, its size and whether it's shown are saved between battles.

signal visibility_toggled(shown: bool)

const SAVE_PATH := "user://log_window.cfg"
const MIN_SIZE := Vector2(220, 90)
const DEFAULT_RECT := Rect2(12, 104, 380, 170)
const MAX_LINES := 300
const TITLE_HEIGHT := 24.0
const TEXT := Color(0.92, 0.94, 1.0)
const DIM := Color(0.92, 0.94, 1.0, 0.55)

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.07, 0.72)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

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
	_collapse = _title_button(bar, "–", "Collapse", toggle_collapsed)
	_title_button(bar, "×", "Hide (L or the Log button shows it again)", hide_log)

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
func add_message(text: String) -> void:
	var at_bottom := _scroll.scroll_vertical >= int(_scroll.get_v_scroll_bar().max_value - _scroll.size.y) - 4
	var line := Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 12)
	line.add_theme_color_override("font_color", TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_child(line)
	while _lines.get_child_count() > MAX_LINES:
		var oldest := _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()
	# Older lines fade a little so the newest stand out.
	var count := _lines.get_child_count()
	for i in count:
		(_lines.get_child(i) as Label).modulate.a = 1.0 if i >= count - 3 else 0.7
	if at_bottom:
		_scroll_to_bottom.call_deferred()


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
	cfg.set_value("log", "rect", Rect2(position, Vector2(size.x, _full_height)))
	cfg.set_value("log", "collapsed", _collapsed)
	cfg.set_value("log", "visible", visible)
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
	position = rect.position
	size = rect.size.max(MIN_SIZE)
	_full_height = size.y
	_apply_collapsed()
	_keep_on_screen.call_deferred()
