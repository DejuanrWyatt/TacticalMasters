extends Control
## Choosing one class for a team slot in Battle Setup. There are over a
## hundred, so the list can be searched, filtered by role and sorted, the same
## way as in the Unit Guide (both ask ClassList). The right-hand panel shows
## the highlighted class's stats and its four abilities before it is taken.

signal picked(id: String)
signal closed

const Jobs = preload("res://scripts/core/jobs.gd")
const ClassList = preload("res://scripts/ui/class_list.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

## Stats worth seeing while picking; the Unit Guide has the rest.
const SHOWN_STATS := [["hp", "HP"], ["power", "Power"], ["attdef", "AttDef"], ["magdef", "MagDef"],
	["speed", "Speed"], ["move", "Move"], ["sight", "Sight"]]

var _search := ""
var _role_filter := ""
var _sort := "name"
var _shown := ""

var _list: VBoxContainer
var _detail: VBoxContainer
var _role_row: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.98)  # the setup screen behind must not read through
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 40
	column.offset_right = -40
	column.offset_top = 24
	column.offset_bottom = -24
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := Label.new()
	title.text = "CHOOSE A CLASS"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Cancel"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(110, 38)
	close.pressed.connect(_close)
	header.add_child(close)

	# Search, roles and order.
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	var search := LineEdit.new()
	search.placeholder_text = "Search"
	search.custom_minimum_size = Vector2(190, 34)
	search.text_changed.connect(func(text: String):
		_search = text.strip_edges().to_lower()
		_fill())
	filters.add_child(search)
	_role_row = HBoxContainer.new()
	_role_row.add_theme_constant_override("separation", 4)
	filters.add_child(_role_row)
	var group := ButtonGroup.new()
	_role_button("", "All", group)
	for role in Jobs.ROLES:
		_role_button(role, Jobs.ROLES[role].name, group)
	var sort := OptionButton.new()
	sort.focus_mode = Control.FOCUS_NONE
	sort.custom_minimum_size = Vector2(190, 34)
	for entry in ClassList.SORTS:
		sort.add_item(entry[1])
	sort.item_selected.connect(func(i: int):
		_sort = ClassList.SORTS[i][0]
		_fill())
	filters.add_child(sort)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 430
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	detail_panel.add_child(_detail)
	_fill()


func _role_button(role: String, text: String, group: ButtonGroup) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = role == _role_filter
	if role != "":
		b.icon = load(Jobs.ROLES[role].icon)
		b.add_theme_constant_override("icon_max_width", 16)
		b.add_theme_color_override("font_color", Jobs.ROLES[role].color)
	b.pressed.connect(func():
		_role_filter = role
		_fill())
	_role_row.add_child(b)


## Rebuilds the list for the current search, role and order.
func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids := ClassList.listed_ids(_search, _role_filter, _sort)
	for id in ids:
		_list.add_child(_row(id))
	if ids.is_empty():
		var none := Label.new()
		none.text = "No class matches that."
		none.add_theme_color_override("font_color", UiTheme.DIM)
		_list.add_child(none)
		_shown = ""
		_show_detail("")
	elif not ids.has(_shown):
		_show_detail(ids[0])


## One class in the list: icon, name, roles and the numbers worth comparing.
func _row(id: String) -> Button:
	var job: Dictionary = Jobs.job(id)
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = 34
	row.tooltip_text = "Click to put %s in this slot" % job.name
	row.pressed.connect(_show_detail.bind(id))
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.double_click:
			_take(id))
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load(Jobs.icon_path(id))
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var name_label := Label.new()
	name_label.text = job.name
	name_label.custom_minimum_size.x = 150
	box.add_child(name_label)
	box.add_child(ClassList.role_icons(id))
	var numbers := Label.new()
	numbers.text = "HP %d   POW %d   WIT %d" % [job.hp, job.power, job.speed]
	numbers.add_theme_font_size_override("font_size", 11)
	numbers.add_theme_color_override("font_color", UiTheme.DIM)
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(numbers)
	return row


## The panel on the right: everything about the class being looked at.
func _show_detail(id: String) -> void:
	_shown = id
	for child in _detail.get_children():
		child.queue_free()
	if id == "":
		return
	var job: Dictionary = Jobs.job(id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_detail.add_child(head)
	var icon := TextureRect.new()
	icon.texture = load(Jobs.icon_path(id))
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var name_label := Label.new()
	name_label.text = job.name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", UiTheme.GOLD)
	head.add_child(name_label)
	head.add_child(ClassList.role_icons(id, 20))
	var role_label := Label.new()
	role_label.text = Jobs.role_name(id)
	role_label.add_theme_color_override("font_color", UiTheme.DIM)
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(role_label)

	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 18)
	_detail.add_child(stats)
	for entry in SHOWN_STATS:
		var l := Label.new()
		l.text = "%s %s" % [entry[1], job[entry[0]]]
		l.add_theme_font_size_override("font_size", 12)
		stats.add_child(l)

	_detail.add_child(HSeparator.new())
	for slot in 4:
		var ab: Dictionary = Jobs.ability(Jobs.job(id).abilities[slot])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_detail.add_child(row)
		var ab_icon := TextureRect.new()
		ab_icon.texture = load(Jobs.ability_icon_path(Jobs.job(id).abilities[slot]))
		ab_icon.custom_minimum_size = Vector2(20, 20)
		ab_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ab_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ab_icon)
		var ab_name := Label.new()
		ab_name.text = "%d  %s" % [slot + 1, ab.name]
		ab_name.custom_minimum_size.x = 150
		ab_name.add_theme_font_size_override("font_size", 13)
		row.add_child(ab_name)
		var desc := Label.new()
		desc.text = ab.get("desc", "")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", UiTheme.DIM)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc)

	var take := Button.new()
	take.text = "Put %s in this slot" % job.name
	take.focus_mode = Control.FOCUS_NONE
	take.custom_minimum_size.y = 40
	take.pressed.connect(_take.bind(id))
	_detail.add_child(take)


func _take(id: String) -> void:
	picked.emit(id)
	_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
