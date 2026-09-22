extends SceneTree
## Measures how long the computer takes per order, and its main parts, to
## find hitches.
##   godot --headless --script res://tests/profile_ai.gd

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")


func _initialize() -> void:
	await process_frame
	var ai := AIPlayer.new("hard")
	var state := GameState.new()
	state.setup(MapData.highlands())
	var times: Array[int] = []
	var parts := {"reachable_nodes": 0, "distance_from": 0, "best_action": 0, "validate": 0}
	var calls := {"reachable_nodes": 0, "distance_from": 0, "best_action": 0, "validate": 0}
	var worst := {}
	while state.winner == -1 and state.tick < 20000:
		var ready := state.ready_units()
		if ready.is_empty():
			state.apply({"type": "advance", "ticks": 1})
			continue
		var u = ready[0]
		# Break the decision into its parts.
		var t := Time.get_ticks_usec()
		var reach: Dictionary = {} if u.moved or u.is_casting() else state.reachable_nodes(u)
		parts.reachable_nodes += Time.get_ticks_usec() - t
		calls.reachable_nodes += 1
		if not u.acted:
			t = Time.get_ticks_usec()
			ai._best_action(state, u, reach)
			parts.best_action += Time.get_ticks_usec() - t
			calls.best_action += 1
		t = Time.get_ticks_usec()
		var goals: Array[Vector2] = [state.spawn_points[1 - u.team]]
		for e in state.team_units(1 - u.team):
			goals.append(e.pos)
		for g in goals:
			state.distance_from(g)
		parts.distance_from += Time.get_ticks_usec() - t
		calls.distance_from += 1

		var t0 := Time.get_ticks_usec()
		var cmd := ai.next_command(state, u)
		var dt := Time.get_ticks_usec() - t0
		t = Time.get_ticks_usec()
		state.validate(cmd)
		parts.validate += Time.get_ticks_usec() - t
		calls.validate += 1
		times.append(dt)
		if dt > worst.get("us", 0):
			worst = {"us": dt, "cmd": cmd.type, "job": u.job}
		state.apply(cmd)
	times.sort()
	print("orders=%d  median=%.1f ms  p90=%.1f ms  max=%.1f ms (%s, %s)" % [
		times.size(), times[times.size() / 2] / 1000.0, times[int(times.size() * 0.9)] / 1000.0,
		worst.us / 1000.0, worst.job, worst.cmd])
	for k in parts:
		print("  %-16s avg %.1f ms" % [k, parts[k] / 1000.0 / maxi(1, calls[k])])
	quit()
