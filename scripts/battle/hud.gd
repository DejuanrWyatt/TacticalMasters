extends CanvasLayer
## All 2D battle UI, kept compact so the battlefield stays visible:
##   top           turn order bars, one per team (an icon chip per unit with
##                 a time badge: READY countdown, cast, or time until ready)
##   top right     Log / Units / Pause / Menu buttons
##   left          the combat log window (movable, resizable) and the stats
##                 card of a clicked ally; a clicked enemy's card is on the right
##   bottom left   the selected unit's card: HP / TG / Ultimate bars and stats
##   bottom center action bar (Move, abilities 1-4, End Turn), with the
##                 hover preview floating just above it
## plus the game-over panel and the overlays: in-game menu, Options and the
## Unit Guide. Everything shares one theme (ui_theme.gd). Key names on
## buttons follow the player's key bindings.

signal move_pressed
signal sprint_pressed
signal ability_pressed(slot: int)
signal end_turn_pressed
signal menu_pressed
signal surrender_pressed
signal ready_pressed
signal layout_editing_changed(editing: bool)
signal pause_pressed
signal chip_pressed(unit_id: int)
## An overlay (menu, Options or Unit Guide) opened or closed.
signal overlay_changed(open: bool)
signal rematch_pressed
signal replay_pressed
signal replay_speed_changed(speed: float)
## A point in the replay to jump to, from 0 (the start) to 1 (the end).
signal replay_seek(fraction: float)
signal replay_step_pressed
signal replay_back_pressed
signal replay_pause_pressed
signal replay_results_pressed
signal chat_submitted(text: String)
signal chat_toggled(open: bool)
signal tuning_changed(values: Dictionary)
signal inspect_closed

const GameState = preload("res://scripts/core/game_state.gd")
const Jobs = preload("res://scripts/core/jobs.gd")
const UnitGuide = preload("res://scripts/ui/unit_guide.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const OptionsMenu = preload("res://scripts/ui/options_menu.gd")
const HowToPlay = preload("res://scripts/ui/how_to_play.gd")
const DevTools = preload("res://scripts/ui/dev_tools.gd")
const LogWindow = preload("res://scripts/ui/log_window.gd")
const LayoutEditor = preload("res://scripts/ui/layout_editor.gd")

const TEXT := Color(0.92, 0.94, 1.0)
## Turn order timeline: two parallel bars, one per team. Chips slide along
## their team's bar toward its READY zone at the left end, placed by seconds
## until ready; far-off turns are drawn smaller.
## Room kept at the top right for the Units / Pause / Menu buttons.
const TIMELINE_RIGHT_MARGIN := 310.0
const TICK_SECONDS := [0, 1, 3, 5, 10, 20, 30]
const TIMELINE_SECONDS := 30.0  # the far (right) end of the bar
## Each team's row: its bar, with the icon chips sitting on it at each
## unit's time. Icons that come close together merge into one framed group,
## side by side around the group's average time (each still clickable).
const ROW_HEIGHT := 42.0
## Icons closer than this (in pixels) join a group.
const MERGE_DISTANCE := 4.0
const READY_SLOTS := 4
## Chips are uniform squares: the class icon, with a small time badge.
const CHIP_SIZE := Vector2(36, 36)
const CHIP_GAP := 3.0
const CHIP_MIN_SCALE := 0.75
const TRACK_START := READY_SLOTS * (CHIP_SIZE.x + CHIP_GAP) + 10
## Height of a team's bar line within its row (chips are centered on it).
const BAR_Y := CHIP_SIZE.y * 0.5 + 2
## Time until ready shows this long after a turn ends and before it's ready.
const SHOW_TIME_SECONDS := 3.0
const DIM := Color(0.92, 0.94, 1.0, 0.55)
const GOLD := Color(1.0, 0.82, 0.35)
const URGENT := Color(1.0, 0.38, 0.32)
const CAST := Color(0.75, 0.45, 1.0)
const PANEL_BG := Color(0.06, 0.08, 0.12, 0.78)
## A fixed turn square (the other turn order display).
const SQUARE_SIZE := Vector2(44, 48)

var _root: Control
var _timeline: Control
var _team_bars: Array[ColorRect] = []
## Frames behind merged groups of chips (reused), under the chips.
var _frame_layer: Control
var _frames: Array[Panel] = []
var _bar_ticks: Array[ColorRect] = []
var _bars_width := -1.0
var _chips: Array[Button] = []
var _chip_for := {}
var _icons := {}
## Stats cards for an inspected unit: "left" (allies) and "right" (enemies).
var _inspect := {}
var _chip_styles := {}
var _guide_button: Button
var _pause_button: Button
var _card: PanelContainer
var _title: Label
var _subtitle: Label
var _hp_bar: ProgressBar
var _tg_bar: ProgressBar
var _ult_bar: ProgressBar
var _stats: Label
var _action_bar: PanelContainer
var _move_button: Button
var _sprint_button: Button
## Which ability button the mouse is over (-1 for none), and what to say
## about it: the battle shows this in the hover preview.
var _hovered_ability := -1
var _ability_buttons: Array[Button] = []
var _end_button: Button
var _hover_panel: PanelContainer
var _hover: Label
var _log: LogWindow
var _log_button: Button
var _game_over: Control
var _game_over_label: Label
var _game_over_sub: Label
var _stats_grid: GridContainer
var _mvp_label: Label
var _rematch_button: Button
var _replay_button: Button
var _replay_bar: PanelContainer
var _replay_slider: HSlider
var _replay_pause_button: Button
var _chat: LineEdit
var _guide: Control
var _options: Control
var _game_menu: Control
var _surrender_button: Button
var _field_button: Button
var _objective: Label
var _planning: PanelContainer
var _planning_label: Label
var _ready_button: Button
## The fixed turn squares (Settings.turn_icons), by unit id.
var _squares_box: Control
var _square_rows: Array[HBoxContainer] = []
var _squares := {}
var _field: PanelContainer
var _field_box: VBoxContainer
var _field_rows := {}
## Dragging the panels around (Edit layout) and the bar shown while doing it.
var _layout: LayoutEditor
var _layout_bar: PanelContainer
var _how_to: Control
var _dev_tools: Control
## The battle's rules, for the calculation tooltips (set by Battle).
var game_state
## True when Developer Tools changes apply to this battle right away.
var dev_tools_live := false
## What the unit card's tooltips were last built from.
var _card_tip_sig := ""
## The row under the selected unit's card showing what is aimed at it.
var _incoming: HFlowContainer


func build(can_pause: bool) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)

	_build_turn_order()
	_build_turn_squares()
	_build_planning()
	_build_objective()
	_build_field()
	_build_corner_buttons(can_pause)
	_build_log()
	_build_chat()
	_build_unit_card()
	_build_action_bar()
	_build_game_over()
	_build_game_menu()
	_build_layout_bar()

	_layout = LayoutEditor.new()
	_root.add_child(_layout)
	_register_layout()
	Keybinds.changed.connect(_update_key_labels)
	_update_key_labels()


## Everything the player may drag around in Edit layout.
func _register_layout() -> void:
	_layout.register("turn_order", _timeline, "Turn order bars")
	_layout.register("turn_cards_blue", _square_rows[0], "Turn cards: first team")
	_layout.register("turn_cards_red", _square_rows[1], "Turn cards: second team")
	_layout.register("objective", _objective, "Objective line")
	_layout.register("planning", _planning, "Planning banner")
	_layout.register("unit_card", _card, "Selected unit")
	_layout.register("action_bar", _action_bar, "Action bar")
	_layout.register("hover", _hover_panel, "Hover preview")
	_layout.register("field", _field, "Field list")
	_layout.register("inspect_left", _inspect.left.card if _inspect.has("left") else null, "Ally card")
	_layout.register("inspect_right", _inspect.right.card if _inspect.has("right") else null, "Enemy card")


## Turns Edit layout on or off, with a banner while it is on.
func toggle_layout_editing() -> void:
	# The stats cards are built the first time a unit is clicked, so they are
	# registered whenever editing starts rather than only at build time.
	if _inspect.has("left"):
		_layout.register("inspect_left", _inspect.left.card, "Ally card")
		_layout.register("inspect_right", _inspect.right.card, "Enemy card")
	var on := not _layout.is_editing()
	_layout.set_editing(on)
	_layout_bar.visible = on
	if on and _game_menu.visible:
		toggle_game_menu()
	layout_editing_changed.emit(on)


func is_layout_editing() -> bool:
	return _layout != null and _layout.is_editing()


## The bar shown while the layout is being edited.
func _build_layout_bar() -> void:
	_layout_bar = PanelContainer.new()
	_layout_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_layout_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layout_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layout_bar.offset_bottom = -120
	_layout_bar.visible = false
	_layout_bar.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(0.45, 0.8, 1.0, 0.9), 1, 10, Vector2(14, 8)))
	_root.add_child(_layout_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_layout_bar.add_child(row)
	var hint := Label.new()
	hint.text = "Edit layout: drag anything to move it, or a turn card to reorder its team"
	hint.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	_menu_button(row, "Reset layout", func(): _layout.reset()).custom_minimum_size = Vector2(120, 32)
	_menu_button(row, "Done", toggle_layout_editing).custom_minimum_size = Vector2(90, 32)


# --- Theme -----------------------------------------------------------------

static func _box(bg: Color, border := Color(0, 0, 0, 0), border_width := 0, radius := 8, pad := Vector2(10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	return s


# --- Layout ----------------------------------------------------------------

func _build_turn_order() -> void:
	# Across the top, from the left edge to the corner buttons.
	_timeline = Control.new()
	_timeline.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timeline.offset_left = 12
	_timeline.offset_right = -TIMELINE_RIGHT_MARGIN
	_timeline.offset_top = 8
	_timeline.offset_bottom = 8 + 2 * ROW_HEIGHT
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_timeline)
	# One bar per team (Blue on top, Red below), each running from its READY
	# zone to the far end, with ticks at 1, 3, 5, 10, 20 and 30 s.
	for team in 2:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.14)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timeline.add_child(line)
		_team_bars.append(line)
		for sec in TICK_SECONDS:
			var tick := ColorRect.new()
			tick.color = GOLD if sec == 0 else Color(1, 1, 1, 0.22)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tick.set_meta("seconds", sec)
			tick.set_meta("team", team)
			_timeline.add_child(tick)
			_bar_ticks.append(tick)
	_frame_layer = Control.new()
	_frame_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline.add_child(_frame_layer)


## Places the bars and ticks for the timeline's current width.
func _layout_bars() -> void:
	_bars_width = _timeline.size.x
	for team in 2:
		var y := team * ROW_HEIGHT + BAR_Y
		_team_bars[team].position = Vector2(TRACK_START, y - 1.5)
		_team_bars[team].size = Vector2(maxf(0.0, _bars_width - TRACK_START), 3)
	for tick in _bar_ticks:
		var sec: float = tick.get_meta("seconds")
		var y: float = tick.get_meta("team") * ROW_HEIGHT + BAR_Y
		tick.position = Vector2(_bar_x(sec) - 1, y - (5 if sec == 0 else 3))
		tick.size = Vector2(2, 10 if sec == 0 else 6)


## Where on the bar a turn this many seconds away sits. A square-root scale
## gives the last seconds before READY the most room.
func _bar_x(seconds: float) -> float:
	var frac := sqrt(clampf(seconds / TIMELINE_SECONDS, 0.0, 1.0))
	return TRACK_START + frac * (_bars_width - TRACK_START - CHIP_SIZE.x * 0.5)


## A line under the turn bars: the time left, and who is holding the middle.
## The other way of showing turn order (Options): one fixed square per unit
## instead of chips sliding along a bar. A square is gold with a flashing
## border while that unit can act, and grey with a red meter filling from the
## bottom while its gauge refills.
func _build_turn_squares() -> void:
	# One group per team, each of which can be picked up and moved on its own
	# (Edit layout), and whose cards can be reordered inside it.
	_squares_box = Control.new()
	_squares_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_squares_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squares_box.visible = false
	_root.add_child(_squares_box)
	for team in 2:
		var team_row := HBoxContainer.new()
		team_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		team_row.offset_left = 12 + team * 4 * (SQUARE_SIZE.x + 4) + team * 24
		team_row.offset_top = 8
		team_row.add_theme_constant_override("separation", 4)
		_squares_box.add_child(team_row)
		_square_rows.append(team_row)


## One square, built the first time its unit needs one.
func _new_square(unit_id: int, team: int) -> Panel:
	var square := Panel.new()
	square.custom_minimum_size = SQUARE_SIZE
	square.set_meta("unit_id", unit_id)
	square.set_meta("team", team)
	square.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.1, 0.85), Color(1, 1, 1, 0.2), 2, 6, Vector2.ZERO))
	# The meter sits behind the icon and grows from the bottom.
	var meter := ColorRect.new()
	meter.name = "Meter"
	# Anchored along the bottom edge and grown upward by its offset, so the
	# meter fills the square from the bottom instead of spilling below it.
	meter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square.add_child(meter)
	var button := Button.new()
	button.name = "Pick"
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(func(): chip_pressed.emit(unit_id))
	button.gui_input.connect(_on_square_input.bind(square, team))
	square.add_child(button)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5
	icon.offset_top = 3
	icon.offset_right = -5
	icon.offset_bottom = -13
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square.add_child(icon)
	var badge := Label.new()
	badge.name = "Badge"
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	badge.offset_top = -13
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 9)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	square.add_child(badge)
	_square_rows[team].add_child(square)
	_squares[unit_id] = square
	return square


## While the layout is being edited, dragging a card moves it along its
## team's row: where it is dropped decides its new place.
func _on_square_input(event: InputEvent, square: Panel, team: int) -> void:
	if not is_layout_editing() or not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	var row: HBoxContainer = _square_rows[team]
	var dropped_at: float = event.global_position.x + square.global_position.x
	var place := 0
	for other in row.get_children():
		if other != square and other.global_position.x + other.size.x * 0.5 < dropped_at:
			place += 1
	row.move_child(square, clampi(place, 0, row.get_child_count() - 1))
	_save_square_order()


## Remembers the order of each team's cards with the rest of the layout.
func _save_square_order() -> void:
	var order := {}
	for team in 2:
		var ids := []
		for square in _square_rows[team].get_children():
			ids.append(int(square.get_meta("unit_id", -1)))
		order[str(team)] = ids
	_layout.set_extra("turn_card_order", order)


## Puts the cards back in the order the player left them in.
func _apply_square_order() -> void:
	var order: Dictionary = _layout.get_extra("turn_card_order", {})
	for team in 2:
		var ids = order.get(str(team), [])
		if not (ids is Array):
			continue
		var place := 0
		for id in ids:
			var square: Panel = _squares.get(int(id), null)
			if square != null and square.get_parent() == _square_rows[team]:
				_square_rows[team].move_child(square, place)
				place += 1


## Fills the fixed squares from the same entries the bars use.
func _update_squares(entries: Array) -> void:
	# A slow pulse for the border of whoever can act right now.
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 180.0)
	for e in entries:
		var square: Panel = _squares.get(e.id, null)
		if square == null:
			square = _new_square(e.id, e.team)
			_apply_square_order()
		var icon := square.get_node("Icon") as TextureRect
		var wanted := _icon(Jobs.icon_path(e.job)) if not e.hidden else null
		if icon.texture != wanted:
			icon.texture = wanted
		var meter := square.get_node("Meter") as ColorRect
		var style: StyleBoxFlat = square.get_theme_stylebox("panel")
		if e.ready:
			# Its turn: gold, with the meter draining as its countdown runs out.
			style.bg_color = Color(0.45, 0.35, 0.08, 0.9)
			style.border_color = Color(GOLD, pulse)
			meter.color = Color(1.0, 0.82, 0.35, 0.35)
			meter.offset_top = -SQUARE_SIZE.y * float(e.get("ready_left", 1.0))
			icon.modulate = Color(1, 1, 1, 1)
			_set_text(square.get_node("Badge") as Label, "%ds" % ceili(e.seconds))
			_set_color(square.get_node("Badge") as Label, GOLD)
		else:
			# Waiting: grey, with the meter filling up to its next turn.
			style.bg_color = Color(0.07, 0.08, 0.11, 0.85)
			style.border_color = Color(1, 1, 1, 0.2)
			meter.color = Color(0.8, 0.25, 0.2, 0.45)
			meter.offset_top = -SQUARE_SIZE.y * float(e.get("tg", 0.0))
			icon.modulate = Color(0.55, 0.58, 0.62, 1)
			var casting: bool = e.casting != ""
			_set_text(square.get_node("Badge") as Label, "%.1fs" % e.cast_seconds if casting else "%ds" % ceili(e.seconds))
			_set_color(square.get_node("Badge") as Label, CAST if casting else DIM)
		square.modulate.a = 0.45 if e.hidden else 1.0
		_set_tip(square, e.tip)


## The planning banner: how long is left to place units, and the button that
## says this side is done.
func _build_planning() -> void:
	_planning = PanelContainer.new()
	_planning.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_planning.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_planning.offset_top = 96
	_planning.visible = false
	_planning.add_theme_stylebox_override("panel", _box(PANEL_BG, GOLD, 1, 10, Vector2(14, 8)))
	_root.add_child(_planning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_planning.add_child(row)
	_planning_label = Label.new()
	_planning_label.add_theme_color_override("font_color", GOLD)
	_planning_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_planning_label)
	_ready_button = _small_button(row, "Ready", ready_pressed.emit)
	_ready_button.custom_minimum_size = Vector2(90, 30)
	_ready_button.tooltip_text = "Start the battle without waiting for the rest of the planning time"


## Shows the planning banner (an empty text hides it).
func set_planning(text: String, can_ready: bool) -> void:
	_planning.visible = text != ""
	_set_text(_planning_label, text)
	_ready_button.visible = can_ready


func _build_objective() -> void:
	_objective = Label.new()
	_objective.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective.offset_top = 8 + 2 * ROW_HEIGHT + 2
	_objective.offset_bottom = _objective.offset_top + 22
	_objective.offset_right = -TIMELINE_RIGHT_MARGIN
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_font_size_override("font_size", 13)
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.visible = false
	_root.add_child(_objective)


## Shows (or, with an empty text, hides) the objective line.
func set_objective(text: String) -> void:
	if _objective.text == text:
		return
	_objective.text = text
	_objective.visible = text != ""


## Both teams down the left edge: icon, name, health, statuses and whether
## the unit is ready. Clicking a row picks that unit, like its chip.
func _build_field() -> void:
	_field = PanelContainer.new()
	_field.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_field.grow_vertical = Control.GROW_DIRECTION_BOTH
	_field.offset_left = 10
	_field.add_theme_stylebox_override("panel", _box(Color(0.03, 0.05, 0.08, 0.86), Color(1, 1, 1, 0.12), 1, 8, Vector2(8, 8)))
	_field.visible = false
	_root.add_child(_field)
	_field_box = VBoxContainer.new()
	_field_box.add_theme_constant_override("separation", 2)
	_field.add_child(_field_box)


func toggle_field() -> void:
	_field.visible = not _field.visible


func is_field_open() -> bool:
	return _field != null and _field.visible


## One row, built the first time its unit shows up.
func _field_row(unit_id: int) -> Button:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.flat = true
	row.custom_minimum_size = Vector2(228, 28)
	row.set_meta("unit_id", unit_id)
	row.pressed.connect(func(): chip_pressed.emit(unit_id))
	var box := HBoxContainer.new()
	box.name = "Row"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size.x = 76
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var bar := _gauge(box, Color(0.35, 0.82, 0.4))
	bar.name = "HP"
	bar.custom_minimum_size = Vector2(56, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state_label := Label.new()
	state_label.name = "State"
	state_label.custom_minimum_size.x = 44
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.add_theme_font_size_override("font_size", 11)
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(state_label)
	_field_box.add_child(row)
	_field_rows[unit_id] = row
	return row


## Fills the panel. Each entry: id, team, job, name, hp, max_hp, state, tags,
## color, selected, hidden.
func set_field(entries: Array) -> void:
	if not is_field_open():
		return
	for entry in entries:
		var row: Button = _field_rows.get(entry.id, null)
		if row == null:
			row = _field_row(entry.id)
		var icon := row.get_node("Row/Icon") as TextureRect
		var wanted := _icon(Jobs.icon_path(entry.job)) if not entry.hidden else null
		if icon.texture != wanted:
			icon.texture = wanted
		_set_text(row.get_node("Row/Name") as Label, entry.name)
		_set_color(row.get_node("Row/Name") as Label, entry.color)
		_set_gauge(row.get_node("Row/HP") as ProgressBar, entry.hp, entry.max_hp,
			"%d" % entry.hp if not entry.hidden else "?", URGENT if entry.hp < entry.max_hp * 0.35 else Color(0.35, 0.82, 0.4))
		_set_text(row.get_node("Row/State") as Label, entry.state)
		_set_color(row.get_node("Row/State") as Label, GOLD if entry.get("ready", false) else DIM)
		_set_tip(row, entry.get("tip", ""))
		row.modulate.a = 0.5 if entry.hidden else 1.0


func _build_corner_buttons(can_pause: bool) -> void:
	var corner := HBoxContainer.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_top = 8
	corner.offset_right = -10
	corner.add_theme_constant_override("separation", 4)
	_root.add_child(corner)
	_log_button = _small_button(corner, "Log", toggle_log)
	_log_button.tooltip_text = "Show or hide the combat log (drag its title to move it, its corner to resize it)"
	_field_button = _small_button(corner, "Field", toggle_field)
	_field_button.tooltip_text = "Show or hide the list of every unit on the field"
	_guide_button = _small_button(corner, "Units", toggle_guide)
	_pause_button = _small_button(corner, "Pause", pause_pressed.emit)
	_pause_button.visible = can_pause
	_small_button(corner, "Menu", toggle_game_menu)


func _build_chat() -> void:
	_chat = LineEdit.new()
	_chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_chat.offset_left = 12
	_chat.offset_top = 12
	_chat.custom_minimum_size = Vector2(360, 36)
	_chat.placeholder_text = "Say something (Enter to send, Esc to close)"
	_chat.max_length = 120
	_chat.visible = false
	_chat.text_submitted.connect(_on_chat_submitted)
	_chat.gui_input.connect(_on_chat_input)
	_root.add_child(_chat)


func open_chat() -> void:
	# Just under the combat log (or where it would be).
	_chat.position = Vector2(_log.position.x, _log.position.y + (_log.size.y + 4 if _log.visible else 0.0))
	_chat.visible = true
	_chat.text = ""
	_chat.grab_focus()
	chat_toggled.emit(true)


func close_chat() -> void:
	_chat.visible = false
	_chat.release_focus()
	chat_toggled.emit(false)


func is_chat_open() -> bool:
	return _chat.visible


func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() != "":
		chat_submitted.emit(text.strip_edges())
	close_chat()


func _on_chat_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_chat()
		_chat.accept_event()


func _build_log() -> void:
	_log = LogWindow.new()
	_root.add_child(_log)
	_log.visibility_toggled.connect(func(shown: bool): _set_color(_log_button, TEXT if shown else DIM))


func _build_unit_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = 10
	_card.offset_bottom = -10
	_card.custom_minimum_size.x = 250
	_root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_card.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", DIM)
	box.add_child(_subtitle)
	_hp_bar = _gauge(box, Color(0.35, 0.82, 0.4))
	_tg_bar = _gauge(box, Color(0.4, 0.65, 1.0))
	_ult_bar = _gauge(box, Color(1.0, 0.7, 0.2))
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 11)
	_stats.add_theme_color_override("font_color", DIM)
	box.add_child(_stats)
	_incoming = _incoming_row(box)
	# Hovering these shows how their numbers are calculated.
	for part in [_title, _subtitle, _hp_bar, _tg_bar, _ult_bar, _stats]:
		part.mouse_filter = Control.MOUSE_FILTER_PASS


## A stats card for a clicked unit that isn't taking orders: allies on the
## left, enemies on the right.
func _build_inspect_card(right: bool) -> Dictionary:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT if right else Control.PRESET_CENTER_LEFT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	if right:
		card.offset_right = -10
	else:
		card.offset_left = 10
	card.offset_top = -20
	card.custom_minimum_size.x = 240
	card.visible = false
	_root.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close"
	close.pressed.connect(inspect_closed.emit)
	head.add_child(close)
	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(sub)
	var hp := _gauge(box, Color(0.35, 0.82, 0.4))
	var tg := _gauge(box, Color(0.4, 0.65, 1.0))
	var ult := _gauge(box, Color(1.0, 0.7, 0.2))
	var stats := Label.new()
	stats.add_theme_font_size_override("font_size", 12)
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(stats)
	var abilities := VBoxContainer.new()
	abilities.add_theme_constant_override("separation", 1)
	box.add_child(abilities)
	box.add_child(_ability_legend())
	var incoming := _incoming_row(box)
	for part in [hp, tg, ult]:
		part.mouse_filter = Control.MOUSE_FILTER_PASS
	return {"card": card, "title": title, "sub": sub, "hp": hp, "tg": tg, "ult": ult, "stats": stats,
		"abilities": abilities, "incoming": incoming}


## What the colors on the ability list mean, in a small block under it.
func _ability_legend() -> Control:
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 8)
	legend.add_theme_constant_override("v_separation", 1)
	legend.tooltip_text = "What each ability does"
	for id in Jobs.ABILITY_CLASSES:
		var entry: Dictionary = Jobs.ABILITY_CLASSES[id]
		var swatch := Label.new()
		swatch.text = "● " + entry.name
		swatch.add_theme_font_size_override("font_size", 9)
		swatch.add_theme_color_override("font_color", entry.color)
		swatch.mouse_filter = Control.MOUSE_FILTER_PASS
		legend.add_child(swatch)
	return legend


## One row of the ability list: its icon, then its name.
func _ability_row(parent: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(icon)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_label)
	parent.add_child(row)
	return row


## Shows a unit's stats on the left (ally) or right (enemy) card; null hides both.
func show_inspect(u, enemy: bool, title: String, color: Color, seconds: float) -> void:
	if _inspect.is_empty():
		_inspect = {"left": _build_inspect_card(false), "right": _build_inspect_card(true)}
	var side := "right" if enemy else "left"
	for key in _inspect:
		_inspect[key].card.visible = u != null and key == side
	if u == null:
		return
	var c: Dictionary = _inspect[side]
	_set_text(c.title, title)
	_set_color(c.title, color.lightened(0.4))
	var sub := "KNOCKED OUT" if u.is_ko() else ("READY · %ds left" % ceili(seconds) if u.ready else "Ready in %.1fs" % seconds)
	if u.is_casting():
		sub += "  ·  casting %s" % u.casting.name
	for s in u.statuses:
		sub += "  ·  %s" % Jobs.STATUSES[s.id].tag
	_set_text(c.sub, sub)
	_fill_incoming(c.incoming, u)
	_set_gauge(c.hp, u.hp, u.max_hp(), "HP  %d / %d" % [u.hp, u.max_hp()])
	if u.ready:
		_set_gauge(c.tg, 1.0, 1.0, "TG  READY", GOLD)
	else:
		_set_gauge(c.tg, u.tg, GameState.TG_MAX, "TG  %d%%" % GameState.tg_percent(u))
	_set_gauge(c.ult, u.ult, 100, "ULT  %d%%" % u.ult, Color(1, 0.95, 0.6) if u.ult >= 100 else Color(0, 0, 0, 0))
	var move: float = game_state.move_of(u) if game_state != null else float(u.stat("move"))
	var sight: float = game_state.sight_of(u) if game_state != null else float(u.stat("sight"))
	_set_text(c.stats, "Power %d   AttDef %d   MagDef %d\nA-Eva %d%%   M-Eva %d%%   Crit %d%%\nSpeed %d   Patience %d\nMove %s m   Sight %s m" % [
		u.stat("power"), u.stat("attdef"), u.stat("magdef"), u.stat("aeva"), u.stat("meva"), u.stat("crit"),
		u.stat("speed"), u.stat("patience"), GameState._n(move), GameState._n(sight)])
	var rows: Array = c.abilities.get_children()
	while rows.size() < 4:
		rows.append(_ability_row(c.abilities))
	for i in 4:
		var ab: Dictionary = u.ability(i)
		var note := ""
		if i == 3:
			note = "  (ULT %d%%)" % u.ult if u.ult < 100 else "  (ULT ready)"
		elif u.cooldowns[i] > 0:
			note = "  (wait %d)" % u.cooldowns[i]
		var row: HBoxContainer = rows[i]
		var name_label := row.get_node("Name") as Label
		var icon := row.get_node("Icon") as TextureRect
		var ab_id: String = u.job_data().abilities[i]
		if icon.get_meta("ability_id", "") != ab_id:
			icon.set_meta("ability_id", ab_id)
			icon.texture = _icon(Jobs.ability_icon_path(ab_id))
		_set_text(name_label, "%s  %s%s" % ["U" if i == 3 else str(i + 1), ab.name, note])
		# Colored by what the ability is for (the legend under the list).
		var ability_class: String = Jobs.ability_class(ab)
		var tint: Color = Jobs.ABILITY_CLASSES[ability_class].color
		_set_color(name_label, tint if u.cooldowns[i] == 0 and not (i == 3 and u.ult < 100) else tint.darkened(0.35))
		icon.modulate = Color(1, 1, 1, 1.0 if u.cooldowns[i] == 0 else 0.5)
		if game_state != null:
			_set_tip(row, "%s  ·  %s\n\n%s" % [ab.desc, Jobs.ABILITY_CLASSES[ability_class].name,
				game_state.explain_ability(u, i)])
	if game_state != null:
		_set_tip(c.tg, game_state.explain_turn(u))
		_set_tip(c.sub, game_state.explain_countdown(u) + "\n" + game_state.explain_turn(u))
		_set_tip(c.stats, "%s\n%s\n%s%s" % [game_state.explain_move(u), game_state.explain_sight(u),
			game_state.explain_countdown(u), _buff_text(u)])


func _build_action_bar() -> void:
	_action_bar = PanelContainer.new()
	_action_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.offset_bottom = -10
	_action_bar.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(1, 1, 1, 0.07), 1, 12, Vector2(6, 6)))
	_root.add_child(_action_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	_action_bar.add_child(row)
	_move_button = _action_button(row, move_pressed.emit)
	_sprint_button = _action_button(row, sprint_pressed.emit)
	_sprint_button.tooltip_text = "Walk further than a normal move, but it counts as the unit's action: no ability afterwards."
	for i in 4:
		var b := _action_button(row, ability_pressed.emit.bind(i))
		b.add_theme_constant_override("icon_max_width", 22)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		# Hovering a button shows what the ability does right away, in the
		# preview above the bar, instead of waiting for a tooltip.
		b.mouse_entered.connect(func(): _hovered_ability = i)
		b.mouse_exited.connect(func(): _hovered_ability = -1 if _hovered_ability == i else _hovered_ability)
		_ability_buttons.append(b)
	_end_button = _action_button(row, end_turn_pressed.emit)
	_end_button.toggle_mode = false

	# Hover preview floats just above the action bar.
	_hover_panel = PanelContainer.new()
	_hover_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hover_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hover_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hover_panel.offset_bottom = -88
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_theme_stylebox_override("panel", _box(Color(0.04, 0.05, 0.08, 0.7), Color(0, 0, 0, 0), 0, 8, Vector2(10, 4)))
	_hover_panel.visible = false
	_root.add_child(_hover_panel)
	_hover = Label.new()
	_hover.add_theme_font_size_override("font_size", 13)
	_hover.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover.custom_minimum_size.x = 640
	_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_panel.add_child(_hover)


func _build_game_over() -> void:
	_game_over = PanelContainer.new()
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_over.visible = false
	_root.add_child(_game_over)
	_game_over.add_theme_stylebox_override("panel", _box(Color(0.05, 0.07, 0.1, 0.94), Color(GOLD, 0.35), 1, 12, Vector2(20, 16)))
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 560
	box.add_theme_constant_override("separation", 12)
	_game_over.add_child(box)
	_game_over_label = Label.new()
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.add_theme_font_size_override("font_size", 36)
	_game_over_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_game_over_label)
	# Whatever else there is to say about the ending: how close it was on
	# health, how long the battle ran.
	_game_over_sub = Label.new()
	_game_over_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_sub.add_theme_font_size_override("font_size", 15)
	_game_over_sub.add_theme_color_override("font_color", DIM)
	box.add_child(_game_over_sub)
	_mvp_label = Label.new()
	_mvp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mvp_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_mvp_label)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 11
	_stats_grid.add_theme_constant_override("h_separation", 14)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	var grid_center := CenterContainer.new()
	grid_center.add_child(_stats_grid)
	box.add_child(grid_center)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_rematch_button = _menu_button(buttons, "Rematch", rematch_pressed.emit)
	_replay_button = _menu_button(buttons, "Watch Replay", replay_pressed.emit)
	var menu := _menu_button(buttons, "Main Menu", menu_pressed.emit)
	for b in [_rematch_button, _replay_button, menu]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Replay controls (top center, under the turn order).
	_replay_bar = PanelContainer.new()
	_replay_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_replay_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_replay_bar.offset_top = 96  # under both team bars and the objective line
	_replay_bar.visible = false
	_root.add_child(_replay_bar)
	var replay_row := HBoxContainer.new()
	replay_row.add_theme_constant_override("separation", 6)
	_replay_bar.add_child(replay_row)
	var replay_label := Label.new()
	replay_label.text = "REPLAY"
	replay_label.add_theme_color_override("font_color", GOLD)
	replay_row.add_child(replay_label)
	var speed_group := ButtonGroup.new()
	for speed in [1.0, 2.0, 4.0]:
		var b := _small_button(replay_row, "×%d" % speed, replay_speed_changed.emit.bind(speed))
		b.toggle_mode = true
		b.button_group = speed_group
		b.custom_minimum_size.x = 48
		if speed == 1.0:
			b.set_pressed_no_signal(true)
	# Drag the bar to jump to any point in the battle; it is replayed from the
	# start to get there, so what you see is exactly what happened.
	_replay_slider = HSlider.new()
	_replay_slider.custom_minimum_size = Vector2(220, 24)
	_replay_slider.min_value = 0.0
	_replay_slider.max_value = 1.0
	_replay_slider.step = 0.001
	_replay_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_replay_slider.tooltip_text = "Jump to a point in the battle"
	_replay_slider.drag_ended.connect(_on_replay_drag_ended)
	replay_row.add_child(_replay_slider)
	_replay_pause_button = _small_button(replay_row, "Pause", replay_pause_pressed.emit)
	_replay_pause_button.tooltip_text = "Stop the replay where it is, or start it again"
	_small_button(replay_row, "Back", replay_back_pressed.emit).tooltip_text = "Rewind one order"
	_small_button(replay_row, "Step", replay_step_pressed.emit).tooltip_text = "Play the next order"
	_small_button(replay_row, "Results", replay_results_pressed.emit).tooltip_text = "Skip to the end and show the results"
	_small_button(replay_row, "Exit", menu_pressed.emit)


func _build_game_menu() -> void:
	_game_menu = PanelContainer.new()
	_game_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_menu.visible = false
	_root.add_child(_game_menu)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 260
	box.add_theme_constant_override("separation", 8)
	_game_menu.add_child(box)
	var title := Label.new()
	title.text = "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	_menu_button(box, "Resume", toggle_game_menu)
	_menu_button(box, "Options", _open_options)
	var open_guide := func() -> void:
		toggle_game_menu()
		toggle_guide()
	_menu_button(box, "Unit Guide", open_guide)
	_menu_button(box, "How to Play", _open_how_to)
	_menu_button(box, "Developer Tools", _open_dev_tools)
	_menu_button(box, "Edit layout", toggle_layout_editing)
	_surrender_button = _menu_button(box, "Surrender", _on_surrender)
	_menu_button(box, "Quit to Main Menu", menu_pressed.emit)


# --- Widgets ---------------------------------------------------------------

func _small_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(70, 32)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Compact two-line action button: name on top, key and details below.
func _action_button(parent: Control, action: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE  # keep keys for the game, not the last-clicked button
	b.custom_minimum_size = Vector2(98, 52)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _gauge(parent: Control, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	bar.add_theme_stylebox_override("fill", _box(color, Color(0, 0, 0, 0), 0, 4, Vector2.ZERO))
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_constant_override("outline_size", 4)
	bar.add_child(label)
	bar.set_meta("label", label)
	bar.set_meta("color", color)
	parent.add_child(bar)
	return bar


func _set_gauge(bar: ProgressBar, value: float, max_value: float, text: String, color := Color(0, 0, 0, 0)) -> void:
	bar.max_value = max_value
	bar.value = value
	_set_text(bar.get_meta("label") as Label, text)
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	fill.bg_color = color if color.a > 0.0 else bar.get_meta("color")


## Chip look: dark pill with a team-colored left edge; gold/red/purple
## outline when ready/urgent/casting; white when selected.
func _chip_style(team_color: Color, state_name: String) -> StyleBoxFlat:
	var key := "%s/%s" % [team_color.to_html(), state_name]
	if not _chip_styles.has(key):
		var outline: Color = {"normal": Color(1, 1, 1, 0.06), "ready": GOLD, "urgent": URGENT,
			"casting": CAST, "selected": Color.WHITE}[state_name]
		var bg := Color(0.06, 0.08, 0.12, 0.8)
		if state_name == "ready":
			bg = Color(0.2, 0.16, 0.06, 0.88)
		elif state_name == "urgent":
			bg = Color(0.25, 0.08, 0.07, 0.88)
		elif state_name == "selected":
			bg = Color(0.2, 0.22, 0.28, 0.92)
		# Extra left padding leaves room for the team-colored edge (a ColorRect).
		_chip_styles[key] = _box(bg, outline, 1 if state_name == "normal" else 2, 6, Vector2(2, 2))
	return _chip_styles[key]


# --- Updates ---------------------------------------------------------------

## Turn order strip. Each entry: {"id", "name", "color", "ready", "seconds",
## "casting", "cast_seconds", "selected", "hidden"}, already in display order.
## Loaded icon textures by path.
## The row under a card for what is on its way to this unit: who is casting it
## and which ability, as their two icons side by side.
func _incoming_row(box: VBoxContainer) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 2)
	row.visible = false
	box.add_child(row)
	return row


## What can be seen coming is a spell in flight: a cast names the spot it will
## land on, so anything standing inside its shape is about to be caught --
## whether it was the target or just happens to be standing there.
func _fill_incoming(row: HFlowContainer, u) -> void:
	if row == null:
		return
	var aimed := []
	if game_state != null:
		for caster in game_state.units:
			if caster == u or not caster.is_alive() or not caster.is_casting():
				continue
			var ab: Dictionary = caster.ability(int(caster.casting.slot))
			if game_state.in_shape(ab, caster.pos, caster.casting.target, u.pos):
				aimed.append(caster)
	row.visible = not aimed.is_empty()
	# Rebuilt only when what is coming changes: this runs every frame.
	var sig := ""
	for caster in aimed:
		sig += "%d:%d," % [caster.id, int(caster.casting.slot)]
	if row.get_meta("aimed_sig", "") == sig:
		return
	row.set_meta("aimed_sig", sig)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	for caster in aimed:
		row.add_child(_incoming_chip(caster))


## One "who is casting what at you" pair of icons.
func _incoming_chip(caster) -> Control:
	var slot := int(caster.casting.slot)
	var ab: Dictionary = caster.ability(slot)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 1)
	pair.tooltip_text = "%s %s is casting %s on this spot" % [GameState.TEAM_NAMES[caster.team], caster.job_name(), ab.name]
	pair.mouse_filter = Control.MOUSE_FILTER_STOP
	pair.add_child(_incoming_icon(Jobs.icon_path(caster.job)))
	pair.add_child(_incoming_icon(Jobs.ability_icon_path(caster.job_data().abilities[slot])))
	return pair


func _incoming_icon(path: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _icon(path)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _icon(path: String) -> Texture2D:
	if not _icons.has(path):
		_icons[path] = load(path)
	return _icons[path]


## A turn order chip for one unit (clicking it selects or inspects the unit).
func _new_chip(unit_id: int) -> Button:
	var chip := Button.new()
	chip.focus_mode = Control.FOCUS_NONE
	chip.size = CHIP_SIZE
	chip.pressed.connect(func(): chip_pressed.emit(chip.get_meta("unit_id")))
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	chip.add_child(icon)
	var edge := ColorRect.new()
	edge.name = "Edge"
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	edge.offset_right = 3
	edge.offset_top = 3
	edge.offset_bottom = -3
	chip.add_child(edge)
	# Time badge along the bottom (READY countdown, cast or time until ready).
	var badge := Label.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 9)
	badge.add_theme_stylebox_override("normal", _box(Color(0.02, 0.03, 0.05, 0.8), Color(0, 0, 0, 0), 0, 3, Vector2(1, 0)))
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	badge.offset_top = -12
	badge.offset_bottom = 1
	badge.offset_left = 2
	badge.offset_right = -1
	chip.add_child(badge)
	_timeline.add_child(chip)
	_chips.append(chip)
	chip.set_meta("unit_id", unit_id)
	_chip_for[unit_id] = chip
	return chip


func set_turn_order(entries: Array) -> void:
	# Fixed squares instead of the sliding bars, if that's what is wanted.
	if Settings.turn_icons:
		if _timeline.visible:
			_timeline.visible = false
			_squares_box.visible = true
		_update_squares(entries)
		return
	if not _timeline.visible:
		_timeline.visible = true
		_squares_box.visible = false

	# Where each chip goes: READY units in the zone at the left end, the rest
	# along the bar by seconds until ready (closer = further left and bigger).
	if _timeline.size.x != _bars_width:
		_layout_bars()
	var targets := {}
	var ready_count := [0, 0]
	var on_bar := [[], []]
	for e in entries:
		var team: int = e.team
		var bar_y := team * ROW_HEIGHT + BAR_Y
		# The bar takes the team's color (from its chips).
		_team_bars[team].color = Color(e.color, 0.45)
		if e.ready:
			var slot: int = ready_count[team]
			ready_count[team] += 1
			targets[e.id] = {"pos": Vector2(mini(slot, READY_SLOTS - 1) * (CHIP_SIZE.x + CHIP_GAP), bar_y - CHIP_SIZE.y * 0.5),
				"scale": 1.0}
			continue
		var scale_now := lerpf(1.0, CHIP_MIN_SCALE, clampf(e.seconds / TIMELINE_SECONDS, 0.0, 1.0))
		var h := CHIP_SIZE.y * scale_now
		targets[e.id] = {"pos": Vector2(0, bar_y - h * 0.5), "scale": scale_now, "x": _bar_x(e.seconds)}
		on_bar[team].append(e.id)

	# Group icons that would touch (entries come soonest first, so left to
	# right), merging again until no two groups touch. A group sits centered
	# on the average time of its units.
	var groups: Array = []
	var end := _bars_width
	for team in 2:
		var team_groups: Array = []
		for id in on_bar[team]:
			var t: Dictionary = targets[id]
			team_groups.append({"ids": [id], "center": t.x, "width": CHIP_SIZE.x * t.scale})
		var merged := true
		while merged:
			merged = false
			for i in team_groups.size() - 1:
				var a: Dictionary = team_groups[i]
				var b: Dictionary = team_groups[i + 1]
				if a.center + a.width * 0.5 + MERGE_DISTANCE > b.center - b.width * 0.5:
					var ids: Array = a.ids + b.ids
					var width := -CHIP_GAP
					var total := 0.0
					for id in ids:
						width += CHIP_SIZE.x * targets[id].scale + CHIP_GAP
						total += targets[id].x
					team_groups[i] = {"ids": ids, "center": total / ids.size(), "width": width}
					team_groups.remove_at(i + 1)
					merged = true
					break
		for g in team_groups:
			var center := clampf(g.center, TRACK_START + g.width * 0.5, end - g.width * 0.5)
			var x: float = center - g.width * 0.5
			for id in g.ids:
				targets[id].pos.x = x
				x += CHIP_SIZE.x * targets[id].scale + CHIP_GAP
			if g.ids.size() > 1:
				groups.append(g.ids)

	var blend := minf(1.0, get_process_delta_time() * 12.0)
	for chip in _chips:
		chip.visible = targets.has(chip.get_meta("unit_id"))
	for e in entries:
		var target: Dictionary = targets[e.id]
		# Each unit keeps its own chip, which glides rather than jumps
		# (e.g. from READY back to the end of the bar).
		var chip: Button = _chip_for.get(e.id)
		if chip == null:
			chip = _new_chip(e.id)
			chip.position = target.pos
			chip.scale = Vector2.ONE * target.scale
		else:
			chip.position = chip.position.lerp(target.pos, blend)
			chip.scale = chip.scale.lerp(Vector2.ONE * target.scale, blend)
		var status: String
		var look := "normal"
		var badge_color := TEXT
		if e.hidden:
			status = ""
		elif e.ready:
			# Time left before its Patience runs out.
			status = "%ds" % ceili(e.seconds)
			look = "urgent" if e.seconds <= 5.0 else "ready"
			badge_color = URGENT if look == "urgent" else GOLD
		elif e.casting != "":
			status = "%.1fs" % e.cast_seconds
			look = "casting"
			badge_color = CAST.lightened(0.3)
		elif e.seconds <= SHOW_TIME_SECONDS or e.get("since_turn", INF) <= SHOW_TIME_SECONDS or chip.is_hovered():
			# The time until ready shows only just after a turn, just before the
			# next, and while the mouse is over the chip.
			status = "%.1fs" % e.seconds
		else:
			status = ""
		if e.selected:
			look = "selected"
		var badge: Label = chip.get_node("Badge")
		_set_text(badge, status)
		badge.visible = status != ""
		_set_color(badge, badge_color)
		var icon: TextureRect = chip.get_node("Icon")
		var icon_key: String = "?" if e.hidden else e.job
		if icon.get_meta("job", "") != icon_key:
			icon.set_meta("job", icon_key)
			var icon_path: String = "res://assets/icons/hidden.svg" if e.hidden else Jobs.icon_path(e.job)
			icon.texture = _icon(icon_path)
			# The generic icon of an imported class takes the class color.
			icon.modulate = Jobs.job(e.job).color.lightened(0.3) if icon_path == Jobs.GENERIC_ICON else Color.WHITE
		# The turn explanation costs something to build, so only when it changes.
		var tip_sig := "%s|%s|%d|%d|%d" % [e.title, e.casting, int(e.hidden), e.get("serial", 0), _tuning_revision()]
		if chip.get_meta("tip_sig", "") != tip_sig:
			chip.set_meta("tip_sig", tip_sig)
			var tip: String = "Hidden by the fog of war" if e.hidden else e.title
			if e.casting != "":
				tip += "\nCasting %s" % e.casting
			var unit = game_state.get_unit(e.id) if game_state != null else null
			if not e.hidden and unit != null:
				tip += "\n\n%s\n%s" % [game_state.explain_turn(unit), game_state.explain_countdown(unit)]
			_set_tip(chip, tip)
		# Restyle only when the look changes: theme overrides are costly.
		var look_key := "%s/%s" % [look, e.color.to_html()]
		if chip.get_meta("look", "") != look_key:
			chip.set_meta("look", look_key)
			var style := _chip_style(e.color, look)
			for state_name in ["normal", "hover", "pressed"]:
				chip.add_theme_stylebox_override(state_name, style)
			(chip.get_node("Edge") as ColorRect).color = e.color
	_place_group_frames(groups)


## A frame around each merged group, fitted to its chips as they glide.
func _place_group_frames(groups: Array) -> void:
	while _frames.size() < groups.size():
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.07, 0.75), Color(1, 1, 1, 0.25), 1, 7))
		_frame_layer.add_child(frame)
		_frames.append(frame)
	for i in _frames.size():
		_frames[i].visible = i < groups.size()
		if i >= groups.size():
			continue
		var rect := Rect2()
		for id in groups[i]:
			var chip: Button = _chip_for[id]
			var r := Rect2(chip.position, chip.size * chip.scale)
			rect = r if rect.size == Vector2.ZERO else rect.merge(r)
		rect = rect.grow(3.0)
		_frames[i].position = rect.position
		_frames[i].size = rect.size


## Shows the selected unit. `blocked[i]` is "" when ability i is usable.
func show_unit(u, title: String, color: Color, seconds: float, controllable: bool,
		move_selected: bool, selected_slot: int, blocked: Array, sprint_selected := false) -> void:
	_card.visible = true
	_action_bar.visible = true
	for part in [_hp_bar, _tg_bar, _ult_bar, _subtitle, _stats]:
		part.visible = true
	_set_text(_title, title)
	_set_color(_title, color.lightened(0.4))
	var sub := "READY · %ds left" % ceili(seconds) if u.ready else "Ready in %.1fs" % seconds
	for s in u.statuses:
		sub += "  ·  %s" % Jobs.STATUSES[s.id].tag
	_set_text(_subtitle, sub)
	_set_color(_subtitle, (URGENT if seconds <= 5.0 else GOLD) if u.ready else DIM)
	_fill_incoming(_incoming, u)
	_set_gauge(_hp_bar, u.hp, u.max_hp(), "HP  %d / %d" % [u.hp, u.max_hp()])
	if u.is_casting():
		var done: float = 1.0 - float(u.casting.ticks) / u.casting.total
		_set_gauge(_tg_bar, done, 1.0, "Casting %s" % u.casting.name, CAST)
	elif u.ready:
		_set_gauge(_tg_bar, 1.0, 1.0, "TG  READY", GOLD)
	else:
		_set_gauge(_tg_bar, u.tg, GameState.TG_MAX, "TG  %d%%" % GameState.tg_percent(u))
	_set_gauge(_ult_bar, u.ult, 100, "ULT  %d%%" % u.ult, Color(1, 0.95, 0.6) if u.ult >= 100 else Color(0, 0, 0, 0))
	var move: float = game_state.move_of(u) if game_state != null else float(u.stat("move"))
	var sight: float = game_state.sight_of(u) if game_state != null else float(u.stat("sight"))
	_set_text(_stats, "POW %d  DEF %d  MDF %d  CRIT %d%%\nAEV %d%%  MEV %d%%  WIT %d  MOV %sm  PAT %d  SGT %sm" % [
		u.stat("power"), u.stat("attdef"), u.stat("magdef"), u.stat("crit"),
		u.stat("aeva"), u.stat("meva"), u.stat("speed"), GameState._n(move), u.stat("patience"), GameState._n(sight)])
	if game_state != null and _card_tip_sig != _unit_tip_signature(u):
		_card_tip_sig = _unit_tip_signature(u)
		_set_tip(_subtitle, game_state.explain_countdown(u) + "\n" + game_state.explain_turn(u))
		_set_tip(_tg_bar, game_state.explain_turn(u))
		_set_tip(_hp_bar, "Max HP %d (class %s)%s" % [u.max_hp(), u.job_name(), "" if u.hp == u.max_hp() else "\nMissing %d" % (u.max_hp() - u.hp)])
		_set_tip(_ult_bar, "Ultimate meter %d / %d\n+%d each turn, +%d per ability used, +%s per 1%% of max HP lost" % [
			u.ult, GameState.ULT_MAX, roundi(game_state.tune("ult_per_turn")), roundi(game_state.tune("ult_per_action")), str(GameState.ULT_FROM_DAMAGE)])
		_set_tip(_stats, "%s\n%s\n%s\n%s%s" % [game_state.explain_move(u), game_state.explain_sight(u),
			game_state.explain_countdown(u), game_state.explain_turn(u), _buff_text(u)])

	_set_text(_move_button, "Move\n%s" % Keybinds.key_name("move"))
	_move_button.disabled = not controllable or u.moved or u.is_casting()
	_move_button.set_pressed_no_signal(move_selected and not sprint_selected)
	_set_text(_sprint_button, "Sprint\n%s · %s" % [Keybinds.key_name("sprint"),
		"%.1f m" % (game_state.move_of(u, true) if game_state != null else 0.0)])
	_sprint_button.disabled = not controllable or u.moved or u.acted or u.is_casting()
	_sprint_button.set_pressed_no_signal(sprint_selected)
	for i in 4:
		var ab: Dictionary = u.ability(i)
		var b := _ability_buttons[i]
		var details: Array[String] = [Keybinds.key_name("ability_%d" % (i + 1))]
		var kind: String = ab.get("kind", "active")
		if kind == "passive" or kind == "aura":
			details = [Jobs.KINDS[kind].name.to_upper()]
		elif kind == "toggle":
			details.append("ON" if u.toggled.get(i, false) else "OFF")
		elif kind == "channeled":
			details.append("%d turns" % int(ab.get("channel", 2)))
		if i == 3 and u.ult < 100:
			details.append("ULT %d%%" % u.ult)
		elif u.cooldowns[i] > 0:
			details.append("wait %d" % u.cooldowns[i])
		elif ab.cast > 0.0:
			details.append("%.1fs" % (game_state.cast_seconds(ab) if game_state != null else ab.cast))
		_set_text(b, "%s\n%s" % [ab.name, "  ·  ".join(details)])
		var ab_id: String = u.job_data().abilities[i]
		if b.get_meta("ability_id", "") != ab_id:
			b.set_meta("ability_id", ab_id)
			b.icon = _icon(Jobs.ability_icon_path(ab_id))
		# A ready ultimate stands out in gold.
		_set_color(b, GOLD if i == 3 and u.ult >= 100 else TEXT)
		var range_text := "self" if ab.max_range == 0 else "range %.1f-%.1f m" % [ab.min_range, ab.max_range]
		var cast_text := "instant" if ab.cast == 0.0 else "cast %.1fs" % (game_state.cast_seconds(ab) if game_state != null else ab.cast)
		var shape: String = GameState.shape_of(ab)
		var tip := "%s\n%s · %s%s · %s" % [ab.desc, Jobs.KINDS[ab.get("kind", "active")].name, Jobs.SHAPES[shape].name,
			(", radius %.1f m" % ab.aoe) if ab.aoe > 0 and shape == "circle" else "", cast_text]
		tip = tip.replace(" · ", "  ·  ")
		tip += "\n" + range_text
		if game_state != null and b.get_meta("tip_sig", "") != _unit_tip_signature(u):
			b.set_meta("tip_sig", _unit_tip_signature(u))
			var full: String = tip + "\n\n" + game_state.explain_ability(u, i)
			_set_tip(b, full)
			b.set_meta("hover_text", "%s%s\n%s" % [ab.name, "  (%s)" % blocked[i] if blocked[i] != "" else "", full])
		b.disabled = not controllable or u.acted or blocked[i] != ""
		b.set_pressed_no_signal(selected_slot == i)
	_end_button.disabled = not controllable


## What the calculation tooltips depend on: while this is the same, they say
## the same thing, so they don't need building again.
func _unit_tip_signature(u) -> String:
	return "%d|%d|%d|%d|%s|%s|%d" % [u.id, u.serial, u.hp, u.ult, u.buffs, u.toggled, _tuning_revision()]


func _tuning_revision() -> int:
	return game_state.tuning.hash() if game_state != null else 0


## Active buffs as tooltip lines.
static func _buff_text(u) -> String:
	var text := ""
	for b in u.buffs:
		text += "\nBuff: %s %+d (%d turn%s left)" % [b.stat, b.amount, b.turns, "" if b.turns == 1 else "s"]
	return text


static func _set_tip(control: Control, tip: String) -> void:
	if control.tooltip_text != tip:
		control.tooltip_text = tip


## Sets text only when it differs (avoids needless relayouts every frame).
static func _set_text(control: Control, text: String) -> void:
	if control.text != text:
		control.text = text


## Sets the font color override only when it changes.
static func _set_color(control: Control, color: Color) -> void:
	if control.get_meta("font_color", Color(0, 0, 0, 0)) != color:
		control.set_meta("font_color", color)
		control.add_theme_color_override("font_color", color)


## Nothing selected: a short message on the card; the action bar hides.
func show_no_unit(text: String) -> void:
	_card.visible = true
	_set_text(_title, text)
	_set_color(_title, TEXT)
	for part in [_hp_bar, _tg_bar, _ult_bar, _subtitle, _stats]:
		part.visible = false
	_action_bar.visible = false


## What to show while the mouse is over an ability button, or "" when it
## isn't over one.
func hovered_ability_text() -> String:
	if _hovered_ability < 0 or _hovered_ability >= _ability_buttons.size():
		return ""
	return _ability_buttons[_hovered_ability].get_meta("hover_text", "")


func set_hover(text: String) -> void:
	_hover.text = text
	_hover_panel.visible = text != ""
	# Lift the preview above the action bar only while the bar is shown.
	_hover_panel.offset_bottom = -88 if _action_bar.visible else -12


## A line for the combat log: plain text, or an entry from the rules with a
## kind and the icon of the unit it is about.
func log_message(entry) -> void:
	_log.add_message(entry)


func toggle_log() -> void:
	_log.toggle_shown()


## Victory / defeat panel with per-unit stats. `rows`: [{"name", "color",
## "dealt", "taken", "healed", "kos"}]; `mvp`: index into rows or -1.
func show_game_over(text: String, rows: Array = [], mvp := -1, can_rematch := true, result_color := GOLD) -> void:
	_game_over_label.add_theme_color_override("font_color", result_color)
	# The first line is the result; anything after it is the small print.
	var lines := text.split("\n", false)
	_game_over_label.text = lines[0] if lines.size() > 0 else text
	_game_over_sub.text = "\n".join(Array(lines).slice(1))
	_game_over_sub.visible = _game_over_sub.text != ""
	for child in _stats_grid.get_children():
		child.queue_free()
	for header in ["Unit", "Damage dealt", "Damage taken", "Damage avoided", "Healing", "KOs",
			"Abilities", "Crits", "Evaded", "Buffs", "Debuffs"]:
		var h := Label.new()
		h.text = header
		h.add_theme_color_override("font_color", GOLD)
		h.add_theme_font_size_override("font_size", 12)
		_stats_grid.add_child(h)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var values := ["%s%s" % ["★ " if i == mvp else "", r.name], str(r.dealt), str(r.taken),
			str(r.get("avoided", 0)), str(r.healed), str(r.kos), str(r.get("abilities", 0)),
			str(r.get("crits", 0)), str(r.get("evades", 0)), str(r.get("buffs", 0)), str(r.get("debuffs", 0))]
		for v in values.size():
			var l := Label.new()
			l.text = values[v]
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", r.color if v == 0 or r.get("total", false) else TEXT)
			_stats_grid.add_child(l)
	_mvp_label.text = "MVP: %s" % rows[mvp].name if mvp >= 0 else ""
	_mvp_label.add_theme_color_override("font_color", rows[mvp].color if mvp >= 0 else GOLD)
	_rematch_button.visible = can_rematch
	_game_over.visible = true
	_replay_bar.visible = false


func hide_game_over() -> void:
	_game_over.visible = false


## Let go of the bar: jump there, but only if it actually moved.
func _on_replay_drag_ended(changed: bool) -> void:
	if changed:
		replay_seek.emit(_replay_slider.value)


func show_replay_bar(shown: bool) -> void:
	_replay_bar.visible = shown


## How far through the log the replay is, from 0 to 1 (ignored while the bar
## is being dragged, so it doesn't fight the mouse).
func set_replay_progress(fraction: float) -> void:
	if _replay_slider != null and not _replay_slider.has_focus():
		_replay_slider.set_value_no_signal(clampf(fraction, 0.0, 1.0))


## Button captions from the current key bindings.
func _update_key_labels() -> void:
	_guide_button.text = "Units %s" % Keybinds.key_name("unit_guide")
	_log_button.text = "Log %s" % Keybinds.key_name("log")
	_end_button.text = "End Turn\n%s" % Keybinds.key_name("end_turn")
	_move_button.text = "Move\n%s" % Keybinds.key_name("move")
	_sprint_button.text = "Sprint\n%s" % Keybinds.key_name("sprint")
	set_paused(_pause_button.text.begins_with("Resume"))


func set_paused(paused: bool) -> void:
	_pause_button.text = "%s %s" % ["Resume" if paused else "Pause", Keybinds.key_name("pause")]
	if _replay_pause_button != null:
		_replay_pause_button.text = "Play" if paused else "Pause"


# --- Overlays --------------------------------------------------------------

## Opens or closes the Unit Guide over the battle.
func toggle_guide() -> void:
	# Rebuilt when Developer Tools changed the rule numbers it shows.
	var tuning: Dictionary = game_state.tuning if game_state != null else {}
	if _guide != null and not _guide.visible and _guide.tuning != tuning:
		_guide.queue_free()
		_guide = null
	if _guide == null:
		_guide = UnitGuide.new()
		_guide.tuning = tuning.duplicate()
		_guide.visible = false
		_root.add_child(_guide)
		_guide.closed.connect(_emit_overlay)
	if _guide.visible:
		_guide.close_guide()
	else:
		_guide.visible = true
		_emit_overlay()


## Give up, from the in-game menu (asks once).
func _on_surrender() -> void:
	if _surrender_button.text == "Surrender":
		_surrender_button.text = "Surrender: are you sure?"
		return
	_surrender_button.text = "Surrender"
	toggle_game_menu()
	surrender_pressed.emit()


func toggle_game_menu() -> void:
	if _surrender_button != null:
		_surrender_button.text = "Surrender"
	_game_menu.visible = not _game_menu.visible
	_emit_overlay()


func _open_options() -> void:
	_game_menu.visible = false
	if _options == null:
		_options = OptionsMenu.new()
		_options.visible = false
		_root.add_child(_options)
		# Back to the in-game menu after closing Options.
		var back_to_menu := func() -> void:
			_game_menu.visible = true
			_emit_overlay()
		_options.closed.connect(back_to_menu)
	_options.visible = true
	_emit_overlay()


func _open_dev_tools() -> void:
	_game_menu.visible = false
	if _dev_tools == null:
		_dev_tools = DevTools.new()
		_dev_tools.visible = false
		_dev_tools.live = dev_tools_live
		_root.add_child(_dev_tools)
		var back_to_menu := func() -> void:
			_game_menu.visible = true
			_emit_overlay()
		_dev_tools.closed.connect(back_to_menu)
		_dev_tools.tuning_changed.connect(tuning_changed.emit)
	if game_state != null:
		_dev_tools.show_values(game_state.tuning)
	_dev_tools.visible = true
	_emit_overlay()


func _open_how_to() -> void:
	_game_menu.visible = false
	if _how_to == null:
		_how_to = HowToPlay.new()
		_how_to.visible = false
		_root.add_child(_how_to)
		var back_to_menu := func() -> void:
			_game_menu.visible = true
			_emit_overlay()
		_how_to.closed.connect(back_to_menu)
	_how_to.visible = true
	_emit_overlay()


func is_guide_open() -> bool:
	return _guide != null and _guide.visible


## Any overlay covering the battle (menu, Options, Unit Guide).
func is_overlay_open() -> bool:
	return (is_guide_open() or _game_menu.visible or (_options != null and _options.visible)
		or (_how_to != null and _how_to.visible) or (_dev_tools != null and _dev_tools.visible))


func _emit_overlay() -> void:
	overlay_changed.emit(is_overlay_open())
