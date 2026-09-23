extends SceneTree
## Balance check: each class plays in a mixed team ([class, Knight, Archer,
## White Mage]) against a fixed team ([Black Mage, Knight, Archer, White
## Mage]), computer vs computer (medium), sides alternating. Prints each
## class's win rate and its average damage dealt. Each pair of games (one per
## side) uses its own seed, so more games means a wider sample.
##   godot --headless --script res://tests/balance.gd -- [games per class] [class ids...]

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")
const Jobs = preload("res://scripts/core/jobs.gd")

const REFERENCE := ["black_mage", "knight", "archer", "white_mage"]


func _initialize() -> void:
	await process_frame  # autoloads (imported classes) first
	var args := OS.get_cmdline_user_args()
	var games := args[0].to_int() if args.size() > 0 else 8
	var ids: Array = args.slice(1) if args.size() > 1 else Jobs.all_jobs().keys()
	var ai := AIPlayer.new("medium")
	for id in ids:
		var wins := 0.0
		var dealt := 0
		var uses := [0, 0, 0, 0]
		var illegal := 0
		var alive_ticks := 0
		var ms := Time.get_ticks_msec()
		for g in games:
			var side := g % 2
			var mine := [id, "knight", "archer", "white_mage"]
			var rosters := [mine, REFERENCE] if side == 0 else [REFERENCE, mine]
			var state := GameState.new()
			# Each game gets its own seed, or every battle would play out the
			# same way and a class would score 0% or 100% on one lucky roll.
			state.setup(MapData.build(MapData.DEFAULT_MAP, rosters[0], rosters[1]), {}, 1 + (g / 2))
			var class_unit_id: int = state.units[0 if side == 0 else 4].id
			while state.winner == -1 and state.tick < 40000:
				var ready := state.orderable_units()
				var cmd: Dictionary = {"type": "advance", "ticks": 1} if ready.is_empty() else ai.next_command(state, ready[0])
				if state.validate(cmd) != "":
					illegal += 1
					cmd = {"type": "end_turn", "unit": ready[0].id, "serial": ready[0].serial}
				var result := state.apply(cmd)
				if result.knocked_out.has(class_unit_id) and not state.has_meta("ko_at_%d" % class_unit_id):
					state.set_meta("ko_at_%d" % class_unit_id, state.tick)
				for r in result.resolved:
					if r.unit == class_unit_id:
						uses[r.slot] += 1
						for i in r.hits.size():
							var t = state.get_unit(r.hits[i])
							if i < r.amounts.size() and (t == null or t.team != side):
								dealt += r.amounts[i]
			var me = state.get_unit(class_unit_id)
			alive_ticks += state.tick if me != null and me.is_alive() else state.get_meta("ko_at_%d" % class_unit_id, state.tick)
			if state.winner == side:
				wins += 1.0
			elif state.winner == -1:
				wins += 0.5
		print("%-18s win %3d%%   avg dealt %4d   uses %s   lives %3ds of the battle%s   (%d ms)" % [id, roundi(100.0 * wins / games), dealt / games,
			uses, alive_ticks / games / 10, "   ILLEGAL ORDERS %d" % illegal if illegal > 0 else "", Time.get_ticks_msec() - ms])
	quit()
