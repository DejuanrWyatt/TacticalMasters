# Dumps what abilities do, for the Unreal port to be measured against.
#
#   godot --headless --script res://tests/dump_ability_table.gd > GodotAbilityTable.txt
#
# Print the version alongside it: the table is only meaningful as the output of a
# known script against a known build, and it must never be hand-edited to make a
# test pass. If the port disagrees, either the port is wrong or this script is.
#
# The file goes in the Unreal project's Tests/ folder. Regenerate it whenever the
# ability rules change, or the C++ test will rightly start failing.
#
# Three sections, because abilities go wrong in three different ways.
#
# PREVIEW is who an ability would reach and for how much, without doing any of
# it. It is the pure part, so it is dumped over a wide matrix: every class, every
# slot, aimed at every unit and at a few patches of empty ground.
#
# RESOLVE is what actually happens, which is a different question because it
# involves the dice. Each case starts from the same board with the generator set
# to a known state, so the port has to roll the same numbers in the same order to
# arrive at the same result. The order is the thing most likely to differ and the
# hardest to spot: a port that rolls crit before evade agrees about almost
# everything until it does not.
#
# TRACE is the clock: a cast is begun and lands several ticks later, and where it
# lands is decided when it lands rather than when it was cast. Tick-by-tick, so a
# port that resolves a cast one tick early shows up here rather than in a battle
# ten seconds later.
extends SceneTree

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const Jobs = preload("res://scripts/core/jobs.gd")

## The classes with abilities written in code (the other 81 await the importer).
const ROSTER := ["knight", "archer", "black_mage", "white_mage", "knight", "archer", "black_mage", "white_mage"]

func _n(v: float) -> String:
	return "%.2f" % v

## The same empty result apply() builds, so the rules can write into it.
func _result() -> Dictionary:
	return {"logs": [], "events": [], "became_ready": [], "turn_ended": [], "cast_started": [],
		"resolved": [], "knocked_out": [], "revived": [], "gone": [], "timed_out": []}

## Every unit, in the shape the C++ side rebuilds a board from.
func _units(s: GameState) -> void:
	print("UNITS")
	for u in s.units:
		# Everything needed to stand the same board up again, including whatever
		# is already on each unit: the statuses are half the point of the cases
		# below, so they cannot be left implicit.
		print("  %d %s team=%d pos=%s,%s facing=%s,%s maxhp=%d ko=%d clock=%d %s" % [
			u.id, u.job, u.team, _n(u.pos.x), _n(u.pos.y), _n(u.facing.x), _n(u.facing.y),
			u.max_hp(), u.ko_ticks, u.clock, _state_of(u)])

## Everything about a unit an ability could have changed.
func _state_of(u) -> String:
	var statuses: Array[String] = []
	for st in u.statuses:
		statuses.append("%s:%d:%d:%d" % [st.id, st.turns, int(st.get("amount", 0)), int(st.get("by", -1))])
	var buffs: Array[String] = []
	for b in u.buffs:
		buffs.append("%s:%d:%d" % [b.stat, b.amount, b.turns])
	return "hp=%d tg=%d ult=%d ready=%d moved=%d acted=%d cd=%d,%d,%d,%d statuses=%s buffs=%s" % [
		u.hp, u.tg, u.ult, int(u.ready), int(u.moved), int(u.acted),
		u.cooldowns[0], u.cooldowns[1], u.cooldowns[2], u.cooldowns[3],
		"|".join(statuses) if statuses.size() > 0 else "-",
		"|".join(buffs) if buffs.size() > 0 else "-"]

## Aim points worth trying: every unit's feet, plus ground nobody is standing on.
func _aims(s: GameState, caster) -> Array[Vector2]:
	var out: Array[Vector2] = [caster.pos]
	for t in s.units:
		if t.id != caster.id:
			out.append(t.pos)
	for offset in [Vector2(3.0, 0.0), Vector2(0.0, 4.0), Vector2(-2.5, 2.5), Vector2(6.0, 6.0)]:
		var spot := s.snap(caster.pos + offset)
		if s.in_bounds(spot) and s.level_at(spot) > 0:
			out.append(spot)
	return out

## Packs the two sides close enough that most abilities can actually reach.
func _gather(s: GameState) -> void:
	var spots: Array[Vector2] = []
	for ty in range(4, s.tiles_y - 4):
		for tx in range(4, s.tiles_x - 4):
			var centre := Vector2(tx * s.TILE_SIZE + 1.0, ty * s.TILE_SIZE + 1.0)
			if s.level_at(centre) > 0:
				spots.append(centre)
	var taken: Array[Vector2] = []
	for u in s.units:
		for spot in spots:
			var clash := false
			for t in taken:
				if t.distance_to(spot) < 1.5:
					clash = true
					break
			if not clash:
				u.pos = s.snap(spot)
				taken.append(spot)
				break

func _base() -> GameState:
	var s := GameState.new()
	s.setup(MapData.highlands(), {}, 12345)
	for i in s.units.size():
		s.units[i].job = ROSTER[i]
	_gather(s)
	# A spread of health, so healing has something to do, a revive has someone to
	# raise, and the cap on healing is actually reached.
	s.units[1].hp = int(s.units[1].max_hp() * 0.35)
	s.units[3].hp = int(s.units[3].max_hp() * 0.8)
	s.units[5].hp = int(s.units[5].max_hp() * 0.15)
	# One knocked out, which is the only thing a revive can be aimed at.
	s.units[6].hp = 0
	s.units[6].ko_ticks = 40
	# Facing every which way, so hits from the side and from behind both happen.
	var faces := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	for i in s.units.size():
		s.units[i].facing = faces[i % 4]
	# Statuses that change what resolution does: one that soaks damage, one that
	# turns it away, one asleep to be woken, one immune to be refused.
	s.units[2].statuses.append({"id": "shield", "turns": 3, "amount": 18})
	s.units[4].statuses.append({"id": "invuln", "turns": 2})
	s.units[7].statuses.append({"id": "sleep", "turns": 3})
	s.units[0].statuses.append({"id": "immunity", "turns": 3})
	# Full meters, so the ultimates are legal and can be dumped.
	for u in s.units:
		u.ult = s.ULT_MAX
		u.ready = true
		u.tg = s.TG_MAX
		u.clock = s.clock_ticks(u)
	return s

func _dump_preview(s: GameState) -> void:
	print("PREVIEW")
	var cases := 0
	for caster in s.units:
		if not caster.is_alive():
			continue
		for slot in 4:
			for aim in _aims(s, caster):
				var hits: Array[Dictionary] = s.preview(caster, slot, caster.pos, aim)
				var parts: Array[String] = []
				for h in hits:
					parts.append("%d:%d:%s" % [h.unit.id, h.amount, _n(h.flank)])
				print("  %d %d %s,%s inrange=%d los=%d hits=%s" % [
					caster.id, slot, _n(aim.x), _n(aim.y),
					int(s.in_ability_range(caster, slot, caster.pos, aim)),
					int(s.has_line_of_sight(caster.pos, aim)),
					"|".join(parts) if parts.size() > 0 else "-"])
				cases += 1
	print("PREVIEW CASES %d" % cases)

func _dump_resolve(s: GameState) -> void:
	print("RESOLVE")
	var cases := 0
	for caster_id in s.units.size():
		if not s.units[caster_id].is_alive():
			continue
		for slot in 4:
			for aim in _aims(s, s.units[caster_id]):
				# A fresh board every time, with the generator put in a known
				# place, so each case is answerable on its own.
				var w = s.snapshot()
				w.rng.seed = 1000 + cases
				var caster = w.get_unit(caster_id)
				if s.ability_blocked_reason(caster, slot) != "":
					cases += 1
					continue
				var result := _result()
				w._resolve_ability(caster, slot, aim, result)
				var r: Dictionary = result.resolved[0] if result.resolved.size() > 0 else {}
				var amounts: Array[String] = []
				for i in int(r.get("hits", []).size()):
					amounts.append("%d:%d" % [r.hits[i], r.amounts[i]])
				print("  case=%d caster=%d slot=%d aim=%s,%s seed=%d" % [
					cases, caster_id, slot, _n(aim.x), _n(aim.y), 1000 + cases])
				print("    struck=%s evaded=%s crits=%s avoided=%d winner=%d" % [
					"|".join(amounts) if amounts.size() > 0 else "-",
					"|".join(PackedStringArray(r.get("evaded", []).map(func(x): return str(x)))) if r.get("evaded", []).size() > 0 else "-",
					"|".join(PackedStringArray(r.get("crits", []).map(func(x): return str(x)))) if r.get("crits", []).size() > 0 else "-",
					int(r.get("avoided", 0)), w.winner])
				for u in w.units:
					print("    %d %s" % [u.id, _state_of(u)])
				cases += 1
	print("RESOLVE CASES %d" % cases)

## Committing to an ability, which is a separate question from what it does.
## Paying for it -- the meter, the cooldown, the unit's action, which way it ends
## up facing -- happens whether it goes off now or several ticks later, and none
## of it is visible in the resolution cases because those call the resolver
## directly, exactly as the original does.
func _dump_use(s: GameState) -> void:
	print("USE")
	var cases := 0
	for caster_id in s.units.size():
		if not s.units[caster_id].is_alive():
			continue
		for slot in 4:
			var aim_list := _aims(s, s.units[caster_id])
			# One aim per slot is enough here: what it costs does not depend on
			# where it was pointed, only on which slot it was.
			var aim: Vector2 = aim_list[mini(1, aim_list.size() - 1)]
			var w = s.snapshot()
			w.rng.seed = 5000 + cases
			var caster = w.get_unit(caster_id)
			var blocked: String = w.ability_blocked_reason(caster, slot)
			print("  case=%d caster=%d slot=%d aim=%s,%s blocked=%s" % [
				cases, caster_id, slot, _n(aim.x), _n(aim.y),
				"yes" if blocked != "" else "no"])
			if blocked == "":
				var result := _result()
				w._use_ability(caster, slot, aim, -1, result)
				print("    casting=%d castticks=%d channeling=%d channelturns=%d facing=%s,%s toggled=%d" % [
					int(caster.is_casting()), int(caster.casting.get("ticks", 0)),
					int(caster.is_channeling()), int(caster.channeling.get("turns", 0)),
					_n(caster.facing.x), _n(caster.facing.y),
					int(caster.toggled.get(slot, false))])
				print("    %d %s" % [caster_id, _state_of(caster)])
			cases += 1
	print("USE CASES %d" % cases)

## A cast begun, and the ticks until it lands. Four of them, because each goes
## wrong differently: one that follows a unit who walks away, one nailed to the
## ground that somebody walks into, one whose caster is struck down mid-cast, and
## the four-second one.
func _dump_trace(s: GameState) -> void:
	print("TRACE")
	var scenes := [
		{"name": "follows", "caster": 2, "slot": 1, "follow": 4, "kill": -1, "walk": 4},
		{"name": "ground", "caster": 2, "slot": 2, "follow": -1, "kill": -1, "walk": -1},
		{"name": "fizzles", "caster": 2, "slot": 3, "follow": 4, "kill": 2, "walk": -1},
		{"name": "meteor", "caster": 6, "slot": 3, "follow": -1, "kill": -1, "walk": -1},
	]
	for scene in scenes:
		var w = s.snapshot()
		w.rng.seed = 777
		# Everyone awake and unshielded, so the trace is about the clock alone.
		for u in w.units:
			u.statuses.clear()
		w.units[6].hp = w.units[6].max_hp()
		w.units[6].ko_ticks = 0
		var caster = w.get_unit(scene.caster)
		var target = w.get_unit(scene.follow) if scene.follow >= 0 else null
		var aim: Vector2 = target.pos if target != null else w.snap(caster.pos + Vector2(3.0, 0.0))
		print("  SCENE %s caster=%d slot=%d follow=%d aim=%s,%s" % [
			scene.name, scene.caster, scene.slot, scene.follow, _n(aim.x), _n(aim.y)])
		if w.ability_blocked_reason(caster, scene.slot) != "":
			print("    BLOCKED %s" % w.ability_blocked_reason(caster, scene.slot))
			continue
		var result := _result()
		w._use_ability(caster, scene.slot, aim, scene.follow, result)
		print("    started casting=%d ticks=%d" % [
			int(caster.is_casting()), int(caster.casting.get("ticks", 0))])
		# Whoever is being followed steps aside, to prove the spell tracks them.
		if scene.walk >= 0:
			var runner = w.get_unit(scene.walk)
			runner.pos = w.snap(runner.pos + Vector2(4.0, 2.0))
			print("    unit %d walks to %s,%s" % [scene.walk, _n(runner.pos.x), _n(runner.pos.y)])
		if scene.kill >= 0:
			w.get_unit(scene.kill).hp = 0
			w._knock_out(w.get_unit(scene.kill), "test", result)
			print("    unit %d is struck down" % scene.kill)
		for t in 45:
			var step := _result()
			w._tick(step)
			var casting: int = int(caster.casting.get("ticks", 0)) if caster.is_casting() else -1
			var hp: Array[String] = []
			for u in w.units:
				hp.append(str(u.hp))
			print("    t=%d cast=%d resolved=%d hp=%s" % [
				w.tick, casting, step.resolved.size(), ",".join(hp)])

func _initialize() -> void:
	await process_frame
	var s := _base()
	print("FROM tests/dump_ability_table.gd godot=%s" % Engine.get_version_info().string)
	var keys := ["damage_multiplier", "heal_multiplier", "height_bonus", "side_bonus", "back_bonus",
		"crit_multiplier", "evade_multiplier", "crit_chance_multiplier", "cast_time_multiplier",
		"ko_seconds", "ult_per_action", "ult_per_turn", "stun_tg_percent", "hazard_percent",
		"regen_percent", "regen_after_turns", "clock_base", "patience_multiplier", "speed_multiplier"]
	var tuned: Array[String] = []
	for k in keys:
		tuned.append("%s=%s" % [k, s.tune(k)])
	print("TUNING %s" % " ".join(tuned))
	print("CONSTANTS tg_max=%d ult_max=%d hit_radius=%s melee_range=%s ticks_per_second=%d" % [
		s.TG_MAX, s.ULT_MAX, _n(s.HIT_RADIUS), _n(s.MELEE_RANGE), s.TICKS_PER_SECOND])
	_units(s)
	_dump_preview(s)
	_dump_resolve(s)
	_dump_use(s)
	_dump_trace(s)
	quit(0)
