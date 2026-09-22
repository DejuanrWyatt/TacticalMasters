extends RefCounted
## Computer opponent. Each call returns the next single order for one of its
## ready units: maybe a move, maybe an ability, then end_turn.
##
## It tries standing spots it can walk to (every meter) with every usable
## ability aimed at every unit it can see, and picks the best score (damage,
## kills, healing, support). With nothing worth doing, it walks toward the
## nearest visible enemy, or toward the enemy's starting area if none are
## visible, stopping at its preferred fighting distance.
##
## Difficulty (see LEVELS) sets how quickly it reacts, how long it pauses
## between orders, and how often it settles for a weaker option instead of
## its best one. Hard never makes mistakes.

const LEVELS := {
	# think: seconds from a unit becoming READY to its first order
	# step: seconds between orders
	# mistakes: chance to pick a random option from the `top` best instead of the best
	"easy": {"think": 2.5, "step": 1.2, "mistakes": 0.45, "top": 5},
	"medium": {"think": 1.3, "step": 0.9, "mistakes": 0.2, "top": 3},
	"hard": {"think": 0.4, "step": 0.6, "mistakes": 0.0, "top": 1},
}

var difficulty := "hard"
var rng := RandomNumberGenerator.new()


func _init(p_difficulty := "hard") -> void:
	difficulty = p_difficulty if LEVELS.has(p_difficulty) else "hard"
	rng.randomize()


func level() -> Dictionary:
	return LEVELS[difficulty]


func next_command(state, u) -> Dictionary:
	var order := {"unit": u.id, "serial": u.serial}
	# One pathfinding search per decision, shared by everything below.
	var reach: Dictionary = {} if u.moved or u.is_casting() else state.reachable_nodes(u)
	if not u.acted:
		var best := _best_action(state, u, reach)
		if not best.is_empty():
			if best.spot != u.pos:
				return order.merged({"type": "move", "to": best.spot})
			return order.merged({"type": "ability", "slot": best.slot, "target": best.target, "follow": best.follow})
	if not u.moved and not u.is_casting():
		var dest := _approach_spot(state, u, reach)
		if dest != u.pos:
			return order.merged({"type": "move", "to": dest})
	return order.merged({"type": "end_turn"})


## Standing spots to consider: where the unit is, plus reachable spots on a 1 m grid.
func _spots(state, u, reach: Dictionary) -> Array[Vector2]:
	var spots: Array[Vector2] = [u.pos]
	for n in reach:
		if n.x % 2 == 0 and n.y % 2 == 0:
			spots.append(state.node_pos(n))
	return spots


## The best-scoring (spot, ability, target), or on a "mistake" roll a random
## one of the few best. Empty if nothing is worth doing.
func _best_action(state, u, reach: Dictionary) -> Dictionary:
	var options: Array[Dictionary] = []
	var spots := _spots(state, u, reach)
	var sight: float = state.sight_of(u)
	for slot in 4:
		if state.ability_blocked_reason(u, slot) != "":
			continue
		var ab: Dictionary = u.ability(slot)
		var min_r: float = ab.min_range
		var max_r: float = ab.max_range
		var cast_factor: float = 1.0 - 0.08 * ab.get("cast", 0.0)
		# Units this ability could be aimed at (the right side), and whether
		# the rest of the team already sees them: both independent of the spot.
		var candidates := []
		for t in state.units:
			var fits: bool
			if ab.target == "ko_ally":
				fits = t.is_ko() and t.team == u.team
			else:
				fits = t.is_alive() and (t.team != u.team) == (ab.target == "enemy")
			if fits:
				candidates.append([t, t == u or state.can_see(u.team, t.pos, u.id)])
		var needs_los: bool = state.needs_line_of_sight(ab)
		for spot in spots:
			var aims: Array[Vector2] = []
			if max_r == 0.0:
				aims.append(spot)
			else:
				for c in candidates:
					var t = c[0]
					var t_pos: Vector2 = spot if t == u else t.pos
					var d := spot.distance_to(t_pos)
					# Cheap checks first: range, then vision.
					if d < min_r or d > max_r:
						continue
					# Then the (costlier) terrain checks.
					var clear: bool = not needs_los or state.has_line_of_sight(spot, t_pos)
					if not clear:
						continue
					if c[1] or (d <= sight and (needs_los or state.has_line_of_sight(spot, t_pos))):
						aims.append(t_pos)
			for target in aims:
				var score := _score(u, slot, ab, state.preview(u, slot, spot, target))
				if score <= 0.0:
					continue
				# Slow casts give targets time to walk away.
				score *= cast_factor
				score += state.level_at(spot) * 0.5 - spot.distance_to(u.pos) * 0.05
				options.append({"score": score, "spot": spot, "slot": slot, "target": target})
	if options.is_empty():
		return {}
	options.sort_custom(func(a, b): return a.score > b.score)
	var pick: Dictionary = options[0]
	var lv := level()
	if lv.mistakes > 0.0 and rng.randf() < lv.mistakes:
		pick = options[rng.randi_range(0, mini(lv.top, options.size()) - 1)]
	pick.follow = _unit_at(state, pick.target, u, pick.spot, u.ability(pick.slot))
	return pick


## Id of the unit standing on `target` (the AI always aims at units), or -1.
func _unit_at(state, target: Vector2, u, spot: Vector2, ab: Dictionary) -> int:
	# A revive follows the knocked-out ally (the caster may stand on its spot).
	if ab.target == "ko_ally":
		for t in state.units:
			if t.is_ko() and t.team == u.team and t.pos == target:
				return t.id
		return -1
	if target == spot:
		return u.id if spot == u.pos else -1
	for t in state.units:
		if t.is_alive() and t.pos == target:
			return t.id
	return -1


func _score(u, slot: int, ab: Dictionary, hits: Array) -> float:
	var score := 0.0
	# A toggle is worth switching on once; never worth switching back off.
	if ab.get("kind", "active") == "toggle":
		if u.toggled.get(slot, false):
			return 0.0
		var helps := false
		for b in ab.get("buffs", []):
			helps = helps or b.amount > 0
		if not helps:
			return 0.0
	for hit in hits:
		var t = hit.unit
		var amount: int = hit.amount
		match ab.effect:
			"damage":
				score += amount
				if amount >= t.hp:
					score += 30.0
			"heal":
				score += amount * 1.2
			"revive":
				score += 70.0 + amount
			"support":
				# Haste only helps an ally still filling its gauge.
				if ab.has("tg") and t != u and not t.ready:
					score += 12.0
				if ab.has("buffs"):
					score += 8.0
		# A fresh status (Slow, Stun, Burn, Regen) on the unit is worth something.
		if ab.has("status") and t.is_alive() and not t.has_status(ab.status.id):
			score += 20.0 if ab.status.id == "stun" else 10.0
	return score


## Spot that moves the unit toward its preferred fighting distance.
func _approach_spot(state, u, reach: Dictionary) -> Vector2:
	var goals: Array[Vector2] = []
	for enemy in state.team_units(1 - u.team):
		if state.can_see(u.team, enemy.pos):
			goals.append(enemy.pos)
	if goals.is_empty():
		goals.append(state.spawn_points[1 - u.team])
	var attack_range: float = maxf(u.ability(0).max_range, u.ability(1).max_range)
	var desired := maxf(1.0, attack_range - 1.0)
	var best: Vector2 = u.pos
	var best_value := INF
	for n in reach:
		var dist: float = state.distance_to_nearest(goals, n)
		var value: float = absf(minf(dist, 999.0) - desired) - state.node_level(n) * 0.1
		if value < best_value:
			best_value = value
			best = state.node_pos(n)
	return best
