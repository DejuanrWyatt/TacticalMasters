extends Control
## Battle Setup: pick the map, both teams (4 of the 6 jobs each) and, against
## the computer, its difficulty. Writes the choices into GameConfig and emits
## `confirmed`. Used before a vs-computer, same-device or hosted online game.

signal confirmed
signal closed

const Jobs = preload("res://scripts/core/jobs.gd")
const ClassList = preload("res://scripts/ui/class_list.gd")
const ClassPicker = preload("res://scripts/ui/class_picker.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const BoardView = preload("res://scripts/battle/board_view.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var TEAM_COLORS: Array = [Settings.team_colors()[0].lightened(0.2), Settings.team_colors()[1].lightened(0.2)]
const DIFFICULTIES := ["easy", "medium", "hard"]
const PREVIEW_TILE := 26

## "ai", "hotseat" or "host" (set before adding to the tree).
var setup_mode := "ai"

var _job_ids: Array = []
var _map_buttons := {}
var _preview: GridContainer
var _map_desc: Label
var _slots: Array = [[], []]
var _saved_pickers := {}
var _team_names := {}
var _seed_field: LineEdit
var _difficulty: OptionButton
## "cpu" mode: Blue's difficulty (_difficulty is Red's).
var _difficulty_blue: OptionButton
var _win_rule: OptionButton
var _time_limit: OptionButton

## How a battle can be won, beyond knocking the other side out: the seconds a
## side must hold the middle of the map (0 = only the last team standing).
const WIN_RULES := [["Last team standing", 0.0], ["Hold the middle: 30s", 30.0], ["Hold the middle: 60s", 60.0]]
## An optional time limit; when it runs out the healthier side wins.
const TIME_LIMITS := [["No time limit", 0.0], ["3 minutes", 180.0], ["5 minutes", 300.0], ["10 minutes", 600.0]]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_job_ids = Jobs.all_jobs().keys()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	# Header.
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "BATTLE SETUP  ·  " + {"ai": "vs Computer", "cpu": "Computer vs Computer", "hotseat": "Two Players", "host": "Host Online Game"}[setup_mode]
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Back", close_setup, Vector2(110, 44)))
	var start := _button("Host Game" if setup_mode == "host" else "Start Battle", _on_start, Vector2(170, 44))
	start.add_theme_font_size_override("font_size", 16)
	header.add_child(start)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# Map picker.
	var map_panel := PanelContainer.new()
	map_panel.custom_minimum_size.x = 420
	body.add_child(map_panel)
	var map_box := VBoxContainer.new()
	map_box.add_theme_constant_override("separation", 10)
	map_panel.add_child(map_box)
	map_box.add_child(_heading("Map"))
	var map_list := HBoxContainer.new()
	map_list.add_theme_constant_override("separation", 6)
	map_box.add_child(map_list)
	var group := ButtonGroup.new()
	for id in MapData.map_ids():
		var b := _button(MapData.MAPS[id].name, _select_map.bind(id), Vector2(0, 38))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map_list.add_child(b)
		_map_buttons[id] = b
	var preview_center := CenterContainer.new()
	map_box.add_child(preview_center)
	_preview = GridContainer.new()
	_preview.add_theme_constant_override("h_separation", 1)
	_preview.add_theme_constant_override("v_separation", 1)
	preview_center.add_child(_preview)
	_map_desc = Label.new()
	_map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_desc.add_theme_color_override("font_color", UiTheme.DIM)
	map_box.add_child(_map_desc)

	# Teams.
	var teams_panel := PanelContainer.new()
	teams_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(teams_panel)
	var teams_box := VBoxContainer.new()
	teams_box.add_theme_constant_override("separation", 12)
	teams_panel.add_child(teams_box)
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 24)
	teams_box.add_child(teams)
	for team in 2:
		teams.add_child(_team_column(team))

	if setup_mode == "ai" or setup_mode == "cpu":
		teams_box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		teams_box.add_child(row)
		if setup_mode == "cpu":
			_difficulty_blue = _difficulty_picker(row, "Blue computer", GameConfig.ai_difficulty_blue)
		_difficulty = _difficulty_picker(row, "Red computer" if setup_mode == "cpu" else "Computer difficulty", GameConfig.ai_difficulty)
	# How the battle can be won.
	teams_box.add_child(HSeparator.new())
	var rules := HBoxContainer.new()
	rules.add_theme_constant_override("separation", 10)
	teams_box.add_child(rules)
	_win_rule = _rule_picker(rules, "Victory", WIN_RULES, GameConfig.battle_tuning().get("capture_seconds", 0.0))
	_time_limit = _rule_picker(rules, "Time", TIME_LIMITS, GameConfig.battle_tuning().get("battle_seconds", 0.0))
	# A seed of 0 means a fresh battle every time; any other number plays out
	# the same way again, which is how a battle can be repeated exactly.
	var seed_label := Label.new()
	seed_label.text = "Seed"
	rules.add_child(seed_label)
	_seed_field = LineEdit.new()
	_seed_field.custom_minimum_size = Vector2(110, 38)
	_seed_field.placeholder_text = "0 = random"
	_seed_field.tooltip_text = "The same seed and the same teams play out exactly the same battle. 0 picks a new one each time."
	_seed_field.text = str(GameConfig.battle_seed_setting) if GameConfig.battle_seed_setting != 0 else ""
	rules.add_child(_seed_field)

	var tip := Label.new()
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", UiTheme.DIM)
	tip.text = "Each side fields 4 units; the same job can be picked more than once. See the Unit Guide for every job's stats and abilities."
	teams_box.add_child(tip)

	_select_map(GameConfig.map_id)
	for team in 2:
		_apply_roster(team, GameConfig.rosters[team])


## A picker over one of the rule lists above, starting on the saved value.
func _rule_picker(row: HBoxContainer, text: String, entries: Array, current: float) -> OptionButton:
	var label := Label.new()
	label.text = text
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(210, 38)
	for i in entries.size():
		picker.add_item(entries[i][0])
		if is_equal_approx(float(entries[i][1]), current):
			picker.select(i)
	row.add_child(picker)
	return picker


func _difficulty_picker(row: HBoxContainer, text: String, current: String) -> OptionButton:
	var label := Label.new()
	label.text = text
	row.add_child(label)
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for level in DIFFICULTIES:
		picker.add_item(level.capitalize())
	picker.select(maxi(0, DIFFICULTIES.find(current)))
	row.add_child(picker)
	return picker


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	return l


func _button(text: String, action: Callable, size := Vector2(0, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	b.pressed.connect(action)
	return b


func _team_column(team: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading_text := "Your team (Blue)" if setup_mode != "hotseat" and setup_mode != "cpu" and team == 0 else ("Blue team" if team == 0 else "Red team")
	if setup_mode == "ai" and team == 1:
		heading_text = "Computer's team (Red)"
	elif setup_mode == "host" and team == 1:
		heading_text = "Opponent's team (Red)"
	var heading := _heading(heading_text)
	heading.add_theme_color_override("font_color", TEAM_COLORS[team])
	box.add_child(heading)
	for i in 4:
		# One button per slot: it shows what is in the slot and opens the
		# picker, which can search and filter over a hundred classes.
		var slot := Button.new()
		slot.focus_mode = Control.FOCUS_NONE
		slot.custom_minimum_size.y = 38
		slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot.add_theme_constant_override("icon_max_width", 22)
		slot.pressed.connect(_open_class_picker.bind(team, i))
		box.add_child(slot)
		_slots[team].append(slot)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	# Saved teams, on two rows so a column stays narrow: load or delete one,
	# and save what is in the slots now under a name.
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 6)
	box.add_child(load_row)
	var saved := OptionButton.new()
	saved.focus_mode = Control.FOCUS_NONE
	saved.custom_minimum_size = Vector2(0, 32)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved.tooltip_text = "Load one of your saved teams"
	load_row.add_child(saved)
	_saved_pickers[team] = saved
	saved.item_selected.connect(_load_team.bind(team))
	load_row.add_child(_button("Delete", _delete_team.bind(team), Vector2(70, 32)))
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	box.add_child(save_row)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Name this team"
	name_field.custom_minimum_size.y = 32
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(name_field)
	_team_names[team] = name_field
	save_row.add_child(_button("Save", _save_team.bind(team), Vector2(70, 32)))
	_refresh_saved(team)
	var random := _button("Random", _randomize.bind(team))
	random.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(random)
	var reset := _button("Default", _apply_roster.bind(team, Jobs.DEFAULT_ROSTER))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(reset)
	return box


func _apply_roster(team: int, roster: Array) -> void:
	for i in 4:
		var job: String = roster[i] if i < roster.size() else Jobs.DEFAULT_ROSTER[i]
		_set_slot(team, i, job if Jobs.all_jobs().has(job) else Jobs.DEFAULT_ROSTER[i])


## Puts a class in one slot and shows it on the slot's button.
func _set_slot(team: int, index: int, job_id: String) -> void:
	var button: Button = _slots[team][index]
	button.set_meta("job", job_id)
	button.text = Jobs.job(job_id).name
	button.icon = load(Jobs.icon_path(job_id))
	button.tooltip_text = "%s: %s\nClick to choose another class" % [Jobs.job(job_id).name, Jobs.role_name(job_id)]


## A team worth fielding rather than four classes out of the hat: a tank, two
## damage dealers and someone to keep them standing.
func _randomize(team: int) -> void:
	var roster := ClassList.sensible_team(_rng)
	for i in 4:
		_set_slot(team, i, roster[i])


func _roster(team: int) -> Array:
	var out := []
	for button in _slots[team]:
		out.append((button as Button).get_meta("job", Jobs.DEFAULT_ROSTER[0]))
	return out


## The saved-team dropdown for one side, kept in the order they were saved.
func _refresh_saved(team: int) -> void:
	var picker: OptionButton = _saved_pickers[team]
	picker.clear()
	picker.add_item("Saved teams...")
	for key in GameConfig.teams:
		picker.add_item(key)
	picker.select(0)


func _save_team(team: int) -> void:
	var field: LineEdit = _team_names[team]
	var team_name: String = field.text.strip_edges()
	if team_name == "":
		field.placeholder_text = "Name it first"
		return
	GameConfig.save_team(team_name, _roster(team))
	field.text = ""
	for side in 2:
		_refresh_saved(side)


func _load_team(index: int, team: int) -> void:
	var picker: OptionButton = _saved_pickers[team]
	if index <= 0:
		return
	var roster = GameConfig.teams.get(picker.get_item_text(index), [])
	if roster is Array and roster.size() == 4:
		_apply_roster(team, roster)


func _delete_team(team: int) -> void:
	var picker: OptionButton = _saved_pickers[team]
	if picker.selected <= 0:
		return
	GameConfig.delete_team(picker.get_item_text(picker.selected))
	for side in 2:
		_refresh_saved(side)


## Opens the class picker for one slot; what it hands back goes in the slot.
func _open_class_picker(team: int, index: int) -> void:
	var picker := ClassPicker.new()
	picker.picked.connect(func(id: String): _set_slot(team, index, id))
	add_child(picker)


func _select_map(map_id: String) -> void:
	if not MapData.MAPS.has(map_id):
		map_id = MapData.DEFAULT_MAP
	GameConfig.map_id = map_id
	for id in _map_buttons:
		(_map_buttons[id] as Button).set_pressed_no_signal(id == map_id)
	_map_desc.text = MapData.MAPS[map_id].desc
	_draw_preview(map_id)


## Top-down preview: one colored square per ground block, spawn areas tinted.
func _draw_preview(map_id: String) -> void:
	for child in _preview.get_children():
		child.queue_free()
	var rows := MapData.rows(map_id)
	_preview.columns = (rows[0] as String).length()
	var spawn_tiles := {}
	var info: Dictionary = MapData.MAPS[map_id]
	var size := Vector2(_preview.columns, rows.size())
	for p in info.spawns:
		spawn_tiles[Vector2i(p / MapData.TILE_SIZE)] = 0
		spawn_tiles[Vector2i((size * MapData.TILE_SIZE - p) / MapData.TILE_SIZE)] = 1
	for y in rows.size():
		for x in (rows[y] as String).length():
			var ch: String = rows[y][x]
			var level := MapData.char_level(ch)
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(PREVIEW_TILE, PREVIEW_TILE)
			var color: Color = BoardView.GROUND_COLORS[mini(level, BoardView.GROUND_COLORS.size() - 1)]
			# Brighter = higher.
			color = color.lightened(0.08 * maxi(0, level - 1))
			# Embers, springs and rocks keep their own colors.
			var hazard := MapData.char_hazard(ch)
			if hazard < 0:
				color = BoardView.EMBER_COLOR
			elif hazard > 0:
				color = BoardView.SPRING_COLOR
			elif MapData.char_is_cover(ch):
				color = BoardView.ROCK_COLOR
			if spawn_tiles.has(Vector2i(x, y)):
				color = color.lerp(TEAM_COLORS[spawn_tiles[Vector2i(x, y)]], 0.7)
			cell.color = color
			_preview.add_child(cell)


func _on_start() -> void:
	GameConfig.rosters = [_roster(0), _roster(1)]
	if _difficulty != null:
		GameConfig.ai_difficulty = DIFFICULTIES[_difficulty.selected]
	if _difficulty_blue != null:
		GameConfig.ai_difficulty_blue = DIFFICULTIES[_difficulty_blue.selected]
	if _win_rule != null:
		GameConfig.set_tuning("capture_seconds", float(WIN_RULES[_win_rule.selected][1]))
	if _time_limit != null:
		GameConfig.set_tuning("battle_seconds", float(TIME_LIMITS[_time_limit.selected][1]))
	if _seed_field != null:
		GameConfig.battle_seed_setting = maxi(0, _seed_field.text.strip_edges().to_int())
	confirmed.emit()


func close_setup() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_setup()
		get_viewport().set_input_as_handled()
