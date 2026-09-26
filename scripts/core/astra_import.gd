extends RefCounted
## Imports classes designed in Astra Ability Creator (E:\Astra-Ability Creator).
##
## Export the library (or one ability) from Astra as JSON and put the file in
## res://data/classes/ or user://classes/. Classes are loaded at startup.
##
## How an Astra library describes a class (all through tags):
##   "class:<id>"   every ability of the class carries it (id: letters, digits, _)
##   "profile"      one Passive ability per class holding its stats as
##                  parameters: hp, attdef, magdef, speed, move, patience and
##                  sight, plus the optional power (flat damage bonus, 0),
##                  aeva, meva and crit (chances in %, 5 each). Its name is the class name and its color
##                  the class color. Optional tag "look:<job>" picks which
##                  built-in character model to use (default black_mage).
##   "slot:1".."slot:4"  the class's 4 abilities; slot 4 is its ultimate.
##   "fx:<ability>"      optional: borrow a built-in ability's animation.
##   "role:<x>"          optional, on the profile: what the class is for,
##                       "tank", "damage", "support", "special" or a pair
##                       like "tank/support". Without it the game works one
##                       out from the stats and abilities.
##   "icon:<name>"       optional, on the profile: the class icon
##                       (assets/icons/<name>.svg; default the class id's icon,
##                       else a generic icon in the class color).
##   "revive"            optional: the ability revives a knocked-out ally.
##   "taunt"             optional: the ability taunts whoever it hits.
##
## Astra's **ability type** becomes the game's kind (see Jobs.KINDS):
## Active, Passive, Toggle, Channeled, Active + Passive and Aura. A Channeled
## ability lasts `channel_turns` turns (default 2).
##
## Astra's **targeting** becomes the target shape (see Jobs.SHAPES):
## Unit target, Point target, Self, Circle, Line, Cone, Global and Vector.
## A cone's spread comes from the `cone_angle` parameter (default 60).
##
## Ability parameters (formula keys), read at rank 1, distances in meters:
##   power           the damage it does (healing for heals, or the share of
##                   max HP a revive brings back)
##   min_range       closest target point (default 0)
##   cast_range      farthest target point (default 1.8 = melee; Self = 0)
##   radius          area radius (default 0 = one unit)
##   cast_time       seconds until it takes effect (default 0 = instant)
##   cooldown_turns  turns to wait (else Astra's "cooldown" seconds / 10)
##   channel_turns   turns a Channeled ability lasts (default 2)
##   cone_angle      spread of a cone in degrees (default 60)
##   tg_change       % change to each affected unit's Turn Gauge
##   buff_<stat>     a buff (e.g. buff_attdef); lasts buff_turns (default 2)
## Other fields: damageType Physical means AttDef and A-Eva resist it,
## anything else MagDef and M-Eva. targetTeam Enemies -> enemies, else allies.
## Effects: Damage / Heal decide what it does (none -> support). Slow, Stun,
## Shield, Root, Silence and periodic Damage (Burn) / Heal (Regen) put a
## status on each unit hit, lasting the effect's duration in *turns* of that
## unit. The tag "taunt" makes it a Taunt instead.
##
## Formulas use Astra's rules (numbers, + - * /, parentheses, postfix %,
## other parameter keys, Astra's sample stats and rank).

const Jobs = preload("res://scripts/core/jobs.gd")

const STAT_KEYS := Jobs.STAT_KEYS
## A class profile must give these; the rest fall back to DEFAULT_STATS.
const REQUIRED_STATS := ["hp", "attdef", "magdef", "speed", "move", "patience", "sight"]
const DEFAULT_STATS := {"power": 0, "aeva": 5, "meva": 5, "crit": 5}
## Stat parameters that have been renamed. A profile written before the change
## is read as the stat it now is rather than turned away for a missing one.
const LEGACY_STATS := {"wits": "speed"}
## The ability parameters the game reads (everything else is Astra's own).
const READ_KEYS := ["power", "min_range", "cast_range", "radius", "cast_time", "cooldown_turns", "cooldown",
	"tg_change", "status_duration", "channel_turns", "cone_angle"]
const STAT_LIMITS := Jobs.STAT_LIMITS
const DIRS := ["res://data/classes/", "user://classes/"]
## Astra's sample caster stats (model.mjs defaultStats), so formulas that
## Astra accepts also evaluate here.
const ASTRA_STATS := {"maxMana": 1000, "currentMana": 800, "maxHealth": 2000, "currentHealth": 1400,
	"attackDamage": 100, "bonusAttackDamage": 40, "spellPower": 100, "armor": 50, "magicResist": 30,
	"moveSpeed": 350, "abilityHaste": 0}
const BUILT_IN_LOOKS := ["squire", "knight", "archer", "monk", "black_mage", "white_mage"]
## Patterns are reused across classes, so each one is only built once.
static var _patterns := {}


static func _pattern(source: String) -> RegEx:
	if not _patterns.has(source):
		_patterns[source] = RegEx.create_from_string(source)
	return _patterns[source]
## Astra's ability types and targeting, as the game's kinds and shapes.
const KINDS := {"Active": "active", "Passive": "passive", "Toggle": "toggle", "Channeled": "channeled",
	"Active + Passive": "active_passive", "Aura": "aura"}
const SHAPES := {"Unit target": "unit", "Point target": "point", "Self": "self", "Circle": "circle",
	"Line": "line", "Cone": "cone", "Global": "global", "Vector": "vector"}


## Loads every class file in DIRS into the Jobs registry. Returns messages
## about what was loaded or skipped.
static func load_all() -> Array[String]:
	var messages: Array[String] = []
	for dir in DIRS:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".json"):
				continue
			var result := parse(FileAccess.get_file_as_string(dir + file))
			Jobs.register(result, true)  # one rebuild at the end, not per file
			for id in result.jobs:
				messages.append("Loaded class '%s' from %s" % [result.jobs[id].name, file])
			for e in result.errors:
				messages.append("%s: %s" % [file, e])
	Jobs.register({}, false)  # now apply any changed stats to what was loaded
	return messages


## Turns Astra JSON text into {"jobs": {}, "abilities": {}, "errors": []}.
static func parse(text: String) -> Dictionary:
	var out := {"jobs": {}, "abilities": {}, "errors": []}
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.get("abilities") is Array:
		out.errors.append("Not an Astra library export.")
		return out
	if data.get("schemaVersion") != 1.0:
		out.errors.append("Unsupported Astra schema version %s (expected 1)." % data.get("schemaVersion"))
		return out
	# Group by class tag.
	var classes := {}
	for a in data.abilities:
		if not a is Dictionary or not a.get("tags") is Array:
			continue
		for tag in a.tags:
			if tag is String and tag.begins_with("class:"):
				var id: String = tag.substr(6)
				if not classes.has(id):
					classes[id] = []
				classes[id].append(a)
	if classes.is_empty():
		out.errors.append("No abilities tagged class:<id>.")
	for id in classes:
		var err := _import_class(id, classes[id], out)
		if err != "":
			out.errors.append("Class '%s' skipped: %s" % [id, err])
	return out


static func _import_class(id: String, entries: Array, out: Dictionary) -> String:
	if not _pattern("^[a-z][a-z0-9_]{0,30}$").search(id):
		return "the id must be lowercase letters, digits and _."
	if Jobs.JOBS.has(id):
		return "'%s' is a built-in job." % id
	var profile = null
	var slots := [null, null, null, null]
	for a in entries:
		if a.tags.has("profile"):
			profile = a
		for tag in a.tags:
			if tag is String and tag.begins_with("slot:"):
				var n: int = int(tag.substr(5))
				if n >= 1 and n <= 4:
					slots[n - 1] = a
	if profile == null:
		return "no ability tagged 'profile' with the class stats."
	var job := {"name": str(profile.get("name", id)), "color": _color(profile.get("color", "")),
		"look": "black_mage", "abilities": [], "astra": true}
	for tag in profile.tags:
		if tag is String and tag.begins_with("look:") and BUILT_IN_LOOKS.has(tag.substr(5)):
			job["look"] = tag.substr(5)
		if tag is String and tag.begins_with("role:"):
			var wanted := []
			for part in tag.substr(5).split("/", false):
				if Jobs.ROLES.has(part) and not wanted.has(part):
					wanted.append(part)
			if not wanted.is_empty():
				job["role"] = "/".join(wanted)
			else:
				out.errors.append("Class '%s': ignoring role tag '%s' (use %s, or a pair like tank/support); its role is worked out from its stats instead."
					% [id, tag.substr(5), ", ".join(Jobs.ROLES.keys())])
		if tag is String and tag.begins_with("icon:") and _pattern("^[a-z0-9_]{1,40}$").search(tag.substr(5)):
			job["icon"] = tag.substr(5)
	var values := _values(profile)
	if values.has("error"):
		return "profile: " + values.error
	for old in LEGACY_STATS:
		if values.has(old) and not values.has(LEGACY_STATS[old]):
			values[LEGACY_STATS[old]] = values[old]
	for key in STAT_KEYS:
		if not values.has(key):
			if REQUIRED_STATS.has(key):
				return "the profile needs a '%s' parameter." % key
			job[key] = DEFAULT_STATS[key]
			continue
		job[key] = clampi(roundi(values[key]), STAT_LIMITS[key][0], STAT_LIMITS[key][1])
	var abilities := {}
	for i in 4:
		if slots[i] == null:
			return "no ability tagged 'slot:%d'." % (i + 1)
		var ab := _ability(slots[i], i == 3)
		if ab.has("error"):
			return "%s: %s" % [slots[i].get("name", "slot %d" % (i + 1)), ab.error]
		var ab_id := "%s_%s" % [id, _slug(ab.name)]
		abilities[ab_id] = ab
		job.abilities.append(ab_id)
	out.jobs[id] = job
	out.abilities.merge(abilities, true)
	return ""


static func _ability(a: Dictionary, ultimate: bool) -> Dictionary:
	var v := _values(a)
	if v.has("error"):
		return v
	var effects: Array = a.get("effects", []) if a.get("effects") is Array else []
	var types := []
	for e in effects:
		types.append(str(e.get("type", "")))
	var effect := "support"
	if a.tags.has("revive"):
		effect = "revive"
	elif types.has("Damage"):
		effect = "damage"
	elif types.has("Heal"):
		effect = "heal"
	var team := str(a.get("targetTeam", "Enemies"))
	var kind: String = KINDS.get(str(a.get("kind", "Active")), "active")
	var shape: String = SHAPES.get(str(a.get("targeting", "")), "")
	var self_only := shape == "self"
	var ab := {
		"name": str(a.get("name", "Ability")).substr(0, 30),
		"desc": ("ULTIMATE: " if ultimate else "") + str(a.get("description", "")),
		"effect": effect,
		"scale": "att" if str(a.get("damageType", "")) == "Physical" else "mag",
		"power": clampf(v.get("power", 0.0), 0.0, 400.0),
		"min_range": clampf(v.get("min_range", 0.0), 0.0, 20.0),
		"max_range": 0.0 if self_only else clampf(v.get("cast_range", 1.8), 0.0, 20.0),
		"aoe": clampf(v.get("radius", 0.0), 0.0, 8.0),
		"cooldown": clampi(roundi(v.get("cooldown_turns", v.get("cooldown", 0.0) / 10.0)), 0, 10),
		"cast": clampf(v.get("cast_time", 0.0), 0.0, 10.0),
		"target": "ko_ally" if effect == "revive" else ("enemy" if team == "Enemies" else "ally"),
		"kind": kind,
	}
	if shape != "":
		ab["shape"] = shape
	if shape == "cone":
		ab["angle"] = clampf(v.get("cone_angle", 60.0), 10.0, 180.0)
	if kind == "channeled":
		ab["channel"] = clampi(roundi(v.get("channel_turns", 2.0)), 1, 6)
	if effect == "revive":
		ab["power"] = clampf(ab.power, 0.05, 1.0)
	if v.has("tg_change"):
		ab["tg"] = clampi(roundi(v.tg_change), -100, 100)
	var buffs := []
	for key in v:
		if key.begins_with("buff_") and key != "buff_turns" and STAT_KEYS.has(key.substr(5)):
			buffs.append({"stat": key.substr(5), "amount": roundi(v[key]), "turns": clampi(roundi(v.get("buff_turns", 2.0)), 1, 5)})
	if not buffs.is_empty():
		ab["buffs"] = buffs
	# Timed status from the effects (the first one found wins).
	for e in effects:
		var status := ""
		match str(e.get("type", "")):
			"Slow": status = "slow"
			"Stun": status = "stun"
			"Shield": status = "shield"
			"Root": status = "root"
			"Silence": status = "silence"
			"Damage": status = "burn" if e.get("timing") == "Periodic" else ""
			"Heal": status = "regen" if e.get("timing") == "Periodic" else ""
		if status == "":
			continue
		var turns = _eval_in(a, str(e.get("duration", "0")), v)
		if turns is String:
			return {"error": "%s duration: %s" % [e.get("name", status), turns]}
		if turns >= 1.0:
			ab["status"] = {"id": status, "turns": clampi(roundi(turns), 1, 10)}
			break
	if a.tags.has("taunt") and not ab.has("status"):
		ab["status"] = {"id": "taunt", "turns": clampi(roundi(v.get("status_duration", 2.0)), 1, 10)}
	ab["fx"] = _fx(a, ab)
	return ab


## Which built-in animation to borrow.
static func _fx(a: Dictionary, ab: Dictionary) -> String:
	for tag in a.tags:
		if tag is String and tag.begins_with("fx:"):
			return tag.substr(3)
	match ab.effect:
		"revive":
			return "raise"
		"heal":
			return "sanctuary" if ab.aoe > 0.0 else "cure"
		"support":
			return "haste" if ab.max_range > 0.0 else "focus"
	if ab.scale == "att":
		return "attack" if ab.max_range <= 2.0 else ("arrow_rain" if ab.aoe > 0.0 else "bow_shot")
	return "blizzard" if ab.aoe > 0.0 else "fire"


# --- Astra's formulas (a port of model.mjs) ---------------------------------

## Every parameter of an Astra ability evaluated at rank 1, or {"error": ...}.
## The parameters of an ability, worked out at rank 1. Only the ones the game
## reads, plus any an effect's formula mentions, or {"error": ...}.
static func _values(a: Dictionary) -> Dictionary:
	var params: Array = a.get("parameters", []) if a.get("parameters") is Array else []
	var by_key := {}
	for p in params:
		if p is Dictionary and p.get("key") is String:
			by_key[p.key] = p
	# What the effects' formulas mention, so those parameters are worked out too.
	var formulas := ""
	for e in (a.get("effects", []) if a.get("effects") is Array else []):
		if e is Dictionary:
			formulas += "%s %s %s " % [e.get("amount", ""), e.get("duration", ""), e.get("tick", "")]
	var out := {}
	var cache := {}
	for key in by_key:
		# Only the parameters the game reads; a formula that mentions another
		# parameter still resolves it (see _resolve).
		if not _is_read(key) and not formulas.contains(key):
			continue
		var value = _resolve(key, by_key, cache, [])
		if value is String:
			return {"error": value}
		out[key] = value
	return out


## Whether the game reads this parameter itself.
static func _is_read(key: String) -> bool:
	return READ_KEYS.has(key) or key.begins_with("buff_") or STAT_KEYS.has(key)


static func _eval_in(a: Dictionary, expression: String, values: Dictionary):
	var vars := ASTRA_STATS.duplicate()
	vars.merge(values, true)
	vars.rank = 1.0
	vars.missingHealth = float(ASTRA_STATS.maxHealth - ASTRA_STATS.currentHealth)
	return evaluate(expression, vars)


## Resolves one parameter (following references, rejecting cycles). Returns
## a float, or an error message String.
static func _resolve(key: String, by_key: Dictionary, cache: Dictionary, active: Array):
	if cache.has(key):
		return cache[key]
	if active.has(key):
		return "Circular parameter reference: %s" % key
	active.append(key)
	var vars := ASTRA_STATS.duplicate()
	vars.rank = 1.0
	vars.missingHealth = float(ASTRA_STATS.maxHealth - ASTRA_STATS.currentHealth)
	# Referenced parameters are resolved first.
	var expression := rank_value(by_key[key], 1)
	for other in by_key:
		if other != key and expression.contains(other) and _pattern("\\b%s\\b" % other).search(expression):
			var v = _resolve(other, by_key, cache, active)
			if v is String:
				active.erase(key)
				return v
			vars[other] = v
	if by_key.has("cost") and not vars.has("manaCost") and expression.contains("manaCost"):
		var c = _resolve("cost", by_key, cache, active)
		if c is String:
			active.erase(key)
			return c
		vars.manaCost = c
	active.erase(key)
	var value = evaluate(expression, vars)
	if value is String:
		return "%s: %s" % [key, value]
	cache[key] = value
	return value


## A parameter's value (formula text) at a rank: an override, or generated
## from base / step / mode / every.
static func rank_value(p: Dictionary, rank: int) -> String:
	var overrides = p.get("overrides", {})
	if overrides is Dictionary and overrides.has(str(rank)):
		return str(overrides[str(rank)])
	return generated_value(p, rank)


static func generated_value(p: Dictionary, rank: int) -> String:
	var every := maxi(1, int(float(p.get("every", 1))))
	var steps := (rank - 1) / every
	var base_text := str(p.get("base", "0"))
	if not base_text.is_valid_float() or not str(p.get("step", "0")).is_valid_float():
		return base_text
	var base := float(base_text)
	var step := float(str(p.get("step", "0")))
	var v := base
	match str(p.get("mode", "")):
		"Flat increase", "Time increase": v = base + step * steps
		"Flat decrease", "Time decrease": v = base - step * steps
		"% increase": v = base * pow(1.0 + step / 100.0, steps)
		"% decrease": v = base * pow(1.0 - step / 100.0, steps)
	if p.get("floorZero", false):
		v = maxf(0.0, v)
	v = snappedf(v, 0.0001)
	return str(int(v)) if v == floorf(v) and absf(v) < 1e15 else str(v)  # like Astra: 12, not 12.0


## Evaluates an Astra formula: numbers, + - * /, parentheses, unary +/-,
## postfix % and variables. Returns a float, or an error message String.
static func evaluate(expression: String, variables: Dictionary):
	var input := expression.strip_edges()
	var re := _pattern("(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][+-]?\\d+)?|[a-zA-Z_][a-zA-Z_0-9]*|[()+\\-*/%]")
	var tokens: Array[String] = []
	for m in re.search_all(input):
		tokens.append(m.get_string())
	if tokens.is_empty() or "".join(tokens).to_lower() != input.replace(" ", "").replace("\t", "").to_lower():
		return "Use numbers, parameter keys, + - * /, and parentheses."
	if tokens.size() > 300:
		return "Expression is too long."
	var parser := _Parser.new(tokens, variables)
	var result := parser.sum()
	if parser.error == "" and parser.i != tokens.size():
		parser.error = "Invalid expression."
	if parser.error == "" and (is_nan(result) or is_inf(result)):
		parser.error = "Invalid expression or division by zero."
	return parser.error if parser.error != "" else result


class _Parser:
	var tokens: Array[String]
	var vars: Dictionary
	var i := 0
	var error := ""

	func _init(p_tokens: Array[String], p_vars: Dictionary) -> void:
		tokens = p_tokens
		vars = p_vars

	func _peek() -> String:
		return tokens[i] if i < tokens.size() else ""

	func atom() -> float:
		if error != "":
			return 0.0
		var t := _peek()
		i += 1
		var v := 0.0
		if t == "(":
			v = sum()
			if _peek() != ")":
				error = "Missing closing parenthesis."
				return 0.0
			i += 1
		elif t == "+" or t == "-":
			v = (-1.0 if t == "-" else 1.0) * atom()
		elif t != "" and (t[0] == "." or t[0].is_valid_int()):
			v = float(t)
		elif t != "" and vars.has(t):
			v = float(vars[t])
		else:
			error = "Unknown variable: %s" % (t if t != "" else "end of expression")
			return 0.0
		if _peek() == "%":
			i += 1
			v /= 100.0
		return v

	func product() -> float:
		var v := atom()
		while error == "" and (_peek() == "*" or _peek() == "/"):
			var op := _peek()
			i += 1
			var n := atom()
			v = v * n if op == "*" else (v / n if n != 0.0 else NAN)
		return v

	func sum() -> float:
		var v := product()
		while error == "" and (_peek() == "+" or _peek() == "-"):
			var op := _peek()
			i += 1
			var n := product()
			v = v + n if op == "+" else v - n
		return v


static func _slug(text: String) -> String:
	var s := _pattern("[^a-z0-9]+").sub(text.to_lower(), "_", true)
	return s.trim_prefix("_").trim_suffix("_")


static func _color(hex) -> Color:
	return Color.html(hex) if hex is String and Color.html_is_valid(hex) else Color(0.6, 0.5, 0.9)
