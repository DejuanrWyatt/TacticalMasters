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
signal ability_pressed(slot: int)
signal end_turn_pressed
signal menu_pressed
signal pause_pressed
signal chip_pressed(unit_id: int)
## An overlay (menu, Options or Unit Guide) opened or closed.
signal overlay_changed(open: bool)
signal rematch_pressed
signal replay_pressed
signal replay_speed_changed(speed: float)
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
var _ability_buttons: Array[Button] = []
var _end_button: Button
var _hover_panel: PanelContainer
var _hover: Label
var _log: LogWindow
var _log_button: Button
var _game_over: Control
var _game_over_label: Label
var _stats_grid: GridContainer
var _mvp_label: Label
var _rematch_button: Button
var _replay_button: Button
var _replay_bar: PanelContainer
var _chat: LineEdit
var _guide: Control
var _options: Control
var _game_menu: Control
var _how_to: Control
var _dev_tools: Control
## The battle's rules, for the calculation tooltips (set by Battle).
var game_state
## True when Developer Tools changes apply to this battle right away.
var dev_tools_live := false
## What the unit card's tooltips were last built from.
var _card_tip_sig := ""


func build(can_pause: bool) -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.build()
	add_child(_root)

	_build_turn_order()
	_build_corner_buttons(can_pause)
	_build_log()
	_build_chat()
	_build_unit_card()
	_build_action_bar()
	_build_game_over()
	_build_game_menu()

	Keybinds.changed.connect(_update_key_labels)
	_update_key_labels()


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
	for part in [hp, tg, ult]:
		part.mouse_filter = Control.MOUSE_FILTER_PASS
	return {"card": card, "title": title, "sub": sub, "hp": hp, "tg": tg, "ult": ult, "stats": stats, "abilities": abilities}


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
	_set_gauge(c.hp, u.hp, u.max_hp(), "HP  %d / %d" % [u.hp, u.max_hp()])
	if u.ready:
		_set_gauge(c.tg, 1.0, 1.0, "TG  READY", GOLD)
	else:
		_set_gauge(c.tg, u.tg, GameState.TG_MAX, "TG  %d%%" % GameState.tg_percent(u))
	_set_gauge(c.ult, u.ult, 100, "ULT  %d%%" % u.ult, Color(1, 0.95, 0.6) if u.ult >= 100 else Color(0, 0, 0, 0))
	var move: float = game_state.move_of(u) if game_state != null else float(u.stat("move"))
	var sight: float = game_state.sight_of(u) if game_state != null else float(u.stat("sight"))
	_set_text(c.stats, "Power %d   AttDef %d   MagDef %d\nA-Eva %d%%   M-Eva %d%%   Crit %d%%\nWits %d   Patience %d\nMove %s m   Sight %s m" % [
		u.stat("power"), u.stat("attdef"), u.stat("magdef"), u.stat("aeva"), u.stat("meva"), u.stat("crit"),
		u.stat("wits"), u.stat("patience"), GameState._n(move), GameState._n(sight)])
	var rows: Array = c.abilities.get_children()
	while rows.size() < 4:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		c.abilities.add_child(l)
		rows.append(l)
	for i in 4:
		var ab: Dictionary = u.ability(i)
		var note := ""
		if i == 3:
			note = "  (ULT %d%%)" % u.ult if u.ult < 100 else "  (ULT ready)"
		elif u.cooldowns[i] > 0:
			note = "  (wait %d)" % u.cooldowns[i]
		_set_text(rows[i], "%s  %s%s" % ["U" if i == 3 else str(i + 1), ab.name, note])
		_set_color(rows[i], GOLD if i == 3 and u.ult >= 100 else DIM)
		if game_state != null:
			_set_tip(rows[i], "%s\n\n%s" % [ab.desc, game_state.explain_ability(u, i)])
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
	for i in 4:
		var b := _action_button(row, ability_pressed.emit.bind(i))
		b.add_theme_constant_override("icon_max_width", 22)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
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
	_mvp_label = Label.new()
	_mvp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mvp_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_mvp_label)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 5
	_stats_grid.add_theme_constant_override("h_separation", 26)
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
	_replay_bar.offset_top = 56
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
		move_selected: bool, selected_slot: int, blocked: Array) -> void:
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
		u.stat("aeva"), u.stat("meva"), u.stat("wits"), GameState._n(move), u.stat("patience"), GameState._n(sight)])
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
	_move_button.set_pressed_no_signal(move_selected)
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
			_set_tip(b, tip + "\n\n" + game_state.explain_ability(u, i))
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


func set_hover(text: String) -> void:
	_hover.text = text
	_hover_panel.visible = text != ""
	# Lift the preview above the action bar only while the bar is shown.
	_hover_panel.offset_bottom = -88 if _action_bar.visible else -12


func log_message(text: String) -> void:
	_log.add_message(text)


func toggle_log() -> void:
	_log.toggle_shown()


## Victory / defeat panel with per-unit stats. `rows`: [{"name", "color",
## "dealt", "taken", "healed", "kos"}]; `mvp`: index into rows or -1.
func show_game_over(text: String, rows: Array = [], mvp := -1, can_rematch := true) -> void:
	_game_over_label.text = text
	for child in _stats_grid.get_children():
		child.queue_free()
	for header in ["Unit", "Damage dealt", "Damage taken", "Healing", "KOs"]:
		var h := Label.new()
		h.text = header
		h.add_theme_color_override("font_color", GOLD)
		h.add_theme_font_size_override("font_size", 12)
		_stats_grid.add_child(h)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var values := ["%s%s" % ["★ " if i == mvp else "", r.name], str(r.dealt), str(r.taken), str(r.healed), str(r.kos)]
		for v in values.size():
			var l := Label.new()
			l.text = values[v]
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", r.color if v == 0 else TEXT)
			_stats_grid.add_child(l)
	_mvp_label.text = "MVP: %s" % rows[mvp].name if mvp >= 0 else ""
	_rematch_button.visible = can_rematch
	_game_over.visible = true
	_replay_bar.visible = false


func hide_game_over() -> void:
	_game_over.visible = false


func show_replay_bar(shown: bool) -> void:
	_replay_bar.visible = shown


## Button captions from the current key bindings.
func _update_key_labels() -> void:
	_guide_button.text = "Units %s" % Keybinds.key_name("unit_guide")
	_log_button.text = "Log %s" % Keybinds.key_name("log")
	_end_button.text = "End Turn\n%s" % Keybinds.key_name("end_turn")
	_move_button.text = "Move\n%s" % Keybinds.key_name("move")
	set_paused(_pause_button.text.begins_with("Resume"))


func set_paused(paused: bool) -> void:
	_pause_button.text = "%s %s" % ["Resume" if paused else "Pause", Keybinds.key_name("pause")]


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


func toggle_game_menu() -> void:
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
