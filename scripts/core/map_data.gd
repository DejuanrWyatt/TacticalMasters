extends RefCounted
## Built-in maps. Each character is a 2 m x 2 m block of ground: digits are
## its height level (1-5) and "~" is water, which can't be walked on. Maps
## are point-symmetric: the bottom half is the top half rotated 180 degrees,
## so neither side gets better ground. Units can climb at most 2 levels at a
## time, so a level-5 block next to level-1 ground is a wall.

const Jobs = preload("res://scripts/core/jobs.gd")

const TILE_SIZE := 2.0
const DEFAULT_MAP := "highlands"

## Blue's usual starting positions in meters (navigation node centers).
## Red starts at the mirrored positions.
const WEST_SPAWNS := [Vector2(2.75, 4.75), Vector2(0.75, 8.75), Vector2(4.75, 6.75), Vector2(2.75, 10.75)]

## id -> {name, desc, top (the top half), spawns}
const MAPS := {
	"highlands": {
		"name": "Highlands",
		"desc": "Rolling hills with a high ridge on each flank. Take the high ground for bonus damage.",
		"top": [
			"112233211111",
			"112233211111",
			"111222111111",
			"111111111111",
			"122111121111",
			"123111121111",
		],
		"spawns": WEST_SPAWNS,
	},
	"river": {
		"name": "River Crossing",
		"desc": "A river splits the field. Two narrow bridges are the only way across: hold them.",
		"top": [
			"11111~~11111",
			"121111111121",
			"11111~~11111",
			"11211~~11211",
			"11111~~11111",
			"12211~~11221",
		],
		"spawns": [Vector2(2.75, 6.75), Vector2(0.75, 10.75), Vector2(4.75, 8.75), Vector2(2.75, 12.75)],
	},
	"fortress": {
		"name": "Fortress",
		"desc": "A raised plateau in the middle, reachable only by its ramps. Stone pillars block line of sight.",
		"top": [
			"111111111111",
			"115111111111",
			"111122221111",
			"111244442111",
			"111144441511",
			"111144441111",
		],
		"spawns": WEST_SPAWNS,
	},
	"plains": {
		"name": "Open Plains",
		"desc": "Flat, open ground with a few low hills. Nowhere to hide from archers.",
		"top": [
			"111111111111",
			"111112111111",
			"121111111121",
			"111111211111",
			"111211111111",
			"111111112111",
		],
		"spawns": WEST_SPAWNS,
	},
}


static func map_ids() -> Array:
	return MAPS.keys()


## Builds a map dictionary for GameState.setup():
## {"id", "name", "rows": Array[String], "units": [[job, team, Vector2], ...], "spawn_points": [blue, red]}
static func build(map_id: String, blue_roster: Array = Jobs.DEFAULT_ROSTER, red_roster: Array = Jobs.DEFAULT_ROSTER) -> Dictionary:
	var info: Dictionary = MAPS.get(map_id, MAPS[DEFAULT_MAP])
	var map := _symmetric(info.name, info.top, info.spawns, [blue_roster, red_roster])
	map.id = map_id if MAPS.has(map_id) else DEFAULT_MAP
	return map


static func highlands(blue_roster: Array = Jobs.DEFAULT_ROSTER, red_roster: Array = Jobs.DEFAULT_ROSTER) -> Dictionary:
	return build("highlands", blue_roster, red_roster)


## The full height rows of a map (top half plus its mirrored bottom half).
static func rows(map_id: String) -> Array:
	var top: Array = MAPS.get(map_id, MAPS[DEFAULT_MAP]).top
	var out: Array = top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		out.append((top[i] as String).reverse())
	return out


static func _symmetric(map_name: String, top: Array, spawns: Array, rosters: Array) -> Dictionary:
	var all_rows: Array = top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		all_rows.append((top[i] as String).reverse())
	var size := Vector2((all_rows[0] as String).length(), all_rows.size()) * TILE_SIZE
	var units := []
	for team in 2:
		for i in mini(rosters[team].size(), spawns.size()):
			var p: Vector2 = spawns[i]
			units.append([rosters[team][i], team, p if team == 0 else size - p])
	return {
		"name": map_name,
		"rows": all_rows,
		"units": units,
		"spawn_points": [spawns[0], size - spawns[0]],
	}
