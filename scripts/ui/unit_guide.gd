extends Control
## Unit Guide: a full-screen reference of every job's stats and abilities,
## with the damage or healing each ability does. Damage depends on the
## target's defense, so a picker chooses which job to calculate it against
## (on level ground, before buffs). Used from the main menu and in battle.
## Numbers follow the current rule numbers (Developer Tools); hovering a
## number shows how it is calculated. From the main menu (`editable`),
## clicking a stat changes it for every new battle (GameConfig.set_stat);
## changed stats are gold. The list can be searched, filtered by role
## (Tank / Damage / Support / Special) and sorted by name or by role.

signal closed

const Jobs = preload("res://scripts/core/jobs.gd")
const GameState = preload("res://scripts/core/game_state.gd")

const SORTS := [["name", "Name (A-Z)"], ["role", "Role, then name"], ["hp", "HP"], ["wits", "Wits (fastest first)"]]
const STAT_COLUMNS := [
	["hp", "HP"], ["power", "Power"], ["attdef", "AttDef"], ["magdef", "MagDef"],
	["aeva", "A-Eva"], ["meva", "M-Eva"], ["crit", "Crit"],
	["wits", "Wits"], ["move", "Move (m)"], ["patience", "Patience"], ["sight", "Sight (m)"],
]
const ABILITY_COLUMNS := ["", "Ability", "Type", "Shape", "Effect", "Range", "Area", "Cast", "Cooldown", "Base", "vs target", "Description"]
const HEADER_COLOR := Color(1.0, 0.85, 0.45)
const ULT_COLOR := Color(1.0, 0.75, 0.3)
const CHANGED_COLOR := Color(1.0, 0.82, 0.35)

var _target_picker: OptionButton
## Which class's abilities are shown (a dropdown: there are over 100 classes).
var _class_picker: OptionButton
var _ability_box: PanelContainer
var _job_ids: Array = []
## Rule numbers to calculate with (set before adding the guide); missing
## keys use the defaults.
var tuning := {}
## True from the main menu: stats can be changed by clicking them. (In a
## battle the guide only shows them, so a battle's numbers never change.)
var editable := false
var _stats_holder: VBoxContainer
var _editor: PopupPanel
var _editor_title: Label
var _editor_box: SpinBox
var _editor_default: Button
## [job id, stat, the clicked cell] being edited.
var _editing := []
## List controls: what to show and in which order.
var _search := ""
var _role_filter := ""
var _sort := "name"
var _role_buttons := {}
var _count_label: Label


func _ready() -> void:
	_job_ids = Jobs.all_jobs().keys()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = preload("res://scripts/ui/ui_theme.gd").build()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 0.94)
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
	title.text = "Unit Guide"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(130, 44)
	close.pressed.connect(close_guide)
	if editable:
		var reset_all := Button.new()
		reset_all.text = "Reset all stats"
		reset_all.focus_mode = Control.FOCUS_NONE
		reset_all.custom_minimum_size = Vector2(150, 44)
		reset_all.tooltip_text = "Put every class's stats back to their own values"
		reset_all.pressed.connect(func():
			GameConfig.reset_stats()
			_refresh_stats())
		header.add_child(reset_all)
	header.add_child(close)
	var hint := Label.new()
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.text = ("Click a stat to change it (changed stats are gold). Changes are saved and used by every new battle; online, the host's are used."
		if editable else "Stats can be changed from the Unit Guide on the main menu.")
	column.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	body.add_child(_section("Stats"))
	body.add_child(_filter_row())
	_stats_holder = VBoxContainer.new()
	_stats_holder.add_child(_stats_table())
	body.add_child(_stats_holder)

	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 10)
	body.add_child(picker_row)
	picker_row.add_child(_section("Abilities"))
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 24
	picker_row.add_child(spacer)
	var class_label := Label.new()
	class_label.text = "Class:"
	picker_row.add_child(class_label)
	_class_picker = _job_picker()
	_class_picker.item_selected.connect(func(_i): _show_abilities())
	picker_row.add_child(_class_picker)
	var picker_label := Label.new()
	picker_label.text = "   Damage against:"
	picker_row.add_child(picker_label)
	_target_picker = _job_picker()
	_target_picker.select(_job_ids.find("knight"))
	_target_picker.item_selected.connect(func(_i): _show_abilities())
	picker_row.add_child(_target_picker)

	_ability_box = PanelContainer.new()
	_ability_box.custom_minimum_size.y = 190
	body.add_child(_ability_box)
	_show_abilities()

	body.add_child(_section("Status effects"))
	var statuses := GridContainer.new()
	statuses.columns = 3
	statuses.add_theme_constant_override("h_separation", 22)
	statuses.add_theme_constant_override("v_separation", 6)
	for id in Jobs.STATUSES:
		var info: Dictionary = Jobs.STATUSES[id]
		_cell(statuses, info.tag, info.color)
		_cell(statuses, info.name, info.color, 90)
		_cell(statuses, info.desc)
	body.add_child(statuses)

	var notes := Label.new()
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes.modulate = Color(1, 1, 1, 0.65)
	notes.text = ("Base = the ability's own power (+ the class's Power stat); healing is × %s%s. "
		+ "Damage = (Base × height bonus − the target's AttDef (physical) or MagDef (magic)) × %s, minimum 1. "
		+ "A-Eva and M-Eva are the chances to evade a physical or magical ability entirely; Crit is the chance to hit for × %s. "
		+ "The height bonus is +%d%% per level above the target (−%d%% per level below), up to 3 levels. "
		+ "Abilities with a cast time go off when the cast finishes. Move first: only instant abilities let a unit move afterwards. "
		+ "Hits from the side deal +%d%%, from behind +%d%%. Ranged abilities and vision need line of sight over the terrain. "
		+ "A unit at 0 HP is knocked out for %ds and can be revived with Raise before it's gone. "
		+ "The ultimate (4) needs a full Ultimate meter. Hover a number to see how it is calculated.") % [
			_num(GameState.HEAL_SCALE * _t("heal_multiplier")), "", _num(_t("damage_multiplier")), _num(_t("crit_multiplier")),
			roundi(_t("height_bonus") * 100), roundi(_t("height_bonus") * 100),
			roundi((_t("side_bonus") - 1.0) * 100), roundi((_t("back_bonus") - 1.0) * 100), roundi(_t("ko_seconds"))]
	body.add_child(notes)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_guide()
		get_viewport().set_input_as_handled()


func close_guide() -> void:
	visible = false
	closed.emit()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", HEADER_COLOR)
	return l


func _t(key: String) -> float:
	return float(tuning.get(key, GameState.TUNING[key][0]))


func _cell(grid: GridContainer, text: String, color := Color.WHITE, min_width := 0.0, tip := "") -> Label:
	var l := Label.new()
	l.text = text
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_color_override("font_color", color)
	if min_width > 0.0:
		l.custom_minimum_size.x = min_width
	grid.add_child(l)
	return l


func _stats_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = STAT_COLUMNS.size() + 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	_cell(grid, "Job", HEADER_COLOR, 110)
	_cell(grid, "Role", HEADER_COLOR, 120)
	for col in STAT_COLUMNS:
		_cell(grid, col[1], HEADER_COLOR)
	_cell(grid, "Turn every", HEADER_COLOR)
	var ids := _listed_ids()
	if _count_label != null:
		_count_label.text = "  %d of %d classes" % [ids.size(), _job_ids.size()]
	var heading := ""
	for id in ids:
		# Sorted by role: a heading row before each group.
		if _sort == "role":
			var role: String = Jobs.roles_of(id)[0]
			if role != heading:
				heading = role
				_cell(grid, Jobs.ROLES[role].name.to_upper(), Jobs.ROLES[role].color, 110)
				for i in STAT_COLUMNS.size() + 2:
					_cell(grid, "")
		var job: Dictionary = Jobs.job(id)
		# Clicking a class's name shows its abilities below.
		var name_cell := _cell(grid, job.name, job.color.lightened(0.35), 0.0, "%s: click to see its abilities" % job.name)
		name_cell.mouse_filter = Control.MOUSE_FILTER_STOP
		name_cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var on_click := func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_class(id)
		name_cell.gui_input.connect(on_click)
		_role_cell(grid, id)
		var changed: Dictionary = Jobs.stat_overrides.get(id, {})
		for col in STAT_COLUMNS:
			var stat: String = col[0]
			var tip := _stat_tip(job, stat)
			if changed.has(stat):
				tip = "Changed from %d\n%s" % [Jobs.base_job(id)[stat], tip]
			var cell := _cell(grid, str(job[stat]), CHANGED_COLOR if changed.has(stat) else Color.WHITE, 0.0,
				tip + ("\nClick to change" if editable else ""))
			if editable:
				cell.mouse_filter = Control.MOUSE_FILTER_STOP
				cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				var on_edit := func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
						_edit_stat(id, stat, cell)
				cell.gui_input.connect(on_edit)
		# Time to fill the Turn Gauge from empty.
		var gain := maxi(1, roundi(job.wits * GameState.TG_PER_WITS * _t("wits_multiplier")))
		var seconds: float = float(GameState.TG_MAX) / gain / GameState.TICKS_PER_SECOND
		_cell(grid, "%.1fs" % seconds, Color.WHITE, 0.0, "TG per tick = Wits %d x %d x Wits multiplier %s = %d\n%d / %d = %d ticks (%d per second) = %.1f s" % [
			job.wits, GameState.TG_PER_WITS, _num(_t("wits_multiplier")), gain, GameState.TG_MAX, gain,
			ceili(float(GameState.TG_MAX) / gain), GameState.TICKS_PER_SECOND, seconds])
	return grid


## How a stat is used, with its numbers worked out.
func _stat_tip(job: Dictionary, key: String) -> String:
	match key:
		"move":
			return "Move %d m x move multiplier %s = %s m per turn" % [job.move, _num(_t("move_multiplier")), _num(job.move * _t("move_multiplier"))]
		"sight":
			return "Sight %d m x sight multiplier %s = %s m vision" % [job.sight, _num(_t("sight_multiplier")), _num(job.sight * _t("sight_multiplier"))]
		"patience":
			return "READY countdown = base %s s + Patience %d x %s s = %s s" % [
				_num(_t("clock_base")), job.patience, _num(_t("patience_multiplier")), _num(_t("clock_base") + job.patience * _t("patience_multiplier"))]
		"wits":
			return "TG per tick = Wits %d x %d x Wits multiplier %s" % [job.wits, GameState.TG_PER_WITS, _num(_t("wits_multiplier"))]
		"power":
			return "Power: added to the damage and healing of every ability it uses (+%d)" % job[key]
		"aeva":
			return "A-Eva: %d%% chance to evade a physical ability entirely" % job[key]
		"meva":
			return "M-Eva: %d%% chance to evade a harmful magical ability entirely" % job[key]
		"crit":
			return "Crit: %d%% chance its abilities hit critically (x %s damage)" % [job[key], _num(_t("crit_multiplier"))]
		"attdef", "magdef":
			return "Subtracted from %s damage before the damage multiplier %s" % ["physical" if key == "attdef" else "magic", _num(_t("damage_multiplier"))]
	return ""


## Search, role filter and sorting for the class list.
func _filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var search := LineEdit.new()
	search.placeholder_text = "Search classes"
	search.custom_minimum_size.x = 190
	search.clear_button_enabled = true
	search.text_changed.connect(func(text: String):
		_search = text.strip_edges().to_lower()
		_refresh_stats())
	row.add_child(search)
	var role_label := Label.new()
	role_label.text = "  Role:"
	row.add_child(role_label)
	_role_buttons[""] = _role_button("", "All", row)
	for role in Jobs.ROLES:
		_role_buttons[role] = _role_button(role, Jobs.ROLES[role].name, row)
	var sort_label := Label.new()
	sort_label.text = "  Sort:"
	row.add_child(sort_label)
	var sort := OptionButton.new()
	sort.focus_mode = Control.FOCUS_NONE
	for entry in SORTS:
		sort.add_item(entry[1])
	sort.item_selected.connect(func(i: int):
		_sort = SORTS[i][0]
		_refresh_stats())
	row.add_child(sort)
	_count_label = Label.new()
	_count_label.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_count_label)
	return row


func _role_button(role: String, text: String, row: HBoxContainer) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = role == _role_filter
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Show only %s classes" % text if role != "" else "Show every class"
	if role != "":
		b.icon = load(Jobs.ROLES[role].icon)
		b.add_theme_constant_override("icon_max_width", 16)
		b.add_theme_color_override("font_color", Jobs.ROLES[role].color)
	b.pressed.connect(func():
		_role_filter = role
		for key in _role_buttons:
			(_role_buttons[key] as Button).set_pressed_no_signal(key == role)
		_refresh_stats())
	row.add_child(b)
	return b


## The classes to list, in the chosen order.
func _listed_ids() -> Array:
	var ids := []
	for id in _job_ids:
		var job: Dictionary = Jobs.job(id)
		if _search != "" and not String(job.name).to_lower().contains(_search):
			continue
		if _role_filter != "" and not Jobs.roles_of(id).has(_role_filter):
			continue
		ids.append(id)
	var order := Jobs.ROLES.keys()
	var by_name := func(a, b): return String(Jobs.job(a).name).naturalnocasecmp_to(Jobs.job(b).name) < 0
	match _sort:
		"role":
			var by_role := func(a, b):
				var ra: int = order.find(Jobs.roles_of(a)[0])
				var rb: int = order.find(Jobs.roles_of(b)[0])
				if ra != rb:
					return ra < rb
				return by_name.call(a, b)
			ids.sort_custom(by_role)
		"hp":
			ids.sort_custom(func(a, b): return Jobs.job(a).hp > Jobs.job(b).hp)
		"wits":
			ids.sort_custom(func(a, b): return Jobs.job(a).wits > Jobs.job(b).wits)
		_:
			ids.sort_custom(by_name)
	return ids


## An ability's icon and name, as one cell.
func _ability_name_cell(grid: GridContainer, ab_id: String, text: String, color: Color) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var icon := TextureRect.new()
	icon.texture = load(Jobs.ability_icon_path(ab_id))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 110
	box.add_child(label)
	grid.add_child(box)


## What a target shape covers, in words.
func _shape_tip(ab: Dictionary, shape: String) -> String:
	match shape:
		"line", "vector":
			return "Everyone within %s m of the line out to %s m%s" % [_num(maxf(ab.aoe, 0.6)), _num(ab.max_range),
				"; the user ends up at the far end" if shape == "vector" else ""]
		"cone":
			return "Everyone within %s m in a %d° arc" % [_num(ab.max_range), roundi(ab.get("angle", 60.0))]
		"global":
			return "Everyone on the field"
		"circle":
			return "Everyone within %s m of the point" % _num(ab.aoe)
		"self":
			return "Centered on the user" + ("" if ab.aoe == 0.0 else " (%s m)" % _num(ab.aoe))
		"point":
			return "Whoever is standing on the point"
	return "One unit"


## Icons and names of a class's roles, as one cell.
func _role_cell(grid: GridContainer, id: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.tooltip_text = "%s: %s" % [Jobs.job(id).name, Jobs.role_name(id)]
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	for role in Jobs.roles_of(id):
		var icon := TextureRect.new()
		icon.texture = load(Jobs.ROLES[role].icon)
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	var label := Label.new()
	label.text = Jobs.role_name(id)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Jobs.ROLES[Jobs.roles_of(id)[0]].color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	grid.add_child(box)


## Opens the small editor over a stat cell.
func _edit_stat(id: String, stat: String, cell: Label) -> void:
	if _editor == null:
		_build_editor()
	_editing = [id, stat, cell]
	var limits: Array = Jobs.STAT_LIMITS[stat]
	_editor_title.text = "%s: %s" % [Jobs.job(id).name, _stat_name(stat)]
	# Loading the editor must not count as a change (a new range can clamp the
	# old value and fire value_changed).
	_editor_box.set_block_signals(true)
	_editor_box.min_value = limits[0]
	_editor_box.max_value = limits[1]
	_editor_box.value = Jobs.job(id)[stat]
	_editor_box.set_block_signals(false)
	_editor_default.text = "Default (%d)" % Jobs.base_job(id)[stat]
	_editor.popup(Rect2i(Vector2i(cell.get_screen_position()) + Vector2i(0, int(cell.size.y) + 2), Vector2i(220, 0)))
	_editor_box.get_line_edit().grab_focus.call_deferred()
	_editor_box.get_line_edit().select_all.call_deferred()


func _build_editor() -> void:
	_editor = PopupPanel.new()
	add_child(_editor)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_editor.add_child(box)
	_editor_title = Label.new()
	_editor_title.add_theme_color_override("font_color", HEADER_COLOR)
	box.add_child(_editor_title)
	_editor_box = SpinBox.new()
	_editor_box.step = 1
	_editor_box.value_changed.connect(_on_edit_value)
	_editor_box.get_line_edit().text_submitted.connect(func(_t): _editor.hide())
	box.add_child(_editor_box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_editor_default = Button.new()
	_editor_default.focus_mode = Control.FOCUS_NONE
	_editor_default.pressed.connect(func():
		_editor_box.value = Jobs.base_job(_editing[0])[_editing[1]])
	row.add_child(_editor_default)
	var reset_class := Button.new()
	reset_class.text = "Reset class"
	reset_class.focus_mode = Control.FOCUS_NONE
	reset_class.tooltip_text = "Put all of this class's stats back"
	reset_class.pressed.connect(func():
		GameConfig.reset_stats(_editing[0])
		_editor.hide())
	row.add_child(reset_class)
	# Closing the editor redraws the table (turn times, tooltips) and abilities.
	_editor.popup_hide.connect(_refresh_stats)


## A new value typed or stepped in the editor: saved and shown at once.
func _on_edit_value(value: float) -> void:
	var id: String = _editing[0]
	var stat: String = _editing[1]
	GameConfig.set_stat(id, stat, roundi(value))
	var cell: Label = _editing[2]
	cell.text = str(Jobs.job(id)[stat])
	cell.add_theme_color_override("font_color", CHANGED_COLOR if Jobs.stat_overrides.get(id, {}).has(stat) else Color.WHITE)


## Redraws the stats table and the abilities (their numbers use the stats).
func _refresh_stats() -> void:
	for child in _stats_holder.get_children():
		_stats_holder.remove_child(child)
		child.queue_free()
	_stats_holder.add_child(_stats_table())
	_show_abilities()


static func _stat_name(stat: String) -> String:
	for col in STAT_COLUMNS:
		if col[0] == stat:
			return col[1]
	return stat


## A dropdown of every class, with icons.
func _job_picker() -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.add_theme_constant_override("icon_max_width", 20)
	picker.get_popup().add_theme_constant_override("icon_max_width", 20)
	for id in _job_ids:
		picker.add_icon_item(load(Jobs.icon_path(id)), Jobs.job(id).name)
	return picker


## Shows the chosen class's abilities, with damage against the chosen target.
func _show_abilities() -> void:
	for child in _ability_box.get_children():
		_ability_box.remove_child(child)
		child.queue_free()
	var target: Dictionary = Jobs.job(_job_ids[_target_picker.selected])
	var job: Dictionary = Jobs.job(_job_ids[_class_picker.selected])
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = ABILITY_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	for header in ABILITY_COLUMNS:
		_cell(grid, header, HEADER_COLOR)
	for slot in 4:
		_ability_row(grid, job, slot, target)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_child(grid)
	_ability_box.add_child(pad)


## Shows one class's abilities (e.g. from a click in the stats table).
func show_class(id: String) -> void:
	var i := _job_ids.find(id)
	if i != -1:
		_class_picker.select(i)
		_show_abilities()
		# Scroll down to them (the stats table above is long).
		var node: Node = _class_picker.get_parent()
		while node != null and not node is ScrollContainer:
			node = node.get_parent()
		if node != null:
			(node as ScrollContainer).ensure_control_visible.call_deferred(_ability_box)


func _ability_row(grid: GridContainer, job: Dictionary, slot: int, target: Dictionary) -> void:
	var ab: Dictionary = Jobs.ability(job.abilities[slot])
	var color := ULT_COLOR if slot == 3 else Color.WHITE
	_cell(grid, "ULT" if slot == 3 else str(slot + 1), color)
	_ability_name_cell(grid, job.abilities[slot], ab.name, color)
	var effect: String = ab.effect.capitalize()
	if ab.effect == "damage":
		effect = "Physical" if ab.scale == "att" else "Magic"
	if ab.has("status"):
		effect += " + %s" % Jobs.STATUSES[ab.status.id].name
	var kind: String = ab.get("kind", "active")
	_cell(grid, Jobs.KINDS[kind].name, ULT_COLOR if kind != "active" else Color.WHITE, 0.0, Jobs.KINDS[kind].desc)
	var shape: String = GameState.shape_of(ab)
	var shape_text: String = Jobs.SHAPES[shape].name
	if shape == "cone":
		shape_text += " %d°" % roundi(ab.get("angle", 60.0))
	_cell(grid, shape_text, Color.WHITE, 0.0, _shape_tip(ab, shape))
	_cell(grid, effect)
	_cell(grid, "Self" if ab.max_range == 0.0 else "%s-%s m" % [_num(ab.min_range), _num(ab.max_range)])
	_cell(grid, "—" if ab.aoe == 0.0 else "%s m" % _num(ab.aoe))
	var cast: float = ab.cast * _t("cast_time_multiplier")
	_cell(grid, "Instant" if cast == 0.0 else "%ss" % _num(cast), Color.WHITE, 0.0,
		"" if ab.cast == 0.0 else "Cast %s s x cast time multiplier %s = %s s" % [_num(ab.cast), _num(_t("cast_time_multiplier")), _num(cast)])
	_cell(grid, "—" if ab.cooldown == 0 else "%d turn%s" % [ab.cooldown, "" if ab.cooldown == 1 else "s"])

	var power: int = roundi(ab.power) + int(job.power)
	var base := ""
	var versus := ""
	var base_tip := ""
	var versus_tip := ""
	var resisted := "AttDef / A-Eva" if ab.scale == "att" else "MagDef / M-Eva"
	match ab.effect:
		"damage":
			var def: int = target.attdef if ab.scale == "att" else target.magdef
			var evade: int = target.aeva if ab.scale == "att" else target.meva
			var dealt := maxi(1, roundi((power - def) * _t("damage_multiplier")))
			base = str(power)
			versus = "%d  (%d%% of %s HP)" % [dealt, roundi(100.0 * dealt / target.hp), target.name]
			base_tip = "Power %s%s, resisted by %s" % [_num(ab.power), " + %d from the class" % job.power if job.power > 0 else "", resisted]
			versus_tip = "(%d - %s's %s %d) x damage multiplier %s = %d%s\nLevel ground, from the front. From the side x %s, from behind x %s, +%d%% per level above.\n%s evades it %d%% of the time; a critical hit (x %s) does %d." % [
				power, target.name, "AttDef" if ab.scale == "att" else "MagDef", def, _num(_t("damage_multiplier")), dealt,
				" (minimum 1)" if dealt == 1 else "", _num(_t("side_bonus")), _num(_t("back_bonus")), roundi(_t("height_bonus") * 100),
				target.name, evade, _num(_t("crit_multiplier")), maxi(1, roundi(dealt * _t("crit_multiplier")))]
		"heal":
			var healed := roundi(power * GameState.HEAL_SCALE * _t("heal_multiplier"))
			base = "+%d" % healed
			versus = "heals"
			base_tip = "Power %s%s x %s x heal multiplier %s = %d (up to the missing HP)" % [
				_num(ab.power), " + %d from the class" % job.power if job.power > 0 else "",
				_num(GameState.HEAL_SCALE), _num(_t("heal_multiplier")), healed]
		"revive":
			base = "%d%% HP" % roundi(ab.power * 100)
			versus = "revives"
		_:
			base = "—"
			versus = "—"
	_cell(grid, base, Color(1, 0.6, 0.5) if ab.effect == "damage" else Color(0.6, 1, 0.65), 0.0, base_tip)
	_cell(grid, versus, Color.WHITE, 0.0, versus_tip)
	var extra := ""
	if ab.has("tg"):
		extra = "  (TG %+d%%)" % ab.tg
	var text: String = ab.desc.trim_prefix("ULTIMATE: ")
	var desc := _cell(grid, text.left(1).to_upper() + text.substr(1) + extra)
	desc.modulate = Color(1, 1, 1, 0.75)


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(snappedf(v, 0.01))
