extends Node3D
## Battle scene controller.
##
## Time runs continuously: every unit's Turn Gauge fills by its Wits, and a
## unit with a full gauge is READY and can act at once, whatever else is
## happening. Several units, from both teams, can be ready together, each
## with its own countdown. The player picks one of their ready units (click
## it, click its chip in the turn order bar, or press Tab), then walks it
## and/or uses an ability before its countdown ends.
##
## Movement and targeting are free-form (no grid): the shaded area shows
## where the unit can walk, dots show the path to the cursor, and abilities
## use range rings and area circles measured in meters.
##
## All rules live in GameState; this script presents them, plays the
## animations and relays orders (straight to the rules, or via the host
## when playing online).

const GameState = preload("res://scripts/core/game_state.gd")
const Unit = preload("res://scripts/core/unit.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")
const BoardView = preload("res://scripts/battle/board_view.gd")
const UnitView = preload("res://scripts/battle/unit_view.gd")
const CameraRig = preload("res://scripts/battle/camera_rig.gd")
const Hud = preload("res://scripts/battle/hud.gd")
const Fx = preload("res://scripts/battle/fx.gd")
const Jobs = preload("res://scripts/core/jobs.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"
## Team colors (blue/red, or blue/orange with the colorblind setting).
var TEAM_COLORS: Array = Settings.team_colors()
const TICK_SECONDS := 1.0 / GameState.TICKS_PER_SECOND
## Online: how often the host sends its checksum (in ticks).
const CHECKSUM_EVERY_TICKS := 50
const NO_POINT := Vector2(-1000, -1000)

enum Mode { NONE, MOVE, ABILITY }

var state := GameState.new()
## The computer player for each team (null = not the computer).
var ais := [null, null]
## Teams the computer plays in this battle (fixed when the battle starts).
var _ai_teams: Array = []
var board: BoardView
var cam: CameraRig
var hud: Hud
var fx: Fx
var unit_views := {}
var selected_id := -1
var mode := Mode.NONE
## In MOVE mode: whether this is a sprint (further, but uses the action).
var sprinting := false
var ability_slot := -1
## Move mode: navigation nodes the selected unit can walk to -> meters.
var reachable := {}
## Ground point under the mouse (meters) and the unit under it, if any.
var hover_point := NO_POINT
var hover_unit_id := -1
var _hover_node := Vector2i(-99999, -99999)
## Team whose vision is drawn (fog of war). -1 on a shared device: no fog.
var viewer_team := 0
var paused := false
## Online client: an order was sent and the host hasn't answered yet.
var waiting_for_host := false
var _tick_time := 0.0
## Per team: seconds until the computer may order again.
var _ai_wait := [1.0, 1.0]
## Casting unit id -> ground circle showing where its spell will land.
var _cast_markers := {}
## The beam from each casting unit to where its spell will land.
var _cast_links := {}
## A faint ring under each unit that carries an aura, showing how far it reaches.
var _aura_rings := {}
## Computer's units: unit id -> time (msec) it may act, after its reaction delay.
var _ai_ready_at := {}
## The computer thinks on a worker thread so the game never stutters.
## Per team: background decision in progress (-1 = none) and its result.
var _ai_task := [-1, -1]
var _ai_result := [{}, {}]
## The game was paused by opening the Unit Guide (so closing it resumes).
var _paused_by_guide := false
## Every command applied this battle, for Watch Replay (deterministic rules
## make replaying them exact).
var command_log: Array = []
## Per-unit battle stats for the victory screen: id -> {dealt, taken, healed, kos}.
var stats := {}
## Replay mode: feeding command_log back in instead of taking orders.
var replaying := false
var _replay_log: Array = []
var _replay_i := 0
var _replay_time := 0.0
var _replay_speed := 1.0
## Rule numbers this battle started with (a replay starts from them too).
var _start_tuning := {}
## Changed class stats this battle started with.
var _start_overrides := {}
## Battle tick when each unit's last turn ended (turn order timeline).
var _turn_used_at := {}
## Online: the host's checksums by tick, and when one was last sent.
var _host_checksums := {}
var _last_checksum_tick := 0
## Unit whose stats card is open (clicked, not taking orders), or -1.
var inspected_id := -1
## What the threat preview was last drawn for (see _update_threat).
var _threat_signature := ""


func _ready() -> void:
	# Class stats changed in the Unit Guide (the host's online; a replay's own).
	Jobs.set_overrides(GameConfig.battle_overrides())
	_start_overrides = Jobs.stat_overrides.duplicate(true)
	state.setup(GameConfig.build_map(), GameConfig.battle_tuning(), GameConfig.battle_seed())
	_start_tuning = state.tuning.duplicate()
	for u in state.units:
		stats[u.id] = {"dealt": 0, "taken": 0, "healed": 0, "kos": 0, "abilities": 0, "crits": 0, "evades": 0}
	if not GameConfig.replay_log.is_empty():
		replaying = true
		_replay_log = GameConfig.replay_log
		GameConfig.replay_log = []
		# Asked to start partway through: play those orders out before the
		# board is built, so everything is already where it should be.
		if GameConfig.replay_skip > 0:
			while _replay_i < GameConfig.replay_skip and _replay_i < _replay_log.size() and state.winner == -1:
				_record_stats(state.apply(_replay_log[_replay_i]))
				_replay_i += 1
			GameConfig.replay_skip = 0
	match GameConfig.mode:
		"ai":
			viewer_team = 1 - GameConfig.ai_team
		"cpu":
			viewer_team = -1  # watching: fog off
		"online":
			viewer_team = GameConfig.local_team
		_:
			viewer_team = -1
	if replaying:
		viewer_team = -1  # replays show everything
	_build_world()
	hud = Hud.new()
	hud.game_state = state
	# Developer Tools changes apply at once, except online (the host's rule
	# numbers hold for the match) and in replays (they replay the recorded ones).
	hud.dev_tools_live = GameConfig.mode != "online" and not replaying
	add_child(hud)
	hud.build(GameConfig.mode != "online")
	hud.tuning_changed.connect(_on_tuning_changed)
	hud.inspect_closed.connect(func(): inspected_id = -1)
	Settings.changed.connect(_apply_look)
	hud.move_pressed.connect(_toggle_move)
	hud.sprint_pressed.connect(_toggle_sprint)
	hud.ability_pressed.connect(_select_ability)
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.menu_pressed.connect(_back_to_menu)
	hud.surrender_pressed.connect(_surrender)
	hud.pause_pressed.connect(_toggle_pause)
	hud.chip_pressed.connect(_on_chip_pressed)
	hud.overlay_changed.connect(_on_overlay_changed)
	hud.rematch_pressed.connect(_rematch)
	hud.replay_pressed.connect(_watch_replay)
	hud.replay_speed_changed.connect(_set_replay_speed)
	hud.replay_seek.connect(_replay_seek)
	hud.replay_step_pressed.connect(_replay_one)
	hud.replay_results_pressed.connect(func(): _replay_seek(1.0))
	if replaying:
		hud.show_replay_bar(true)
		hud.log_message("Watching the replay.")
	elif GameConfig.mode == "online":
		Net.command_received.connect(_process_inbox)
		Net.request_received.connect(_process_requests)
		Net.request_rejected.connect(_on_request_rejected)
		Net.checksum_received.connect(_on_checksum_received)
		Net.out_of_sync.connect(_on_out_of_sync)
		Net.opponent_left.connect(_on_opponent_left)
		Net.chat_received.connect(_on_chat_received)
		Net.rematch_requested.connect(_on_rematch_requested)
		# A rematch (both players agreed) restarts the battle scene.
		Net.game_started.connect(get_tree().reload_current_scene)
		hud.chat_submitted.connect(_on_chat_submitted)
		hud.chat_toggled.connect(func(open: bool): cam.keys_enabled = not open)
		hud.log_message("Press %s to chat with your opponent." % Keybinds.key_name("chat"))
	if not replaying:
		hud.log_message("Battle start! Units act as soon as they are READY. Act before their countdown runs out.")
	_ai_teams = [] if replaying else GameConfig.ai_teams()
	for team in _ai_teams:
		ais[team] = AIPlayer.new(GameConfig.difficulty_for(team))
	if GameConfig.mode == "ai" and not replaying:
		hud.log_message("Computer difficulty: %s" % GameConfig.ai_difficulty.capitalize())
	if GameConfig.mode == "cpu" and not replaying:
		hud.log_message("Computer vs Computer: Blue (%s) vs Red (%s). Sit back and watch." % [
			GameConfig.difficulty_for(0).capitalize(), GameConfig.difficulty_for(1).capitalize()])
	_refresh()
	# Draw every visual once during loading (hidden again right after), so no
	# shader compiles mid-battle.
	board.prewarm(state.size_meters() * 0.5)
	for view in unit_views.values():
		view.prewarm()
	get_tree().create_timer(0.3).timeout.connect(_refresh)
	Audio.sfx_enabled = true
	Audio.play_music(Audio.BATTLE_MUSIC)
	var models := 0
	for view in unit_views.values():
		if view._character != null:
			models += 1
	print("Battle: %s, %d/%d units with animated models" % [GameConfig.map_id, models, unit_views.size()])
	if GameConfig.mode == "online" and not replaying:
		_process_inbox()
		_process_requests()
	# Jumped to (or past) the end of the log: show the results again.
	if replaying and state.winner != -1:
		_game_over.call_deferred()


func _build_world() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_material.sky_horizon_color = Color(0.7, 0.78, 0.86)
	# Below the horizon: the same haze, so the world beyond the map fades out.
	sky_material.ground_bottom_color = Color(0.6, 0.68, 0.76)
	sky_material.ground_horizon_color = Color(0.7, 0.78, 0.86)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)

	board = BoardView.new()
	add_child(board)
	board.build(state, GameConfig.map_id)
	for u in state.units:
		var view := UnitView.new()
		add_child(view)
		view.setup(u, TEAM_COLORS[u.team])
		view.place(board.ground(u.pos))
		view.face(board.ground(state.size_meters() * 0.5))
		unit_views[u.id] = view
	fx = Fx.new()
	add_child(fx)
	fx.prewarm(board.ground(state.size_meters() * 0.5))

	cam = CameraRig.new()
	add_child(cam)
	var home: Vector2 = state.spawn_points[maxi(0, viewer_team)]
	cam.snap_to(board.ground(home.lerp(state.size_meters() * 0.5, 0.35)))


# --- Who controls what -----------------------------------------------------

## "local", "ai" or "remote": who gives orders to a team on this device.
func _controller(team: int) -> String:
	if replaying:
		return "replay"
	match GameConfig.mode:
		"ai":
			return "ai" if team == GameConfig.ai_team else "local"
		"cpu":
			return "ai"
		"online":
			return "local" if team == GameConfig.local_team else "remote"
	return "local"


func _selected() -> Unit:
	return state.get_unit(selected_id) if selected_id >= 0 else null


## A unit this device may give orders to right now.
func _commandable(u: Unit) -> bool:
	return (u != null and u.is_alive() and u.ready and _controller(u.team) == "local"
		and state.winner == -1 and not paused and not waiting_for_host)


func _can_input() -> bool:
	return _commandable(_selected())


func _is_seen(u: Unit) -> bool:
	return viewer_team == -1 or state.winner != -1 or u.team == viewer_team or state.can_see(viewer_team, u.pos)


func _point_seen(p: Vector2) -> bool:
	return viewer_team == -1 or state.winner != -1 or state.can_see(viewer_team, p)


# --- Time and orders -------------------------------------------------------

func _process(delta: float) -> void:
	if replaying:
		if not paused:
			_replay_step(delta)
	elif state.winner == -1 and not paused:
		# Online, only the host moves time forward; the client follows.
		if GameConfig.mode != "online" or Net.is_host():
			_tick_time += delta
			var ticks := floori(_tick_time / TICK_SECONDS)
			if ticks > 0:
				_tick_time -= ticks * TICK_SECONDS
				_submit({"type": "advance", "ticks": mini(ticks, GameState.MAX_ADVANCE)})
		for team in _ai_teams:
			_ai_step(delta, team)
		if GameConfig.mode == "online":
			if Net.is_host():
				_send_checksum_if_due()
			elif not _host_checksums.is_empty():
				_check_checksums()
	_update_live_ui()


## Sends an order for the selected unit.
func _order(cmd: Dictionary) -> void:
	var u := _selected()
	if not _commandable(u):
		return
	cmd["unit"] = u.id
	cmd["serial"] = u.serial
	_submit(cmd)


## Sends a command through the proper path: straight to the rules locally,
## or through the host online.
func _submit(cmd: Dictionary) -> void:
	if GameConfig.mode == "online" and not Net.is_host():
		if not waiting_for_host:
			waiting_for_host = true
			Net.send_request(cmd)
		return
	var err := state.validate(cmd)
	if err != "":
		hud.log_message(err)
		return
	if GameConfig.mode == "online":
		Net.broadcast(cmd)  # before applying, so any follow-up command is sent after it
	_apply(cmd)


func _apply(cmd: Dictionary) -> void:
	if cmd.type != "advance":
		waiting_for_host = false
	if not replaying:
		command_log.append(cmd.duplicate(true))

	# Capture what the animations need before the rules change the state.
	var actor: Unit = state.get_unit(cmd.unit) if cmd.has("unit") else null
	var walk_path: Array[Vector2] = []
	if cmd.type == "move":
		walk_path = state.path_to(actor, state.node_of(cmd.to))
	var result := state.apply(cmd)
	for id in result.turn_ended:
		_turn_used_at[id] = state.tick

	if cmd.type == "move":
		var points: Array[Vector3] = []
		for p in walk_path:
			points.append(board.ground(p))
		unit_views[actor.id].walk(points)
	for id in result.cast_started:
		var caster := state.get_unit(id)
		if _is_seen(caster):
			unit_views[id].face(board.ground(caster.casting.target))
			fx.charge(unit_views[id], caster.casting.ticks / float(GameState.TICKS_PER_SECOND))
	_record_stats(result)
	# Abilities that took effect now (instant ones, or casts that finished).
	var delay := 0.0
	for r in result.resolved:
		delay = maxf(delay, _play_ability(state.get_unit(r.unit), r.slot, r.target, r.hits))
	for e in result.events:
		if _point_seen(e.pos):
			_popup(e, delay if e.get("impact", false) else 0.0)
	for id in result.knocked_out:
		unit_views[id].knock_out(delay)
		if _is_seen(state.get_unit(id)):
			get_tree().create_timer(delay + 0.3).timeout.connect(Audio.play_at.bind("knock_out", unit_views[id].global_position))
	_play_turn_sounds(result)
	for id in result.revived:
		unit_views[id].revive(delay)
	for id in result.gone:
		unit_views[id].vanish()
	for line in result.logs:
		hud.log_message(line)
	if state.winner != -1:
		_game_over()
		return

	var sel := _selected()
	if sel != null and (not sel.is_alive() or not sel.ready):
		_deselect()
	elif sel != null and actor == sel and _commandable(sel):
		# The selected unit just acted: finish its turn or offer the next step.
		# After starting a cast it can't move, so there is nothing left to do.
		if sel.acted and (sel.moved or sel.is_casting()):
			_order({"type": "end_turn"})
			return
		mode = Mode.NONE
		ability_slot = -1
		if not sel.moved:
			_enter_move_mode()
	elif sel != null and mode == Mode.MOVE and (cmd.type == "move" or cmd.type == "tune"):
		reachable = state.reachable_nodes(sel, sprinting)  # someone else moved; paths may change
	if selected_id == -1:
		_auto_select()
	if (cmd.type != "advance" or not result.became_ready.is_empty() or not result.turn_ended.is_empty()
			or not result.resolved.is_empty()):
		_refresh()


## The stats card of a clicked unit: allies (of the unit you're ordering, or
## of your team) on the left, enemies on the right.
func _update_inspect() -> void:
	var u := state.get_unit(inspected_id) if inspected_id != -1 else null
	if u != null and ((not u.is_alive() and not u.is_ko()) or not _is_seen(u) or u.id == selected_id):
		u = null
	if u == null:
		inspected_id = -1
		hud.show_inspect(null, false, "", Color.WHITE, 0.0)
		_update_threat(null)
		return
	var sel := _selected()
	var ally_team := sel.team if sel != null else (viewer_team if viewer_team != -1 else 0)
	hud.show_inspect(u, u.team != ally_team, "%s %s" % [GameState.TEAM_NAMES[u.team], u.job_name()],
		TEAM_COLORS[u.team], state.seconds_left(u))
	_update_threat(u if u.team != ally_team else null)


## Shows what a clicked enemy could do next: the ground it can walk to, and
## the reach of its longest attack from where it stands. Only worked out again
## when that unit moves or takes a turn, not every frame.
func _update_threat(enemy) -> void:
	if enemy == null or not enemy.is_alive():
		if _threat_signature != "":
			_threat_signature = ""
			board.show_threat([], Vector2.ZERO, 0.0)
		return
	var signature := "%d:%s:%d:%s" % [enemy.id, enemy.pos, enemy.serial, enemy.moved]
	if signature == _threat_signature:
		return
	_threat_signature = signature
	var reach := 0.0
	for slot in 4:
		var ab: Dictionary = enemy.ability(slot)
		if ab.effect == "damage":
			reach = maxf(reach, ab.max_range)
	board.show_threat(state.reachable_nodes(enemy).keys(), enemy.pos, reach)


## Draws what the ability would cover: a circle, a line from the unit, or a
## cone (Jobs.SHAPES).
func _show_aim_shape(sel: Unit, ab: Dictionary, aim: Dictionary) -> void:
	var shape := GameState.shape_of(ab)
	var from := sel.pos
	match shape:
		"line", "vector":
			var along: Vector2 = aim.point - from
			if along.length() < 0.2:
				along = sel.facing * maxf(ab.max_range, 1.0)
			var side := Vector2(-along.y, along.x).normalized() * maxf(ab.aoe, 0.6)
			board.show_aoe(aim.point, 0.0, aim.ok)
			board.show_patch(PackedVector2Array([from - side, from + side, from + along + side, from + along - side]), aim.ok)
		"cone":
			var facing: Vector2 = (aim.point - from).normalized() if aim.point.distance_to(from) > 0.2 else sel.facing
			var spread: float = deg_to_rad(ab.get("angle", 60.0)) * 0.5
			var points := PackedVector2Array([from])
			for i in 9:
				points.append(from + facing.rotated(lerpf(-spread, spread, i / 8.0)) * ab.max_range)
			board.show_aoe(aim.point, 0.0, aim.ok)
			board.show_patch(points, aim.ok)
		"global":
			board.hide_patch()
			board.show_aoe(sel.pos, 0.0, aim.ok)
		_:
			board.hide_patch()
			board.show_aoe(aim.point, maxf(ab.aoe, GameState.HIT_RADIUS), aim.ok)


## Plays the animation for an ability that just took effect. Returns the
## seconds until it lands.
func _play_ability(caster: Unit, slot: int, target: Vector2, hits: Array) -> float:
	if not _is_seen(caster) and not _point_seen(target):
		return 0.0
	var ab := caster.ability(slot)
	var view: UnitView = unit_views[caster.id]
	var target_3d := board.ground(target)
	# Imported abilities borrow a built-in animation ("fx").
	var delay := fx.play(ab.get("fx", caster.job_data().abilities[slot]), view, board.ground(caster.pos) + Vector3(0, 0.9, 0), target_3d, ab.aoe)
	for id in hits:
		var t := state.get_unit(id)
		if t.is_alive() and _is_seen(t):
			unit_views[id].flinch(delay, Color(1, 0.25, 0.2) if ab.effect == "damage" else Color(0.5, 1, 0.6))
	return delay


func _ai_step(delta: float, team: int) -> void:
	var ai: AIPlayer = ais[team]
	# A decision is being worked out in the background: collect it when ready.
	if _ai_task[team] != -1:
		if not WorkerThreadPool.is_task_completed(_ai_task[team]):
			return
		WorkerThreadPool.wait_for_task_completion(_ai_task[team])
		_ai_task[team] = -1
		var decided: Dictionary = _ai_result[team]
		# The battle kept running while it thought; a stale order is dropped
		# and it simply thinks again.
		if state.validate(decided) == "":
			_submit(decided)
			_ai_wait[team] = ai.level().step + (1.0 if decided.type == "move" else 0.0)
		return
	_ai_wait[team] -= delta
	if _ai_wait[team] > 0.0:
		return
	var unit: Unit = null
	var now := Time.get_ticks_msec()
	for u in state.orderable_units(team):
		# The computer takes a moment to react to a unit becoming ready.
		var key := "%d/%d" % [u.id, u.serial]
		if not _ai_ready_at.has(key):
			_ai_ready_at[key] = now + int(ai.level().think * 1000)
		if now < _ai_ready_at[key]:
			continue
		if unit == null or u.clock < unit.clock:
			unit = u
	if unit == null:
		return
	var snap = state.snapshot()
	var snap_unit = snap.get_unit(unit.id)
	var think := func() -> void:
		_ai_result[team] = ai.next_command(snap, snap_unit)
	_ai_task[team] = WorkerThreadPool.add_task(think, false, "Computer turn")


func _exit_tree() -> void:
	for team in 2:
		if _ai_task[team] != -1:
			WorkerThreadPool.wait_for_task_completion(_ai_task[team])
			_ai_task[team] = -1


# --- Online ----------------------------------------------------------------

## Client: apply commands the host has confirmed (including time passing).
func _process_inbox() -> void:
	while not Net.inbox.is_empty():
		var cmd: Dictionary = Net.inbox.pop_front()
		var err := state.validate(cmd)
		if err != "":
			Net.report_out_of_sync("the host played something this game can't: %s" % err)
			continue
		_apply(cmd)


## Host: check and play the client's orders.
func _process_requests() -> void:
	while not Net.requests.is_empty():
		var cmd: Dictionary = Net.requests.pop_front()
		var err := state.validate(cmd)
		if err == "" and cmd.get("type") in ["advance", "tune"]:
			err = "Only the host moves time forward or changes the rules."
		if err == "" and state.get_unit(cmd.unit).team == GameConfig.local_team:
			err = "That isn't your unit."
		if err != "":
			Net.reject(err)
			continue
		Net.broadcast(cmd)
		_apply(cmd)


## Host: every few seconds of battle, send where the game stands.
func _send_checksum_if_due() -> void:
	if state.tick - _last_checksum_tick < CHECKSUM_EVERY_TICKS:
		return
	_last_checksum_tick = state.tick
	Net.send_checksum(state.tick, state.checksum())


## Client: compare the host's checksum with this game's at the same tick.
func _on_checksum_received(at_tick: int, value: int) -> void:
	_host_checksums[at_tick] = value
	if at_tick > state.tick:
		return  # not there yet; checked when this game reaches that tick
	_check_checksums()


func _check_checksums() -> void:
	for at_tick in _host_checksums.keys():
		if at_tick > state.tick:
			continue
		if at_tick == state.tick and _host_checksums[at_tick] != state.checksum():
			Net.report_out_of_sync("the two games no longer match at %.1f s" % (state.tick / 10.0))
		_host_checksums.erase(at_tick)


## The games have drifted apart: stop rather than play on separately.
func _on_out_of_sync(detail: String) -> void:
	if state.winner != -1:
		return
	paused = true
	hud.set_paused(true)
	hud.log_message("Out of sync: %s" % detail)
	hud.show_game_over("Out of sync\n%s\nThe match can't continue." % detail, [], -1, false)


func _on_request_rejected(reason: String) -> void:
	waiting_for_host = false
	hud.log_message(reason)
	_refresh()


func _on_opponent_left() -> void:
	if state.winner == -1:
		paused = true
		hud.show_game_over("Opponent disconnected", [], -1, false)


# --- Player input ----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if hud.is_overlay_open():
		if hud.is_guide_open() and event.is_action_pressed("tm_unit_guide"):
			hud.toggle_guide()
		return
	if event is InputEventMouseMotion:
		_pick(event.position)
		_update_targeting()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)
		_on_click()
	elif event is InputEventKey and event.pressed and not event.echo:
		# Keys come from the player's bindings (see Keybinds / Options).
		for i in 4:
			if event.is_action_pressed("tm_ability_%d" % (i + 1)):
				_select_ability(i)
				return
		if event.is_action_pressed("tm_move"):
			_toggle_move()
		elif event.is_action_pressed("tm_sprint"):
			_toggle_sprint()
		elif event.is_action_pressed("tm_next_unit"):
			_cycle_ready()
		elif event.is_action_pressed("tm_end_turn"):
			_on_end_turn_pressed()
		elif event.is_action_pressed("tm_cancel"):
			_cancel()
		elif event.is_action_pressed("tm_pause"):
			_toggle_pause()
		elif event.is_action_pressed("tm_unit_guide"):
			hud.toggle_guide()
		elif event.is_action_pressed("tm_log"):
			hud.toggle_log()
		elif event.is_action_pressed("tm_chat") and GameConfig.mode == "online" and not replaying:
			hud.open_chat()
		elif event.is_action_pressed("tm_center_camera"):
			if _selected() != null:
				cam.focus_on(board.ground(_selected().pos))
		else:
			return
		get_viewport().set_input_as_handled()


## Raycasts the mouse into the world: sets hover_point and hover_unit_id.
func _pick(screen_pos: Vector2) -> void:
	hover_point = NO_POINT
	hover_unit_id = -1
	var from := cam.camera.project_ray_origin(screen_pos)
	var to := from + cam.camera.project_ray_normal(screen_pos) * 500.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return
	var body: Object = hit.collider
	if body.has_meta("unit"):
		var u := state.get_unit(body.get_meta("unit"))
		hover_unit_id = u.id
		hover_point = u.pos
		return
	var p := Vector2(hit.position.x, hit.position.z)
	if state.in_bounds(p):
		hover_point = p
		var near := state.unit_near(p, 0.5)
		if near != null and _is_seen(near):
			hover_unit_id = near.id


func _on_click() -> void:
	if hover_point == NO_POINT:
		return
	var sel := _selected()
	if _can_input():
		if mode == Mode.MOVE:
			var node := state.node_of(hover_point)
			if reachable.has(node) and state.node_pos(node) != sel.pos:
				_order({"type": "move", "to": state.node_pos(node), "sprint": sprinting})
				return
		elif mode == Mode.ABILITY:
			var aim := _aim()
			if aim.ok:
				_order({"type": "ability", "slot": ability_slot, "target": aim.point, "follow": aim.follow})
			else:
				hud.log_message(aim.why)
			return
	var clicked := state.get_unit(hover_unit_id)
	if clicked != null and clicked != sel and _commandable(clicked):
		_select_unit(clicked.id)
	elif clicked != null and clicked != sel and _is_seen(clicked):
		# Anyone else: open (or close) its stats card.
		inspected_id = -1 if inspected_id == clicked.id else clicked.id
	elif clicked == null:
		inspected_id = -1


## Where the selected ability would land for the current mouse position:
## {"point": Vector2, "follow": unit id or -1, "ok": bool, "why": String}.
## Pointing at a unit targets that unit (a cast follows it); pointing at the
## ground targets that spot, e.g. where an enemy is expected to walk.
func _aim() -> Dictionary:
	var sel := _selected()
	var ab := sel.ability(ability_slot)
	if ab.max_range == 0.0:
		# Centered on the caster: click the caster or anywhere in the area.
		var near := hover_point != NO_POINT and hover_point.distance_to(sel.pos) <= maxf(ab.aoe, 1.0) + 0.5
		return {"point": sel.pos, "follow": sel.id, "ok": near, "why": "Click on %s to use %s." % [sel.job_name(), ab.name]}
	if hover_point == NO_POINT:
		return {"point": NO_POINT, "follow": -1, "ok": false, "why": ""}
	var point := state.snap(hover_point)
	var follow := -1
	var t := state.get_unit(hover_unit_id)
	if t != null and _fits_target(sel, ab, t):
		point = t.pos
		follow = t.id
	elif ab.target == "ko_ally":
		return {"point": point, "follow": -1, "ok": false, "why": "Pick a knocked-out ally."}
	if not state.in_ability_range(sel, ability_slot, sel.pos, point):
		return {"point": point, "follow": follow, "ok": false, "why": "Out of range."}
	if not state.can_see(sel.team, point):
		return {"point": point, "follow": follow, "ok": false, "why": "You can't see that spot."}
	if GameState.needs_line_of_sight(ab) and not state.has_line_of_sight(sel.pos, point):
		return {"point": point, "follow": follow, "ok": false, "why": "No line of sight (terrain in the way)."}
	return {"point": point, "follow": follow, "ok": true, "why": ""}


## Whether a unit is the kind of target this ability takes.
func _fits_target(sel: Unit, ab: Dictionary, t: Unit) -> bool:
	if ab.target == "ko_ally":
		return t.is_ko() and t.team == sel.team
	return t.is_alive() and (t.team != sel.team) == (ab.target == "enemy")


## Clicking a chip selects that unit if it can act; clicking it again (or
## clicking any other visible unit's chip) centers the camera on it.
func _on_chip_pressed(unit_id: int) -> void:
	var u := state.get_unit(unit_id)
	if _commandable(u) and unit_id != selected_id:
		_select_unit(unit_id)
	elif _is_seen(u):
		cam.focus_on(board.ground(u.pos))
		if u.id != selected_id:
			inspected_id = u.id


func _select_unit(id: int) -> void:
	selected_id = id
	mode = Mode.NONE
	ability_slot = -1
	var u := _selected()
	# The camera doesn't move by itself; press Center or click the chip again.
	if not u.moved:
		_enter_move_mode()
	_refresh()


func _deselect() -> void:
	selected_id = -1
	mode = Mode.NONE
	ability_slot = -1


## Selects this device's ready unit with the least time left, if any.
func _auto_select() -> void:
	for u in state.schedule():
		if _commandable(u):
			_select_unit(u.id)
			return


func _cycle_ready() -> void:
	var ready: Array[Unit] = []
	for u in state.schedule():
		if _commandable(u):
			ready.append(u)
	if ready.is_empty():
		return
	var i := 0
	for j in ready.size():
		if ready[j].id == selected_id:
			i = (j + 1) % ready.size()
	_select_unit(ready[i].id)


func _enter_move_mode(sprint := false) -> void:
	var u := _selected()
	if u == null or u.moved or (sprint and u.acted):
		return
	mode = Mode.MOVE
	sprinting = sprint
	ability_slot = -1
	reachable = state.reachable_nodes(u, sprint)
	_hover_node = Vector2i(-99999, -99999)
	_refresh()


func _toggle_move() -> void:
	if not _can_input():
		return
	if mode == Mode.MOVE and not sprinting:
		_cancel()
	else:
		_enter_move_mode()


## Sprint: walks further than a normal move, but it is the unit's action for
## the turn, so no ability afterwards.
func _toggle_sprint() -> void:
	if not _can_input():
		return
	if mode == Mode.MOVE and sprinting:
		_cancel()
		return
	var u := _selected()
	if u != null and u.acted:
		hud.log_message("Already used an ability this turn: no sprinting.")
		return
	_enter_move_mode(true)


func _select_ability(slot: int) -> void:
	if not _can_input():
		return
	var u := _selected()
	if mode == Mode.ABILITY and ability_slot == slot:
		_cancel()
		return
	if u.acted:
		hud.log_message("Already used an ability this turn.")
		return
	var reason := state.ability_blocked_reason(u, slot)
	if reason != "":
		hud.log_message(reason)
		return
	mode = Mode.ABILITY
	ability_slot = slot
	_refresh()


func _cancel() -> void:
	mode = Mode.NONE
	sprinting = false
	ability_slot = -1
	_refresh()


## Give up: the other side wins. Recorded like any other command, so a
## replay of the battle ends the same way.
func _surrender() -> void:
	var team: int = GameConfig.local_team if GameConfig.mode == "online" else (1 - GameConfig.ai_team if GameConfig.mode == "ai" else 0)
	if team == -1 or state.winner != -1 or replaying:
		return
	_submit({"type": "surrender", "team": team})


func _on_end_turn_pressed() -> void:
	_order({"type": "end_turn"})


func _toggle_pause() -> void:
	if GameConfig.mode == "online" or state.winner != -1:
		return
	paused = not paused
	hud.set_paused(paused)
	hud.log_message("Paused." if paused else "Resumed.")
	_refresh()


## Opening the menu, Options or the Unit Guide pauses the game (not online,
## where time can't stop) and stops the camera reacting to keys.
func _on_overlay_changed(open: bool) -> void:
	cam.keys_enabled = not open
	if GameConfig.mode == "online" or state.winner != -1:
		return
	if open and not paused:
		_paused_by_guide = true
		_toggle_pause()
	elif not open and _paused_by_guide:
		_paused_by_guide = false
		if paused:
			_toggle_pause()


## A chime when one of your units becomes ready; a buzz when one runs out of time.
func _play_turn_sounds(result: Dictionary) -> void:
	for id in result.became_ready:
		if _controller(state.get_unit(id).team) == "local":
			Audio.play("ready", -4.0)
			break
	for id in result.timed_out:
		if _controller(state.get_unit(id).team) == "local":
			Audio.play("turn_lost", -4.0)
			break


## Jumps the replay to a point in the log. The battle is rebuilt and replayed
## from the start to get there: the rules are deterministic, so it lands on
## exactly the state the battle had at that point.
func _replay_seek(fraction: float) -> void:
	if not replaying:
		return
	GameConfig.replay_log = _replay_log
	GameConfig.replay_skip = clampi(roundi(fraction * _replay_log.size()), 0, _replay_log.size())
	get_tree().reload_current_scene()


## Plays the replay's next order, for stepping through a battle by hand.
func _replay_one() -> void:
	if replaying and _replay_i < _replay_log.size() and state.winner == -1:
		_apply(_replay_log[_replay_i])
		_replay_i += 1


func _set_replay_speed(speed: float) -> void:
	_replay_speed = speed
	# Fast-forwarded replays would be a wall of noise.
	Audio.sfx_enabled = speed <= 2.0


func _back_to_menu() -> void:
	Audio.stop_music()
	Audio.sfx_enabled = true
	Net.close()
	get_tree().change_scene_to_file(MENU_SCENE)


func _game_over() -> void:
	_deselect()
	var text: String
	var local_team: int = GameConfig.local_team if GameConfig.mode == "online" else (1 - GameConfig.ai_team if GameConfig.mode == "ai" else -1)
	if state.winner == GameState.DRAW:
		text = "Draw"
	elif local_team == -1:
		text = "%s wins!" % GameState.TEAM_NAMES[state.winner]
	else:
		text = "Victory!" if state.winner == local_team else "Defeat"
	# When the time ran out, say how close it was.
	if state.tune("battle_seconds") > 0.0 and state.tick >= roundi(state.tune("battle_seconds") * GameState.TICKS_PER_SECOND):
		text += "\nTime: Blue %d%% health, Red %d%%" % [roundi(state.health_share(0) * 100), roundi(state.health_share(1) * 100)]
	text += "\nBattle length: %d:%02d" % [state.tick / GameState.TICKS_PER_SECOND / 60, (state.tick / GameState.TICKS_PER_SECOND) % 60]
	var rows := []
	var mvp := -1
	var best := -1.0
	for team in 2:
		var totals := {"dealt": 0, "taken": 0, "healed": 0, "kos": 0, "abilities": 0, "crits": 0, "evades": 0}
		for u in state.units:
			if u.team != team:
				continue
			var st: Dictionary = stats[u.id]
			for key in totals:
				totals[key] += st[key]
			rows.append({"name": "%s %s" % [GameState.TEAM_NAMES[u.team], u.job_name()],
				"color": (TEAM_COLORS[u.team] as Color).lightened(0.35), "total": false,
				"dealt": st.dealt, "taken": st.taken, "healed": st.healed, "kos": st.kos,
				"abilities": st.abilities, "crits": st.crits, "evades": st.evades})
			# Standing in front of the enemy counts too, not only damage.
			var worth: float = st.dealt + st.healed + st.taken * 0.6 + st.kos * 40.0
			if worth > best:
				best = worth
				mvp = rows.size() - 1
		var totals_row := {"name": "%s total" % GameState.TEAM_NAMES[team], "total": true,
			"color": (TEAM_COLORS[team] as Color).lightened(0.15)}
		totals_row.merge(totals)
		rows.append(totals_row)
	hud.show_game_over(text, rows, mvp, true)
	Audio.stop_music()
	Audio.sfx_enabled = true
	Audio.play("defeat" if text == "Defeat" else "victory")
	_refresh()


## Adds damage, healing, knock-outs, critical hits and evasions from a
## command's result to the stats the victory screen shows.
func _record_stats(result: Dictionary) -> void:
	for r in result.resolved:
		var ab := state.get_unit(r.unit).ability(r.slot)
		stats[r.unit].abilities += 1
		stats[r.unit].crits += r.get("crits", []).size()
		for id in r.get("evaded", []):
			stats[id].evades += 1
		for i in r.hits.size():
			var amount: int = r.amounts[i]
			var target_id: int = r.hits[i]
			match ab.effect:
				"damage":
					stats[r.unit].dealt += amount
					stats[target_id].taken += amount
					if result.knocked_out.has(target_id):
						stats[r.unit].kos += 1
				"heal", "revive":
					stats[r.unit].healed += amount


## Same map and teams, fresh battle. Online, both players have to ask; the
## battle restarts (via Net.game_started) once they have.
func _rematch() -> void:
	GameConfig.replay_log = []
	if GameConfig.mode == "online" and Net.is_online():
		Net.request_rematch()
		hud.log_message("Rematch requested: waiting for your opponent to accept...")
		return
	get_tree().reload_current_scene()


func _on_rematch_requested() -> void:
	hud.log_message("Your opponent wants a rematch: press Rematch to accept.")


func _on_chat_submitted(text: String) -> void:
	Net.send_chat(text)
	hud.log_message("You: %s" % text)


func _on_chat_received(text: String) -> void:
	hud.log_message("Opponent: %s" % text)


## Developer Tools: new rule numbers take effect through a recorded "tune"
## command, so a replay of this battle changes them at the same moment.
func _on_tuning_changed(values: Dictionary) -> void:
	if GameConfig.mode == "online" or replaying or state.winner != -1:
		return
	_submit({"type": "tune", "values": values})


## Replays this battle from its recorded commands.
func _watch_replay() -> void:
	GameConfig.replay_log = command_log if not replaying else _replay_log
	GameConfig.replay_tuning = _start_tuning
	GameConfig.replay_seed = state.seed_value
	GameConfig.replay_overrides = _start_overrides
	get_tree().reload_current_scene()


## Feeds recorded commands back in at their original pace (times the speed).
func _replay_step(delta: float) -> void:
	_replay_time += delta * _replay_speed
	while _replay_i < _replay_log.size() and state.winner == -1:
		var cmd: Dictionary = _replay_log[_replay_i]
		if cmd.type == "advance":
			var needed: float = cmd.ticks * TICK_SECONDS
			if _replay_time < needed:
				break
			_replay_time -= needed
		_apply(cmd)
		_replay_i += 1


# --- Presentation ----------------------------------------------------------

## Display settings changed (the Developer Tools "Look" sliders): pass them
## on to the units, so dragging a slider shows straight away.
func _apply_look() -> void:
	for view in unit_views.values():
		view.set_circle_size(Settings.unit_circle_size)


## Rows for the all-units panel: everyone on the field, Blue then Red, with
## what is known about each (a hidden enemy shows as ???).
func _field_entries() -> Array:
	if not hud.is_field_open():
		return []
	var out := []
	for u in state.units:
		var seen := _is_seen(u)
		var text := ""
		if u.is_ko():
			text = "KO"
		elif not seen:
			text = "?"
		elif u.is_casting():
			text = "%.1fs" % state.cast_seconds_left(u)
		elif u.ready:
			text = "READY"
		else:
			text = "%ds" % ceili(state.seconds_left(u))
		var tags := PackedStringArray()
		for s in u.statuses:
			tags.append(Jobs.STATUSES[s.id].tag)
		out.append({
			"id": u.id,
			"team": u.team,
			"job": u.job,
			"name": u.job_name() if seen else "???",
			"hp": u.hp if seen else 0,
			"max_hp": u.max_hp(),
			"state": text,
			"ready": u.ready and seen,
			"hidden": not seen,
			"color": (TEAM_COLORS[u.team] as Color).lightened(0.35),
			"tip": "%s %s%s" % [GameState.TEAM_NAMES[u.team], u.job_name(),
				"\n" + " ".join(tags) if not tags.is_empty() else ""] if seen else "Not in sight",
		})
	return out


## What this battle is being won by, when it is more than the last team
## standing: the time left, and how far each side is to holding the middle.
func _objective_text() -> String:
	var parts := PackedStringArray()
	var limit: float = state.tune("battle_seconds")
	if limit > 0.0:
		var left := maxf(0.0, limit - state.tick / float(GameState.TICKS_PER_SECOND))
		parts.append("Time left %d:%02d" % [int(left) / 60, int(left) % 60])
	if state.tune("capture_seconds") > 0.0:
		parts.append("Middle held: Blue %d%%, Red %d%%" % [roundi(state.capture_share(0) * 100), roundi(state.capture_share(1) * 100)])
	return "   |   ".join(parts)


## Everything that changes every frame: countdowns, bars, turn order.
func _update_live_ui() -> void:
	_update_inspect()
	var entries := []
	for u in state.schedule():
		var seen := _is_seen(u)
		entries.append({
			"id": u.id,
			"team": u.team,
			"job": u.job,
			"title": "%s %s" % [GameState.TEAM_NAMES[u.team], u.job_name()],
			"name": u.job_name() if seen else "???",
			"color": (TEAM_COLORS[u.team] as Color).lightened(0.35),
			"ready": u.ready,
			"casting": u.casting.name if u.is_casting() and seen else "",
			"cast_seconds": state.cast_seconds_left(u),
			"seconds": state.seconds_left(u),
			"serial": u.serial,
			"since_turn": (state.tick - _turn_used_at[u.id]) / float(GameState.TICKS_PER_SECOND) if _turn_used_at.has(u.id) else INF,
			"tip": "",  # filled in below, only when it would change
			"selected": u.id == selected_id,
			"hidden": not seen,
		})
		unit_views[u.id].set_status(u, state.seconds_left(u), state.clock_ticks(u) / float(GameState.TICKS_PER_SECOND))
	hud.set_turn_order(entries)
	hud.set_objective(_objective_text())
	if replaying and not _replay_log.is_empty():
		hud.set_replay_progress(float(_replay_i) / _replay_log.size())
	hud.set_field(_field_entries())
	# Knocked-out units aren't in the turn order but show a revive countdown.
	for u in state.units:
		if u.is_ko():
			unit_views[u.id].set_status(u, 0.0)
	_update_cast_markers()
	_update_aura_rings()

	var sel := _selected()
	if sel != null:
		var blocked: Array[String] = []
		for i in 4:
			blocked.append(state.ability_blocked_reason(sel, i))
		hud.show_unit(sel, "%s %s" % [GameState.TEAM_NAMES[sel.team], sel.job_name()],
			TEAM_COLORS[sel.team], state.seconds_left(sel), _can_input(),
			mode == Mode.MOVE, ability_slot, blocked, sprinting)
	elif state.winner != -1:
		hud.show_no_unit("Battle over")
	elif paused:
		hud.show_no_unit("Paused")
	else:
		hud.show_no_unit("Waiting for one of your units to be READY...")


## Fog, unit visibility, the move area and range rings.
func _refresh() -> void:
	board.set_fog(state.visible_tiles(viewer_team) if viewer_team >= 0 else {}, viewer_team >= 0 and state.winner == -1)
	for t in state.units:
		unit_views[t.id].refresh(t, t.id == selected_id, _is_seen(t))

	var sel := _selected()
	board.clear_targeting()
	if _can_input():
		if mode == Mode.MOVE:
			board.show_move_area(reachable.keys())
		elif mode == Mode.ABILITY:
			var ab := sel.ability(ability_slot)
			board.show_range(sel.pos, ab.min_range, ab.max_range)
	_hover_node = Vector2i(-99999, -99999)
	_update_targeting()


## The path to the cursor, the area circle and the hover description.
func _update_targeting() -> void:
	var sel := _selected()
	# The mouse is over an ability button: say what that ability does, whether
	# or not it can be used right now.
	var over_ability := hud.hovered_ability_text()
	if over_ability != "":
		hud.set_hover(over_ability)
		return
	if _can_input() and mode == Mode.MOVE:
		var node := state.node_of(hover_point) if hover_point != NO_POINT else Vector2i(-99999, -99999)
		if node != _hover_node:
			_hover_node = node
			if reachable.has(node):
				board.show_path(state.path_to(sel, node), true)
				hud.set_hover("Walk here: %.1f m of %.1f m   (%s)" % [reachable[node], state.move_of(sel), state.explain_move(sel)])
				return
			board.show_path([], true)
		if reachable.has(node):
			return
	elif _can_input() and mode == Mode.ABILITY:
		var ab := sel.ability(ability_slot)
		var aim := _aim()
		if aim.point != NO_POINT:
			_show_aim_shape(sel, ab, aim)
		if aim.ok:
			hud.set_hover(_forecast(sel, ability_slot, aim.point, aim.follow))
		else:
			hud.set_hover("%s: %s" % [ab.name, aim.why if aim.why != "" else ab.desc])
		return
	hud.set_hover(_describe_hover())


func _forecast(sel: Unit, slot: int, point: Vector2, follow: int) -> String:
	var ab := sel.ability(slot)
	var parts: Array[String] = []
	for hit in state.preview(sel, slot, sel.pos, point):
		var t: Unit = hit.unit
		if not _is_seen(t):
			continue
		var who := "%s %s" % [GameState.TEAM_NAMES[t.team], t.job_name()]
		match ab.effect:
			"damage":
				var flank := ""
				if hit.flank > 1.0 and hit.flank >= state.tune("back_bonus"):
					flank = " from behind +%d%%" % roundi((hit.flank - 1.0) * 100)
				elif hit.flank > 1.0:
					flank = " from the side +%d%%" % roundi((hit.flank - 1.0) * 100)
				parts.append("%s: %d damage%s (HP %d → %d)" % [who, hit.amount, flank, t.hp, maxi(0, t.hp - hit.amount)])
			"revive":
				parts.append("%s: revive with %d HP" % [who, hit.amount])
			"heal":
				parts.append("%s: heal %d (HP %d → %d)" % [who, hit.amount, t.hp, t.hp + hit.amount])
			_:
				parts.append(who)
	var cast := "   (instant)"
	if ab.cast > 0.0:
		var aim := "follows its target" if follow != -1 and ab.max_range > 0.0 else "lands on this spot"
		if ab.max_range == 0.0:
			aim = "centered on the caster"
		cast = "   (cast %.1fs, %s)" % [state.cast_seconds(ab), aim]
	var who := "; ".join(parts) if not parts.is_empty() else "ground: hits whoever is here when it lands"
	# How the number was worked out, for the first target shown.
	var math := ""
	for hit in state.preview(sel, slot, sel.pos, point):
		if _is_seen(hit.unit) and ab.effect != "support":
			math = "\n%s: %s" % [hit.unit.job_name(), state.explain_hit(sel, slot, sel.pos, hit.unit).replace("\n", "  ")]
			break
	return "%s → %s%s%s" % [ab.name, who, cast, math]


func _describe_hover() -> String:
	if hover_point == NO_POINT:
		return ""
	var ground := "Water" if state.is_water(hover_point) else "Height %d" % state.level_at(hover_point)
	var t := state.get_unit(hover_unit_id)
	if t != null and t.is_ko() and _is_seen(t):
		return "%s %s   KNOCKED OUT: can be revived for %ds" % [GameState.TEAM_NAMES[t.team], t.job_name(), ceili(t.ko_ticks / 10.0)]
	if t != null and _is_seen(t):
		var status := "READY (%ds left)" % ceili(state.seconds_left(t)) if t.ready else "TG %d%%" % GameState.tg_percent(t)
		if t.is_casting():
			status = "Casting %s (%.1fs)" % [t.casting.name, state.seconds_left(t)]
		for s in t.statuses:
			status += "   %s %d turn%s" % [Jobs.STATUSES[s.id].name, s.turns, "" if s.turns == 1 else "s"]
		var sel := _selected()
		var dist := "   ·   %.1f m away" % sel.pos.distance_to(t.pos) if sel != null and sel != t else ""
		return "%s %s   HP %d/%d   %s   Ultimate %d%%   Power %d  AttDef %d  MagDef %d  A-Eva %d%%  M-Eva %d%%  Crit %d%%  Wits %d  Move %s m  Sight %s m%s" % [
			GameState.TEAM_NAMES[t.team], t.job_name(), t.hp, t.max_hp(), status, t.ult, t.stat("power"),
			t.stat("attdef"), t.stat("magdef"), t.stat("aeva"), t.stat("meva"), t.stat("crit"), t.stat("wits"),
			GameState._n(state.move_of(t)), GameState._n(state.sight_of(t)), dist]
	if not _point_seen(hover_point):
		return "%s   ·   hidden by fog of war" % ground
	return ground


## Keeps one purple circle under each pending spell's landing spot. Single
## target spells follow their target.
## Rings under the units whose abilities reach everyone standing near them.
## Only the ones you can see, and only while they are standing.
func _update_aura_rings() -> void:
	for u in state.units:
		var radius := 0.0
		if u.is_alive() and _is_seen(u):
			for slot in 4:
				var ab: Dictionary = u.ability(slot)
				if ab.get("kind", "active") == "aura":
					radius = maxf(radius, maxf(ab.aoe, 1.0))
		if radius <= 0.0:
			if _aura_rings.has(u.id):
				_aura_rings[u.id].queue_free()
				_aura_rings.erase(u.id)
			continue
		if not _aura_rings.has(u.id):
			var ring := MeshInstance3D.new()
			ring.mesh = TorusMesh.new()
			var m := StandardMaterial3D.new()
			m.albedo_color = (TEAM_COLORS[u.team] as Color).lightened(0.3)
			m.albedo_color.a = 0.3
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.mesh.inner_radius = maxf(0.01, radius - 0.04)
			ring.mesh.outer_radius = radius + 0.04
			ring.material_override = m
			add_child(ring)
			_aura_rings[u.id] = ring
		(_aura_rings[u.id] as MeshInstance3D).position = board.ground(u.pos) + Vector3(0, 0.06, 0)


func _update_cast_markers() -> void:
	for id in _cast_markers.keys():
		var u := state.get_unit(id)
		if not u.is_alive() or not u.is_casting():
			_cast_markers[id].queue_free()
			_cast_markers.erase(id)
			if _cast_links.has(id):
				_cast_links[id].queue_free()
				_cast_links.erase(id)
	for u in state.units:
		if not u.is_alive() or not u.is_casting():
			continue
		var target: Vector2 = u.casting.target
		var followed := state.get_unit(u.casting.target_unit)
		if followed != null and followed.is_alive():
			target = followed.pos
		if not _cast_markers.has(u.id):
			var ab := u.ability(u.casting.slot)
			var disc := CylinderMesh.new()
			disc.height = 0.05
			disc.top_radius = maxf(ab.aoe, GameState.HIT_RADIUS)
			disc.bottom_radius = disc.top_radius
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.75, 0.35, 1.0, 0.35)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.no_depth_test = true
			var marker := MeshInstance3D.new()
			marker.mesh = disc
			marker.material_override = m
			add_child(marker)
			_cast_markers[u.id] = marker
		if not _cast_links.has(u.id):
			# A thin beam from the caster to where the spell will land, so it
			# is clear who is casting at what.
			var beam := BoxMesh.new()
			beam.size = Vector3(0.05, 0.02, 1.0)
			var link := MeshInstance3D.new()
			link.mesh = beam
			link.material_override = _cast_markers[u.id].material_override
			add_child(link)
			_cast_links[u.id] = link
		var marker: MeshInstance3D = _cast_markers[u.id]
		marker.position = board.ground(target) + Vector3(0, 0.1, 0)
		var from := board.ground(u.pos) + Vector3(0, 1.1, 0)
		var to := board.ground(target) + Vector3(0, 0.2, 0)
		var link_mesh: MeshInstance3D = _cast_links[u.id]
		# A beam straight down (a spell on its own feet) has no direction to
		# point along, so it isn't drawn.
		link_mesh.visible = _point_seen(u.pos) and Vector2(to.x - from.x, to.z - from.z).length() > 0.3
		if link_mesh.visible:
			link_mesh.position = (from + to) * 0.5
			link_mesh.look_at_from_position(link_mesh.position, to, Vector3.UP)
			link_mesh.scale = Vector3(1, 1, from.distance_to(to))
		# Pulse faster as the spell gets close to going off.
		var left := state.seconds_left(u)
		marker.visible = _point_seen(target) or u.team == viewer_team
		(marker.material_override as StandardMaterial3D).albedo_color.a = 0.25 + 0.2 * absf(sin(Time.get_ticks_msec() / 1000.0 * (3.0 + 6.0 / maxf(left, 0.5))))


func _popup(e: Dictionary, delay: float) -> void:
	var label := Label3D.new()
	label.text = e.text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.007
	label.font_size = 48
	label.outline_size = 12
	label.modulate = e.color
	label.visible = false
	add_child(label)
	label.position = board.ground(e.pos) + Vector3(0, 2.4, 0)
	var tween := label.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): label.visible = true)
	tween.tween_property(label, "position:y", label.position.y + 0.9, 1.2)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tween.tween_callback(label.queue_free)
