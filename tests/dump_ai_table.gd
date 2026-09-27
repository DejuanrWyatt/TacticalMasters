# Dumps what the computer player decides, for the Unreal port to be measured
# against. The port is a transcription, not a rewrite, so the only way to know
# it still agrees is to ask this game the same questions and compare.
#
#   godot --headless --script res://tests/dump_ai_table.gd > GodotAITable.txt
#
# The file goes in the Unreal project's Tests/ folder. Regenerate it whenever
# the way the computer chooses where to stand changes, or the C++ test will
# rightly start failing.
#
# Four states, because one is not enough. The opening has nobody in sight and
# only exercises walking at the enemy's corner. "contact" puts the two sides in
# view of each other over ground of three heights with two units hurt, so
# backing away and high ground count. "hazards" lays burning and healing ground
# over the whole map, because Highlands has none. "springs" lays healing ground
# only, on every other tile, which is the only way the extra value a hurt unit
# puts on it ever changes the spot it picks.
extends SceneTree

const GameState = preload("res://scripts/core/game_state.gd")
const MapData = preload("res://scripts/core/map_data.gd")
const AIPlayer = preload("res://scripts/ai/ai_player.gd")

var _ai := AIPlayer.new("hard")

func _dump(s: GameState, name: String) -> void:
	print("SCENARIO %s" % name)
	print("UNITS")
	for u in s.units:
		print("  %d %s team=%d sight=%d maxhp=%d pos=%.2f,%.2f hp=%d" % [
			u.id, u.job, u.team, u.stat("sight"), u.max_hp(), u.pos.x, u.pos.y, u.hp])
	print("SIGHT")
	for u in s.units:
		var seen: Array[String] = []
		for e in s.units:
			if e.team != u.team and s.can_see(u.team, e.pos):
				seen.append(str(e.id))
		print("  %d %s" % [u.id, ",".join(seen) if seen.size() > 0 else "-"])
	print("SPOTS")
	for u in s.units:
		for sprint in [false, true]:
			var reach: Dictionary = s.reachable_nodes(u, sprint)
			var app: Vector2 = _ai._approach_spot(s, u, reach)
			var ret: Vector2 = _ai._retreat_spot(s, u, reach)
			print("  %d %s approach=%.2f,%.2f retreat=%.2f,%.2f" % [
				u.id, "sprint" if sprint else "walk", app.x, app.y, ret.x, ret.y])

## Packs the units into the middle of the map so the two sides can see each
## other, which is the state most of a battle is actually in.
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
				u.pos = spot
				taken.append(spot)
				break

## Lays ground down and writes out the tiles, so the port lays the same.
func _lay(s: GameState, kinds: Array[int]) -> void:
	var laid: Array[String] = []
	for ty in s.tiles_y:
		for tx in s.tiles_x:
			var kind: int = kinds[(tx + ty) % kinds.size()]
			s.hazards[ty * s.tiles_x + tx] = kind
			laid.append("%d,%d=%d" % [tx, ty, kind])
	print("HAZARDS %s" % " ".join(laid))

func _initialize() -> void:
	await process_frame
	var s := GameState.new()
	s.setup(MapData.highlands(), {}, 12345)
	print("TUNING sight_multiplier=%s hazard_percent=%s" % [
		s.tune("sight_multiplier"), s.tune("hazard_percent")])
	print("SPAWNS %.2f,%.2f %.2f,%.2f" % [
		s.spawn_points[0].x, s.spawn_points[0].y, s.spawn_points[1].x, s.spawn_points[1].y])
	_dump(s, "opening")

	_gather(s)
	# One hurt enough to want to back off, and one just the wrong side of the
	# line where a unit starts valuing healing ground, which is what pins where
	# that line is rather than merely that there is one.
	s.units[1].hp = int(s.units[1].max_hp() * 0.2)
	s.units[5].hp = int(s.units[5].max_hp() * 0.55)
	_dump(s, "contact")

	_lay(s, [-1, 1])
	_dump(s, "hazards")

	# Healing ground with nothing to weigh it against but plain ground, which is
	# what makes the extra value a hurt unit puts on it visible at all.
	_lay(s, [1, 0])
	_dump(s, "springs")
	quit(0)
