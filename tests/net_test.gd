extends SceneTree
## Two-process online test on localhost. Run both at once:
##   godot --headless --script res://tests/net_test.gd -- host
##   godot --headless --script res://tests/net_test.gd -- client
## Uses the real Net flow in fast-forward: the host moves time forward and
## both sides let the AI order their own ready units (the client through
## requests to the host). At the end both print a checksum of their game;
## the checksums must match.

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")
const PORT := 7791

var net: Node
var config: Node
var state := GameState.new()
var ai := AIPlayer.new()
var started := false
var waiting := false


func _initialize() -> void:
	await process_frame  # autoloads enter the tree after _initialize starts
	net = root.get_node("Net")
	config = root.get_node("GameConfig")
	state.setup(MapData.highlands())
	net.game_started.connect(func(): started = true)
	var role := "host" if OS.get_cmdline_user_args().has("host") else "client"
	var err: int = net.host(PORT) if role == "host" else net.join("127.0.0.1", PORT)
	if err != OK:
		_finish(role, "could not start (%d)" % err)
		return

	var deadline := Time.get_ticks_msec() + 20000
	while not started and Time.get_ticks_msec() < deadline:
		await process_frame
	if not started:
		_finish(role, "never connected")
		return

	deadline = Time.get_ticks_msec() + 120000
	while state.winner == -1 and Time.get_ticks_msec() < deadline:
		if role == "host":
			while not net.requests.is_empty():
				var req: Dictionary = net.requests.pop_front()
				if state.validate(req) == "" and state.get_unit(req.unit).team != config.local_team:
					net.broadcast(req)
					state.apply(req)
				else:
					net.reject("rejected")
			var mine := state.ready_units(config.local_team)
			if not mine.is_empty():
				var cmd: Dictionary = ai.next_command(state, mine[0])
				net.broadcast(cmd)
				state.apply(cmd)
			elif state.winner == -1:
				var step := {"type": "advance", "ticks": 5}
				net.broadcast(step)
				state.apply(step)
		else:
			while not net.inbox.is_empty():
				var cmd: Dictionary = net.inbox.pop_front()
				var err_text := state.validate(cmd)
				if err_text != "":
					_finish(role, "invalid command from host: " + err_text)
					return
				state.apply(cmd)
				if cmd.type != "advance":
					waiting = false
			var mine := state.ready_units(config.local_team)
			if not mine.is_empty() and not waiting and state.winner == -1:
				waiting = true
				net.send_request(ai.next_command(state, mine[0]))
		await process_frame

	# Let the last commands flush to the other side before closing.
	for i in 60:
		await process_frame
		if role == "client":
			while not net.inbox.is_empty():
				var cmd: Dictionary = net.inbox.pop_front()
				if state.validate(cmd) == "":
					state.apply(cmd)
	_finish(role, "")


func _finish(role: String, error: String) -> void:
	var sums := []
	for u in state.units:
		sums.append("%d:%s:%d:%d" % [u.id, u.pos, u.hp, u.tg])
	print("%s team=%d winner=%d tick=%d checksum=%d %s" % [
		role, config.local_team, state.winner, state.tick, str(sums).hash(), error])
	quit(1 if error != "" else 0)
