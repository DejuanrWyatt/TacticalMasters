extends Control
## Battle Setup: pick the map, both teams (4 of the 6 jobs each) and, against
## the computer, its difficulty. Writes the choices into GameConfig and emits
## `confirmed`. Used before a vs-computer, same-device or hosted online game.

signal confirmed
signal closed

const Jobs = preload("res://scripts/core/jobs.gd")
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
var _difficulty: OptionButton
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_job_ids = Jobs.JOBS.keys()
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
	title.text = "BATTLE SETUP  ·  " + {"ai": "vs Computer", "hotseat": "Two Players", "host": "Host Online Game"}[setup_mode]
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
	map_panel.custom_minimum_size.x = 470
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

	if setup_mode == "ai":
		teams_box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		teams_box.add_child(row)
		var label := Label.new()
		label.text = "Computer difficulty"
		row.add_child(label)
		_difficulty = OptionButton.new()
		_difficulty.focus_mode = Control.FOCUS_NONE
		for level in DIFFICULTIES:
			_difficulty.add_item(level.capitalize())
		_difficulty.select(maxi(0, DIFFICULTIES.find(GameConfig.ai_difficulty)))
		row.add_child(_difficulty)
	var tip := Label.new()
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_color_override("font_color", UiTheme.DIM)
	tip.text = "Each side fields 4 units; the same job can be picked more than once. See the Unit Guide for every job's stats and abilities."
	teams_box.add_child(tip)

	_select_map(GameConfig.map_id)
	for team in 2:
		_apply_roster(team, GameConfig.rosters[team])


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
	var heading_text := "Your team (Blue)" if setup_mode != "hotseat" and team == 0 else ("Blue team" if team == 0 else "Red team")
	if setup_mode == "ai" and team == 1:
		heading_text = "Computer's team (Red)"
	elif setup_mode == "host" and team == 1:
		heading_text = "Opponent's team (Red)"
	var heading := _heading(heading_text)
	heading.add_theme_color_override("font_color", TEAM_COLORS[team])
	box.add_child(heading)
	for i in 4:
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		picker.custom_minimum_size.y = 38
		for id in _job_ids:
			picker.add_item(Jobs.JOBS[id].name)
		box.add_child(picker)
		_slots[team].append(picker)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
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
		(_slots[team][i] as OptionButton).select(maxi(0, _job_ids.find(job)))


func _randomize(team: int) -> void:
	for picker in _slots[team]:
		(picker as OptionButton).select(_rng.randi_range(0, _job_ids.size() - 1))


func _roster(team: int) -> Array:
	var out := []
	for picker in _slots[team]:
		out.append(_job_ids[(picker as OptionButton).selected])
	return out


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
			var level := 0 if ch == "~" else ch.to_int()
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(PREVIEW_TILE, PREVIEW_TILE)
			var color: Color = BoardView.GROUND_COLORS[mini(level, BoardView.GROUND_COLORS.size() - 1)]
			# Brighter = higher.
			color = color.lightened(0.08 * maxi(0, level - 1))
			if spawn_tiles.has(Vector2i(x, y)):
				color = color.lerp(TEAM_COLORS[spawn_tiles[Vector2i(x, y)]], 0.7)
			cell.color = color
			_preview.add_child(cell)


func _on_start() -> void:
	GameConfig.rosters = [_roster(0), _roster(1)]
	if _difficulty != null:
		GameConfig.ai_difficulty = DIFFICULTIES[_difficulty.selected]
	confirmed.emit()


func close_setup() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_setup()
		get_viewport().set_input_as_handled()
