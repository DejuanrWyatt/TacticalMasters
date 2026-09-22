extends RefCounted
## Jobs (unit classes) and their abilities, modeled on Final Fantasy Tactics.
## Distances are in meters (units move freely, not on a grid).
##
## Stats:
##   hp        hit points
##   power     Power: flat bonus to the damage and healing its abilities do
##             (0 for most classes; buffs and stances raise it)
##   aeva      A-Eva: chance in % to evade a physical ability (5-30)
##   meva      M-Eva: chance in % to evade a harmful magical ability (5-30)
##   crit      Crit: chance in % that an ability lands a critical hit (5-30)
##   attdef    AttDef: reduces physical damage
##   magdef    MagDef: reduces magical damage
##   wits      how fast the Turn Gauge (TG) fills; higher = more turns
##   move      meters the unit can walk per turn
##   patience  length of the countdown while ready (see GameState.clock_ticks)
##   sight     vision radius in meters through the fog of war
##
## Every job has 4 abilities. The 4th is its ultimate, usable only when the
## ultimate meter is full.
##
## Ability types ("kind", as in Astra Ability Creator):
##   active          used on its owner's turn (the default)
##   passive         always on: its buffs apply from the start, it can't be used
##   toggle          switched on and off; its buffs apply while on (free action)
##   channeled       repeats on each of the caster's next `channel` turns; it
##                   can't act meanwhile (End Turn stops it)
##   active_passive  both: its buffs always apply, and it can still be used
##   aura            always on: its buffs go to everyone of the target side
##                   within `aoe` m, refreshed on their turns
const KINDS := {
	"active": {"name": "Active", "desc": "Used on the unit's turn."},
	"passive": {"name": "Passive", "desc": "Always on; can't be used."},
	"toggle": {"name": "Toggle", "desc": "Switched on and off; applies while on."},
	"channeled": {"name": "Channeled", "desc": "Repeats each turn while it lasts; the unit can't act."},
	"active_passive": {"name": "Active + Passive", "desc": "Always on, and can be used as well."},
	"aura": {"name": "Aura", "desc": "Always on; affects everyone nearby."},
}

## Target shapes ("shape", as in Astra Ability Creator). `aoe` is the radius
## for circles, the half-width for lines and the spread for cones.
##   unit     one unit at the point
##   point    a spot on the ground (anyone standing there)
##   circle   everyone within `aoe` m of the point
##   self     centered on the caster
##   line     everyone within `aoe` m of the line from the caster to the point
##   cone     everyone within `max_range` m and `angle` degrees of the aim
##   global   everyone of the target side, wherever they are
##   vector   like a line, and the caster ends up at the far end
const SHAPES := {
	"unit": {"name": "Unit"}, "point": {"name": "Point"}, "circle": {"name": "Circle"}, "self": {"name": "Self"},
	"line": {"name": "Line"}, "cone": {"name": "Cone"}, "global": {"name": "Global"}, "vector": {"name": "Vector"},
}

## Ability fields:
##   kind       one of KINDS (default "active")
##   shape      one of SHAPES (default: "circle" when aoe > 0, else "unit")
##   angle      cone spread in degrees (default 60)
##   channel    turns a channeled ability lasts (default 2)
##   effect     "damage", "heal" or "support"
##   scale      "att" (physical: AttDef and A-Eva resist it) or "mag" (magical:
##              MagDef and M-Eva)
##   power      how much damage it does (or healing, or % of max HP to revive
##              with); the user's Power stat is added to it
##   min_range / max_range   meters to the target point; max_range 0 = centered on yourself
##   aoe        radius in meters around the target point; 0 = a single unit
##   cooldown   your turns to wait before using it again
##   cast       seconds from starting the ability until it takes effect (0 = instant).
##              Move before casting: a unit can't move after starting a cast (only after
##              instant abilities). Its TG doesn't fill until the cast is done.
##   target     "enemy", "ally" (allies include yourself) or "ko_ally" (a knocked-out ally)
##   tg         optional change (in %) to each affected unit's Turn Gauge
##   buffs      optional [{"stat", "amount", "turns"}] applied to each affected unit
##   status     optional {"id", "turns"}: a status (see STATUSES) on each unit
##              hit, lasting that many of its own turns
##
## effect "revive" brings a knocked-out ally back with `power` × max HP.

## Status effects last a number of the affected unit's own turns. Each of its
## turns, the status acts and then counts down by one (so "2 turns" means its
## next two turns); Burn and Regen change HP at the start of that turn.
##   per_turn    HP change as a fraction of max HP (negative = damage)
##   tg_factor   multiplier on Turn Gauge filling (0 = frozen)
##   no_orders   the unit can't be given orders while it lasts
const STATUSES := {
	"burn": {"name": "Burn", "tag": "BRN", "color": Color(1.0, 0.5, 0.2), "per_turn": -0.1,
		"desc": "Loses 10% of max HP at the start of each of its turns."},
	"regen": {"name": "Regen", "tag": "RGN", "color": Color(0.45, 1.0, 0.55), "per_turn": 0.1,
		"desc": "Recovers 10% of max HP at the start of each of its turns."},
	"slow": {"name": "Slow", "tag": "SLW", "color": Color(0.5, 0.75, 1.0), "tg_factor": 0.5,
		"desc": "Turn Gauge fills at half speed."},
	"stun": {"name": "Stun", "tag": "STN", "color": Color(1.0, 0.9, 0.3), "no_orders": true,
		"desc": "Loses its next turns: the gauge fills, but each turn is lost and the Stun counts down."},
}

const DEFAULT_ROSTER := ["knight", "archer", "black_mage", "white_mage"]
const GENERIC_ICON := "res://assets/icons/generic.svg"
## One icon per ability (tools/ability_icons.mjs draws them); an ability
## without its own gets one for what it does.
const ABILITY_ICON_DIR := "res://assets/icons/abilities/"

## What a class is for. A class can have two, e.g. "tank/support".
##   tank     soaks damage and protects the team
##   damage   kills things
##   support  heals, revives and buffs allies
##   special  bends the rules: Turn Gauge, stuns, debuffs
const ROLES := {
	"tank": {"name": "Tank", "color": Color(0.5, 0.7, 0.92), "icon": "res://assets/icons/role_tank.svg"},
	"damage": {"name": "Damage", "color": Color(0.94, 0.48, 0.42), "icon": "res://assets/icons/role_damage.svg"},
	"support": {"name": "Support", "color": Color(0.47, 0.86, 0.63), "icon": "res://assets/icons/role_support.svg"},
	"special": {"name": "Special", "color": Color(0.79, 0.64, 0.95), "icon": "res://assets/icons/role_special.svg"},
}

const JOBS := {
	"squire": {
		"name": "Squire", "color": Color(0.85, 0.65, 0.35), "role": "damage",
		"hp": 75, "power": 14, "attdef": 8, "magdef": 6,
		"aeva": 8, "meva": 5, "crit": 8,
		"wits": 10, "move": 7, "patience": 6, "sight": 9,
		"abilities": ["attack", "throw_stone", "focus", "brave_slash"],
	},
	"knight": {
		"name": "Knight", "color": Color(0.75, 0.78, 0.85), "role": "tank/damage",
		"hp": 105, "power": 16, "attdef": 12, "magdef": 6,
		"aeva": 5, "meva": 5, "crit": 5,
		"wits": 6, "move": 6, "patience": 7, "sight": 8,
		"abilities": ["attack", "shield_bash", "guard", "holy_blade"],
	},
	"archer": {
		"name": "Archer", "color": Color(0.35, 0.7, 0.35), "role": "damage",
		"hp": 60, "power": 15, "attdef": 6, "magdef": 7,
		"aeva": 15, "meva": 8, "crit": 15,
		"wits": 12, "move": 7, "patience": 6, "sight": 13,
		"abilities": ["bow_shot", "aimed_shot", "pin_shot", "arrow_rain"],
	},
	"monk": {
		"name": "Monk", "color": Color(0.9, 0.5, 0.2), "role": "damage/support",
		"hp": 80, "power": 17, "attdef": 8, "magdef": 5,
		"aeva": 18, "meva": 8, "crit": 12,
		"wits": 12, "move": 8, "patience": 5, "sight": 9,
		"abilities": ["punch", "wave_fist", "chakra", "earth_slash"],
	},
	"black_mage": {
		"name": "Black Mage", "color": Color(0.25, 0.2, 0.45), "role": "damage",
		"hp": 60, "power": 18, "attdef": 4, "magdef": 12,
		"aeva": 5, "meva": 12, "crit": 10,
		"wits": 8, "move": 6, "patience": 8, "sight": 10,
		"abilities": ["staff", "fire", "blizzard", "meteor"],
	},
	"white_mage": {
		"name": "White Mage", "color": Color(0.95, 0.95, 0.95), "role": "support",
		"hp": 65, "power": 15, "attdef": 5, "magdef": 13,
		"aeva": 5, "meva": 15, "crit": 5,
		"wits": 8, "move": 6, "patience": 8, "sight": 10,
		"abilities": ["raise", "cure", "haste", "sanctuary"],
	},
}

const ABILITIES := {
	# Squire
	"attack": {"name": "Attack", "desc": "Strike an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 16, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"throw_stone": {"name": "Throw Stone", "desc": "Hurl a stone at an enemy 2-7 m away.",
		"effect": "damage", "scale": "att", "power": 6, "min_range": 2.0, "max_range": 7.0, "aoe": 0.0, "cooldown": 1, "cast": 0.0, "target": "enemy"},
	"focus": {"name": "Focus", "desc": "Raise your Power by 6 for 2 turns (its abilities hit harder).",
		"effect": "support", "scale": "att", "power": 0, "min_range": 0.0, "max_range": 0.0, "aoe": 0.0, "cooldown": 3, "cast": 0.0, "target": "ally",
		"buffs": [{"stat": "power", "amount": 6, "turns": 2}]},
	"brave_slash": {"name": "Brave Slash", "desc": "ULTIMATE: a devastating blow.",
		"effect": "damage", "scale": "att", "power": 59, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	# Knight
	"shield_bash": {"name": "Shield Bash", "desc": "Hit an enemy, lowering its TG by 30% and Stunning it for a turn.",
		"effect": "damage", "scale": "att", "power": 26, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 2, "cast": 0.0, "target": "enemy", "tg": -30,
		"status": {"id": "stun", "turns": 1}},
	"guard": {"name": "Guard", "desc": "Raise your AttDef by 8 and MagDef by 6 for 2 turns.",
		"effect": "support", "scale": "att", "power": 0.0, "min_range": 0.0, "max_range": 0.0, "aoe": 0.0, "cooldown": 3, "cast": 0.0, "target": "ally",
		"buffs": [{"stat": "attdef", "amount": 8, "turns": 2}, {"stat": "magdef", "amount": 6, "turns": 2}]},
	"holy_blade": {"name": "Holy Blade", "desc": "ULTIMATE: a pillar of light hits every enemy within 1.5 m of the target.",
		"effect": "damage", "scale": "att", "power": 48, "min_range": 0.0, "max_range": 3.0, "aoe": 1.5, "cooldown": 0, "cast": 1.0, "target": "enemy"},
	# Archer
	"bow_shot": {"name": "Bow Shot", "desc": "Shoot an enemy 3-10 m away.",
		"effect": "damage", "scale": "att", "power": 15, "min_range": 3.0, "max_range": 10.0, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"aimed_shot": {"name": "Aimed Shot", "desc": "A careful, powerful shot 4-12 m away.",
		"effect": "damage", "scale": "att", "power": 33, "min_range": 4.0, "max_range": 12.0, "aoe": 0.0, "cooldown": 2, "cast": 1.0, "target": "enemy"},
	"pin_shot": {"name": "Pin Shot", "desc": "Pin an enemy down, lowering its TG by 40%.",
		"effect": "damage", "scale": "att", "power": 6, "min_range": 3.0, "max_range": 10.0, "aoe": 0.0, "cooldown": 2, "cast": 0.0, "target": "enemy", "tg": -40},
	"arrow_rain": {"name": "Arrow Rain", "desc": "ULTIMATE: arrows fall on every enemy within 2.5 m of a point 4-13 m away.",
		"effect": "damage", "scale": "att", "power": 24, "min_range": 4.0, "max_range": 13.0, "aoe": 2.5, "cooldown": 0, "cast": 2.0, "target": "enemy"},
	# Monk
	"punch": {"name": "Punch", "desc": "A hard blow to an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 24, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"wave_fist": {"name": "Wave Fist", "desc": "A shockwave that hits an enemy 2-5 m away.",
		"effect": "damage", "scale": "att", "power": 17, "min_range": 2.0, "max_range": 5.0, "aoe": 0.0, "cooldown": 1, "cast": 0.0, "target": "enemy"},
	"chakra": {"name": "Chakra", "desc": "Heal yourself and allies within 2.5 m, and give them Regen for 2 turns.",
		"effect": "heal", "scale": "att", "power": 8, "min_range": 0.0, "max_range": 0.0, "aoe": 2.5, "cooldown": 3, "cast": 0.0, "target": "ally",
		"status": {"id": "regen", "turns": 2}},
	"earth_slash": {"name": "Earth Slash", "desc": "ULTIMATE: shatter the ground, hitting every enemy within 3.5 m.",
		"effect": "damage", "scale": "att", "power": 44, "min_range": 0.0, "max_range": 0.0, "aoe": 3.5, "cooldown": 0, "cast": 1.0, "target": "enemy"},
	# Mages
	"staff": {"name": "Staff Strike", "desc": "A weak strike to an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 5, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"fire": {"name": "Fire", "desc": "Hurl a fireball at an enemy 2-8 m away; it Burns for 3 turns.",
		"effect": "damage", "scale": "mag", "power": 32, "min_range": 2.0, "max_range": 8.0, "aoe": 0.0, "cooldown": 0, "cast": 1.0, "target": "enemy",
		"status": {"id": "burn", "turns": 3}},
	"blizzard": {"name": "Blizzard", "desc": "Freeze every enemy within 2 m of a point 2-8 m away, Slowing them for 2 turns.",
		"effect": "damage", "scale": "mag", "power": 18, "min_range": 2.0, "max_range": 8.0, "aoe": 2.0, "cooldown": 2, "cast": 2.0, "target": "enemy",
		"status": {"id": "slow", "turns": 2}},
	"meteor": {"name": "Meteor", "desc": "ULTIMATE: a meteor strikes every enemy within 3.5 m of a point 3-10 m away.",
		"effect": "damage", "scale": "mag", "power": 61, "min_range": 3.0, "max_range": 10.0, "aoe": 3.5, "cooldown": 0, "cast": 4.0, "target": "enemy"},
	"cure": {"name": "Cure", "desc": "Heal an ally (or yourself) up to 6 m away.",
		"effect": "heal", "scale": "mag", "power": 9, "min_range": 0.0, "max_range": 6.0, "aoe": 0.0, "cooldown": 0, "cast": 1.0, "target": "ally"},
	"haste": {"name": "Haste", "desc": "Raise an ally's TG by 50% so it acts sooner.",
		"effect": "support", "scale": "mag", "power": 0, "min_range": 0.0, "max_range": 6.0, "aoe": 0.0, "cooldown": 3, "cast": 1.5, "target": "ally", "tg": 50},
	"sanctuary": {"name": "Sanctuary", "desc": "ULTIMATE: heal every ally within 3.5 m of a point up to 8 m away, with Regen for 3 turns.",
		"effect": "heal", "scale": "mag", "power": 15, "min_range": 0.0, "max_range": 8.0, "aoe": 3.5, "cooldown": 0, "cast": 3.0, "target": "ally",
		"status": {"id": "regen", "turns": 3}},
	"raise": {"name": "Raise", "desc": "Revive a knocked-out ally up to 5 m away with 30% HP.",
		"effect": "revive", "scale": "mag", "power": 0.3, "min_range": 0.0, "max_range": 5.0, "aoe": 0.0, "cooldown": 4, "cast": 2.0, "target": "ko_ally"},
}


# --- Registry: built-in jobs plus imported classes (see AstraImport) --------

## Imported classes and their abilities, added at startup (and, online, sent
## by the host). Same shapes as JOBS / ABILITIES.
static var custom_jobs := {}
static var custom_abilities := {}
## Changed stats (Unit Guide): {job id: {stat: value}}. job() returns the
## job with these applied; the merged copies are built when they change, so
## the computer's thinking thread only ever reads them.
static var stat_overrides := {}
static var _with_overrides := {}

## The stats a class has, and the values the Unit Guide allows for each.
const STAT_KEYS := ["hp", "power", "attdef", "magdef", "aeva", "meva", "crit", "wits", "move", "patience", "sight"]
const STAT_LIMITS := {"hp": [10, 300], "power": [0, 40], "attdef": [0, 30], "magdef": [0, 30],
	"aeva": [0, 60], "meva": [0, 60], "crit": [0, 60], "wits": [1, 20], "move": [1, 15], "patience": [0, 15], "sight": [3, 25]}


## Every job id -> data, built-in first.
static func all_jobs() -> Dictionary:
	var out := JOBS.duplicate()
	out.merge(custom_jobs, true)
	return out


static func has_job(id: String) -> bool:
	return JOBS.has(id) or custom_jobs.has(id)


static func job(id: String) -> Dictionary:
	if _with_overrides.has(id):
		return _with_overrides[id]
	return base_job(id)


## A job as designed, without changed stats.
static func base_job(id: String) -> Dictionary:
	return custom_jobs[id] if custom_jobs.has(id) else JOBS[id]


## Uses these changed stats from now on (see clean_overrides).
static func set_overrides(overrides: Dictionary) -> void:
	stat_overrides = clean_overrides(overrides)
	_rebuild_overrides()


static func _rebuild_overrides() -> void:
	var merged := {}
	for id in stat_overrides:
		if has_job(id):
			var data := base_job(id).duplicate()
			data.merge(stat_overrides[id], true)
			merged[id] = data
	_with_overrides = merged


## Keeps only known classes and stats, as whole numbers within their limits,
## and drops values equal to the class's own.
static func clean_overrides(overrides) -> Dictionary:
	var out := {}
	if not overrides is Dictionary:
		return out
	for id in overrides:
		if not (id is String and has_job(id) and overrides[id] is Dictionary):
			continue
		for stat in overrides[id]:
			var v = overrides[id][stat]
			if STAT_KEYS.has(stat) and (v is int or v is float):
				var value := clampi(roundi(v), STAT_LIMITS[stat][0], STAT_LIMITS[stat][1])
				if value != base_job(id)[stat]:
					if not out.has(id):
						out[id] = {}
					out[id][stat] = value
	return out


static func ability(id: String) -> Dictionary:
	return custom_abilities[id] if custom_abilities.has(id) else ABILITIES[id]


## What a class is for, as role ids ("tank", "damage/support", ...). A class
## says so itself (JOBS, or an imported class's Astra tag "role:<x>"); one
## that doesn't gets a role from its stats and abilities.
static func roles_of(id: String) -> Array:
	var job := base_job(id)
	var listed = job.get("role", "")
	var out := []
	if listed is String:
		for part in listed.split("/", false):
			if ROLES.has(part) and not out.has(part):
				out.append(part)
	return out if not out.is_empty() else _guess_roles(id)


## Reads the class: healing, reviving and ally buffs make a Support; statuses,
## Turn Gauge changes and enemy debuffs a Special; plenty of HP and AttDef a
## Tank; the rest is Damage. At most two, the strongest first.
static func _guess_roles(id: String) -> Array:
	var job := base_job(id)
	var score := {"tank": 0.0, "damage": 0.0, "support": 0.0, "special": 0.0}
	score.tank = (job.hp - 80) / 12.0 + (job.attdef + job.magdef - 14) / 5.0
	# How hard its abilities hit, on average.
	var hit := 0.0
	for ab_id in job.abilities:
		hit = maxf(hit, float(ability(ab_id).power) if ability(ab_id).effect == "damage" else 0.0)
	score.damage = (hit + job.power - 30.0) / 8.0
	for ab_id in job.abilities:
		var ab := ability(ab_id)
		match ab.effect:
			"heal":
				score.support += 1.5
			"revive":
				score.support += 1.5
			"damage":
				score.damage += 0.5
		if ab.has("buffs"):
			var helps := true
			for b in ab.buffs:
				helps = helps and b.amount > 0
			score.support += 1.0 if helps and ab.target != "enemy" else 0.0
			score.special += 0.0 if helps and ab.target != "enemy" else 1.0
		if ab.has("status") or (ab.has("tg") and ab.target == "enemy"):
			score.special += 1.0
		elif ab.has("tg"):
			score.support += 1.0
	var order := score.keys()
	order.sort_custom(func(a, b): return score[a] > score[b])
	var out := [order[0]]
	# A clear second role makes it a hybrid.
	if score[order[1]] >= maxf(1.5, score[order[0]] * 0.6):
		out.append(order[1])
	return out


## "Tank / Support" for the roles a class has.
static func role_name(id: String) -> String:
	var parts := []
	for role in roles_of(id):
		parts.append(ROLES[role].name)
	return " / ".join(parts)


## The icon of one ability.
static func ability_icon_path(ab_id: String) -> String:
	var path := ABILITY_ICON_DIR + ab_id + ".svg"
	if ResourceLoader.exists(path):
		return path
	var ab := ability(ab_id)
	var glyph := "damage"
	match ab.effect:
		"heal":
			glyph = "heal"
		"revive":
			glyph = "revive"
		"support":
			glyph = "debuff" if ab.target == "enemy" else ("buff" if ab.has("buffs") or ab.has("tg") else "status")
	return ABILITY_ICON_DIR + "any_%s.svg" % glyph


## The class icon (assets/icons/<id>.svg; an imported class can name one with
## the Astra tag "icon:<name>"); classes without one get the generic icon.
static func icon_path(id: String) -> String:
	var path := "res://assets/icons/%s.svg" % id
	if ResourceLoader.exists(path):
		return path
	if custom_jobs.has(id) and custom_jobs[id].has("icon"):
		path = "res://assets/icons/%s.svg" % custom_jobs[id].icon
		if ResourceLoader.exists(path):
			return path
	return GENERIC_ICON


static func is_custom(id: String) -> bool:
	return custom_jobs.has(id)


## Keeps only whole, sensible classes from {"jobs": ..., "abilities": ...}
## (used for what the host sends online, which must not be trusted).
static func clean_classes(classes) -> Dictionary:
	var out := {"jobs": {}, "abilities": {}}
	if not classes is Dictionary or not classes.get("jobs") is Dictionary or not classes.get("abilities") is Dictionary:
		return out
	var abilities: Dictionary = classes.abilities
	for id in classes.jobs:
		var job = classes.jobs[id]
		if not (id is String and id.length() <= 40 and job is Dictionary):
			continue
		if not (job.get("name") is String and job.get("color") is Color and job.get("abilities") is Array and job.abilities.size() == 4):
			continue
		var clean_job := {"name": String(job.name).substr(0, 40), "color": job.color, "abilities": [],
			"look": job.look if job.get("look") is String else "black_mage"}
		if job.get("role") is String:
			clean_job["role"] = job.role
		if job.get("icon") is String:
			clean_job["icon"] = job.icon
		var ok := true
		for stat in STAT_KEYS:
			var v = job.get(stat)
			if not (v is int or v is float):
				ok = false
				break
			clean_job[stat] = clampi(roundi(v), STAT_LIMITS[stat][0], STAT_LIMITS[stat][1])
		var clean_abilities := {}
		for ab_id in job.abilities:
			var ab = abilities.get(ab_id)
			if not (ab_id is String and ab is Dictionary) or not _ability_is_sane(ab):
				ok = false
				break
			clean_abilities[ab_id] = ab
			clean_job.abilities.append(ab_id)
		if ok:
			out.jobs[id] = clean_job
			out.abilities.merge(clean_abilities, true)
	return out


## Whether an ability dictionary has everything the rules read.
static func _ability_is_sane(ab: Dictionary) -> bool:
	for key in ["name", "desc", "effect", "scale", "target"]:
		if not ab.get(key) is String:
			return false
	for key in ["power", "min_range", "max_range", "aoe", "cast"]:
		var v = ab.get(key)
		if not (v is int or v is float) or v < 0.0 or v > 1000.0:
			return false
	if not ab.get("cooldown") is int or ab.cooldown < 0 or ab.cooldown > 20:
		return false
	if not ["damage", "heal", "support", "revive"].has(ab.effect) or not ["att", "mag"].has(ab.scale):
		return false
	if ab.has("status") and not (ab.status is Dictionary and STATUSES.has(ab.status.get("id", "")) and ab.status.get("turns") is int):
		return false
	if ab.has("kind") and not KINDS.has(ab.kind):
		return false
	return true


## Adds classes: {"jobs": {id: job}, "abilities": {id: ability}}.
static func register(classes: Dictionary) -> void:
	custom_abilities.merge(classes.get("abilities", {}), true)
	custom_jobs.merge(classes.get("jobs", {}), true)
	_rebuild_overrides()


## The definitions of the imported classes used in these rosters, for
## sending to the other player online.
static func classes_for(rosters: Array) -> Dictionary:
	var out := {"jobs": {}, "abilities": {}}
	for roster in rosters:
		for id in roster:
			if custom_jobs.has(id):
				out.jobs[id] = custom_jobs[id]
				for ab_id in custom_jobs[id].abilities:
					out.abilities[ab_id] = custom_abilities[ab_id]
	return out
