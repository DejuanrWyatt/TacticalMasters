extends RefCounted
## One unit on the battlefield.

const Jobs = preload("res://scripts/core/jobs.gd")

var id: int
var job: String
var team: int
## Position on the ground in meters (x, z). Always a navigation node center.
var pos: Vector2
var hp: int
## Turn Gauge: the unit becomes ready when this reaches GameState.TG_MAX.
var tg := 0
## Ready to act. Stays ready until it ends its turn or its countdown runs out.
var ready := false
## While ready: ticks left before the turn is lost.
var clock := 0
## Goes up by one every time the unit becomes ready. Orders carry it, so an
## order meant for an earlier turn is rejected.
var serial := 0
## Ultimate meter: ability 4 is usable when this reaches GameState.ULT_MAX.
var ult := 0
## Your turns left before each ability can be used again.
var cooldowns: Array[int] = [0, 0, 0, 0]
var moved := false
var acted := false
## While casting: {"slot", "name", "target": Vector2, "target_unit": id or -1,
## "ticks": ticks left, "total": ticks at the start}. Empty when not casting.
var casting := {}
## Active buffs: [{"stat": String, "amount": int, "turns": int}]
var buffs: Array[Dictionary] = []
## Timed status effects: [{"id": String (see Jobs.STATUSES), "ticks": ticks left}]
var statuses: Array[Dictionary] = []
## Set when a turn ended without an ability: the gauge fills faster until the
## next turn (cleared when it comes round).
var hustling := false
## Toggle abilities that are switched on (slot -> true).
var toggled := {}
## Toggle slots already switched this turn (one switch per turn each).
var toggled_turn := {}
## A channeled ability in progress: {"slot", "target", "turns"}.
var channeling := {}
## Direction the unit faces on the ground (unit vector). Hits from behind or
## the side deal extra damage.
var facing := Vector2(0, 1)
## While knocked out (hp 0): ticks left before the unit is gone for good.
## It can be revived until then.
var ko_ticks := 0
## How many of its own turns have begun since it last took damage. A unit left
## alone long enough starts mending itself (GameState._undamaged_regen).
var unharmed_turns := 0


func _init(p_id: int, p_job: String, p_team: int, p_pos: Vector2) -> void:
	id = p_id
	job = p_job
	team = p_team
	pos = p_pos
	hp = max_hp()


func job_data() -> Dictionary:
	return Jobs.job(job)


func job_name() -> String:
	return job_data().name


## A stat including buffs: timed ones, always-on abilities (passive and
## active + passive) and toggles that are switched on.
func stat(stat_name: String) -> int:
	var value: int = job_data()[stat_name]
	for b in buffs:
		if b.stat == stat_name:
			value += b.amount
	for slot in 4:
		var ab := ability(slot)
		var kind: String = ab.get("kind", "active")
		var on: bool = kind == "passive" or kind == "active_passive" or (kind == "toggle" and toggled.get(slot, false))
		if on and ab.has("buffs") and ab.get("target", "enemy") != "enemy":
			for b in ab.buffs:
				if b.stat == stat_name:
					value += b.amount
	return value


## Whether this ability is switched on now (toggles) or always on.
func is_on(slot: int) -> bool:
	var kind: String = ability(slot).get("kind", "active")
	if kind == "toggle":
		return toggled.get(slot, false)
	return kind == "passive" or kind == "active_passive" or kind == "aura"


func is_channeling() -> bool:
	return not channeling.is_empty()


func max_hp() -> int:
	return job_data().hp


func ability(slot: int) -> Dictionary:
	return Jobs.ability(job_data().abilities[slot])


## An independent copy (for the computer to think on another thread).
func copy():
	var c = get_script().new(id, job, team, pos)
	c.hp = hp
	c.tg = tg
	c.ready = ready
	c.clock = clock
	c.serial = serial
	c.ult = ult
	c.cooldowns = cooldowns.duplicate()
	c.moved = moved
	c.acted = acted
	c.hustling = hustling
	c.casting = casting.duplicate()
	c.buffs = buffs.duplicate(true)
	c.statuses = statuses.duplicate(true)
	c.toggled = toggled.duplicate()
	c.toggled_turn = toggled_turn.duplicate()
	c.channeling = channeling.duplicate(true)
	c.facing = facing
	c.ko_ticks = ko_ticks
	c.unharmed_turns = unharmed_turns
	return c


func is_casting() -> bool:
	return not casting.is_empty()


func is_alive() -> bool:
	return hp > 0


## Knocked out: down on the field and can still be revived.
func is_ko() -> bool:
	return hp <= 0 and ko_ticks > 0


func has_status(status_id: String) -> bool:
	for s in statuses:
		if s.id == status_id:
			return true
	return false


## Multiplier on Turn Gauge filling from statuses (slow, stun).
func tg_factor() -> float:
	var f := 1.0
	for s in statuses:
		f *= Jobs.STATUSES[s.id].get("tg_factor", 1.0)
	return f


## Whether this unit finished its last turn without using an ability, which
## fills its gauge faster until its next one (GameState.hustle_factor).
func is_hustling() -> bool:
	return hustling


## Can't walk (Root).
func is_rooted() -> bool:
	return _status_flag("no_move")


## Can't use abilities (Silence).
func is_silenced() -> bool:
	return _status_flag("no_abilities")


func _status_flag(flag: String) -> bool:
	for s in statuses:
		if Jobs.STATUSES[s.id].get(flag, false):
			return true
	return false


## The unit that taunted this one (it must attack that one), or -1.
func taunted_by() -> int:
	for s in statuses:
		if Jobs.STATUSES[s.id].get("taunt", false):
			return int(s.get("by", -1))
	return -1


## How much damage its Shield can still soak up.
func shield_left() -> int:
	var left := 0
	for s in statuses:
		if Jobs.STATUSES[s.id].get("absorbs", false):
			left += int(s.get("amount", 0))
	return left


## Whether a status stops this unit from taking orders at all (Sleep, Freeze).
func is_stunned() -> bool:
	return no_orders_status() != ""


## The status taking this unit's orders away, or "" if it can act.
func no_orders_status() -> String:
	for s in statuses:
		if Jobs.STATUSES[s.id].get("no_orders", false):
			return str(s.id)
	return ""
