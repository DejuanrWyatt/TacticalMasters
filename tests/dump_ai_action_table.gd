# Dumps what the computer decides to DO with its turn, for the Unreal port to be
# measured against. Where dump_ai_table.gd covers where it would rather stand,
# this covers which ability it picks, where it aims it, and what it thinks that
# is worth.
#
#   godot --headless --script res://tests/dump_ai_action_table.gd > GodotAIActionTable.txt
#
# The file goes in the Unreal project's Tests/ folder. Regenerate it whenever the
# way the computer chooses changes, and never edit it to make a test pass.
#
# Hard only, deliberately. At hard the generator is untouched -- GDScript
# short-circuits `mistakes > 0.0 and rng.randf() < mistakes` -- so the choice is
# wholly deterministic and a port can be held to it exactly. Easy and medium roll
# to settle for a worse option, and that roll needs Godot's randf, which is not
# ported (see SimRandom.h for what is known about it).
#
# Two sections. SCORE pins the scoring formula on its own, over a fixed set of
# (caster, slot, aim) triples, so a mistake in the arithmetic is separable from a
# mistake in the search. CHOICE is the whole decision: every spot it could stand
# on, every target it could aim at, and the one it settles on.
extends SceneTree

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")

const ROSTER := ["knight", "archer", "black_mage", "white_mage", "knight", "archer", "black_mage", "white_mage"]

var _ai := AIPlayer.new("hard")

func _n(v: float) -> String:
	return "%.2f" % v

## Scores are compared to a few decimals, so they are printed to more than that.
func _s(v: float) -> String:
	return "%.6f" % v

func _units(s: GameState) -> void:
	print("UNITS")
	for u in s.units:
		var statuses: Array[String] = []
		for st in u.statuses:
			statuses.append("%s:%d:%d:%d" % [st.id, st.turns, int(st.get("amount", 0)), int(st.get("by", -1))])
		print("  %d %s team=%d pos=%s,%s facing=%s,%s hp=%d maxhp=%d tg=%d ult=%d ready=%d moved=%d acted=%d ko=%d clock=%d cd=%d,%d,%d,%d statuses=%s" % [
			u.id, u.job, u.team, _n(u.pos.x), _n(u.pos.y), _n(u.facing.x), _n(u.facing.y),
			u.hp, u.max_hp(), u.tg, u.ult, int(u.ready), int(u.moved), int(u.acted),
			u.ko_ticks, u.clock,
			u.cooldowns[0], u.cooldowns[1], u.cooldowns[2], u.cooldowns[3],
			"|".join(statuses) if statuses.size() > 0 else "-"])

## Packs the sides together so most abilities can actually reach something.
func _gather(s: GameState, apart: float) -> void:
	var spots: Array[Vector2] = []
	for ty in range(3, s.tiles_y - 3):
		for tx in range(3, s.tiles_x - 3):
			var centre := Vector2(tx * s.TILE_SIZE + 1.0, ty * s.TILE_SIZE + 1.0)
			if s.level_at(centre) > 0:
				spots.append(centre)
	var taken: Array[Vector2] = []
	for u in s.units:
		for spot in spots:
			var clash := false
			for t in taken:
				if t.distance_to(spot) < apart:
					clash = true
					break
			if not clash:
				u.pos = s.snap(spot)
				taken.append(spot)
				break

func _base(apart: float) -> GameState:
	var s := GameState.new()
	s.setup(MapData.highlands(), {}, 12345)
	for i in s.units.size():
		s.units[i].job = ROSTER[i]
	_gather(s, apart)
	# A spread of health, so healing is worth something, a finishing blow is on
	# the table, and a revive has somebody to raise.
	s.units[1].hp = int(s.units[1].max_hp() * 0.30)
	s.units[3].hp = int(s.units[3].max_hp() * 0.85)
	s.units[5].hp = int(s.units[5].max_hp() * 0.12)
	s.units[6].hp = 0
	s.units[6].ko_ticks = 60
	var faces := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	for i in s.units.size():
		s.units[i].facing = faces[i % 4]
	# Everyone waiting to act, meters full, so ultimates are legal and the
	# status reasoning about units mid-turn is exercised.
	for u in s.units:
		if u.is_alive():
			u.ready = true
			u.tg = s.TG_MAX
			u.clock = s.clock_ticks(u)
			u.ult = s.ULT_MAX
	return s

## The scoring formula on its own, away from the search over spots.
func _dump_score(s: GameState) -> void:
	print("SCORE")
	var cases := 0
	for caster in s.units:
		if not caster.is_alive():
			continue
		for slot in 4:
			if s.ability_blocked_reason(caster, slot) != "":
				continue
			var ab: Dictionary = caster.ability(slot)
			for t in s.units:
				var aim: Vector2 = caster.pos if ab.max_range == 0.0 else t.pos
				var hits: Array[Dictionary] = s.preview(caster, slot, caster.pos, aim)
				var worth: float = _ai._score(caster, slot, ab, hits, s)
				var struck: Array[String] = []
				for h in hits:
					struck.append("%d:%d" % [h.unit.id, h.amount])
				print("  %d %d %s,%s score=%s hits=%s" % [
					caster.id, slot, _n(aim.x), _n(aim.y), _s(worth),
					"|".join(struck) if struck.size() > 0 else "-"])
				cases += 1
	print("SCORE CASES %d" % cases)

## The whole decision, including where it would stand to make it.
func _dump_choice(s: GameState, name: String) -> void:
	print("CHOICE %s" % name)
	var cases := 0
	for u in s.units:
		if not u.is_alive():
			continue
		var reach: Dictionary = {} if u.moved or u.is_casting() else s.reachable_nodes(u)
		var best: Dictionary = _ai._best_action(s, u, reach)
		if best.is_empty():
			print("  %d nothing" % u.id)
		else:
			print("  %d slot=%d spot=%s,%s target=%s,%s follow=%d score=%s" % [
				u.id, int(best.slot), _n(best.spot.x), _n(best.spot.y),
				_n(best.target.x), _n(best.target.y), int(best.follow), _s(best.score)])
		cases += 1
	print("CHOICE CASES %d" % cases)

func _initialize() -> void:
	await process_frame
	print("FROM tests/dump_ai_action_table.gd godot=%s difficulty=hard" % Engine.get_version_info().string)
	var s := _base(1.6)
	var keys := ["damage_multiplier", "heal_multiplier", "height_bonus", "side_bonus", "back_bonus",
		"crit_multiplier", "evade_multiplier", "crit_chance_multiplier", "cast_time_multiplier",
		"ko_seconds", "ult_per_action", "ult_per_turn", "stun_tg_percent", "hazard_percent",
		"regen_percent", "regen_after_turns", "clock_base", "patience_multiplier", "speed_multiplier",
		"sight_multiplier", "move_multiplier", "sprint_multiplier", "engage_radius", "engage_cost",
		"hustle_bonus"]
	var tuned: Array[String] = []
	for k in keys:
		tuned.append("%s=%s" % [k, s.tune(k)])
	print("TUNING %s" % " ".join(tuned))
	_units(s)
	_dump_score(s)
	_dump_choice(s, "close")
	quit(0)
