extends Control
## Unit Guide: a full-screen reference of every job's stats and abilities,
## with the damage or healing each ability does. Damage depends on the
## target's defense, so a picker chooses which job to calculate it against
## (on level ground, before buffs). Used from the main menu and in battle.

signal closed

const Jobs = preload("res://scripts/core/jobs.gd")
const GameState = preload("res://scripts/core/game_state.gd")

const STAT_COLUMNS := [
	["hp", "HP"], ["att", "AttPwr"], ["mag", "MagPwr"], ["attdef", "AttDef"], ["magdef", "MagDef"],
	["wits", "Wits"], ["move", "Move (m)"], ["patience", "Patience"], ["sight", "Sight (m)"],
]
const ABILITY_COLUMNS := ["", "Ability", "Effect", "Range", "Area", "Cast", "Cooldown", "Base", "vs target", "Description"]
const HEADER_COLOR := Color(1.0, 0.85, 0.45)
const ULT_COLOR := Color(1.0, 0.75, 0.3)

var _target_picker: OptionButton
var _tabs: TabContainer
var _job_ids: Array = []


func _ready() -> void:
	_job_ids = Jobs.JOBS.keys()
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
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	body.add_child(_section("Stats"))
	body.add_child(_stats_table())

	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 10)
	body.add_child(picker_row)
	picker_row.add_child(_section("Abilities"))
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 24
	picker_row.add_child(spacer)
	var picker_label := Label.new()
	picker_label.text = "Damage against:"
	picker_row.add_child(picker_label)
	_target_picker = OptionButton.new()
	_target_picker.focus_mode = Control.FOCUS_NONE
	for id in _job_ids:
		_target_picker.add_item(Jobs.JOBS[id].name)
	_target_picker.select(_job_ids.find("knight"))
	_target_picker.item_selected.connect(func(_i): _fill_ability_tabs())
	picker_row.add_child(_target_picker)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.y = 250
	body.add_child(_tabs)
	_fill_ability_tabs()

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
	notes.text = ("Base = power stat × ability power × %s for damage (× %s for healing). "
		+ "Damage = (Base × height bonus − the target's AttDef (physical) or MagDef (magic)) × %s, minimum 1. "
		+ "The height bonus is +%d%% per level above the target (−%d%% per level below), up to 3 levels. "
		+ "Abilities with a cast time go off when the cast finishes. Move first: only instant abilities let a unit move afterwards. "
		+ "Hits from the side deal +%d%%, from behind +%d%%. Ranged abilities and vision need line of sight over the terrain. "
		+ "A unit at 0 HP is knocked out for %ds and can be revived with Raise before it's gone. "
		+ "The ultimate (4) needs a full Ultimate meter.") % [
			GameState.DAMAGE_SCALE, GameState.HEAL_SCALE, GameState.DAMAGE_MULTIPLIER,
			roundi(GameState.HEIGHT_BONUS * 100), roundi(GameState.HEIGHT_BONUS * 100),
			roundi((GameState.SIDE_BONUS - 1.0) * 100), roundi((GameState.BACK_BONUS - 1.0) * 100), roundi(GameState.KO_SECONDS)]
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


func _cell(grid: GridContainer, text: String, color := Color.WHITE, min_width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if min_width > 0.0:
		l.custom_minimum_size.x = min_width
	grid.add_child(l)
	return l


func _stats_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = STAT_COLUMNS.size() + 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	_cell(grid, "Job", HEADER_COLOR, 110)
	for col in STAT_COLUMNS:
		_cell(grid, col[1], HEADER_COLOR)
	_cell(grid, "Turn every", HEADER_COLOR)
	for id in _job_ids:
		var job: Dictionary = Jobs.JOBS[id]
		_cell(grid, job.name, job.color.lightened(0.2))
		for col in STAT_COLUMNS:
			_cell(grid, str(job[col[0]]))
		# Time to fill the Turn Gauge from empty.
		var seconds: float = float(GameState.TG_MAX) / (job.wits * GameState.TG_PER_WITS) / GameState.TICKS_PER_SECOND
		_cell(grid, "%.1fs" % seconds)
	return grid


func _fill_ability_tabs() -> void:
	var current := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var target: Dictionary = Jobs.JOBS[_job_ids[_target_picker.selected]]
	for id in _job_ids:
		var job: Dictionary = Jobs.JOBS[id]
		var grid := GridContainer.new()
		grid.columns = ABILITY_COLUMNS.size()
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 8)
		for header in ABILITY_COLUMNS:
			_cell(grid, header, HEADER_COLOR)
		for slot in 4:
			_ability_row(grid, job, slot, target)
		var pad := MarginContainer.new()
		pad.name = job.name
		pad.add_theme_constant_override("margin_left", 10)
		pad.add_theme_constant_override("margin_top", 10)
		grid.name = "Grid"
		pad.add_child(grid)
		_tabs.add_child(pad)
	if current >= 0 and current < _tabs.get_tab_count():
		_tabs.current_tab = current


func _ability_row(grid: GridContainer, job: Dictionary, slot: int, target: Dictionary) -> void:
	var ab: Dictionary = Jobs.ABILITIES[job.abilities[slot]]
	var color := ULT_COLOR if slot == 3 else Color.WHITE
	_cell(grid, "ULT" if slot == 3 else str(slot + 1), color)
	_cell(grid, ab.name, color, 110)
	var effect: String = ab.effect.capitalize()
	if ab.effect == "damage":
		effect = "Physical" if ab.scale == "att" else "Magic"
	if ab.has("status"):
		effect += " + %s" % Jobs.STATUSES[ab.status.id].name
	_cell(grid, effect)
	_cell(grid, "Self" if ab.max_range == 0.0 else "%s-%s m" % [_num(ab.min_range), _num(ab.max_range)])
	_cell(grid, "—" if ab.aoe == 0.0 else "%s m" % _num(ab.aoe))
	_cell(grid, "Instant" if ab.cast == 0.0 else "%ss" % _num(ab.cast))
	_cell(grid, "—" if ab.cooldown == 0 else "%d turn%s" % [ab.cooldown, "" if ab.cooldown == 1 else "s"])

	var stat: int = job[ab.scale]
	var base := ""
	var versus := ""
	match ab.effect:
		"damage":
			var raw := roundi(stat * ab.power * GameState.DAMAGE_SCALE)
			var def: int = target.attdef if ab.scale == "att" else target.magdef
			var dealt := maxi(1, roundi((raw - def) * GameState.DAMAGE_MULTIPLIER))
			base = str(raw)
			versus = "%d  (%d%% of %s HP)" % [dealt, roundi(100.0 * dealt / target.hp), target.name]
		"heal":
			base = "+%d" % roundi(stat * ab.power * GameState.HEAL_SCALE)
			versus = "heals"
		"revive":
			base = "%d%% HP" % roundi(ab.power * 100)
			versus = "revives"
		_:
			base = "—"
			versus = "—"
	_cell(grid, base, Color(1, 0.6, 0.5) if ab.effect == "damage" else Color(0.6, 1, 0.65))
	_cell(grid, versus)
	var extra := ""
	if ab.has("tg"):
		extra = "  (TG %+d%%)" % ab.tg
	var text: String = ab.desc.trim_prefix("ULTIMATE: ")
	var desc := _cell(grid, text.left(1).to_upper() + text.substr(1) + extra)
	desc.modulate = Color(1, 1, 1, 0.75)


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else "%.1f" % v
