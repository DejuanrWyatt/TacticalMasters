extends SceneTree
## Headless smoke test. Run from the project folder:
##   godot --headless --script res://tests/smoke_test.gd
## Checks the core rules, plays a full AI-vs-AI battle in simulated real
## time, and loads the scenes.

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")
const Jobs = preload("res://scripts/core/jobs.gd")
const AstraImport = preload("res://scripts/core/astra_import.gd")

var failures := 0


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	_test_rules()
	_test_ai_battle()
	_test_maps()
	var replay_log := _test_replay_determinism()
	_test_tuning()
	_test_astra_import()
	await _test_scenes()
	await _test_dev_tools()
	await _test_cpu_vs_cpu()
	await _test_log_window()
	await _test_replay_scene(replay_log)
	print("SMOKE TEST %s (%d failure(s))" % ["PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


func _new_state() -> GameState:
	var state := GameState.new()
	state.setup(MapData.highlands())
	return state


## Advances time until some unit is ready; returns it.
func _wait_for_ready(state: GameState) -> Object:
	for i in 1000:
		if not state.ready_units().is_empty():
			return state.ready_units()[0]
		state.apply({"type": "advance", "ticks": 1})
	return null


func _test_rules() -> void:
	var state := _new_state()
	_check(state.size_meters() == Vector2(24, 24), "map is 24 x 24 m")
	_check(not state.heights.has(0), "default map has no water")
	_check(state.units.size() == 8, "4 units per side")
	for u in state.units:
		_check(not state.is_water(u.pos) and u.pos == state.snap(u.pos), "unit %d on land, on a nav node" % u.id)
	_check(state.ready_units().is_empty(), "nobody ready at the start")

	var u = _wait_for_ready(state)
	_check(u != null and u.job == "archer", "fastest unit (archer, Wits 10) is ready first")
	_check(state.validate({"type": "end_turn", "unit": u.id, "serial": u.serial - 1}) != "", "stale serial rejected")
	_check(state.validate({"type": "ability", "unit": u.id, "serial": u.serial, "slot": 3, "target": u.pos}) != "", "ultimate locked until meter full")
	_check(state.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": Vector2(20.25, 20.25)}) != "", "can't move beyond Move")
	var other = state.units[0] if u.id != 0 else state.units[2]
	_check(state.validate({"type": "end_turn", "unit": other.id, "serial": other.serial}) != "", "a unit that isn't ready can't act")

	# Radial movement: a reachable spot 5 m away, not on the grid axes.
	var reach: Dictionary = state.reachable_nodes(u)
	var far := Vector2.ZERO
	for n in reach:
		if reach[n] > 4.0 and reach[n] <= u.stat("move"):
			far = state.node_pos(n)
			break
	_check(far != Vector2.ZERO, "spots 4+ m away are reachable")
	var path := state.path_to(u, state.node_of(far))
	_check(path.size() >= 2 and path[0] == u.pos and path[-1] == far, "path runs from the unit to the spot")
	_check(state.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": far}) == "", "move to reachable spot is legal")
	state.apply({"type": "move", "unit": u.id, "serial": u.serial, "to": far})
	_check(u.pos == far and u.moved, "unit moved")

	# Countdown: doing nothing loses the turn.
	var serial: int = u.serial
	for i in state.clock_ticks(u) + 1:
		state.apply({"type": "advance", "ticks": 1})
		if not u.ready:
			break
	_check(not u.ready and u.tg == 0 and u.serial == serial, "countdown expiry ends the turn with TG 0")

	# Abilities by distance, cooldowns and the ultimate meter.
	var s2 := _new_state()
	var archer = _wait_for_ready(s2)
	var enemy = s2.units[4]
	archer.pos = Vector2(10.25, 10.25)
	enemy.pos = Vector2(10.25, 15.25)  # 5 m away
	var order := {"type": "ability", "unit": archer.id, "serial": archer.serial, "slot": 2, "target": enemy.pos}
	_check(s2.validate(order) == "", "pin shot legal at 5 m")
	var hp_before: int = enemy.hp
	s2.apply(order)
	_check(enemy.hp < hp_before, "pin shot (instant) deals damage")
	_check(archer.cooldowns[2] > 0, "pin shot goes on cooldown")
	_check(archer.ult > 0 and enemy.ult > 0, "ultimate meter charges for attacker and target")
	archer.ult = GameState.ULT_MAX
	archer.acted = false
	var ult := {"type": "ability", "unit": archer.id, "serial": archer.serial, "slot": 3, "target": enemy.pos + Vector2(1, 0)}
	_check(s2.validate(ult) == "", "area ultimate legal on a point near the enemy")
	s2.apply(ult)
	_check(archer.ult == 0, "ultimate empties the meter")
	_test_casting()
	_test_facing()
	_test_statuses()
	_test_ko_and_raise()
	_test_line_of_sight()


## Stages a ready attacker and a target at given spots.
func _stage(state: GameState, attacker, target, attacker_pos: Vector2, target_pos: Vector2) -> void:
	attacker.pos = attacker_pos
	target.pos = target_pos
	_force_ready(state, attacker)


func _test_facing() -> void:
	var dealt := {}
	for side in ["front", "side", "back"]:
		var s := _new_state()
		var knight = s.units[0]
		var foe = s.units[4]
		_stage(s, knight, foe, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
		# The attacker is on the foe's -x side: "front" means the foe faces -x.
		foe.facing = {"front": Vector2(-1, 0), "side": Vector2(0, 1), "back": Vector2(1, 0)}[side]
		var hp: int = foe.hp
		s.apply({"type": "ability", "unit": knight.id, "serial": knight.serial, "slot": 0, "target": foe.pos})
		dealt[side] = hp - foe.hp
	_check(dealt.back > dealt.side and dealt.side > dealt.front, "back > side > front damage (%s)" % dealt)
	var s2 := _new_state()
	var u = _wait_for_ready(s2)
	var to := Vector2(u.pos.x + 2.0, u.pos.y)
	s2.apply({"type": "move", "unit": u.id, "serial": u.serial, "to": to})
	_check(u.facing.x > 0.5, "a unit faces the way it walked")


func _test_statuses() -> void:
	# Fire burns: HP keeps dropping each second, then it wears off.
	var s := _new_state()
	var mage = s.units[2]
	var foe = s.units[4]
	_stage(s, mage, foe, Vector2(10.25, 10.25), Vector2(10.25, 14.25))
	s.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": foe.pos, "follow": foe.id})
	s.apply({"type": "advance", "ticks": 10})  # 1 s cast
	_check(foe.has_status("burn"), "Fire leaves Burn")
	var hp_after_hit: int = foe.hp
	s.apply({"type": "advance", "ticks": 20})
	_check(foe.hp < hp_after_hit, "Burn deals damage over time")
	s.apply({"type": "advance", "ticks": 50})
	_check(not foe.has_status("burn"), "Burn wears off after 6 s")

	# Slow halves Turn Gauge filling; Stun freezes it and blocks orders.
	var s2 := _new_state()
	var u = s2.units[0]
	u.tg = 0
	var normal: int = s2.ticks_to_ready(u)
	s2._add_status(u, "slow", 30.0)
	_check(s2.ticks_to_ready(u) > normal * 1.8, "Slow roughly halves Turn Gauge speed")
	u.statuses.clear()
	var tg_before: int = u.tg
	s2._add_status(u, "stun", 1.0)
	s2.apply({"type": "advance", "ticks": 5})
	_check(u.tg == tg_before, "Stun freezes the Turn Gauge")
	u.statuses.clear()
	_force_ready(s2, u)
	s2._add_status(u, "stun", 2.0)
	_check(s2.validate({"type": "end_turn", "unit": u.id, "serial": u.serial}) != "", "a stunned unit can't take orders")

	# Shield Bash stuns.
	var s3 := _new_state()
	var knight = s3.units[0]
	foe = s3.units[4]
	_stage(s3, knight, foe, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	s3.apply({"type": "ability", "unit": knight.id, "serial": knight.serial, "slot": 1, "target": foe.pos})
	_check(foe.has_status("stun"), "Shield Bash stuns")


func _test_ko_and_raise() -> void:
	var s := _new_state()
	var knight = s.units[0]
	var healer = s.units[3]  # White Mage
	var foe = s.units[4]
	_stage(s, foe, knight, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	knight.hp = 1
	s.apply({"type": "ability", "unit": foe.id, "serial": foe.serial, "slot": 0, "target": knight.pos})
	_check(knight.is_ko() and not knight.is_alive(), "a unit at 0 HP is knocked out, not gone")
	_check(not s.team_units(0).has(knight), "KO'd units don't count as alive")
	healer.pos = Vector2(10.25, 13.25)
	_force_ready(s, healer)
	var raise := {"type": "ability", "unit": healer.id, "serial": healer.serial, "slot": 0, "target": knight.pos, "follow": knight.id}
	_check(s.validate(raise) == "", "Raise can target a knocked-out ally (%s)" % s.validate(raise))
	s.apply(raise)
	s.apply({"type": "advance", "ticks": 20})  # 2 s cast
	_check(knight.is_alive() and knight.hp == roundi(knight.max_hp() * 0.3), "Raise revives with 30% HP")

	# Without help, a KO'd unit is gone after KO_SECONDS.
	var s2 := _new_state()
	var victim = s2.units[1]
	var hitter = s2.units[4]
	_stage(s2, hitter, victim, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	victim.hp = 1
	s2.apply({"type": "ability", "unit": hitter.id, "serial": hitter.serial, "slot": 0, "target": victim.pos})
	for i in roundi(GameState.KO_SECONDS * GameState.TICKS_PER_SECOND) + 1:
		s2.apply({"type": "advance", "ticks": 1})
	_check(not victim.is_ko() and not victim.is_alive(), "a KO'd unit is gone after %ds" % GameState.KO_SECONDS)

	# Snapshots copy the new state.
	var s3 := _new_state()
	s3._add_status(s3.units[1], "burn", 3.0)
	var snap = s3.snapshot()
	_check(snap.units[1].has_status("burn") and snap.units[1].facing == s3.units[1].facing, "snapshot copies statuses and facing")


func _test_line_of_sight() -> void:
	var s := _new_state()
	# Row y=1 m crosses the level-3 hill (x 8-12 m) between two level-1 spots.
	_check(not s.has_line_of_sight(Vector2(2.75, 1.25), Vector2(15.25, 1.25)), "a tall hill blocks line of sight")
	# Row y=7 m is flat ground.
	_check(s.has_line_of_sight(Vector2(2.75, 7.25), Vector2(15.25, 7.25)), "flat ground doesn't block line of sight")
	var archer = s.units[1]
	var foe = s.units[4]
	_stage(s, archer, foe, Vector2(2.75, 1.25), Vector2(11.25, 1.75))
	foe.pos = Vector2(14.75, 1.25)
	_check(s.validate({"type": "ability", "unit": archer.id, "serial": archer.serial, "slot": 0, "target": foe.pos}) != "",
		"can't shoot through a hill")


## Makes a unit ready right now, for staging a situation.
func _force_ready(state: GameState, u) -> void:
	u.tg = GameState.TG_MAX - 1
	for i in 5:
		if u.ready:
			return
		state.apply({"type": "advance", "ticks": 1})


func _test_casting() -> void:
	# Instant: a melee attack lands immediately.
	var s := _new_state()
	var knight = s.units[0]
	var foe = s.units[4]
	knight.pos = Vector2(10.25, 10.25)
	foe.pos = Vector2(11.25, 10.25)
	_force_ready(s, knight)
	var hp: int = foe.hp
	s.apply({"type": "ability", "unit": knight.id, "serial": knight.serial, "slot": 0, "target": foe.pos})
	_check(foe.hp < hp and not knight.is_casting(), "melee attack is instant")
	var retreat := {"type": "move", "unit": knight.id, "serial": knight.serial, "to": Vector2(8.25, 10.25)}
	_check(s.validate(retreat) == "", "a unit can move after an instant ability")

	# Cast: Fire takes 1 s, ends the caster's turn, and follows its target.
	s = _new_state()
	var mage = s.units[2]
	foe = s.units[4]
	mage.pos = Vector2(10.25, 10.25)
	foe.pos = Vector2(10.25, 14.25)
	_force_ready(s, mage)
	hp = foe.hp
	s.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": foe.pos, "follow": foe.id})
	_check(foe.hp == hp and mage.is_casting(), "Fire starts casting")
	var walk := {"type": "move", "unit": mage.id, "serial": mage.serial, "to": Vector2(9.25, 10.25)}
	_check(s.validate(walk) != "", "a unit can't move after starting a cast")
	s.apply({"type": "end_turn", "unit": mage.id, "serial": mage.serial})
	var tg_before: int = mage.tg
	foe.pos = Vector2(12.25, 14.25)  # the target walks away; a spell aimed at it follows
	s.apply({"type": "advance", "ticks": 5})
	_check(mage.tg == tg_before and mage.is_casting(), "after the turn ends, TG doesn't fill while the cast finishes")
	s.apply({"type": "advance", "ticks": 5})
	_check(foe.hp < hp and not mage.is_casting(), "Fire lands after its 1 s cast, on the moved target")

	# Area spells land on the chosen point: walking out dodges them.
	s = _new_state()
	mage = s.units[2]
	foe = s.units[4]
	mage.pos = Vector2(10.25, 10.25)
	foe.pos = Vector2(10.25, 14.25)
	_force_ready(s, mage)
	hp = foe.hp
	s.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 2, "target": foe.pos})
	foe.pos = Vector2(16.25, 14.25)
	s.apply({"type": "advance", "ticks": 20})
	_check(foe.hp == hp and not mage.is_casting(), "moving out of Blizzard's area dodges it")

	# Ground targeting: aim Fire at the spot an enemy is walking to.
	s = _new_state()
	mage = s.units[2]
	foe = s.units[4]
	mage.pos = Vector2(10.25, 10.25)
	foe.pos = Vector2(14.25, 14.25)
	_force_ready(s, mage)
	hp = foe.hp
	var spot := Vector2(10.25, 14.25)
	var fire := {"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": spot, "follow": -1}
	_check(s.validate(fire) == "", "abilities can target empty ground")
	var bad_follow := fire.duplicate()
	bad_follow.follow = foe.id
	_check(s.validate(bad_follow) != "", "following a unit that isn't at the target is rejected")
	s.apply(fire)
	foe.pos = spot  # the enemy walks into the predicted spot
	s.apply({"type": "advance", "ticks": 10})
	_check(foe.hp < hp, "ground-targeted Fire hits the unit that walked into it")

	# A caster defeated mid-cast loses the spell.
	s = _new_state()
	mage = s.units[2]
	foe = s.units[4]
	mage.pos = Vector2(10.25, 10.25)
	foe.pos = Vector2(10.25, 14.25)
	_force_ready(s, mage)
	s.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": foe.pos})
	var enemy_knight = s.units[4]
	enemy_knight.pos = Vector2(11.25, 10.25)
	mage.hp = 1
	_force_ready(s, enemy_knight)
	s.apply({"type": "ability", "unit": enemy_knight.id, "serial": enemy_knight.serial, "slot": 0, "target": mage.pos})
	_check(not mage.is_alive() and not mage.is_casting(), "defeated caster's spell fizzles")


func _test_maps() -> void:
	var ai := AIPlayer.new("hard")
	for id in MapData.map_ids():
		var state := GameState.new()
		state.setup(MapData.build(id, ["knight", "monk", "archer", "black_mage"], ["squire", "white_mage", "archer", "knight"]))
		_check(state.units.size() == 8, "%s: 8 units" % id)
		for u in state.units:
			_check(not state.is_water(u.pos) and u.pos == state.snap(u.pos), "%s: unit %d starts on land" % [id, u.id])
			_check(state.reachable_nodes(u).size() > 20, "%s: unit %d can move from its start" % [id, u.id])
		_check(state.units[1].job == "monk" and state.units[5].job == "white_mage", "%s: rosters applied" % id)
		# A short AI-vs-AI skirmish: every order must be legal on every map.
		while state.winner == -1 and state.tick < 3000:
			var ready := state.orderable_units()
			if ready.is_empty():
				state.apply({"type": "advance", "ticks": 1})
				continue
			var cmd := ai.next_command(state, ready[0])
			var err := state.validate(cmd)
			_check(err == "", "%s: AI order legal (%s)" % [id, err])
			if err != "":
				break
			state.apply(cmd)


## Replays are exact: the same commands on a fresh state give the same battle.
func _test_replay_determinism() -> Array:
	var ai := AIPlayer.new("hard")
	var state := _new_state()
	var log := []
	while state.winner == -1 and state.tick < 20000:
		var ready := state.orderable_units()
		var cmd: Dictionary
		if ready.is_empty():
			cmd = {"type": "advance", "ticks": 1}
		else:
			cmd = ai.next_command(state, ready[0])
		log.append(cmd)
		state.apply(cmd)
	var replayed := _new_state()
	for cmd in log:
		replayed.apply(cmd)
	var same := replayed.winner == state.winner and replayed.tick == state.tick
	for i in state.units.size():
		same = same and replayed.units[i].hp == state.units[i].hp and replayed.units[i].pos == state.units[i].pos
	_check(same, "replaying the command log reproduces the battle exactly")
	return log


func _test_ai_battle() -> void:
	var ai := AIPlayer.new()
	var state := _new_state()
	var orders := 0
	var start := Time.get_ticks_msec()
	while state.winner == -1 and state.tick < 20000:
		var ready := state.orderable_units()
		if ready.is_empty():
			state.apply({"type": "advance", "ticks": 1})
			continue
		var cmd := ai.next_command(state, ready[0])
		var err := state.validate(cmd)
		_check(err == "", "AI command legal: %s (%s)" % [cmd, err])
		if err != "":
			return
		state.apply(cmd)
		orders += 1
	print("AI vs AI: winner=%d battle time=%.0fs orders=%d (%d ms to simulate)" % [
		state.winner, state.tick / 10.0, orders, Time.get_ticks_msec() - start])
	_check(state.winner != -1, "AI vs AI battle finishes")

	# The computer thinks on a snapshot; it must decide exactly as on the live state.
	var live := _new_state()
	var first = _wait_for_ready(live)
	var snap = live.snapshot()
	var on_live := ai.next_command(live, first)
	var on_snap := ai.next_command(snap, snap.get_unit(first.id))
	_check(str(on_live) == str(on_snap), "AI decides the same on a snapshot as on the live state")
	snap.get_unit(first.id).hp = 1
	_check(first.hp != 1, "snapshot units are independent copies")

	# Easy (random mistakes) against hard: orders must still be legal.
	var easy := AIPlayer.new("easy")
	var hard := AIPlayer.new("hard")
	state = _new_state()
	var wins := [0, 0]
	for game in 3:
		state = _new_state()
		while state.winner == -1 and state.tick < 30000:
			var ready := state.orderable_units()
			if ready.is_empty():
				state.apply({"type": "advance", "ticks": 1})
				continue
			var cmd := (easy if ready[0].team == 0 else hard).next_command(state, ready[0])
			var err := state.validate(cmd)
			_check(err == "", "easy/hard AI command legal: %s (%s)" % [cmd, err])
			if err != "":
				return
			state.apply(cmd)
		if state.winner >= 0:
			wins[state.winner] += 1
	print("Easy (Blue) vs Hard (Red) over 3 games: easy %d, hard %d" % wins)
	_check(wins[1] >= wins[0], "hard beats easy at least as often as it loses")


## Developer Tools rule numbers ("tuning") and the "tune" command.
func _test_tuning() -> void:
	var plain := _new_state()
	_check(plain.tune("wits_multiplier") == 1.0 and plain.tune("patience_multiplier") == GameState.CLOCK_PER_PATIENCE,
		"default tuning matches the rule constants")
	var fast := GameState.new()
	fast.setup(MapData.highlands(), {"wits_multiplier": 2.0, "patience_multiplier": 3.0, "bogus": 5, "move_multiplier": 99.0})
	var u = fast.units[0]
	_check(fast._tg_gain(u) == 2 * plain._tg_gain(plain.units[0]), "Wits multiplier doubles Turn Gauge speed")
	_check(fast.clock_ticks(u) == roundi((GameState.CLOCK_BASE + 3.0 * u.stat("patience")) * 10), "Patience multiplier sets the countdown")
	_check(not fast.tuning.has("bogus") and fast.tune("move_multiplier") == GameState.TUNING.move_multiplier[2],
		"unknown tuning keys are dropped and values clamped")
	_check(fast.snapshot().tuning == fast.tuning, "snapshot copies the tuning")
	_check(fast.reachable_nodes(u).size() > plain.reachable_nodes(plain.units[0]).size(), "Move multiplier widens the walk area")
	_check(plain.validate({"type": "tune", "values": {"nope": 1}}) != "", "a tune with an unknown key is rejected")
	_check(plain.validate({"type": "tune", "values": {"damage_multiplier": 1.0}}) == "", "a valid tune is accepted")

	# Explanations use the same numbers as the rules.
	var a = plain.units[0]
	var t = plain.units[4]
	var from: Vector2 = t.pos + t.facing * 0.3
	var amount: int = plain._amount(a, a.ability(0), from, t, t.pos)
	_check(plain.explain_hit(a, 0, from, t).contains("= %d" % amount), "damage explanation ends in the real damage (%d)" % amount)
	plain.apply({"type": "tune", "values": {"damage_multiplier": 1.0}})
	var doubled: int = plain._amount(a, a.ability(0), from, t, t.pos)
	_check(doubled > amount and plain.explain_hit(a, 0, from, t).contains("= %d" % doubled), "a tune changes damage and its explanation")
	_check(plain.explain_turn(a).contains("Wits %d" % a.stat("wits")) and plain.explain_countdown(a).contains("Patience"),
		"turn and countdown explanations name their stats")

	# A tune in the middle of a battle replays exactly.
	var ai := AIPlayer.new()
	var state := _new_state()
	var log: Array = []
	while state.winner == -1 and state.tick < 20000:
		if state.tick == 300 and log.size() > 0 and log[-1].type != "tune":
			var tune := {"type": "tune", "values": {"wits_multiplier": 1.5, "damage_multiplier": 0.8, "cast_time_multiplier": 0.5}}
			log.append(tune)
			state.apply(tune)
		var ready := state.orderable_units()
		var cmd: Dictionary = {"type": "advance", "ticks": 1} if ready.is_empty() else ai.next_command(state, ready[0])
		log.append(cmd)
		state.apply(cmd)
	var replayed := _new_state()
	for cmd in log:
		replayed.apply(cmd)
	var same := replayed.winner == state.winner and replayed.tick == state.tick and replayed.tuning == state.tuning
	for i in state.units.size():
		same = same and replayed.units[i].hp == state.units[i].hp and replayed.units[i].pos == state.units[i].pos
	_check(same and state.winner != -1, "a battle with a mid-battle tune finishes and replays exactly")

	var ko := GameState.new()
	ko.setup(MapData.highlands(), {"ko_seconds": 0.0})
	var result := {"logs": [], "gone": [], "knocked_out": []}
	ko._knock_out(ko.units[0], "x", result)
	_check(result.gone.has(ko.units[0].id) and not ko.units[0].is_ko(), "KO time 0 removes a unit at once")


## Classes made in Astra Ability Creator.
func _test_astra_import() -> void:
	var vars := {"a": 2.0, "b": 3.0}
	_check(AstraImport.evaluate("1 + 2 * 3", {}) == 7.0, "Astra formula: precedence")
	_check(AstraImport.evaluate("(a + b) * 10%", vars) == 0.5, "Astra formula: variables, parentheses, %")
	_check(AstraImport.evaluate("-a - -b", vars) == 1.0, "Astra formula: unary minus")
	_check(AstraImport.evaluate("a +", vars) is String and AstraImport.evaluate("x * 2", vars) is String
		and AstraImport.evaluate("1 / 0", vars) is String and AstraImport.evaluate("a; b", vars) is String,
		"Astra formula: bad input gives an error, never a crash")
	var p := {"base": 10, "step": 20, "mode": "% increase", "every": 2, "floorZero": true, "overrides": {"4": "rank * 3"}}
	_check(AstraImport.rank_value(p, 1) == "10" and AstraImport.rank_value(p, 3) == "12" and AstraImport.rank_value(p, 4) == "rank * 3",
		"Astra rank values: steps every N ranks, overrides win")

	var text := FileAccess.get_file_as_string("res://data/classes/time_mage.astra.json")
	var parsed := AstraImport.parse(text)
	_check(parsed.errors.is_empty() and parsed.jobs.has("time_mage"), "Time Mage imports from its Astra export (%s)" % [parsed.errors])
	_check(Jobs.has_job("time_mage"), "imported classes are registered at startup")
	if not Jobs.has_job("time_mage"):
		return
	var tm: Dictionary = Jobs.job("time_mage")
	_check(tm.wits == 12 and tm.mag == 16 and tm.abilities.size() == 4, "Time Mage stats come from its profile")
	var bolt: Dictionary = Jobs.ability(tm.abilities[0])
	_check(bolt.effect == "damage" and bolt.cast == 0.0 and bolt.power == 1.0 and bolt.tg == -10, "Chrono Bolt: instant damage, formula power, TG -10%")
	var stop: Dictionary = Jobs.ability(tm.abilities[3])
	_check(stop.status.id == "stun" and stop.aoe == 3.0 and stop.fx == "meteor", "Time Stop: area Stun with a borrowed animation")
	_check(Jobs.ability(tm.abilities[1]).status.id == "slow" and Jobs.ability(tm.abilities[2]).tg == 40, "Slowga slows, Quicken +40% TG")
	var bad := AstraImport.parse(text.replace("\"profile\"", "\"nothing\""))
	_check(bad.jobs.is_empty() and not bad.errors.is_empty(), "a class without a profile is skipped with a message")

	# A battle with Time Mages on both sides plays out with legal orders.
	var ai := AIPlayer.new()
	var state := GameState.new()
	state.setup(MapData.build(MapData.DEFAULT_MAP, ["time_mage", "knight", "archer", "white_mage"], ["time_mage", "monk", "black_mage", "knight"]))
	var legal := true
	while state.winner == -1 and state.tick < 30000 and legal:
		var ready := state.orderable_units()
		if ready.is_empty():
			state.apply({"type": "advance", "ticks": 1})
			continue
		var cmd := ai.next_command(state, ready[0])
		legal = state.validate(cmd) == ""
		if not legal:
			printerr("illegal: ", cmd, " ", state.validate(cmd))
		state.apply(cmd)
	_check(legal and state.winner != -1, "a battle with Time Mages finishes with legal orders")
	var sent := Jobs.classes_for([["time_mage"], ["knight"]])
	_check(sent.jobs.has("time_mage") and sent.abilities.size() == 4 and not sent.jobs.has("knight"),
		"online sends only the imported classes in use")


## Computer vs Computer: both teams give their own orders; nobody else can.
func _test_cpu_vs_cpu() -> void:
	var config := root.get_node("GameConfig")
	var saved := [config.mode, config.ai_difficulty, config.ai_difficulty_blue]
	config.mode = "cpu"
	config.ai_difficulty = "hard"
	config.ai_difficulty_blue = "easy"
	_check(config.ai_teams() == [0, 1] and config.difficulty_for(0) == "easy" and config.difficulty_for(1) == "hard",
		"Computer vs Computer: both teams are the computer, each with its own difficulty")
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	var ordered := [false, false]
	var deadline := Time.get_ticks_msec() + 40000
	while not (ordered[0] and ordered[1]) and Time.get_ticks_msec() < deadline:
		await process_frame
		for cmd in battle.command_log:
			if cmd.has("unit"):
				ordered[battle.state.get_unit(cmd.unit).team] = true
	_check(ordered[0] and ordered[1], "Computer vs Computer: both computers give orders")
	_check(battle.viewer_team == -1 and battle._controller(0) == "ai" and battle._controller(1) == "ai",
		"Computer vs Computer: the whole field is visible and no team takes player orders")
	battle.queue_free()
	await process_frame
	config.mode = saved[0]
	config.ai_difficulty = saved[1]
	config.ai_difficulty_blue = saved[2]


## Combat log window: keeps messages, moves, resizes, collapses, hides and
## remembers its place. The player's saved layout is put back afterwards.
func _test_log_window() -> void:
	var LogWindow = load("res://scripts/ui/log_window.gd")
	var saved_cfg := FileAccess.get_file_as_string(LogWindow.SAVE_PATH) if FileAccess.file_exists(LogWindow.SAVE_PATH) else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LogWindow.SAVE_PATH))
	var log = LogWindow.new()
	root.add_child(log)
	await process_frame
	for i in 350:
		log.add_message("message %d" % i)
	_check(log.line_count() == LogWindow.MAX_LINES, "combat log keeps the latest %d messages" % LogWindow.MAX_LINES)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = Vector2(100, 110)
	var drag := InputEventMouseMotion.new()
	drag.global_position = Vector2(160, 150)
	var release := press.duplicate()
	release.pressed = false
	var start: Vector2 = log.position
	log._drag_input(press, "move")
	log._drag_input(drag, "move")
	log._drag_input(release, "move")
	_check(log.position == start + Vector2(60, 40), "dragging the title bar moves the combat log")
	var before: Vector2 = log.size
	log._drag_input(press, "resize")
	drag.global_position = Vector2(100 - 500, 110 - 500)
	log._drag_input(drag, "resize")
	log._drag_input(release, "resize")
	_check(log.size == LogWindow.MIN_SIZE and before != log.size, "resizing stops at the minimum size")
	log.toggle_collapsed()
	_check(not log._body.visible and log.size.y < LogWindow.MIN_SIZE.y, "collapsing leaves only the title bar")
	log.toggle_collapsed()
	log.hide_log()
	var again = LogWindow.new()
	root.add_child(again)
	await process_frame
	_check(not again.visible and again.position == log.position, "the combat log remembers where it was and that it was hidden")
	log.queue_free()
	again.queue_free()
	if saved_cfg != "":
		var f := FileAccess.open(LogWindow.SAVE_PATH, FileAccess.WRITE)
		f.store_string(saved_cfg)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LogWindow.SAVE_PATH))


## Developer Tools: sliders, saved values and formula tooltips.
func _test_dev_tools() -> void:
	var config := root.get_node("GameConfig")
	var saved: Dictionary = config.tuning.duplicate()
	var tools: Control = load("res://scripts/ui/dev_tools.gd").new()
	tools.live = true
	var sent: Array = []
	tools.tuning_changed.connect(func(v: Dictionary): sent.append(v))
	root.add_child(tools)
	await process_frame
	var sliders: Array = tools.find_children("*", "HSlider", true, false)
	_check(sliders.size() == GameState.TUNING.size(), "Developer Tools has a slider per rule number")
	tools._sliders.wits_multiplier.value = 1.5
	_check(config.tuning.get("wits_multiplier") == 1.5, "moving a slider saves the value")
	var tip: String = tools._sliders.wits_multiplier.tooltip_text
	_check(tip.contains("Wits multiplier 1.5") and tip.contains("= "), "the slider tooltip shows the formula with the new value")
	_check(tools._sliders.patience_multiplier.tooltip_text.contains("Patience"), "the Patience slider tooltip shows the countdown math")
	for i in 30:
		await process_frame
	_check(sent.size() == 1 and sent[0].get("wits_multiplier") == 1.5, "a live battle gets the change once, after the slider settles")
	tools._reset_all()
	_check(config.tuning.is_empty(), "Reset all restores the defaults")
	tools.queue_free()
	config.tuning = saved
	config.save_tuning()


## The battle scene plays a recorded log back (fast) to the same winner.
func _test_replay_scene(log: Array) -> void:
	var expected := _new_state()
	for cmd in log:
		expected.apply(cmd)
	var config: Node = root.get_node("GameConfig")
	config.mode = "ai"
	config.replay_log = log
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.replaying, "battle scene starts in replay mode")
	scene._replay_speed = 400.0
	for i in 600:
		await process_frame
		if scene.state.winner != -1:
			break
	_check(scene.state.winner == expected.winner and scene.state.tick == expected.tick,
		"replay scene reaches the same result (winner %d tick %d vs %d %d)" % [scene.state.winner, scene.state.tick, expected.winner, expected.tick])
	_check(scene.hud._game_over.visible, "victory screen shows at the end of the replay")
	scene.queue_free()
	await process_frame


func _test_scenes() -> void:
	# Every script must compile (a broken script otherwise only prints errors).
	for path in ["res://scripts/battle/battle.gd", "res://scripts/battle/hud.gd", "res://scripts/battle/board_view.gd",
			"res://scripts/battle/unit_view.gd", "res://scripts/battle/fx.gd", "res://scripts/battle/camera_rig.gd",
			"res://scripts/ui/unit_guide.gd", "res://scripts/ui/options_menu.gd", "res://scripts/main_menu.gd",
			"res://scripts/ui/battle_setup.gd", "res://scripts/ui/ui_theme.gd", "res://scripts/ui/how_to_play.gd",
			"res://scripts/autoload/settings.gd", "res://scripts/autoload/audio.gd",
			"res://scripts/autoload/net.gd", "res://scripts/autoload/keybinds.gd"]:
		var script: Script = load(path)
		_check(script != null and script.can_instantiate(), "%s compiles" % path)
	if failures > 0:
		return
	for mode in ["ai", "hotseat"]:
		root.get_node("GameConfig").mode = mode
		var scene: Node = load("res://scenes/battle.tscn").instantiate()
		root.add_child(scene)
		for i in 5:
			await process_frame
		_check(scene.state.units.size() == 8 and scene.unit_views.size() == 8 and scene.hud != null, "battle scene (%s) builds" % mode)
		if mode == "ai":
			# Play every ability animation once; script errors show up in the log.
			var view = scene.unit_views[0]
			var from: Vector3 = view.position + Vector3(0, 0.9, 0)
			for id in preload("res://scripts/core/jobs.gd").ABILITIES:
				var aoe: float = preload("res://scripts/core/jobs.gd").ABILITIES[id].aoe
				var delay: float = scene.fx.play(id, view, from, view.position + Vector3(4, 0, 2), maxf(aoe, 1.0))
				_check(delay >= 0.0 and delay < 3.0, "animation for %s has a sensible impact time" % id)
			var steps: Array[Vector3] = [view.position + Vector3(1, 0, 0), view.position + Vector3(1, 0, 1)]
			view.walk(steps)
			view.flinch(0.1)
			for i in 90:
				await process_frame
		scene.queue_free()
		await process_frame
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.get_child_count() > 0, "main menu builds")
	menu._open_guide()
	await process_frame
	var tabs: TabContainer = menu.guide.find_children("*", "TabContainer", true, false)[0]
	_check(menu.guide.visible and tabs.get_tab_count() == Jobs.all_jobs().size() and tabs.get_tab_count() > 6, "unit guide opens from the menu with a tab per job (imported classes too)")

	# Key bindings: Move defaults to Space, and rebinding to a used key swaps.
	var kb: Node = root.get_node("Keybinds")
	kb.reset_defaults()
	_check(kb.keys("move")[0] == KEY_SPACE, "Move is bound to Space by default")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_check(space.is_action_pressed("tm_move"), "Space triggers the Move action")
	kb.rebind("move", KEY_W)
	_check(kb.keys("move")[0] == KEY_W and kb.keys("cam_forward")[0] == KEY_SPACE, "rebinding to a used key swaps the two")
	kb.reset_defaults()
	_check(kb.keys("move")[0] == KEY_SPACE and kb.keys("cam_forward")[0] == KEY_W, "reset restores defaults")
	menu._open_options()
	await process_frame
	_check(menu.options.visible, "options menu opens from the main menu")
	menu._open_how_to()
	await process_frame
	_check(menu.how_to.visible and menu.how_to._pages.size() >= 6, "How to Play opens with its pages")
	var audio: Node = root.get_node("Audio")
	for sound in ["hit_metal", "swing", "magic", "heal", "ready", "turn_lost", "click", "step", "victory", "defeat", "charge"]:
		_check(audio.has_sound(sound), "sound '%s' is loaded" % sound)
	# load(), not preload(): fx.gd uses autoloads, which exist only at runtime.
	var fx_script: GDScript = load("res://scripts/battle/fx.gd")
	for id in preload("res://scripts/core/jobs.gd").ABILITIES:
		_check(fx_script.SOUNDS.has(id), "ability '%s' has sounds" % id)
	var settings: Node = root.get_node("Settings")
	var was: bool = settings.colorblind
	settings.set_value("colorblind", true)
	_check(settings.team_colors()[1] == settings.COLORBLIND_COLORS[1], "colorblind setting switches team colors")
	settings.set_value("colorblind", was)
	menu._open_setup("ai")
	await process_frame
	menu.setup._select_map("fortress")
	menu.setup._randomize(1)
	menu.setup._on_start()
	var config: Node = root.get_node("GameConfig")
	_check(config.map_id == "fortress" and config.rosters[1].size() == 4, "battle setup writes map and rosters to GameConfig")
	config.map_id = MapData.DEFAULT_MAP
	config.rosters = [["knight", "archer", "black_mage", "white_mage"], ["knight", "archer", "black_mage", "white_mage"]]
	menu.queue_free()
