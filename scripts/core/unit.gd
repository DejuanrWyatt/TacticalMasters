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


func _init(p_id: int, p_job: String, p_team: int, p_pos: Vector2) -> void:
	id = p_id
	job = p_job
	team = p_team
	pos = p_pos
	hp = max_hp()


func job_data() -> Dictionary:
	return Jobs.JOBS[job]


func job_name() -> String:
	return job_data().name


## A stat including active buffs.
func stat(stat_name: String) -> int:
	var value: int = job_data()[stat_name]
	for b in buffs:
		if b.stat == stat_name:
			value += b.amount
	return value


func max_hp() -> int:
	return job_data().hp


func ability(slot: int) -> Dictionary:
	return Jobs.ABILITIES[job_data().abilities[slot]]


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
	c.casting = casting.duplicate()
	c.buffs = buffs.duplicate(true)
	return c


func is_casting() -> bool:
	return not casting.is_empty()


func is_alive() -> bool:
	return hp > 0
