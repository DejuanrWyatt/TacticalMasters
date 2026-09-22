extends RefCounted
## Jobs (unit classes) and their abilities, modeled on Final Fantasy Tactics.
## Distances are in meters (units move freely, not on a grid).
##
## Stats:
##   hp        hit points
##   att       AttPwr: strength of physical abilities
##   mag       MagPwr: strength of magic and healing
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
## Ability fields:
##   effect     "damage", "heal" or "support"
##   scale      "att" or "mag": which power stat drives it (and which defense resists)
##   power      multiplier on that stat
##   min_range / max_range   meters to the target point; max_range 0 = centered on yourself
##   aoe        radius in meters around the target point; 0 = a single unit
##   cooldown   your turns to wait before using it again
##   cast       seconds from starting the ability until it takes effect (0 = instant).
##              Move before casting: a unit can't move after starting a cast (only after
##              instant abilities). Its TG doesn't fill until the cast is done.
##   target     "enemy", "ally" (allies include yourself) or "ko_ally" (a knocked-out ally)
##   tg         optional change (in %) to each affected unit's Turn Gauge
##   buffs      optional [{"stat", "amount", "turns"}] applied to each affected unit
##   status     optional {"id", "seconds"}: a timed status (see STATUSES) on each unit hit
##
## effect "revive" brings a knocked-out ally back with `power` × max HP.

## Timed status effects (they tick in real time, not turns).
##   per_second  HP change per second as a fraction of max HP (negative = damage)
##   tg_factor   multiplier on Turn Gauge filling (0 = frozen)
##   no_orders   the unit can't be given orders while it lasts
const STATUSES := {
	"burn": {"name": "Burn", "tag": "BRN", "color": Color(1.0, 0.5, 0.2), "per_second": -0.03,
		"desc": "Loses 3% of max HP every second."},
	"regen": {"name": "Regen", "tag": "RGN", "color": Color(0.45, 1.0, 0.55), "per_second": 0.03,
		"desc": "Recovers 3% of max HP every second."},
	"slow": {"name": "Slow", "tag": "SLW", "color": Color(0.5, 0.75, 1.0), "tg_factor": 0.5,
		"desc": "Turn Gauge fills at half speed."},
	"stun": {"name": "Stun", "tag": "STN", "color": Color(1.0, 0.9, 0.3), "tg_factor": 0.0, "no_orders": true,
		"desc": "Can't act and Turn Gauge is frozen (a READY countdown keeps running)."},
}

const DEFAULT_ROSTER := ["knight", "archer", "black_mage", "white_mage"]
const GENERIC_ICON := "res://assets/icons/generic.svg"

const JOBS := {
	"squire": {
		"name": "Squire", "color": Color(0.85, 0.65, 0.35),
		"hp": 80, "att": 14, "mag": 6, "attdef": 8, "magdef": 6,
		"wits": 9, "move": 7, "patience": 6, "sight": 9,
		"abilities": ["attack", "throw_stone", "focus", "brave_slash"],
	},
	"knight": {
		"name": "Knight", "color": Color(0.75, 0.78, 0.85),
		"hp": 100, "att": 16, "mag": 5, "attdef": 12, "magdef": 6,
		"wits": 7, "move": 6, "patience": 7, "sight": 8,
		"abilities": ["attack", "shield_bash", "guard", "holy_blade"],
	},
	"archer": {
		"name": "Archer", "color": Color(0.35, 0.7, 0.35),
		"hp": 70, "att": 15, "mag": 6, "attdef": 6, "magdef": 7,
		"wits": 10, "move": 7, "patience": 6, "sight": 13,
		"abilities": ["bow_shot", "aimed_shot", "pin_shot", "arrow_rain"],
	},
	"monk": {
		"name": "Monk", "color": Color(0.9, 0.5, 0.2),
		"hp": 90, "att": 17, "mag": 6, "attdef": 8, "magdef": 5,
		"wits": 10, "move": 8, "patience": 5, "sight": 9,
		"abilities": ["punch", "wave_fist", "chakra", "earth_slash"],
	},
	"black_mage": {
		"name": "Black Mage", "color": Color(0.25, 0.2, 0.45),
		"hp": 60, "att": 5, "mag": 18, "attdef": 4, "magdef": 12,
		"wits": 8, "move": 6, "patience": 8, "sight": 10,
		"abilities": ["staff", "fire", "blizzard", "meteor"],
	},
	"white_mage": {
		"name": "White Mage", "color": Color(0.95, 0.95, 0.95),
		"hp": 65, "att": 5, "mag": 15, "attdef": 5, "magdef": 13,
		"wits": 8, "move": 6, "patience": 8, "sight": 10,
		"abilities": ["raise", "cure", "haste", "sanctuary"],
	},
}

const ABILITIES := {
	# Squire
	"attack": {"name": "Attack", "desc": "Strike an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 1.0, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"throw_stone": {"name": "Throw Stone", "desc": "Hurl a stone at an enemy 2-7 m away.",
		"effect": "damage", "scale": "att", "power": 0.7, "min_range": 2.0, "max_range": 7.0, "aoe": 0.0, "cooldown": 1, "cast": 0.0, "target": "enemy"},
	"focus": {"name": "Focus", "desc": "Raise your AttPwr by 6 for 2 turns.",
		"effect": "support", "scale": "att", "power": 0.0, "min_range": 0.0, "max_range": 0.0, "aoe": 0.0, "cooldown": 3, "cast": 0.0, "target": "ally",
		"buffs": [{"stat": "att", "amount": 6, "turns": 2}]},
	"brave_slash": {"name": "Brave Slash", "desc": "ULTIMATE: a devastating blow.",
		"effect": "damage", "scale": "att", "power": 2.6, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	# Knight
	"shield_bash": {"name": "Shield Bash", "desc": "Hit and stun an enemy for 1.5 s, lowering its TG by 30%.",
		"effect": "damage", "scale": "att", "power": 1.3, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 2, "cast": 0.0, "target": "enemy", "tg": -30,
		"status": {"id": "stun", "seconds": 1.5}},
	"guard": {"name": "Guard", "desc": "Raise your AttDef by 8 and MagDef by 6 for 2 turns.",
		"effect": "support", "scale": "att", "power": 0.0, "min_range": 0.0, "max_range": 0.0, "aoe": 0.0, "cooldown": 3, "cast": 0.0, "target": "ally",
		"buffs": [{"stat": "attdef", "amount": 8, "turns": 2}, {"stat": "magdef", "amount": 6, "turns": 2}]},
	"holy_blade": {"name": "Holy Blade", "desc": "ULTIMATE: a pillar of light hits every enemy within 1.5 m of the target.",
		"effect": "damage", "scale": "att", "power": 2.0, "min_range": 0.0, "max_range": 3.0, "aoe": 1.5, "cooldown": 0, "cast": 1.0, "target": "enemy"},
	# Archer
	"bow_shot": {"name": "Bow Shot", "desc": "Shoot an enemy 3-10 m away.",
		"effect": "damage", "scale": "att", "power": 1.0, "min_range": 3.0, "max_range": 10.0, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"aimed_shot": {"name": "Aimed Shot", "desc": "A careful, powerful shot 4-12 m away.",
		"effect": "damage", "scale": "att", "power": 1.6, "min_range": 4.0, "max_range": 12.0, "aoe": 0.0, "cooldown": 2, "cast": 1.0, "target": "enemy"},
	"pin_shot": {"name": "Pin Shot", "desc": "Pin an enemy down, lowering its TG by 40%.",
		"effect": "damage", "scale": "att", "power": 0.7, "min_range": 3.0, "max_range": 10.0, "aoe": 0.0, "cooldown": 2, "cast": 0.0, "target": "enemy", "tg": -40},
	"arrow_rain": {"name": "Arrow Rain", "desc": "ULTIMATE: arrows fall on every enemy within 2.5 m of a point 4-13 m away.",
		"effect": "damage", "scale": "att", "power": 1.3, "min_range": 4.0, "max_range": 13.0, "aoe": 2.5, "cooldown": 0, "cast": 2.0, "target": "enemy"},
	# Monk
	"punch": {"name": "Punch", "desc": "A hard blow to an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 1.2, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"wave_fist": {"name": "Wave Fist", "desc": "A shockwave that hits an enemy 2-5 m away.",
		"effect": "damage", "scale": "att", "power": 1.0, "min_range": 2.0, "max_range": 5.0, "aoe": 0.0, "cooldown": 1, "cast": 0.0, "target": "enemy"},
	"chakra": {"name": "Chakra", "desc": "Heal yourself and allies within 2.5 m, and give them Regen for 5 s (uses AttPwr).",
		"effect": "heal", "scale": "att", "power": 0.9, "min_range": 0.0, "max_range": 0.0, "aoe": 2.5, "cooldown": 3, "cast": 0.0, "target": "ally",
		"status": {"id": "regen", "seconds": 5.0}},
	"earth_slash": {"name": "Earth Slash", "desc": "ULTIMATE: shatter the ground, hitting every enemy within 3.5 m.",
		"effect": "damage", "scale": "att", "power": 1.8, "min_range": 0.0, "max_range": 0.0, "aoe": 3.5, "cooldown": 0, "cast": 1.0, "target": "enemy"},
	# Mages
	"staff": {"name": "Staff Strike", "desc": "A weak strike to an enemy within reach.",
		"effect": "damage", "scale": "att", "power": 0.6, "min_range": 0.0, "max_range": 1.8, "aoe": 0.0, "cooldown": 0, "cast": 0.0, "target": "enemy"},
	"fire": {"name": "Fire", "desc": "Hurl a fireball at an enemy 2-8 m away; it Burns for 6 s.",
		"effect": "damage", "scale": "mag", "power": 1.4, "min_range": 2.0, "max_range": 8.0, "aoe": 0.0, "cooldown": 0, "cast": 1.0, "target": "enemy",
		"status": {"id": "burn", "seconds": 6.0}},
	"blizzard": {"name": "Blizzard", "desc": "Freeze every enemy within 2 m of a point 2-8 m away, Slowing them for 6 s.",
		"effect": "damage", "scale": "mag", "power": 1.0, "min_range": 2.0, "max_range": 8.0, "aoe": 2.0, "cooldown": 2, "cast": 2.0, "target": "enemy",
		"status": {"id": "slow", "seconds": 6.0}},
	"meteor": {"name": "Meteor", "desc": "ULTIMATE: a meteor strikes every enemy within 3.5 m of a point 3-10 m away.",
		"effect": "damage", "scale": "mag", "power": 2.2, "min_range": 3.0, "max_range": 10.0, "aoe": 3.5, "cooldown": 0, "cast": 4.0, "target": "enemy"},
	"cure": {"name": "Cure", "desc": "Heal an ally (or yourself) up to 6 m away.",
		"effect": "heal", "scale": "mag", "power": 1.6, "min_range": 0.0, "max_range": 6.0, "aoe": 0.0, "cooldown": 0, "cast": 1.0, "target": "ally"},
	"haste": {"name": "Haste", "desc": "Raise an ally's TG by 50% so it acts sooner.",
		"effect": "support", "scale": "mag", "power": 0.0, "min_range": 0.0, "max_range": 6.0, "aoe": 0.0, "cooldown": 3, "cast": 1.5, "target": "ally", "tg": 50},
	"sanctuary": {"name": "Sanctuary", "desc": "ULTIMATE: heal every ally within 3.5 m of a point up to 8 m away, with Regen for 8 s.",
		"effect": "heal", "scale": "mag", "power": 2.0, "min_range": 0.0, "max_range": 8.0, "aoe": 3.5, "cooldown": 0, "cast": 3.0, "target": "ally",
		"status": {"id": "regen", "seconds": 8.0}},
	"raise": {"name": "Raise", "desc": "Revive a knocked-out ally up to 5 m away with 30% HP.",
		"effect": "revive", "scale": "mag", "power": 0.3, "min_range": 0.0, "max_range": 5.0, "aoe": 0.0, "cooldown": 4, "cast": 2.0, "target": "ko_ally"},
}


# --- Registry: built-in jobs plus imported classes (see AstraImport) --------

## Imported classes and their abilities, added at startup (and, online, sent
## by the host). Same shapes as JOBS / ABILITIES.
static var custom_jobs := {}
static var custom_abilities := {}


## Every job id -> data, built-in first.
static func all_jobs() -> Dictionary:
	var out := JOBS.duplicate()
	out.merge(custom_jobs, true)
	return out


static func has_job(id: String) -> bool:
	return JOBS.has(id) or custom_jobs.has(id)


static func job(id: String) -> Dictionary:
	return custom_jobs[id] if custom_jobs.has(id) else JOBS[id]


static func ability(id: String) -> Dictionary:
	return custom_abilities[id] if custom_abilities.has(id) else ABILITIES[id]


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


## Adds classes: {"jobs": {id: job}, "abilities": {id: ability}}.
static func register(classes: Dictionary) -> void:
	custom_abilities.merge(classes.get("abilities", {}), true)
	custom_jobs.merge(classes.get("jobs", {}), true)


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
