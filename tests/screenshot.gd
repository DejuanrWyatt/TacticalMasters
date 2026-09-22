extends SceneTree
## Opens a battle (vs computer) in a real window and saves a screenshot.
##   godot --script res://tests/screenshot.gd -- <output.png> [seconds] [ability_slot] [cast_after]
## Waits `seconds` of battle time (default 5) so units become ready. With an
## ability slot, that ability is selected and aimed at an enemy; with
## cast_after, it is also used and the shot taken that many seconds later.
## Add "guide" anywhere after "--" to open the Unit Guide before the shot.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://screenshot.png"
	var seconds: float = args[1].to_float() if args.size() > 1 else 5.0
	root.get_node("GameConfig").mode = "ai"
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
	if args.size() > 2 and args[2] != "guide" and battle._selected() != null:
		var sel = battle._selected()
		sel.pos = battle.state.units[4].pos + Vector2(-5, -1)  # stage an enemy in range
		battle.unit_views[sel.id].place(battle.board.ground(sel.pos))
		battle._select_ability(args[2].to_int())
		battle.hover_point = battle.state.units[4].pos
		battle.hover_unit_id = 4
		battle._refresh()
		battle.cam.focus_on(battle.board.ground(sel.pos))
		for i in 40:
			await process_frame
		if args.size() > 3:
			battle._on_click()
			var shot_at := Time.get_ticks_msec() + int(args[3].to_float() * 1000)
			while Time.get_ticks_msec() < shot_at:
				await process_frame
	if OS.get_cmdline_user_args().has("statuses"):
		# Stage: statuses on two units, one knocked out, all near the camera.
		var st = battle.state
		var blue = st.units[0]
		st._add_status(st.units[1], "burn", 30.0)
		st._add_status(st.units[1], "slow", 30.0)
		st._add_status(st.units[2], "regen", 30.0)
		st._add_status(st.units[3], "stun", 30.0)
		var result := {"logs": [], "knocked_out": []}
		st._knock_out(blue, "Blue Knight", result)
		battle.unit_views[blue.id].knock_out(0.0)
		battle._refresh()
		battle.cam.focus_on(battle.board.ground(st.units[1].pos))
		battle.cam._target_distance = 10.0
		for i in 60:
			await process_frame
	if OS.get_cmdline_user_args().has("guide"):
		battle.hud.toggle_guide()
		for i in 20:
			await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
