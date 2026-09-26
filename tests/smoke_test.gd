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
	# Awaited: _test_rules waits on frames of its own, and without the await its
	# tail ran interleaved with the tests below, stepping on shared settings.
	await _test_rules()
	_test_ai_battle()
	_test_maps()
	var replay_log := _test_replay_determinism()
	_test_tuning()
	_test_astra_import()
	await _test_scenes()
	await _test_dev_tools()
	await _test_cpu_vs_cpu()
	await _test_log_window()
	await _test_turn_order_groups()
	await _test_stat_changes()
	await _test_replay_scene(replay_log)
	print("SMOKE TEST %s (%d failure(s))" % ["PASSED" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


## A battle for the rules tests: evasion and criticals are switched off so
## the numbers are exact (they have their own test).
func _new_state() -> GameState:
	var state := GameState.new()
	state.setup(MapData.highlands(), {"evade_multiplier": 0.0, "crit_chance_multiplier": 0.0})
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
	_check(u != null and u.job == "archer", "the fastest unit (the Archer, Speed %d) is ready first" % Jobs.job("archer").speed)
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
	var archer = null
	for unit in s2.units:
		if unit.team == 0 and unit.job == "archer":
			archer = unit
	_force_ready(s2, archer)
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
	_test_evade_and_crit()
	_test_ability_kinds()
	_test_target_shapes()
	_test_roles_and_icons()
	_test_victory_conditions()
	_test_ground_and_capture()
	_test_saved_teams()
	_test_sprint_engage_hustle()
	_test_log_entries()
	await _test_ability_classes()
	_test_planning_stage()
	await _test_menus_fit()
	await _test_walk_into_range()
	await _test_layout_editing()
	await _test_online_housekeeping()
	_test_new_statuses()
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
	# Statuses last turns of the unit they are on, not seconds.
	# Fire burns: HP drops at the start of each of the target's turns.
	var s := _new_state()
	var mage = s.units[2]
	var foe = s.units[4]
	_stage(s, mage, foe, Vector2(10.25, 10.25), Vector2(10.25, 14.25))
	s.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": foe.pos, "follow": foe.id})
	s.apply({"type": "advance", "ticks": 10})  # 1 s cast
	_check(foe.has_status("burn"), "Fire leaves Burn")
	var burn_turns: int = foe.statuses[0].turns
	var hp_after_hit: int = foe.hp
	s.apply({"type": "advance", "ticks": maxi(1, s.ticks_to_ready(foe) - 2)})
	_check(foe.hp == hp_after_hit and not foe.ready, "Burn waits for the unit's turn (no damage between turns)")
	var turn_damage := maxi(1, roundi(foe.max_hp() * 0.1))
	_wait_for_turn(s, foe)
	_check(foe.hp == hp_after_hit - turn_damage and foe.statuses[0].turns == burn_turns - 1,
		"Burn takes 10%% of max HP on the unit's turn and counts down (HP %d)" % foe.hp)
	for i in burn_turns - 1:
		_wait_for_turn(s, foe)
	_check(not foe.has_status("burn"), "Burn wears off after its turns (%d)" % burn_turns)

	# Regen heals on the unit's turn, up to full.
	var sr := _new_state()
	var hurt = sr.units[1]
	hurt.hp = 10
	sr._add_status(hurt, "regen", 2)
	_wait_for_turn(sr, hurt)
	_check(hurt.hp == 10 + maxi(1, roundi(hurt.max_hp() * 0.1)), "Regen heals on the unit's turn")

	# Slow halves Turn Gauge filling. Stun is not a lockout any more: it takes the
	# turn a unit is caught in, and on its own it leaves orders alone.
	var s2 := _new_state()
	var u = s2.units[0]
	u.tg = 0
	var normal: int = s2.ticks_to_ready(u)
	s2._add_status(u, "slow", 2)
	_check(s2.ticks_to_ready(u) > normal * 1.8, "Slow roughly halves Turn Gauge speed")
	u.statuses.clear()
	var tg_before: int = u.tg
	s2._add_status(u, "stun", 1)
	s2.apply({"type": "advance", "ticks": 5})
	_check(u.tg > tg_before, "a stunned unit's Turn Gauge keeps filling")
	u.statuses.clear()
	_force_ready(s2, u)
	s2._add_status(u, "stun", 2)
	_check(s2.validate({"type": "end_turn", "unit": u.id, "serial": u.serial}) == "",
		"Stun by itself no longer takes a unit's orders away")

	# Caught in its own turn: the turn goes, and the gauge is left most of the way
	# to the next one instead of starting over.
	var s4 := _new_state()
	var caught = s4.units[3]
	_force_ready(s4, caught)
	var kept := GameState.TG_MAX * roundi(s4.tune("stun_tg_percent")) / 100
	var r4 := {"logs": [], "events": [], "turn_ended": []}
	s4._add_status(caught, "stun", 1)
	s4._stun_interrupt(caught, r4)
	_check(not caught.ready and caught.tg == kept and r4.turn_ended.has(caught.id),
		"a Stun in a unit's own turn takes the turn and leaves the gauge at %d%%" % roundi(s4.tune("stun_tg_percent")))

	# Landing on a unit whose gauge is already fuller never drags it back.
	var waiting = s4.units[2]
	waiting.ready = false
	waiting.tg = GameState.TG_MAX - 1
	var fuller: int = waiting.tg
	s4._stun_interrupt(waiting, r4)
	_check(waiting.tg == fuller, "a Stun never sets a fuller gauge back")

	# Left alone, a unit mends itself at the start of each of its turns. Its own
	# state, so burning ground can't muddy the count.
	var s5 := GameState.new()
	s5.setup(MapData.highlands(), {"evade_multiplier": 0.0, "crit_chance_multiplier": 0.0, "hazard_percent": 0.0})
	var calm = s5.units[0]
	calm.hp = calm.max_hp() / 2
	var step := maxi(1, roundi(calm.max_hp() * s5.tune("regen_percent") * 0.01))
	for i in maxi(1, roundi(s5.tune("regen_after_turns"))):
		_wait_for_turn(s5, calm)
	var mended_from: int = calm.hp
	_wait_for_turn(s5, calm)
	_check(calm.hp == mended_from + step, "a unit left unhurt mends %d at the start of its turn" % step)

	# Being hurt puts the count back to nothing, so the mending stops.
	var hurt_from: int = calm.hp
	s5._hurt(calm, 1)
	_check(calm.unharmed_turns == 0, "taking damage forgets how long it had been left alone")
	_wait_for_turn(s5, calm)
	_check(calm.hp == hurt_from - 1, "damage stops the mending until it has been left alone again")

	# Re-applying a status keeps the longer of the two.
	var again := _new_state()
	var victim2 = again.units[1]
	again._add_status(victim2, "burn", 3)
	again._add_status(victim2, "burn", 1)
	_check(victim2.statuses[0].turns == 3, "a weaker re-application doesn't shorten a status")
	again._add_status(victim2, "burn", 5)
	_check(victim2.statuses.size() == 1 and victim2.statuses[0].turns == 5, "a longer re-application extends it")
	victim2.hp = 1
	again._knock_out(victim2, "x", {"logs": [], "knocked_out": [], "gone": [], "events": []})
	_check(victim2.statuses.is_empty(), "a knocked-out unit loses its statuses")

	# Shield Bash stuns.
	var s3 := _new_state()
	var knight = s3.units[0]
	foe = s3.units[4]
	_stage(s3, knight, foe, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	s3.apply({"type": "ability", "unit": knight.id, "serial": knight.serial, "slot": 1, "target": foe.pos})
	_check(foe.has_status("stun") and foe.statuses[0].turns == 1, "Shield Bash stuns for a turn")


## Runs time on until this unit's next turn comes (its statuses act then).
func _wait_for_turn(state: GameState, u) -> void:
	if u.ready:
		state.apply({"type": "end_turn", "unit": u.id, "serial": u.serial})
	var serial: int = u.serial
	for i in 3000:
		if u.serial > serial or not u.is_alive():
			return
		state.apply({"type": "advance", "ticks": 1})
	_check(false, "the unit's turn never came")


## A-Eva / M-Eva and Crit: rolled only while applying a command, from the
## battle's own seed, so both players online and a replay see the same rolls.
func _test_evade_and_crit() -> void:
	var state := GameState.new()
	state.setup(MapData.highlands(), {}, 12345)
	var hitter = state.units[4]
	var victim = state.units[1]
	_stage(state, hitter, victim, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	victim.hp = 9999
	var ab: Dictionary = hitter.ability(0)
	_check(state.evade_chance(victim, ab) == victim.stat("aeva" if ab.scale == "att" else "meva"),
		"the evade chance is the target's A-Eva / M-Eva")
	_check(state.crit_chance(hitter) == hitter.stat("crit"), "the crit chance is the user's Crit")
	_check(state.evade_chance(victim, hitter.ability(2)) == 0, "friendly abilities are never evaded")

	# Roll many times: some hits land, some are evaded, some are critical.
	var misses := 0
	var crits := 0
	var normal := 0
	var normal_damage: int = state.preview(hitter, 0, hitter.pos, victim.pos)[0].amount
	for i in 400:
		_force_ready(state, hitter)
		var before: int = victim.hp
		state.apply({"type": "ability", "unit": hitter.id, "serial": hitter.serial, "slot": 0, "target": victim.pos})
		var dealt: int = before - victim.hp
		if dealt == 0:
			misses += 1
		elif dealt > normal_damage:
			crits += 1
		else:
			normal += 1
	_check(misses > 0 and crits > 0 and normal > misses + crits,
		"over 400 hits: %d evaded, %d critical, %d normal" % [misses, crits, normal])

	# The same seed and the same commands roll the same way.
	var a := GameState.new()
	var b := GameState.new()
	var log: Array = []
	for state2 in [a, b]:
		state2.setup(MapData.highlands(), {}, 777)
	var ai := AIPlayer.new()
	while a.winner == -1 and a.tick < 6000:
		var ready := a.orderable_units()
		var cmd: Dictionary = {"type": "advance", "ticks": 1} if ready.is_empty() else ai.next_command(a, ready[0])
		log.append(cmd)
		a.apply(cmd)
	for cmd in log:
		b.apply(cmd)
	var same := a.tick == b.tick and a.winner == b.winner
	for i in a.units.size():
		same = same and a.units[i].hp == b.units[i].hp
	_check(same, "a battle with evasion and criticals replays exactly from its seed")
	var other := GameState.new()
	other.setup(MapData.highlands(), {}, 4242)
	for cmd in log:
		other.apply(cmd)
	var hp_a := []
	var hp_other := []
	for i in a.units.size():
		hp_a.append(a.units[i].hp)
		hp_other.append(other.units[i].hp)
	_check(hp_a != hp_other, "a different seed rolls differently")


## Ability types: passive and aura are always on, a toggle switches once a
## turn, and a channeled ability repeats and locks the unit.
func _test_ability_kinds() -> void:
	var state := _new_state()
	var u = state.units[0]
	var ab := u.ability(2).duplicate(true)  # Guard: a support ability with buffs

	# Passive: always on, can't be used, and its buffs count all the time.
	Jobs.custom_abilities["test_passive"] = ab.duplicate(true)
	Jobs.custom_abilities.test_passive.kind = "passive"
	Jobs.custom_abilities.test_passive.buffs = [{"stat": "power", "amount": 7, "turns": 2}]
	Jobs.custom_jobs["test_class"] = Jobs.base_job("knight").duplicate(true)
	Jobs.custom_jobs.test_class.name = "Test Class"
	Jobs.custom_jobs.test_class.abilities = ["attack", "test_passive", "test_toggle", "test_channel"]
	Jobs.custom_abilities["test_toggle"] = ab.duplicate(true)
	Jobs.custom_abilities.test_toggle.kind = "toggle"
	Jobs.custom_abilities.test_toggle.buffs = [{"stat": "attdef", "amount": 5, "turns": 2}]
	Jobs.custom_abilities["test_channel"] = u.ability(0).duplicate(true)
	Jobs.custom_abilities.test_channel.kind = "channeled"
	Jobs.custom_abilities.test_channel.channel = 2
	Jobs.custom_abilities.test_channel.max_range = 8.0
	var tester := GameState.new()
	tester.setup(MapData.build(MapData.DEFAULT_MAP, ["test_class", "knight", "archer", "white_mage"],
		["knight", "archer", "black_mage", "white_mage"]), {"evade_multiplier": 0.0, "crit_chance_multiplier": 0.0})
	var t = tester.units[0]
	_force_ready(tester, t)
	_check(t.stat("power") == Jobs.base_job("knight").power + 7, "a passive ability's buffs are always on")
	_check(tester.ability_blocked_reason(t, 1) != "", "a passive ability can't be used")
	_check(t.is_on(1) and not t.is_on(2), "is_on: passive yes, toggle not yet")

	# Toggle: switches on, applies while on, and only once a turn.
	var defense: int = t.stat("attdef")
	tester.apply({"type": "ability", "unit": t.id, "serial": t.serial, "slot": 2, "target": t.pos})
	_check(t.toggled.get(2, false) and t.stat("attdef") == defense + 5, "a toggle switches on and applies at once")
	_check(not t.acted, "switching a toggle doesn't use up the turn")
	_check(tester.validate({"type": "ability", "unit": t.id, "serial": t.serial, "slot": 2, "target": t.pos}) != "",
		"a toggle can only be switched once a turn")

	# Channeled: repeats on the next turns and the unit can't act meanwhile.
	var foe = tester.units[4]
	foe.pos = t.pos + Vector2(4, 0)
	foe.hp = 999
	t.ult = GameState.ULT_MAX  # slot 4 is the ultimate
	tester.apply({"type": "ability", "unit": t.id, "serial": t.serial, "slot": 3, "target": foe.pos, "follow": foe.id})
	_check(t.is_channeling() and t.channeling.turns == 2 and not t.ready,
		"a channeled ability starts channeling and ends the turn")
	var hp_after_first: int = foe.hp
	var serial: int = t.serial
	for i in 3000:
		if t.serial > serial:
			break
		tester.apply({"type": "advance", "ticks": 1})
	_check(foe.hp < hp_after_first, "a channeled ability goes off again on the next turn")
	_check(not t.ready, "the unit's turn is spent channeling")
	Jobs.custom_jobs.erase("test_class")
	for id in ["test_passive", "test_toggle", "test_channel"]:
		Jobs.custom_abilities.erase(id)

	# Auras reach everyone nearby when their turn comes.
	var aura := _new_state()
	var giver = aura.units[0]
	var friend = aura.units[1]
	var aura_ability := {"name": "Test Aura", "desc": "", "effect": "support", "scale": "att", "power": 0,
		"min_range": 0.0, "max_range": 0.0, "aoe": 5.0, "cooldown": 0, "cast": 0.0, "target": "ally",
		"kind": "aura", "buffs": [{"stat": "attdef", "amount": 4, "turns": 2}]}
	Jobs.custom_abilities["test_aura"] = aura_ability
	var giver_job := Jobs.base_job(giver.job).duplicate(true)
	giver_job.abilities = giver_job.abilities.duplicate()
	giver_job.abilities[2] = "test_aura"
	Jobs.custom_jobs[giver.job] = giver_job
	Jobs.set_overrides({})
	friend.pos = giver.pos + Vector2(2, 0)
	var before: int = friend.stat("attdef")
	_force_ready(aura, friend)
	_check(friend.stat("attdef") == before + 4, "an aura reaches an ally when its turn comes")
	Jobs.custom_jobs.erase(giver.job)
	Jobs.custom_abilities.erase("test_aura")
	Jobs.set_overrides({})


## Target shapes: a line skewers, a cone sweeps, global reaches everyone, and
## a vector carries the user to the far end.
func _test_target_shapes() -> void:
	var state := _new_state()
	var caster = state.units[0]
	caster.pos = Vector2(6.25, 12.25)
	var line_ab := {"name": "Line", "desc": "", "effect": "damage", "scale": "att", "power": 20,
		"min_range": 0.0, "max_range": 12.0, "aoe": 0.8, "cooldown": 0, "cast": 0.0, "target": "enemy", "shape": "line"}
	var foes := []
	for i in 3:
		var foe = state.units[4 + i]
		foe.pos = Vector2(6.25 + 3.0 * (i + 1), 12.25)
		foes.append(foe)
	state.units[7].pos = Vector2(6.25, 20.25)  # off the line
	var hits := []
	for t in state.units:
		if state.in_shape(line_ab, caster.pos, Vector2(16.25, 12.25), t.pos):
			hits.append(t.id)
	_check(hits.has(foes[0].id) and hits.has(foes[1].id) and hits.has(foes[2].id) and not hits.has(state.units[7].id),
		"a line hits everyone along it and nobody beside it")

	var cone_ab := line_ab.duplicate()
	cone_ab.shape = "cone"
	cone_ab.max_range = 6.0
	cone_ab.angle = 60.0
	_check(state.in_shape(cone_ab, caster.pos, Vector2(12.25, 12.25), Vector2(9.25, 12.25))
		and not state.in_shape(cone_ab, caster.pos, Vector2(12.25, 12.25), Vector2(6.25, 18.25)),
		"a cone hits in front of the user, not behind")
	# Aiming at bare ground: an ability may be pointed at an empty spot, which is
	# how you catch a unit where it is about to walk rather than where it stands.
	var open_ground := _new_state()
	var thrower = open_ground.units[0]
	_force_ready(open_ground, thrower)
	var empty := open_ground.snap(thrower.pos + Vector2(1, 0))
	var nobody := true
	for t in open_ground.units:
		if t.is_alive() and t.pos == empty:
			nobody = false
	_check(nobody, "the spot chosen for the test really is empty")
	_check(open_ground.validate({"type": "ability", "unit": thrower.id, "serial": thrower.serial,
		"slot": 0, "target": empty, "follow": -1}) == "", "an ability can be aimed at bare ground")
	_check(open_ground.preview(thrower, 0, thrower.pos, empty).is_empty(),
		"and it catches nobody when nobody is standing there")

	var global_ab := line_ab.duplicate()
	global_ab.shape = "global"
	_check(state.in_shape(global_ab, caster.pos, caster.pos, Vector2(23.0, 23.0)), "a global ability reaches the whole field")

	# A vector ability moves the caster to the far end.
	var dash := line_ab.duplicate()
	dash.shape = "vector"
	dash.max_range = 6.0
	Jobs.custom_abilities["test_dash"] = dash
	var dash_job := Jobs.base_job("knight").duplicate(true)
	dash_job.abilities = ["test_dash", "shield_bash", "guard", "holy_blade"]
	Jobs.custom_jobs["test_dasher"] = dash_job
	var dash_state := GameState.new()
	dash_state.setup(MapData.build(MapData.DEFAULT_MAP, ["test_dasher", "knight", "archer", "white_mage"],
		["knight", "archer", "black_mage", "white_mage"]), {"evade_multiplier": 0.0})
	var dasher = dash_state.units[0]
	_force_ready(dash_state, dasher)
	var target := dash_state.snap(dasher.pos + Vector2(4, 0))
	dash_state.apply({"type": "ability", "unit": dasher.id, "serial": dasher.serial, "slot": 0, "target": target})
	_check(dasher.pos == target, "a vector ability carries the user to the far end (%s vs %s)" % [dasher.pos, target])
	Jobs.custom_jobs.erase("test_dasher")
	Jobs.custom_abilities.erase("test_dash")


## Roles come from the class when it says so, and are worked out when it doesn't.
func _test_roles_and_icons() -> void:
	_check(Jobs.roles_of("knight") == ["tank", "damage"] and Jobs.role_name("knight") == "Tank / Damage",
		"a class's own role is used (%s)" % [Jobs.roles_of("knight")])
	_check(Jobs.roles_of("white_mage") == ["support"], "the White Mage is Support")
	var tagged := 0
	var guessed := 0
	for id in Jobs.custom_jobs:
		if Jobs.custom_jobs[id].has("role"):
			tagged += 1
		else:
			guessed += 1
		_check(not Jobs.roles_of(id).is_empty(), "%s has a role" % id)
	_check(tagged >= 100, "the imported classes carry their own roles (%d tagged, %d guessed)" % [tagged, guessed])
	var healer_roles := Jobs.roles_of("frost_mender")
	_check(healer_roles.has("support"), "a cleric class is Support (%s)" % [healer_roles])

	# Icons: every class and ability resolves to a file, with a fallback.
	_check(Jobs.ability_icon_path("attack").ends_with("attack.svg"), "an ability uses its own icon")
	Jobs.custom_abilities["test_no_icon"] = {"name": "No Icon", "desc": "", "effect": "heal", "scale": "mag",
		"power": 5, "min_range": 0.0, "max_range": 3.0, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "ally"}
	_check(Jobs.ability_icon_path("test_no_icon").ends_with("any_heal.svg"), "an ability without an icon falls back to its effect")
	Jobs.custom_abilities.erase("test_no_icon")

	# Classes that arrive over the network are checked before they are used.
	var junk := {"jobs": {"bad": {"name": "Bad"}}, "abilities": {}}
	_check(Jobs.clean_classes(junk).jobs.is_empty(), "a class missing its stats is rejected")
	_check(Jobs.clean_classes("nonsense").jobs.is_empty(), "nonsense instead of classes is rejected")
	var good := Jobs.classes_for([["time_mage"], []])
	var cleaned := Jobs.clean_classes(good)
	_check(cleaned.jobs.has("time_mage") and cleaned.abilities.size() == 4, "a whole class passes the check")


## A battle can have a time limit (the healthier side wins, level shares
## draw), and a player can give up.
func _test_victory_conditions() -> void:
	var state := GameState.new()
	state.setup(MapData.highlands(), {"battle_seconds": 5.0})
	state.units[4].hp = 10  # Red is hurt, so Blue should win on health
	while state.winner == -1 and state.tick < 200:
		state.apply({"type": "advance", "ticks": 1})
	_check(state.winner == 0 and state.tick == 50, "the time limit ends the battle and the healthier side wins (winner %d at %d)" % [state.winner, state.tick])
	_check(state.health_share(0) > state.health_share(1), "health share tells the sides apart")

	var level := GameState.new()
	level.setup(MapData.highlands(), {"battle_seconds": 3.0})
	while level.winner == -1 and level.tick < 200:
		level.apply({"type": "advance", "ticks": 1})
	_check(level.winner == GameState.DRAW, "an even battle at the time limit is a draw")

	var endless := _new_state()
	endless.apply({"type": "advance", "ticks": 50})
	_check(endless.winner == -1, "without a limit a battle keeps going")

	var give_up := _new_state()
	_check(give_up.validate({"type": "surrender", "team": 3}) != "", "a surrender needs a real team")
	give_up.apply({"type": "surrender", "team": 1})
	_check(give_up.winner == 0, "surrendering hands the battle to the other side")

	# Both sides wiped out at once is a draw, not a win.
	var both := _new_state()
	for u in both.units:
		u.hp = 0
		u.ko_ticks = 0
	both._check_winner()
	_check(both.winner == GameState.DRAW, "nobody left on either side is a draw")


## Shield soaks damage, Root stops walking, Silence stops abilities, and a
## taunted unit has to attack whoever taunted it.
func _test_new_statuses() -> void:
	var state := _new_state()
	var hitter = state.units[4]
	var victim = state.units[0]
	_stage(state, hitter, victim, Vector2(10.25, 10.25), Vector2(11.25, 10.25))

	# Shield: damage comes off it first, and it breaks when used up.
	state._add_status(victim, "shield", 3, {"amount": 12})
	_check(victim.shield_left() == 12, "a Shield holds what it was given")
	var hp_before: int = victim.hp
	var expected: int = state.preview(hitter, 0, hitter.pos, victim.pos)[0].amount
	state.apply({"type": "ability", "unit": hitter.id, "serial": hitter.serial, "slot": 0, "target": victim.pos})
	if expected <= 12:
		_check(victim.hp == hp_before and victim.shield_left() == 12 - expected, "a Shield soaks the whole hit")
	else:
		_check(victim.hp == hp_before - (expected - 12) and not victim.has_status("shield"), "a Shield soaks what it can, then breaks")

	# Root: can't walk, can still act. Silence: the other way round.
	var rooted := _new_state()
	var u = rooted.units[0]
	_force_ready(rooted, u)
	var spot := rooted.snap(u.pos + Vector2(1, 0))
	rooted._add_status(u, "root", 2)
	_check(rooted.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": spot}) != "", "a rooted unit can't walk")
	_check(rooted.ability_blocked_reason(u, 0) == "", "a rooted unit can still use abilities")
	u.statuses.clear()
	rooted._add_status(u, "silence", 2)
	_check(rooted.ability_blocked_reason(u, 0) != "", "a silenced unit can't use abilities")
	_check(rooted.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": spot}) == "", "a silenced unit can still walk")

	# Taunt: it must attack the one that taunted it while that one is in reach.
	var taunt := _new_state()
	var angry = taunt.units[0]
	var taunter = taunt.units[4]
	var other = taunt.units[5]
	_stage(taunt, angry, taunter, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	other.pos = Vector2(11.25, 11.25)
	taunt._add_status(angry, "taunt", 2, {"by": taunter.id})
	_check(taunt.validate({"type": "ability", "unit": angry.id, "serial": angry.serial, "slot": 0,
		"target": other.pos, "follow": other.id}) != "", "a taunted unit can't attack someone else")
	_check(taunt.validate({"type": "ability", "unit": angry.id, "serial": angry.serial, "slot": 0,
		"target": taunter.pos, "follow": taunter.id}) == "", "a taunted unit can attack the one that taunted it")
	taunter.pos = Vector2(20.25, 20.25)  # out of reach: it may hit anyone again
	_check(taunt.validate({"type": "ability", "unit": angry.id, "serial": angry.serial, "slot": 0,
		"target": other.pos, "follow": other.id}) == "", "out of reach, a taunt no longer holds")

	# Crippled and Stride scale how far a unit walks.
	var legs := _new_state()
	var walker = legs.units[0]
	var plain: float = legs.move_of(walker)
	legs._add_status(walker, "crippled", 2)
	_check(is_equal_approx(legs.move_of(walker), plain * 0.5), "Crippled halves how far a unit walks")
	walker.statuses.clear()
	legs._add_status(walker, "stride", 2)
	_check(is_equal_approx(legs.move_of(walker), plain * 1.5), "Stride walks half again as far")

	# Blind makes its own attacks easier to evade; Shred cuts what a unit shrugs off.
	var eyes := _new_state()
	var shooter = eyes.units[4]
	var mark = eyes.units[0]
	var ab0: Dictionary = shooter.ability(0)
	var clear_shot: int = eyes.evade_chance(mark, ab0, shooter)
	eyes._add_status(shooter, "blind", 2)
	_check(eyes.evade_chance(mark, ab0, shooter) == mini(clear_shot + 25, 95), "Blind adds 25% to the chance its attack is evaded")
	_check(eyes.evade_chance(mark, ab0) == clear_shot, "and it is the attacker's Blind, not the target's")
	var armour: int = mark.stat("attdef")
	eyes._add_status(mark, "shred", 2)
	_check(mark.stat("attdef") == roundi(armour * 0.6), "Shred cuts AttDef to 60%")
	mark.statuses.clear()
	eyes._add_status(mark, "freeze", 2)
	_check(mark.stat("attdef") == roundi(armour * 3.0) and eyes.validate({"type": "move", "unit": mark.id,
		"serial": mark.serial, "to": eyes.snap(mark.pos + Vector2(1, 0))}) != "",
		"Freeze triples AttDef and pins the unit in place")

	# Invulnerable turns damage away entirely, and it counts as avoided.
	var safe := _new_state()
	var bully = safe.units[4]
	var ward = safe.units[0]
	_stage(safe, bully, ward, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	safe._add_status(ward, "invuln", 2)
	var full_hp: int = ward.hp
	var hit := safe.apply({"type": "ability", "unit": bully.id, "serial": bully.serial, "slot": 0, "target": ward.pos})
	_check(ward.hp == full_hp, "an Invulnerable unit takes nothing")
	_check(hit.resolved[0].avoided > 0, "and what it turned away is counted as avoided")

	# Sleep loses its turns, but any damage wakes it at once.
	var nap := _new_state()
	var sleeper = nap.units[0]
	nap._add_status(sleeper, "sleep", 3)
	_check(nap.validate({"type": "end_turn", "unit": sleeper.id, "serial": sleeper.serial}) != "", "a sleeping unit takes no orders")
	nap._hurt(sleeper, 1)
	_check(not sleeper.has_status("sleep"), "any damage wakes a sleeping unit")

	# Immunity clears what is already on a unit and turns new harm away.
	var ward2 := _new_state()
	var cleansed = ward2.units[0]
	ward2._add_status(cleansed, "burn", 3)
	ward2._add_status(cleansed, "slow", 3)
	ward2._add_status(cleansed, "immunity", 2)
	_check(not cleansed.has_status("burn") and not cleansed.has_status("slow"), "Immunity clears the harmful statuses on a unit")
	ward2._add_status(cleansed, "bleed", 3)
	_check(not cleansed.has_status("bleed"), "and turns new harmful ones away while it lasts")
	ward2._add_status(cleansed, "regen", 3)
	_check(cleansed.has_status("regen"), "a helpful status still lands through Immunity")

	# Doom: when the count runs out the unit falls, whatever health it has.
	var fate := _new_state()
	var marked = fate.units[0]
	marked.hp = marked.max_hp()
	fate._add_status(marked, "doom", 1)
	_wait_for_turn(fate, marked)
	_check(not marked.is_alive(), "Doom takes the unit when its count runs out, at full health")

	# Knockdown: it may walk or act on its turn, but not both.
	var down := _new_state()
	var floored = down.units[0]
	_force_ready(down, floored)
	down._add_status(floored, "knockdown", 2)
	var step := down.snap(floored.pos + Vector2(1, 0))
	_check(down.validate({"type": "move", "unit": floored.id, "serial": floored.serial, "to": step}) == "",
		"a knocked-down unit may still walk")
	down.apply({"type": "move", "unit": floored.id, "serial": floored.serial, "to": step})
	_check(down.validate({"type": "ability", "unit": floored.id, "serial": floored.serial, "slot": 0,
		"target": floored.pos}) != "", "but not act as well once it has walked")

	# Fly: melee can't reach it, and it crosses any height.
	var air := _new_state()
	var swinger = air.units[0]
	var flier = air.units[4]
	_stage(air, swinger, flier, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	_check(air.preview(swinger, 0, swinger.pos, flier.pos).size() == 1, "a melee attack reaches a unit on the ground")
	var grounded: int = air.reachable_nodes(flier).size()
	air._add_status(flier, "fly", 2)
	_check(air.preview(swinger, 0, swinger.pos, flier.pos).is_empty(), "melee can't reach a unit in the air")
	_check(air._jump_of(flier) > GameState.JUMP and air.reachable_nodes(flier).size() >= grounded,
		"a flier crosses any height, so it is never held back by a climb")

	# Relentless: straight back round again, then it wears off.
	var again2 := _new_state()
	var eager = again2.units[0]
	_force_ready(again2, eager)
	again2._add_status(eager, "relentless", 2)
	again2.apply({"type": "end_turn", "unit": eager.id, "serial": eager.serial})
	_check(eager.tg >= GameState.TG_MAX - 1 and not eager.has_status("relentless"),
		"Relentless sends a unit straight back round, and is spent doing it")

	# Barrier soaks like a Shield, and the two stack.
	var wall := _new_state()
	var guarded = wall.units[0]
	wall._add_status(guarded, "shield", 3, {"amount": 5})
	wall._add_status(guarded, "barrier", 3, {"amount": 7})
	_check(guarded.shield_left() == 12, "a Barrier stacks with a Shield")


## The new ground: embers burn and springs heal whoever starts a turn on
## them, rocks hide what is behind them, and holding the middle can win.
func _test_ground_and_capture() -> void:
	var state := GameState.new()
	state.setup(MapData.build("ashfields"), {"evade_multiplier": 0.0, "crit_chance_multiplier": 0.0})
	var ember := Vector2.ZERO
	var spring := Vector2.ZERO
	var rock := Vector2.ZERO
	for y in state.tiles_y:
		for x in state.tiles_x:
			var p := Vector2(x + 0.5, y + 0.5) * GameState.TILE_SIZE
			if state.hazard_at(p) < 0:
				ember = p
			elif state.hazard_at(p) > 0:
				spring = p
			elif state.is_cover(p):
				rock = p
	_check(ember != Vector2.ZERO and spring != Vector2.ZERO and rock != Vector2.ZERO, "Ashfields has embers, a spring and rocks")
	_check(not state.node_walkable(state.node_of(rock)), "a rock can't be walked on")
	_check(not state.has_line_of_sight(rock - Vector2(3, 0), rock + Vector2(3, 0)), "a rock blocks sight through it")

	# Embers burn on the unit's own turn, not while it walks past.
	var burned = state.units[0]
	burned.pos = ember
	var before: int = burned.hp
	state.apply({"type": "advance", "ticks": 1})
	_check(burned.hp == before, "standing on embers costs nothing between turns")
	_force_ready(state, burned)
	_check(burned.hp < before, "embers burn when the unit's turn comes round (%d -> %d)" % [before, burned.hp])

	# A spring heals, up to full health.
	var healed = state.units[1]
	healed.pos = spring
	healed.hp = 10
	_force_ready(state, healed)
	_check(healed.hp > 10, "a spring heals when the unit's turn comes round")
	healed.hp = healed.max_hp()
	_force_ready(state, healed)
	_check(healed.hp == healed.max_hp(), "a spring can't heal past full health")

	# Holding the middle alone long enough wins.
	var hold := GameState.new()
	hold.setup(MapData.highlands(), {"capture_seconds": 3.0})
	var middle := hold.capture_point()
	for u in hold.units:
		u.pos = middle if u.team == 0 else middle + Vector2(30, 30)
	for i in 40:
		if hold.winner != -1:
			break
		hold.apply({"type": "advance", "ticks": 1})
	_check(hold.winner == 0, "holding the middle alone wins the battle")

	var fight := GameState.new()
	fight.setup(MapData.highlands(), {"capture_seconds": 3.0})
	for u in fight.units:
		u.pos = fight.capture_point() + Vector2(0.5 * u.team, 0)
	fight.apply({"type": "advance", "ticks": 40})
	_check(fight.capture_ticks[0] == 0 and fight.capture_ticks[1] == 0, "a contested middle counts for neither side")

	var off := _new_state()
	off.apply({"type": "advance", "ticks": 40})
	_check(off.capture_share(0) == 0.0, "with the rule off the middle is just ground")


## Teams saved in Battle Setup come back, including ones with an imported
## class (they are only known after the class files are read), and junk is
## dropped instead of being handed to a battle.
func _test_saved_teams() -> void:
	var config = root.get_node("GameConfig")
	var kept: Dictionary = config.teams.duplicate(true)
	config.teams.clear()
	var imported := ""
	for id in Jobs.all_jobs():
		if not Jobs.JOBS.has(id):
			imported = id
			break
	_check(imported != "", "there is an imported class to save a team of")
	var roster := [imported, "knight", "archer", "white_mage"]
	config.save_team("  Test team  ", roster)
	_check(config.teams.has("Test team"), "a saved team is kept under its trimmed name")
	config.save_team("Test team", ["knight", "knight", "knight", "knight"])
	_check(config.teams["Test team"].size() == 4 and config.teams["Test team"][0] == "knight", "saving again under the same name replaces it")
	config.save_team("Half team", ["knight", "archer"])
	_check(not config.teams.has("Half team"), "a team that isn't four classes isn't saved")
	config.save_team("", roster)
	_check(not config.teams.has(""), "a team needs a name")

	# Reading them back: the imported class must survive the round trip.
	config.save_team("Test team", roster)
	config.teams.clear()
	config._load_teams()
	_check(config.teams.get("Test team", []) == roster, "a saved team with an imported class is read back whole")

	config.delete_team("Test team")
	_check(not config.teams.has("Test team"), "a team can be deleted")
	config.teams = kept
	config._save_teams()


## Sprinting walks further but spends the turn's action; an enemy's
## engagement radius is free to walk into and costs movement to leave; and a
## turn that used no ability fills the gauge faster.
func _test_sprint_engage_hustle() -> void:
	var state := _new_state()
	var u = state.units[0]
	# Far from the enemies, so nothing is engaged.
	for e in state.units:
		if e.team != u.team:
			e.pos = Vector2(40, 40)
	_force_ready(state, u)
	var walk: float = state.move_of(u)
	var run: float = state.move_of(u, true)
	_check(run > walk, "a sprint goes further than a walk (%.1f m vs %.1f m)" % [run, walk])
	_check(state.reachable_nodes(u, true).size() > state.reachable_nodes(u).size(), "a sprint reaches more ground")

	# A spot only a sprint can get to: legal as a sprint, refused as a walk.
	var far := Vector2.ZERO
	for n in state.reachable_nodes(u, true):
		if not state.reachable_nodes(u).has(n):
			far = state.node_pos(n)
			break
	_check(far != Vector2.ZERO, "there is ground only a sprint can reach")
	_check(state.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": far}) != "", "a walk can't reach it")
	_check(state.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": far, "sprint": true}) == "", "a sprint can")
	_check(state.path_to(u, state.node_of(far), true).size() >= 2, "there is a path to a sprint's destination")
	_check(state.path_to(u, state.node_of(far)).is_empty(), "and none within a walk's budget")
	state.apply({"type": "move", "unit": u.id, "serial": u.serial, "to": far, "sprint": true})
	_check(u.moved and u.acted, "a sprint uses the move and the action")
	_check(state.validate({"type": "ability", "unit": u.id, "serial": u.serial, "slot": 0, "target": u.pos}) != "", "no ability after a sprint")

	# Engagement: standing next to an enemy costs movement to break away.
	var field := _new_state()
	var runner = field.units[0]
	var enemy = field.units[4]
	for other in field.units:
		if other != runner and other != enemy:
			other.pos = Vector2(40, 40)
	runner.pos = field.snap(Vector2(10.25, 10.25))
	enemy.pos = field.snap(runner.pos + Vector2(1.0, 0))
	_force_ready(field, runner)
	var away := field.node_of(runner.pos + Vector2(-field.move_of(runner) + 0.75, 0))
	var free_reach: int = field.reachable_nodes(runner).size()
	field.tuning["engage_cost"] = 0.0
	var loose_reach: int = field.reachable_nodes(runner).size()
	_check(loose_reach > free_reach, "breaking away costs movement (%d spots engaged, %d free)" % [free_reach, loose_reach])
	field.tuning["engage_cost"] = GameState.TUNING.engage_cost[0]
	_check(field.reachable_nodes(runner).has(field.node_of(enemy.pos + Vector2(0, 0.75))), "walking around an enemy stays free")

	# Held back its ability: the gauge fills faster until its next turn.
	var quick := _new_state()
	var waiter = quick.units[0]
	_force_ready(quick, waiter)
	quick.apply({"type": "end_turn", "unit": waiter.id, "serial": waiter.serial})
	_check(waiter.hustling, "a turn without an ability leaves the unit hustling")
	_check(quick.hustle_factor(waiter) > 1.0, "hustling fills the gauge faster")
	var acted := _new_state()
	var user = acted.units[0]
	var victim = acted.units[4]
	_stage(acted, user, victim, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	acted.apply({"type": "ability", "unit": user.id, "serial": user.serial, "slot": 0, "target": victim.pos})
	acted.apply({"type": "end_turn", "unit": user.id, "serial": user.serial})
	_check(not user.hustling, "a turn that used an ability doesn't")
	# It wears off when the turn comes round.
	_force_ready(quick, waiter)
	_check(not waiter.hustling, "the bonus ends when the next turn arrives")


## Every log line says what kind of thing happened and who it was about, so
## the combat log can color it and put that unit's icon beside it.
func _test_log_entries() -> void:
	var state := _new_state()
	var hitter = state.units[4]
	var victim = state.units[0]
	_stage(state, hitter, victim, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	var result := state.apply({"type": "ability", "unit": hitter.id, "serial": hitter.serial, "slot": 0, "target": victim.pos})
	_check(not result.logs.is_empty(), "using an ability writes to the log")
	var kinds := {}
	for line in result.logs:
		_check(line is Dictionary and line.has("text") and line.has("kind") and line.has("unit"),
			"a log line carries its text, kind and unit (%s)" % line)
		kinds[line.kind] = true
	_check(kinds.has("damage"), "an attack is logged as damage (%s)" % kinds.keys())

	# The pieces a line is drawn from: units to show as icons, and text in the
	# color of what it says.
	var attack := {}
	for line in result.logs:
		if line.kind == "damage" and line.has("parts"):
			attack = line
	_check(not attack.is_empty(), "the attack line is built from pieces")
	var units_named := 0
	var damage_pieces := 0
	var filler_pieces := 0
	for part in attack.get("parts", []):
		if part.has("unit"):
			units_named += 1
		elif part.get("kind", "") == "damage":
			damage_pieces += 1
		elif part.get("kind", "") == "filler":
			filler_pieces += 1
	_check(units_named >= 2, "both the attacker and its target are pieces of their own (%d)" % units_named)
	_check(damage_pieces >= 1, "the damage itself is a piece colored as damage")
	_check(filler_pieces >= 1, "the words joining them are plain text")
	# The written-out sentence still reads the same as before.
	_check(attack.text.contains("uses") and attack.text.contains(hitter.job_name()),
		"the line still spells itself out for anything reading text (%s)" % attack.text)

	# A healer's line is healing, and it knows which unit it was about.
	var heal := _new_state()
	var mage = heal.units[3]
	var hurt = heal.units[0]
	_stage(heal, mage, hurt, Vector2(10.25, 10.25), Vector2(11.25, 10.25))
	hurt.hp = 10
	var cure := heal.apply({"type": "ability", "unit": mage.id, "serial": mage.serial, "slot": 1, "target": hurt.pos})
	var healed_line := {}
	for line in cure.logs:
		if line.kind == "heal" or line.kind == "cast":
			healed_line = line
	_check(not healed_line.is_empty(), "a Cure is logged as healing or casting")
	_check(healed_line.get("unit", -1) == mage.id, "the line is about the unit that cast it")


## The planning stage: before the fighting, each side places its units in its
## own spawn area, and nothing else happens until it is over.
func _test_planning_stage() -> void:
	var state := GameState.new()
	state.setup(MapData.highlands(), {"planning_seconds": 10.0})
	_check(state.is_planning(), "a battle with planning time starts in the planning stage")
	var u = state.units[0]
	var enemy = state.units[4]
	var gauge_before: int = u.tg
	state.apply({"type": "advance", "ticks": 20})
	_check(state.tick == 0 and u.tg == gauge_before, "no gauge fills and no time passes while planning")

	var spot := state.snap(state.spawn_points[0] + Vector2(1.0, 1.0))
	_check(state.validate({"type": "place", "unit": u.id, "serial": u.serial, "to": spot}) == "", "a unit can be placed in its own spawn area")
	state.apply({"type": "place", "unit": u.id, "serial": u.serial, "to": spot})
	_check(u.pos == spot, "placing moves it there")
	var far := state.snap(state.spawn_points[1])
	_check(state.validate({"type": "place", "unit": u.id, "serial": u.serial, "to": far}) != "", "it can't be placed in the other side's area")
	_check(state.validate({"type": "place", "unit": enemy.id, "serial": enemy.serial, "to": spot}) != "", "and not on top of somebody else")
	_check(not state.placeable_nodes(u).is_empty(), "there are spots to place it on")
	_check(state.validate({"type": "move", "unit": u.id, "serial": u.serial, "to": spot}) != "", "nobody walks while planning")

	# Both sides ready: the fighting starts before the time is up.
	state.apply({"type": "ready", "team": 0})
	_check(state.is_planning(), "one side being ready isn't enough")
	state.apply({"type": "ready", "team": 1})
	_check(not state.is_planning(), "both sides ready starts the battle")
	state.apply({"type": "advance", "ticks": 5})
	_check(state.tick == 5, "time runs once the planning is over")
	_check(state.validate({"type": "place", "unit": u.id, "serial": u.serial, "to": spot}) != "", "and units can't be placed any more")

	# Or the time simply runs out.
	var waited := GameState.new()
	waited.setup(MapData.highlands(), {"planning_seconds": 1.0})
	waited.apply({"type": "advance", "ticks": 10})
	_check(not waited.is_planning(), "the planning stage ends when its time runs out")

	var straight := _new_state()
	_check(not straight.is_planning(), "without planning time a battle starts fighting")


## Nothing on the menu screens may run off the right-hand edge: the canvas is
## a fixed width, so a control past it is simply cut off (as Battle Setup's
## settings row was once it had four pickers on it).
func _test_menus_fit() -> void:
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var width: float = root.get_viewport().get_visible_rect().size.x
	for screen in ["setup", "guide", "options", "how_to", "dev_tools"]:
		match screen:
			"setup":
				menu._open_setup("ai")
			"guide":
				menu._open_guide()
			"options":
				menu._open_options()
			"how_to":
				menu._open_how_to()
			"dev_tools":
				menu._open_dev_tools()
		for i in 4:
			await process_frame
		var panel: Node = menu.get(screen)
		var widest := 0.0
		var culprit := ""
		for c in panel.find_children("*", "Control", true, false):
			if not c.visible or not c.is_visible_in_tree():
				continue
			var right: float = c.global_position.x + c.size.x
			if right > widest and (c is Button or c is OptionButton or c is LineEdit or c is SpinBox):
				widest = right
				culprit = "%s '%s'" % [c.get_class(), c.text if "text" in c else c.name]
		_check(widest <= width, "%s fits the screen (%s ends at %d of %d)" % [screen, culprit, roundi(widest), roundi(width)])
		if panel.has_method("close_setup"):
			panel.close_setup()
		else:
			panel.hide()
		await process_frame
	menu.free()


## Abilities are sorted into what they are for, which colors them on a unit's
## stats card and is spelled out by the legend under the list.
func _test_ability_classes() -> void:
	_check(Jobs.ability_class(Jobs.ability("attack")) == "physical", "a sword swing is a physical attack")
	_check(Jobs.ability_class(Jobs.ability("fire")) == "magical", "Fire is a magic attack")
	_check(Jobs.ability_class(Jobs.ability("cure")) == "heal", "Cure is healing")
	_check(Jobs.ability_class(Jobs.ability("raise")) == "heal", "so is Raise")
	_check(Jobs.ability_class(Jobs.ability("guard")) == "boost", "Guard is a buff")
	for id in Jobs.ABILITIES:
		var name: String = Jobs.ABILITY_CLASSES[Jobs.ability_class(Jobs.ability(id))].name
		if name == "":
			_check(false, "%s has no kind" % id)
	for id in Jobs.all_jobs():
		for slot in 4:
			var kind: String = Jobs.ability_class(Jobs.ability(Jobs.job(id).abilities[slot]))
			if not Jobs.ABILITY_CLASSES.has(kind):
				_check(false, "%s ability %d has an unknown kind %s" % [id, slot, kind])

	# On the card: every ability shows its icon, in the color of its kind.
	var hud = load("res://scripts/battle/hud.gd").new()
	var state := _new_state()
	hud.game_state = state
	root.add_child(hud)
	hud.build(true)
	await process_frame
	var u = state.units[0]
	hud.show_inspect(u, false, "Blue Knight", Color.WHITE, 10.0)
	await process_frame
	var rows: Array = hud._inspect.left.abilities.get_children()
	_check(rows.size() == 4, "the card lists all four abilities")
	var with_icons := 0
	for i in rows.size():
		var icon := rows[i].get_node("Icon") as TextureRect
		var label := rows[i].get_node("Name") as Label
		if icon.texture != null:
			with_icons += 1
		var wanted: Color = Jobs.ABILITY_CLASSES[Jobs.ability_class(u.ability(i))].color
		var shown: Color = label.get_theme_color("font_color")
		_check(shown.is_equal_approx(wanted) or shown.is_equal_approx(wanted.darkened(0.35)),
			"ability %d is colored for what it does" % (i + 1))
	_check(with_icons == 4, "each ability on the card has its icon (%d of 4)" % with_icons)
	hud.free()


## Ordering an ability on something out of reach: the unit walks into range
## and uses it where the target was standing. If the target has moved on by
## the time it gets there, the blow lands on empty ground and does nothing.
func _test_walk_into_range() -> void:
	root.get_node("GameConfig").mode = "hotseat"
	var scene: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var state = scene.state
	# A real battle rolls evasion and crits from a random seed; this is about
	# walking into range, so those are turned off for it.
	state.tuning["evade_multiplier"] = 0.0
	state.tuning["crit_chance_multiplier"] = 0.0
	var hitter = state.units[0]
	var victim = state.units[4]
	for other in state.units:
		if other != hitter and other != victim:
			other.pos = Vector2(40, 40)
	hitter.pos = state.snap(Vector2(10.25, 10.25))
	# Out of reach of a melee blow, but within a walk of it.
	victim.pos = state.snap(hitter.pos + Vector2(3.5, 0))
	hitter.tg = GameState.TG_MAX - 1
	for i in 6:
		state.apply({"type": "advance", "ticks": 1})
	_check(hitter.ready, "the unit is ready to be ordered about")
	scene._select_unit(hitter.id)
	scene.ability_slot = 0
	scene.mode = scene.Mode.ABILITY
	scene.reachable = state.reachable_nodes(hitter)
	_check(not state.in_ability_range(hitter, 0, hitter.pos, victim.pos), "the target starts out of range")

	var spot: Vector2 = scene._closest_spot_in_range(hitter, 0, victim.pos)
	_check(spot != scene.NO_POINT, "there is somewhere in reach to attack from")
	_check(state.in_ability_range(hitter, 0, spot, victim.pos), "and the attack reaches from there")

	var target_spot: Vector2 = victim.pos
	_check(scene._walk_into_range(hitter, victim.pos), "the order sets the unit walking")
	_check(hitter.moved and hitter.pos == spot, "it walks to that spot")
	_check(not scene._pending_ability.is_empty(), "the ability is waiting for it to arrive")

	# It leaves before the blow lands: the attack hits where it was standing.
	var hp_before: int = victim.hp
	victim.pos = state.snap(Vector2(30.25, 30.25))
	scene._fire_pending_ability()
	# Using it spends the turn, which clears "acted" again: either way the
	# unit is no longer standing there waiting to act.
	_check(hitter.acted or not hitter.ready, "the ability is used on arrival")
	_check(victim.hp == hp_before, "a target that has moved on takes nothing")
	var missed := false
	for row in scene.hud._log._lines.get_children():
		for piece in row.get_children():
			if piece is Label and String(piece.text).contains("misses"):
				missed = true
	_check(missed, "and it is logged as a miss")

	# The same order with the target still there does land.
	var second = state.units[1]
	second.pos = state.snap(Vector2(12.25, 16.25))
	victim.pos = state.snap(second.pos + Vector2(3.5, 0))
	victim.hp = victim.max_hp()
	second.tg = GameState.TG_MAX - 1
	for i in 6:
		state.apply({"type": "advance", "ticks": 1})
	scene._select_unit(second.id)
	scene.ability_slot = 0
	scene.mode = scene.Mode.ABILITY
	scene.reachable = state.reachable_nodes(second)
	_check(scene._walk_into_range(second, victim.pos), "the second unit sets off too")
	var before: int = victim.hp
	scene._fire_pending_ability()
	_check(victim.hp < before, "a target still standing there is hit (%d -> %d)" % [before, victim.hp])
	scene.free()


## Edit layout: panels can be dragged somewhere else, stay there for the next
## battle, and go back where they belong when the layout is reset.
func _test_layout_editing() -> void:
	var hud = load("res://scripts/battle/hud.gd").new()
	var state := _new_state()
	hud.game_state = state
	root.add_child(hud)
	hud.build(true)
	await process_frame
	var layout = hud._layout
	_check(layout._panels.size() >= 6, "the movable panels are registered (%d)" % layout._panels.size())
	_check(not hud.is_layout_editing(), "a battle doesn't start in Edit layout")

	hud.toggle_layout_editing()
	_check(hud.is_layout_editing() and hud._layout_bar.visible, "Edit layout turns on, with its bar")
	var card = hud._card
	var was: float = card.offset_left
	layout._nudge("unit_card", Vector2(40, -25))
	_check(is_equal_approx(card.offset_left, was + 40.0), "a panel moves by what it was dragged")
	_check(layout._saved.get("unit_card", Vector2.ZERO) == Vector2(40, -25), "and how far it moved is remembered")

	# A new battle's HUD puts it back where the player left it.
	layout._save()
	var again = load("res://scripts/battle/hud.gd").new()
	again.game_state = state
	root.add_child(again)
	again.build(true)
	await process_frame
	_check(is_equal_approx(again._card.offset_left, was + 40.0), "the next battle opens with it where it was left")

	# Reset puts everything back.
	again._layout.reset()
	_check(is_equal_approx(again._card.offset_left, was), "Reset layout puts a panel back")
	_check(again._layout._saved.is_empty(), "and forgets what was saved")

	hud.toggle_layout_editing()
	_check(not hud.is_layout_editing(), "Edit layout turns off again")
	hud.free()
	again.free()


## What went wrong in a real match: the host kept talking to an opponent that
## had gone, every battle added another rematch listener that outlived it, and
## a menu that had already handed over to the battle still tried to open one.
func _test_online_housekeeping() -> void:
	var net = root.get_node("Net")

	# An opponent that drops is forgotten, so nothing is sent to it again.
	net.opponent_id = 312955946
	net._on_peer_disconnected(312955946)
	_check(net.opponent_id == 0, "an opponent that disconnects is forgotten")
	net.opponent_id = 4
	net._on_peer_disconnected(9)
	_check(net.opponent_id == 4, "somebody else disconnecting changes nothing")
	net.opponent_id = 0

	# The battle's rematch listener belongs to the battle, not to the tree, so
	# a second battle doesn't stack another one on top.
	root.get_node("GameConfig").mode = "hotseat"
	var first: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(first)
	await process_frame
	var before: int = net.game_started.get_connections().size()
	first.free()
	await process_frame
	_check(net.game_started.get_connections().size() <= before,
		"a battle that is gone stops listening for a rematch (%d -> %d)" % [before, net.game_started.get_connections().size()])

	# The combat log scrolls itself a frame after a message arrives, by which
	# time the battle may have ended and taken the log with it. Scrolling must
	# note what it wants and wait, not reach for the tree it has left.
	var log_window: Node = load("res://scripts/ui/log_window.gd").new()
	root.add_child(log_window)
	await process_frame
	log_window.add_message("A line, and then the battle ends")
	root.remove_child(log_window)
	# A last message lands after the battle took the log out of the tree.
	log_window.add_message("and one more on the way out")
	log_window._scroll_to_bottom()  # once needed the tree; now just a flag
	await process_frame
	_check(log_window.line_count() == 2 and log_window._want_bottom,
		"a log out of the tree still takes lines, and remembers it owes a scroll")
	# Back in the tree it pays that off on the next frame, and goes quiet again.
	root.add_child(log_window)
	await process_frame
	_check(not log_window._want_bottom and not log_window.is_processing(),
		"the waiting scroll happens once it is back in the tree, then stops")
	root.remove_child(log_window)
	log_window.free()

	# A menu that has been replaced doesn't try to open a battle.
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	root.remove_child(menu)
	menu._on_game_started()  # would have been "Cannot call method on a null value"
	_check(true, "a menu out of the tree ignores a game starting")
	menu.free()


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
	s3._add_status(s3.units[1], "burn", 3)
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

	# Reviving from on top of the knocked-out ally (bodies don't block): the
	# computer's order must follow the ally, not the caster.
	var rv := _new_state()
	var mage = null
	for unit in rv.units:
		if unit.team == 0 and unit.job == "white_mage":
			mage = unit
	var fallen = rv.units[0]
	rv._knock_out(fallen, "x", {"logs": [], "knocked_out": [], "gone": []})
	mage.pos = fallen.pos
	mage.ready = true
	mage.clock = 200
	mage.moved = true  # it must act from on top of the ally
	var revive := ai.next_command(rv, mage)
	_check(revive.get("slot", -1) == 0 and rv.validate(revive) == "",
		"the computer revives an ally it stands on (%s: %s)" % [revive, rv.validate(revive)])

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
	var wins := [0, 0]
	# Each game gets its own seed, for the battle and for the easy AI's own
	# mistakes, so the run is varied but always the same from run to run:
	# a failure here is a real change in play, not a bad roll.
	for game in 8:
		state = GameState.new()
		state.setup(MapData.highlands(), {}, game + 1)
		easy.rng.seed = game + 1
		hard.rng.seed = game + 1
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
	print("Easy (Blue) vs Hard (Red) over 8 games: easy %d, hard %d" % wins)
	_check(wins[1] >= wins[0], "hard beats easy at least as often as it loses")


## Developer Tools rule numbers ("tuning") and the "tune" command.
func _test_tuning() -> void:
	var plain := _new_state()
	_check(plain.tune("speed_multiplier") == 1.0 and plain.tune("patience_multiplier") == GameState.CLOCK_PER_PATIENCE,
		"default tuning matches the rule constants")
	var fast := GameState.new()
	fast.setup(MapData.highlands(), {"speed_multiplier": 2.0, "patience_multiplier": 3.0, "bogus": 5, "move_multiplier": 99.0})
	var u = fast.units[0]
	_check(fast._tg_gain(u) == 2 * plain._tg_gain(plain.units[0]), "Speed multiplier doubles Turn Gauge speed")
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
	_check(plain.explain_turn(a).contains("Speed %d" % a.stat("speed")) and plain.explain_countdown(a).contains("Patience"),
		"turn and countdown explanations name their stats")

	# A tune in the middle of a battle replays exactly.
	var ai := AIPlayer.new()
	var state := _new_state()
	var log: Array = []
	while state.winner == -1 and state.tick < 20000:
		if state.tick == 300 and log.size() > 0 and log[-1].type != "tune":
			var tune := {"type": "tune", "values": {"speed_multiplier": 1.5, "damage_multiplier": 0.8, "cast_time_multiplier": 0.5}}
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
	_check(tm.speed == 16 and tm.meva == 16 and tm.power == 16 and tm.abilities.size() == 4, "Time Mage stats come from its profile")
	var bolt: Dictionary = Jobs.ability(tm.abilities[0])
	_check(bolt.effect == "damage" and bolt.cast == 0.0 and bolt.power >= 15.0 and bolt.tg == -10, "Chrono Bolt: instant damage, flat power, TG -10%")
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
	# Every class file made in Astra imports cleanly, with an icon.
	var class_files := DirAccess.get_files_at("res://data/classes/")
	var imported := 0
	for file in class_files:
		if file.ends_with(".json"):
			var r := AstraImport.parse(FileAccess.get_file_as_string("res://data/classes/" + file))
			_check(r.errors.is_empty() and r.jobs.size() == 1, "%s imports cleanly %s" % [file, r.errors])
			for id in r.jobs:
				_check(Jobs.icon_path(id) != Jobs.GENERIC_ICON, "%s has its own icon" % id)
			imported += r.jobs.size()
	_check(imported >= 11, "at least 11 imported classes (%d)" % imported)

	# The new classes in battle, two games (every class on the field), legal orders throughout.
	var mixes := [[["dragoon", "ninja", "summoner", "paladin"], ["bard", "berserker", "chemist", "geomancer"]],
		[["oracle", "samurai", "chemist", "bard"], ["paladin", "summoner", "ninja", "dragoon"]]]
	for mix in mixes:
		var game := GameState.new()
		game.setup(MapData.build(MapData.DEFAULT_MAP, mix[0], mix[1]))
		var ok := true
		while game.winner == -1 and game.tick < 40000 and ok:
			var ready := game.orderable_units()
			if ready.is_empty():
				game.apply({"type": "advance", "ticks": 1})
				continue
			var cmd := ai.next_command(game, ready[0])
			ok = game.validate(cmd) == ""
			if not ok:
				printerr("illegal: ", cmd, " ", game.validate(cmd))
			game.apply(cmd)
		_check(ok and game.winner != -1, "a battle of %s vs %s finishes with legal orders" % mix)

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
	log.toggle_options()
	_check(log._options.visible, "the cog opens the combat log options")
	log.set_options(18, Color(1, 0.8, 0.2), 0.4)
	var line: Label = log._lines.get_child(0).get_child(0)
	_check(line.get_theme_font_size("font_size") == 18 and line.get_theme_color("font_color") == log.color_for("system")
		and is_equal_approx(log._style.bg_color.a, 0.4), "log options change every line's size and color and the background")
	log.add_message("new line")
	var newest: Label = log._lines.get_child(log.line_count() - 1).get_child(0)
	_check(newest.get_theme_font_size("font_size") == 18, "new log lines use the chosen size")
	log.set_options(99, Color.WHITE, 0.4)
	_check(log.font_size == LogWindow.FONT_SIZES.y, "log text size stays within its limits")
	log.set_options(18, Color(1, 0.8, 0.2), 0.4)
	log.toggle_collapsed()
	log.hide_log()
	var again = LogWindow.new()
	root.add_child(again)
	await process_frame
	_check(not again.visible and again.position == log.position, "the combat log remembers where it was and that it was hidden")
	_check(again.font_size == 18 and again.text_color == Color(1, 0.8, 0.2) and is_equal_approx(again.opacity, 0.4),
		"the combat log remembers its text size, color and background")
	log.queue_free()
	again.queue_free()
	if saved_cfg != "":
		var f := FileAccess.open(LogWindow.SAVE_PATH, FileAccess.WRITE)
		f.store_string(saved_cfg)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LogWindow.SAVE_PATH))


## Turn order bars: icons sit on their team's bar; close ones merge into one
## framed group side by side (each still its own button), far ones don't.
func _test_turn_order_groups() -> void:
	var hud = load("res://scripts/battle/hud.gd").new()
	root.add_child(hud)
	hud.build(true)
	await process_frame
	var entry := func(id: int, team: int, seconds: float) -> Dictionary:
		return {"id": id, "team": team, "job": "knight", "title": "Blue Knight", "name": "Knight",
			"color": Color(0.5, 0.7, 1.0), "ready": false, "casting": "", "cast_seconds": 0.0,
			"seconds": seconds, "since_turn": INF, "tip": "", "selected": false, "hidden": false}
	var entries := [entry.call(0, 0, 6.0), entry.call(1, 0, 6.2), entry.call(2, 0, 25.0), entry.call(3, 1, 6.1)]
	var settings := root.get_node("Settings")
	var icons_before: bool = settings.turn_icons

	# The other display first: one fixed square per unit, whoever is ready.
	settings.turn_icons = true
	hud.set_turn_order(entries)
	await process_frame
	_check(hud._squares.size() == entries.size(), "the fixed turn squares are one per unit")
	_check(not hud._timeline.visible, "the sliding bars are put away while the squares are shown")

	settings.turn_icons = false
	for i in 60:  # let the chips glide into place
		hud.set_turn_order(entries)
		await process_frame
	_check(hud._timeline.visible, "the bars come back when the squares are turned off")
	settings.turn_icons = icons_before
	var a: Button = hud._chip_for[0]
	var b: Button = hud._chip_for[1]
	var far: Button = hud._chip_for[2]
	var red: Button = hud._chip_for[3]
	var a_rect := Rect2(a.position, a.size * a.scale)
	var b_rect := Rect2(b.position, b.size * b.scale)
	var shown := 0
	for f in hud._frames:
		shown += 1 if f.visible else 0
	_check(not a_rect.intersects(b_rect) and absf(a.position.y - b.position.y) < 2.0 and shown == 1,
		"close icons merge into one framed group, side by side")
	_check(hud._frames[0].get_rect().encloses(a_rect) and hud._frames[0].get_rect().encloses(b_rect)
		and not hud._frames[0].get_rect().intersects(Rect2(far.position, far.size * far.scale)),
		"the group frame holds both icons and not a far one")
	_check(red.position.y > a.position.y + 20.0, "each team's icons sit on their own bar")
	var bar_y: float = hud.BAR_Y
	_check(absf(a.position.y + a.size.y * a.scale.y * 0.5 - bar_y) < 1.0, "icons sit centered on the bar")
	var pressed := []
	hud.chip_pressed.connect(func(id: int): pressed.append(id))
	a.pressed.emit()
	b.pressed.emit()
	_check(pressed == [0, 1], "icons in a group can still be clicked separately")
	hud.queue_free()


## Class stats changed in the Unit Guide: applied to units, limited, saved,
## editable from the main menu's guide only. The player's own are put back.
func _test_stat_changes() -> void:
	var config := root.get_node("GameConfig")
	var saved: Dictionary = config.stat_overrides.duplicate(true)
	config.reset_stats()
	config.set_stat("knight", "hp", 150)
	config.set_stat("knight", "speed", 99)
	config.set_stat("archer", "move", Jobs.base_job("archer").move)  # its own value: no change
	_check(Jobs.job("knight").hp == 150 and Jobs.job("knight").speed == Jobs.STAT_LIMITS.speed[1] and not Jobs.stat_overrides.has("archer"),
		"changed stats apply, stay within limits, and a class's own value is no change")
	var state := GameState.new()
	state.setup(MapData.build(MapData.DEFAULT_MAP, ["knight", "archer", "monk", "squire"], ["knight", "archer", "monk", "squire"]))
	_check(state.units[0].hp == 150 and state.units[0].max_hp() == 150 and state.units[0].stat("speed") == Jobs.STAT_LIMITS.speed[1],
		"a new battle's units use the changed stats")
	_check(Jobs.clean_overrides({"knight": {"bogus": 3, "att": "x"}, "nobody": {"hp": 50}}).is_empty(), "bad stat changes are dropped")
	var file := ConfigFile.new()
	_check(file.load(config.STATS_PATH) == OK and file.get_value("knight", "hp") == 150, "changed stats are saved")

	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._open_guide()
	await process_frame
	var guide = menu.guide
	var knight_row: int = guide._listed_ids().find("knight")  # the list is sorted
	var grid: GridContainer = guide._stats_holder.get_child(0)
	# Columns: Job, Role, then the stats (HP first).
	var hp_cell: Label = grid.get_child((knight_row + 1) * grid.columns + 2)
	_check(guide.editable and hp_cell.text == "150" and hp_cell.get_theme_color("font_color") == guide.CHANGED_COLOR,
		"the main menu's Unit Guide shows changed stats in gold")
	guide._edit_stat("knight", "speed", hp_cell)
	guide._edit_stat("knight", "attdef", hp_cell)
	_check(Jobs.job("knight").speed == Jobs.STAT_LIMITS.speed[1] and Jobs.job("knight").attdef == Jobs.base_job("knight").attdef,
		"opening the stat editor changes nothing")
	guide._editor_box.value = 20
	guide._editor.hide()
	await process_frame
	_check(Jobs.job("knight").attdef == 20, "editing a stat in the Unit Guide changes it")
	menu.queue_free()
	var in_battle = load("res://scripts/ui/unit_guide.gd").new()
	_check(not in_battle.editable, "the in-battle Unit Guide can't change stats")
	in_battle.free()
	config.reset_stats()
	_check(Jobs.job("knight").hp == Jobs.base_job("knight").hp, "Reset puts every class's stats back")
	config.stat_overrides = saved
	config._save_stats()


## Developer Tools: sliders, saved values and formula tooltips.
func _test_dev_tools() -> void:
	var config := root.get_node("GameConfig")
	var saved: Dictionary = config.tuning.duplicate()
	config.reset_tuning()  # start from the defaults, whatever was saved
	var tools: Control = load("res://scripts/ui/dev_tools.gd").new()
	tools.live = true
	var sent: Array = []
	tools.tuning_changed.connect(func(v: Dictionary): sent.append(v))
	root.add_child(tools)
	await process_frame
	var sliders: Array = tools.find_children("*", "HSlider", true, false)
	_check(tools._sliders.size() == GameState.TUNING.size(), "Developer Tools has a slider per rule number")
	# Plus the "Look" sliders, which change display settings rather than rules.
	_check(sliders.size() > tools._sliders.size(), "Developer Tools also has the display sliders")
	var settings := root.get_node("Settings")
	var circle_before: float = settings.unit_circle_size
	var look: HSlider = sliders[0]
	look.value = 1.6
	_check(is_equal_approx(settings.unit_circle_size, 1.6), "a display slider changes the setting at once")
	settings.set_value("unit_circle_size", circle_before)
	tools._sliders.speed_multiplier.value = 1.5
	_check(config.tuning.get("speed_multiplier") == 1.5, "moving a slider saves the value")
	var tip: String = tools._sliders.speed_multiplier.tooltip_text
	_check(tip.contains("Speed multiplier 1.5") and tip.contains("= "), "the slider tooltip shows the formula with the new value")
	_check(tools._sliders.patience_multiplier.tooltip_text.contains("Patience"), "the Patience slider tooltip shows the countdown math")
	# The change is sent once the slider settles (DevTools.APPLY_DELAY), which
	# is a time, not a number of frames.
	for i in 2000:
		if not sent.is_empty():
			break
		await process_frame
	_check(sent.size() == 1 and sent[0].get("speed_multiplier") == 1.5,
		"a live battle gets the change once, after the slider settles (got %s, live=%s, pending=%s)" % [sent, tools.live, tools._pending])
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
	# The log was recorded without evasion or criticals (see _new_state), so
	# the replay has to run with the same rules and seed.
	config.replay_tuning = {"evade_multiplier": 0.0, "crit_chance_multiplier": 0.0}
	config.replay_seed = 0
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
			"res://scripts/ui/class_picker.gd", "res://scripts/ui/class_list.gd", "res://scripts/ui/log_window.gd",
			"res://scripts/autoload/settings.gd", "res://scripts/autoload/audio.gd",
			"res://scripts/autoload/net.gd", "res://scripts/autoload/keybinds.gd"]:
		var script: Script = load(path)
		# can_instantiate() still says yes for a script whose own parse failed,
		# so the check actually makes one.
		var made: Variant = script.new() if script != null and script.can_instantiate() else null
		_check(made != null, "%s compiles" % path)
		if made is Node:
			(made as Node).free()
	if failures > 0:
		return
	for mode in ["ai", "hotseat"]:
		root.get_node("GameConfig").mode = mode
		var scene: Node = load("res://scenes/battle.tscn").instantiate()
		root.add_child(scene)
		for i in 5:
			await process_frame
		_check(scene.state.units.size() == 8 and scene.unit_views.size() == 8 and scene.hud != null, "battle scene (%s) builds" % mode)
		if mode == "hotseat":
			# Sprinting to a spot a walk couldn't reach: the unit has to end up
			# there on screen too, not only in the rules.
			var runner = scene.state.units[0]
			runner.tg = GameState.TG_MAX - 1
			for i in 6:
				scene.state.apply({"type": "advance", "ticks": 1})
			var reach: Dictionary = scene.state.reachable_nodes(runner)
			var sprint_spot := Vector2.ZERO
			for n in scene.state.reachable_nodes(runner, true):
				if not reach.has(n):
					sprint_spot = scene.state.node_pos(n)
					break
			_check(sprint_spot != Vector2.ZERO and runner.ready, "there is somewhere only a sprint reaches")
			scene._apply({"type": "move", "unit": runner.id, "serial": runner.serial, "to": sprint_spot, "sprint": true})
			# Headless frames run far faster than real time, and the walk is a
			# tween over seconds, so wait on the clock rather than on frames.
			var walk_until := Time.get_ticks_msec() + 3000
			while Time.get_ticks_msec() < walk_until:
				await process_frame
			var view_at: Vector3 = scene.unit_views[runner.id].position
			var should_be: Vector3 = scene.board.ground(runner.pos)
			_check(runner.pos == sprint_spot, "the rules move the unit to the sprint's destination")
			_check(view_at.distance_to(should_be) < 0.3, "and its model walks there (at %s, should be %s)" % [view_at, should_be])
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
	var picker: OptionButton = menu.guide._class_picker
	_check(menu.guide.visible and picker.item_count == Jobs.all_jobs().size() and picker.item_count > 100,
		"unit guide opens from the menu with every class in its class picker (%d)" % picker.item_count)
	menu.guide.show_class("time_mage")
	var shown_grid: Array = menu.guide._ability_box.find_children("Grid", "GridContainer", true, false)
	_check(shown_grid.size() == 1 and (shown_grid[0] as GridContainer).get_child_count() == 5 * menu.guide.ABILITY_COLUMNS.size(),
		"picking a class shows its four abilities")

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
