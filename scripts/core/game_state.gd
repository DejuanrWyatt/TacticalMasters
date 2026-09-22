extends RefCounted
## The complete rules of a battle: pure data and logic, no rendering.
##
## Space: units stand anywhere on the ground, in meters. Movement follows a
## fine navigation grid (NAV_STEP meters, 8 directions) so paths go around
## water, cliffs and enemies, and a unit may walk up to its Move in meters.
## Ranges, areas and sight are circles measured in meters. The ground is
## made of TILE_SIZE blocks, each with a height level (0 = water).
##
## Statuses (Burn, Regen, Slow, Stun) last a number of the affected unit's own
## turns: they act and count down when its turn comes (see _tick_statuses).
##
## Time: runs in ticks (TICKS_PER_SECOND per second). Every tick, each unit
## that isn't ready fills its Turn Gauge (TG) by its Wits. At TG_MAX it
## becomes READY and its countdown starts (length set by Patience). A ready
## unit may move once and use one ability, in either order, then end its
## turn. If the countdown runs out first, the turn is lost. Any number of
## units, from both teams, can be ready at the same time.
##
## Targeting: any ability (except self abilities) can be aimed at a unit or
## at the ground. Aimed at the ground, it hits whoever is there when it
## takes effect; single-target abilities hit the one unit closest to the
## point.
##
## Casting: abilities with a cast time don't take effect right away; the
## ability goes off when the cast finishes. A unit may move before it starts
## casting, but not after (only instant abilities allow moving afterwards).
## If the turn ends first, the cast carries on and the unit's TG doesn't fill
## until it's done. Aimed at a unit ("follow"),
## it tracks that unit; aimed at the ground, it lands on that spot, so it can
## be placed where an enemy is expected to walk, and targets can walk out of
## it. A caster defeated mid-cast loses the spell.
##
## Facing: units face where they last walked or aimed. Hits from the side
## deal SIDE_BONUS damage, from behind BACK_BONUS.
##
## Line of sight: ranged abilities (beyond MELEE_RANGE) and vision need a
## clear line over the terrain, from eye height to target height.
##
## Statuses (Jobs.STATUSES) tick in real time: Burn and Regen change HP every
## second, Slow halves Turn Gauge filling, Stun freezes it and blocks orders.
##
## Knock-out: a unit reduced to 0 HP is knocked out (KO) for KO_SECONDS. It
## can't act and doesn't count as alive, but Raise can revive it until then;
## afterwards it is gone. A team with no living units loses.
##
## Tuning: the main rule numbers (Wits and Patience multipliers, damage and
## healing multipliers, height/flank bonuses, KO time, Ultimate gains, move,
## sight and cast-time multipliers) live in `tuning` (defaults in
## DEFAULT_TUNING) so Developer Tools can adjust them. A "tune" command changes
## them mid-battle; like every command it is recorded, so replays stay exact.
##
## Every change goes through a command dictionary:
##   {"type": "advance", "ticks": n}     time passes
##   {"type": "move", "unit": id, "serial": s, "to": Vector2}
##   {"type": "ability", "unit": id, "serial": s, "slot": 0-3, "target": Vector2,
##    "follow": unit id or -1}      follow = the unit clicked on (-1: the ground)
##   {"type": "end_turn", "unit": id, "serial": s}
##   {"type": "tune", "values": {tuning key: number}}   Developer Tools
## "serial" must match the unit's current serial, so an order for an earlier
## turn of that unit is rejected. There is no randomness, so applying the
## same commands always produces the same game. Online play relies on this.

const Unit = preload("res://scripts/core/unit.gd")
const Jobs = preload("res://scripts/core/jobs.gd")

const TEAM_NAMES := ["Blue", "Red"]

# Space
const TILE_SIZE := 2.0
const NAV_STEP := 0.5
const NODES_PER_TILE := 4
const NAV_DIAGONAL := 0.7071067811865476
const NAV_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
## Closest two units may stand; enemies also block paths this close to them.
const UNIT_SPACING := 0.9
## A unit is hit when its center is within (ability aoe + HIT_RADIUS) of the target point.
const HIT_RADIUS := 0.6
## Largest height difference (in levels) a unit can step up or down.
const JUMP := 2
## Meters per ground height level.
const LEVEL_HEIGHT := 0.7
## Line of sight runs from EYE_HEIGHT above the viewer's ground to
## TARGET_HEIGHT above the target's ground, sampled every LOS_STEP meters.
const EYE_HEIGHT := 1.2
const TARGET_HEIGHT := 1.0
const LOS_STEP := 0.5
## Abilities reaching farther than this need line of sight.
const MELEE_RANGE := 1.8

# Time
const TICKS_PER_SECOND := 10
## A full Turn Gauge. Shown to players as a percentage (see tg_percent).
## (Fine-grained so that Slow's half speed stays a whole number for any Wits.)
const TG_MAX := 4000
## TG gained per tick per point of Wits (Wits 10 fills the gauge in 20 seconds).
const TG_PER_WITS := 2
## Head start at the beginning of a battle, per point of Wits (Wits 10 starts 80% full).
const START_TG_PER_WITS := 320
## TG kept after a turn where the unit only moved or only acted (20%) / did neither (40%).
const TG_KEEP_ONE := 800
const TG_KEEP_NONE := 1600
## Countdown while ready, in seconds = CLOCK_BASE + CLOCK_PER_PATIENCE * Patience.
const CLOCK_BASE := 8.0
const CLOCK_PER_PATIENCE := 2.0
## Largest "advance" a single command may carry.
const MAX_ADVANCE := 50

# Combat
const ULT_MAX := 100
const ULT_PER_TURN := 5
const ULT_PER_ACTION := 20
## Ultimate meter gained when hit, per 1% of max HP lost.
const ULT_FROM_DAMAGE := 0.5
## How much a critical hit multiplies damage by.
const CRIT_BONUS := 1.5
const DAMAGE_SCALE := 1.0
## Final multiplier on all damage (after defense), for overall balance.
const DAMAGE_MULTIPLIER := 0.5
const HEAL_SCALE := 1.5
## Damage bonus per height level above the target (penalty when below), up to 3 levels.
const HEIGHT_BONUS := 0.1
## Damage multipliers for hitting a unit from the side / from behind.
const SIDE_BONUS := 1.1
const BACK_BONUS := 1.25
## Seconds a knocked-out unit stays on the field, revivable.
const KO_SECONDS := 12.0

## Adjustable rule numbers (Developer Tools). Each: default, min, max, step,
## label and what it does. The defaults are the constants above.
const TUNING := {
	"wits_multiplier": [1.0, 0.25, 3.0, 0.05, "Wits multiplier", "How fast Turn Gauges fill (x Wits)."],
	"clock_base": [CLOCK_BASE, 2.0, 30.0, 0.5, "Countdown base (s)", "Seconds every READY unit gets, before Patience."],
	"patience_multiplier": [CLOCK_PER_PATIENCE, 0.0, 6.0, 0.25, "Patience multiplier (s)", "Extra countdown seconds per point of Patience."],
	"damage_multiplier": [DAMAGE_MULTIPLIER, 0.1, 2.0, 0.05, "Damage multiplier", "Final multiplier on all damage (after defense)."],
	"heal_multiplier": [1.0, 0.1, 3.0, 0.05, "Healing multiplier", "Multiplier on all healing."],
	"height_bonus": [HEIGHT_BONUS, 0.0, 0.5, 0.01, "Height bonus per level", "Damage bonus per level above the target (penalty below)."],
	"side_bonus": [SIDE_BONUS, 1.0, 2.0, 0.05, "Side attack multiplier", "Damage multiplier for hits from the side."],
	"back_bonus": [BACK_BONUS, 1.0, 3.0, 0.05, "Back attack multiplier", "Damage multiplier for hits from behind."],
	"ko_seconds": [KO_SECONDS, 0.0, 60.0, 1.0, "Knock-out time (s)", "How long a knocked-out unit can still be revived."],
	"ult_per_action": [float(ULT_PER_ACTION), 0.0, 100.0, 1.0, "Ultimate per action", "Ultimate meter gained per ability used."],
	"ult_per_turn": [float(ULT_PER_TURN), 0.0, 50.0, 1.0, "Ultimate per turn", "Ultimate meter gained each time a unit becomes READY."],
	"move_multiplier": [1.0, 0.25, 3.0, 0.05, "Move multiplier", "Multiplier on every unit's Move distance."],
	"sight_multiplier": [1.0, 0.25, 3.0, 0.05, "Sight multiplier", "Multiplier on every unit's Sight radius."],
	"cast_time_multiplier": [1.0, 0.0, 3.0, 0.05, "Cast time multiplier", "Multiplier on every ability's cast time."],
	"crit_multiplier": [CRIT_BONUS, 1.0, 3.0, 0.05, "Critical hit multiplier", "What a critical hit multiplies damage by."],
	"evade_multiplier": [1.0, 0.0, 3.0, 0.05, "Evasion multiplier", "Multiplier on every unit's A-Eva and M-Eva."],
	"crit_chance_multiplier": [1.0, 0.0, 3.0, 0.05, "Crit chance multiplier", "Multiplier on every unit's Crit chance."],
}

var tiles_x := 0
var tiles_y := 0
var nav_x := 0
var nav_y := 0
## Height level per tile; 0 is water.
var heights: Array[int] = []
## Height level per navigation node (y * nav_x + x), precomputed for pathfinding.
var _nav_levels := PackedInt32Array()
var units: Array[Unit] = []
var spawn_points: Array[Vector2] = []
var tick := 0
var winner := -1
## Evasion and critical hits are rolled with this, so a battle plays out the
## same for both players online and in a replay: it is seeded at setup, only
## rolled while applying a command, and copied by snapshot().
var rng := RandomNumberGenerator.new()
var seed_value := 0
## Current rule numbers (see TUNING); missing keys use the defaults.
var tuning := {}


## A copy the computer can think on in a background thread while the live
## battle keeps running. Terrain data is shared (it never changes); units are
## copied. The distance cache is shared too: only the computer uses it, and
## it thinks about one order at a time.
func snapshot():
	var s = get_script().new()
	s.tiles_x = tiles_x
	s.tiles_y = tiles_y
	s.nav_x = nav_x
	s.nav_y = nav_y
	s.heights = heights
	s._nav_levels = _nav_levels
	s.spawn_points = spawn_points
	s.tick = tick
	s.winner = winner
	s.tuning = tuning.duplicate()
	s.seed_value = seed_value
	s.rng.seed = rng.seed
	s.rng.state = rng.state
	s._field_cache = _field_cache
	for u in units:
		s.units.append(u.copy())
	return s


## Default rule numbers as a dictionary.
static func default_tuning() -> Dictionary:
	var out := {}
	for key in TUNING:
		out[key] = TUNING[key][0]
	return out


## A tuning value (current, or the default if unset).
func tune(key: String) -> float:
	return float(tuning.get(key, TUNING[key][0]))


## Keeps only known keys, clamped to their allowed range.
static func clean_tuning(values: Dictionary) -> Dictionary:
	var out := {}
	for key in values:
		if TUNING.has(key) and (values[key] is float or values[key] is int):
			out[key] = clampf(float(values[key]), TUNING[key][1], TUNING[key][2])
	return out


func setup(map: Dictionary, p_tuning := {}, p_seed := 0) -> void:
	seed_value = p_seed
	rng.seed = p_seed  # this also resets the sequence
	tuning = default_tuning()
	tuning.merge(clean_tuning(p_tuning), true)
	var rows: Array = map["rows"]
	tiles_y = rows.size()
	tiles_x = (rows[0] as String).length()
	nav_x = tiles_x * NODES_PER_TILE
	nav_y = tiles_y * NODES_PER_TILE
	heights.clear()
	for row in rows:
		for ch in row:
			heights.append(0 if ch == "~" else ch.to_int())
	_nav_levels.resize(nav_x * nav_y)
	for y in nav_y:
		for x in nav_x:
			_nav_levels[y * nav_x + x] = node_level(Vector2i(x, y))
	units.clear()
	for entry in map["units"]:
		var u := Unit.new(units.size(), entry[0], entry[1], entry[2])
		u.tg = mini(TG_MAX - 1, u.stat("wits") * START_TG_PER_WITS)
		u.facing = (size_meters() * 0.5 - u.pos).normalized()
		units.append(u)
	spawn_points.assign(map["spawn_points"])


# --- Ground ----------------------------------------------------------------

func size_meters() -> Vector2:
	return Vector2(tiles_x, tiles_y) * TILE_SIZE


func tile_in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < tiles_x and t.y < tiles_y


func tile_level(t: Vector2i) -> int:
	return heights[t.y * tiles_x + t.x]


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.y / TILE_SIZE))


func in_bounds(p: Vector2) -> bool:
	return tile_in_bounds(tile_of(p))


## Height level of the ground at a point (0 = water).
func level_at(p: Vector2) -> int:
	return tile_level(tile_of(p))


func is_water(p: Vector2) -> bool:
	return level_at(p) == 0


## Height of the ground surface in meters (water counts as 0).
func ground_height(p: Vector2) -> float:
	return level_at(p) * LEVEL_HEIGHT


## Whether terrain leaves a clear line from a viewer at `a` to a target at `b`.
func has_line_of_sight(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	if d <= LOS_STEP * 2.0:
		return true
	var from_h := ground_height(a) + EYE_HEIGHT
	var to_h := ground_height(b) + TARGET_HEIGHT
	var steps := int(d / LOS_STEP)
	for i in range(1, steps):
		var t := float(i) / steps
		if ground_height(a.lerp(b, t)) > lerpf(from_h, to_h, t):
			return false
	return true


## Whether an ability needs line of sight (ranged, not centered on the caster).
static func needs_line_of_sight(ab: Dictionary) -> bool:
	return ab.max_range > MELEE_RANGE


# --- Units -----------------------------------------------------------------

func get_unit(id: int) -> Unit:
	if id >= 0 and id < units.size():
		return units[id]
	return null


func team_units(team: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and u.team == team:
			out.append(u)
	return out


## Ready units, of one team or (team -1) of both.
func ready_units(team := -1) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and u.ready and (team == -1 or u.team == team):
			out.append(u)
	return out


## A number that sums up the whole battle: both players should always have
## the same one at the same tick (used online to catch the games drifting).
func checksum() -> int:
	var parts := [tick, winner]
	for u in units:
		parts.append("%d:%s:%d:%d:%d:%d:%s:%s" % [u.id, u.pos, u.hp, u.tg, u.serial, u.ult,
			u.statuses, u.buffs])
	return str(parts).hash()


## READY units that can take orders now (not stunned).
func orderable_units(team := -1) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in ready_units(team):
		if not u.is_stunned():
			out.append(u)
	return out


## Living unit whose center is within `radius` of the point, closest first.
func unit_near(p: Vector2, radius: float) -> Unit:
	var best: Unit = null
	for u in units:
		if u.is_alive() and u.pos.distance_to(p) <= radius and (best == null or u.pos.distance_to(p) < best.pos.distance_to(p)):
			best = u
	return best


# --- Navigation ------------------------------------------------------------

func node_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / NAV_STEP), floori(p.y / NAV_STEP))


func node_pos(n: Vector2i) -> Vector2:
	return Vector2((n.x + 0.5) * NAV_STEP, (n.y + 0.5) * NAV_STEP)


## The navigation node center closest to a point.
func snap(p: Vector2) -> Vector2:
	return node_pos(node_of(p))


func node_level(n: Vector2i) -> int:
	return tile_level(Vector2i(floori(float(n.x) / NODES_PER_TILE), floori(float(n.y) / NODES_PER_TILE)))


func node_walkable(n: Vector2i) -> bool:
	return n.x >= 0 and n.y >= 0 and n.x < nav_x and n.y < nav_y and node_level(n) > 0


## Nodes the unit can end its move on, mapped to the meters walked.
## Allies can be passed through but not stood on; enemies block.
func reachable_nodes(unit: Unit) -> Dictionary:
	var costs: Dictionary = _dijkstra([node_of(unit.pos)], move_of(unit), unit.team).cost
	for n in costs.keys():
		var p := node_pos(n)
		for other in units:
			if other != unit and other.is_alive() and other.pos.distance_to(p) < UNIT_SPACING:
				costs.erase(n)
				break
	return costs


## Walking path from the unit to a node (both ends included), or [] if none.
func path_to(unit: Unit, to: Vector2i) -> Array[Vector2]:
	var result := _dijkstra([node_of(unit.pos)], move_of(unit), unit.team)
	var path: Array[Vector2] = []
	if not result.cost.has(to):
		return path
	var n := to
	while true:
		path.push_front(node_pos(n))
		if not result.parent.has(n):
			break
		n = result.parent[n]
	return path


## Walking distance in meters from `goal` to every node (ignoring units), as
## an array indexed by nav_index(). Terrain never changes, so results are
## cached per goal node: the computer asks for these constantly.
func distance_from(goal: Vector2) -> PackedFloat64Array:
	var key := nav_index(node_of(goal))
	if not _field_cache.has(key):
		if _field_cache.size() >= 256:
			_field_cache.clear()
		var starts: Array[Vector2i] = [node_of(goal)]
		_run_dijkstra(starts, INF, -1)
		_field_cache[key] = _cost.duplicate()
	return _field_cache[key]


## Walking distance from the nearest of several goals to node `n` (INF if unreachable).
func distance_to_nearest(goals: Array[Vector2], n: Vector2i) -> float:
	var best := INF
	var i := nav_index(n)
	for g in goals:
		best = minf(best, distance_from(g)[i])
	return best


func nav_index(n: Vector2i) -> int:
	return n.y * nav_x + n.x


## Shortest paths over the navigation grid. Units of teams other than
## `team` block nodes near them; team -1 ignores units.
## Returns {"cost": {node: meters}, "parent": {node: previous node}}.
##
## Runs on flat arrays indexed by node (y * nav_x + x) for speed: the
## computer calls this several times per decision, so it must stay fast.
func _dijkstra(starts: Array[Vector2i], max_cost: float, team: int) -> Dictionary:
	_run_dijkstra(starts, max_cost, team)
	var cost_out := {}
	var parent_out := {}
	for i in _cost.size():
		if _cost[i] < INF:
			@warning_ignore("integer_division")
			var n := Vector2i(i % nav_x, i / nav_x)
			cost_out[n] = _cost[i]
			if _parent[i] >= 0:
				@warning_ignore("integer_division")
				parent_out[n] = Vector2i(_parent[i] % nav_x, _parent[i] / nav_x)
	return {"cost": cost_out, "parent": parent_out}


# Results of the last _run_dijkstra, indexed by node.
var _cost := PackedFloat64Array()
var _parent := PackedInt32Array()
## Goal node index -> distance array (see distance_from).
var _field_cache := {}


## The search itself; fills _cost and _parent.
func _run_dijkstra(starts: Array[Vector2i], max_cost: float, team: int) -> void:
	var count := nav_x * nav_y
	var blocked := PackedByteArray()
	blocked.resize(count)
	if team >= 0:
		for u in units:
			if u.is_alive() and u.team != team:
				_mark_blocked(u.pos, UNIT_SPACING, blocked)
	_cost.resize(count)
	_cost.fill(INF)
	_parent.resize(count)
	_parent.fill(-1)
	_heap_cost.clear()
	_heap_node.clear()
	for s in starts:
		if s.x >= 0 and s.y >= 0 and s.x < nav_x and s.y < nav_y:
			var si := s.y * nav_x + s.x
			_cost[si] = 0.0
			_heap_push(0.0, si)
	var diagonal := NAV_STEP * NAV_DIAGONAL * 2.0
	while not _heap_node.is_empty():
		var c := _heap_cost[0]
		var i := _heap_node[0]
		_heap_pop()
		if c > _cost[i]:
			continue
		var x := i % nav_x
		@warning_ignore("integer_division")
		var y := i / nav_x
		var level := _nav_levels[i]
		for k in 8:
			var dx: int = NAV_DIRS[k].x
			var dy: int = NAV_DIRS[k].y
			var mx := x + dx
			var my := y + dy
			if mx < 0 or my < 0 or mx >= nav_x or my >= nav_y:
				continue
			var m := my * nav_x + mx
			var m_level := _nav_levels[m]
			if m_level <= 0 or blocked[m] == 1 or absi(m_level - level) > JUMP:
				continue
			var step := NAV_STEP
			if dx != 0 and dy != 0:
				# No cutting corners past water, cliffs or enemies.
				var a := y * nav_x + mx
				var b := my * nav_x + x
				var a_level := _nav_levels[a]
				var b_level := _nav_levels[b]
				if a_level <= 0 or b_level <= 0 or blocked[a] == 1 or blocked[b] == 1:
					continue
				if absi(a_level - level) > JUMP or absi(b_level - level) > JUMP:
					continue
				step = diagonal
			var nc := c + step
			if nc > max_cost + 0.001 or nc >= _cost[m]:
				continue
			_cost[m] = nc
			_parent[m] = i
			_heap_push(nc, m)


func _mark_blocked(p: Vector2, radius: float, blocked: PackedByteArray) -> void:
	var center := node_of(p)
	var r := ceili(radius / NAV_STEP)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var n := center + Vector2i(dx, dy)
			if n.x >= 0 and n.y >= 0 and n.x < nav_x and n.y < nav_y and node_pos(n).distance_to(p) < radius:
				blocked[n.y * nav_x + n.x] = 1


# Binary min-heap of (cost, node index) in two parallel arrays, reused
# between searches to avoid allocations.
var _heap_cost := PackedFloat64Array()
var _heap_node := PackedInt32Array()


func _heap_push(c: float, n: int) -> void:
	_heap_cost.append(c)
	_heap_node.append(n)
	var i := _heap_cost.size() - 1
	while i > 0:
		var up := (i - 1) >> 1
		if _heap_cost[up] <= _heap_cost[i]:
			break
		_heap_swap(i, up)
		i = up


func _heap_pop() -> void:
	var last := _heap_cost.size() - 1
	_heap_swap(0, last)
	_heap_cost.resize(last)
	_heap_node.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < last and _heap_cost[l] < _heap_cost[smallest]:
			smallest = l
		if r < last and _heap_cost[r] < _heap_cost[smallest]:
			smallest = r
		if smallest == i:
			break
		_heap_swap(i, smallest)
		i = smallest


func _heap_swap(a: int, b: int) -> void:
	var c := _heap_cost[a]
	_heap_cost[a] = _heap_cost[b]
	_heap_cost[b] = c
	var n := _heap_node[a]
	_heap_node[a] = _heap_node[b]
	_heap_node[b] = n


# --- Fog of war ------------------------------------------------------------

## Whether any unit of `team` (other than `exclude_id`) can see the point.
func can_see(team: int, p: Vector2, exclude_id := -1) -> bool:
	for u in units:
		if u.is_alive() and u.team == team and u.id != exclude_id and u.pos.distance_to(p) <= sight_of(u) \
				and has_line_of_sight(u.pos, p):
			return true
	return false


## Set of ground tiles the team can see (for drawing the fog).
func visible_tiles(team: int) -> Dictionary:
	var out := {}
	for y in tiles_y:
		for x in tiles_x:
			var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * TILE_SIZE
			for u in units:
				if u.is_alive() and u.team == team and u.pos.distance_to(center) <= sight_of(u) + TILE_SIZE * 0.5 \
						and has_line_of_sight(u.pos, center):
					out[Vector2i(x, y)] = true
					break
	return out


# --- Time ------------------------------------------------------------------

## Turn Gauge as a percentage (0-100).
static func tg_percent(u: Unit) -> int:
	@warning_ignore("integer_division")
	return u.tg * 100 / TG_MAX


func clock_ticks(u: Unit) -> int:
	return roundi((tune("clock_base") + tune("patience_multiplier") * u.stat("patience")) * TICKS_PER_SECOND)


## Meters the unit can walk per turn (Move x move multiplier).
func move_of(u: Unit) -> float:
	return u.stat("move") * tune("move_multiplier")


## Vision radius in meters (Sight x sight multiplier).
func sight_of(u: Unit) -> float:
	return u.stat("sight") * tune("sight_multiplier")


func ticks_to_ready(u: Unit) -> int:
	if u.ready:
		return 0
	var cast_ticks: int = u.casting.ticks if u.is_casting() else 0
	var gain := _tg_gain(u)
	if gain <= 0:
		gain = _base_tg_gain(u)  # stunned: estimate as if not
	return cast_ticks + maxi(0, ceili(float(TG_MAX - u.tg) / gain))


## Turn Gauge gained per tick, after Slow / Stun.
func _tg_gain(u: Unit) -> int:
	return roundi(_base_tg_gain(u) * u.tg_factor())


## Turn Gauge per tick before statuses: Wits x TG_PER_WITS x Wits multiplier.
func _base_tg_gain(u: Unit) -> int:
	return maxi(1, roundi(u.stat("wits") * TG_PER_WITS * tune("wits_multiplier")))


## Seconds left to act if ready, seconds until the spell goes off if
## casting, otherwise seconds until ready.
func seconds_left(u: Unit) -> float:
	return float(_ticks_left(u)) / TICKS_PER_SECOND


## Seconds until a unit's pending spell goes off (0 if not casting).
func cast_seconds_left(u: Unit) -> float:
	return float(u.casting.ticks) / TICKS_PER_SECOND if u.is_casting() else 0.0


func _ticks_left(u: Unit) -> int:
	if u.ready:
		return u.clock
	if u.is_casting():
		return u.casting.ticks
	return ticks_to_ready(u)


## Every living unit, ready ones first (least time left first), then the
## rest in order of what happens next to them (a spell going off, or
## becoming ready).
func schedule() -> Array[Unit]:
	var out := team_units(0)
	out.append_array(team_units(1))
	out.sort_custom(_schedule_before)
	return out


func _schedule_before(a: Unit, b: Unit) -> bool:
	if a.ready != b.ready:
		return a.ready
	var ta := _ticks_left(a)
	var tb := _ticks_left(b)
	if ta != tb:
		return ta < tb
	return a.id < b.id


# --- Abilities -------------------------------------------------------------

## "" if the unit may use the ability now, otherwise why not.
func ability_blocked_reason(u: Unit, slot: int) -> String:
	var kind: String = u.ability(slot).get("kind", "active")
	if kind == "passive" or kind == "aura":
		return "%s is always on." % u.ability(slot).name
	if kind == "toggle":
		if u.toggled_turn.get(slot, false):
			return "%s was already switched this turn." % u.ability(slot).name
		return ""
	if slot == 3 and u.ult < ULT_MAX:
		return "The ultimate meter isn't full yet (%d%%)." % u.ult
	if u.cooldowns[slot] > 0:
		return "%s is recharging (%d more turn%s)." % [u.ability(slot).name, u.cooldowns[slot], "" if u.cooldowns[slot] == 1 else "s"]
	return ""


## Whether `target` is a legal point for the ability used from `from`.
func in_ability_range(u: Unit, slot: int, from: Vector2, target: Vector2) -> bool:
	var ab := u.ability(slot)
	if ab.max_range == 0.0:
		return target == from
	var d := from.distance_to(target)
	return d >= ab.min_range and d <= ab.max_range and in_bounds(target)


## The shape an ability covers: "unit", "point", "circle", "self", "line",
## "cone", "global" or "vector" (see Jobs.SHAPES).
static func shape_of(ab: Dictionary) -> String:
	var shape: String = ab.get("shape", "")
	if Jobs.SHAPES.has(shape):
		return shape
	if ab.max_range == 0.0:
		return "self"
	return "circle" if ab.aoe > 0.0 else "unit"


## Whether a unit standing at `t_pos` is inside the ability's shape, used
## from `from` and aimed at `target`.
func in_shape(ab: Dictionary, from: Vector2, target: Vector2, t_pos: Vector2) -> bool:
	match shape_of(ab):
		"global":
			return true
		"line", "vector":
			var along := target - from
			var length := along.length()
			if length < 0.01:
				return t_pos.distance_to(from) <= ab.aoe + HIT_RADIUS
			var dir := along / length
			var travelled := (t_pos - from).dot(dir)
			if travelled < -HIT_RADIUS or travelled > length + HIT_RADIUS:
				return false
			return absf((t_pos - from).cross(dir)) <= maxf(ab.aoe, 0.6) + HIT_RADIUS
		"cone":
			var to_target := target - from
			var to_unit := t_pos - from
			var reach := to_unit.length()
			if reach > ab.max_range + HIT_RADIUS or to_target.length() < 0.01:
				return false
			if reach < 0.01:
				return true
			var spread: float = ab.get("angle", 60.0) * 0.5
			return rad_to_deg(absf(to_unit.angle_to(to_target))) <= spread
	return t_pos.distance_to(target) <= ab.aoe + HIT_RADIUS


## What the ability would do if `u` used it from `from` on `target`:
## [{"unit": Unit, "amount": int}] for every affected unit.
func preview(u: Unit, slot: int, from: Vector2, target: Vector2) -> Array[Dictionary]:
	var ab := u.ability(slot)
	var out: Array[Dictionary] = []
	for t in units:
		if ab.target == "ko_ally":
			if not t.is_ko() or t.team != u.team:
				continue
		elif not t.is_alive() or (t.team != u.team) != (ab.target == "enemy"):
			continue
		var t_pos := from if t == u else t.pos
		if not in_shape(ab, from, target, t_pos):
			continue
		out.append({"unit": t, "amount": _amount(u, ab, from, t, t_pos), "distance": t_pos.distance_to(target),
			"flank": flank_bonus(t, t_pos, from) if ab.effect == "damage" else 1.0})
	if ab.aoe == 0.0 and shape_of(ab) != "global" and out.size() > 1:
		# A single-target ability only hits the unit closest to the point.
		var closest: Dictionary = out[0]
		for hit in out:
			if hit.distance < closest.distance:
				closest = hit
		out = [closest]
	return out


func _amount(u: Unit, ab: Dictionary, from: Vector2, t: Unit, t_pos: Vector2) -> int:
	return _calc(u, ab, from, t, t_pos, false).value


## The damage / healing / revive math. With `explain`, also returns the
## step-by-step calculation as text (for tooltips), using the same numbers.
## Returns {"value": int, "text": String}.
func _calc(u: Unit, ab: Dictionary, from: Vector2, t: Unit, t_pos: Vector2, explain: bool) -> Dictionary:
	# An ability's own power is the damage (or healing) it does; the user's
	# Power stat is added to it.
	var power: float = ab.power + (u.stat("power") if ab.effect != "revive" else 0)
	match ab.effect:
		"damage":
			var def_name := "AttDef" if ab.scale == "att" else "MagDef"
			var def := t.stat("attdef" if ab.scale == "att" else "magdef")
			var levels := clampi(level_at(from) - level_at(t_pos), -3, 3)
			var height := 1.0 + tune("height_bonus") * levels
			var flank := flank_bonus(t, t_pos, from)
			var raw := roundi(power * DAMAGE_SCALE * height * flank)
			var value := maxi(1, roundi((raw - def) * tune("damage_multiplier")))
			if not explain:
				return {"value": value}
			var lines := ["Power %s%s" % [_n(ab.power), " + %d from %s" % [u.stat("power"), u.job_name()] if u.stat("power") > 0 else ""]]
			if levels != 0:
				lines.append("x height %s (%+d level%s)" % [_n(height), levels, "" if absi(levels) == 1 else "s"])
			if flank != 1.0:
				lines.append("x %s %s" % ["from behind" if flank >= tune("back_bonus") else "from the side", _n(flank)])
			lines.append("= %d, - %s %d = %d" % [raw, def_name, def, raw - def])
			lines.append("x damage multiplier %s = %d%s" % [_n(tune("damage_multiplier")), value, " (minimum 1)" if value == 1 else ""])
			lines.append("%s %d%% to evade, %s %d%% to crit (x %s)" % ["A-Eva" if ab.scale == "att" else "M-Eva",
				evade_chance(t, ab), u.job_name(), crit_chance(u), _n(tune("crit_multiplier"))])
			return {"value": value, "text": "\n".join(lines)}
		"heal":
			var full := roundi(power * HEAL_SCALE * tune("heal_multiplier"))
			var missing := t.max_hp() - t.hp
			var value := mini(full, missing)
			if not explain:
				return {"value": value}
			var text := "Power %s%s x %s x heal multiplier %s = %d" % [_n(ab.power),
				" + %d" % u.stat("power") if u.stat("power") > 0 else "", _n(HEAL_SCALE), _n(tune("heal_multiplier")), full]
			if value < full:
				text += "\ncapped at missing HP %d" % missing
			return {"value": value, "text": text}
		"revive":
			var value := maxi(1, roundi(t.max_hp() * ab.power))
			return {"value": value, "text": "Max HP %d x %d%% = %d" % [t.max_hp(), roundi(ab.power * 100), value] if explain else ""}
	return {"value": 0, "text": ""}


static func _n(v: float) -> String:
	return str(snappedf(v, 0.01)).trim_suffix(".0")


## Chance in % that this unit evades the ability (physical abilities are
## evaded with A-Eva, harmful magic with M-Eva; friendly abilities never are).
func evade_chance(t: Unit, ab: Dictionary) -> int:
	if ab.effect != "damage":
		return 0
	var base := t.stat("aeva" if ab.scale == "att" else "meva")
	return clampi(roundi(base * tune("evade_multiplier")), 0, 95)


## Chance in % that this unit's abilities land a critical hit.
func crit_chance(u: Unit) -> int:
	return clampi(roundi(u.stat("crit") * tune("crit_chance_multiplier")), 0, 100)


## Step-by-step calculation of what an ability does to one target.
func explain_hit(u: Unit, slot: int, from: Vector2, t: Unit) -> String:
	var t_pos := from if t == u else t.pos
	return _calc(u, u.ability(slot), from, t, t_pos, true).text


## How the unit's Turn Gauge timing is worked out.
func explain_turn(u: Unit) -> String:
	var gain := _base_tg_gain(u)
	var text := "TG per tick = Wits %d x %d x Wits multiplier %s = %d\n" % [u.stat("wits"), TG_PER_WITS, _n(tune("wits_multiplier")), gain]
	text += "Full gauge %d / %d = %d ticks = %s s between turns" % [TG_MAX, gain, ceili(float(TG_MAX) / gain), _n(ceili(float(TG_MAX) / gain) / float(TICKS_PER_SECOND))]
	if u.tg_factor() != 1.0:
		text += "\nStatuses: x %s" % _n(u.tg_factor())
	return text


## How the READY countdown is worked out.
func explain_countdown(u: Unit) -> String:
	return "Countdown = base %s s + Patience %d x %s s = %s s" % [
		_n(tune("clock_base")), u.stat("patience"), _n(tune("patience_multiplier")), _n(clock_ticks(u) / float(TICKS_PER_SECOND))]


## An ability's cast time in seconds (after the cast time multiplier).
func cast_seconds(ab: Dictionary) -> float:
	return ab.get("cast", 0.0) * tune("cast_time_multiplier")


## What an ability does, with its numbers worked out (ability tooltips).
func explain_ability(u: Unit, slot: int) -> String:
	var ab := u.ability(slot)
	var lines: Array[String] = []
	match ab.effect:
		"damage":
			lines.append("Damage = power %s%s" % [_n(ab.power), " + Power %d" % u.stat("power") if u.stat("power") > 0 else ""])
			lines.append("  x height (%s per level) x side %s / back %s" % [_n(tune("height_bonus")), _n(tune("side_bonus")), _n(tune("back_bonus"))])
			lines.append("  - target's %s, x damage multiplier %s (at least 1)" % ["AttDef" if ab.scale == "att" else "MagDef", _n(tune("damage_multiplier"))])
			lines.append("  target's %s evades it; %d%% chance of a critical hit (x %s)" % [
				"A-Eva" if ab.scale == "att" else "M-Eva", crit_chance(u), _n(tune("crit_multiplier"))])
		"heal":
			lines.append("Heal = power %s%s x %s x heal multiplier %s = %d" % [_n(ab.power),
				" + Power %d" % u.stat("power") if u.stat("power") > 0 else "", _n(HEAL_SCALE), _n(tune("heal_multiplier")),
				roundi((ab.power + u.stat("power")) * HEAL_SCALE * tune("heal_multiplier"))])
		"revive":
			lines.append("Revives with %d%% of max HP" % roundi(ab.power * 100))
	if ab.has("tg"):
		lines.append("Turn Gauge %+d%% = %+d TG (of %d)" % [ab.tg, ab.tg * TG_MAX / 100, TG_MAX])
	for b in ab.get("buffs", []):
		lines.append("%s %+d for %d turn%s" % [b.stat, b.amount, b.turns, "" if b.turns == 1 else "s"])
	if ab.has("status"):
		lines.append("%s for %d turn%s" % [Jobs.STATUSES[ab.status.id].name, ab.status.turns, "" if ab.status.turns == 1 else "s"])
	if ab.cast > 0.0:
		lines.append("Cast %s s x cast time multiplier %s = %s s" % [_n(ab.cast), _n(tune("cast_time_multiplier")), _n(cast_seconds(ab))])
	else:
		lines.append("Instant")
	if ab.cooldown > 0:
		lines.append("Cooldown %d turn%s" % [ab.cooldown, "" if ab.cooldown == 1 else "s"])
	if slot == 3:
		lines.append("Ultimate: needs a full meter (+%d per turn, +%d per ability used, +%s per 1%% of max HP lost)" % [
			roundi(tune("ult_per_turn")), roundi(tune("ult_per_action")), _n(ULT_FROM_DAMAGE)])
	return "
".join(lines)


func explain_move(u: Unit) -> String:
	return "Move %d m x move multiplier %s = %s m" % [u.stat("move"), _n(tune("move_multiplier")), _n(move_of(u))]


func explain_sight(u: Unit) -> String:
	return "Sight %d m x sight multiplier %s = %s m" % [u.stat("sight"), _n(tune("sight_multiplier")), _n(sight_of(u))]


## Damage multiplier for where the attacker stands relative to the target's
## facing: BACK_BONUS from behind, SIDE_BONUS from the side, 1 from the front.
func flank_bonus(t: Unit, t_pos: Vector2, from: Vector2) -> float:
	var to_attacker := from - t_pos
	if to_attacker.length() < 0.01:
		return 1.0
	var dot := t.facing.dot(to_attacker.normalized())
	if dot < -0.5:
		return tune("back_bonus")
	if dot < 0.5:
		return tune("side_bonus")
	return 1.0


# --- Commands --------------------------------------------------------------

## Returns "" if the command is legal right now, otherwise the reason it isn't.
func validate(cmd: Dictionary) -> String:
	if winner != -1:
		return "The battle is over."
	var type = cmd.get("type", "")
	if type == "advance":
		var ticks = cmd.get("ticks")
		return "" if ticks is int and ticks >= 1 and ticks <= MAX_ADVANCE else "Bad time step."
	if type == "tune":
		var values = cmd.get("values")
		return "" if values is Dictionary and clean_tuning(values).size() == values.size() else "Bad tuning values."
	var id = cmd.get("unit")
	var u: Unit = get_unit(id) if id is int else null
	if u == null or not u.is_alive():
		return "No such unit."
	if not u.ready:
		return "%s isn't ready." % u.job_name()
	if u.is_stunned():
		return "%s is stunned." % u.job_name()
	var serial = cmd.get("serial")
	if not (serial is int) or serial != u.serial:
		return "That order was for an earlier turn."
	match type:
		"move":
			if u.moved:
				return "Already moved this turn."
			if u.is_casting():
				return "Can't move while casting."
			var to = cmd.get("to")
			if not (to is Vector2) or to == u.pos or to != snap(to) or not reachable_nodes(u).has(node_of(to)):
				return "Can't move there."
			return ""
		"ability":
			if u.acted:
				return "Already used an ability this turn."
			var slot = cmd.get("slot")
			if not (slot is int) or slot < 0 or slot > 3:
				return "No such ability."
			var reason := ability_blocked_reason(u, slot)
			if reason != "":
				return reason
			var target = cmd.get("target")
			if not (target is Vector2) or not in_ability_range(u, slot, u.pos, target):
				return "That target is out of range."
			if not can_see(u.team, target):
				return "You can't see that spot."
			var ab := u.ability(slot)
			if needs_line_of_sight(ab) and not has_line_of_sight(u.pos, target):
				return "No line of sight."
			var follow = cmd.get("follow", -1)
			if not (follow is int):
				return "Bad target."
			if follow != -1:
				var t := get_unit(follow)
				var ok_state := t != null and (t.is_ko() if ab.target == "ko_ally" else t.is_alive())
				if not ok_state or t.pos.distance_to(target) > HIT_RADIUS:
					return "Bad target."
			return ""
		"end_turn":
			return ""
	return "Unknown command."


## Applies a command that already passed validate(). Returns
## {"logs": [String], "events": [{"pos": Vector2, "text", "color", "impact": bool}],
##  "became_ready": [unit id], "turn_ended": [unit id],
##  "cast_started": [unit id],
##  "resolved": [{"unit": id, "slot": int, "target": Vector2, "hits": [unit id], "amounts": [int]}],
##  "knocked_out": [unit id], "revived": [unit id], "gone": [unit id]}.
## Events with "impact" come from an ability landing.
func apply(cmd: Dictionary) -> Dictionary:
	var result := {"logs": [], "events": [], "became_ready": [], "turn_ended": [], "cast_started": [], "resolved": [],
		"knocked_out": [], "revived": [], "gone": [], "timed_out": []}
	match cmd["type"]:
		"advance":
			for i in cmd["ticks"]:
				_tick(result)
		"move":
			var u := get_unit(cmd["unit"])
			var to: Vector2 = cmd["to"]
			# Face the direction of the last step of the walk.
			var path := path_to(u, node_of(to))
			var step := (path[-1] - path[-2]) if path.size() >= 2 else (to - u.pos)
			if step.length() > 0.001:
				u.facing = step.normalized()
			u.pos = to
			u.moved = true
		"ability":
			_use_ability(get_unit(cmd["unit"]), cmd["slot"], cmd["target"], cmd.get("follow", -1), result)
		"end_turn":
			_end_turn(get_unit(cmd["unit"]), false, result)
		"tune":
			tuning.merge(clean_tuning(cmd["values"]), true)
			result.logs.append("Developer Tools: rule numbers updated.")
	return result


func _tick(result: Dictionary) -> void:
	if winner != -1:
		return
	tick += 1
	for u in units:
		if u.is_ko():
			u.ko_ticks -= 1
			if u.ko_ticks <= 0:
				result.gone.append(u.id)
				result.logs.append("%s %s is gone." % [TEAM_NAMES[u.team], u.job_name()])
			continue
		if not u.is_alive():
			continue
		var was_casting := u.is_casting()
		if was_casting:
			u.casting.ticks -= 1
			if u.casting.ticks <= 0:
				var cast := u.casting
				u.casting = {}
				var target: Vector2 = cast.target
				var followed := get_unit(cast.target_unit)
				if followed != null and followed.is_alive():
					target = followed.pos
				_resolve_ability(u, cast.slot, target, result)
				if winner != -1:
					return
				if not u.is_alive():
					continue
		if u.ready:
			u.clock -= 1
			if u.clock <= 0:
				_end_turn(u, true, result)
		elif not was_casting:
			u.tg = mini(TG_MAX, u.tg + _tg_gain(u))
			if u.tg >= TG_MAX:
				_become_ready(u, result)


## The unit's turn has come: its statuses act (Burn and Regen change its HP)
## and then count down by one; the ones that run out are removed.
func _tick_statuses(u: Unit, result: Dictionary) -> void:
	if u.statuses.is_empty():
		return
	var kept: Array[Dictionary] = []
	for s in u.statuses:
		var info: Dictionary = Jobs.STATUSES[s.id]
		var per_turn: float = info.get("per_turn", 0.0)
		if per_turn != 0.0 and u.is_alive():
			var amount := maxi(1, roundi(u.max_hp() * absf(per_turn)))
			if per_turn < 0.0:
				u.hp = maxi(0, u.hp - amount)
				result.events.append({"pos": u.pos, "text": "-%d" % amount, "color": info.color})
				result.logs.append("%s %s takes %d from %s." % [TEAM_NAMES[u.team], u.job_name(), amount, info.name])
				if not u.is_alive():
					_knock_out(u, "%s %s" % [TEAM_NAMES[u.team], u.job_name()], result)
					_check_winner()
					return
			else:
				var healed := mini(amount, u.max_hp() - u.hp)
				if healed > 0:
					u.hp += healed
					result.events.append({"pos": u.pos, "text": "+%d" % healed, "color": info.color})
		s.turns -= 1
		if s.turns > 0:
			kept.append(s)
		else:
			result.logs.append("%s %s: %s wears off." % [TEAM_NAMES[u.team], u.job_name(), info.name])
	u.statuses = kept


## Auras of every living unit whose side this one is on (or against) reach it
## when its turn comes: their buffs are refreshed for the turn.
func _apply_aura_buffs(u: Unit, source: Unit, ab: Dictionary) -> void:
	for b in ab.get("buffs", []):
		var found := false
		for existing in u.buffs:
			if existing.stat == b.stat and existing.get("aura", "") == ab.name:
				existing.turns = 2
				found = true
		if not found:
			var copy: Dictionary = b.duplicate()
			copy.turns = 2
			copy["aura"] = ab.name
			u.buffs.append(copy)


func _apply_auras(u: Unit, result: Dictionary) -> void:
	for source in units:
		if not source.is_alive():
			continue
		for slot in 4:
			var ab := source.ability(slot)
			if ab.get("kind", "active") != "aura":
				continue
			var wants_enemy: bool = ab.get("target", "ally") == "enemy"
			if (source.team != u.team) != wants_enemy:
				continue
			if source.pos.distance_to(u.pos) > maxf(ab.aoe, 1.0):
				continue
			_apply_aura_buffs(u, source, ab)
			if ab.has("status"):
				_add_status(u, ab.status.id, ab.status.turns)


## Puts (or refreshes) a status on a unit for that many of its own turns.
func _add_status(u: Unit, status_id: String, turns: int) -> void:
	for s in u.statuses:
		if s.id == status_id:
			s.turns = maxi(s.turns, turns)
			return
	u.statuses.append({"id": status_id, "turns": turns})


## A unit drops to 0 HP: it's knocked out and can be revived for KO_SECONDS.
func _knock_out(t: Unit, who: String, result: Dictionary) -> void:
	t.hp = 0
	t.ko_ticks = roundi(tune("ko_seconds") * TICKS_PER_SECOND)
	if t.ko_ticks <= 0:
		result.gone.append(t.id)
	t.ready = false
	t.clock = 0
	t.moved = false
	t.acted = false
	t.statuses.clear()
	if t.is_casting():
		result.logs.append("%s's %s fizzles." % [who, t.casting.name])
		t.casting = {}
	result.knocked_out.append(t.id)
	result.logs.append("%s is knocked out! (%ds to revive)" % [who, roundi(tune("ko_seconds"))])


func _check_winner() -> void:
	for team in 2:
		if team_units(team).is_empty():
			winner = 1 - team
			return


func _become_ready(u: Unit, result: Dictionary) -> void:
	# Statuses act on the unit's own turn, then count down (Burn can knock it
	# out before it acts).
	var stunned := u.is_stunned()
	_tick_statuses(u, result)
	if not u.is_alive():
		return
	u.ready = true
	u.tg = TG_MAX
	u.serial += 1
	u.clock = clock_ticks(u)
	u.moved = false
	u.acted = false
	u.toggled_turn.clear()
	u.ult = mini(ULT_MAX, u.ult + roundi(tune("ult_per_turn")))
	for i in u.cooldowns.size():
		u.cooldowns[i] = maxi(0, u.cooldowns[i] - 1)
	var kept: Array[Dictionary] = []
	for b in u.buffs:
		b.turns -= 1
		if b.turns > 0:
			kept.append(b)
	u.buffs = kept
	_apply_auras(u, result)
	# Channeled: it goes off again and the unit's turn is spent on it.
	if u.is_channeling():
		u.channeling.turns -= 1
		result.became_ready.append(u.id)
		_resolve_ability(u, u.channeling.slot, u.channeling.target, result)
		if u.channeling.turns <= 0:
			result.logs.append("%s %s finishes channeling." % [TEAM_NAMES[u.team], u.job_name()])
			u.channeling = {}
		if u.is_alive():
			_end_turn(u, false, result)
		return
	# Stunned: the turn it just earned is lost (and the Stun counted down).
	if stunned:
		result.logs.append("%s %s loses its turn: %s." % [TEAM_NAMES[u.team], u.job_name(), Jobs.STATUSES.stun.name])
		result.events.append({"pos": u.pos, "text": Jobs.STATUSES.stun.tag, "color": Jobs.STATUSES.stun.color})
		_end_turn(u, true, result)
		return
	result.became_ready.append(u.id)
	result.events.append({"pos": u.pos, "text": "READY", "color": Color(1, 0.85, 0.3)})


func _end_turn(u: Unit, timed_out: bool, result: Dictionary) -> void:
	# A turn lost to the countdown stops a channel.
	if timed_out and u.is_channeling():
		u.channeling = {}
	if timed_out:
		u.tg = 0
		result.logs.append("%s %s ran out of time!" % [TEAM_NAMES[u.team], u.job_name()])
		result.timed_out.append(u.id)
	elif u.moved and u.acted:
		u.tg = 0
	elif u.moved or u.acted:
		u.tg = TG_KEEP_ONE
	else:
		u.tg = TG_KEEP_NONE
	u.ready = false
	u.clock = 0
	u.moved = false
	u.acted = false
	result.turn_ended.append(u.id)


## Commits to an ability: pays its cost, then resolves it now (instant; the
## unit may still move afterwards) or starts casting it (no more moving).
func _use_ability(u: Unit, slot: int, target: Vector2, follow: int, result: Dictionary) -> void:
	var ab := u.ability(slot)
	# A toggle just switches: no cast, no cooldown, and the unit can still act.
	# Once per turn, so it can't be flipped back and forth.
	if ab.get("kind", "active") == "toggle":
		var on: bool = not u.toggled.get(slot, false)
		u.toggled[slot] = on
		u.toggled_turn[slot] = true
		result.logs.append("%s %s switches %s %s." % [TEAM_NAMES[u.team], u.job_name(), ab.name, "on" if on else "off"])
		result.events.append({"pos": u.pos, "text": "%s %s" % [ab.name, "ON" if on else "OFF"],
			"color": Color(0.6, 0.9, 1.0) if on else Color(0.7, 0.7, 0.75)})
		return
	if slot == 3:
		u.ult = 0
	else:
		u.ult = mini(ULT_MAX, u.ult + roundi(tune("ult_per_action")))
	u.cooldowns[slot] = ab.cooldown + 1 if ab.cooldown > 0 else 0
	u.acted = true
	if target.distance_to(u.pos) > 0.01:
		u.facing = (target - u.pos).normalized()
	# Channeled: it goes off now and again on each of the next turns, and the
	# unit's turn ends at once (it is busy channeling).
	if ab.get("kind", "active") == "channeled":
		u.channeling = {"slot": slot, "target": target, "turns": maxi(1, int(ab.get("channel", 2)))}
		result.logs.append("%s %s starts channeling %s (%d more turn%s)." % [TEAM_NAMES[u.team], u.job_name(), ab.name,
			u.channeling.turns, "" if u.channeling.turns == 1 else "s"])
		_resolve_ability(u, slot, target, result)
		if u.is_alive():
			_end_turn(u, false, result)
		return
	var cast_ticks := roundi(cast_seconds(ab) * TICKS_PER_SECOND)
	if cast_ticks <= 0:
		_resolve_ability(u, slot, target, result)
		return
	# Aimed at a unit: the spell tracks it. Aimed at the ground: it stays put.
	u.casting = {"slot": slot, "name": ab.name, "target": target, "target_unit": follow,
		"ticks": cast_ticks, "total": cast_ticks}
	result.cast_started.append(u.id)
	result.logs.append("%s %s begins casting %s (%.1fs)" % [TEAM_NAMES[u.team], u.job_name(), ab.name, ab.cast])


## The ability takes effect.
func _resolve_ability(u: Unit, slot: int, target: Vector2, result: Dictionary) -> void:
	var ab := u.ability(slot)
	var hits := preview(u, slot, u.pos, target)
	# A "vector" ability carries the caster to the far end of the line.
	if shape_of(ab) == "vector" and node_walkable(node_of(target)) and unit_near(target, UNIT_SPACING) in [null, u]:
		u.pos = snap(target)
		result.logs.append("%s %s dashes." % [TEAM_NAMES[u.team], u.job_name()])
	var parts: Array[String] = []
	var resolved := {"unit": u.id, "slot": slot, "target": target, "hits": [], "amounts": []}
	result.resolved.append(resolved)
	for hit in hits:
		var t: Unit = hit.unit
		var amount: int = hit.amount
		var who := "%s %s" % [TEAM_NAMES[t.team], t.job_name()]
		# Damage is rolled against the target's evasion and the user's Crit.
		# (Only here, while the command is applied, so both players online and
		# a replay roll exactly the same.)
		var evaded := false
		var critical := false
		if ab.effect == "damage":
			evaded = rng.randi_range(1, 100) <= evade_chance(t, ab)
			if not evaded:
				critical = rng.randi_range(1, 100) <= crit_chance(u)
				if critical:
					amount = maxi(1, roundi(amount * tune("crit_multiplier")))
		if evaded:
			amount = 0
			resolved.hits.append(t.id)
			resolved.amounts.append(0)
			parts.append("%s evades" % who)
			result.events.append({"pos": t.pos, "text": "MISS", "color": Color(0.85, 0.88, 1.0), "impact": true})
			continue
		resolved.hits.append(t.id)
		resolved.amounts.append(amount)
		match ab.effect:
			"damage":
				if critical:
					result.events.append({"pos": t.pos, "text": "CRIT!", "color": Color(1.0, 0.85, 0.3), "impact": true})
				t.hp = maxi(0, t.hp - amount)
				t.ult = mini(ULT_MAX, t.ult + roundi(amount * 100.0 / t.max_hp() * ULT_FROM_DAMAGE))
				result.events.append({"pos": t.pos, "text": "-%d" % amount, "color": Color(1, 0.45, 0.35), "impact": true})
				if critical:
					parts.append("%s takes %d (critical!)" % [who, amount])
				parts.append("%s -%d%s" % [who, amount, " (defeated!)" if not t.is_alive() else ""])
			"heal":
				t.hp += amount
				result.events.append({"pos": t.pos, "text": "+%d" % amount, "color": Color(0.45, 1, 0.5), "impact": true})
				parts.append("%s +%d" % [who, amount])
			"revive":
				t.hp = amount
				t.ko_ticks = 0
				t.tg = 0
				t.ready = false
				result.revived.append(t.id)
				result.events.append({"pos": t.pos, "text": "Revived!", "color": Color(1, 0.95, 0.6), "impact": true})
				parts.append("%s revived with %d HP" % [who, amount])
		if not t.is_alive():
			if not t.is_ko():
				_knock_out(t, who, result)
			continue
		if ab.has("status"):
			_add_status(t, ab.status.id, ab.status.turns)
			var info: Dictionary = Jobs.STATUSES[ab.status.id]
			result.events.append({"pos": t.pos, "text": info.name, "color": info.color, "impact": true})
		# TG changes only affect units still filling their gauge.
		if ab.has("tg") and not t.ready:
			t.tg = clampi(t.tg + ab.tg * TG_MAX / 100, 0, TG_MAX)
			result.events.append({"pos": t.pos, "text": "TG %+d%%" % ab.tg, "color": Color(0.5, 0.8, 1), "impact": true})
		if ab.has("buffs"):
			for b in ab.buffs:
				t.buffs.append(b.duplicate())
			result.events.append({"pos": t.pos, "text": ab.name, "color": Color(0.5, 0.8, 1), "impact": true})
			if ab.effect == "support":
				parts.append(who)

	result.logs.append("%s %s uses %s%s" % [TEAM_NAMES[u.team], u.job_name(), ab.name,
		": " + ", ".join(parts) if not parts.is_empty() else " (no effect)"])
	_check_winner()
