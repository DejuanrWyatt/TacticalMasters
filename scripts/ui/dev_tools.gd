extends Control
## Developer Tools: sliders for the main rule numbers (GameState.TUNING), such
## as the Speed and Patience multipliers, plus the classes imported from Astra
## Ability Creator. Hovering a slider shows the formula it feeds, worked out
## for example units with the current values.
##
## Values are saved (GameConfig.tuning) and used by the next battle. In a
## battle vs the computer or on one device ("live"), changes also apply at
## once through a recorded "tune" command. Online matches keep the host's
## numbers. Used from the main menu and the in-game menu.

signal closed
## New rule numbers for the running battle (only sent when `live`).
signal tuning_changed(values: Dictionary)

const GameState = preload("res://scripts/core/game_state.gd")
const Jobs = preload("res://scripts/core/jobs.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AstraImport = preload("res://scripts/core/astra_import.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
## Seconds to wait after the last slider move before changing the battle
## (dragging would otherwise send a command every frame).
const APPLY_DELAY := 0.25

var live := false
var _sliders := {}
var _value_labels := {}
var _name_labels := {}
var _note: Label
var _classes: VBoxContainer
## A small battle used to work out the tooltip examples.
var _example := GameState.new()
var _pending := {}
var _pending_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	_example.setup(MapData.build(MapData.DEFAULT_MAP, ["knight", "archer", "black_mage", "white_mage"],
		["knight", "monk", "black_mage", "white_mage"]))

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
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Developer Tools"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Reset all", _reset_all))
	header.add_child(_button("Close", close_tools))

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	content.add_child(_section("Look  (saved with your settings, not with the battle)"))
	var look := GridContainer.new()
	look.columns = 4
	look.add_theme_constant_override("h_separation", 16)
	look.add_theme_constant_override("v_separation", 4)
	content.add_child(look)
	_add_look_row(look, "Team circle size", "unit_circle_size", 0.4, 2.5, 0.05,
		"How big the team-colored circle under each unit is. Bigger circles make it easier to tell the sides apart.")

	content.add_child(_section("Rule numbers  (hover for the formula)"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for key in GameState.TUNING:
		_add_row(grid, key)

	content.add_child(_section("Imported classes  (Astra Ability Creator)"))
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.7)
	help.text = ("Design a class in Astra: tag every ability \"class:<id>\", give one Passive ability the tag \"profile\" with "
		+ "parameters hp, attdef, magdef, speed, move, patience and sight (power, aeva, meva and crit are optional), tag it \"role:tank\" "
		+ "(or damage / support / special, or a pair like tank/support), and tag the 4 abilities \"slot:1\" to \"slot:4\" "
		+ "(4 = ultimate). Export the library as JSON into the classes folder, then Reload. See README for every parameter.")
	content.add_child(help)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)
	var open := _button("Open classes folder", _open_folder)
	open.tooltip_text = ProjectSettings.globalize_path("user://classes/")
	buttons.add_child(open)
	var reload := _button("Reload classes", _reload_classes)
	reload.tooltip_text = "Reads the class files again. Classes already in a running battle keep their old numbers."
	buttons.add_child(reload)
	_classes = VBoxContainer.new()
	content.add_child(_classes)

	show_values(GameConfig.tuning)
	_list_classes()


func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	_pending_time -= delta
	if _pending_time <= 0.0:
		tuning_changed.emit(_pending)
		_pending = {}


## Shows these rule numbers on the sliders (missing keys: defaults).
func show_values(values: Dictionary) -> void:
	if _sliders.is_empty():
		return
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(values.get(key, GameState.TUNING[key][0])))
	_refresh()


## A slider over one of the player's display settings (Settings), which
## takes effect at once and is saved for next time.
func _add_look_row(grid: GridContainer, title: String, key: String, low: float, high: float, step: float, tip: String) -> void:
	var name_label := Label.new()
	name_label.text = title
	name_label.tooltip_text = tip
	name_label.custom_minimum_size.x = 230
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(name_label)
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.custom_minimum_size = Vector2(320, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = tip
	s.set_value_no_signal(float(Settings.get(key)))
	var value := Label.new()
	value.custom_minimum_size.x = 70
	value.text = _fmt(float(Settings.get(key)))
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	var on_change := func(v: float) -> void:
		Settings.set_value(key, v)
		value.text = _fmt(v)
	s.value_changed.connect(on_change)
	grid.add_child(s)
	grid.add_child(value)
	var reset := _button("Reset", func(): s.value = 1.0)
	reset.custom_minimum_size = Vector2(80, 30)
	reset.tooltip_text = "Back to the default: 1"
	grid.add_child(reset)


func _add_row(grid: GridContainer, key: String) -> void:
	var info: Array = GameState.TUNING[key]
	var name_label := Label.new()
	name_label.text = info[4]
	name_label.custom_minimum_size.x = 230
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(name_label)
	var s := HSlider.new()
	s.min_value = info[1]
	s.max_value = info[2]
	s.step = info[3]
	s.custom_minimum_size = Vector2(320, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(_on_slider.bind(key))
	grid.add_child(s)
	var value := Label.new()
	value.custom_minimum_size.x = 70
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(value)
	var reset := _button("Reset", _reset.bind(key))
	reset.custom_minimum_size = Vector2(80, 30)
	reset.tooltip_text = "Back to the default: %s" % _fmt(info[0])
	grid.add_child(reset)
	_sliders[key] = s
	_value_labels[key] = value
	_name_labels[key] = name_label


func _on_slider(value: float, key: String) -> void:
	GameConfig.set_tuning(key, value)
	if live:
		_pending[key] = value
		_pending_time = APPLY_DELAY
	_refresh()


func _reset(key: String) -> void:
	_sliders[key].value = GameState.TUNING[key][0]


func _reset_all() -> void:
	GameConfig.reset_tuning()
	show_values({})
	if live:
		_pending = GameState.default_tuning()
		_pending_time = 0.0


## Updates value labels, the note and every formula tooltip.
func _refresh() -> void:
	var values := current_values()
	_example.tuning = values
	var changed := 0
	for key in _sliders:
		var v: float = values[key]
		var is_default := is_equal_approx(v, GameState.TUNING[key][0])
		if not is_default:
			changed += 1
		var label: Label = _value_labels[key]
		label.text = _fmt(v)
		label.add_theme_color_override("font_color", UiTheme.GOLD if not is_default else UiTheme.TEXT)
		var tip := "%s\n\n%s" % [GameState.TUNING[key][5], _formula(key)]
		for c in [_name_labels[key], _sliders[key], label]:
			c.tooltip_text = tip
	var where := "Changes apply to this battle right away and are saved for the next ones." if live \
		else "Changes are saved and used by the next battle. Online matches use the host's numbers."
	_note.text = "%s  %d of %d changed from the defaults." % [where, changed, _sliders.size()]


func current_values() -> Dictionary:
	var out := {}
	for key in _sliders:
		out[key] = (_sliders[key] as HSlider).value
	return out


## The formula a rule number feeds, worked out for example units.
func _formula(key: String) -> String:
	var knight = _unit(0, "knight")
	var archer = _unit(0, "archer")
	var mage = _unit(1, "black_mage")
	var white = _unit(0, "white_mage")
	match key:
		"speed_multiplier":
			return "Knight: %s\nArcher: %s" % [_example.explain_turn(knight), _example.explain_turn(archer)]
		"clock_base", "patience_multiplier":
			return "Knight: %s\nBlack Mage: %s" % [_example.explain_countdown(knight), _example.explain_countdown(mage)]
		"damage_multiplier":
			return "Knight Attack on a Black Mage, from the front:\n%s" % _hit(knight, 0, mage, 1.0)
		"heal_multiplier":
			knight.hp = 40
			var text := "White Mage Cure on a Knight at 40 HP:\n%s" % _example.explain_hit(white, 1, white.pos, knight)
			knight.hp = knight.max_hp()
			return text
		"height_bonus":
			var h: float = _example.tune("height_bonus")
			return "Damage x (1 + %s x levels above the target), -3 to +3 levels.\n2 levels above: x %s   ·   1 level below: x %s" % [
				_fmt(h), _fmt(1.0 + 2 * h), _fmt(1.0 - h)]
		"side_bonus":
			return "Knight Attack on a Black Mage, from the side:\n%s" % _hit(knight, 0, mage, 0.0)
		"back_bonus":
			return "Knight Attack on a Black Mage, from behind:\n%s" % _hit(knight, 0, mage, -1.0)
		"ko_seconds":
			var s: float = _example.tune("ko_seconds")
			return "Knocked out for %s s = %d ticks, then removed.%s" % [_fmt(s), roundi(s * GameState.TICKS_PER_SECOND),
				"\n0 = removed at once (no revive)." if s == 0.0 else ""]
		"ult_per_action", "ult_per_turn":
			var per_turn := roundi(_example.tune("ult_per_turn"))
			var per_action := roundi(_example.tune("ult_per_action"))
			var both := per_turn + per_action
			return ("Meter +%d each turn, +%d per ability used (max %d).\nActing every turn: full after %s turns."
				% [per_turn, per_action, GameState.ULT_MAX, "never" if both == 0 else str(ceili(float(GameState.ULT_MAX) / both))])
		"move_multiplier":
			return "Knight: %s\nArcher: %s" % [_example.explain_move(knight), _example.explain_move(archer)]
		"sight_multiplier":
			return "Archer: %s\nBlack Mage: %s" % [_example.explain_sight(archer), _example.explain_sight(mage)]
		"cast_time_multiplier":
			var lines: Array[String] = []
			for slot in 4:
				var ab: Dictionary = mage.ability(slot)
				if ab.cast > 0.0:
					lines.append("%s: %s s x %s = %s s" % [ab.name, _fmt(ab.cast), _fmt(_example.tune(key)), _fmt(_example.cast_seconds(ab))])
			return "Black Mage casts:\n" + "\n".join(lines)
	return ""


## An example hit on `t` from next to it: dot 1 = front, 0 = side, -1 = behind.
func _hit(u, slot: int, t, dot: float) -> String:
	var side := Vector2(-t.facing.y, t.facing.x)
	var dir: Vector2 = t.facing * dot + side * sqrt(maxf(0.0, 1.0 - dot * dot))
	# Close in, so both stand on the same level (level ground for the example).
	var from: Vector2 = t.pos + dir.normalized() * 0.3
	var text: String = _example.explain_hit(u, slot, from, t)
	return text


func _unit(team: int, job: String):
	for u in _example.units:
		if u.team == team and u.job == job:
			return u
	return _example.units[0]


func _list_classes() -> void:
	for child in _classes.get_children():
		child.queue_free()
	var any := false
	for id in Jobs.custom_jobs:
		any = true
		var job: Dictionary = Jobs.custom_jobs[id]
		var l := Label.new()
		var names: Array[String] = []
		for ab_id in job.abilities:
			names.append(Jobs.ability(ab_id).name)
		l.text = "%s  (%s)   HP %d  AttDef %d  MagDef %d  A-Eva %d%%  M-Eva %d%%  Crit %d%%  Speed %d  Move %d  Patience %d  Sight %d   ·   %s" % [
			job.name, id, job.hp, job.attdef, job.magdef, job.aeva, job.meva, job.crit,
			job.speed, job.move, job.patience, job.sight, ", ".join(names)]
		l.add_theme_color_override("font_color", job.color.lightened(0.3))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_classes.add_child(l)
	for m in GameConfig.class_messages:
		if m.begins_with("Loaded"):
			continue
		var e := Label.new()
		e.text = m
		e.add_theme_color_override("font_color", Color(1.0, 0.38, 0.32))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_classes.add_child(e)
	if not any:
		var none := Label.new()
		none.text = "No imported classes yet."
		none.modulate = Color(1, 1, 1, 0.6)
		_classes.add_child(none)


func _open_folder() -> void:
	DirAccess.make_dir_recursive_absolute("user://classes")
	OS.shell_open(ProjectSettings.globalize_path("user://classes/"))


func _reload_classes() -> void:
	GameConfig.class_messages = AstraImport.load_all()
	_list_classes()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(action)
	return b


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_tools()
		get_viewport().set_input_as_handled()


func close_tools() -> void:
	# Send any change still waiting before closing.
	if not _pending.is_empty():
		tuning_changed.emit(_pending)
		_pending = {}
	visible = false
	closed.emit()
