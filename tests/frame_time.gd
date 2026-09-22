extends SceneTree
## Runs a vs-computer battle in a real window and reports frame times, to
## catch stutters (slow frames) while turns are being taken.
##   godot --script res://tests/frame_time.gd -- [seconds] [difficulty]

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var seconds: float = args[0].to_float() if args.size() > 0 else 40.0
	var config := root.get_node("GameConfig")
	config.mode = "ai"
	config.ai_difficulty = args[1] if args.size() > 1 else "hard"
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	# Let the first frames (loading) pass before measuring.
	for i in 30:
		await process_frame
	var frames: Array[float] = []
	var slow := 0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames.append(ms)
		worst = maxf(worst, ms)
		if ms > 50.0:
			slow += 1
			# What was going on: recent messages and units' states.
			var log_lines := []
			for line in battle.hud._log_box.get_children():
				log_lines.append(line.text)
			var states := []
			for u in battle.state.units:
				states.append("%s%s%s%s" % [u.job.left(3), "R" if u.ready else "", "C" if u.is_casting() else "", "K" if u.is_ko() else ""])
			print("SLOW FRAME %.0f ms at tick %d | units %s | log %s" % [ms, battle.state.tick, states, log_lines])
	frames.sort()
	var orders: int = battle.state.tick
	print("frames=%d  median=%.1f ms  p99=%.1f ms  worst=%.1f ms  frames over 50 ms=%d  (battle tick %d)" % [
		frames.size(), frames[frames.size() / 2], frames[int(frames.size() * 0.99)], worst, slow, orders])
	quit()
