extends SceneTree
## Two-process online test on localhost. Run a host and a client at once:
##   godot --headless --script res://tests/net_test.gd -- host
##   godot --headless --script res://tests/net_test.gd -- client
## The host picks a map and teams, which must arrive at the client; the
## client sends a chat message the host must receive. Then it uses the real
## Net flow in fast-forward: the host moves time forward and both sides let
## the AI order their own ready units (the client through requests to the
## host). At the end both print a checksum of their game (they must match),
## then both ask for a rematch, which must restart the game.
##
## Version check (run these two instead):
##   godot --headless --script res://tests/net_test.gd -- host_refuse
##   godot --headless --script res://tests/net_test.gd -- old_client
## The "old" client claims another protocol version and must be refused.

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")
const PORT := 7791

var net: Node
var config: Node
var state := GameState.new()
var ai := AIPlayer.new()
var starts := 0
var waiting := false
var chat_got := ""
var last_status := ""


func _initialize() -> void:
	await process_frame  # autoloads enter the tree after _initialize starts
	net = root.get_node("Net")
	config = root.get_node("GameConfig")
	net.game_started.connect(func(): starts += 1)
	net.chat_received.connect(func(text: String): chat_got = text)
	var on_rejected := func(reason: String) -> void:
		print("CLIENT REQUEST REJECTED: %s" % reason)
		waiting = false
	net.request_rejected.connect(on_rejected)
	net.status_changed.connect(func(text: String): last_status = text)
	var args := OS.get_cmdline_user_args()
	if args.has("host_refuse") or args.has("old_client"):
		await _version_test(args.has("host_refuse"))
		return
	var role := "host" if args.has("host") else "client"
	if role == "host":
		# The host's Battle Setup choices must reach the client.
		config.map_id = "river"
		config.rosters = [["monk", "archer", "squire", "white_mage"], ["knight", "black_mage", "archer", "monk"]]
	var err: int = net.host(PORT, false) if role == "host" else net.join("127.0.0.1", PORT)
	if err != OK:
		_finish(role, "could not start (%d)" % err)
		return

	if not await _wait(func(): return starts >= 1, 20.0):
		_finish(role, "never connected")
		return
	if config.map_id != "river" or config.rosters[0][0] != "monk":
		_finish(role, "host settings didn't arrive (map %s)" % config.map_id)
		return
	state.setup(config.build_map())
	if role == "client":
		net.send_chat("gl hf")

	var deadline := Time.get_ticks_msec() + 120000
	while state.winner == -1 and Time.get_ticks_msec() < deadline:
		if role == "host":
			while not net.requests.is_empty():
				var req: Dictionary = net.requests.pop_front()
				var req_err := state.validate(req)
				if req_err == "" and state.get_unit(req.unit).team != config.local_team:
					net.broadcast(req)
					state.apply(req)
				else:
					net.reject("rejected: %s" % req_err)
			var mine := state.ready_units(config.local_team)
			if state.winner != -1:
				pass
			elif not mine.is_empty():
				# Like the real game: validate before sending and applying.
				var cmd: Dictionary = ai.next_command(state, mine[0])
				var err_text := state.validate(cmd)
				if err_text != "":
					print("HOST AI ORDER REJECTED (%s): %s" % [err_text, cmd])
					cmd = {"type": "end_turn", "unit": mine[0].id, "serial": mine[0].serial}
				net.broadcast(cmd)
				state.apply(cmd)
			else:
				var step := {"type": "advance", "ticks": 5}
				net.broadcast(step)
				state.apply(step)
		else:
			_drain_inbox()
			var mine := state.ready_units(config.local_team)
			if not mine.is_empty() and not waiting and state.winner == -1:
				waiting = true
				net.send_request(ai.next_command(state, mine[0]))
		await process_frame

	# Let the last commands flush to the other side.
	for i in 60:
		await process_frame
		if role == "client":
			_drain_inbox()
	var summary := _summary(role)
	if role == "host" and chat_got != "gl hf":
		_finish(role, "chat didn't arrive (got '%s')" % chat_got, summary)
		return

	# Both ask for a rematch: the game must start again on both sides.
	net.request_rematch()
	if not await _wait(func(): return starts >= 2, 15.0):
		_finish(role, "rematch didn't start", summary)
		return
	# Keep running briefly so the restart message reaches the other side.
	for i in 60:
		await process_frame
	_finish(role, "", summary + " rematch=ok chat=ok")


func _drain_inbox() -> void:
	while not net.inbox.is_empty():
		var cmd: Dictionary = net.inbox.pop_front()
		var err_text := state.validate(cmd)
		if err_text == "":
			state.apply(cmd)
		else:
			print("CLIENT DROPPED HOST COMMAND (%s): %s" % [err_text, cmd])
		if cmd.type != "advance":
			waiting = false


func _wait(done: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not done.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return done.call()


func _version_test(is_host: bool) -> void:
	if is_host:
		net.host(PORT, false)
		var refused := await _wait(func(): return last_status.begins_with("Refused"), 20.0)
		_finish("host_refuse", "" if refused and starts == 0 else "old client was not refused (%s)" % last_status, "refused=%s" % refused)
	else:
		net.protocol_version = 1
		net.join("127.0.0.1", PORT)
		var told := await _wait(func(): return last_status.begins_with("Version mismatch"), 20.0)
		_finish("old_client", "" if told and starts == 0 else "no refusal message (%s)" % last_status, "told=%s" % told)


func _summary(role: String) -> String:
	var sums := []
	for u in state.units:
		sums.append("%d:%s:%d:%d" % [u.id, u.pos, u.hp, u.tg])
	return "%s team=%d winner=%d tick=%d checksum=%d" % [role, config.local_team, state.winner, state.tick, str(sums).hash()]


func _finish(role: String, error: String, summary := "") -> void:
	print("%s %s %s" % [role, summary if summary != "" else "", ("ERROR: " + error) if error != "" else "OK"])
	quit(1 if error != "" else 0)
