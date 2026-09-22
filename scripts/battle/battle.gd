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
const TEAM_COLORS := [Color(0.25, 0.5, 0.9), Color(0.85, 0.25, 0.22)]
const TICK_SECONDS := 1.0 / GameState.TICKS_PER_SECOND
const NO_POINT := Vector2(-1000, -1000)

enum Mode { NONE, MOVE, ABILITY }

var state := GameState.new()
var ai := AIPlayer.new(GameConfig.ai_difficulty)
var board: BoardView
var cam: CameraRig
var hud: Hud
var fx: Fx
var unit_views := {}
var selected_id := -1
var mode := Mode.NONE
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
var _ai_wait := 1.0
## Casting unit id -> ground circle showing where its spell will land.
var _cast_markers := {}
## Computer's units: unit id -> time (msec) it may act, after its reaction delay.
var _ai_ready_at := {}
## The computer thinks on a worker thread so the game never stutters.
var _ai_task := -1
var _ai_result := {}
## The game was paused by opening the Unit Guide (so closing it resumes).
var _paused_by_guide := false


func _ready() -> void:
	state.setup(GameConfig.build_map())
	match GameConfig.mode:
		"ai":
			viewer_team = 1 - GameConfig.ai_team
		"online":
			viewer_team = GameConfig.local_team
		_:
			viewer_team = -1
	_build_world()
	hud = Hud.new()
	add_child(hud)
	hud.build(GameConfig.mode != "online")
	hud.move_pressed.connect(_toggle_move)
	hud.ability_pressed.connect(_select_ability)
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.menu_pressed.connect(_back_to_menu)
	hud.pause_pressed.connect(_toggle_pause)
	hud.chip_pressed.connect(_on_chip_pressed)
	hud.overlay_changed.connect(_on_overlay_changed)
	if GameConfig.mode == "online":
		Net.command_received.connect(_process_inbox)
		Net.request_received.connect(_process_requests)
		Net.request_rejected.connect(_on_request_rejected)
		Net.opponent_left.connect(_on_opponent_left)
	hud.log_message("Battle start! Units act as soon as they are READY. Act before their countdown runs out.")
	if GameConfig.mode == "ai":
		hud.log_message("Computer difficulty: %s" % GameConfig.ai_difficulty.capitalize())
	_refresh()
	if GameConfig.mode == "online":
		_process_inbox()
		_process_requests()


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.68, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
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
	board.build(state)
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
	match GameConfig.mode:
		"ai":
			return "ai" if team == GameConfig.ai_team else "local"
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
	if state.winner == -1 and not paused:
		# Online, only the host moves time forward; the client follows.
		if GameConfig.mode != "online" or Net.is_host():
			_tick_time += delta
			var ticks := floori(_tick_time / TICK_SECONDS)
			if ticks > 0:
				_tick_time -= ticks * TICK_SECONDS
				_submit({"type": "advance", "ticks": mini(ticks, GameState.MAX_ADVANCE)})
		if GameConfig.mode == "ai":
			_ai_step(delta)
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

	# Capture what the animations need before the rules change the state.
	var actor: Unit = state.get_unit(cmd.unit) if cmd.has("unit") else null
	var walk_path: Array[Vector2] = []
	if cmd.type == "move":
		walk_path = state.path_to(actor, state.node_of(cmd.to))
	var result := state.apply(cmd)

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
	# Abilities that took effect now (instant ones, or casts that finished).
	var delay := 0.0
	for r in result.resolved:
		delay = maxf(delay, _play_ability(state.get_unit(r.unit), r.slot, r.target, r.hits))
	for e in result.events:
		if _point_seen(e.pos):
			_popup(e, delay if e.get("impact", false) else 0.0)
	for id in result.knocked_out:
		unit_views[id].knock_out(delay)
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
	elif sel != null and mode == Mode.MOVE and cmd.type == "move":
		reachable = state.reachable_nodes(sel)  # someone else moved; paths may change
	if selected_id == -1:
		_auto_select()
	if (cmd.type != "advance" or not result.became_ready.is_empty() or not result.turn_ended.is_empty()
			or not result.resolved.is_empty()):
		_refresh()


## Plays the animation for an ability that just took effect. Returns the
## seconds until it lands.
func _play_ability(caster: Unit, slot: int, target: Vector2, hits: Array) -> float:
	if not _is_seen(caster) and not _point_seen(target):
		return 0.0
	var ab := caster.ability(slot)
	var view: UnitView = unit_views[caster.id]
	var target_3d := board.ground(target)
	var delay := fx.play(caster.job_data().abilities[slot], view, board.ground(caster.pos) + Vector3(0, 0.9, 0), target_3d, ab.aoe)
	for id in hits:
		var t := state.get_unit(id)
		if t.is_alive() and _is_seen(t):
			unit_views[id].flinch(delay, Color(1, 0.25, 0.2) if ab.effect == "damage" else Color(0.5, 1, 0.6))
	return delay


func _ai_step(delta: float) -> void:
	# A decision is being worked out in the background: collect it when ready.
	if _ai_task != -1:
		if not WorkerThreadPool.is_task_completed(_ai_task):
			return
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1
		var decided := _ai_result
		# The battle kept running while it thought; a stale order is dropped
		# and it simply thinks again.
		if state.validate(decided) == "":
			_submit(decided)
			_ai_wait = ai.level().step + (1.0 if decided.type == "move" else 0.0)
		return
	_ai_wait -= delta
	if _ai_wait > 0.0:
		return
	var unit: Unit = null
	var now := Time.get_ticks_msec()
	for u in state.ready_units(GameConfig.ai_team):
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
		_ai_result = ai.next_command(snap, snap_unit)
	_ai_task = WorkerThreadPool.add_task(think, false, "Computer turn")


func _exit_tree() -> void:
	if _ai_task != -1:
		WorkerThreadPool.wait_for_task_completion(_ai_task)
		_ai_task = -1


# --- Online ----------------------------------------------------------------

## Client: apply commands the host has confirmed (including time passing).
func _process_inbox() -> void:
	while not Net.inbox.is_empty():
		var cmd: Dictionary = Net.inbox.pop_front()
		var err := state.validate(cmd)
		if err != "":
			hud.log_message("Out of sync with the host (%s)." % err)
			continue
		_apply(cmd)


## Host: check and play the client's orders.
func _process_requests() -> void:
	while not Net.requests.is_empty():
		var cmd: Dictionary = Net.requests.pop_front()
		var err := state.validate(cmd)
		if err == "" and cmd.get("type") == "advance":
			err = "Only the host moves time forward."
		if err == "" and state.get_unit(cmd.unit).team == GameConfig.local_team:
			err = "That isn't your unit."
		if err != "":
			Net.reject(err)
			continue
		Net.broadcast(cmd)
		_apply(cmd)


func _on_request_rejected(reason: String) -> void:
	waiting_for_host = false
	hud.log_message(reason)
	_refresh()


func _on_opponent_left() -> void:
	if state.winner == -1:
		paused = true
		hud.show_game_over("Opponent disconnected")


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
				_order({"type": "move", "to": state.node_pos(node)})
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


func _enter_move_mode() -> void:
	var u := _selected()
	if u == null or u.moved:
		return
	mode = Mode.MOVE
	ability_slot = -1
	reachable = state.reachable_nodes(u)
	_hover_node = Vector2i(-99999, -99999)
	_refresh()


func _toggle_move() -> void:
	if not _can_input():
		return
	if mode == Mode.MOVE:
		_cancel()
	else:
		_enter_move_mode()


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
	ability_slot = -1
	_refresh()


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


func _back_to_menu() -> void:
	Net.close()
	get_tree().change_scene_to_file(MENU_SCENE)


func _game_over() -> void:
	_deselect()
	var text: String
	if viewer_team == -1:
		text = "%s wins!" % GameState.TEAM_NAMES[state.winner]
	else:
		text = "Victory!" if state.winner == viewer_team else "Defeat"
	hud.show_game_over(text)
	_refresh()


# --- Presentation ----------------------------------------------------------

## Everything that changes every frame: countdowns, bars, turn order.
func _update_live_ui() -> void:
	var entries := []
	for u in state.schedule():
		var seen := _is_seen(u)
		entries.append({
			"id": u.id,
			"name": u.job_name() if seen else "???",
			"color": (TEAM_COLORS[u.team] as Color).lightened(0.35),
			"ready": u.ready,
			"casting": u.casting.name if u.is_casting() and seen else "",
			"cast_seconds": state.cast_seconds_left(u),
			"seconds": state.seconds_left(u),
			"selected": u.id == selected_id,
			"hidden": not seen,
		})
		unit_views[u.id].set_status(u, state.seconds_left(u))
	hud.set_turn_order(entries)
	# Knocked-out units aren't in the turn order but show a revive countdown.
	for u in state.units:
		if u.is_ko():
			unit_views[u.id].set_status(u, 0.0)
	_update_cast_markers()

	var sel := _selected()
	if sel != null:
		var blocked: Array[String] = []
		for i in 4:
			blocked.append(state.ability_blocked_reason(sel, i))
		hud.show_unit(sel, "%s %s" % [GameState.TEAM_NAMES[sel.team], sel.job_name()],
			TEAM_COLORS[sel.team], state.seconds_left(sel), _can_input(),
			mode == Mode.MOVE, ability_slot, blocked)
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
	if _can_input() and mode == Mode.MOVE:
		var node := state.node_of(hover_point) if hover_point != NO_POINT else Vector2i(-99999, -99999)
		if node != _hover_node:
			_hover_node = node
			if reachable.has(node):
				board.show_path(state.path_to(sel, node), true)
				hud.set_hover("Walk here: %.1f m of %d m" % [reachable[node], sel.stat("move")])
				return
			board.show_path([], true)
		if reachable.has(node):
			return
	elif _can_input() and mode == Mode.ABILITY:
		var ab := sel.ability(ability_slot)
		var aim := _aim()
		if aim.point != NO_POINT:
			board.show_aoe(aim.point, maxf(ab.aoe, GameState.HIT_RADIUS), aim.ok)
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
				if hit.flank >= GameState.BACK_BONUS:
					flank = " from behind +%d%%" % roundi((GameState.BACK_BONUS - 1.0) * 100)
				elif hit.flank >= GameState.SIDE_BONUS:
					flank = " from the side +%d%%" % roundi((GameState.SIDE_BONUS - 1.0) * 100)
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
		cast = "   (cast %.1fs, %s)" % [ab.cast, aim]
	var who := "; ".join(parts) if not parts.is_empty() else "ground: hits whoever is here when it lands"
	return "%s → %s%s" % [ab.name, who, cast]


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
			status += "   %s %.0fs" % [Jobs.STATUSES[s.id].name, ceilf(s.ticks / 10.0)]
		var sel := _selected()
		var dist := "   ·   %.1f m away" % sel.pos.distance_to(t.pos) if sel != null and sel != t else ""
		return "%s %s   HP %d/%d   %s   Ultimate %d%%   AttPwr %d  MagPwr %d  AttDef %d  MagDef %d  Wits %d  Move %d m  Sight %d m%s" % [
			GameState.TEAM_NAMES[t.team], t.job_name(), t.hp, t.max_hp(), status, t.ult,
			t.stat("att"), t.stat("mag"), t.stat("attdef"), t.stat("magdef"), t.stat("wits"), t.stat("move"), t.stat("sight"), dist]
	if not _point_seen(hover_point):
		return "%s   ·   hidden by fog of war" % ground
	return ground


## Keeps one purple circle under each pending spell's landing spot. Single
## target spells follow their target.
func _update_cast_markers() -> void:
	for id in _cast_markers.keys():
		var u := state.get_unit(id)
		if not u.is_alive() or not u.is_casting():
			_cast_markers[id].queue_free()
			_cast_markers.erase(id)
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
		var marker: MeshInstance3D = _cast_markers[u.id]
		marker.position = board.ground(target) + Vector3(0, 0.1, 0)
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
