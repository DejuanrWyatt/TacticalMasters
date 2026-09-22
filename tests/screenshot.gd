extends SceneTree
## Opens a battle (vs computer) in a real window and saves a screenshot.
##   godot --script res://tests/screenshot.gd -- <output.png> [seconds] [ability_slot] [cast_after]
## Waits `seconds` of battle time (default 5) so units become ready. With an
## ability slot, that ability is selected and aimed at an enemy; with
## cast_after, it is also used and the shot taken that many seconds later.
## Add "guide" anywhere after "--" to open the Unit Guide before the shot.
## Menus instead: "-- out.png menu" (title screen) or "-- out.png setup <map_id>".
## "-- out.png 0 victory": a fast-replayed AI battle ending on the victory screen.
## "-- out.png devtools": Developer Tools (prints the slider tooltips too).
## Add "timemage" to put the imported Time Mage first on Blue, and "tips" to
## print the selected unit's calculation tooltips; "inspect <unit id>" opens
## that unit's stats card.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://screenshot.png"
	var seconds: float = args[1].to_float() if args.size() > 1 else 5.0
	if args.has("menu") or args.has("setup") or args.has("options") or args.has("howto") or args.has("devtools"):
		# Menu screens instead of a battle.
		var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
		root.add_child(menu)
		await process_frame
		if args.has("setup"):
			menu._open_setup("cpu" if args.has("cpu") else "ai")
			await process_frame
			menu.setup._select_map(args[args.find("setup") + 1] if args.size() > args.find("setup") + 1 else "highlands")
		if args.has("options"):
			menu._open_options()
		if args.has("devtools"):
			menu._open_dev_tools()
			menu.dev_tools._sliders.wits_multiplier.set_value_no_signal(1.5)
			menu.dev_tools._refresh()
			for key in ["wits_multiplier", "patience_multiplier", "damage_multiplier", "back_bonus", "cast_time_multiplier"]:
				print("--- tooltip ", key, "\n", menu.dev_tools._sliders[key].tooltip_text)
		if args.has("howto"):
			menu._open_how_to()
			menu.how_to._show_page(args[args.find("howto") + 1].to_int() if args.size() > args.find("howto") + 1 else 0)
		for i in 20:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		quit()
		return
	if args.has("victory"):
		# Simulate a computer-vs-computer battle, then replay it fast to the victory screen.
		var sim = preload("res://scripts/core/game_state.gd").new()
		sim.setup(preload("res://scripts/core/map_data.gd").highlands())
		var bot = preload("res://scripts/ai/ai_player.gd").new("hard")
		var log := []
		while sim.winner == -1 and sim.tick < 20000:
			var ready = sim.orderable_units()
			var cmd: Dictionary = {"type": "advance", "ticks": 1} if ready.is_empty() else bot.next_command(sim, ready[0])
			log.append(cmd)
			sim.apply(cmd)
		root.get_node("GameConfig").replay_log = log
	root.get_node("GameConfig").mode = "ai"
	if args.has("timemage"):
		root.get_node("GameConfig").rosters[0] = ["time_mage", "knight", "archer", "white_mage"]
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	if args.has("victory"):
		battle._replay_speed = 400.0
		while battle.state.winner == -1:
			await process_frame
		for i in 30:
			await process_frame
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
		for i in 200:
			await process_frame
	if args.has("inspect"):
		# Open a unit's stats card: "inspect <unit id>" (0-3 Blue, 4-7 Red).
		battle.inspected_id = args[args.find("inspect") + 1].to_int()
		for i in 20:
			await process_frame
	if args.has("tips") and battle._selected() != null:
		var hud = battle.hud
		print("--- unit card stats\n", hud._stats.tooltip_text)
		print("--- TG bar\n", hud._tg_bar.tooltip_text)
		for b in hud._ability_buttons:
			print("--- ", b.text.replace("\n", " / "), "\n", b.tooltip_text)
		print("--- hover\n", hud._hover.text)
		print("--- chip\n", hud._chips[0].tooltip_text)
	if OS.get_cmdline_user_args().has("guide"):
		battle.hud.toggle_guide()
		for i in 20:
			await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
